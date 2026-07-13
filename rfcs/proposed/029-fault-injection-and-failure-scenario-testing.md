# RFC 029: Fault Injection and Failure Scenario Testing

**Status:** Proposed — scheduled remediation support
**Milestone:** R2 — event/state integrity
**Priority:** Release-blocking for RFC 066 failure paths
**Primary layer:** Testing / Model Validation  
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

This RFC defines systematic fault injection for iotakt's model, bridge, fake poller, and native boundary. The goal is to validate error paths, not only happy-path readiness.

The 2026-07-13 architecture review makes the register/modify/deregister,
accept-registration, connect-registration, close, mailbox, and fatal-poll scenarios
release-blocking. RFC 066 defines the state-safe transition seam; this RFC owns the
deterministic scenario matrix and failure evidence over that seam.

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

The following list is background/example coverage inherited from the original RFC;
it is not the normative release set. The mandatory transition and resource-failure
coverage is the complete matrix in the next section.

Example event and I/O scenarios:

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
inductive TransitionOp where
  | register | modify | deregister
  | configureListener | bindListener | listenListener | registerListener
  | registerAccepted | registerConnected
  | closeAfterDeregister

inductive TransitionResult where
  | succeeded
  | interrupted
  | wouldBlock
  | nativeError : IoErrno -> TransitionResult
  | resourcePressure : ResourceError -> TransitionResult

inductive FaultEvent where
  | rawEvent : RawFd -> BackendEvent -> FaultEvent
  | pollInterrupted
  | pollError : IoErrno -> FaultEvent
  | transitionResult : TransitionOp -> TransitionResult -> FaultEvent
  | nativeRecvResult : FdKey -> ReadResult -> FaultEvent
  | nativeSendResult : FdKey -> WriteResult -> FaultEvent
  | deliveryResult : FdKey -> DeliveryResult -> FaultEvent
  | allocationResult : AllocationResult -> FaultEvent
