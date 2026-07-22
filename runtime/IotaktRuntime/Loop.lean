import IotaktRuntime.Driver
import Henret.Model

/-!
# IotaktRuntime.Loop

A multi-connection event loop for v0.2 (RFC 023).

`EventLoop` wraps `NativeDriverState`, a Henret `RuntimeState`, and a
`PollerHandle` and exposes a single `runStep` function that:

1. Calls `epoll_wait` with a configurable blocking timeout.
2. Parses events, translates through the registry, and coalesces them into
   the authoritative returned-event stream.
3. Delivers a `LoopEvent` per ready connection so the caller can dispatch:
   - `.newConnection listener connection` — an attributed accepted connection
   - `.dataReady key`        — a registered stream has a readable event
   - `.tick now`             — a timeout expired

## Multi-connection pattern

```text
loop:
  match ← EventLoop.runStep loop with
  | .error (.waitFailed errno) => apply fatal-backend policy
  | .ok (loop, events) =>
      for ev in events:
        match ev with
        | .newConnection listener connection =>
            register connection in app state
        | .dataReady key =>
            bytes ← Unsafe.Io.recv key.raw maxBytes
            handle(bytes)
        | .tick now =>
            cleanup idle connections
```

## Connection lifetime

The loop manages `FdKey` lifecycle automatically: `acceptConnections`
adds new keys, `closeConnection` deregisters from both epoll and the
registry. A closed key's events are dropped at the model boundary.
-/

namespace IotaktRuntime.Loop

open Iotakt.Model IotaktRuntime.Bridge IotaktRuntime.Driver IotaktRuntime.Listener
  IotaktRuntime.Native Henret

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

/-- Typed failure for stable operations that can cause a native fd effect. -/
inductive EffectError where
  | invalidKey
  | staleKey
  | invalidRawFd
  | wrongKind
  | inactive
  | invalidSlice
  | nativeLengthLimit
  | limitExceeded
  | nativeError (errno : IoErrno)
  deriving DecidableEq, Repr, Inhabited

/-- Fatal failure of the public event-loop step. Timeout/no-readiness is not an
error and continues to return a normal `.tick` result. -/
inductive LoopError where
  | waitFailed (errno : IoErrno)
  deriving DecidableEq, Repr, Inhabited

namespace LoopError

/-- Explicit exception adapter for legacy examples whose outer API predates the
typed public loop result. Stable consumers should handle `Except` directly. -/
def orThrow {α : Type} : Except LoopError α → IO α
  | .ok value => pure value
  | .error e => throw <| IO.userError s!"iotakt event loop failed: {repr e}"

end LoopError

/-- Injectable native wait boundary for deterministic fatal-wait testing. -/
structure WaitOps where
  wait : Int32 → Int32 → Int32 → IO (Int × ByteArray)

/-- Production epoll wait boundary. -/
def unsafeNativeWaitOps : WaitOps where
  wait := Unsafe.Epoll.wait

namespace EffectError

/-- Explicitly lift a checked effect result into `IO` for examples and internal
drivers whose own API still uses exceptions. Stable fd operations return the
`Except` value directly. -/
def orThrow {α : Type} : Except EffectError α → IO α
  | .ok value => pure value
  | .error e => throw <| IO.userError s!"iotakt fd effect failed: {repr e}"

end EffectError

private def ofKeyError : Iotakt.Model.KeyError → EffectError
  | .invalidRawFd => .invalidRawFd
  | .unknownKey => .invalidKey
  | .staleKey => .staleKey
  | .wrongKind => .wrongKind
  | .inactive => .inactive

/-- Convert a validated POSIX fd to the native ABI representation without
`Int.toNat` truncation or signed wrap. -/
private def checkedFd32 (raw : Int) : Except EffectError Int32 :=
  if raw < 0 || raw > 2147483647 then
    .error .invalidRawFd
  else
    .ok (Int32.mk raw.toNat.toUInt32)

