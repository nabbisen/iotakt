# RFC 034: Research Notes for io_uring, IOCP, and Multi-Poller Backends

**Status:** Research / Future RFC Parking Lot  
**Milestone:** M8+  
**Priority:** Low for v0.1  
**Primary layer:** Future Architecture Research  
**Project:** iotakt  
**Stack position:** `jemmet → iotakt → henret`  
**Date:** 2026-06-08

---

## Document Intent

This RFC belongs to the continuation set after the v0.1 core RFC batch. It is intentionally detailed enough to guide implementation later, but it must not silently expand the v0.1 release boundary unless its status explicitly says so.

The governing principles remain:

- pure Lean model first,
- optional native boundary,
- no hidden async runtime,
- no C-side application buffering,
- readiness is a hint rather than a guarantee,
- file descriptors are identified by `FdKey(raw_fd, generation)`, not by raw fd alone,
- proof/trust/test classification is mandatory for every correctness claim.

## Summary

This RFC records future research directions for io_uring, Windows IOCP, and multi-poller or multi-threaded architectures. It does not approve implementation.

## Motivation

Advanced I/O mechanisms may become relevant if iotakt grows beyond a reference socket bridge. They are not drop-in replacements for epoll/kqueue and would significantly alter native assumptions and possibly driver determinism.

## Goals

- Prevent advanced backend ideas from contaminating v0.1 scope.
- Identify what must be studied before any implementation RFC.
- Protect deterministic Henret integration assumptions.
- Document why these features are future research, not near-term requirements.

## Non-Goals

- Do not implement io_uring.
- Do not implement Windows IOCP.
- Do not add native polling threads.
- Do not promise cross-platform production async runtime behavior.

## External Design

Research topics:

```text
io_uring:
  completion queue semantics
  registered buffers/files
  cancellation model
  kernel version dependency

IOCP:
  completion-based model rather than readiness-based model
  Windows handle semantics
  overlapped I/O ownership

multi-poller:
  multiple native waiters
  deterministic merge of event streams
  actor affinity and mailbox injection ordering
```

Each item requires a dedicated RFC before implementation.

## Data Model / Internal Design

The existing model is readiness-oriented. Completion-based APIs may require a different event vocabulary:

```lean
inductive IoCompletion where
  | recvCompleted : FdKey -> ByteArray -> IoCompletion
  | sendCompleted : FdKey -> USize -> IoCompletion
  | acceptCompleted : FdKey -> FdKey -> IoCompletion
  | failed : FdKey -> IoErrno -> IoCompletion
```

This is intentionally not part of current iotakt.

## Lifecycle / Workflow

Promotion workflow:

```text
research note
prototype outside core
benchmark/security analysis
model impact analysis
dedicated RFC
experimental feature gate
```

## Public API Impact

No current API impact. Do not reserve public names that imply committed support.

## Native Boundary Impact

These backends greatly expand native trust assumptions. io_uring and IOCP may require native buffer ownership, kernel-specific queues, or completion lifecycle state. That conflicts with v0.1 simplicity and must be justified separately.

## Security Considerations

Completion-based and multi-threaded designs introduce cancellation, lifetime, and memory-safety risks. They also complicate denial-of-service analysis and deterministic ordering.

## Proof Obligations

Future proof obligations could include deterministic merge of completions, ownership of in-flight operations, cancellation safety, and no stale completion injection. None are active now.

## Test Obligations

Future tests would require platform-specific integration suites and stress tests. They are not part of current CI.

## Trust / Assumption Changes

All advanced backend claims are OUTSCOPE for v0.1 and FUTURE/RESEARCH until an implementation RFC exists.

## Architecture Gaps

The current readiness model may not generalize cleanly to completion APIs. Trying to force IOCP/io_uring into the same shape may be worse than defining a separate model layer.

## Acceptance Criteria

- Research topics are documented.
- They are explicitly excluded from v0.1/v0.2 unless promoted by RFC.
- Model-impact questions are listed.
- No implementation work is implied by this RFC.

## Alternatives Considered

Ignore future platforms: rejected because Windows/advanced Linux may matter later. Design full abstraction now: rejected as overengineering. Use a third-party async runtime: rejected for iotakt's proof-boundary identity.

## Open Questions

- Would completion APIs belong in iotakt or a sibling project?
- Can Henret support deterministic completion merging cleanly?
- Should Windows support be a separate project rather than an iotakt backend?