```

The harness separates event translation, syscall results, allocation pressure, and
mailbox/injection outcomes. A transition script records both the model snapshot and
the fake kernel resource set before and after every operation, so tests can assert
correspondence rather than only the returned error.

## Required release-blocking matrix

Every row is mandatory. `P`, `F`, and `N` mean proof, deterministic fake harness,
and native conformance respectively; a combined classification requires all listed
evidence. Test IDs are stable identifiers used by the retained R2 evidence report.

| Subject | Injection seam | Typed result | Expected model state | Expected kernel-resource disposition | Class | Test ID |
|---|---|---|---|---|---|---|
| Register failure | `transitionResult register (nativeError e)` | `Except.error (registerFailed e)` | entry/current generation absent; prior registry unchanged | candidate fd remains open and caller-owned; callee acquires no ownership | P+F+N | `FI-REG-001` |
| Listener socket-option failure | `transitionResult configureListener (nativeError e)` | `Except.error (listenerConfigureFailed e)` | no listener entry, endpoint mapping, or generation is published | candidate listener fd is closed exactly once | P+F+N | `FI-LST-OPT-001` |
| Listener bind failure | `transitionResult bindListener (nativeError e)` | `Except.error (listenerBindFailed e)` | no listener entry, endpoint mapping, or generation is published | candidate listener fd is closed exactly once; endpoint remains available according to kernel state | P+F+N | `FI-LST-BIND-001` |
| Listener listen failure | `transitionResult listenListener (nativeError e)` | `Except.error (listenerListenFailed e)` | no listener entry, endpoint mapping, or generation is published | bound candidate listener fd is closed exactly once | P+F+N | `FI-LST-LISTEN-001` |
| Listener poller-registration failure | `transitionResult registerListener (nativeError e)` | `Except.error (listenerRegistrationFailed e)` | no listener entry/current mapping or active endpoint record is published | listening candidate fd is closed exactly once and has no poller registration | P+F+N | `FI-LST-REG-001` |
| Modify failure | `transitionResult modify (nativeError e)` | `Except.error (modifyFailed e)` | prior interest and pending bits unchanged | kernel registration retains prior interest | P+F+N | `FI-MOD-001` |
| Deregister failure | `transitionResult deregister (nativeError e)` | `Except.error (deregisterFailed e)` | entry remains live/registered; no terminal transition committed | registration and fd remain open and owned; this operation performs no implicit retry or close | P+F+N | `FI-DEL-001` |
| Accepted-socket registration failure | `transitionResult registerAccepted (nativeError e)` | `Except.error (acceptRegistrationFailed e)` | no accepted entry/current mapping is published | accepted fd is closed exactly once before return | P+F+N | `FI-ACC-001` |
| Connected-socket registration failure | `transitionResult registerConnected (nativeError e)` | `Except.error (connectRegistrationFailed e)` | no connected/live entry is published | created fd is closed exactly once before return | P+F+N | `FI-CON-001` |
| Close after deregister succeeds | `transitionResult closeAfterDeregister (nativeError e)` | `Except.error (closeFailed e)` | entry records explicit closing/cleanup-pending state; generation is not reusable as live authority | poller registration is absent; the driver retains fd ownership for a finite configured retry budget, then returns fatal `cleanupExhausted` without accepting new work | P+F+N | `FI-CLS-001` |
| Close path when deregister fails | `transitionResult deregister (nativeError e)` during close | `Except.error (closeDeregisterFailed e)` | live/registered state is preserved; closed state is not committed | no native close occurs while registration ownership is unresolved | P+F+N | `FI-CLS-002` |
| Mailbox/injection failure | `deliveryResult key (failed e)` | `Except.error (deliveryFailed e)` | pending suppression is rolled back so a later cycle may retry delivery | fd registration and interest remain unchanged; no native cleanup occurs | P+F | `FI-MBX-001` |
| Fatal poll failure | `pollError e` where `e != EINTR` | `Except.error (pollFailed e)` | registry, pending, and delivery state remain unchanged; the cycle terminates | all registrations/resources remain owned and unchanged; the error is returned to the driver owner | P+F+N | `FI-POLL-001` |
| Poll interrupted | `pollInterrupted` / native `EINTR` | `Except.ok interrupted` | registry/pending/delivery state unchanged | registrations/resources unchanged; retry consumes bounded cycle budget | P+F+N | `FI-EINTR-001` |
| Allocation/resource pressure | `allocationResult exhausted` or native fd/resource limit | `Except.error resourceExhausted` | no partial entry, pending delivery, or ownership publication | any newly acquired fd/buffer is released exactly once; existing resources remain owned | P+F+N | `FI-RES-001` |

Where a host cannot deterministically induce a native errno, the native test must use
an in-process controllable syscall seam or document the platform exclusion in the
evidence report; it may not silently downgrade an `N` row to fake-only. Cleanup retry
budgets and escalation destinations are configuration/documentation constants tested
for termination.

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

The table above is the minimum matrix. The harness executes every row and emits its
test ID, injected result, returned typed result, before/after model snapshots, and
before/after fake/native resource disposition. Additional rows may be added, but no
required row may be marked out of scope for the remediation release.

Tests must also cover bounded cleanup/retry exhaustion, demonstrate that no fd is
orphaned or closed twice, and compare the model's ownership/registration state with
the observed fake/native resource set after each failure.

RFC 070 applies `FI-CLS-001` and `FI-CLS-002` to both stream and listener keys; the
retained report contains a distinct execution for each resource kind even though the
transition contract and stable IDs are shared.

## Trust / Assumption Changes

Fake-poller tests validate model behavior under scripted faults. Native tests validate only inducible host behaviors. Kernel timing races remain assumed/out of scope unless specifically tested.

## Architecture Gaps

Some real-world failures are hard to reproduce deterministically. The project must be honest about what is not tested.

## Acceptance Criteria

- Every required matrix row executes with its stable test ID and required P/F/N
  evidence; platform exclusions are explicit and independently reviewed.
- The harness can script transition operation results, delivery failures, allocation
  pressure, stale events, and duplicate events.
- Each row observes the specified typed result, model state, and kernel-resource
  disposition, including bounded cleanup/retry termination.
- Model ownership/registration state corresponds to the fake/native resource set at
  every post-failure observation point.
- No required fault path crashes the driver, leaks/orphans a resource, closes an fd
  twice, or silently suppresses later delivery.

## Alternatives Considered

Rely on normal unit tests: rejected because failures are the main risk. Use random fuzzing only: rejected because deterministic proofs/tests are needed first. Ignore native-only faults: rejected for socket library credibility.

## Open Questions

- Should property-based testing be introduced later?
- How should tests report proof/test/trust status automatically?

The release-blocking failure set is closed by the required matrix above. New failure
classes discovered during implementation are added to the matrix and cannot be
waived merely to preserve the R2 date.
