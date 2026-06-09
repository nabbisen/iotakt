# RFC 016: kqueue Compatibility and BSD/macOS Backend Plan

**Status:** Proposed / Implementation Deferred  
**Milestone:** M6  
**Priority:** Medium for v0.1, High for v0.2  
**Primary layer:** Iotakt.Model and Future Iotakt.Native.Kqueue

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

This RFC ensures v0.1 model choices remain compatible with a future BSD/macOS kqueue backend, even though native kqueue implementation is deferred.

## Motivation

Although Linux epoll is the first native backend, the model should not become epoll-specific. BSD/macOS kqueue has different EOF and error semantics that must be anticipated now. This RFC protects the v0.1 model from choices that would force breaking changes when kqueue support is added later.

## Goals

- Analyze kqueue semantic requirements.
- Ensure normalized event vocabulary can represent EV_EOF and EV_ERROR.
- Prevent epoll-specific assumptions in model and public API.
- Define future acceptance criteria for kqueue backend.
- Record OpenBSD/macOS portability concerns.

## Non-Goals

- Do not require native kqueue implementation in v0.1.
- Do not emulate epoll on kqueue or kqueue on epoll.
- Do not expose kqueue flags publicly.
- Do not promise identical event timing across backends.

## External Design

The v0.1 model must remain kqueue-aware. This means EOF and error are explicit normalized events, backend flags are hidden, and bridge logic is backend-neutral.

Future backend modules:

```text
Iotakt.Native.Kqueue
Iotakt.Native.Kqueue.Normalize
```

## Data Model / Internal Design

Future kqueue mapping must handle:

```text
EVFILT_READ
EVFILT_WRITE
EV_EOF
EV_ERROR
filter-specific data
udata or ident handling policy
```

The model should not assume epoll's mask style. Normalized raw events are the common interface.

## Lifecycle / Workflow

Future workflow mirrors epoll:

```text
create kqueue
register filters
wait with timeout
normalize kevent entries
feed bridge
cleanup/deregister/close
```

Differences in EOF/error behavior are absorbed by normalization, not by henejt.

## Public API Impact

No immediate public API changes beyond preserving backend-neutral names. Applications should not know whether epoll or kqueue backs the poller.

## Native Boundary Impact

Native kqueue is deferred. This RFC constrains model/API choices now to avoid future breaking changes.

## Henret Integration Impact

Henret bridge remains identical because it consumes normalized `IoEvent`s.

## Security Considerations

BSD/macOS may reveal assumptions hidden by Linux-only testing. Future native tests must include EOF/error cases carefully.

## Proof Obligations

- Model backend-neutrality: no bridge theorem depends on epoll-specific flags.
- EOF/error vocabulary is expressive enough for kqueue normalization.

## Test Obligations

- v0.1 static/model review: no public epoll leakage.
- Future v0.2 tests: kqueue readable/writable/eof/error/timeout.

## Trust / Assumption Changes

- Assume kqueue semantics according to target OS documentation and tests once implemented.
- OpenBSD/macOS differences are expected and tested, not proven.

## Architecture Gaps

- Exact kqueue `udata` strategy later.
- macOS and OpenBSD differences may require conditional code.
- Build infrastructure for BSD/macOS native CI is future work.

## Acceptance Criteria

- Model has explicit EOF/error/hangup vocabulary.
- No public epoll-only API in v0.1.
- kqueue implementation checklist exists.
- Future RFC can add native backend without changing core model.

## Alternatives Considered

- Implement kqueue in v0.1: deferred to keep first release focused.
- Ignore kqueue until later: rejected because model choices made now can block it.
- Use a cross-platform event library: rejected as too heavy.

## Open Questions

- Whether OpenBSD or macOS should be first kqueue target.
- How to test kqueue in CI reliably.

