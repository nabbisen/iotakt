---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 058: Advanced Buffer Pool and Memory Strategy

## Summary

This RFC defines a post-v1 path for reusable receive buffers, buffer pools, and advanced memory
strategies. v1 intentionally favors the most auditable contract: receive returns a fresh Lean-owned
`ByteArray`, write borrows a read-only `ByteArray`, and the native layer retains no payload pointers.
After v1, performance-sensitive users may want buffer reuse. This RFC defines how to approach that
without weakening safety claims.

## Motivation

Fresh allocation per receive is simple but may be expensive under high connection counts. RFC 022
introduced `recvInto` as an optimization theme. This post-v1 RFC generalizes the topic into a memory
strategy that can support buffer pools while keeping ownership explicit and testable.

## Goals

- Allow future buffer reuse for performance.
- Preserve no-retained-native-pointer discipline.
- Make uniqueness and mutation contracts explicit.
- Keep advanced memory APIs opt-in.
- Provide fallback to v1 fresh-buffer APIs.

## Non-goals

- No mandatory buffer pool.
- No C-side application ring buffers by default.
- No native ownership of Lean payload buffers across event-loop turns.
- No zero-copy receive promise.
- No unsafe optimization in stable APIs without benchmarks and audit.

## API layers

### Stable simple API

```lean
recv : FdKey -> maxBytes : USize -> IO ReadResult
send : FdKey -> bytes : ByteArray -> IO WriteResult
```

This remains the baseline.

### Opt-in reusable buffer API

```lean
structure MutableBufferToken where
  id : UInt64
  capacity : USize

recvInto : FdKey -> MutableBufferToken -> IO RecvIntoResult
```

The actual representation must be chosen carefully. It may be Lean-managed, native-managed, or hybrid,
but each direction changes the trust boundary.

## Design options

### Option A: Lean-managed mutable ByteArray

Lean owns the buffer. Native fills it during one syscall and returns immediately. Requires a clear
uniqueness/mutation contract.

### Option B: native-managed fixed buffers

Native allocates buffers and exposes tokens. This can be performant but violates the v1 no-malloc/no-C-state
policy and requires explicit lifetime management.

### Option C: actor-local Lean buffer pool

Actors keep reusable Lean buffers and pass them to `recvInto`. This may be the best balance if Lean
FFI mutation can be made auditable.

Recommendation: prefer Option C first, with Option A-style FFI mutation rules. Avoid Option B unless
native backend design has already matured through io_uring or IOCP work.

## Ownership contract

Any `recvInto` API must state:

- caller owns the buffer token before call,
- native code may write only during the call,
- native code must not retain the pointer,
- result reports actual byte length,
- caller regains exclusive ownership after return,
- buffer content beyond actual length is unspecified and must not be read.

## Result model

```lean
inductive RecvIntoResult where
  | read : bytesRead : USize -> RecvIntoResult
  | wouldBlock
  | eof
  | interrupted
  | error : IoErrno -> RecvIntoResult
```

## Workflow

1. Actor obtains or creates reusable buffer.
2. Readiness message arrives.
3. Actor calls `recvInto fdKey buffer`.
4. Actor processes only the valid prefix.
5. Actor returns buffer to actor-local pool or keeps it for next receive.

## Proof/trust/test classification

PROVEN candidates:

- Buffer pool state transitions preserve unique ownership at the model level.
- A buffer checked out to a receive operation is not simultaneously available in the pool.

ASSUMED/TESTED:

- Native writes do not exceed capacity.
- Native does not retain pointers.
- Lean object uniqueness assumptions are valid for the chosen implementation.

## Benchmarks required

This RFC must not be implemented merely because it seems faster. Required benchmarks:

- small reads under many connections,
- large reads,
- allocation pressure,
- tail latency under load,
- comparison with v1 fresh-buffer API.

## Security considerations

- Buffer reuse can leak stale data if valid lengths are mishandled.
- Debug logs must not dump unused buffer tail.
- Returned byte length must be treated as authoritative.
- Optional zeroing policy may be needed for sensitive data, but default zeroing may be expensive.

## Acceptance criteria

- Fresh-buffer API remains supported.
- `recvInto` is opt-in and feature-gated until stable.
- Native tests include capacity-bound checks and fault injection.
- Benchmarks justify promotion from experimental to stable.
