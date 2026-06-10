# RFC 023: Edge-Triggered and One-Shot Polling Semantics

**Status:** Future / Performance Candidate  
**Milestone:** M8  
**Priority:** Medium  
**Primary layer:** Iotakt.Model / Native Backends  
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

This RFC designs optional future support for edge-triggered and one-shot readiness modes. The baseline design remains level-triggered because it is easier to reason about and safer for a first release.

## Motivation

Linux epoll and some high-performance servers use `EPOLLET` and `EPOLLONESHOT` to reduce repeated readiness notifications. These modes can improve throughput but introduce subtle correctness requirements: actors must drain until `EAGAIN`, and one-shot interests must be rearmed deliberately.

## Goals

- Capture edge-triggered and one-shot modes as explicit advanced policies.
- Prevent accidental use of advanced polling modes through the default API.
- Define model-level obligations for drain-to-EAGAIN and rearm behavior.
- Keep backends normalized through the same `IoEvent` vocabulary.

## Non-Goals

- Do not make edge-triggered mode the default.
- Do not require jemmet actors to adopt drain loops before baseline correctness.
- Do not add undocumented backend-specific flags to the general API.
- Do not claim performance benefits without measurement.

## External Design

Future policy type:

```lean
inductive PollMode where
  | level
  | edge
  | oneShot
  | edgeOneShot
```

Default registration uses `level`. Advanced registration must require a visible policy argument so code review can identify the change.

## Data Model / Internal Design

Edge mode changes the actor obligation more than the backend vocabulary. A read-ready event in edge mode means the actor should continue calling `recv` until `wouldBlock` or a terminal condition. One-shot mode means the actor must rearm interest after it has handled the current readiness.

Model additions:

```lean
structure InterestState where
  interest : IoInterest
  mode     : PollMode
  armed    : Bool
  pending  : Bool
```

For one-shot modes, translation should set `armed := false` when an event is delivered.

## Lifecycle / Workflow

Level-triggered workflow remains:

```text
ready -> actor does bounded work -> may wait again
```

Edge-triggered workflow:

```text
edge ready -> actor drains until EAGAIN/eof/error -> wait again
```

One-shot workflow:

```text
ready -> iotakt marks interest disarmed -> actor handles event -> actor explicitly rearms
```

## Public API Impact

Advanced API only:

```lean
def registerAdvanced (fd : FdKey) (interest : IoInterest) (mode : PollMode) : IO RegisterResult
def rearm (fd : FdKey) (interest : IoInterest) : IO RearmResult
```

The baseline API should not expose these names unless imported from `Iotakt.Advanced`.

## Native Boundary Impact

Linux epoll maps modes to `EPOLLET` and `EPOLLONESHOT`. kqueue equivalents are not identical; the model must not pretend all platforms share one behavior. Backend support may be partial.

## Security Considerations

Misuse can cause connection stalls. If an actor fails to drain or rearm, it may never receive further events. Advanced modes should include trace diagnostics and optional debug assertions.

## Proof Obligations

Proof targets:

```text
one-shot delivery disarms interest
no event is delivered for a disarmed one-shot interest
rearm restores eligibility for delivery
coalescing still bounds pending messages
```

The proof does not claim the actor drains the kernel buffer unless the actor code is separately modeled.

## Test Obligations

Tests:

- edge-mode drain-to-EAGAIN scenario,
- one-shot requires explicit rearm,
- duplicate readiness not injected while disarmed,
- level mode unchanged,
- fallback/rejection on unsupported backend.

## Trust / Assumption Changes

Assume backend flags implement documented behavior. Since these modes are subtle, all performance and correctness claims must be tested per backend.

## Architecture Gaps

The jemmet parser/actor design may need explicit drain loops before edge-triggered mode is useful. kqueue support needs careful separate mapping.

## Acceptance Criteria

- Advanced modes are not default.
- Unsupported platforms reject clearly.
- Proof obligations for armed/disarmed model states are complete.
- Debug traces expose registration mode and rearm events.

## Alternatives Considered

Never support edge/one-shot: acceptable for simplicity, but may limit high-throughput experimentation. Make edge default: rejected as unsafe for first users.

## Open Questions

- Should edge mode be compile-time feature-gated?
- Should jemmet provide actor templates for drain loops?
- Should one-shot be available before kqueue parity is understood?
