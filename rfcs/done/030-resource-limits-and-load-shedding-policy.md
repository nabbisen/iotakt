# RFC 030: Resource Limits and Load-Shedding Policy

**Status:** Done / Hardening  
**Milestone:** M5/M7  
**Priority:** High  
**Primary layer:** Security / Runtime Policy  
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

This RFC designs explicit resource limits and load-shedding behavior for listener and stream operation. The aim is to prevent unbounded fd growth, mailbox growth, accept loops, and output queues while keeping policy simple.

## Motivation

Even a minimal socket layer needs limits. Without them, a simple server can exhaust file descriptors, memory, actor mailboxes, or scheduler time. iotakt should expose simple limit hooks and recommended defaults while leaving application policy to jemmet or the embedding driver.

## Goals

- Define limit categories for fd count, accept budget, read chunk size, event batch size, and pending readiness.
- Provide deterministic behavior when limits are reached.
- Keep application payload queue limits outside core iotakt but document integration points.
- Preserve proof-friendly boundedness.

## Non-Goals

- Do not implement complex admission control or rate limiting.
- Do not manage HTTP request limits.
- Do not create a general resource manager.
- Do not silently drop established connection data.

## External Design

Limit categories:

```text
maxActiveFds
maxEventsPerPoll
maxAcceptsPerCycle
maxReadBytesPerRecv
maxDriverOpsPerCycle
maxPendingReadinessPerFdInterest = 1 by coalescing policy
```

When a limit is hit, iotakt should return structured results or trace events rather than blocking indefinitely.

## Data Model / Internal Design

Suggested configuration:

```lean
structure IotaktLimits where
  maxActiveFds        : Nat
  maxEventsPerPoll    : Nat
  maxAcceptsPerCycle  : Nat
  maxReadBytes        : USize
  maxDriverOps        : Nat
```

Limits should be passed to driver creation, not stored in native global state.

## Lifecycle / Workflow

Load-shedding examples:

```text
accept limit reached:
  stop accepting this cycle, keep listener read interest

max active fds reached:
  accepted fd may be closed immediately with diagnostic result

max events per poll reached:
  process returned batch, poll again later

pending readiness already exists:
  coalesce duplicate event
```

## Public API Impact

Public driver configuration may include `IotaktLimits.default`. Defaults should be conservative and documented. Advanced users can override explicitly.

## Native Boundary Impact

Native `poll_wait` must accept a maximum event count and never return unbounded event arrays. Native accept helper should not loop indefinitely; loops belong in Lean with a budget.

## Security Considerations

Limits are central to denial-of-service resistance. A server must not allow one listener or one connection to monopolize the driver. Limit-hit trace events should not leak sensitive payload bytes.

## Proof Obligations

Proof targets:

```text
driver cycle injects at most maxEventsPerPoll translated readiness messages before coalescing
a listener actor accepts at most maxAcceptsPerCycle streams per cycle
pending readiness per FdKey+Interest is bounded by one
```

## Test Obligations

Tests:

- accept budget enforced,
- event batch cap enforced,
- duplicate readiness coalesced,
- max active fd behavior,
- read chunk cap honored,
- trace events emitted on limit hits.

## Trust / Assumption Changes

Native event count cap is trusted/tested. Model-level limits can be proven if encoded in pure driver functions.

## Architecture Gaps

Choosing default limits is application-sensitive. iotakt can provide safe defaults but jemmet must tune them for real workloads.

## Acceptance Criteria

- Limit structure documented.
- Default limits exist.
- Limit-hit behavior is deterministic.
- Security section explains DoS relevance.
- Tests cover all limit categories.

## Alternatives Considered

Leave all limits to jemmet: rejected because some limits are driver-level. Hardcode limits: rejected. Implement complex adaptive load shedding: deferred.

## Open Questions

- Should maxActiveFds be enforced by registry only or by native admission too?
- Should limit-hit be a trace, error, or both?
- What default read chunk size is appropriate for examples?
