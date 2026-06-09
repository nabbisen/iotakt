# RFC 020: Future Optimizations and Advanced Features

**Status:** Future RFC  
**Milestone:** M8  
**Priority:** Low for v0.1  
**Primary layer:** Future Planning

## Document Control

- **Project:** iotakt
- **Language:** Lean 4 with an optional native C boundary
- **Primary stack position:** `henejt` → `iotakt` → `henret`
- **Design principle:** Lean-first model, explicit trusted boundary, no hidden async runtime
- **Date:** 2026-06-08

## Common Terminology

- **Raw fd:** the integer file descriptor returned by the host OS.
- **FdKey:** stable iotakt identity, composed of `raw_fd` and a monotonic generation.
- **Interest:** what iotakt asked the poller to observe, normally readability or writability.
- **Readiness:** a host hint that an operation may make progress; it is not a guarantee.
- **Registry:** the Lean-side state that maps active `FdKey`s to owner actors and interests.
- **Native boundary:** the optional C FFI layer that performs POSIX socket and poller calls.
- **Bridge:** the deterministic Lean layer that translates iotakt events into Henret operations/messages.

## Summary

This RFC records explicitly deferred optimizations and advanced features so they do not pollute the v0.1 design.

## Motivation

Many attractive features are deliberately not part of v0.1. Without a future-feature parking lot, they will keep reappearing inside core RFCs and make the first implementation heavier than necessary. This RFC records them while requiring a separate proof/trust/test analysis before any future promotion.

## Goals

- List future features without making them v0.1 requirements.
- Preserve pure model boundary for future changes.
- Define criteria for promoting a future item to an active RFC.
- Prevent accidental scope creep.

## Non-Goals

- Do not implement these features in v0.1.
- Do not design performance optimizations before baseline correctness.
- Do not introduce new trusted boundaries without separate RFCs.
- Do not commit to io_uring, IOCP, or TLS architecture now.

## External Design

Future candidates:

```text
recvInto / reusable buffer API
edge-triggered epoll
EPOLLONESHOT
send slicing and batching APIs
multi-driver or multi-threaded polling
io_uring research
Windows IOCP research
TLS boundary with henejt or separate library
DNS resolver boundary
advanced backpressure coordination with henejt
```

## Data Model / Internal Design

No active v0.1 model changes are introduced. Each future feature must later state whether it changes:

```text
FdKey model
lifecycle model
event vocabulary
coalescing semantics
native trust boundary
Henret bridge semantics
```

## Lifecycle / Workflow

Promotion workflow:

```text
future item → benchmark/user need/security need identified
            → dedicated RFC written
            → proof/trust/test impact assessed
            → implementation milestone assigned
```

## Public API Impact

No v0.1 public API impact except documenting that some optimizations are deferred. Avoid reserving too many names prematurely.

## Native Boundary Impact

Each future native feature introduces a new native boundary assessment. io_uring/IOCP are especially large and must not be treated as drop-in replacements.

## Henret Integration Impact

Multi-driver or threaded polling would significantly alter Henret integration and requires new determinism/concurrency analysis.

## Security Considerations

Future features must not weaken v0.1 safety defaults such as non-blocking, no stale injection, bounded readiness, and explicit partial-write handling.

## Proof Obligations

- No current proof obligations. Future RFCs must add/modify proof obligations explicitly.

## Test Obligations

- No current tests. Future RFCs must define benchmarks/conformance tests before implementation.

## Trust / Assumption Changes

- Future platform APIs will require new assumptions.
- Performance claims require measurement, not intuition.

## Architecture Gaps

- Performance bottlenecks are unknown before baseline implementation.
- Future feature parking lot may become stale.
- TLS/DNS boundaries may belong in separate projects rather than iotakt.

## Acceptance Criteria

- Deferred feature list exists.
- v0.1 scope explicitly excludes listed items.
- Promotion criteria are documented.
- No future item blocks v0.1 release.

## Alternatives Considered

- Design all future features now: rejected because it would overfit the first architecture.
- Ignore future needs entirely: rejected because some model compatibility choices matter now.
- Add Rust/native abstraction layer now for future backends: rejected for v0.1 minimalism.

## Open Questions

- Which optimization should be considered first after v0.1; likely kqueue or recvInto based on user need/benchmarks.

