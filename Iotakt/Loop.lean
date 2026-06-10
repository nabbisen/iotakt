import Iotakt.Driver
import Henret.Model

/-!
# Iotakt.Loop

A multi-connection event loop for v0.2 (RFC 023).

`EventLoop` wraps `NativeDriverState`, a Henret `RuntimeState`, and a
`PollerHandle` and exposes a single `runStep` function that:

1. Calls `epoll_wait` with a configurable blocking timeout.
2. Parses events, translates through the registry, coalesces, injects
   into Henret actor mailboxes.
3. Delivers a `LoopEvent` per ready connection so the caller can dispatch:
   - `.newConnection key fd` — an accepted connection
   - `.dataReady key`        — a registered stream has a readable event
   - `.tick now`             — a timeout expired

## Multi-connection pattern

```text
loop:
  (loop, events) ← EventLoop.runStep loop
  for ev in events:
    match ev with
    | .newConnection key fd =>
        register connection in app state
    | .dataReady key =>
        bytes ← Io.recv key.raw maxBytes
        handle(bytes)
    | .tick now =>
        cleanup idle connections
```

## Connection lifetime

The loop manages `FdKey` lifecycle automatically: `acceptConnections`
adds new keys, `closeConnection` deregisters from both epoll and the
registry. A closed key's events are dropped at the model boundary.
-/

namespace Iotakt.Loop

open Iotakt.Model Iotakt.Bridge Iotakt.Driver Iotakt.Native Henret

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

/-- An event delivered to the caller from one driver step. -/
inductive LoopEvent where
  /-- A new connection was accepted on the listener. -/
  | newConnection (key : FdKey) (rawFd : Int) : LoopEvent
  /-- A stream fd has a readiness event (readable, writable, eof, etc.). -/
  | dataReady (key : FdKey) (event : IoEvent) : LoopEvent
  /-- A timer tick (clock advanced). -/
  | tick (now : Nat) : LoopEvent

/-- An `EventLoop` holds all the state needed to drive iotakt connections.
Pass it between loop iterations; it is purely functional except for the
`PollerHandle` (which wraps the native epoll fd). -/
structure EventLoop where
  nds       : NativeDriverState
  rt        : RuntimeState
  ph        : PollerHandle
  listeners : List (FdKey × Int)   -- (key, raw fd) for each active listener
  /-- Maps each connection's FdKey to the Henret task id that owns it.
  Populated at spawn time; used by `closeConnection` to `cancel` the task
  and free its runtime state (Gap 006 cleanup, henret ≥ v0.11.0). -/
  taskByKey : List (FdKey × Nat) := []
  /-- Optional idle timeout in milliseconds. When set, connections with no
  activity for longer than this are reaped by `reapIdle` / `runStepAuto`
  (v0.7). -/
  idleTimeoutMs : Option Nat := none
  /-- Wall-clock (monotonic ns) of the last activity on each connection.
  Updated on accept and on each `dataReady`. Used for idle reaping. -/
  lastActivityNs : List (FdKey × Nat) := []
  /-- Optional cap on concurrent connections. When set, accepts past the cap
  are shed (closed immediately) rather than registered — a resource-exhaustion
  control (RFC 030, v0.11). -/
  maxConnections : Option Nat := none

namespace EventLoop

/-- Record the Henret task id that owns a connection key. -/
def recordTask (loop : EventLoop) (key : FdKey) (task : Nat) : EventLoop :=
  { loop with taskByKey := (key, task) :: loop.taskByKey }

/-- Look up the Henret task id owning a connection key. -/
def taskOf (loop : EventLoop) (key : FdKey) : Option Nat :=
  loop.taskByKey.find? (·.1 == key) |>.map (·.2)

/-- Forget a connection's task mapping. -/
def forgetTask (loop : EventLoop) (key : FdKey) : EventLoop :=
  { loop with taskByKey := loop.taskByKey.filter (·.1 != key) }

/-- Number of currently-tracked connections (each accepted/connected stream
records a task; `closeConnection` removes it). -/
def connectionCount (loop : EventLoop) : Nat := loop.taskByKey.length