private def nativeStatus (status : Int) : Except EffectError Unit :=
  if status < 0 then .error (.nativeError (classifyErrno (-status))) else .ok ()

/-- An event delivered to the caller from one driver step. -/
inductive LoopEvent where
  /-- A new connection and the generation-safe listener that accepted it. -/
  | newConnection (listener : ListenerKey) (connection : FdKey) : LoopEvent
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
  /-- Exactly one readiness sink is authoritative for this loop. -/
  deliveryMode : DeliveryMode := .returned
  /-- Active listener identity, native fd, and endpoint as one lifecycle record. -/
  listeners : List ListenerRecord
  /-- Active connection authority, independent of an optional mailbox task. -/
  connections : List FdKey := []
  /-- Mailbox-mode connection task ownership. Empty in returned mode; used by
  `closeConnection` to cancel explicitly selected mailbox actors. -/
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

/-- Look up the consolidated record for an active listener key. -/
def listener? (loop : EventLoop) (key : ListenerKey) : Option ListenerRecord :=
  loop.listeners.find? (·.key == key)

/-- Resolve model authority and native fd representation before an effect. -/
private def resolveEffect (loop : EventLoop) (key : FdKey)
    (allowedKinds : List ResourceKind) : Except EffectError (RegistryEntry × Int32) := do
  let nativeFd ← checkedFd32 key.raw
  let entry ← (loop.nds.ds.registry.resolveEffectKey key allowedKinds).mapError ofKeyError
  return (entry, nativeFd)

/-! ### Internal connection and optional task tracking

Connection authority is tracked independently of Henret. Mailbox mode additionally
records a connection→task mapping for cancel-on-close (Gap 006). These helpers are
internal and remain non-`private` only for integration tests. Consumers should use
`closeConnection` / `connectionCount` / `unsafeShutdown`, not these. -/

/-- (Internal) Record the Henret task id that owns a connection key. -/
def recordTask (loop : EventLoop) (key : FdKey) (task : Nat) : EventLoop :=
  { loop with
    connections := key :: loop.connections.filter (· != key)
    taskByKey := (key, task) :: loop.taskByKey.filter (·.1 != key) }

/-- (Internal) Record returned-mode connection authority without a task/mailbox. -/
def recordConnection (loop : EventLoop) (key : FdKey) : EventLoop :=
  { loop with connections := key :: loop.connections.filter (· != key) }

/-- (Internal) Look up the Henret task id owning a connection key. -/
def taskOf (loop : EventLoop) (key : FdKey) : Option Nat :=
  loop.taskByKey.find? (·.1 == key) |>.map (·.2)

/-- (Internal) Forget connection authority and any mailbox task mapping. -/
def forgetTask (loop : EventLoop) (key : FdKey) : EventLoop :=
  { loop with
    connections := loop.connections.filter (· != key)
    taskByKey := loop.taskByKey.filter (·.1 != key) }

/-- Number of currently-tracked connections. Returned mode does not require a
Henret task/mailbox for this bookkeeping. -/
def connectionCount (loop : EventLoop) : Nat := loop.connections.length

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

/-- Create a new event loop with an explicitly selected authoritative sink. -/
def unsafeCreateWithMode (mode : DeliveryMode) (config : DriverConfig := {}) :
    IO (Option EventLoop) := do
  let epfd ← Unsafe.Epoll.create
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
    deliveryMode := mode
    listeners := []
  }

/-- Create the stable external-consumer loop. Returned events are authoritative
and accepted connections do not allocate Henret tasks/mailboxes. -/
def create (config : DriverConfig := {}) : IO (Option EventLoop) :=
  unsafeCreateWithMode .returned config

/-- Create the explicitly selected legacy/internal mailbox-authority loop. -/
def unsafeCreateMailbox (config : DriverConfig := {}) : IO (Option EventLoop) :=
  unsafeCreateWithMode .mailbox config

