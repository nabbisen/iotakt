# RFC 035: Henret Wait-Queue Parking Integration

- **Status:** Future / Henret-dependent
- **Intended phase:** After Henret wait queues exist
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines how iotakt should integrate with a future Henret capability for real blocked-task parking and wakeup queues.

The current iotakt v0.1 bridge must not depend on such a feature. It uses injected I/O messages to make actors runnable. This RFC exists to prevent future integration from being invented ad hoc once Henret grows explicit wait queues.

## 2. Motivation

The current Henret-compatible iotakt design treats readiness as a message:

```text
OS poll event -> normalized IoEvent -> Henret mailbox injection -> actor receives IoMessage
```

This is simple, deterministic, and compatible with Henret's current model. However, a future Henret may support explicit parking of tasks on external conditions, such as:

```text
park task T on key K
wake all tasks waiting on key K
wake one task waiting on key K
```

If this feature appears, iotakt can reduce mailbox noise and model waiting more precisely. It must still preserve the same safety invariants: no stale fd event delivery, no unknown injection, readiness-as-hint semantics, and no native-side actor mutation.

## 3. Non-goals

This RFC does not require changes to Henret.

This RFC does not make parking a v0.1 requirement.

This RFC does not replace mailbox-based readiness messages. The mailbox bridge remains the compatibility baseline.

This RFC does not introduce native background threads or direct native calls into Henret internals.

## 4. Proposed model extension

Introduce a Lean-only abstraction that can be interpreted either as mailbox injection or as future parking wakeup.

```lean
structure WaitKey where
  fd    : FdKey
  kind  : IoInterest

deriving DecidableEq, Repr

inductive ReadinessDelivery where
  | mailboxMessage : ActorId -> IoMessage -> ReadinessDelivery
  | wakeWaitKey    : WaitKey -> ReadinessDelivery
```

The translator should not directly choose OS behavior. It should produce a pure `ReadinessDelivery` plan.

```lean
def translateReady
  (registry : Registry)
  (pending  : PendingReadiness)
  (event    : NativeReadyEvent) : Registry × PendingReadiness × List ReadinessDelivery
```

For v0.1, the interpreter for `ReadinessDelivery` supports only `mailboxMessage`. For future Henret integration, an alternate interpreter may support `wakeWaitKey`.

## 5. Parking semantics

A parked task must be associated with an actor-owned `FdKey` and an interest kind.

```text
Task T may park on WaitKey(fd, readable) only if:
- T belongs to the actor that owns fd, or
- the actor explicitly delegated that authority through an iotakt handle.
```

A wakeup caused by readiness does not guarantee a successful read or write. The actor must still call `recv` or `send` and handle `wouldBlock`.

## 6. Invariants

The future parking bridge should prove or test the following properties:

```text
Wake-authority invariant:
  iotakt never wakes a wait key for an unregistered FdKey.

Generation invariant:
  iotakt never wakes a wait key for an obsolete fd generation.

Interest invariant:
  readable wakeups require registered read interest.
  writable wakeups require registered write interest.

No native mutation invariant:
  the native poller does not directly mutate Henret wait queues.
```

## 7. Compatibility policy

All public APIs introduced before parking support must continue to work.

The mailbox bridge remains the stable baseline. Parking support may be introduced as an optimization or refinement, not as a breaking replacement.

## 8. Acceptance criteria

- A design note describes how current mailbox readiness maps to future wait keys.
- The model contains no assumption that parking exists in Henret v0.1.
- Test traces can be replayed under the mailbox interpreter and the parking interpreter, with equivalent actor-visible readiness behavior.
- The proof/trust/test matrix distinguishes proven translation properties from assumed Henret parking semantics.
