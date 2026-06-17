# Henret Integration Contract

This document records exactly what iotakt depends on from Henret, pinned
to **henret v0.11.0**. It mirrors the consumer side of Henret's own
RFC 044 (Runtime Integration Contract). When Henret changes, this is the
checklist to re-verify.

---

## Pinned version

```text
henret v0.34.0
```

`lakefile.lean` requires henret at this tag. The path from v0.6.0:

| Bump | What changed for iotakt |
|------|--------------------------|
| v0.6.0 → v0.11.0 | One proof fix (`inject_ok_of_mailbox` gained a `cases` for the new timed-waiter queue); two `Envelope` data fixes (3-field form). |
| v0.11.0 → v0.11.1 | Selective receive (`receiveByOccurrence`, `receiveFrom`) — additive, no iotakt change. |
| v0.11.1 → v0.12.0 | Multi-worker bridge model (`MultiBridgeState`) — additive, no iotakt change. |
| v0.12.0 → v0.12.1 | RFC 044 integration contract published — documentation only, no iotakt change. |
| v0.12.1 → v0.13.x | Trace ledger (RFC 045) + golden-trace conformance (RFC 047) — additive modules, no iotakt change. |
| v0.13.x → v0.14.x | Fairness/liveness policy layer (RFC 046) + bounded model explorer (RFC 048) — additive, no iotakt change. |
| v0.14.x → v0.15.0 | **Supervision restart (RFC 049)**: new `TaskState.failed`, `fail`/`restartOne` ops, `restartOf` field. iotakt's only `TaskState` match (`SchedConn.phaseOf`) has a catch-all, so non-breaking; iotakt *adopted* the new ops (see below). |
| v0.15.0 → v0.15.2 | Renderers (RFC 050) + package/doc maturity (RFC 051) — additive, no iotakt change. |
| v0.15.2 → v0.16.0 | Semantic Profiles (RFC 054) — optional metadata vocabulary (`core ⊂ actor ⊂ full`); no behavior/theorem change. iotakt depends on the **`actor`** profile (lifecycle + scheduling + mailboxes + parking + occurrence identity); it does **not** use the resource ledger (RFC 057/091), so those features are vacuous for it. |
| v0.16.0 → v0.17.0 | **Structured Cancellation & Shutdown (RFC 055)**: +3 `RuntimeOp` (`closeActor`/`shutdown`/`stopWhenIdle` → 21), +2 `RuntimeState` fields (`actorStatus`/`runtimeStatus`), +2 enums, +3 trace events, +`RuntimeQuiescent`. Admission guards added to `spawn`/`send`/`inject`. **One proof fix** — `inject_ok_of_mailbox` gained two hypotheses (`runtimeStatus = .running`, `actorStatus a ≠ .closed`) to discharge the new `inject` guard. No compiler-caught break (iotakt uses `RuntimeState.init`, no exhaustive `RuntimeOp`/`TraceEvent` match). |
| v0.17.0 → v0.17.7 | Release-engineering wave (RFCs 080–086): release gate, evidence ledger, conformance coverage (37 scenarios), proof ergonomics, generated docs. No model behavior change; no iotakt change. |
| v0.17.7 → v0.18.0 | **Bounded mailboxes / backpressure (RFC 056, Option A reject-only)**: +`MailboxPolicy`, +1 `RuntimeState` field (`mailboxPolicy`, init `.unbounded`), +1 `StepResult` ctor (`.backpressured` → 9), +1 `WellFormed` field (`mailbox_within_capacity`, vacuous under unbounded). `RuntimeOp` unchanged. **One proof fix** — `inject_ok_of_mailbox` gained `mailboxFull a mb = false` (always true under iotakt's unbounded policy). Behaviourally identical until a bound is set. |
| v0.18.0 → v0.19.0 | **Resource lifetime ledger (RFC 057)**: +`Henret.Resource.Ledger` (`ResourceId`/`ResourceState`/`ResourceRecord`), +2 `RuntimeState` fields (`resources`/`nextResourceId`), +3 `RuntimeOp` (`acquire`/`release`/`finalize` → 24), +1 `StepResult` ctor (`.acquired` → 10), +4 `WellFormed` fields (30–33). All vacuous for iotakt (never acquires resources). |
| v0.19.0 → v0.26.0 | RFC 057 thread + hardening: more `RuntimeOp` constructors (→ ~27); additive, no exhaustive-match break for iotakt. |
| v0.26.0 → v0.27.0 | **Actor-owned resources (RFC 091)**: `ResourceRecord.owner` `TaskId` → `ResourceOwner` sum; three task-keyed `WellFormed` fields generalised (old statements kept as compat corollaries); `status_irrel` → `runtimeStatus_irrel`; +`acquireActor` op (→ 28). iotakt references none of these names → no break. |
| v0.27.0 → v0.33.0 | Continued additive growth (`RuntimeOp` → 29) + release-engineering/governance/generated-doc waves; public theorem surface snapshotted at v0.30.0, additive-only since ("None yet" renamed/removed). No iotakt change. |
| v0.33.0 → v0.34.0 | **mdbook documentation migration only.** `Henret/` source is byte-identical to v0.33.0 (verified `diff -rq`); no model, proof, or `WellFormed` change. No iotakt change. |

`TaskState` (10 constructors) is byte-for-byte identical from v0.11.0
through v0.34.0. `StepResult` grew additively (8 → 10: `.backpressured`
v0.18, `.acquired` v0.19) and `WellFormed` grew (28 → 33 fields); iotakt
matches neither exhaustively, so the additions are inert.
`RuntimeState` gained two RFC 055 status fields (`actorStatus`,
`runtimeStatus`) at v0.17.0; both are `WellFormed`-irrelevant and are
populated by `RuntimeState.init` (running / all-active), so iotakt's
driver never observes a fired admission guard. The `inject` branch gained
an RFC 055 admission guard, mitigated by the strengthened
`inject_ok_of_mailbox` (see below). `Envelope` (3-field, RFC 033) is
unchanged. Every bump from
v0.11.0 onward required **zero** iotakt code changes to keep building; the
RFC 049 capabilities were adopted by choice, not necessity.

### Adopted in v0.15.0: failure and supervised restart (RFC 049)

`Iotakt.SchedConn` now models a connection actor that can fail and be
restarted by a supervisor — aligning the connection lifecycle with Henret's
supervision model:

- `ConnPhase.failed` (distinct from `.closed`) read from `TaskState.failed`.
- `SchedConn.fail` (`fail t`) — terminal failure, cleans up like cancel but
  lands in `.failed` so a supervisor can distinguish error from clean close.
- `SchedConn.restart` (`restartOne parent failed actor`) — a running
  supervisor restarts a failed connection into a fresh task, with provenance
  recorded in Henret's `restartOf` field (`restartOf new = some old`).

Verified end-to-end in the v0.8 test: spawn child → fail → supervised
restart, with fresh-id and provenance invariants checked against real
Henret semantics.

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
| `receiveUntil` timed parking | 040 | **Infrastructure verified** (v0.7 test); driver uses an equivalent wall-clock park/wake (`pollTimeoutMs` / `runStepAuto`) rather than literal `receiveUntil` |
| Selective receive | 041 | Available; iotakt is single-consumer-per-connection so not needed |
| Multi-worker bridge | 043 | Available; iotakt's driver is a single outer loop |
| Supervision restart | 049 | **Adopted** — `SchedConn.fail`/`restart`, `ConnPhase.failed` |
| Integration contract | 044 | **Published** in henret v0.12.1; this document is iotakt's consumer-side mirror |
| Lean-runtime bridge | 035/036 | Available; iotakt's driver remains the single outer loop, so not yet needed |
| Occurrence identity (`Envelope`) | 033 | Transparent — iotakt builds `Message`; Henret stamps occurrence ids |

### The `receiveUntil` opportunity (and what v0.7 actually did)

Henret's `receiveUntil (t, deadline)` parks a *running* task on its mailbox
with a deadline; `tick` or message delivery wakes it. iotakt verified this
infrastructure works (v0.7 test section D): issuing `receiveUntil` registers
a timer in `rt.timers`, sets `waitDeadline`, parks the task as
`.waitingTimed`, and `tick` at the deadline wakes it to `.ready`.

**However**, iotakt's connection "actors" are not Henret-*running* tasks —
the driver does the I/O and injects readiness into mailboxes; the Henret
task is never `running = some t` during the driver loop. So iotakt cannot
literally call `receiveUntil` on a connection without restructuring the
driver so connection actors are scheduled and run. That restructure is
deferred.

What v0.7 *did* adopt is the **timer-driven park/wake pattern** at the
driver level, using iotakt's own wall-clock deadlines rather than Henret
logical timers:

- `EventLoop.pollTimeoutMs` computes the `epoll_wait` timeout from the
  nearest connection idle deadline, returning `-1` (block indefinitely)
  when nothing is pending. An idle server now uses zero CPU instead of
  spinning on a fixed 100ms heartbeat.
- `EventLoop.runStepAuto` blocks exactly as long as the next deadline
  allows, then reaps idle connections (`reapIdle`).

Two clocks are deliberately kept separate:

1. **Henret logical time** (`rt.now`, `rt.timers`) — model ordering and the
   `receiveUntil`/`sleep`/`tick` semantics. iotakt's connection actors do
   not populate this today, so `nextDeadline rt` is empty in practice.
2. **iotakt wall-clock** (`Io.monoNs`) — real idle timeouts and the adaptive
   poll timeout.

A future RFC could unify these by mapping logical deadlines to wall-clock
when a connection actor genuinely runs `receiveUntil`.

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

---

## v0.17.7 → v0.34.0 adoption notes

Henret RFC 055 (v0.17.0) added orderly-shutdown **admission control**.
iotakt's impact was assessed against the three compiler-caught migration
triggers and one proof-level concern:

- **Exhaustive `RuntimeOp` match** — iotakt has none. ✓ no break.
- **Literal `RuntimeState` construction** — iotakt uses `RuntimeState.init`
  (`Loop.lean`); the +2 fields are populated automatically. ✓ no break.
- **Exhaustive `TraceEvent` match** — iotakt has none. ✓ no break.
- **Proof-level** — `inject` now rejects (`StepResult.invalid`, state
  unchanged) when `runtimeStatus ≠ .running` **or** `actorStatus a =
  .closed`. iotakt's `inject_ok_of_mailbox` (a standalone leaf theorem,
  no proof callers) was strengthened with two hypotheses
  (`runtimeStatus = .running`, `actorStatus a ≠ .closed`) so the existing
  waiter-queue case-split discharges the new guard.

