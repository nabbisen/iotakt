# Proof, Trust, and Test Matrix

**iotakt v0.1 — RFC 014**

iotakt follows a four-level claim classification. Every correctness
claim must appear in exactly one category.

| Level | Meaning |
|-------|---------|
| **PROVEN** | A Lean 4 theorem; the kernel checked it. |
| **TESTED** | Not proven, but covered by executable tests (fake-poller or native). |
| **ASSUMED** | Accepted from OS, C compiler, or Lean runtime documentation. |
| **OUTSCOPE** | Outside iotakt's defined responsibility. |

---

## PROVEN

All theorems live next to the definitions they constrain in
`Iotakt/Model/`, with re-export aggregation in `Iotakt.Proofs`.
`inject_ok_of_mailbox` lives in `Iotakt.Bridge.Driver`.

### Registry and generation identity

| Claim | Location |
|-------|----------|
| `wf_empty` — the empty registry satisfies WellFormed | `Registry.lean` |
| `allocate_preserves_wf` — allocation preserves WellFormed | `Registry.lean` |
| `close_preserves_wf` — closing preserves WellFormed | `Lifecycle.lean` |
| `allocate_fresh_gen` — fresh generation is strictly greater than any prior current generation | `Registry.lean` |
| `allocate_is_current` — after allocation the new key is the current resolution for that raw fd | `Registry.lean` |
| `close_not_current` (= `close_terminal`) — after close, the key is no longer the current resolution | `Registry.lean` |
| `double_close_idempotent` — closing an already-closed key leaves the generation map unchanged | `Lifecycle.lean` |
| `resolveCurrent_sound` — `resolveCurrent` only returns keys registered as current | `Registry.lean` |
| `resolveCurrent_gen` — the resolved key's raw matches the query | `Registry.lean` |

### Translation: no unknown, no stale, owner and interest soundness

| Claim | Location |
|-------|----------|
| `translate_no_unknown` — an unresolvable raw fd yields `dropped unknownRawFd` | `Translate.lean` |
| `translate_unknown_not_injectable` — corollary: never injectable | `Translate.lean` |
| `translate_injectable_owner` — every injectable event targets the live registry owner of the current key | `Translate.lean` |
| `translate_readable_interest` — `readable` injectable ⇒ read interest registered | `Translate.lean` |
| `translate_writable_interest` — `writable` injectable ⇒ write interest registered | `Translate.lean` |
| `translate_injectable_live` — every injectable event's resource is live (not closed/closing) | `Translate.lean` |
| `translateKeyed_stale` — an event carrying a non-current key is dropped as stale | `Translate.lean` |
| `translateKeyed_closed_dropped` — after closing, `translateKeyed` on the old key drops | `Translate.lean` |

### Coalescing: at-most-one-pending flood bound

| Claim | Location |
|-------|----------|
| `step_delivers` — first delivery of a slot sets the pending flag | `Coalesce.lean` |
| `step_deliver_pending` — after delivery the slot is pending | `Coalesce.lean` |
| `step_coalesces` — a pending-while-pending slot is suppressed | `Coalesce.lean` |
| `step_twice_coalesced` — **the flood bound**: two consecutive steps on the same event without ack ⇒ second is `coalesced` | `Coalesce.lean` |
| `ack_clears` — ack clears exactly the matching slot | `Coalesce.lean` |
| `ack_preserves_other` — ack does not touch other slots | `Coalesce.lean` |
| `step_preserves_other` — coalescing one slot does not touch other slots | `Coalesce.lean` |
| `deliver_after_ack` — after ack, the same event delivers again (no deadlock) | `Coalesce.lean` |

### Lifecycle

| Claim | Location |
|-------|----------|
| `close_state_closed` — after close the entry state is `closed` | `Lifecycle.lean` |
| `registered_not_closed` — a freshly registered resource is live | `Lifecycle.lean` |

### Henret bridge integration

| Claim | Location |
|-------|----------|
| `inject_ok_of_mailbox` — when the owner mailbox exists, Henret `inject` always returns `.ok` (formal mitigation of Henret v0.6.0 inject precondition discrepancy) | `Bridge/Driver.lean` |
| `applyResult_unknown_unchanged` — unknown drop leaves the Henret runtime untouched | `Bridge/Driver.lean` |
| `deliverOne_no_mailbox` — if no mailbox, deliver does not mutate the runtime | `Bridge/Driver.lean` |
| `deliverOne_coalesced` — coalesced delivery does not mutate the runtime | `Bridge/Driver.lean` |
| `runPoll_interrupted_unchanged` — interrupted wait mutates nothing | `Bridge/Driver.lean` |
| `processEvents_nil` — empty event batch mutates nothing | `Bridge/Driver.lean` |

