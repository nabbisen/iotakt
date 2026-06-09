# RFC 005: Registry, Event Translation, and Stale Event Rejection

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M2  
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

This RFC defines the pure translation logic from normalized poller events to actor-targeted readiness messages. It is the core correctness boundary of iotakt: unknown events and stale events are dropped before actor messages are constructed.

## Motivation

Native pollers report readiness by fd-like identity, but actors own model resources. The translator is the boundary that must prevent native quirks from corrupting actor mailboxes. By making translation pure and deterministic, iotakt can prove the most important claims without proving the OS.

## Goals

- Define translation input and output types.
- Resolve raw fd to current `FdKey`.
- Reject unknown and stale events deterministically.
- Validate interest and ownership before message construction.
- Produce traceable drop reasons for debugging/tests.

## Non-Goals

- Do not inject into Henret directly; RFC 007 owns bridge execution.
- Do not coalesce readiness; RFC 006 owns pending readiness state.
- Do not normalize native backend flags; RFC 004/RFC 011 own that.

## External Design

Externally, the translator produces one of the following outcomes:

```text
Injectable: a valid message can be sent to the owner actor.
DroppedUnknown: no active resource exists for the raw fd.
DroppedStale: the event refers to an obsolete generation or closed key.
DroppedNoInterest: the event is not enabled for this resource.
DroppedClosed: the resource is closed/closing and cannot receive readiness.
TraceOnly: informational event for observability.
```

The translator must be deterministic: same registry state and event list yield same translation results.

## Data Model / Internal Design

Representative model:

```lean
structure OwnerEvent where
  owner : ActorId
  key   : FdKey
  event : IoEvent
  deriving Repr

inductive DropReason where
  | unknownRawFd
  | staleGeneration
  | noRegisteredInterest
  | resourceClosed
  | unsupportedEvent
  deriving DecidableEq, Repr

inductive TranslationResult where
  | injectable (event : OwnerEvent)
  | dropped (rawFd : RawFd) (reason : DropReason)
  deriving Repr

-- Specification-level pseudo-code:
-- translateOne resolves raw fd, validates current generation, checks state and interest,
-- and returns either an injectable owner event or a structured drop reason.
def translateOne (reg : Registry) (ev : NormalizedRawEvent) : TranslationResult :=
  match resolveCurrent reg ev.rawFd with
  | none      => .dropped ev.rawFd .unknownRawFd
  | some key  =>
      match lookupEntry reg key with
      | none       => .dropped ev.rawFd .staleGeneration
      | some entry => validateAndBuild entry ev
```

`translateMany` should preserve order except where coalescing later suppresses duplicates.

## Lifecycle / Workflow

Translation workflow:

```text
1. Receive normalized event: (raw_fd, IoEvent).
2. Look up current generation for raw_fd.
3. If no current generation exists, drop as unknown.
4. Construct current FdKey(raw_fd, gen).
5. Look up registry entry by FdKey.
6. If missing or closed, drop as stale/closed.
7. Check event against registered interests and fatal-event policy.
8. Create OwnerEvent(owner, FdKey, IoEvent).
9. Emit trace for injection or drop.
```

Fake tests may also inject events with explicit stale keys to exercise stale-generation proofs more directly.

## Public API Impact

Translator APIs are mostly internal/model-facing, but useful for tests:

```lean
def translateOne  : Registry → NormalizedRawEvent → TranslationResult
def translateMany : Registry → List NormalizedRawEvent → List TranslationResult
```

Public application code should not call the translator directly in normal use.

## Native Boundary Impact

Native backends supply normalized raw events only. They do not know actor ownership and must not construct `IoMessage`s. This avoids duplicating registry logic in C.

## Henret Integration Impact

The bridge consumes only `TranslationResult.injectable`. Dropped results may be logged/traced but must not produce Henret mailbox messages.

## Security Considerations

This RFC is the main defense against stale event misdelivery. Unknown and stale events are not exceptional at the OS boundary; they are expected under close/reuse races and must be safely ignored.

## Proof Obligations

- No unknown injection: if raw fd cannot resolve to an active key, no owner event is produced.
- No stale injection: an event for a non-current generation cannot become an owner event.
- Owner soundness: every injectable event targets the registry owner for the current key.
- Interest soundness: readable/writable owner events require matching registered interest unless fatal policy allows otherwise.
- Translation does not mutate registry state.

## Test Obligations

- Unknown raw fd event is dropped.
- Stale generation event is dropped.
- Readable without read interest is dropped.
- Writable without write interest is dropped.
- Fatal/error event follows documented delivery/drop policy.
- Order of independent translated events is deterministic.

## Trust / Assumption Changes

- Translator assumes the registry state is the authoritative Lean-side state.
- Translator does not assume native backend drains all stale events before close.
- Translator does not assume OS event order beyond the received list order.

## Architecture Gaps

- Fatal event policy may need final tuning after epoll/kqueue tests.
- If multiple owner models are introduced later, registry owner soundness must be extended.

## Acceptance Criteria

- Pure translator function exists and is executable.
- Drop reasons are explicit and testable.
- No bridge code constructs actor messages directly from raw native events.
- Stale and unknown event scenarios are covered by fake tests.

## Alternatives Considered

- Let native backend store actor IDs: rejected because it moves proof-relevant state into C.
- Deliver unknown events as errors to a global actor: rejected for v0.1 to avoid unexpected mailbox noise.
- Ignore interest checks: rejected because it weakens proof and flood prevention.

## Open Questions

- Should unknown events be counted in a debug statistic in v0.1?
- Should fatal events bypass interest checks by default? Recommended: yes for hangup/error, with precise documentation.

