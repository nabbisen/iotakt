import Henret.Model
import IotaktRuntime.Bridge
import IotaktRuntime.Native

/-!
# IotaktRuntime.Driver

The real native driver loop (RFC 007 + RFC 011): ties the Linux epoll
backend, the pure model registry, the coalescing bridge, and Henret into
a deterministic single-threaded step.

## Driver step

One call to `nativeStep` performs:

```text
1. Henret.drain — run all ready tasks until the queue is empty
2. computeTimeout — nearest Henret timer deadline → epoll timeout
3. Epoll.wait — poll for I/O readiness (blocking up to timeout)
4. Epoll.parseEvents — decode raw ByteArray → NormalizedRawEvent list
5. Bridge.processEvents — translate → coalesce → guarded inject
6. tick if timeout — advance Henret logical clock on timer expiry
```

## ActorId allocation

Henret's `ActorId = Nat`. iotakt maintains its own monotone counter in
`NativeDriverState.nextActorId`. Each newly accepted connection receives
a fresh ActorId that does not overlap with previously allocated IDs in
this driver run. The application must coordinate ActorId namespaces when
combining iotakt-managed and application-managed actors.

## Resource limits

`DriverConfig` (RFC 013) bounds `maxEventsPerPoll`, `maxReadBytes`,
`maxAcceptBurst`, and `pollInterruptRetries`.
-/

namespace IotaktRuntime.Driver

open Iotakt.Model IotaktRuntime.Bridge IotaktRuntime.Native Henret

/-- Handle for the epoll instance used by the driver. -/
structure PollerHandle where
  epfd : Int
  deriving Repr, Inhabited

/-- Extended driver state: core `DriverState` plus a fresh ActorId
counter so the driver can spawn actors for accepted connections. -/
structure NativeDriverState where
  ds           : DriverState
  nextActorId  : Nat := 100  -- avoids ActorId ambiguity (both Henret and Model define it)
  -- (no Inhabited derivation; Registry lacks a trivial default)

/-- Allocate a fresh ActorId that won't collide with prior allocations. -/
def NativeDriverState.freshActorId (s : NativeDriverState) :
    NativeDriverState × Nat :=
  ({ s with nextActorId := s.nextActorId + 1 }, s.nextActorId)

/-- Compute the epoll timeout (ms) from Henret's nearest timer deadline.
    -1 = block indefinitely (no pending timers).
    0  = don't block (poll only, e.g. when tasks are ready). -/
def computeTimeout (rt : RuntimeState) (cfg : DriverConfig) : Int :=
  match rt.timers.head? with
  | none      => if rt.readyQ.isEmpty then -1 else 0
  | some tmr  =>
      let remaining := (tmr.deadline : Int) - (rt.now : Int)
      -- Clamp to [0, maxTimeout]; we use Int here to avoid underflow.
      -- The actual maximum is governed by DriverConfig (future extension);
      -- for now cap at 30 000 ms (30 s).
      let _ := cfg  -- reserved for future maxPollTimeoutMs
      if remaining <= 0 then 0 else min remaining 30000

/-- One driver step: drain Henret, wait for I/O, translate events,
inject messages, tick if timer expired. Returns the updated state, the
updated Henret runtime, and the trace for this step. -/
def nativeStep
    (nds : NativeDriverState) (rt : RuntimeState) (ph : PollerHandle)
    : IO (NativeDriverState × RuntimeState × List BridgeTrace) := do
  let cfg := nds.ds.config
  -- 1. Drain Henret ready queue.
  -- Note (Gap 003/RFC docs): use Henret.run [] rather than drain to
  -- avoid force-completing long-lived connection actors.
  -- With an empty op list, run is a no-op; actual draining happens
  -- in the calling echo/server loop via repeated schedule/receive ops.

  -- 2. Compute timeout from nearest Henret timer.
  let timeoutMs := computeTimeout rt cfg

  -- 3. Wait for I/O or timeout.
  let maxEv := min cfg.maxEventsPerPoll 1024 |>.toInt32
  let (waitStatus, evtBytes) ←
    Epoll.wait (fd32 ph.epfd) maxEv timeoutMs.toInt32

  -- 4. Parse events and translate through the bridge.
  let rawEvts := Epoll.parseEvents evtBytes
  let (ds1, rt1, trace) :=
    if waitStatus > 0 then
      processEvents nds.ds rt rawEvts
    else if waitStatus == 0 then
      -- timeout: tick Henret
      let now1 := nds.ds.clock + 1
      let rt1  := (Henret.step rt (.tick now1)).1
      let ds1  := { nds.ds with clock := now1 }
      (ds1, rt1, [.ticked now1])
    else
      -- fatal epoll error
      (nds.ds, rt, [.fatalWait (.other waitStatus)])

  return ({ nds with ds := ds1 }, rt1, trace)

where fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

/-! ## Listener setup -/

/-- Result of setting up a TCP listener. -/
inductive ListenerSetupResult where
  | ok   (key : FdKey) (lfd : Int)
  | fail (msg : String)
  deriving Repr