### Fake poller

| Claim | Location |
|-------|----------|
| `next_deterministic` — `FakePoller.next` is a pure function (replay determinism) | `Fake/Poller.lean` |
| `next_scripted` — `next` returns the scripted outcome at the cursor | `Fake/Poller.lean` |
| `next_advances` — `next` advances the cursor | `Fake/Poller.lean` |
| `next_exhausted` — past the end, `next` reports `timeout` | `Fake/Poller.lean` |

---

## TESTED

Covered by the deterministic fake-poller demo (`Main.lean`).

| Claim | Test scenario |
|-------|---------------|
| Unknown raw fd ⇒ `droppedUnknown`, runtime unchanged | scenario 3 |
| Stale generation ⇒ `droppedStale` via `translateKeyed` | scenario 4 |
| Post-close raw event ⇒ unknown drop (currentGen removed) | scenario 4 |
| Duplicate readiness ⇒ exactly one inject, second coalesced | scenario 2 |
| Readable with read interest ⇒ inject delivered | scenario 1 |
| Writable without interest ⇒ `droppedNoInterest` | scenario 5 |
| Writable after `enableWrite` ⇒ injectable | scenario 5 |
| EOF (fatal) bypasses interest filter ⇒ injectable | scenario 6 |
| Timeout ⇒ Henret `tick`, clock advances | scenario 7 |
| Interrupted wait ⇒ no mutation, `interruptedWait` trace | scenario 7 |
| Inject delivers `.ok` (not `.woke`), waiter added to readyQ | scenario 1 |
| Message waits in mailbox until re-receive (Mesa semantics) | scenario 1 |
| Re-issued `receive` consumes the delivered message | scenario 1 |

Native backend TESTED claims (v0.1 native build, not yet implemented):

| Claim |
|-------|
| Accepted fd is non-blocking |
| Accepted fd has close-on-exec |
| `recv` returns `wouldBlock` on exhausted non-blocking socket |
| `recv` returns EOF on peer close |
| Partial write is returned correctly |
| SIGPIPE does not terminate the process |
| EINTR classified correctly |
| `accept` burst limit respected |
| epoll deregistration before close takes effect |
| Sanitizer builds pass |

---

## ASSUMED

Accepted from OS, C compiler, or Lean runtime documentation.

| Claim | Source |
|-------|--------|
| Kernel readiness APIs behave according to platform docs (epoll, POSIX) | OS |
| `EAGAIN`/`EWOULDBLOCK` signal non-readiness, not error | POSIX |
| `EINTR` may be returned from blocking and non-blocking syscalls | POSIX |
| Raw fd reuse does not happen until the fd is `close`d | OS/kernel |
| C compiler correctly compiles the native shim | Toolchain |
| Lean 4 runtime allocation helpers are correct per FFI contract | Lean runtime |
| Lean 4 `Int.toNat` truncates negatives to 0 (documented behavior) | Lean std |
| Henret v0.6.0 `spawn` creates the owner mailbox if absent | Henret source (verified in review) |
| Henret v0.6.0 `inject` with existing mailbox returns `.ok` | **Formally proven** by `inject_ok_of_mailbox` (was ASSUMED; now PROVEN) |

---

## OUTSCOPE

Outside iotakt's defined responsibility.

| Claim | Reason |
|-------|--------|
| TCP delivery and ordering correctness | Kernel responsibility |
| TLS security | Higher-layer responsibility |
| HTTP protocol correctness | `jemmet` responsibility |
| Kernel correctness of epoll or kqueue | OS responsibility |
| C compiler correctness | Toolchain responsibility |
| Lean runtime memory manager correctness | Lean core responsibility |
| Production liveness under adversarial load | Application + OS responsibility |
| Global fairness between actors under arbitrary scheduling | Henret responsibility |

---

## Discrepancy log — Henret v0.6.0 integration

Three discrepancies were found between the Henret v0.6.0→iotakt handoff
document and the shipped henret source. See
`docs/henret-integration-notes.md` for full detail and mitigations.

| # | Handoff claim | Actual behavior | Mitigation |
|---|---------------|-----------------|------------|
| 1 | `inject` "always succeeds, creating mailbox if absent" | `inject` returns `.invalid` if mailbox absent | Bridge guards inject by checking `mailboxes owner`; proven by `inject_ok_of_mailbox` |
| 2 | Bootstrap trace shows `r2=.woke [0]` after inject | `inject` always returns `.ok`, never `.woke` | Demo uses `.ok`; Main.lean checks `r12 matches .ok` pattern |
| 3 | Woken waiters "prepended" to readyQ | Actually appended (`.readyQ ++ [w]`) | Ordering documented; no functional impact for iotakt |
