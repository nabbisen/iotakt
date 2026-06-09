# RFC 003: Resource Lifecycle Model

**Status:** Proposed  
**Milestone:** M1  
**Priority:** Critical  
**Primary layer:** Iotakt.Model

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

This RFC defines the pure resource lifecycle for listeners and streams. iotakt models ownership, registration, readiness, and closure; it does not model the full TCP state machine. Lifecycle modeling provides the foundation for cleanup safety, double-close prevention, and proof obligations around closed resources.

## Motivation

Low-level I/O bugs often come from lifecycle ambiguity: registering before non-blocking configuration, closing without deregistering, double-closing a reused fd, or delivering events after cleanup. These are not HTTP-layer concerns and should not be left to ad hoc native behavior. A precise Lean model can state the valid transitions and classify invalid transitions as no-ops, errors, or traces.

## Goals

- Define listener and stream lifecycle states.
- Define valid transitions for create, configure, register, accept, deregister, close, and cancel cleanup.
- Define close ordering and double-close policy.
- Define EOF/hangup as observed conditions, not full TCP state.
- Create proof targets for closed terminality and deregister safety.

## Non-Goals

- Do not model TCP states such as TIME_WAIT, FIN_WAIT, retransmission, congestion, or packet behavior.
- Do not define native syscall wrappers; RFC 009/RFC 012 own that.
- Do not define HTTP connection lifecycle.
- Do not define TLS shutdown semantics.

## External Design

Applications and henejt see resources as listener or stream references. They do not directly manage raw lifecycle ordering. iotakt provides operations that move resources through the model and, when native is enabled, through corresponding native calls.

The external lifecycle policy is:

```text
allocate → configure non-blocking/close-on-exec → bind/listen or accept
         → register interests → active events/read/write
         → deregister → close → terminal
```

`close` is idempotent at the model boundary only in the sense that repeated close attempts do not reactivate or mutate unrelated resources. A second close should be classified as invalid/no-op or a structured error, never as a native syscall on a possibly reused raw fd.

## Data Model / Internal Design

Representative transition vocabulary:

```lean
inductive LifecycleOp where
  | allocateListener (raw : RawFd) (owner : ActorId)
  | markConfigured (key : FdKey)
  | markListening (key : FdKey)
  | register (key : FdKey) (interests : InterestSet)
  | allocateAcceptedStream (raw : RawFd) (owner : ActorId)
  | observeEof (key : FdKey)
  | beginClosing (key : FdKey)
  | deregister (key : FdKey)
  | close (key : FdKey)
  | cancelOwner (owner : ActorId)

inductive LifecycleResult where
  | ok
  | invalid
  | alreadyClosed
  | unknownKey
```

The lifecycle model should be total: every operation returns a new state and a structured result. Invalid operations must not create partial mutations.

## Lifecycle / Workflow

Listener workflow:

```text
1. Create socket and receive raw fd.
2. Allocate FdKey and listener registry entry.
3. Configure non-blocking and close-on-exec.
4. Bind/listen.
5. Register readable interest for accept readiness.
6. On readable readiness, actor/driver calls accept.
7. Each accepted raw fd becomes a stream with a fresh FdKey.
8. Deregister and close listener during shutdown.
```

Stream workflow:

```text
1. Accepted raw fd becomes stream FdKey.
2. Configure non-blocking and close-on-exec before registration.
3. Register readable interest by default.
4. Enable writable interest only when pending output exists.
5. On EOF/hangup/error, notify owner and move toward closing.
6. Deregister before close in the model.
7. Close is terminal for that FdKey.
```

Actor cancellation cleanup:

```text
cancel actor → enumerate owned resources → deregister each active key
             → close each native fd if native is enabled
             → mark keys closed/tombstoned
```

## Public API Impact

Public API should expose lifecycle operations at a safe level:

```lean
def closeStream   : StreamRef → IotaktM CloseResult
def closeListener : ListenerRef → IotaktM CloseResult
def enableWrite   : StreamRef → IotaktM Unit
def disableWrite  : StreamRef → IotaktM Unit
```

Application code should not need to call raw `deregister` directly except in advanced/internal APIs.

## Native Boundary Impact

The native implementation should follow model ordering, but the model must also specify fallback behavior when native calls fail. For example, if deregister fails because the fd is already gone, model cleanup still moves to a safe terminal state with a trace. Native close must not be called twice for the same active model key.

## Henret Integration Impact

Resource ownership is actor-scoped. When an owner actor is cancelled or completed, iotakt must have a cleanup path. Whether cleanup is triggered by Henret supervision, explicit henejt code, or the driver loop must be clearly documented. v0.1 may require explicit cleanup calls if Henret does not yet provide automatic actor-finalizer hooks.

## Security Considerations

Lifecycle correctness protects against fd leaks, stale events, and cross-connection confusion. The most security-sensitive rules are:

- configure before register,
- deregister before native close where possible,
- never native-close a key that is already closed,
- never deliver readiness to a closed or closing resource unless it is a modeled final error/hangup notification.

## Proof Obligations

- Closed is terminal: no operation reactivates a closed key.
- Double close is invalid/no-op and does not call for a second modeled native close.
- Registered resources are not closed.
- Deregistered/closed resources do not receive modeled readiness injection.
- Owner cancellation cleanup removes or closes all resources owned by that actor in the model.

## Test Obligations

- Fake lifecycle sequence for listener create/register/close.
- Fake lifecycle sequence for accepted stream active/read/eof/close.
- Double close returns alreadyClosed or invalid without state corruption.
- Cancel owner cleans all owned keys.
- Native integration: close after deregister prevents further readiness events where reproducible.

## Trust / Assumption Changes

- Native close behavior and OS fd reuse are assumed/tested, not proven.
- Model lifecycle proves only iotakt state transitions, not kernel TCP state.
- Actor cancellation notification from Henret may be an integration assumption in v0.1.

## Architecture Gaps

- Automatic cleanup hooks depend on Henret integration maturity.
- Whether tombstones are retained for debugging/proofs or removed immediately remains an implementation choice.

## Acceptance Criteria

- Lifecycle states and transitions are implemented in pure Lean.
- Invalid lifecycle operations are total and non-corrupting.
- Deregister-before-close is the modeled normal path.
- Double-close behavior is deterministic.
- Owner cancellation cleanup is specified and testable.

## Alternatives Considered

- Model full TCP state: rejected as too broad and not provable from user-space socket readiness.
- Leave lifecycle to native code: rejected because stale/double-close behavior must be model-visible.
- Close immediately without deregister: rejected as normal path, though native fallback behavior may handle already-closed cases.

## Open Questions

- Exact representation of half-close/EOF in resource state versus event trace.
- Whether close result exposes native errno details publicly or only in traces.

