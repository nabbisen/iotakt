import Iotakt.Model.Update
import Iotakt.Model.Translate

/-!
# Iotakt.Model.Coalesce

Readiness coalescing and mailbox-flood prevention (RFC 006).

A level-triggered poller may report the same readiness condition over
and over. Injecting each repeat into a Henret mailbox would let a slow
actor accumulate unbounded duplicate readiness messages. iotakt buffers
*readiness bits* (never application bytes): for each `FdKey + kind` at
most one readiness notification is outstanding until the actor
acknowledges it.

The pending set is a function-map `PendingKey → Bool`, so the
"at-most-one pending per key/kind" bound is structural — a flag is set
or not. The theorems establish that a duplicate while pending is
suppressed, that delivery sets the flag, and that `ack` clears exactly
the matching flag.
-/

namespace Iotakt.Model

/-- The kind of a pending readiness notification. Readiness hints
(`readable`/`writable`) and fatal conditions (`eof`/`hangup`/`error`)
get independent pending slots so a hangup is never masked by a pending
readable. -/
inductive PendingKind where
  | readable
  | writable
  | eof
  | hangup
  | error
  deriving DecidableEq, Repr, Inhabited

/-- The kind of pending slot an event occupies. -/
def IoEvent.pendingKind : IoEvent → PendingKind
  | .readable => .readable
  | .writable => .writable
  | .eof      => .eof
  | .hangup   => .hangup
  | .error _  => .error

/-- A coalescing key: which resource, which kind. -/
structure PendingKey where
  fd   : FdKey
  kind : PendingKind
  deriving DecidableEq, Repr, Inhabited

/-- Coalescing state: the set of outstanding readiness notifications,
as a total predicate. -/
structure CoalesceState where
  pending : PendingKey → Bool
  deriving Inhabited

/-- The outcome of coalescing one owner event: either it is delivered
(no prior pending notification of its kind) or suppressed as a
duplicate. -/
inductive CoalesceResult where
  | deliver (ev : OwnerEvent)
  | coalesced (ev : OwnerEvent)
  deriving Repr, Inhabited

namespace CoalesceState

/-- No readiness outstanding. -/
def empty : CoalesceState := ⟨fun _ => false⟩

/-- The pending key an owner event would occupy. -/
def keyOf (oe : OwnerEvent) : PendingKey :=
  { fd := oe.key, kind := oe.event.pendingKind }

/-- Is a notification of this key/kind already outstanding? -/
def isPending (st : CoalesceState) (pk : PendingKey) : Bool := st.pending pk

/-- Coalesce one owner event. If its slot is already pending, suppress
it (`coalesced`) and leave the state unchanged. Otherwise mark the slot
pending and deliver it. -/
def step (st : CoalesceState) (oe : OwnerEvent) : CoalesceState × CoalesceResult :=
  let pk := keyOf oe
  if st.pending pk then
    (st, .coalesced oe)
  else
    (⟨upd st.pending pk true⟩, .deliver oe)

/-- Acknowledge a key/kind: clear its pending flag (typically after the
actor attempts the corresponding `recv`/`send`). Future readiness of
that kind can then be delivered again. -/
def ack (st : CoalesceState) (pk : PendingKey) : CoalesceState :=
  ⟨upd st.pending pk false⟩

/-! ## Coalescing theorems -/

/-- **Delivery sets the flag.** If a slot is not pending, `step`
delivers the event and marks that slot pending. -/
theorem step_delivers {st : CoalesceState} {oe : OwnerEvent}
    (h : st.pending (keyOf oe) = false) :
    st.step oe = (⟨upd st.pending (keyOf oe) true⟩, .deliver oe) := by
  simp [step, h]

/-- After a delivering `step`, the slot is pending. -/
theorem step_deliver_pending {st : CoalesceState} {oe : OwnerEvent}
    (h : st.pending (keyOf oe) = false) :
    (st.step oe).1.pending (keyOf oe) = true := by
  simp [step, h, upd]

/-- **Duplicate while pending is suppressed.** If a slot is already
pending, `step` yields `coalesced` and does not change the state. -/
theorem step_coalesces {st : CoalesceState} {oe : OwnerEvent}
    (h : st.pending (keyOf oe) = true) :
    st.step oe = (st, .coalesced oe) := by
  simp [step, h]

/-- **At-most-one delivery (the flood bound).** Two consecutive `step`s
on the same event, with no intervening `ack`, deliver at most once: the
second is always `coalesced`. -/
theorem step_twice_coalesced (st : CoalesceState) (oe : OwnerEvent) :
    ((st.step oe).1.step oe).2 = .coalesced oe := by
  unfold step keyOf
  by_cases h : st.pending ⟨oe.key, oe.event.pendingKind⟩
  · simp [h]
  · simp [h, upd]

/-- **Ack clears exactly the matching slot.** -/
theorem ack_clears (st : CoalesceState) (pk : PendingKey) :
    (st.ack pk).pending pk = false := by
  simp [ack, upd]

/-- **Ack preserves other slots.** -/
theorem ack_preserves_other (st : CoalesceState) {pk pk' : PendingKey}
    (h : pk' ≠ pk) : (st.ack pk).pending pk' = st.pending pk' := by
  simp [ack, upd, h]

set_option linter.unusedVariables false in
/-- **Step preserves other slots.** Coalescing one event's slot never
changes any other resource's or kind's pending flag — independent
readiness streams (e.g. readable vs writable on the same fd, or two
different fds) are tracked separately. -/
theorem step_preserves_other (st : CoalesceState) (oe : OwnerEvent)
    {pk' : PendingKey} (h : pk' ≠ keyOf oe) :
    (st.step oe).1.pending pk' = st.pending pk' := by
  by_cases hp : st.pending (keyOf oe)
  · simp [step, hp]
  · have hstep : st.step oe = (⟨upd st.pending (keyOf oe) true⟩, .deliver oe) := by
      simp [step, hp]
    rw [hstep]
    exact upd_ne st.pending true h

/-- **Progress after ack.** After acknowledging a slot, the same event
delivers again — unconditionally, since `ack` clears the slot regardless
of its prior state (the bound never deadlocks progress). -/
theorem deliver_after_ack (st : CoalesceState) (oe : OwnerEvent) :
    (((st.step oe).1.ack (keyOf oe)).step oe).2 = .deliver oe := by
  have hack : ((st.step oe).1.ack (keyOf oe)).pending (keyOf oe) = false :=
    ack_clears _ _
  rw [step_delivers hack]

end CoalesceState

end Iotakt.Model