The **v0.17.7 → v0.34.0** jump (17 minor versions; the v0.33 → v0.34 step
is henret mdbook-docs only, `Henret/` source byte-identical) crossed RFC 056
(bounded mailboxes), RFC 057 (resource ledger), RFC 091 (actor-owned
resources), and several release-engineering waves. Re-assessed against the
same triggers:

- **Exhaustive `RuntimeOp` match** — none (count grew 21 → 29). ✓ no break.
- **Exhaustive `StepResult` match** — none (grew 8 → 10: `.backpressured`,
  `.acquired`). iotakt only does equality checks (`= .ok`/`.invalid`). ✓
- **Literal `RuntimeState` construction** — still `RuntimeState.init`; the
  new fields (`mailboxPolicy`, `resources`, `nextResourceId`) populate
  automatically (unbounded policy, empty ledger). ✓ no break.
- **Renamed theorem names** (`status_irrel` → `runtimeStatus_irrel` at
  v0.27, pre-snapshot) and `ResourceRecord` refactor — iotakt references
  none. ✓ no break.
- **`ResourceState` name clash** — iotakt's `ResourceState` (fd lifecycle)
  lives in `Iotakt.Model` (no Henret import); Henret's new resource
  `ResourceState` is in a different namespace. ✓ no clash.
