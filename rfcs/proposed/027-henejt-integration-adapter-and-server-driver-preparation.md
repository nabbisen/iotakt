# RFC 027: henejt Integration Adapter and Server Driver Preparation

**Status:** Proposed / Integration Planning  
**Milestone:** M7  
**Priority:** High before henejt implementation  
**Primary layer:** Iotakt.HenretBridge / Examples  
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

This RFC defines how iotakt should prepare for the future henejt HTTP server without importing HTTP concepts into iotakt. It describes driver shapes, actor ownership patterns, and examples that henejt can later use.

## Motivation

iotakt exists to support a Henret-based HTTP server named henejt. However, iotakt must remain protocol-agnostic. A thin integration planning RFC prevents accidental HTTP leakage into the socket layer while still giving henejt a practical adoption path.

## Goals

- Define listener actor and connection actor workflows useful to henejt.
- Keep request parsing, routing, TLS, and response construction outside iotakt.
- Define example echo/byte server patterns that henejt can copy.
- Clarify where output buffering belongs.

## Non-Goals

- Do not implement HTTP.
- Do not define henejt APIs.
- Do not require iotakt to know request/response semantics.
- Do not add TLS or ALPN to iotakt.

## External Design

Integration shape:

```text
henejt application
  owns protocol actors and parser state
  calls iotakt listener/stream APIs
  reacts to IoReady messages
  keeps request and response buffers

iotakt
  owns fd lifecycle and readiness translation
  injects bounded readiness messages
  exposes non-blocking recv/send primitives
```

A recommended actor pattern should be documented, but not enforced as a framework.

## Data Model / Internal Design

Example actor roles:

```text
ListenerActor:
  owns listening FdKey
  on readable: accept loop under budget
  for each accepted stream: spawn/register connection actor

ConnectionActor:
  owns stream FdKey
  on readable: recv and pass bytes upward
  on writable: flush pending actor-owned output
  on eof/error: deregister and close
```

The accept loop must be budgeted to avoid starving other actors.

## Lifecycle / Workflow

Recommended flow:

```text
start driver
create listener
spawn ListenerActor
register read interest on listener
poll event arrives
inject ListenerReadable
listener accepts up to acceptBudget streams
for each stream, henejt spawns ConnectionActor
connection actor registers read interest
```

## Public API Impact

iotakt may provide examples and small generic helpers, but no HTTP-specific API. Names should avoid protocol terms:

```text
Iotakt.Examples.Echo
Iotakt.Patterns.ListenerActor
Iotakt.Patterns.StreamActor
```

Any henejt-specific adapter should live in henejt or a separate integration package.

## Native Boundary Impact

No new native boundary. Integration uses existing listener, accept, recv, send, register, deregister, close, and driver APIs.

## Security Considerations

Example patterns must include limits: accept budget, per-connection read budget, maximum read chunk size, idle timeout hook, and output queue guidance. Even examples should not teach unbounded behavior.

## Proof Obligations

Possible proof targets for generic patterns:

```text
listener accept budget bounds spawned streams per driver cycle
connection actor close path deregisters before closing
helper pattern never registers write interest without pending output
```

henejt-specific protocol correctness is outside iotakt.

## Test Obligations

Tests:

- echo server using fake poller,
- echo server using native socketpair or localhost,
- listener actor accept budget,
- connection close cleanup,
- integration trace expected sequence.

## Trust / Assumption Changes

No new assumptions. Integration examples rely on existing iotakt and Henret bridge assumptions.

## Architecture Gaps

Henret may still lack full parked receive/wait queues. The pattern must work with external injected messages and current Henret semantics.

## Acceptance Criteria

- henejt name is used consistently.
- No HTTP-specific types are added to iotakt core.
- Listener/connection patterns are documented.
- At least one protocol-agnostic example demonstrates the intended workflow.

## Alternatives Considered

Design henejt first and retrofit iotakt: rejected because iotakt needs clear protocol neutrality. Add HTTP helper APIs to iotakt: rejected. Leave integration entirely undocumented: rejected because henejt is the primary motivating user.

## Open Questions

- Should generic actor patterns live in iotakt or Henret examples?
- How much convenience can be added before iotakt feels like a framework?
- What minimal henejt prototype should validate iotakt v0.1?
