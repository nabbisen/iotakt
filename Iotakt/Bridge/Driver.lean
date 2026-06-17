import Henret.Model
import Iotakt.Model
import Iotakt.Bridge.Message

/-!
# Iotakt.Bridge.Driver

The deterministic outer driver (RFC 007).

The driver is the sole writer of both the iotakt `DriverState` and the
Henret `RuntimeState`; there is no background thread, so the whole step
is a pure function of its inputs and the poller trace. One driver pass:

1. translate each raw event through the registry (stale/unknown drop);
2. coalesce duplicate readiness;
3. **guarded-inject** each delivered event into the owning actor.

### Guarded inject — a Henret v0.6.0 integration requirement

Henret's `inject a m` is **invalid** (a no-op returning `.invalid`) when
actor `a` has no mailbox; the `inject_appends` theorem carries the
hypothesis `s.mailboxes a = some mb`. (The v0.6.0→iotakt handoff states
inject "always succeeds, creating the mailbox if absent" — that does not
match the shipped code; see `docs/henret-integration-notes.md`.) A
mailbox exists only after the owning actor has been `spawn`ed. The
driver therefore checks `rt.mailboxes owner` and only injects when the
mailbox exists, recording `droppedNoMailbox` otherwise. `inject_ok_of_mailbox`
below proves that, under this guard, every inject the driver issues
returns `.ok` — so no readiness event is ever silently dropped by an
`.invalid` inject.
-/

namespace Iotakt.Bridge

open Iotakt.Model

/-- Resource limits for the driver loop (RFC 013).
    All limits have safe defaults; override for production tuning. -/
structure DriverConfig where
  /-- Maximum events fetched from the poller per wait call. -/
  maxEventsPerPoll    : Nat := 1024
  /-- Maximum bytes requested per recv call. -/
  maxReadBytes        : Nat := 16384
  /-- Maximum connections accepted per listener-readiness event. -/
  maxAcceptBurst      : Nat := 64
  /-- How many times the driver retries after EINTR in poll_wait.
      0 = return interrupted to Lean; the driver decides whether to retry. -/
  pollInterruptRetries : Nat := 0
  deriving Repr, Inhabited

/-- iotakt driver state: the registry, the coalescing set, the
logical clock, and the active resource-limit config. Kept separate
from Henret's `RuntimeState`. -/
structure DriverState where
  registry     : Registry
  coalesce     : CoalesceState
  clock        : Nat
  config       : DriverConfig := {}
  shuttingDown : Bool := false

/-- The result of waiting on a poller (fake or native). -/
inductive PollWaitResult where
  | events (events : List NormalizedRawEvent)
  | timeout
  | interrupted
  | fatal (err : IoErrno)
  deriving Repr, Inhabited

/-- Structured driver trace (RFC 015), shared by fake and native runs so
deterministic fake traces match the native code path's shape. -/
inductive BridgeTrace where
  | injected (owner : ActorId) (msg : Henret.Message)
  | coalesced (key : FdKey) (kind : PendingKind)
  | droppedUnknown (rawFd : RawFd)
  | droppedStale (rawFd : RawFd)
  | droppedNoInterest (rawFd : RawFd)
  | droppedClosed (rawFd : RawFd)
  | droppedNoMailbox (owner : ActorId)
  | ticked (now : Nat)
  | interruptedWait
  | fatalWait (err : IoErrno)
  deriving Repr, Inhabited

/-- The next logical timer deadline, read directly from Henret's sorted
timer list (handoff §7: no `nextDeadline` helper exists in Henret, so
read `timers.head?`). -/
def nextDeadline (rt : Henret.RuntimeState) : Option Nat :=
  rt.timers.head?.map (·.deadline)