/-- Close the epoll handle and free all resources. -/
def unsafeDestroy (loop : EventLoop) : IO Unit := do
  -- Close all tracked listener fds
  for listener in loop.listeners do
    Unsafe.Socket.closeFdRaw (fd32 listener.key.raw)
  Unsafe.Epoll.close (fd32 loop.ph.epfd)

/-- Add an address-aware IPv4 listener and return its generation-safe identity. -/
def addListenerAt (loop : EventLoop) (endpoint : BindEndpoint) :
    IO (Except ListenerError (EventLoop × ListenerKey)) := do
  if endpoint.port == 0 then return .error .invalidEndpoint
  if loop.listeners.any (fun listener => listener.endpoint == endpoint) then
    return .error .duplicateEndpoint
  match ← unsafeSetupListenerAt loop.nds loop.rt loop.ph endpoint loop.nds.nextActorId with
  | .error e => return .error e
  | .ok (nds, rt, key, _lfd) =>
      let (nds, _) := nds.freshActorId
      return .ok ({ loop with
        nds
        rt
        listeners := { key, endpoint } :: loop.listeners }, key)

/-- Compatibility wrapper: add a loopback listener and report success as `Bool`.
New consumers use `addListenerAt` and retain the returned `ListenerKey`. -/
def addListener (loop : EventLoop) (port : UInt16) : IO (EventLoop × Bool) := do
  match ← loop.addListenerAt (.loopback port) with
  | .error _ => return (loop, false)
  | .ok (loop, _) => return (loop, true)

/-- Run one driver step through an explicit wait boundary. A fatal wait returns
before readiness processing or accept work and preserves the input loop. -/
def unsafeRunStepWith (ops : WaitOps) (loop : EventLoop) (timeoutMs : Int := -1) :
    IO (Except LoopError (EventLoop × List LoopEvent)) := do
  let cfg := loop.nds.ds.config

  -- ── 1. Poll for I/O events ──────────────────────────────────────────
  let maxEv := (min cfg.maxEventsPerPoll 1024).toInt32
  let (waitStatus, evtBytes) ← ops.wait (fd32 loop.ph.epfd) maxEv timeoutMs.toInt32
  if waitStatus < 0 then
    return .error (.waitFailed (classifyErrno (-waitStatus)))

  -- ── 2. Process readiness events through the bridge ──────────────────
  let mut nds := loop.nds
  let mut rt  := loop.rt
  let mut loopEvents : List LoopEvent := []

  if waitStatus > 0 then do
    let rawEvts := Unsafe.Epoll.parseEvents evtBytes
    -- Listener readiness drives accept below and never occupies a connection
    -- coalescing slot or mailbox entry.
    let connectionEvts := rawEvts.filter fun raw =>
      match nds.ds.registry.resolveCurrent raw.rawFd with
      | some key => match nds.ds.registry.lookup key with
        | some entry => entry.kind != .listener
        | none => true
      | none => true
    match loop.deliveryMode with
    | .returned =>
        let (ds1, delivered, _) := processEventsReturned nds.ds connectionEvts
        nds := { nds with ds := ds1 }
        -- The bridge result is authoritative. Never replay raw epoll events.
        for ev in delivered do
          match nds.ds.registry.lookup ev.key with
          | none => pure ()
          | some entry =>
              match entry.kind with
              | .stream   => loopEvents := loopEvents ++ [.dataReady ev.key ev.event]
              | .listener => pure ()
              | .datagram => loopEvents := loopEvents ++ [.dataReady ev.key ev.event]
    | .mailbox =>
        let (ds1, rt1, _) := processEvents nds.ds rt connectionEvts
        nds := { nds with ds := ds1 }
        rt := rt1
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
  let mut newKeys : List FdKey := []
  -- Track the running connection count so the cap is enforced across this
  -- step's accept burst, not just against the count at step entry.
  let mut liveCount := loop.connectionCount
  for listener in loop.listeners do
    let (nds1, rt1, accepted) ←
      unsafeAcceptBurst nds rt loop.ph listener.key.raw loop.deliveryMode
    nds := nds1; rt := rt1
    for (key, _, task) in accepted do
      let overCap := match loop.maxConnections with
        | none   => false
        | some m => liveCount >= m
      if overCap then
        -- Load-shed: deregister, close the fd, cancel its task, drop the
        -- registry entry. The connection is never surfaced to the caller.
        let _ ← Unsafe.Epoll.deregister (fd32 loop.ph.epfd) (fd32 key.raw)
        Unsafe.Socket.closeFdRaw (fd32 key.raw)
        nds := { nds with ds := { nds.ds with registry := nds.ds.registry.close key } }
        match task with
        | some task => rt := (Henret.step rt (.cancel task)).1
        | none => pure ()
      else
        newConns := newConns ++ [.newConnection listener.key key]
        newKeys := key :: newKeys
        match task with
        | some task => newTasks := (key, task) :: newTasks
        | none => pure ()
        liveCount := liveCount + 1

  let loopOut := { loop with
    nds       := nds
    rt        := rt
    connections := newKeys ++ loop.connections
    taskByKey := newTasks ++ loop.taskByKey }
  return .ok (loopOut, newConns ++ loopEvents)

