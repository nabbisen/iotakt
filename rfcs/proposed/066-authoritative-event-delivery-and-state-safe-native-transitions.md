# RFC 066 — Authoritative event delivery and state-safe native transitions

**Status.** Proposed — release-blocking remediation
**Tracks.** Architecture review B3, N1, N2, and part of N4; Go evidence 4 and 5.
**Touches.** `IotaktRuntime.Bridge`, `IotaktRuntime.Driver`, `IotaktRuntime.Loop`, event/result types, fault-injection seams, loop decomposition.

## Summary

Create one authoritative event-delivery pipeline. Actor injection and public
`LoopEvent` output must be derived from the same validated translation and
coalescing decision. Native state transitions must report errors and update the
model only after the kernel transition succeeds, with explicit cleanup for partial
failure.

## Goals

- Remove the independent raw-event-to-`LoopEvent` path.
- Preserve interest, liveness, generation, and coalescing decisions at the stable
  public boundary.
- Make fatal poll errors observable.
- Prevent pending coalescing state from being committed when delivery cannot occur.
- Make register/modify/deregister/accept/connect/close failures state-safe.
- Split the oversized event-loop module by responsibility while changing it.

## Non-goals

- Do not add edge-triggered or one-shot semantics.
- Do not add native background threads.
- Do not turn operational traces into application protocol events.

## External design

The bridge returns an authoritative delivered-event record containing the updated
driver/runtime state and the caller-visible outcome. `EventLoop.runStep` consumes
that result; it never reconstructs readiness from the original raw event list.

Operational outcomes distinguish at least:

- delivered readiness;
- coalesced readiness;
- dropped unknown/stale/no-interest/closed/no-mailbox;
- timeout/tick; and
- fatal poll/backend error.

Only delivered readiness becomes `.dataReady`. Fatal errors must be returned in a
typed form that permits the caller to stop or apply policy.

## Transaction rules

For register, modify, deregister, accept registration, connect registration, and
close:

1. validate the modeled key/transition;
2. attempt the native operation;
3. commit the corresponding model transition only on success; and
4. on partial failure, perform bounded cleanup and return a structured error.

Errors may not be discarded with `let _ <- ...` on stable paths.

If mailbox validation or Henret injection fails, coalescing state must remain
deliverable: validate before setting pending, or roll the pending slot back.

## Implementation sequence

1. Define authoritative delivery and operational error result types.
2. Refactor bridge processing to return delivered events and traces together.
3. Remove `runStep`'s raw-event replay and surface fatal poll errors.
4. Repair pending-state commit ordering around mailbox/injection failures.
5. Introduce state-safe native transition helpers with fault-injection seams.
6. Split polling/delivery, connection lifecycle, idle policy, and outbound connect
   out of `Loop.lean` where it improves reviewability.
7. Update API stability and consumer migration documentation.

## Proof obligations

- Every public `.dataReady` corresponds to an injectable, delivered translation.
- Coalesced or rejected events produce no public readiness.
- Failed delivery does not leave an unreachable pending slot.
- Failed modeled/native transitions preserve the pre-operation correspondence.

## Test obligations

- Duplicate readiness without acknowledgement yields one public delivery.
- No-interest, stale, unknown, and closed events yield no public readiness.
- Missing mailbox/injection failure remains deliverable after correction.
- Fatal poll failure is observable.
- Fault-injected register/modify/deregister/accept/connect/close failures do not
  leave an active modeled resource with inconsistent kernel state.
- RFC 029's deterministic failure matrix is updated and executed.

## Security considerations

This RFC prevents verification claims from being bypassed by a parallel public
delivery path and prevents kernel/model divergence from granting stale authority or
causing silent denial of service.

## Dependencies and follow-ups

- Depends on RFC 064's checked effect resolution for fd operations.
- Uses RFC 029 for failure-scenario organization.
- Blocks RFC 033 and downstream runtime recommendation.

## Acceptance criteria

- One code path decides both actor injection and public readiness delivery.
- Stable native transitions return and preserve structured failure information.
- Required proofs and public-loop/fault-injection tests pass.
- `Loop.lean` responsibilities are reduced enough to keep the security-sensitive
  transition logic independently reviewable.

## Open questions

- Should operational drops be returned to all callers or retained in a structured
  trace/counter channel while only fatal errors enter the main result?
