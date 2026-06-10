# RFC 011: Linux epoll Backend

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M4  
**Priority:** Critical for v0.1 native backend  
**Primary layer:** Iotakt.Native.Epoll

## Document Control

- **Project:** iotakt
- **Language:** Lean 4 with an optional native C boundary
- **Primary stack position:** `jemmet` → `iotakt` → `henret`
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

This RFC defines the Linux epoll backend, including epoll instance lifecycle, level-triggered default behavior, event mask normalization, timeout handling, and native tests.

## Motivation

Linux epoll is the first practical native poller backend for iotakt. It provides the v0.1 path from model and fake tests to real sockets. The backend must be designed so that epoll-specific flags and quirks are normalized before reaching the bridge; otherwise the pure model and jemmet integration will become Linux-shaped and harder to extend to kqueue later.

## Goals

- Implement epoll backend for v0.1 native Linux support.
- Use level-triggered mode by default.
- Normalize epoll flags into model events.
- Define register/modify/delete/wait wrappers.
- Handle EPOLLERR/EPOLLHUP policy explicitly.

## Non-Goals

- Do not implement edge-triggered epoll in v0.1.
- Do not implement EPOLLONESHOT in v0.1.
- Do not implement io_uring.
- Do not expose epoll flags to jemmet.

## External Design

The epoll backend is the first native poller. It must conform to `Iotakt.Model` vocabulary and the poller interface. It is an implementation detail behind the bridge.

Recommended v0.1 behavior:

```text
level-triggered epoll
max events per wait from DriverConfig
timeout provided by bridge
EINTR returned as interrupted
EPOLLERR/EPOLLHUP surfaced as fatal normalized events
```

## Data Model / Internal Design

```lean
structure EpollHandle where
  raw : Int

inductive PollCtlOp where
  | add | mod | del

structure EpollInterest where
  read  : Bool
  write : Bool
```

C-side epoll_event structs must be flattened before returning to Lean.

## Lifecycle / Workflow

Backend workflow:

```text
create epoll instance
register fd with interest mask
wait(timeout, maxEvents)
normalize returned flags
modify interest as actor output state changes
deregister before close
close epoll handle during shutdown
```

## Public API Impact

Public API impact should be minimal. Applications should not import `Iotakt.Native.Epoll` except in backend selection or tests.

## Native Boundary Impact

Native functions include epoll_create1, epoll_ctl add/mod/del, epoll_wait, and epoll fd close. Use CLOEXEC for epoll instance where available.

## Henret Integration Impact

Bridge consumes normalized results. It must not branch on epoll constants.

## Security Considerations

Level-triggered epoll plus coalescing prevents mailbox floods while avoiding edge-triggered drain obligations in v0.1. Limits on max events per wait are required.

## Proof Obligations

- No direct proof over epoll.
- Lean normalization wrapper maps flags into `IoEvent` according to table.
- Model proofs remain backend-neutral.

## Test Obligations

- Readable event using socketpair or loopback.
- Writable event when interest enabled.
- No event after deregister where reproducible.
- Timeout returns timeout.
- EINTR handling if practical.
- EPOLLHUP/EOF behavior where reproducible.

## Trust / Assumption Changes

- Assume Linux epoll semantics and headers.
- Assume native C wrapper faithfully reports flags.
- Backend behavior is TESTED.

## Architecture Gaps

- EPOLLERR may need SO_ERROR query policy.
- EPOLLRDHUP availability may need feature guards.
- Loopback tests can be timing-sensitive.

## Acceptance Criteria

- Epoll backend compiles on Linux native profile.
- Event normalization table exists.
- Basic readiness tests pass.
- No epoll constants leak into public event vocabulary.
- Deregister/close path is tested.

## Alternatives Considered

- Edge-triggered epoll: deferred for complexity.
- EPOLLONESHOT: deferred because coalescing handles v0.1 flood concern portably.
- io_uring: future research only.

## Open Questions

- Exact policy for EPOLLERR + getsockopt(SO_ERROR).
- Whether to include EPOLLRDHUP in v0.1 when available.