/-- Run one public driver step. Fatal backend failures are typed and cannot be
confused with timeout/no-readiness. `timeoutMs = -1` blocks indefinitely. -/
def runStep (loop : EventLoop) (timeoutMs : Int := -1) :
    IO (Except LoopError (EventLoop × List LoopEvent)) :=
  unsafeRunStepWith unsafeNativeWaitOps loop timeoutMs

/-- Register write interest for a connection (call when you have pending
output; disable when the output buffer is drained). -/
def enableWrite (loop : EventLoop) (key : FdKey) : IO (Except EffectError EventLoop) := do
  match loop.resolveEffect key [.stream, .datagram] with
  | .error e => return .error e
  | .ok (_, nativeFd) =>
      let newInterests := InterestSet.readOnly.enableWrite
      let status ← Unsafe.Epoll.modify (fd32 loop.ph.epfd) nativeFd (Unsafe.Epoll.interestFlags newInterests)
      match nativeStatus status with
      | .error e => return .error e
      | .ok () =>
          let reg1 := loop.nds.ds.registry.setInterests key newInterests
          return .ok { loop with
            nds := { loop.nds with ds := { loop.nds.ds with registry := reg1 } } }

/-- Disable write interest for a connection (output buffer drained). -/
def disableWrite (loop : EventLoop) (key : FdKey) : IO (Except EffectError EventLoop) := do
  match loop.resolveEffect key [.stream, .datagram] with
  | .error e => return .error e
  | .ok (_, nativeFd) =>
      let newInterests := InterestSet.readOnly
      let status ← Unsafe.Epoll.modify (fd32 loop.ph.epfd) nativeFd (Unsafe.Epoll.interestFlags newInterests)
      match nativeStatus status with
      | .error e => return .error e
      | .ok () =>
          let reg1 := loop.nds.ds.registry.setInterests key newInterests
          return .ok { loop with
            nds := { loop.nds with ds := { loop.nds.ds with registry := reg1 } } }

/-- Close and deregister a connection fd. Must be called when the
connection closes or the actor is done. -/
def closeConnection (loop : EventLoop) (key : FdKey) :
    IO (Except EffectError EventLoop) := do
  match loop.resolveEffect key [.stream, .datagram] with
  | .error e => return .error e
  | .ok (_, nativeFd) =>
      let status ← Unsafe.Epoll.deregister (fd32 loop.ph.epfd) nativeFd
      match nativeStatus status with
      | .error e => return .error e
      | .ok () =>
          Unsafe.Socket.closeFdRaw nativeFd
          let reg1 := loop.nds.ds.registry.close key
          -- Gap 006 (henret ≥ v0.11.0): cancel the owning task to free its
          -- runtime state (readyQ / timers / mailboxWaiters entries). The actor
          -- mailbox itself persists in Henret — that is upstream behaviour and is
          -- documented in docs/src/henret-integration.md.
          let rt1 := match loop.taskOf key with
            | some task => (Henret.step loop.rt (.cancel task)).1
            | none      => loop.rt
          return .ok <| (loop.forgetTask key)
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
    l ← EffectError.orThrow (← l.closeConnection key)
  return (l, expired)

