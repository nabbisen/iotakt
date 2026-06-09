---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 051: Windows IOCP Backend

## Summary

This RFC defines a post-v1 path for a Windows backend based on I/O Completion Ports (IOCP). IOCP is
not a small variation of epoll or kqueue. It is a completion-oriented API, while iotakt v1 is designed
around readiness-oriented event translation. Therefore, Windows support must be treated as a separate
backend family with a compatibility layer into the normalized iotakt model.

This RFC is future scope. It must not block the Unix-focused v1 release.

## Motivation

Long-term Lean ecosystem adoption may benefit from Windows support, especially for education,
experimentation, and developer machines. However, forcing IOCP into the v1 design would distort the
simple POSIX socket boundary and risk overcomplicating the initial proof model.

## Goals

- Define a feasible IOCP direction without committing v1 to Windows support.
- Preserve the normalized iotakt event vocabulary where possible.
- Identify where readiness and completion semantics diverge.
- Avoid contaminating the Unix FFI design with Windows-specific assumptions.
- Prepare a future `Iotakt.Native.Iocp` module boundary.

## Non-goals

- No Windows backend in v1.
- No emulation of epoll on Windows.
- No dependency on libuv or other broad cross-platform runtime libraries.
- No attempt to prove Windows kernel semantics.
- No generic async runtime abstraction.

## Semantic mismatch

Unix readiness model:

```text
poller says fd may be readable/writable
actor performs recv/send
operation may still would-block
```

IOCP completion model:

```text
actor posts an overlapped operation
kernel completes it later
completion reports result bytes/error
```

This means IOCP cannot be faithfully represented as only `IoReady`. A future model may need a
separate normalized event:

```lean
inductive IoEvent where
  | readable
  | writable
  | eof
  | hangup
  | error : IoErrno -> IoEvent
  | completed : OperationId -> CompletionResult -> IoEvent
```

Adding `.completed` would be a major model expansion and should occur only after v1.

## Proposed architecture

```text
Iotakt.Model
  existing readiness model
  future completion extension

Iotakt.Native.Iocp
  Windows socket setup
  IOCP handle creation
  overlapped operation posting
  completion retrieval

Iotakt.IocpBridge
  maps completions into Henret messages
```

Unlike epoll/kqueue, the IOCP backend may need native-side operation records because Windows requires
stable overlapped structures across asynchronous operation lifetime. This violates the v1 native
policy of no retained C state, so it requires a separate trust matrix and audit standard.

## Data model

```lean
structure OperationId where
  value : UInt64

inductive OperationKind where
  | recv
  | send
  | accept
  | connect

structure PendingOperation where
  opId : OperationId
  fdKey : FdKey
  kind : OperationKind
```

The generation check remains mandatory. A completion for an old `FdKey` must be dropped or reported
as stale according to the future model.

## Workflow

### Receive completion workflow

1. Actor asks backend to post receive operation.
2. Backend records `OperationId -> FdKey`.
3. IOCP returns completion later.
4. Bridge validates that the fd generation is still current.
5. Bridge injects completion message to owner actor.
6. Actor consumes result bytes or error.

## Security and safety considerations

- Native memory lifetime is much more complex than epoll/kqueue.
- Overlapped buffers must remain valid until completion.
- Cancellation and close races require explicit model treatment.
- Windows error codes require a separate normalized error map.

## Proof/trust/test classification

PROVEN candidates:

- Completion is delivered only if `OperationId` maps to current `FdKey`.
- Stale completion is not delivered to a new actor after fd/handle reuse.
- Pending operation registry uniqueness.

ASSUMED/TESTED:

- IOCP completion behavior.
- Native memory safety of overlapped operation records.
- Cancellation semantics.

## Acceptance criteria

- IOCP remains post-v1 until a completion model is accepted.
- The Unix readiness API is not weakened to accommodate Windows prematurely.
- A prototype must include stress tests for cancellation, close races, and stale completions.
- The proof/trust/test matrix clearly separates readiness and completion claims.
