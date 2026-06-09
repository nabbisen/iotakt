# RFC 015: Observability, Debugging, and Trace Format

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M5  
**Priority:** High  
**Primary layer:** Cross-cutting

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

This RFC defines a minimal model-oriented trace system for debugging, fake test comparison, and auditability without introducing a heavy logging dependency.

## Motivation

The most important iotakt decisions happen at boundaries: dropping an unknown event, rejecting a stale generation, coalescing duplicate readiness, or injecting a message. These events must be visible in tests and demos. A small structured trace format gives auditability without adding a production logging framework or leaking payload bytes.

## Goals

- Define trace event vocabulary.
- Support stale/unknown/coalesced/injected visibility.
- Support native error trace entries.
- Keep traces deterministic in fake tests.
- Avoid heavy logging framework dependency in v0.1.

## Non-Goals

- Do not implement production observability platform.
- Do not add structured logging dependencies unless justified.
- Do not log application payload bytes by default.
- Do not expose sensitive data in traces.

## External Design

Trace events should explain boundary decisions:

```text
registered, deregistered, closed, stale_drop, unknown_drop,
no_interest_drop, readiness_coalesced, readiness_injected,
native_error, timeout, interrupted, shutdown
```

Trace output is primarily for tests, demos, and architecture review.

## Data Model / Internal Design

```lean
inductive TraceEvent where
  | registered (key : FdKey) (owner : ActorId)
  | deregistered (key : FdKey)
  | closed (key : FdKey)
  | dropped (raw : RawFd) (reason : DropReason)
  | coalesced (key : FdKey) (kind : PendingKind)
  | injected (key : FdKey) (owner : ActorId) (event : IoEvent)
  | nativeError (context : String) (errno : IoErrno)
  | timeout
  | interrupted
  | shutdown
```

## Lifecycle / Workflow

Trace workflow:

```text
model transition → optional TraceEvent
fake driver run  → deterministic Trace list
native run       → Trace list plus platform-dependent native events
example/demo     → compact human-readable rendering
```

## Public API Impact

Debug helpers may expose trace rendering. Public stable API should not require users to depend on trace internals unless the project chooses to make trace format stable.

## Native Boundary Impact

Native wrappers surface errno/context to Lean; trace creation remains Lean-side where practical.

## Henret Integration Impact

Bridge emits injection/coalescing/drop traces around Henret operations. It should not inspect Henret private state for tracing.

## Security Considerations

Traces must not include application payload bytes by default. Raw fd/key/actor information is useful but may still be sensitive in production logs; tracing should be opt-in or debug-oriented.

## Proof Obligations

- Trace emission does not change model semantics.
- Fake trace output is deterministic for same inputs.
- Drop/injection trace corresponds to translator/bridge results.

## Test Obligations

- Expected trace for stale drop.
- Expected trace for duplicate coalescing.
- Expected trace for register/close lifecycle.
- Native error trace mapping.

## Trust / Assumption Changes

- Trace correctness is model-tested; native event ordering may vary.
- Trace rendering is not security-audited logging.

## Architecture Gaps

- Trace volume can grow under high event load.
- Public trace stability policy needs a decision.

## Acceptance Criteria

- TraceEvent type exists.
- Fake tests compare traces.
- Drop/coalescing/injection are traceable.
- No payload bytes logged by default.
- Debug rendering exists.

## Alternatives Considered

- Use println/logging only: rejected because tests need structured trace.
- Adopt full logging framework: rejected for v0.1 minimalism.
- No traces: rejected because boundary decisions become hard to audit.

## Open Questions

- Whether trace format is semver-stable or internal in v0.1.