/-- One adaptive step: block in `epoll_wait` only as long as the next
deadline allows (or indefinitely if nothing is pending), process events,
touch active connections, then reap any that have gone idle (v0.7).

This is the park/wake driver: an idle server with no I/O and no idle
timeout blocks forever (zero CPU); a server with idle timeouts wakes just
in time to reap expired connections. -/
def runStepAuto (loop : EventLoop) :
    IO (Except LoopError (EventLoop × List LoopEvent)) := do
  let nowNs := (← Unsafe.Io.monoNs).toNat
  let timeout := loop.pollTimeoutMs nowNs
  match ← loop.runStep timeout with
  | .error e => return .error e
  | .ok (loop1, events) =>
      -- Touch every connection that saw activity this step
      let nowNs2 := (← Unsafe.Io.monoNs).toNat
      let mut l := loop1
      for ev in events do
        match ev with
        | .newConnection _ connection => l := l.touchConn connection nowNs2
        | .dataReady key _     => l := l.touchConn key nowNs2
        | .tick _              => pure ()
      -- Reap idle connections
      let (l2, reaped) ← l.reapIdle nowNs2
      -- Surface reaped connections as a synthetic close-ish signal is not needed;
      -- the caller learns about them via the returned loop's state.
      let _ := reaped
      return .ok (l2, events)

/-- Explicitly unsafe graceful-shutdown helper (RFC 037): stop accepting and drain
cleanly.

1. Deregister and close every listener fd (stop accepting new connections).
2. Close every active stream connection (deregister from epoll, close the fd,
   cancel its Henret task — the same path as `closeConnection`).
3. Leave the poller open for `unsafeDestroy` to finalize.

Returns the drained loop. The caller should call `unsafeDestroy` afterwards to
close the poller handle. This is the clean lifecycle end that replaces the
bounded-iteration loop the examples use for testability. -/
def unsafeShutdown (loop : EventLoop) : IO EventLoop := do
  -- 1. Stop accepting: deregister + close listeners.
  for listener in loop.listeners do
    let _ ← Unsafe.Epoll.deregister (fd32 loop.ph.epfd) (fd32 listener.key.raw)
    Unsafe.Socket.closeFdRaw (fd32 listener.key.raw)
  -- 2. Drain active stream connections.
  let mut l := { loop with listeners := [] }
  let activeKeys := loop.connections
  for key in activeKeys do
    l ← EffectError.orThrow (← l.closeConnection key)
  return l

/-- Acknowledge that a connection's readiness has been handled.
Must be called after processing each `dataReady` event to allow
the coalescing layer to deliver the next readiness for this key. -/
def ackReady (loop : EventLoop) (key : FdKey) (ev : IoEvent) : EventLoop :=
  let pk : Iotakt.Model.PendingKey :=
    { fd := key, kind := ev.pendingKind }
  let cs1 := loop.nds.ds.coalesce.ack pk
  { loop with nds := { loop.nds with ds := { loop.nds.ds with coalesce := cs1 } } }