/-- Configure a maximum number of concurrent connections (RFC 030). -/
def withMaxConnections (loop : EventLoop) (n : Nat) : EventLoop :=
  { loop with maxConnections := some n }

/-- True when the connection cap is configured and reached. -/
def atCapacity (loop : EventLoop) : Bool :=
  match loop.maxConnections with
  | none   => false
  | some n => loop.connectionCount >= n

/-- Configure an idle timeout (milliseconds). Connections idle longer than
this are closed by `reapIdle` / `runStepAuto`. -/
def withIdleTimeout (loop : EventLoop) (ms : Nat) : EventLoop :=
  { loop with idleTimeoutMs := some ms }

/-- Record activity on a connection at wall-clock time `nowNs` (monotonic ns).
Replaces any previous entry for the key. -/
def touchConn (loop : EventLoop) (key : FdKey) (nowNs : Nat) : EventLoop :=
  { loop with
    lastActivityNs := (key, nowNs) :: loop.lastActivityNs.filter (·.1 != key) }

/-- Drop a connection's activity record. -/
def forgetActivity (loop : EventLoop) (key : FdKey) : EventLoop :=
  { loop with lastActivityNs := loop.lastActivityNs.filter (·.1 != key) }

/-- Compute the epoll poll timeout in milliseconds for the next `runStepAuto`.

Returns `-1` (block indefinitely) when there is nothing time-sensitive
pending — an idle server then uses zero CPU instead of spinning on a fixed
heartbeat. When an idle timeout is configured and connections are active,
returns the milliseconds until the soonest idle deadline (clamped to ≥ 0).

This is iotakt's wall-clock park/wake: the driver blocks exactly as long as
the nearest deadline allows. Henret *logical* timers (from `sleep` /
`receiveUntil`) are a separate clock; see docs/src/henret-integration.md for
why iotakt's connection actors do not yet populate them. -/
def pollTimeoutMs (loop : EventLoop) (nowNs : Nat) : Int :=
  match loop.idleTimeoutMs with
  | none => -1
  | some ms =>
      if loop.lastActivityNs.isEmpty then -1
      else
        let idleNs := ms * 1000000
        -- soonest deadline = min over connections of (lastActivity + idleNs)
        let deadlines := loop.lastActivityNs.map (fun (_, t) => t + idleNs)
        let soonest := deadlines.foldl Nat.min (deadlines.headD (nowNs + idleNs))
        if soonest <= nowNs then 0
        else Int.ofNat ((soonest - nowNs) / 1000000)

/-- Connections whose idle deadline has passed at wall-clock `nowNs`. -/
def idleExpired (loop : EventLoop) (nowNs : Nat) : List FdKey :=
  match loop.idleTimeoutMs with
  | none => []
  | some ms =>
      let idleNs := ms * 1000000
      loop.lastActivityNs.filterMap fun (key, t) =>
        if t + idleNs <= nowNs then some key else none

/-- Create a new event loop with a fresh epoll instance.
Returns `none` if epoll creation fails. -/
def create (config : DriverConfig := {}) : IO (Option EventLoop) := do
  let epfd ← Epoll.create
  if epfd < 0 then return none
  let ds : DriverState := {
    registry := Registry.empty,
    coalesce := CoalesceState.empty,
    clock    := 0,
    config   := config
  }
  return some {
    nds       := { ds := ds }
    rt        := RuntimeState.init
    ph        := { epfd := epfd }
    listeners := []
  }

/-- Close the epoll handle and free all resources. -/
def destroy (loop : EventLoop) : IO Unit := do
  -- Close all tracked listener fds
  for (_, lfd) in loop.listeners do
    Socket.closeFdRaw (fd32 lfd)
  Epoll.close (fd32 loop.ph.epfd)

