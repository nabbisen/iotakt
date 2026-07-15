# Proof, Trust, and Test Matrix

**iotakt v0.11 — RFC 014 — henret v0.34.0**

iotakt classifies every correctness-relevant claim as PROVEN, TESTED,
ASSUMED, or OUTSCOPE. This is the project's central honesty artifact: it
states exactly what the Lean kernel checks, what executable tests cover,
what is taken on trust from the platform, and what is deliberately out of
scope.

| Class | Meaning |
|-------|---------|
| **PROVEN** | A Lean 4 theorem; the kernel checked it. |
| **TESTED** | Not proven, but covered by executable tests (fake-poller, native, or against real Henret). |
| **ASSUMED** | Accepted from OS, C compiler, or Lean runtime documentation. |
| **OUTSCOPE** | Outside iotakt's defined responsibility. |

**Corpus during R2 remediation:** 83 machine-checked theorems/lemmas across `Iotakt/`,
**no `sorry`, no `admit`, no project `axiom`**. The full proven core builds
with `lake build Iotakt.Proofs`. The CI gate runs **365 executable checks**
across the legacy 14 test suites, plus 11 RFC 066 returned-event checks, 36 RFC
070 address-aware listener checks, and the live server smoke tests.

---

## PROVEN

All theorems live next to the definitions they constrain; `Iotakt.Proofs`
re-exports them under one target. Counts below are by source file.

### Registry and generation identity (`Model/Registry.lean`, 14)

| Theorem | Property |
|---------|----------|
| `allocate_preserves_wf`, `close_preserves_wf` | the registry well-formedness invariant survives every modeled transition |
| `allocate_fresh_gen` | a newly allocated `FdKey` gets a strictly fresh generation |
| `close_not_current`, `double_close_idempotent` | closing is terminal; a closed raw fd no longer resolves to a current key, and double-close is a no-op |
| `translate_no_unknown`, `translateKeyed_stale` | unknown and stale-generation events are dropped before any actor message is constructed |
| `translate_injectable_owner`, `translate_injectable_live` | every injected event targets the *live* registry owner of the *current* key |
| `translate_readable_interest`, `translate_writable_interest` | readable/writable events inject only when the matching interest is registered |

### Translation and event vocabulary (`Model/Translate.lean` 9, `Model/Event.lean` 9, `Model/Interest.lean` 4, `Model/Fd.lean` 3)

Normalization is total and deterministic; interest soundness and the
no-stale/no-unknown guarantees compose through the translator.

### Coalescing: at-most-one-pending flood bound (`Model/Coalesce.lean`, 8)

| Theorem | Property |
|---------|----------|
| `step_twice_coalesced` | two readiness notifications for one fd/kind collapse to one pending item |
| `ack_clears` | acknowledging clears the pending bit |
| `deliver_after_ack` | progress is preserved — a fresh readiness after ack is delivered |

### Lifecycle (`Model/Lifecycle.lean`, 14)

Closed is terminal; deregistered resources do not translate to injected
readiness; active registered entries are in non-closed states.

### Henret bridge integration (`Bridge/Driver.lean` 7, `Bridge/Message.lean` 3)

| Theorem | Property |
|---------|----------|
| `inject_ok_of_mailbox` | when the owner mailbox exists, the runtime is running, the owner is not closed, **and the mailbox is not at capacity**, Henret `inject` returns `.ok` (never `.invalid`/`.backpressured`) — mitigates Henret's inject precondition (mailbox v0.6.0+, RFC 055 shutdown guard v0.17.0+, RFC 056 backpressure guard v0.18.0+) |
| `deliverOne_no_mailbox_pending_unchanged` | a missing mailbox does not consume the coalescing slot, so mailbox delivery remains eligible after the mailbox becomes available |

### Fake poller (`Fake/Poller.lean`, 4)

Deterministic replay: the same script yields the same trace, so the TESTED
scenarios below are reproducible.

---

## TESTED

Executable checks. The pure-model scenarios run with the deterministic
fake poller (no C); the native and lifecycle scenarios run against the real
Linux epoll backend and real Henret.

### Pure-model / fake-poller (`fake-demo`, 20 checks)

| Claim | Scenario |
|-------|----------|
| Unknown raw fd ⇒ dropped, runtime unchanged | 3 |
| Stale generation ⇒ dropped via `translateKeyed` | 4 |
| Post-close raw event ⇒ unknown drop (currentGen removed) | 4 |
| Duplicate readiness ⇒ exactly one inject, second coalesced | 2 |
| Readable with interest ⇒ delivered; writable without interest ⇒ dropped | 1, 5 |
| EOF (fatal) bypasses the interest filter ⇒ injectable | 6 |
| Timeout ⇒ Henret `tick`, clock advances; interrupted wait ⇒ no mutation | 7 |
| Inject delivers `.ok` (Mesa semantics; waiter appended to readyQ) | 1 |

### Native backend — **implemented** (Linux epoll; `native-test` 13, `v0.4-test` 31)

| Claim |
|-------|
| Accepted fd is non-blocking and close-on-exec |
| `recv` returns `wouldBlock` on an exhausted non-blocking socket |
| `recv` returns EOF on peer close; partial write returned correctly |
| SIGPIPE does not terminate the process (`MSG_NOSIGNAL`) |
| EINTR classified correctly; `accept` burst limit respected |
| epoll deregistration before close takes effect |
| FFI ownership contract (RFC 028): one `lean_dec` per arg per path; recvfrom double-free avoided |
| Throughput benchmark sustains ~250–400k req/s over socketpair (`benchmark`, 4) |

