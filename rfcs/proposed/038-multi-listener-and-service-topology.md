# RFC 038: Multi-Listener and Service Topology

- **Status:** Proposed
- **Intended phase:** v0.2+/v0.3
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines how iotakt represents multiple listeners, multiple services, and accept routing without becoming aware of application protocols.

## 2. Motivation

A practical jemmet server may listen on multiple addresses and ports, such as public HTTP, local admin, test-only loopback, or separate IPv4/IPv6 sockets. iotakt must support this topology while preserving a minimal byte/readiness role.

## 3. Service identity

Introduce a Lean-side service identifier that is meaningful to the application but opaque to the native backend.

```lean
structure ServiceId where
  value : Nat

deriving DecidableEq, Repr, Ord

structure ListenerSpec where
  serviceId : ServiceId
  bindAddr  : BindAddr
  backlog   : Nat
  options   : SocketOptionSet
```

`ServiceId` is not a protocol type. It only tells the bridge which accept owner should receive accepted connections.

## 4. Listener registry

```lean
structure ListenerEntry where
  key        : FdKey
  serviceId  : ServiceId
  ownerActor : ActorId
  bindAddr   : BindAddr
  state      : ListenerState
```

Accepted connection actors are created by jemmet or a jemmet-owned accept supervisor, not by native code.

## 5. Accept routing workflow

```text
1. Poller reports listener FdKey readable.
2. iotakt translates readiness to ListenerReady(serviceId, listenerKey).
3. Accept actor calls accept on listener handle.
4. iotakt returns AcceptedConnection with a new FdKey.
5. jemmet chooses or spawns the connection actor.
6. iotakt registers the connection fd to that actor.
```

## 6. IPv4 and IPv6 policy

Iotakt should represent bind addresses explicitly:

```lean
inductive IpFamily where
  | inet4
  | inet6

structure TcpBindAddr where
  family : IpFamily
  host   : String
  port   : UInt16
```

Dual-stack behavior must be explicit. Iotakt should not silently depend on platform-specific defaults for `IPV6_V6ONLY`.

## 7. Non-goals

- virtual host routing
- HTTP Host header routing
- TLS SNI routing
- load balancing
- hot-reload orchestration

These belong above iotakt.

## 8. Invariants

```text
Listener uniqueness:
  A listener FdKey maps to exactly one ServiceId.

Accept ownership:
  An accepted connection initially belongs to the accept workflow, then is explicitly registered to one actor.

No protocol dependency:
  The service topology model contains no HTTP/TLS-specific states.
```

## 9. Acceptance criteria

- Tests cover two listeners mapped to different service IDs.
- Tests cover listener shutdown by service ID.
- Tests cover accepted connection registration to different actors.
- Documentation explains how jemmet maps services to protocol handlers above iotakt.