/-- Add a TCP listener on the given port (bound to 127.0.0.1).
The listener actor ID is allocated from the next available slot. -/
def addListener (loop : EventLoop) (port : UInt16) : IO (EventLoop × Bool) := do
  let (nds1, rt1, setupR) ← setupListener loop.nds loop.rt loop.ph port loop.nds.nextActorId
  -- Consume the actorId by incrementing
  let (nds2, _) := nds1.freshActorId
  match setupR with
  | .fail _ => return (loop, false)
  | .ok key lfd =>
      return ({ loop with
        nds       := nds2
        rt        := rt1
        listeners := (key, lfd) :: loop.listeners }, true)

/-- Run one driver step: poll for events, accept new connections, deliver
readiness messages. Returns the updated loop and the list of events that
occurred this step. `timeoutMs = -1` blocks indefinitely. -/
def runStep (loop : EventLoop) (timeoutMs : Int := -1) :
    IO (EventLoop × List LoopEvent) := do
  let cfg := loop.nds.ds.config

  -- ── 1. Poll for I/O events ──────────────────────────────────────────
  let maxEv := (min cfg.maxEventsPerPoll 1024).toInt32
  let (waitStatus, evtBytes) ← Epoll.wait (fd32 loop.ph.epfd) maxEv timeoutMs.toInt32

  -- ── 2. Process readiness events through the bridge ──────────────────
  let mut nds := loop.nds
  let mut rt  := loop.rt
  let mut loopEvents : List LoopEvent := []

  if waitStatus > 0 then do
    let rawEvts := Epoll.parseEvents evtBytes
    let (ds1, rt1, _) := processEvents nds.ds rt rawEvts
    nds := { nds with ds := ds1 }; rt := rt1
    -- Collect dataReady events for streams (not listeners)
    for ev in rawEvts do
      match nds.ds.registry.resolveCurrent ev.rawFd with
      | none => pure ()
      | some key =>
          match nds.ds.registry.lookup key with
          | none => pure ()
          | some entry =>
              match entry.kind with
              | .stream   => loopEvents := loopEvents ++ [.dataReady key ev.event]
              | .listener  => pure ()  -- handle via acceptConnections below
              | .datagram  => loopEvents := loopEvents ++ [.dataReady key ev.event]
  else if waitStatus == 0 then do
    -- Timeout: advance clock
    let now := nds.ds.clock + 1
    let rt1  := (Henret.step rt (.tick now)).1
    nds := { nds with ds := { nds.ds with clock := now } }
    rt  := rt1
    loopEvents := [.tick now]

  -- ── 3. Accept new connections from all listeners ────────────────────
  let mut newConns : List LoopEvent := []
  let mut newTasks : List (FdKey × Nat) := []
  -- Track the running connection count so the cap is enforced across this
  -- step's accept burst, not just against the count at step entry.
  let mut liveCount := loop.connectionCount
  for (_, lfd) in loop.listeners do
    let (nds1, rt1, accepted) ← acceptBurst nds rt loop.ph lfd
    nds := nds1; rt := rt1
    for (key, rawFd, task) in accepted do
      let overCap := match loop.maxConnections with
        | none   => false
        | some m => liveCount >= m
      if overCap then
        -- Load-shed: deregister, close the fd, cancel its task, drop the
        -- registry entry. The connection is never surfaced to the caller.
        let _ ← Epoll.deregister (fd32 loop.ph.epfd) (fd32 key.raw)
        Socket.closeFdRaw (fd32 key.raw)
        nds := { nds with ds := { nds.ds with registry := nds.ds.registry.close key } }
        rt  := (Henret.step rt (.cancel task)).1
      else
        newConns := newConns ++ [.newConnection key rawFd]
        newTasks := (key, task) :: newTasks
        liveCount := liveCount + 1

  let loopOut := { loop with
    nds       := nds
    rt        := rt
    taskByKey := newTasks ++ loop.taskByKey }
  return (loopOut, newConns ++ loopEvents)

/-- Register write interest for a connection (call when you have pending
output; disable when the output buffer is drained). -/
def enableWrite (loop : EventLoop) (key : FdKey) : IO EventLoop := do
  let newInterests := InterestSet.readOnly.enableWrite
  let reg1 := loop.nds.ds.registry.setInterests key newInterests
  let _ ← Epoll.modify (fd32 loop.ph.epfd) (fd32 key.raw)
            (Epoll.interestFlags newInterests)
  return { loop with nds := { loop.nds with ds := { loop.nds.ds with registry := reg1 } } }

