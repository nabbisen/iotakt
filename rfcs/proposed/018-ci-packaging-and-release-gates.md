# RFC 018: CI, Packaging, and Release Gates

**Status:** Proposed  
**Milestone:** M7  
**Priority:** High before release  
**Primary layer:** Project Operations

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

This RFC defines build profiles, CI matrix, packaging expectations, and release gates for iotakt.

## Motivation

The package must serve two audiences: Lean users who want model/proof/fake-backend functionality without native dependencies, and systems users who want native Linux socket behavior. CI and release gates must preserve both workflows while ensuring native claims are tested and documented before release.

## Goals

- Define Lean-only CI.
- Define proof/test/doc gates.
- Define Linux native CI with C warnings and sanitizers.
- Define platform gating for native tests.
- Define release checklist and versioning policy.

## Non-Goals

- Do not require native backend on every contributor machine.
- Do not block Lean-only users on C toolchain setup.
- Do not promise kqueue CI in v0.1.
- Do not publish release without proof/trust/test matrix.

## External Design

CI should have at least two tracks:

```text
Lean-only:
  lake build
  proof build
  fake tests/examples
  docs lint/check if available

Linux native:
  C strict warning build
  sanitizer build where practical
  native conformance tests
  epoll/socket tests
```

## Data Model / Internal Design

Release metadata:

```text
Lean toolchain version
Lake package version
Native backend support table
Proof/trust/test matrix version
RFC acceptance snapshot
```

Native support table should explicitly say Linux epoll only for v0.1 if that remains true.

## Lifecycle / Workflow

Release workflow:

```text
RFCs accepted → implementation complete → Lean-only CI green
              → native CI green on supported platforms
              → matrix updated → examples pass → tag/release
```

## Public API Impact

Public package should be installable/buildable in Lean-only mode. Native feature/profile use must be documented clearly.

## Native Boundary Impact

Native build should fail clearly when attempted on unsupported platforms rather than silently building broken stubs.

## Henret Integration Impact

CI should run integration examples that exercise bridge behavior with fake poller and, on Linux, native epoll.

## Security Considerations

Release gates are security controls: no release with known unclassified native boundary claims, missing matrix updates, or failing cleanup tests.

## Proof Obligations

- CI proof build checks all theorem files compile.
- No separate formal proof obligation in this RFC beyond gate definitions.

## Test Obligations

- Lean-only build.
- Fake poller tests.
- Native C compilation.
- Sanitizer profile.
- Native socket/epoll tests.
- Docs generation/checks where available.

## Trust / Assumption Changes

- Assume CI runner OS behavior is representative enough for basic conformance.
- Native tests are evidence, not proof.

## Architecture Gaps

- Lake native-profile design may be nontrivial.
- Sanitizer availability varies.
- Flaky native timing tests must be minimized.

## Acceptance Criteria

- CI matrix documented.
- Release checklist exists.
- Lean-only build is default.
- Native test profile exists on Linux.
- Matrix update is release gate.

## Alternatives Considered

- Single CI job only: rejected because native and Lean-only requirements differ.
- Require native tools for all builds: rejected for Lean ecosystem usability.
- Skip native tests: rejected because native boundary must be tested.

## Open Questions

- Exact CI provider configuration.
- Whether docs are mdBook, plain Markdown, or Lake-generated docs initially.

