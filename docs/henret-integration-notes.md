# Henret Integration Notes

**iotakt v0.1 — Henret v0.6.0**

This document records discrepancies between the Henret v0.6.0→iotakt
handoff document and the shipped `henret` source, together with
mitigations and open questions for the Henret maintainer.

---

## Discrepancy 1 — `inject` does NOT create the mailbox if absent

### Handoff claim

> iotakt does not need to guard inject calls. inject always succeeds.
> If the mailbox is absent for actor a, the mailbox is created.

### Actual Henret v0.6.0 behavior (Henret/Scheduler/Model.lean)

```lean
| .inject a m =>
    match s.mailboxes a with
    | some mb => ...            -- delivers, wakes waiter if any, returns .ok
    | none    => (s, .invalid)  -- SILENT no-op
```

`inject` returns `.invalid` when the mailbox does not exist. The runtime
state is **not mutated**. No mailbox is created.

### Impact

An iotakt bridge that calls `inject` without first verifying the mailbox
silently drops every readiness notification to un-spawned actors. There
is no error — the state just does not change.

### Mitigation (implemented)

`Iotakt.Bridge.Driver.deliverOne` checks `rt.mailboxes oe.owner` before
issuing the inject op:

```lean
match rt.mailboxes oe.owner with
| none   => (ds', rt, [.droppedNoMailbox oe.owner])   -- guarded drop
| some _ =>
    let rt' := (Henret.step rt (.inject oe.owner msg)).1
    (ds', rt', [.injected oe.owner msg])
```

The theorem `inject_ok_of_mailbox` proves that when this guard passes,
the inject always returns `.ok`:

```lean
theorem inject_ok_of_mailbox {rt} {a} {mb}
    (h : rt.mailboxes a = some mb) (m : Henret.Message) :
    (Henret.step rt (.inject a m)).2 = .ok
```

This theorem is machine-checked. It is the formal mitigation for this
discrepancy, and it appears in the proof/trust/test matrix as PROVEN.

### Request to Henret maintainer

Please clarify the intended semantics in the handoff document. If
"always succeeds with mailbox creation" is the intended design, the
shipped code does not implement it and the `inject_appends` proof
theorem's hypothesis `s.mailboxes a = some mb` would be incorrect.

If "invalid when absent" is the intended design, update the handoff
document and confirm that `spawn` is the correct mechanism to create
a mailbox before injecting.

---

## Discrepancy 2 — `inject` returns `.ok`, never `.woke`

### Handoff claim (§13 Bootstrap Trace)

```
let (s2, r2) := step s1 (.inject 7 ⟨1, 100⟩)
-- r2 = .woke [0]    ← INCORRECT
```

### Actual Henret v0.6.0 behavior

From Henret `Main.lean` scenario 7 (the project's own test):

```lean
let (s12, r12) := step s11 (.inject 7 ⟨1, 100⟩)
check "inject delivers ok" (r12 matches .ok)
```

And from `Model.lean`: the inject branch returns `.ok` in **both** the
`[]`-waiter and `w :: ws`-waiter subcases. `.woke` is returned only by
`.tick`.

### Impact

Any code that pattern-matches the second element of `inject`'s result
looking for `.woke` will fail to match and may silently miss the wakeup.

### Mitigation (implemented)

The iotakt bridge uses only `.1` of the inject result (the new runtime
state) and never relies on the result variant. `Main.lean` scenario 1
verifies the woken-task behavior by inspecting `rt.taskState 0`
(expecting `.ready`), not by matching `.woke`.

---

## Discrepancy 3 — Woken waiters appended, not prepended

### Handoff claim (§13)

> The woken task is **prepended** to readyQ for priority.

### Actual Henret v0.6.0 behavior

```lean
readyQ := s'.readyQ ++ [w]   -- APPENDED, not prepended
```

Woken tasks are appended to the tail of `readyQ`, consistent with FIFO
scheduling.

### Impact

Minor. FIFO is the correct semantics for actor-model fairness; prepend
would introduce priority inversion. No functional impact for iotakt since
the bridge does not schedule actors directly.

---

## Open questions for Henret maintainer

1. **ActorId allocation API.** iotakt must `spawn` an actor before
   injecting. Who owns ActorId allocation, and how does iotakt know which
   ActorId to use for a newly accepted connection actor? Does Henret
   expose a next-id counter or does the application manage its own
   namespace?

2. **RFC 033 timeline.** RFC 033 proposes a richer `Message` envelope
   to replace `{ id : Nat, payload : Nat }`. The current iotakt bridge
   uses a lossy two-Nat codec (`id = raw_fd.toNat`, `payload = event
   bitmask`). When RFC 033 ships, iotakt will need `Bridge/Message.lean`
   updated. What is the expected timeline?

3. **`drain` vs `driveBounded`.** The handoff recommends `drain` for
   emptying the ready queue before polling. In Henret v0.6.0, `drain`
   **force-completes** runnable tasks (calling them terminal). Long-lived
   connection actors that never complete would be terminated by `drain`.
   Was this intentional, or should iotakt use `driveBounded`/`step` in a
   loop instead?

---

## Summary

All three discrepancies are mitigated in the v0.1 iotakt implementation.
Discrepancy 1 is formally proven by `inject_ok_of_mailbox`. Discrepancy
2 is tested by the demo scenario 1. Discrepancy 3 is documentation-only
with no functional impact.

The three open questions require a response from the Henret maintainer
before the native integration milestone (RFCs 009–012) is finalized.