/-- Receive on a connection **and acknowledge** its readable readiness in one
step — the combined helper recommended by RFC 006 so consumers cannot forget
to ack (which would suppress the next readiness for this fd). This pins
iotakt's coalescing contract to **explicit acknowledgement**: pending
readiness clears when the actor calls `recvAck`/`sendAck`/`ackReady`, never
implicitly. Returns the updated loop and the read result. -/
def recvAck (loop : EventLoop) (key : FdKey) (maxBytes : Nat) :
    IO (Except EffectError (EventLoop × Iotakt.Model.ReadResult)) := do
  match loop.resolveEffect key [.stream] with
  | .error e => return .error e
  | .ok _ =>
      if maxBytes > loop.nds.ds.config.maxReadBytes then
        return .error .limitExceeded
      if !Unsafe.Io.nativeIoLengthInRange maxBytes then
        return .error .nativeLengthLimit
      let r ← Unsafe.Io.recv key.raw maxBytes
      return .ok (loop.ackReady key .readable, r)

/-- Send on a connection **and acknowledge** its writable readiness in one
step (the write-side companion to `recvAck`). After a full write the caller
typically also `disableWrite`s; after a partial write it keeps write interest
and the next writable readiness will be delivered (the ack cleared the
previous one). -/
def sendAck (loop : EventLoop) (key : FdKey) (ba : ByteArray) (offset len : Nat) :
    IO (Except EffectError (EventLoop × Iotakt.Model.WriteResult)) := do
  match loop.resolveEffect key [.stream] with
  | .error e => return .error e
  | .ok _ =>
      let w ← Unsafe.Io.send key.raw ba offset len
      match w with
      | .invalidSlice => return .error .invalidSlice
      | .nativeLengthLimit => return .error .nativeLengthLimit
      | _ => return .ok (loop.ackReady key .writable, w)

/-- Result of initiating an outbound connect. -/
inductive ConnectOutcome where
  /-- Connection initiated; `key` is the fd key to watch for `.dataReady writable`.
      When writable arrives, call `Unsafe.Socket.checkConnect key.raw` to confirm. -/
  | inProgress (key : FdKey) : ConnectOutcome
  /-- Connection succeeded immediately (rare). -/
  | connected (key : FdKey) : ConnectOutcome
  /-- Connection failed. -/
  | failed (msg : String) : ConnectOutcome

/-- Initiate a non-blocking outbound TCP connect to `addr:port` (RFC 039).
`addr` is host-byte-order IPv4 (e.g. `0x7f000001` = 127.0.0.1).
The caller should watch for a `.dataReady key .writable` event, then
call `Unsafe.Socket.checkConnect key.raw` to confirm the connection. -/
def unsafeConnectTo (loop : EventLoop) (addr : UInt32) (port : UInt16) :
    IO (EventLoop × ConnectOutcome) := do
  let fd_r ← Unsafe.Socket.socketTcpRaw 1  -- AF_INET
  if fd_r < 0 then return (loop, .failed s!"socket() failed errno={-fd_r}")

  let r ← Unsafe.Socket.connectIPv4 fd_r addr port
  match r with
  | .error e =>
      Unsafe.Socket.closeFdRaw (fd32 fd_r)
      return (loop, .failed s!"connect() failed: {repr e}")
  | .connected =>
      -- Connected immediately; allocate key with read+write interest
      let (nds1, actorId) := loop.nds.freshActorId
      let (reg1, key) := nds1.ds.registry.allocate fd_r actorId .stream
      let reg2 := reg1.setInterests key (InterestSet.readOnly.enableWrite)
                    |>.markActive key
      let (rt1, spawnRes) := Henret.step loop.rt (.spawn actorId)
      let _ ← Unsafe.Epoll.register (fd32 loop.ph.epfd) (fd32 fd_r)
                (Unsafe.Epoll.interestFlags (InterestSet.readOnly.enableWrite))
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
      let _ ← Unsafe.Epoll.register (fd32 loop.ph.epfd) (fd32 fd_r)
                (Unsafe.Epoll.interestFlags (InterestSet.readOnly.enableWrite))
      let loop1 := { loop with
        nds := { nds1 with ds := { nds1.ds with registry := reg2 } }
        rt  := rt1 }
      let loop2 := match spawnRes with
        | .spawned task => loop1.recordTask key task
        | _             => loop1
      return (loop2, .inProgress key)

end EventLoop

end IotaktRuntime.Loop