/-- Deliver one owner event: coalesce, then guarded-inject. Threads both
the iotakt `DriverState` (its coalescing set) and the Henret runtime. -/
def deliverOne (ds : DriverState) (rt : Henret.RuntimeState) (oe : OwnerEvent) :
    DriverState × Henret.RuntimeState × List BridgeTrace :=
  match ds.coalesce.step oe with
  | (cs', .coalesced _) =>
      ({ ds with coalesce := cs' }, rt, [.coalesced oe.key oe.event.pendingKind])
  | (cs', .deliver _) =>
      let ds' := { ds with coalesce := cs' }
      match rt.mailboxes oe.owner with
      | none   => (ds', rt, [.droppedNoMailbox oe.owner])
      | some _ =>
          let msg := encodeOwnerEvent oe
          let rt' := (Henret.step rt (.inject oe.owner msg)).1
          (ds', rt', [.injected oe.owner msg])

/-- Apply one translation result. Injectable events go through
`deliverOne`; drops are traced and change nothing. -/
def applyResult (ds : DriverState) (rt : Henret.RuntimeState) :
    TranslationResult → DriverState × Henret.RuntimeState × List BridgeTrace
  | .injectable oe                     => deliverOne ds rt oe
  | .dropped raw .unknownRawFd         => (ds, rt, [.droppedUnknown raw])
  | .dropped raw .staleGeneration      => (ds, rt, [.droppedStale raw])
  | .dropped raw .noRegisteredInterest => (ds, rt, [.droppedNoInterest raw])
  | .dropped raw .resourceClosed       => (ds, rt, [.droppedClosed raw])

/-- Process a batch of normalized events in order. Translation reads the
(unchanging) registry; coalescing and the Henret runtime are threaded. -/
def processEvents (ds : DriverState) (rt : Henret.RuntimeState) :
    List NormalizedRawEvent → DriverState × Henret.RuntimeState × List BridgeTrace
  | []      => (ds, rt, [])
  | e :: es =>
      let (ds1, rt1, tr1) := applyResult ds rt (ds.registry.translateOne e)
      let (ds2, rt2, tr2) := processEvents ds1 rt1 es
      (ds2, rt2, tr1 ++ tr2)

/-- Handle one poll-wait outcome: deliver events, tick on timeout, or
trace interrupted/fatal. `now` is the logical time to tick to on timeout. -/
def runPoll (ds : DriverState) (rt : Henret.RuntimeState) (now : Nat) :
    PollWaitResult → DriverState × Henret.RuntimeState × List BridgeTrace
  | .events evs  => processEvents ds rt evs
  | .timeout     => ({ ds with clock := now }, (Henret.step rt (.tick now)).1, [.ticked now])
  | .interrupted => (ds, rt, [.interruptedWait])
  | .fatal e     => (ds, rt, [.fatalWait e])

/-! ## Theorems -/

/-- **Guarded inject always succeeds.** When the owner's mailbox exists,
the runtime is running, the owner is not closed, and the mailbox is not at
capacity, Henret `inject` returns `.ok` (never `.invalid`, never
`.backpressured`). This is the formal mitigation of Henret's inject
precondition: the driver's mailbox guard guarantees no readiness is lost.

The preconditions track Henret's admission guards, all of which hold
throughout iotakt's driver operation:
* `runtimeStatus`/`actorStatus` — RFC 055 (v0.17.0) shutdown guards. The
  driver starts from `RuntimeState.init` (`runtimeStatus = .running`, every
  actor `.active`) and never issues `closeActor`/`shutdown`/`stopWhenIdle`.
* `mailboxFull a mb = false` — RFC 056 (v0.18.0) backpressure guard. iotakt
  never configures a mailbox bound, so `mailboxPolicy` stays `.unbounded`
  (from `RuntimeState.init`) and `mailboxFull` is always `false`; readiness
  occupancy is independently bounded by the coalescing discipline. -/
theorem inject_ok_of_mailbox {rt : Henret.RuntimeState} {a : Henret.ActorId}
    {mb : Henret.Mailbox} (h : rt.mailboxes a = some mb)
    (hrun : rt.runtimeStatus = .running) (hact : rt.actorStatus a ≠ .closed)
    (hfull : rt.mailboxFull a mb = false)
    (m : Henret.Message) :
    (Henret.step rt (.inject a m)).2 = .ok := by
  -- Inject guard order: RFC 055 (v0.17.0) runtimeStatus/actorStatus
  -- (discharged by hrun/hact), then mailbox-exists (h), then RFC 056
  -- (v0.18.0) mailboxFull backpressure (discharged by hfull). v0.11.0
  -- (RFC 040): the enqueue path then checks mailboxWaiters, then
  -- timedMailboxWaiters; all branches return .ok. Case-split on both queues.
  cases hw : rt.mailboxWaiters a <;>
    cases htw : rt.timedMailboxWaiters a <;>
    simp [Henret.step, h, hw, htw, hrun, hact, hfull]

/-- **Unknown events never inject.** Applying an `unknownRawFd` drop
leaves the Henret runtime untouched and traces only the drop. -/
theorem applyResult_unknown_unchanged (ds : DriverState) (rt : Henret.RuntimeState)
    (raw : RawFd) :
    applyResult ds rt (.dropped raw .unknownRawFd) = (ds, rt, [.droppedUnknown raw]) :=
  rfl

/-- **The mailbox guard holds.** If the owner has no mailbox, `deliverOne`
leaves the Henret runtime unchanged and records `droppedNoMailbox` — it
never issues an inject that would be a silent no-op. -/
theorem deliverOne_no_mailbox {ds : DriverState} {rt : Henret.RuntimeState}
    {oe : OwnerEvent} (hcoal : ds.coalesce.pending (CoalesceState.keyOf oe) = false)
    (hmb : rt.mailboxes oe.owner = none) :
    (deliverOne ds rt oe).2.1 = rt := by
  unfold deliverOne CoalesceState.step
  simp [hcoal, hmb]

/-- **Coalesced delivery does not touch the runtime.** A duplicate
readiness (already pending) injects nothing. -/
theorem deliverOne_coalesced {ds : DriverState} {rt : Henret.RuntimeState}
    {oe : OwnerEvent} (hcoal : ds.coalesce.pending (CoalesceState.keyOf oe) = true) :
    (deliverOne ds rt oe).2.1 = rt := by
  unfold deliverOne CoalesceState.step
  simp [hcoal]

/-- **Interrupted waits mutate nothing.** An interrupted poll wait leaves
both the iotakt driver state and the Henret runtime untouched (RFC 008
proof obligation: timeout/interrupted simulation does not mutate
unrelated state). -/
theorem runPoll_interrupted_unchanged (ds : DriverState) (rt : Henret.RuntimeState)
    (now : Nat) :
    runPoll ds rt now .interrupted = (ds, rt, [.interruptedWait]) := rfl

/-- **Empty event batch mutates nothing.** -/
theorem processEvents_nil (ds : DriverState) (rt : Henret.RuntimeState) :
    processEvents ds rt [] = (ds, rt, []) := rfl

end Iotakt.Bridge
