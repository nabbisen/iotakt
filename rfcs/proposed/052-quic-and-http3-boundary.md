---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 052: QUIC and HTTP/3 Boundary

## Summary

This RFC defines the post-v1 boundary for QUIC and HTTP/3-related work. QUIC must not be implemented
inside core iotakt. iotakt may eventually provide the UDP and timing primitives needed by a QUIC
package, but QUIC's cryptography, congestion control, stream multiplexing, packet number spaces, TLS
1.3 integration, and transport state machine belong above or beside iotakt.

## Motivation

henejt may eventually want HTTP/3 support. Since HTTP/3 runs over QUIC rather than TCP, it cannot use
the TCP stream model directly. At the same time, QUIC is a full secure transport protocol, not a small
socket option. Placing it inside iotakt would destroy iotakt's clean role as a socket/readiness bridge.

## Goals

- Define a clear boundary between iotakt and future QUIC work.
- Prevent QUIC from becoming a hidden expansion of iotakt core.
- Identify the minimal iotakt capabilities useful to a QUIC implementation.
- Preserve henejt's ability to adopt HTTP/3 later.

## Non-goals

- No QUIC implementation in iotakt.
- No TLS 1.3 implementation in iotakt.
- No HTTP/3 framing in iotakt.
- No congestion control, packet loss recovery, stream scheduling, or crypto state.
- No decision to adopt a particular QUIC library.

## Boundary decision

Core iotakt may provide:

- UDP datagram sockets.
- Monotonic timer integration through Henret driver concepts.
- Readiness/coalescing for UDP fd resources.
- ByteArray packet transfer.
- Optional socket configuration needed for UDP operation.

Core iotakt must not provide:

- QUIC packet parsing.
- QUIC connection state.
- TLS handshake state.
- HTTP/3 stream mapping.
- Congestion-control logic.

## Proposed package topology

```text
henejt-http3
  HTTP/3 semantics, request/response mapping

quic-layer or external QUIC library adapter
  QUIC transport, TLS 1.3, congestion control, streams

iotakt
  UDP socket readiness, packet I/O, timers through Henret driver
```

## Data handoff

If a future QUIC layer is written in Lean, it should receive datagrams through an actor mailbox:

```lean
structure UdpPacket where
  fdKey : FdKey
  peer : UdpEndpoint
  bytes : ByteArray
```

If a native QUIC library is adapted, the boundary becomes more complex because the native library may
own buffers, timers, retransmission state, and crypto state. That must be handled by a separate RFC.

## Workflow: Lean QUIC package direction

1. iotakt receives UDP readiness.
2. QUIC actor calls `recvFrom`.
3. QUIC actor parses packets and updates transport state.
4. QUIC actor schedules timers through Henret-compatible timer operations.
5. QUIC actor emits outgoing packets with `sendTo`.
6. henejt receives logical HTTP/3 stream events from the QUIC layer, not from iotakt.

## Workflow: native QUIC adapter direction

1. Native QUIC library owns QUIC connection state.
2. iotakt or adapter feeds UDP packets into native library.
3. Native library requests timers and outbound datagrams.
4. Adapter emits Henret messages for application-level stream events.

This direction has a much larger trusted code base and should not be default.

## Proof/trust/test classification

PROVEN in iotakt:

- UDP event delivery and fd lifecycle invariants only.

ASSUMED/TESTED outside iotakt:

- QUIC transport correctness.
- TLS correctness.
- Congestion control.
- HTTP/3 stream semantics.

OUTSCOPE for iotakt:

- Security proofs for QUIC.
- Formal verification of cryptography.

## Security considerations

QUIC is security-sensitive. iotakt must not imply that using iotakt makes QUIC verified. At most,
iotakt can provide verified-ish event translation and fd lifecycle handling below a QUIC layer.

## Acceptance criteria

- QUIC remains a post-v1 theme.
- The v1 iotakt API does not contain QUIC-specific concepts.
- Any future QUIC RFC must explicitly define whether QUIC state is Lean-owned or native-owned.
- henejt HTTP/3 integration must consume QUIC-layer stream events, not raw iotakt datagrams directly.
