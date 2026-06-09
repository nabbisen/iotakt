# RFC 014: Proof, Trust, and Test Matrix

**Status:** Proposed  
**Milestone:** M5  
**Priority:** Critical  
**Primary layer:** Documentation and Verification

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

This RFC defines the formal claim taxonomy and required matrix for iotakt, classifying each correctness/security claim as PROVEN, TESTED, ASSUMED, or OUTSCOPE.

## Motivation

iotakt's credibility depends on honest claims. Some properties can be proven in Lean, some can only be tested against native platforms, some are assumptions about the OS, compiler, or Lean runtime, and some are out of scope. Without a mandatory matrix, documentation can easily overclaim and blur these categories.

## Goals

- Define proof/trust/test matrix document structure.
- List expected theorem inventory.
- Classify native claims accurately.
- Define CI gates for proofs/tests.
- Prevent overclaiming about OS, C, TCP, or Lean FFI behavior.

## Non-Goals

- Do not require proving native C code in v0.1.
- Do not prove TCP protocol correctness.
- Do not prove henejt HTTP behavior.
- Do not prove real-time latency or global liveness.

## External Design

The matrix is a required release artifact:

```text
Claim | Classification | Evidence | Module | RFC | Notes
```

Every RFC that creates a correctness claim must update the matrix.

## Data Model / Internal Design

Expected PROVEN candidates:

```text
registry uniqueness
closed terminality
no unknown injection
no stale injection
interest soundness
coalescing bound
deterministic fake replay
```

Expected TESTED candidates:

```text
non-blocking native behavior
errno mapping
epoll normalization
socket accept/read/write behavior
SIGPIPE prevention
cleanup behavior
```

## Lifecycle / Workflow

Documentation workflow:

```text
new claim introduced → classify in RFC → implement/prove/test → update matrix
                     → release checklist validates no unclassified claims
```

## Public API Impact

The public API docs must use the same classifications. Marketing/readme language must not call native I/O verified unless the matrix supports it.

## Native Boundary Impact

Native claims appear as TESTED/ASSUMED, never PROVEN in v0.1 unless a separate verification effort is introduced.

## Henret Integration Impact

Henret-related claims should cite or depend on Henret's own theorem/assumption classifications rather than restating them as iotakt proofs.

## Security Considerations

The matrix is a security document because it prevents false assurance. It must explicitly say TLS/authentication/OS correctness are out of scope.

## Proof Obligations

- The matrix itself is not a theorem, but theorem names must be linked once implemented.
- Proof targets from RFCs 002-007 and 013 must be represented.

## Test Obligations

- CI verifies Lean proof files compile.
- CI verifies fake tests and native tests according to platform.
- Release script/checklist verifies matrix exists and has no TBD critical claims.

## Trust / Assumption Changes

- Lean kernel trusted.
- Lean runtime/FFI trusted where native involved.
- C compiler and OS trusted/tested.
- POSIX semantics assumed/tested.
- Kernel bug freedom out of scope.

## Architecture Gaps

- Initial theorem names may change during implementation.
- Native test coverage can be platform-sensitive.
- Matrix drift is a governance risk.

## Acceptance Criteria

- Matrix document exists.
- All RFC claims are classified.
- Readme language matches matrix.
- CI gates proofs/tests according to classification.
- No v0.1 release with unclassified critical claims.

## Alternatives Considered

- Use informal documentation only: rejected because it invites overclaiming.
- Mark all native behavior assumed without tests: rejected because conformance testing is required.
- Attempt full C verification now: deferred as overengineering for v0.1.

## Open Questions

- Exact docs path; recommended `docs/proof-trust-test-matrix.md`.
- Whether theorem index is generated manually or by convention.

