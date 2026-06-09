---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 056: io_uring Backend Adoption

## Summary

This RFC converts the earlier io_uring research theme into a possible post-v1 implementation path.
io_uring can improve Linux I/O performance, but it introduces completion queues, shared ring memory,
operation submission state, kernel-version variability, and a much more complex trust boundary than
epoll. Therefore, io_uring must be a post-v1 experimental backend until its model and native safety
contract are mature.

## Motivation

Linux deployments may benefit from io_uring for high-throughput servers, especially if future iotakt
adds file transfer or more complex I/O patterns. However, adopting io_uring too early would undermine
iotakt's v1 simplicity and auditability.

## Goals

- Define a safe adoption path for io_uring after v1.
- Distinguish completion semantics from readiness semantics.
- Preserve fd generation and stale completion rejection.
- Keep io_uring experimental until native memory and kernel-version risks are understood.

## Non-goals

- No io_uring in v1.
- No replacement of epoll as the default Linux backend initially.
- No dependency on a large runtime library.
- No claim that io_uring behavior is formally verified.

## Semantic model

Like IOCP, io_uring is completion-oriented. A future model may need:

```lean
structure SubmissionId where
  value : UInt64

inductive CompletionResult where
  | ok : bytesOrStatus : Int -> CompletionResult
  | canceled
  | error : IoErrno -> CompletionResult
```

The bridge must validate:

```text
completion.submissionId -> current FdKey -> owning actor
```

A completion for a stale fd generation must not be delivered to a new resource owner.

## Native boundary

io_uring native code may need to manage:

- ring setup and teardown,
- submission queue entries,
- completion queue entries,
- user data tokens,
- registered buffers or files if later enabled,
- cancellation and close coordination.

This is significantly more native state than v1 epoll. A separate native audit checklist is required.

## Backend modes

### Minimal mode

Use io_uring only for poll-like operations or simple recv/send submissions. This limits complexity but
may not provide major gains.

### Full completion mode

Use submitted recv/send operations and deliver completions to actors. This requires the expanded
completion model.

Recommendation: start with minimal mode only for experiments; do not promote to stable unless the
full semantics are clearly justified.

## Workflows

### Submitted receive

1. Actor requests receive operation.
2. Backend assigns `SubmissionId` and associates it with `FdKey`.
3. Backend submits operation to io_uring.
4. Completion arrives.
5. Bridge checks `SubmissionId` and generation.
6. Actor receives completion message.

### Cancellation

Close/cancel must handle completions that arrive after cancellation. The model must explicitly allow
stale/canceled completions to be dropped or reported according to policy.

## Security and reliability risks

- Kernel-version-specific behavior.
- Shared ring memory misuse.
- Complex cancellation semantics.
- Buffer lifetime bugs.
- Difficult fuzzing compared to epoll.

## Proof/trust/test classification

PROVEN candidates:

- Submission id uniqueness.
- Completion-to-current-generation validation.
- Canceled/stale completion non-delivery.

ASSUMED/TESTED:

- Kernel io_uring behavior.
- Native ring memory management.
- Correct mapping of completion result codes.

## Acceptance criteria

- io_uring remains experimental until separate promotion RFC.
- Epoll remains the default stable Linux backend.
- Completion model extension is accepted before full completion mode.
- Stress tests cover cancellation, close races, stale completion, and kernel unsupported fallback.
