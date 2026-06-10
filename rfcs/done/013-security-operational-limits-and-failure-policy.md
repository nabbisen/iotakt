# RFC 013: Security, Operational Limits, and Failure Policy

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M5  
**Priority:** Critical  
**Primary layer:** Cross-cutting

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

This RFC defines iotakt's security posture, default limits, resource exhaustion controls, cleanup behavior, and failure handling policy.

## Motivation

Even though iotakt is a low-level boundary library, it still owns important reliability and security controls. Fd leaks, double close, stale event injection, SIGPIPE termination, blocking linger, unbounded accept loops, and mailbox readiness floods are all boundary-level failures. This RFC makes those controls explicit without pretending that iotakt is a sandbox, TLS layer, or authentication system.

## Goals

- Define fd leak, stale event, double-close, and mailbox-flood defenses.
- Define default operational limits.
- Define graceful and fatal failure paths.
- Define SIGPIPE and blocking linger policies.
- Clarify that iotakt is not a sandbox or TLS/authentication layer.

## Non-Goals

- Do not claim peer authentication or confidentiality.
- Do not implement TLS.
- Do not provide sandboxing against malicious native code.
- Do not guarantee global liveness under arbitrary hostile workloads.

## External Design

Security model:

```text
iotakt protects its own resource ownership and event translation boundaries.
iotakt does not protect application protocol semantics, TLS, authentication,
or OS/kernel correctness.
```

Default limits should exist even in a low-level library: max events per poll, max accepts per tick, max read bytes, max active connections if configured, and pending readiness bound.

## Data Model / Internal Design

```lean
structure Limits where
  maxEventsPerPoll : Nat
  maxAcceptsPerTick : Nat
  maxReadBytes : USize
  maxActiveResources : Option Nat
```

Failure classification:

```lean
inductive FailureKind where
  | recoverableWouldBlock
  | interrupted
  | peerClosed
  | nativeError
  | resourceLimitExceeded
  | invariantViolation
  | fatalBackendFailure
```

## Lifecycle / Workflow

Failure workflow examples:

```text
resource limit exceeded → reject accept/register → trace → optional actor notification
native init failure      → fail backend startup → no partial driver start
actor cancellation       → cleanup owned resources → trace each close result
shutdown                 → stop accepting → deregister/close → final trace
```

## Public API Impact

APIs should return structured failure results rather than throwing opaque strings where practical. Panic/fatal behavior is reserved for invariant violations or impossible native initialization states.

## Native Boundary Impact

Native layer must prevent SIGPIPE termination, enforce non-blocking, enforce close-on-exec, and avoid positive blocking linger by default. Native errors are surfaced to Lean typed results/traces.

## Henret Integration Impact

Henret actors receive structured close/error messages only through the bridge. Cleanup after actor termination must be explicit until automatic Henret finalizers exist.

## Security Considerations

Security-relevant defaults: no blocking syscalls, no raw fd identity, bounded readiness, bounded accepts, bounded read allocation, no retained native pointers, no background native mutation.

## Proof Obligations

- Pending readiness bound.
- Closed resources cannot receive modeled readiness injection.
- Double-close is invalid/no-op in model.
- Limit enforcement transitions do not corrupt registry.

## Test Obligations

- Limit exceeded scenarios.
- Graceful shutdown closes/deregisters resources.
- SIGPIPE prevention.
- Cancellation cleanup.
- Non-blocking enforcement.
- Double close.

## Trust / Assumption Changes

- OS/kernel behavior remains trusted/tested.
- Resource limits are library controls, not a full DoS-proof guarantee.
- Application protocols must provide their own authentication/TLS policies.

## Architecture Gaps

- Exact defaults need tuning after examples.
- Actor-finalizer integration depends on Henret evolution.
- Native linger behavior may differ across platforms.

## Acceptance Criteria

- Limits type and defaults exist.
- Failure taxonomy is documented.
- Security non-goals are explicit.
- Cleanup workflows are implemented/tested.
- Proof/trust/test matrix includes all security claims.

## Alternatives Considered

- No limits in low-level library: rejected because resource exhaustion is a boundary concern.
- Crash on any native error: rejected except for fatal initialization/invariant cases.
- Implement TLS in iotakt: rejected as wrong layer.

## Open Questions

- Default values for limits.
- Whether limit violations notify a supervisor actor or return to caller only.