/-- Disable write interest for a connection (output buffer drained). -/
def disableWrite (loop : EventLoop) (key : FdKey) : IO EventLoop := do
  let newInterests := InterestSet.readOnly
  let reg1 := loop.nds.ds.registry.setInterests key newInterests
  let _ ← Epoll.modify (fd32 loop.ph.epfd) (fd32 key.raw)
            (Epoll.interestFlags newInterests)
  return { loop with nds := { loop.nds with ds := { loop.nds.ds with registry := reg1 } } }

/-- Close and deregister a connection fd. Must be called when the
connection closes or the actor is done. -/
def closeConnection (loop : EventLoop) (key : FdKey) : IO EventLoop := do
  let _ ← Epoll.deregister (fd32 loop.ph.epfd) (fd32 key.raw)
  Socket.closeFdRaw (fd32 key.raw)
  let reg1 := loop.nds.ds.registry.close key
  -- Gap 006 (henret ≥ v0.11.0): cancel the owning task to free its
  -- runtime state (readyQ / timers / mailboxWaiters entries). The actor
  -- mailbox itself persists in Henret — that is upstream behaviour and is
  -- documented in docs/src/henret-integration.md.
  let rt1 := match loop.taskOf key with
    | some task => (Henret.step loop.rt (.cancel task)).1
    | none      => loop.rt
  return (loop.forgetTask key)
    |> fun l => l.forgetActivity key
    |> fun l => { l with
        nds := { l.nds with ds := { l.nds.ds with registry := reg1 } }
        rt  := rt1 }

/-- Close every connection idle past the configured timeout at wall-clock
`nowNs`. Returns the updated loop and the closed keys (v0.7). -/
def reapIdle (loop : EventLoop) (nowNs : Nat) : IO (EventLoop × List FdKey) := do
  let expired := loop.idleExpired nowNs
  let mut l := loop
  for key in expired do
    l ← l.closeConnection key
  return (l, expired)

/-- One adaptive step: block in `epoll_wait` only as long as the next
deadline allows (or indefinitely if nothing is pending), process events,
touch active connections, then reap any that have gone idle (v0.7).

This is the park/wake driver: an idle server with no I/O and no idle
timeout blocks forever (zero CPU); a server with idle timeouts wakes just
in time to reap expired connections. -/
def runStepAuto (loop : EventLoop) : IO (EventLoop × List LoopEvent) := do
  let nowNs := (← Io.monoNs).toNat
  let timeout := loop.pollTimeoutMs nowNs
  let (loop1, events) ← loop.runStep timeout
  -- Touch every connection that saw activity this step
  let nowNs2 := (← Io.monoNs).toNat
  let mut l := loop1
  for ev in events do
    match ev with
    | .newConnection key _ => l := l.touchConn key nowNs2
    | .dataReady key _     => l := l.touchConn key nowNs2
    | .tick _              => pure ()
  -- Reap idle connections
  let (l2, reaped) ← l.reapIdle nowNs2
  -- Surface reaped connections as a synthetic close-ish signal is not needed;
  -- the caller learns about them via the returned loop's state.
  let _ := reaped
  return (l2, events)

/-- Graceful shutdown (RFC 037): stop accepting and drain cleanly.

1. Deregister and close every listener fd (stop accepting new connections).
2. Close every active stream connection (deregister from epoll, close the fd,
   cancel its Henret task — the same path as `closeConnection`).
3. Leave the poller open for `destroy` to finalize.

