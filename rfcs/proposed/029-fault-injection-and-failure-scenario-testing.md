# RFC 029: Fault Injection and Failure Scenario Testing

**Status:** Proposed / Hardening  
**Milestone:** M5/M7  
**Priority:** High  
**Primary layer:** Testing / Model Validation  
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

This RFC defines systematic fault injection for iotakt's model, bridge, fake poller, and native boundary. The goal is to validate error paths, not only happy-path readiness.

## Motivation

Socket systems fail constantly: `EAGAIN`, `EINTR`, connection reset, EOF, duplicate events, stale events, close races, and resource exhaustion. A formally flavored project must make these failures first-class.

## Goals

- Define deterministic fake-poller fault injection.
- Test stale raw fd events and generation mismatches.
- Test native error classification where feasible.
- Ensure bridge behavior remains bounded under noisy event streams.

## Non-Goals

- Do not create a full chaos-testing framework.
- Do not require nondeterministic timing races for release tests.
- Do not simulate entire TCP kernel behavior.
- Do not hide failures behind retries without documentation.

## External Design

Fault scenarios:

```text
unknown raw fd event
stale generation event
duplicate read readiness
write readiness without registered write interest
read would-block after readiness
send partial then would-block
EOF after readable
close while pending readiness exists
poll wait interrupted
accept returns would-block
resource limit exceeded
```

## Data Model / Internal Design

Fake poller should support scripted event traces:

```lean
inductive FaultEvent where
  | rawEvent : RawFd -> BackendEvent -> FaultEvent
  | pollInterrupted
  | pollError : IoErrno -> FaultEvent
  | nativeRecvResult : FdKey -> ReadResult -> FaultEvent
  | nativeSendResult : FdKey -> WriteResult -> FaultEvent
```

The harness should separate event translation tests from syscall result tests.

## Lifecycle / Workflow

Test workflow:

```text
construct registry state
script poller events/faults
run driver cycle(s)
collect injected Henret operations/messages
assert bounded and correct behavior
```

No test should rely on sleeping for arbitrary wall-clock durations.

## Public API Impact

No production API impact. Test APIs may be exposed under `Iotakt.Test` or `Iotakt.Fake`. They should not be imported by normal users.

## Native Boundary Impact

Native fault injection is limited. Some faults can be induced with socketpair/close/resource limits; others should remain fake-poller tests. The native boundary should never require LD_PRELOAD or invasive harnesses for normal CI.

## Security Considerations

Failure tests protect against denial-of-service by mailbox flooding, stale injection, resource leaks, and unchecked error paths. They should be considered security-relevant tests.

## Proof Obligations

Proof targets:

```text
unknown fd events inject no message
stale events inject no message
duplicate coalesced events remain bounded
unregistered interest events inject no message
closed fd state is terminal in the model
```

## Test Obligations

A named test matrix should list each fault, whether it is proven, fake-tested, native-tested, or out of scope. Release cannot claim robustness for a fault that is not represented in the matrix.

## Trust / Assumption Changes

Fake-poller tests validate model behavior under scripted faults. Native tests validate only inducible host behaviors. Kernel timing races remain assumed/out of scope unless specifically tested.

## Architecture Gaps

Some real-world failures are hard to reproduce deterministically. The project must be honest about what is not tested.

## Acceptance Criteria

- Fault scenario list exists.
- Each scenario maps to proof/test/trust classification.
- Fake-poller harness can express stale and duplicate events.
- Native conformance covers feasible failures.
- No fault path crashes the driver in tests.

## Alternatives Considered

Rely on normal unit tests: rejected because failures are the main risk. Use random fuzzing only: rejected because deterministic proofs/tests are needed first. Ignore native-only faults: rejected for socket library credibility.

## Open Questions

- Should property-based testing be introduced later?
- Which fault scenarios should be v0.1 release blockers?
- How should tests report proof/test/trust status automatically?
