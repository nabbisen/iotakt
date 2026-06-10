# RFC 017: Public API Surface and Developer Experience

**Status.** Implemented (v0.2.0-dev)

**Status:** Proposed  
**Milestone:** M7  
**Priority:** High before first user-facing release  
**Primary layer:** Public Lean API

## Document Control

- **Project:** iotakt
- **Language:** Lean 4 with an optional native C boundary
- **Primary stack position:** `jemmet` → `iotakt` → `henret`
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

This RFC defines the developer-facing Lean API, module visibility, naming conventions, examples, and jemmet integration expectations.

## Motivation

A formally disciplined library still needs a usable public API. jemmet and other Lean users should be able to work with listeners, streams, events, and result types without importing backend flags or unsafe extern declarations. This RFC turns the internal architecture into an API shape that is explicit, teachable, and hard to misuse.

## Goals

- Define stable public modules and internal modules.
- Provide model-friendly result types.
- Keep backend details out of jemmet.
- Provide minimal listener/echo examples.
- Define API stability policy for v0.1.

## Non-Goals

- Do not guarantee long-term API stability before v0.1 acceptance.
- Do not expose every native wrapper as public API.
- Do not provide HTTP server APIs.
- Do not optimize ergonomics by hiding important wouldBlock/partial-write states.

## External Design

Public module shape:

```text
Iotakt
Iotakt.Model
Iotakt.Socket
Iotakt.Driver
Iotakt.Fake
Iotakt.Native   # explicit advanced/backend import
```

Applications should be able to write a small echo-style program without importing epoll internals.

## Data Model / Internal Design

Public types include:

```lean
SocketRef, ListenerRef, SocketAddr, ListenOptions,
ReadResult, WriteResult, AcceptResult, CloseResult,
IoMessage, IoEvent, FdKey
```

Internal-only types include raw native result encodings and backend flag constants.

## Lifecycle / Workflow

Example workflow:

```text
listen loopback:8080
spawn/assign accept actor
on listener readable: acceptMany
for each stream: spawn/assign connection actor
on stream readable: recvAndAck
on stream writable: sendAndAck
on eof/hangup/error: close stream
```

## Public API Impact

Representative public snippets:

```lean
open Iotakt

#eval Fake.runEchoScenario
```

Native examples should be clearly marked platform-dependent.

## Native Boundary Impact

Safe wrappers are public. Raw extern declarations remain internal/advanced. Native backend selection should be explicit but not invasive.

## Henret Integration Impact

jemmet should depend on public socket/driver/model APIs and should not branch on epoll/kqueue.

## Security Considerations

API ergonomics must not hide security-relevant states. `wouldBlock`, partial write, EOF, and error remain explicit.

## Proof Obligations

- Public API preserves model result distinctions.
- Backend-independent examples can use fake poller deterministically.

## Test Obligations

- Compile public examples.
- Fake echo scenario.
- Native loopback echo demo where supported.
- Import hygiene test: jemmet-style code imports no epoll module.

## Trust / Assumption Changes

- Assume users understand non-blocking result handling; docs must teach it.
- Native examples are platform-dependent.

## Architecture Gaps

- Exact names may change during implementation.
- jemmet integration may reveal API gaps.
- Documentation quality is critical for Lean ecosystem adoption.

## Acceptance Criteria

- Public API list exists.
- Internal/native modules are separated.
- At least one Lean-only example exists.
- At least one native Linux example is planned/implemented.
- jemmet can consume backend-neutral APIs.

## Alternatives Considered

- Expose minimal model only and no helpers: rejected because jemmet needs usable APIs.
- Hide all low-level states for ergonomics: rejected because correctness depends on explicit handling.
- Expose raw externs directly: rejected for safety and stability.

## Open Questions

- Whether `FdKey` should be public or wrapped opaquely in `SocketRef`; public debug plus opaque refs may be best.