### Lifecycle, framing, and stabilization (v0.5 – v0.11, against real Henret v0.34.0)

| Claim | Suite (checks) |
|-------|----------------|
| Connection actor + stats; HTTP/1.0 round-trip | `v0.5-test` (36) |
| Router (path params, method match, 404); Gap 006 cancel-on-close | `v0.6-test` (32) |
| Adaptive poll timeout (idle = block, work = 0ms); idle reaping; `receiveUntil` | `v0.7-test` (21) |
| Chunked transfer-encoding; SchedConn scheduled lifecycle + **failure/restart (RFC 049)** | `v0.8-test` (44) |
| Body framing (Content-Length + chunked); `readFull`; handoff surface | `v0.9-test` (22) |
| **Request-size limits** (`.tooLarge`); `readFromBuffer` pipelining (no dropped requests) | `v0.10-test` (13) |
| **Connection limits / load shedding** (cap=1 admits ≤1 of 3 clients); **graceful shutdown** (drains connections + listeners) | `v0.11-test` (18) |
| **Explicit-ack coalescing** plus checked unknown/forged/invalid-range/wrong-kind/inactive authority and live raw-fd reuse isolation for `enableWrite`, `disableWrite`, `closeConnection`, `recvAck`, and `sendAck` | `v0.13-test` (75; `RFC064-AUTH-MATRIX-001`, `RFC064-FD-REUSE-001`) |
| Echo, multi-connection echo, live HTTP server+client, routing/streaming/upload/reference servers | server smoke tests |

---

## ASSUMED

Accepted from OS, C compiler, or Lean runtime documentation.

| Claim | Source |
|-------|--------|
| Kernel readiness APIs behave per platform docs (epoll, POSIX) | OS |
| `EAGAIN`/`EWOULDBLOCK` signal non-readiness, not error | POSIX |
| `EINTR` may be returned from blocking and non-blocking syscalls | POSIX |
| Raw fd reuse does not happen until the fd is `close`d | OS/kernel |
| C compiler correctly compiles the native shim | Toolchain |
| Lean 4 runtime allocation helpers are correct per FFI contract | Lean runtime |
| `clock_gettime(CLOCK_MONOTONIC)` (via `iotakt_mono_ns`) is monotonic | OS |
| Henret `spawn` creates the owner mailbox if absent (v0.6.0+, RFC 032) | Henret source (verified in review) |
| Henret `inject` with an existing mailbox returns `.ok` | **PROVEN** by `inject_ok_of_mailbox` |
| Henret `TaskState` (10) unchanged v0.11.0 → v0.34.0; `StepResult` (8 → 10) and `WellFormed` (28 → 33) grew additively; `RuntimeOp` 21 → 29 — iotakt matches none exhaustively; `RuntimeState` new fields populated by `.init`; resource ledger (RFC 057/091) unused; public theorem surface additive-only | Henret source + `docs/generated/` (diffed each bump) |

---

## OUTSCOPE

Outside iotakt's defined responsibility.

| Claim | Reason |
|-------|--------|
| TCP delivery and ordering correctness | Kernel responsibility |
| TLS security | Higher-layer responsibility (RFC 041 documents the boundary) |
| **HTTP server: routing, handler dispatch, keep-alive policy, serve loop** | **jemmet** — a separate project built on iotakt after v1.0 |
| Kernel correctness of epoll or kqueue | OS responsibility |
| C compiler / Lean runtime memory-manager correctness | Toolchain / Lean core |
| Production liveness under adversarial load | Application + OS responsibility |
| Global fairness between actors under arbitrary scheduling | Henret responsibility (its RFC 046 fairness layer is opt-in and conditional) |

iotakt provides the I/O-boundary *building blocks* a server consumes
(`readFull`, `readFromBuffer`, body framing, the `Iotakt.Server` surface);
it is not itself a server. The reference server (`examples/ReferenceServer.lean`)
is a demonstration consumer, not a shipped module.

---

## Discrepancy log — Henret integration

Three discrepancies between the original Henret v0.6.0 handoff document and
the shipped source were found, mitigated, and **re-verified to still hold
through v0.15.2** (the dependency surface is byte-identical from v0.11.0 on).
See `docs/henret-integration-notes.md` for full detail.

| # | Handoff claim | Actual behavior | Mitigation |
|---|---------------|-----------------|------------|
| 1 | `inject` "always succeeds, creating mailbox if absent" | returns `.invalid` if mailbox absent | bridge guards inject by checking the owner mailbox; **proven** by `inject_ok_of_mailbox`; iotakt always spawns (which creates the mailbox) before injecting |
| 2 | Bootstrap trace shows `.woke` after inject | `inject` always returns `.ok`, never `.woke` | demo + `Main.lean` assert `.ok` |
| 3 | Woken waiters "prepended" to readyQ | actually appended (`readyQ ++ [w]`) | ordering documented; no functional impact for iotakt |

RFC 049 (v0.15.0) added `TaskState.failed` and `fail`/`restartOne`; iotakt's
only `TaskState` match (`SchedConn.phaseOf`) has a catch-all and was extended
to model the new state, so the addition is non-breaking and now exercised by
`v0.8-test`.