Returns the drained loop. The caller should call `destroy` afterwards to
close the poller handle. This is the clean lifecycle end that replaces the
bounded-iteration loop the examples use for testability. -/
def shutdown (loop : EventLoop) : IO EventLoop := do
  -- 1. Stop accepting: deregister + close listeners.
  for (_, lfd) in loop.listeners do
    let _ ← Epoll.deregister (fd32 loop.ph.epfd) (fd32 lfd)
    Socket.closeFdRaw (fd32 lfd)
  -- 2. Drain active stream connections.
  let mut l := { loop with listeners := [] }
  let activeKeys := loop.taskByKey.map (·.1)
  for key in activeKeys do
    l ← l.closeConnection key
  return l

/-- Acknowledge that a connection's readiness has been handled.
Must be called after processing each `dataReady` event to allow
the coalescing layer to deliver the next readiness for this key. -/
def ackReady (loop : EventLoop) (key : FdKey) (ev : IoEvent) : EventLoop :=
  let pk : Iotakt.Model.PendingKey :=
    { fd := key, kind := ev.pendingKind }
  let cs1 := loop.nds.ds.coalesce.ack pk
  { loop with nds := { loop.nds with ds := { loop.nds.ds with coalesce := cs1 } } }

/-- Result of initiating an outbound connect. -/
inductive ConnectOutcome where
  /-- Connection initiated; `key` is the fd key to watch for `.dataReady writable`.
      When writable arrives, call `Socket.checkConnect key.raw` to confirm. -/
  | inProgress (key : FdKey) : ConnectOutcome
  /-- Connection succeeded immediately (rare). -/
  | connected (key : FdKey) : ConnectOutcome
  /-- Connection failed. -/
  | failed (msg : String) : ConnectOutcome

/-- Initiate a non-blocking outbound TCP connect to `addr:port` (RFC 039).
`addr` is host-byte-order IPv4 (e.g. `0x7f000001` = 127.0.0.1).
The caller should watch for a `.dataReady key .writable` event, then
call `Socket.checkConnect key.raw` to confirm the connection. -/
def connectTo (loop : EventLoop) (addr : UInt32) (port : UInt16) :
    IO (EventLoop × ConnectOutcome) := do
  let fd_r ← Socket.socketTcpRaw 1  -- AF_INET
  if fd_r < 0 then return (loop, .failed s!"socket() failed errno={-fd_r}")

  let r ← Socket.connectIPv4 fd_r addr port
  match r with
  | .error e =>
      Socket.closeFdRaw (fd32 fd_r)
      return (loop, .failed s!"connect() failed: {repr e}")
  | .connected =>
      -- Connected immediately; allocate key with read+write interest
      let (nds1, actorId) := loop.nds.freshActorId
      let (reg1, key) := nds1.ds.registry.allocate fd_r actorId .stream
      let reg2 := reg1.setInterests key (InterestSet.readOnly.enableWrite)
                    |>.markActive key
      let (rt1, spawnRes) := Henret.step loop.rt (.spawn actorId)
      let _ ← Epoll.register (fd32 loop.ph.epfd) (fd32 fd_r)
                (Epoll.interestFlags (InterestSet.readOnly.enableWrite))
      let loop1 := { loop with
        nds := { nds1 with ds := { nds1.ds with registry := reg2 } }
        rt  := rt1 }
      let loop2 := match spawnRes with
        | .spawned task => loop1.recordTask key task
        | _             => loop1
      return (loop2, .connected key)
  | .inProgress =>
      -- Register for write interest; writable event confirms connection
      let (nds1, actorId) := loop.nds.freshActorId
      let (reg1, key) := nds1.ds.registry.allocate fd_r actorId .stream
      let reg2 := reg1.setInterests key (InterestSet.readOnly.enableWrite)
                    |>.markActive key
      let (rt1, spawnRes) := Henret.step loop.rt (.spawn actorId)
      let _ ← Epoll.register (fd32 loop.ph.epfd) (fd32 fd_r)
                (Epoll.interestFlags (InterestSet.readOnly.enableWrite))
      let loop1 := { loop with
        nds := { nds1 with ds := { nds1.ds with registry := reg2 } }
        rt  := rt1 }
      let loop2 := match spawnRes with
        | .spawned task => loop1.recordTask key task
        | _             => loop1
      return (loop2, .inProgress key)

end EventLoop

end Iotakt.Loop
