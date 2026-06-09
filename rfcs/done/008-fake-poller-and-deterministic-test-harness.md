# RFC 008: Fake Poller and Deterministic Test Harness

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M2  
**Priority:** High  
**Primary layer:** Iotakt.Fake / Iotakt.Test

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

This RFC defines the Lean-only fake poller and deterministic test harness used to validate iotakt's model, translator, coalescing, and Henret bridge without native C or OS timing.

## Motivation

Native socket tests are inherently dependent on OS timing, platform behavior, and kernel scheduling. They are necessary but not sufficient for model validation. iotakt needs a Lean-only backend that can replay exact event traces, including impossible-to-time edge cases such as stale events, duplicate readiness bursts, and deterministic timeout/interrupted paths. The fake poller makes the bridge testable before the native C backend exists and keeps the core library useful to Lean users without a C toolchain.

## Goals

- Define a poller interface shared by fake and native backends.
- Define scripted event traces.
- Support timeout and interrupted wait simulation.
- Support stale, unknown, duplicate, EOF, hangup, and error scenarios.
- Make proof-adjacent executable examples easy to write.

## Non-Goals

- Do not simulate full TCP semantics.
- Do not replace native conformance tests.
- Do not hide model bugs with test-only behavior.
- Do not depend on epoll/kqueue.

## External Design

The fake poller is a first-class backend. It is not a toy; it is the reference mechanism for deterministic bridge tests. A fake script is a list of poll outcomes. Each driver step consumes one scripted outcome or returns timeout according to policy.

```text
FakePoller script:
  [ events [raw 10 readable]
  , events [raw 10 readable, raw 10 readable]
  , interrupted
  , timeout
  , events [raw 99 readable] ]
```

## Data Model / Internal Design

```lean
inductive FakePollResult where
  | events (events : List NormalizedRawEvent)
  | timeout
  | interrupted
  | fatal (err : IoErrno)

structure FakePoller where
  script : List FakePollResult
  cursor : Nat

def next : FakePoller → FakePoller × FakePollResult
```

The fake poller should also support expected trace assertions, either through simple lists or a small DSL.

## Lifecycle / Workflow

Main workflow:

```text
1. Construct Registry and DriverState.
2. Construct FakePoller with scripted events.
3. Run driver step(s).
4. Capture TraceEvent and Henret message outputs.
5. Compare against expected trace.
```

Canonical scenarios: unknown raw fd drop, stale key drop, duplicate readiness coalescing, EOF delivery, hangup/error delivery, timeout tick, interrupted wait retry.

## Public API Impact

```lean
def runFakeOnce  : DriverConfig → FakePoller → DriverState → Henret.RuntimeState → TestResult
def runFakeTrace : DriverConfig → FakePoller → DriverState → Henret.RuntimeState → TraceResult
```

The exact return shape should favor simple `#eval` examples and regression tests.

## Native Boundary Impact

No native impact. The fake poller must build in the Lean-only profile and must not import native modules.

## Henret Integration Impact

The fake poller drives the same bridge path as native pollers, so Henret-facing behavior can be tested deterministically.

## Security Considerations

The fake backend should not be used to claim native security behavior. It verifies model/bridge security properties such as stale-event rejection and coalescing only.

## Proof Obligations

- Fake trace replay is deterministic.
- Fake events reaching bridge preserve translator no-stale/no-unknown properties.
- Timeout/interrupted simulation does not mutate unrelated state.

## Test Obligations

- Unknown raw fd scenario.
- Stale generation scenario.
- Duplicate readiness coalescing scenario.
- Writable enable/disable scenario.
- EOF/hangup/error scenario.
- Timer timeout scenario.

## Trust / Assumption Changes

- Assume fake scripts accurately encode intended test conditions.
- Do not treat fake poller results as evidence of native syscall correctness.

## Architecture Gaps

- Fake traces may grow verbose; trace helpers are needed.
- Expected Henret output format depends on bridge details.

## Acceptance Criteria

- Fake poller compiles without native C.
- At least six canonical scenarios are implemented.
- Driver path is shared with native backend abstraction.
- Examples can be run via Lake without platform-specific setup.

## Alternatives Considered

- Use only native socketpair tests: rejected because OS timing is nondeterministic and unavailable in Lean-only build.
- Mock Henret instead of using bridge path: rejected for lower integration confidence.

## Open Questions

- Whether fake scripts should be a custom DSL or plain lists; plain lists are recommended for v0.1.

