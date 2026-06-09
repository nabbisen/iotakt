---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 049: UDP and Datagram Socket Boundary

## Summary

This RFC defines a post-v1 expansion path for UDP and other datagram-style sockets in iotakt.
The goal is to add message-oriented network I/O without weakening the existing v1 contract for
non-blocking TCP streams, file descriptor identity, readiness-as-hint semantics, and Henret message
translation discipline.

UDP must not be treated as a trivial variant of TCP. TCP exposes byte streams, while UDP exposes
packets with boundaries, peer metadata, truncation behavior, and different error reporting. Therefore,
post-v1 UDP support should be modeled as a separate resource family inside `Iotakt.Model`, sharing
poller and lifecycle machinery but not pretending to have stream semantics.

## Motivation

Several future applications above iotakt may need UDP:

- DNS client or server experiments.
- Metrics and telemetry protocols.
- Local service discovery.
- QUIC research or future henejt-adjacent HTTP/3 experiments.
- Lightweight actor-to-actor network messages where packet boundaries matter.

Adding UDP after v1 allows the TCP-focused core to stabilize first.

## Goals

- Add datagram sockets as a first-class resource type.
- Preserve `FdKey(raw, generation)` as the identity mechanism.
- Preserve readiness-as-hint semantics.
- Provide `recvFrom` / `sendTo`-style APIs with explicit peer address handling.
- Model packet truncation and zero-length datagrams explicitly.
- Keep datagram payload buffering outside iotakt except for one syscall result object.
- Reuse poller backends where possible.
- Keep UDP outside v1 release gates.

## Non-goals

- No QUIC implementation.
- No DNS resolver implementation.
- No multicast management in the first UDP RFC implementation.
- No connected UDP abstraction unless separately justified.
- No reliability, retransmission, congestion control, ordering, or packet aggregation.
- No generic packet-processing framework.

## External design

### Resource family

Datagram resources should be distinguished from stream resources:

```lean
inductive ResourceKind where
  | streamTcp
  | listenerTcp
  | datagramUdp
```

A datagram resource is not `listening` or `accepted`. It is created, optionally bound, optionally
configured, registered with the poller, used for packet receive/send, then deregistered and closed.

### Datagram address model

The model should avoid exposing platform `sockaddr` structures directly. Use a normalized Lean-side
address representation:

```lean
inductive IpFamily where
  | inet4
  | inet6

structure UdpEndpoint where
  family : IpFamily
  hostBytes : ByteArray
  port : UInt16
```

The native layer is responsible for converting between `UdpEndpoint` and platform socket address
structures. This conversion is trusted/tested, not proven.

### Receive result

```lean
inductive DatagramRecvResult where
  | packet : data : ByteArray -> peer : UdpEndpoint -> truncated : Bool -> DatagramRecvResult
  | wouldBlock
  | interrupted
  | error : IoErrno -> DatagramRecvResult
```

A zero-length datagram is valid and must be represented as `.packet #[] peer false`, not EOF.
UDP has no TCP-style EOF.

### Send result

```lean
inductive DatagramSendResult where
  | sent : bytes : USize -> DatagramSendResult
  | wouldBlock
  | interrupted
  | messageTooLarge
  | error : IoErrno -> DatagramSendResult
```

For UDP, partial sends should normally be treated as an error-like abnormal condition unless the
platform reports otherwise. The API must not reuse TCP's partial-write contract without documenting
datagram-specific behavior.

## Lifecycle

```text
create socket
  -> set nonblock + cloexec
  -> optional bind
  -> register read/write interests
  -> recvFrom/sendTo event-driven operations
  -> deregister
  -> close
```

No accept lifecycle exists for UDP.

## Workflows

### Server-style UDP receive

1. Application asks iotakt to create and bind a UDP socket.
2. iotakt registers read interest.
3. Poller reports readable hint.
4. Henret bridge injects `IoReady fdKey readable` to the owning actor.
5. Actor calls `recvFrom fdKey maxBytes`.
6. Result is either one packet, would-block, interrupted, or error.
7. Actor processes packet; iotakt retains no payload state.

### Client-style UDP send

1. Actor prepares packet and destination endpoint.
2. Actor calls `sendTo fdKey endpoint bytes`.
3. Result is success, would-block, message-too-large, interrupted, or error.
4. If would-block, actor may request write interest and retry after readiness.

## Native boundary

The native C layer may expose:

```text
iotakt_udp_socket(family) -> fd/error
iotakt_udp_bind(fd, endpoint) -> status/error
iotakt_udp_recvfrom(fd, max_bytes) -> DatagramRecvResult-compatible object
iotakt_udp_sendto(fd, endpoint, bytearray) -> send result
```

The native layer must not maintain datagram queues.

## Proof and model targets

PROVEN candidates:

- Datagram resources preserve fd generation uniqueness.
- Datagram readiness events are translated only for registered resources.
- UDP receive/write interests obey the same interest-soundness invariant as TCP.
- Closing a datagram resource prevents modeled future event injection.

ASSUMED/TESTED:

- Platform sockaddr conversion is correct.
- Kernel reports UDP readiness according to documented platform behavior.
- Truncation flags and message-too-large errors are mapped correctly.

## Security considerations

- UDP is spoofable. iotakt must not authenticate peer endpoints.
- Amplification risk belongs to application/protocol layers, but iotakt documentation should warn users.
- Default socket receive buffer changes are out of scope unless RFC 040-style socket options are extended.
- Packet size limits should be explicit in the API call site.

## Acceptance criteria

- UDP APIs are absent from v1 stable surface unless this RFC is ratified post-v1.
- A fake datagram poller can drive deterministic tests.
- UDP does not change TCP stream semantics.
- UDP event translation reuses `FdKey` generation checks.
- Native tests cover zero-length datagrams, truncation, would-block, and closed socket behavior.
