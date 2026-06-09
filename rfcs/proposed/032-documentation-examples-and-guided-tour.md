# RFC 032: Documentation, Examples, and Guided Tour

**Status:** Proposed / Developer Experience  
**Milestone:** M7  
**Priority:** High before first public release  
**Primary layer:** Docs / Examples  
**Project:** iotakt  
**Stack position:** `henejt → iotakt → henret`  
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

This RFC designs the documentation set needed for iotakt to be understandable as a Lean ecosystem library, not merely as a socket wrapper.

## Motivation

The target audience includes Lean users interested in systems modeling, low-level developers interested in formal boundaries, and future henejt developers. Documentation must explain both usage and proof/trust boundaries.

## Goals

- Create a guided tour from pure model to fake poller to native backend.
- Provide minimal examples that do not require native dependencies.
- Provide native examples only behind explicit setup instructions.
- Explain non-goals and trust boundaries prominently.

## Non-Goals

- Do not write a general POSIX socket tutorial.
- Do not teach HTTP server design inside iotakt docs.
- Do not hide limitations behind marketing language.
- Do not require native backend to understand the core model.

## External Design

Recommended docs:

```text
README.md
  project identity, install/build, quick examples

docs/guided-tour.md
  Model -> FakePoller -> Bridge -> Native overview

docs/architecture.md
  henejt/iotakt/henret stack and boundaries

docs/proof-trust-test-matrix.md
  proven/assumed/tested/outscope claims

docs/native-boundary.md
  C shim and FFI ownership rules

docs/examples.md
  echo, fake traces, listener pattern
```

## Data Model / Internal Design

Examples should be executable where possible:

```text
Iotakt.Examples.ModelTrace
Iotakt.Examples.FakePollerEcho
Iotakt.Examples.NativeEchoLinux
```

The first two should work in Lean-only builds. Native examples should fail gracefully or be excluded when native features are disabled.

## Lifecycle / Workflow

Learning path:

```text
read README
run Lean-only model example
run fake poller example
inspect proof/trust/test matrix
optionally enable native epoll
run native echo/listener example
```

## Public API Impact

Examples should use public APIs only unless a section explicitly teaches internals. This helps detect accidental public API gaps.

## Native Boundary Impact

Native docs must list supported platforms, compiler requirements, feature flags, and expected failure modes. They must also state that native backend is optional.

## Security Considerations

Docs must warn that examples are not production hardening templates unless they include limits. Any sample server should include resource budget comments.

## Proof Obligations

Docs should link theorem names to concepts. Avoid claiming more than the theorem states. Proof documentation should distinguish model properties from OS/FFI assumptions.

## Test Obligations

Documentation examples should compile in CI. Markdown snippets that are intended to compile should be extracted or mirrored in example files.

## Trust / Assumption Changes

Documentation accuracy is TESTED through example compilation and review. Human explanations remain documentation, not proof.

## Architecture Gaps

Lean doc tooling choices may affect layout. A small documentation set is better than an ambitious site that becomes stale.

## Acceptance Criteria

- README explains project in under ten minutes.
- Guided tour works without native dependencies.
- Native boundary doc exists.
- Examples compile in CI.
- Non-goals are visible near the top-level docs.

## Alternatives Considered

Only provide API docs: rejected because boundary concepts are central. Build a full book immediately: deferred. Put all explanation in RFCs only: rejected because users need approachable docs.

## Open Questions

- Should iotakt use mdBook later?
- Should docs mirror Henret's README/guided-tour structure?
- Which example best demonstrates henejt readiness without implementing HTTP?
