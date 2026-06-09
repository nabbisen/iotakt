# RFC 012: Socket Provisioning and Listener/Stream API

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M4  
**Priority:** Critical for v0.1 native backend  
**Primary layer:** Public API and Iotakt.Native.Socket

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

This RFC defines listener and stream APIs, address representation, accept policy, non-blocking/close-on-exec enforcement, and accepted stream registration behavior.

## Motivation

The socket provisioning API is where raw OS resources first enter iotakt's model. Incorrect ordering here—such as registering before non-blocking configuration or accepting without assigning a fresh generation—can invalidate the rest of the architecture. This RFC ensures listener and stream creation follow the same lifecycle and fd identity rules used by the pure model.

## Goals

- Define minimal IPv4/IPv6 address model.
- Define listener create/bind/listen/register workflow.
- Prefer accept4 with SOCK_NONBLOCK and SOCK_CLOEXEC on Linux.
- Fallback to accept + fcntl when necessary.
- Allocate fresh FdKey for accepted streams.
- Define max accepts per driver tick.

## Non-Goals

- Do not implement DNS resolution.
- Do not implement TLS.
- Do not provide high-level HTTP server APIs.
- Do not model full sockaddr complexity publicly in v0.1.

## External Design

The listener API should be small and direct. v0.1 should support binding to explicit IP addresses and ports. Name resolution belongs above or outside iotakt.

```text
create listener → bind/listen → register readable accept interest
readable listener → accept loop bounded by maxAcceptsPerTick
accepted stream → configure → allocate FdKey → register read interest
```

## Data Model / Internal Design

```lean
inductive IpAddr where
  | v4 (a b c d : UInt8)
  | v6 (bytes : ByteArray) -- length checked by constructor/helper

structure SocketAddr where
  ip   : IpAddr
  port : UInt16

structure ListenOptions where
  backlog : Nat
  reuseAddr : Bool := true
```

Accepted streams are model resources with kind `stream` and fresh generation.

## Lifecycle / Workflow

Accept workflow:

```text
1. Listener receives Readable.
2. Driver/actor calls acceptMany(listener, limit).
3. Each accepted raw fd is immediately non-blocking and close-on-exec.
4. Each stream receives a new FdKey and owner actor.
5. Streams are registered for readable interest.
6. accept wouldBlock ends the accept loop normally.
```

## Public API Impact

```lean
def listen    : SocketAddr → ListenOptions → ActorId → IotaktM ListenerRef
def acceptOne : ListenerRef → ActorId → IotaktM AcceptResult
def acceptMany : ListenerRef → ActorId → Nat → IotaktM (List StreamRef)
def closeListener : ListenerRef → IotaktM CloseResult
```

Ownership assignment for accepted streams may be listener-owner by default or supplied by henejt's accept supervisor policy.

## Native Boundary Impact

Native socket wrappers include socket, bind, listen, accept4/accept, fcntl nonblock/cloexec, setsockopt for reuseaddr where supported, and close.

## Henret Integration Impact

Accepted stream ownership determines the actor that receives readiness messages. henejt may spawn a connection actor before registering the stream.

## Security Considerations

Non-blocking and close-on-exec enforcement are mandatory. Backlog and accept limits reduce resource exhaustion. DNS is omitted to avoid resolver-related blocking and complexity.

## Proof Obligations

- Accepted stream receives fresh FdKey.
- Registered listener/stream states follow lifecycle model.
- Accept wouldBlock does not corrupt lifecycle state.

## Test Obligations

- Create listener on loopback.
- Connect client and accept stream.
- Accepted stream is non-blocking.
- accept wouldBlock is normal.
- close listener cleanup path.

## Trust / Assumption Changes

- Assume OS socket syscalls behave according to POSIX/Linux semantics.
- Assume address conversion code is reviewed/tested.

## Architecture Gaps

- IPv6 byte validation details.
- Portability differences for SO_REUSEADDR/SO_REUSEPORT.
- Accepted actor assignment policy may evolve with henejt.

## Acceptance Criteria

- Minimal address model exists.
- Listener can be created and closed.
- Accepted stream obtains fresh FdKey.
- Non-blocking/CLOEXEC are enforced before registration.
- Bounded accept loop is implemented.

## Alternatives Considered

- Expose raw sockaddr directly: rejected for v0.1 API clarity.
- Include DNS resolver: rejected as scope creep and possible blocking.
- Accept unlimited per tick: rejected due to fairness/resource concerns.

## Open Questions

- Whether `reuseAddr` default should be true or false for production examples.
- How henejt will choose connection actor ownership.