- **Proof-level** — RFC 056 added a third `inject` guard: after the RFC 055
  shutdown guards and the mailbox-exists check, a full mailbox returns
  `.backpressured`. `inject_ok_of_mailbox` gained a fourth hypothesis
  `mailboxFull a mb = false`. iotakt never configures a bound, so
  `mailboxPolicy` stays `.unbounded` and `mailboxFull` is always `false`;
  readiness occupancy is independently bounded by coalescing. (RFC 056 is
  Option A "reject-only" — the visible-rejection policy iotakt prefers over
  silent drop.)

**Why the guard never fires at runtime.** iotakt's driver starts from
`RuntimeState.init` (running, every actor `.active`) and never issues
`closeActor`, `shutdown`, or `stopWhenIdle` — the only ops that could
falsify the strengthened hypotheses. (iotakt's own `EventLoop.shutdown`,
RFC 037, is an IO-level graceful drain; it does **not** emit Henret's
`RuntimeOp.shutdown`.) The hypotheses therefore hold at every inject the
driver issues, so no readiness event is lost.

**Dependency reference.** As of this adoption the lakefile uses the
**CI-portable git require** on the published tag `"0.34.0"`; the manifest is
a git entry (rev `63f10f48`), so a clean checkout and the CI workflow build
with no vendoring. The vendored sibling tree remains a documented offline
override.

**Assurance.** Verified by full `lake build` (66/66, against the
GitHub-fetched Henret v0.34.0) and the 26-step CI
gate (333 checks, 14 suites): **77 theorems, 0 sorry/admit, 0 project
axiom**, matrix-honesty guard matches. Henret v0.34.0 itself: public theorem surface additive-only since the v0.30.0 snapshot (no renames/removals); zero project axioms.
