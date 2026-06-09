# RFC 007: Henret Bridge and Deterministic Driver Loop

**Status:** Proposed  
**Milestone:** M2  
**Priority:** Critical  
**Primary layer:** Iotakt.HenretBridge

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

This RFC defines the deterministic bridge between iotakt and Henret. The bridge runs as an outer driver: drain Henret work, compute timeout, wait for fake/native poller events, translate/coalesce them, and inject valid messages into Henret.

## Motivation

A background native I/O thread would introduce shared state, races, and nondeterministic mutation of Henret mailboxes. iotakt should instead preserve Henret's executable trace style by making the driver explicit and deterministic with respect to the poller trace.

## Goals

- Define outer driver loop.
- Define mapping from translated events to Henret messages/operations.
- Integrate Henret timers with poller timeout calculation.
- Avoid native background mutation of Henret state.
- Support fake poller trace replay.

## Non-Goals

- Do not modify Henret internals.
- Do not require Henret parked wait queues in v0.1.
- Do not implement multi-threaded polling.
- Do not guarantee real-time scheduling latency.

## External Design

The driver loop is externally described as:

```text
loop:
  1. drain Henret until no immediate work remains or fuel is exhausted
  2. compute next timeout from Henret timers and driver policy
  3. wait for I/O through configured poller
  4. normalize poller events
  5. translate through registry
  6. coalesce duplicate readiness
  7. inject valid IoMessage values into Henret
  8. tick timers as needed
  9. repeat or shutdown
```

The loop may be implemented as a reference driver first. Production integration can refine it later, but the semantics must remain traceable.

## Data Model / Internal Design

Representative bridge types:

```lean
inductive IoMessage where
  | ready (key : FdKey) (event : IoEvent)
  | closed (key : FdKey) (reason : CloseReason)
  deriving Repr

structure DriverState where
  registry  : Registry
  coalesce  : CoalesceState
  clock     : Nat
  shuttingDown : Bool
  deriving Repr

inductive PollWaitResult where
  | events (events : List NormalizedRawEvent)
  | timeout
  | interrupted
  | fatal (err : IoErrno)
```

The bridge should keep iotakt state separate from Henret state, passing changes through explicit operations.

## Lifecycle / Workflow

Event injection workflow:

```text
PollWaitResult.events xs
  → translateMany registry xs
  → filter injectable results
  → coalesce each OwnerEvent
  → for each delivered event, create IoMessage.ready
  → Henret RuntimeOp.inject/send to owner actor
```

Timer workflow:

```text
Henret next logical timer deadline
  → driver calculates poll timeout
  → timeout result or elapsed wall interval
  → driver emits Henret tick according to reference policy
```

Shutdown workflow:

```text
shutdown requested
  → stop accepting new resources
  → drain/notify active actors if policy allows
  → deregister/close owned resources
  → emit final traces
```

## Public API Impact

Representative APIs:

```lean
structure DriverConfig where
  maxEventsPerPoll : Nat
  maxHenretFuel    : Nat
  defaultTimeoutMs : Nat

def runOnce : DriverConfig → DriverState → Henret.RuntimeState → IotaktM (DriverState × Henret.RuntimeState)
def runLoop : DriverConfig → DriverState → Henret.RuntimeState → IotaktM DriverExit
```

Exact Henret type names may be adapted to the real Henret API.

## Native Boundary Impact

Native pollers are called only from the driver. They return data; they do not mutate Henret. EINTR is represented as an interrupted wait and handled by driver policy.

## Henret Integration Impact

The bridge should use public Henret operations such as send/inject/tick/wake according to the currently available Henret API. Since Henret's blocked receive semantics do not yet park tasks, iotakt must not rely on automatic wakeup from a receive wait queue. Instead, readiness is represented by mailbox messages.

## Security Considerations

The driver must enforce operational limits: max events per poll, max accepts per tick, max read size through helper APIs, and shutdown bounds. It must avoid infinite native waits when Henret timers are pending.

## Proof Obligations

- Bridge injects only events produced by successful translation and coalescing.
- Stale/unknown drops remain drops through the bridge.
- Fake poller replay with same inputs is deterministic.
- Bridge does not mutate registry except through documented lifecycle/coalescing transitions.

## Test Obligations

- Fake trace replay yields expected Henret message trace.
- Stale event in fake trace is not injected.
- Duplicate readiness in fake trace is coalesced.
- Timeout path produces expected timer/tick behavior.
- Interrupted wait does not corrupt driver state.

## Trust / Assumption Changes

- Henret public operations are trusted/proven according to Henret's own classification.
- Native poll timing is tested/assumed, not proven.
- Wall-clock to logical tick policy is a bridge design assumption unless modeled separately.

## Architecture Gaps

- Precise Henret API type names may need adjustment during implementation.
- Timer integration depends on Henret exposing enough timer/deadline information or a reference driver wrapper.

## Acceptance Criteria

- Reference driver loop is documented and implemented.
- No native background thread mutates Henret.
- Fake poller can drive the same bridge path as native poller.
- Bridge injection path preserves translator and coalescing properties.

## Alternatives Considered

- Background polling thread: rejected for determinism and proof complexity.
- Let actors call epoll directly: rejected because it leaks backend details and breaks central translation.
- Treat Henret as an opaque event sink without traceability: rejected.

## Open Questions

- Exact representation of Henret drain/fuel in public API.
- Whether bridge should expose a pure trace replay function separate from IO driver.

