# RFC 031: API Versioning, Feature Flags, and Compatibility Policy

**Status:** Proposed / Governance  
**Milestone:** M7  
**Priority:** Medium  
**Primary layer:** Public API / Release Governance  
**Project:** iotakt  
**Stack position:** `jemmet → iotakt → henret`  
**Date:** 2026-06-08

---

## Document Intent

This RFC belongs to the continuation set after the v0.1 core RFC batch. It is intentionally detailed enough to guide implementation later, but it must not silently expand the v0.1 release boundary unless its status explicitly says so.

The governing principles remain:

- pure Lean model first,
- optional native boundary,
- no hidden async runtime,
- no C-side application buffering,
- readiness is a hint rather than a guarantee,
- file descriptors are identified by `FdKey(raw_fd, generation)`, not by raw fd alone,
- proof/trust/test classification is mandatory for every correctness claim.

## Summary

This RFC defines how iotakt will version its public API, optional native backends, advanced features, and proof claim changes.

## Motivation

iotakt sits at a boundary between proofs, Lean APIs, C FFI, and host-specific behavior. API changes can affect theorem statements, native assumptions, and downstream jemmet code. A compatibility policy prevents accidental breakage.

## Goals

- Define stable, experimental, and internal namespaces.
- Define feature flags/backends policy.
- Define how proof claim changes are versioned.
- Define deprecation and migration expectations.

## Non-Goals

- Do not promise permanent stability before v1.0.
- Do not stabilize advanced optimization APIs prematurely.
- Do not hide breaking proof changes as minor edits.
- Do not require all backends to be enabled together.

## External Design

Namespace policy:

```text
Iotakt.Model          stable after v0.1 unless model version changes
Iotakt.Driver         public driver API
Iotakt.Native         backend-specific, semi-internal
Iotakt.Advanced       experimental optimization APIs
Iotakt.Test/Fake      testing utilities
Iotakt.Internal       no compatibility promise
```

Feature/backends:

```text
lean-only default
native-epoll optional
native-kqueue optional future
advanced-recv-into optional future
advanced-edge optional future
```

## Data Model / Internal Design

Every public API should be classified in docs. The proof/trust/test matrix should include a model version field. Breaking theorem statement changes should be recorded like API changes.

## Lifecycle / Workflow

Change workflow:

```text
change proposed
classify namespace affected
classify model/proof/native impact
update RFC or create new RFC
update migration notes
run compatibility tests
```

## Public API Impact

Public API docs should include stability labels. Experimental APIs must be imported explicitly and may change. Internal modules should not be used by jemmet unless both projects coordinate.

## Native Boundary Impact

Native feature flags must fail clearly if unsupported. Native backend availability should not affect Lean-only model builds.

## Security Considerations

Security fixes may break compatibility when necessary. Such changes should be documented as security-motivated and not hidden.

## Proof Obligations

Proof compatibility matters. If an invariant is renamed, weakened, strengthened, or removed, release notes must explain the migration path or rationale.

## Test Obligations

Compatibility tests:

- Lean-only import smoke test,
- public API examples compile,
- native feature builds when enabled,
- experimental APIs excluded from stable examples unless marked.

## Trust / Assumption Changes

Version claims are governance/process claims. They are documented and tested through build/examples, not proven.

## Architecture Gaps

Lean package ecosystem versioning conventions may evolve. iotakt should remain simple and avoid overcomplicated semver promises before users exist.

## Acceptance Criteria

- Namespace stability table exists.
- Feature flag policy exists.
- Proof claim changes require release note entries.
- Lean-only default remains valid.
- Experimental APIs are clearly marked.

## Alternatives Considered

No compatibility policy: risky for downstream jemmet. Strict v1 stability immediately: premature. Put all APIs in one namespace: rejected because it blurs stable/advanced/internal boundaries.

## Open Questions

- Should iotakt use semantic versioning before v1.0?
- Should proof theorem names be part of compatibility guarantees?
- Should jemmet pin exact iotakt versions?
