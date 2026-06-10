# Henret Integration Contract

This document records exactly what iotakt depends on from Henret, pinned
to **henret v0.11.0**. It mirrors the consumer side of Henret's own
RFC 044 (Runtime Integration Contract). When Henret changes, this is the
checklist to re-verify.

---

## Pinned version

```text
henret v0.11.0
```

`lakefile.lean` requires henret at this tag. The bump from v0.6.0 → v0.11.0
required exactly one proof change in iotakt (see "Bridge proof" below).

---

## What iotakt imports

iotakt's bridge and driver import only the **stable model surface**:

| Import | iotakt usage |
|--------|--------------|
| `Henret.Model` | `RuntimeState`, `RuntimeOp`, `step`, `run`, `drain` |
| `Henret.ActorId`, `Henret.Core.Id` | actor / task identifiers (= `Nat`) |
| `Henret.Mailbox`, `Henret.Message` | message envelope construction |

iotakt does **not** import `Henret.Bridge`, `Henret.Proofs` internals, or
`Henret.Native.*`. Per Henret RFC 044, `Henret.Model` is the stable tier.

## Operations iotakt issues

| iotakt action | Henret op |
|---------------|-----------|
| Set up listener / accept connection | `spawn actorId` |
| Inject readiness into owning actor | `inject owner msg` |
| Advance logical clock on timer expiry | `tick now` |
| Close connection (Gap 006) | `cancel taskId` |

iotakt spawns one task per connection (the task owns the actor's mailbox),
injects readiness messages into that actor's mailbox, and cancels the task
on close.

---

## The three discrepancies (re-verified against v0.11.0)

These were discovered during early development and are re-checked here.

### Discrepancy 1 — `inject` does not auto-create a mailbox

`inject a m` returns `.invalid` if actor `a` has no mailbox. **However**,
since v0.6.0 (RFC 032) `spawn a` auto-creates actor `a`'s mailbox. Because
iotakt always spawns the owning actor *before* injecting (verified in
`setupListener`, `acceptOne`, and `connectTo`), the mailbox is always
present at inject time.

- **Status:** structurally resolved upstream.
- **iotakt mitigation:** `deliverOne`'s mailbox guard remains as defensive
  code; `inject_ok_of_mailbox` proves delivery succeeds when the mailbox
  exists. Both are still correct and retained.

### Discrepancy 2 — `inject` never returns `.woke`

All three `inject` branches in v0.11.0 (regular waiter / timed waiter /
no waiter) return `.ok`. iotakt's bridge assumes `.ok`; this holds.

### Discrepancy 3 — woken waiters are appended, not prepended

`send`/`inject`/`tick` wake a waiter by `readyQ ++ [w]` (FIFO append).
iotakt does not depend on wake ordering, so this is informational only.

---

## Bridge proof

iotakt's one proof against Henret internals is `inject_ok_of_mailbox`
in `Iotakt/Bridge/Driver.lean`. The v0.11.0 bump required updating it:

- **v0.6.0:** `inject` checked only `mailboxWaiters`; the proof
  case-split on that one queue.
- **v0.11.0 (RFC 040):** `inject` checks `mailboxWaiters` first, then
  `timedMailboxWaiters` (timed-receive support). The proof now
  case-splits on both queues. All branches still return `.ok`, so the
  theorem statement is unchanged — only the proof body grew one `cases`.

This is the *only* iotakt code change required by the version bump.

---

## New v0.11.0 capabilities iotakt now uses or could use

| Capability | RFC | iotakt status |
|------------|-----|---------------|
| `cancel` task cleanup | 029/031 | **Used** — Gap 006 cancel-on-close |
| `cancelTree` cascade cancel | 039 | Available; not yet used (single-level connections) |
| `receiveUntil` timed parking | 040 | **Candidate** — could replace the driver's poll-timeout loop with true park/wake; deferred to a future RFC |
| Lean-runtime bridge | 035/036 | Available; iotakt's driver remains the single outer loop, so not yet needed |
| Occurrence identity (`Envelope`) | 033 | Transparent — iotakt builds `Message`; Henret stamps occurrence ids |

### The `receiveUntil` opportunity

Today iotakt's driver computes the next Henret timer deadline, uses it as
the `epoll_wait` timeout, and injects `.tick` on expiry. With
`receiveUntil`, a connection actor blocked on its mailbox could park with
a deadline directly, and Henret would wake it on either message delivery
or timer expiry. This would let the driver block indefinitely in
`epoll_wait` (no 100ms polling), waking only on real I/O. Adopting it is a
v0.7+ design decision because it changes the driver loop's shape; it is
recorded here and in the roadmap.

---

## Mesa semantics (consumer obligations)

Per Henret RFC 044, iotakt must respect Mesa delivery semantics:

- delivery wakes at most one waiter;
- wake does not atomically hand off the message;
- a woken task must re-run `receive`;
- another task may consume the message first.

iotakt's model is single-consumer-per-connection (one actor owns each fd),
so the "another task may consume first" case does not arise in practice —
but iotakt does not rely on atomic handoff, so the contract holds.

---

## Re-verification checklist (on future Henret bumps)

1. `lake build IotaktBridge` — does `inject_ok_of_mailbox` still prove?
2. Re-check the three discrepancies against the new `step` source.
3. Confirm `RuntimeOp` constructors iotakt issues still exist with the
   same signatures: `spawn`, `inject`, `tick`, `cancel`.
4. Confirm `StepResult.spawned` still carries the task id.
5. Run the full CI gate (`scripts/ci.sh`).
