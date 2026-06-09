# RFC 006: Readiness Coalescing and Mailbox Flood Prevention

**Status:** Proposed  
**Milestone:** M2  
**Priority:** Critical  
**Primary layer:** Iotakt.Model and Iotakt.HenretBridge

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

This RFC defines readiness coalescing. iotakt must prevent repeated poller readiness hints from producing unbounded duplicate mailbox messages for the same resource and interest. iotakt buffers readiness bits, not application bytes.

## Motivation

Level-triggered pollers may report the same readiness condition repeatedly. If iotakt injects every repeated `Readable` or `Writable` hint into a Henret mailbox, a slow actor or persistent writable socket can cause mailbox growth unrelated to application-level work. Coalescing gives a simple, provable bound.

## Goals

- Define pending readiness state keyed by `FdKey + event kind`.
- Suppress duplicate readiness messages while one is pending.
- Define acknowledgement/clear policy.
- Define writable interest behavior for backpressure.
- Prove at-most-one pending readiness per key/event kind.

## Non-Goals

- Do not buffer application bytes.
- Do not implement HTTP output queues.
- Do not guarantee global fairness or throughput under hostile workloads.
- Do not implement edge-triggered epoll semantics in v0.1.

## External Design

The external behavior is:

```text
If Readable(key) is already pending, another Readable(key) is coalesced.
If Writable(key) is already pending, another Writable(key) is coalesced.
EOF/hangup/error may follow separate fatal-event policy.
The actor acknowledges readiness after attempting the corresponding operation.
```

Coalescing must not hide fatal closure/error notifications. However, repeated fatal notifications should still be bounded by lifecycle transition to closing/closed.

## Data Model / Internal Design

Representative model:

```lean
inductive PendingKind where
  | readable
  | writable
  | eof
  | hangup
  | error
  deriving DecidableEq, Hashable, Repr

structure PendingKey where
  fd   : FdKey
  kind : PendingKind
  deriving DecidableEq, Hashable, Repr

structure CoalesceState where
  pending : Std.HashSet PendingKey
  deriving Repr

inductive CoalesceResult where
  | deliver (ev : OwnerEvent)
  | coalesced (ev : OwnerEvent)
```

Recommended v0.1 policy: explicit acknowledgement exists in the model, and helper APIs combine `recv/send` with acknowledgement for ergonomic application use.

## Lifecycle / Workflow

Coalescing workflow:

```text
1. Translator produces OwnerEvent(owner, key, event).
2. Bridge maps event to PendingKind.
3. If PendingKey is absent, insert it and inject message.
4. If PendingKey is present, emit coalesced trace and do not inject.
5. Actor receives message and attempts read/write/close handling.
6. Actor/helper acknowledges the pending key.
7. Future readiness can be delivered again.
```

Writable backpressure workflow:

```text
1. Actor has no pending output → write interest disabled.
2. Actor queues output → enable write interest.
3. Writable message delivered → actor sends as much as possible.
4. Partial write → retain suffix and keep write interest.
5. All output flushed → disable write interest and ack writable.
```

## Public API Impact

Recommended APIs:

```lean
def ackReady      : SocketRef → IoEvent → IotaktM Unit
def recvAndAck    : SocketRef → USize → IotaktM ReadResult
def sendAndAck    : SocketRef → ByteArray → IotaktM WriteResult
def enableWritable  : SocketRef → IotaktM Unit
def disableWritable : SocketRef → IotaktM Unit
```

The combined helpers reduce user mistakes while preserving explicit model transitions.

## Native Boundary Impact

Native code does not coalesce. It reports events. Coalescing is a Lean-side model/bridge responsibility.

## Henret Integration Impact

Coalescing happens before Henret message injection. Therefore, the Henret mailbox receives at most one pending readiness message per key/kind until acknowledgement. This provides a clean property without depending on Henret mailbox internals beyond send/inject behavior.

## Security Considerations

Mailbox flood prevention is a reliability/security control. Without it, a peer or normal writable socket state could cause unbounded memory growth. Coalescing does not replace resource limits, but it prevents a basic class of readiness amplification.

## Proof Obligations

- Coalescing bound: at most one pending readiness item per `FdKey + PendingKind`.
- Duplicate event does not create an additional injected message while pending exists.
- Acknowledgement removes only the matching pending key.
- Coalescing does not alter registry ownership or lifecycle state.

## Test Obligations

- Two identical readable events before ack produce one injected message and one coalesced trace.
- Ack readable then another readable produces a second message.
- Readable and writable for same key are tracked independently.
- Writable interest disabled prevents writable injection except fatal policy.

## Trust / Assumption Changes

- Assume Henret mailbox append behavior follows its own model/proofs.
- Coalescing proves only iotakt's pending set bound, not whole-system memory boundedness.

## Architecture Gaps

- Ack discipline may be misused by applications; helper APIs mitigate this.
- Fatal events need careful policy so they are not accidentally hidden by normal readiness coalescing.

## Acceptance Criteria

- Pending readiness state exists in model.
- Bridge uses coalescing before injection.
- Ack/clear semantics are implemented and tested.
- Writable interest workflow is documented.
- No application byte buffering is introduced in iotakt.

## Alternatives Considered

- Inject every readiness event: rejected due to mailbox flood risk.
- Use EPOLLONESHOT for v0.1 instead of model coalescing: rejected because model/fake backend still needs a portable policy.
- Clear pending automatically on message delivery: rejected because delivery is not the same as actor operation attempt.

## Open Questions

- Should ack happen before or after syscall attempt in helper functions? Recommended: after attempt returns.
- Should fatal events have separate pending keys or force lifecycle transition immediately?

