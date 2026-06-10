# Architecture Gap Register

**iotakt v0.1 — RFC 019**

This document tracks architecture gaps discovered during design and
implementation. Every gap is classified by status and appears in the
proof/trust/test matrix (ASSUMED, TESTED, or OUTSCOPE) where it affects
a correctness claim.

---

## Gap 001 — Henret inject precondition: mailbox must exist

**Status:** Mitigated in v0.1  
**Severity:** High (silent data loss if unmitigated)  
**Source:** Henret v0.6.0 implementation vs handoff document

### Description

Henret v0.6.0's `inject a m` returns `.invalid` and does nothing when
actor `a` has no mailbox. The v0.6.0→iotakt handoff document incorrectly
states that inject "always succeeds, creating the mailbox if absent".

If the iotakt bridge calls `inject` before the owner actor is spawned,
every readiness notification is silently dropped — no error, no trace.

### Mitigation

`Iotakt.Bridge.Driver.deliverOne` guards every inject with a mailbox
check. `inject_ok_of_mailbox` formally proves that the guard guarantees
`.ok` (see `Iotakt/Bridge/Driver.lean`). The bridge records
`droppedNoMailbox` in the trace when the guard fires, making drops
visible rather than silent.

### Open question for Henret maintainer

Is auto-create-on-inject the intended future behavior? If yes, the guard
can be removed when Henret ships it. If no, update the handoff document
to match the shipped semantics.

---

## Gap 002 — Henret inject returns .ok, not .woke

**Status:** Mitigated in v0.1  
**Severity:** Low (documentation error, no functional impact)  
**Source:** Henret v0.6.0 handoff bootstrap trace

### Description

The handoff bootstrap trace shows `r2 = .woke [0]` after an inject call.
The shipped code and Henret's own `Main.lean` scenario 7 both confirm
inject always returns `.ok` regardless of whether it woke a waiter.

### Mitigation

The bridge uses only the first element of Henret's step result (the new
runtime state) and never pattern-matches the result tag. No functional
impact.

---

## Gap 003 — Woken waiters appended to readyQ, not prepended

**Status:** Accepted for v0.1  
**Severity:** Negligible (FIFO is correct behavior)  
**Source:** Henret v0.6.0 handoff

### Description

The handoff states woken tasks are prepended to `readyQ` for priority.
The code appends (`readyQ ++ [w]`), consistent with FIFO fairness.

### Mitigation

FIFO is correct for actor-model scheduling. No iotakt action required.
Handoff document error only.

---

## Gap 004 — ActorId allocation API not specified

**Status:** Open (deferred to native integration milestone)  
**Severity:** Medium  
**Source:** RFC 012 open question

### Description

iotakt must spawn an actor for each accepted connection to create its
mailbox before injecting. The Henret API for allocating ActorIds (distinct
from TaskIds) is not documented in the handoff. It is unclear whether the
application manages the ActorId namespace or whether Henret provides a
next-id counter.

### Mitigation plan

Block on the Henret maintainer answering open question #1 in
`docs/henret-integration-notes.md`. In the meantime, the fake demo
manages ActorId manually (actor 7 in the example).

---

## Gap 005 — Henret RFC 033 (richer Message envelope) not yet shipped

**Status:** Accepted for v0.1  
**Severity:** Low (lossy codec is functional)  
**Source:** Bridge design, RFC 007

### Description

Henret's current `Message = { id : Nat, payload : Nat }` is a minimal
envelope. iotakt encodes readiness as `id = raw_fd.toNat`, `payload =
event bitmask`. This loses the fd generation (iotakt uses `FdKey(raw,
gen)` for stale-event safety) — but since the actor knows its own key,
the generation travels implicitly.

### Mitigation

Single-file update `Iotakt/Bridge/Message.lean` when Henret RFC 033
ships. Isolated behind `encodeOwnerEvent`.

---

## Gap 006 — Henret actor lifecycle notification not available

**Status:** Accepted for v0.1  
**Severity:** Medium  
**Source:** RFC 003, RFC 007

### Description

When an actor owning an fd terminates, iotakt needs to deregister and
close that fd. Henret v0.6.0 does not currently emit lifecycle
notifications (task completion/cancellation events) to external
observers. The iotakt bridge cannot automatically detect actor
termination.

### Mitigation

v0.1 requires explicit ownership: application code must call `closeFd`
before allowing an actor to complete. A future Henret RFC that adds
lifecycle hooks can be wired into the bridge driver without model
changes.

---

## Gap 007 — Native backend: single-threaded only

**Status:** Accepted for v0.1  
**Severity:** Accepted (by design)  
**Source:** RFC 001, RFC 009

### Description

The v0.1 driver loop is single-threaded. A single `epoll_wait` blocks
the entire process during the poll phase. Multi-threaded polling
(multiple driver threads, io_uring, Windows IOCP) is explicitly deferred
to v0.2+.

### Mitigation

Single-threaded epoll is correct and sufficient for the Henret actor
model in v0.1. RFC 020 records multi-threaded and io_uring paths.

---

## Gap 008 — kqueue backend deferred

**Status:** Accepted for v0.1 (model-compatible)  
**Severity:** Low  
**Source:** RFC 016

### Description

The BSD/macOS kqueue backend is deferred to v0.2. The v0.1 pure model
uses kqueue-aware event vocabulary (`IoEvent.eof` distinct from
`IoEvent.hangup`, `error` separate from generic error) to avoid locking
in epoll semantics. The model can accept a kqueue backend without
changes.

### Mitigation

RFC 016 tracks the compatibility constraints. The fake poller can
exercise kqueue-specific scenarios (EV_EOF, EV_ERROR) today.

---

## Gap 009 — ByteArray FFI allocation: one malloc per recv

**Status:** Accepted for v0.1  
**Severity:** Low (correctness first)  
**Source:** RFC 010, native/iotakt_io.c

### Description

Option A receive allocates a Lean ByteArray (via `lean_alloc_sarray`) for
every recv syscall, even for small reads. For high-connection-count
workloads, allocation pressure may be measurable.

### Mitigation

Benchmarks first (RFC 025). If allocation is a bottleneck, RFC 010 §
"Future Buffer Optimization" defines `recvInto` with a reusable
buffer. Not introduced until measurements justify it.

---

## Gap 010 — Backpressure beyond readiness coalescing

**Status:** Accepted for v0.1  
**Severity:** Medium  
**Source:** RFC 006, RFC 013

### Description

iotakt prevents readiness-message floods via coalescing. It cannot
prevent an actor from accumulating unbounded outgoing data in its own
buffers if the remote peer is slow. Application-level backpressure
(write interest enable/disable, jemmet flow control) is the actor's
responsibility.

### Mitigation

Documented: actors should disable write interest when output is drained.
jemmet RFC (future) should define protocol-level backpressure policy.

---

## Summary

| Gap | Severity | Status |
|-----|----------|--------|
| 001 Inject precondition | High | **Mitigated** (proven) |
| 002 inject returns .ok | Low | **Mitigated** |
| 003 waiter ordering | Negligible | **Accepted** |
| 004 ActorId allocation API | Medium | **Open** |
| 005 RFC 033 envelope | Low | **Accepted** |
| 006 Actor lifecycle notification | Medium | **Accepted** |
| 007 Single-threaded only | Accepted by design | **Accepted** |
| 008 kqueue deferred | Low | **Accepted** |
| 009 ByteArray per recv | Low | **Accepted** |
| 010 Application-level backpressure | Medium | **Accepted** |