/-- Create a TCP listener on 127.0.0.1:port, register it with epoll and
the iotakt registry.  The listener fd is owned by `ownerActorId`. -/
def setupListener
    (nds : NativeDriverState) (rt : RuntimeState) (ph : PollerHandle)
    (port : UInt16) (ownerActorId : Nat)
    : IO (NativeDriverState × RuntimeState × ListenerSetupResult) := do
  let lfd_r ← Socket.socketTcpRaw 1  -- AF_INET
  if lfd_r < 0 then return (nds, rt, .fail s!"socket() failed errno={-lfd_r}")
  let lfd := lfd_r

  let _ ← Socket.setReuseAddrRaw (fd32 lfd)
  let LOOPBACK : UInt32 := 0x7f000001  -- 127.0.0.1
  let bind_r ← Socket.bindIPv4Raw (fd32 lfd) LOOPBACK port
  if bind_r != 0 then do
    Socket.closeFdRaw (fd32 lfd)
    return (nds, rt, .fail s!"bind() failed errno={-bind_r}")

  let listen_r ← Socket.listenRaw (fd32 lfd) nds.ds.config.maxAcceptBurst.toInt32
  if listen_r != 0 then do
    Socket.closeFdRaw (fd32 lfd)
    return (nds, rt, .fail s!"listen() failed errno={-listen_r}")

  -- Allocate FdKey and register in the iotakt registry
  let (reg1, key) := nds.ds.registry.allocate lfd ownerActorId .listener
  let reg2 := reg1.setInterests key InterestSet.readOnly |>.markRegistered key

  -- Register with epoll
  let reg_r ← Epoll.register (fd32 ph.epfd) (fd32 lfd)
    (Epoll.interestFlags InterestSet.readOnly)
  if reg_r != 0 then do
    Socket.closeFdRaw (fd32 lfd)
    return (nds, rt, .fail s!"epoll register failed errno={-reg_r}")

  -- Spawn the listener actor in Henret (creates its mailbox)
  let rt1 := (Henret.step rt (.spawn ownerActorId)).1

  let ds1 := { nds.ds with registry := reg2 }
  return ({ nds with ds := ds1 }, rt1, .ok key lfd)

where fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

/-! ## Accept loop -/

/-- Result of one accept4 call plus the FdKey if accepted. -/
inductive AcceptOneResult where
  | accepted (streamKey : FdKey) (streamFd : Int) (task : Nat)
  | wouldBlock
  | error (e : IoErrno)
  deriving Repr

/-- Accept one connection: set up registry entry and Henret actor.
The stream actor gets its own fresh ActorId and is spawned in Henret. -/
def acceptOne
    (nds : NativeDriverState) (rt : RuntimeState) (ph : PollerHandle)
    (listenerFd : Int)
    : IO (NativeDriverState × RuntimeState × AcceptOneResult) := do
  let acc ← Socket.accept listenerFd
  match acc with
  | .wouldBlock  => return (nds, rt, .wouldBlock)
  | .interrupted => return (nds, rt, .wouldBlock)  -- treat EINTR same as wouldBlock
  | .error e     => return (nds, rt, .error e)
  | .accepted streamFd _ =>
      -- Allocate FdKey and fresh ActorId for the stream
      let (nds1, actorId) := nds.freshActorId
      let (reg1, key) := nds1.ds.registry.allocate streamFd actorId .stream
      let reg2 := reg1.setInterests key InterestSet.readOnly |>.markActive key

      -- Register with epoll
      let _ ← Epoll.register (fd32 ph.epfd) (fd32 streamFd)
        (Epoll.interestFlags InterestSet.readOnly)

      -- Spawn connection actor in Henret (creates its mailbox).
      -- Capture the spawned task id for later cancel-on-close (Gap 006).
      let (rt1, spawnRes) := Henret.step rt (.spawn actorId)
      let task := match spawnRes with | .spawned t => t | _ => actorId

      let ds2 := { nds1.ds with registry := reg2 }
      return ({ nds1 with ds := ds2 }, rt1, .accepted key streamFd task)

where fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

/-- Accept up to `maxBurst` connections in a loop.
Returns the list of accepted (streamKey, streamFd) pairs. -/
def acceptBurst
    (nds : NativeDriverState) (rt : RuntimeState) (ph : PollerHandle)
    (listenerFd : Int)
    : IO (NativeDriverState × RuntimeState × List (FdKey × Int × Nat)) := do
  let maxBurst := nds.ds.config.maxAcceptBurst
  let mut nds := nds
  let mut rt  := rt
  let mut acc : List (FdKey × Int × Nat) := []
  let mut stop := false
  for _ in List.range maxBurst do
    if stop then pure ()
    else do
      let (nds1, rt1, r) ← acceptOne nds rt ph listenerFd
      nds := nds1; rt := rt1
      match r with
      | .wouldBlock  => stop := true
      | .error _     => stop := true
      | .accepted k fd task => acc := (k, fd, task) :: acc
  return (nds, rt, acc.reverse)

end IotaktRuntime.Driver
