# RFC 010: Buffer Ownership, Read Semantics, and Write Semantics

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M3  
**Priority:** Critical  
**Primary layer:** Iotakt.Native and Public API

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

This RFC defines read/write result types, ByteArray ownership policy, partial write behavior, and the v0.1 decision to use native-created Lean ByteArray results for receive operations.

## Motivation

Read/write APIs are deceptively simple, but they define one of the riskiest parts of the Lean/C boundary: memory ownership. v0.1 must prefer a contract that is easy to audit over a more aggressive performance optimization. It must also teach callers that non-blocking I/O produces normal outcomes such as would-block, EOF, interrupted calls, and partial writes.

## Goals

- Use Option A for v0.1 receive allocation.
- Forbid C-side retained buffers and ring buffers.
- Represent would-block, EOF, interrupted, partial write, and errors explicitly.
- Define maximum read size policy.
- Prepare future `recvInto` optimization without making it v0.1 scope.

## Non-Goals

- Do not implement reusable caller-provided mutable ByteArray receive in v0.1.
- Do not implement zero-copy or native ring buffers.
- Do not assume full writes.
- Do not treat EAGAIN as exceptional failure.

## External Design

v0.1 receive policy:

```text
C allocates one Lean ByteArray result using Lean runtime helpers,
performs exactly one non-blocking recv into that fresh object,
returns ownership immediately to Lean.
```

This does not mean native malloc/free or retained buffers. It means one short-lived result object per receive call, owned by Lean after return.

## Data Model / Internal Design

```lean
inductive ReadResult where
  | bytes (data : ByteArray)
  | wouldBlock
  | eof
  | interrupted
  | error (errno : IoErrno)

inductive WriteResult where
  | wrote (n : USize)
  | wouldBlock
  | interrupted
  | closed
  | error (errno : IoErrno)
```

`wrote n` may be less than the input size and is still success.

## Lifecycle / Workflow

Read workflow:

```text
Readable message → recv(key, maxBytes)
  → bytes data | wouldBlock | eof | interrupted | error
```

Write workflow:

```text
Writable message → send(key, bytes)
  → wrote n
       n == len → clear output / disable writable
       n < len  → retain suffix above iotakt / keep writable
     wouldBlock/interrupted/error handled by actor policy
```

## Public API Impact

```lean
def recv : SocketRef → USize → IotaktM ReadResult
def send : SocketRef → ByteArray → IotaktM WriteResult
```

Optional helpers `recvAndAck` and `sendAndAck` are specified by RFC 006.

## Native Boundary Impact

Native receive may use Lean runtime allocation helpers but must not retain the result pointer. Native send treats ByteArray as read-only and must prevent SIGPIPE termination according to platform policy.

## Henret Integration Impact

Actors/henejt own protocol buffers and unsent suffixes. Henret receives only messages, not native pointers or C buffers.

## Security Considerations

Read size limits prevent accidental memory allocation abuse. Partial write handling prevents silent truncation. SIGPIPE prevention is mandatory to avoid process termination by peer behavior.

## Proof Obligations

- Read/write result types make wouldBlock and partial write explicit.
- No model claim says readiness guarantees bytes or full write.
- Ack helpers preserve coalescing invariants when used correctly.

## Test Obligations

- would-block read on drained non-blocking socket.
- EOF after peer close.
- partial write where reproducible or simulated.
- SIGPIPE does not terminate process.
- max read size enforced.

## Trust / Assumption Changes

- Assume Lean ByteArray allocation helpers behave correctly.
- Assume OS recv/send follow documented non-blocking semantics.
- Native buffer use is TESTED and reviewed, not proven.

## Architecture Gaps

- Current Lean FFI helper details may require implementation research.
- Option B may be needed later for performance but is deferred.

## Acceptance Criteria

- ReadResult and WriteResult are implemented.
- v0.1 recv does not mutate caller-provided ByteArray.
- send handles partial writes.
- EAGAIN/EWOULDBLOCK map to wouldBlock.
- EINTR maps to interrupted or documented retry policy.

## Alternatives Considered

- Option B recvInto first: rejected for v0.1 due to sharper uniqueness/unsafe contract.
- Native ring buffers: rejected due to C state and lifecycle complexity.
- Treat partial write as error: rejected because it is normal socket behavior.

## Open Questions

- Exact maximum default read size.
- Whether EINTR should be returned or internally retried for each syscall; returning `interrupted` is recommended initially.

