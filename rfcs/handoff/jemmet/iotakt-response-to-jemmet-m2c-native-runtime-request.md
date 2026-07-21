# iotakt response to jemmet M2C native-runtime consumer request

**Response date:** 2026-07-14
**Status:** Architecture decisions accepted; implementation and release evidence
pending
**Release decision:** No-Go remains in force
**Governing work:** [RFC 064](../../proposed/064-generation-safe-effectful-fd-authority.md),
[RFC 066](../../proposed/066-authoritative-event-delivery-and-state-safe-native-transitions.md),
[RFC 070](../../proposed/070-address-aware-listener-identity-and-lifecycle.md)

This is a durable design response, not a release announcement. Jemmet must not pin or
recommend the native runtime from this document. Exact release coordinates and
verification evidence can be supplied only after the remediation train completes.

## 1. Listener address and identity decision

Iotakt accepts address-aware listener creation as required scope.

- Initial support: IPv4 loopback, wildcard, and validated specified local address.
- IPv6: explicitly deferred from the first M2C-capable release.
- Listener identity: the listener's generation-safe `FdKey`, named `ListenerKey`
  where useful; no second numeric identity mechanism.
- Accepted event: carries both `ListenerKey` and connection `FdKey` before jemmet
  creates a slot or processes bytes.
- Stable accepted events do not expose a raw fd.
- Listener creation and duplicate/conflict failures are typed and normalized.

RFC 070 owns the exact endpoint constructors, listener error type, accept attribution,
and lifecycle implementation.

## 2. Authoritative event-consumption decision

Stable external consumers use **Option A: returned events are authoritative**.

In consumer-event mode, `EventLoop.runStep` returns the sole readiness/terminal event
stream. Iotakt does not inject a duplicate into Henret and does not allocate a
connection mailbox merely for readiness delivery. Any retained mailbox-driving mode
is separately selected and returns no duplicate public readiness.

The bridge still performs generation, liveness, interest, translation, and
coalescing checks once. Only its authoritative delivered result reaches the selected
sink. The returned collection is bounded by poll/accept configuration, and the model
retains at most one pending slot per connection generation and pending kind.

## 3. Timeout and reaping ownership decision

Jemmet owns idle, header, body, handler, write, and drain deadlines.

- Jemmet calls `runStep timeoutMs`, using its nearest phase deadline.
- `idleTimeoutMs = none` must fully disable iotakt idle reaping.
- `runStepAuto` is not the supported jemmet phase-deadline API.
- After `.newConnection` is returned, no internal close may occur without an
  authoritative typed terminal/closed outcome.
- Capacity rejection before a connection is published may close the candidate but
  must be represented in bounded operational evidence/counters.

## 4. Readiness and terminal acknowledgement

| Event | Pending kind | Required jemmet action | Ack operation | Readable bytes may coexist? |
|---|---|---|---|---|
| `.readable` | `.readable` | Attempt bounded receive, or defer while a bounded staged queue drains | `recvAck` after attempt | Yes |
| `.writable` | `.writable` | Attempt send; retain suffix or disable interest | `sendAck`, or `ackReady` if no send is required | Not applicable |
| `.eof` | `.eof` | Drain co-delivered readable bytes, then close once | `ackReady` if retaining; close otherwise clears all | Yes |
| `.hangup` | `.hangup` | Drain available bytes when applicable, then close once | `ackReady` if retaining; close otherwise clears all | Yes |
| `.error e` | `.error` | Record normalized error, optionally drain, then close once | `ackReady` if retaining; close otherwise clears all | Yes |

Readable and writable have independent pending slots. Readiness is ordered before the
terminal disposition for the same key in one returned batch. Several terminal flags
may coexist, but jemmet issues one close intent.

EINTR supports an immediate bounded retry before the next poll step. A deferred
readable event remains pending and suppresses duplicates until jemmet attempts the
operation and acknowledges. Successful close clears all pending kinds for that
generation; no prior-generation mailbox/pending state survives raw-fd reuse.

## 5. Physical close and listener lifecycle

- Jemmet's driver is the sole consumer caller of physical connection close.
- Protocol handlers return close intent/drain state and do not receive raw-fd
  authority.
- `closeConnection` and `closeListener` validate current generation, live state,
  resource kind, and native fd range before native work.
- Unknown, stale, wrong-kind, invalid, and already-closed keys are typed no-effect
  failures; a stale key cannot close a reused fd.
- Duplicate physical close is not a supported success operation.
- Listener creation, accepted registration, deregistration, and close publish model
  state only after native success and clean up partial candidates exactly once.
- `shutdown` closes listeners through `closeListener`, then connections through
  `closeConnection`; successful `destroy` closes only the poller and does not repeat
  resource closes.
- `destroy` on a non-drained loop returns typed `notDrained` and performs no close;
  jemmet calls `shutdown` explicitly before retrying it.

## 6. Intended API signatures

Exact placement may evolve under RFC review, but these semantics are fixed:

```lean
structure BindEndpoint where
  address : Ipv4Address
  port : UInt16

abbrev ListenerKey := FdKey

def EventLoop.addListener
  (loop : EventLoop) (endpoint : BindEndpoint) :
  IO (Except ListenerError (EventLoop × ListenerKey))

def EventLoop.closeListener
  (loop : EventLoop) (listener : ListenerKey) :
  IO (Except EffectError EventLoop)

inductive LoopEvent where
  | newConnection (listener : ListenerKey) (connection : FdKey)
  | ioEvent (connection : FdKey) (event : IoEvent)
  | tick (now : Nat)

def EventLoop.runStep
  (loop : EventLoop) (timeoutMs : Int) :
  IO (Except LoopError (EventLoop × List LoopEvent))
```

RFC 070 implements the listener surface. RFC 066 implements authoritative delivery,
fatal errors, terminal acknowledgement, and state-safe transitions.

## 7. Required test and gate additions

The accepted R2/R3 evidence set includes:

1. IPv4 loopback, wildcard, specified-address, duplicate, and multi-listener tests;
2. correct listener attribution and plaintext/TLS-mode demultiplexing fixture;
3. same-batch readable/writable and readable/terminal acknowledgement;
4. EOF/hangup/error ordering and exactly-once close;
5. bounded EINTR retry and deferred acknowledgement without lost wakeup;
6. long-lived consumer mode with zero Henret readiness-mailbox growth;
7. disabled idle reaping with consumer-owned phase deadlines;
8. fault-injected listener/accept/register/close transitions with state/resource
   correspondence;
9. connection and listener close followed by raw-fd reuse; and
10. individual listener close, shutdown, destroy, and bind-again without descriptor
    growth or double close.

These tests do not become release evidence until RFC 067's fail-closed clean gate and
retained logs are available.

## 8. Target release and verification evidence

No release version, commit, archive hash, sidecar hash, dependency syntax, or Go gate
record is available yet. The project is No-Go and the current jemmet pin at release
`0.14.6` / commit `c6334e58927cf17973d3391e1304c697acee2d01` predates the remediation.

Version selection occurs only after R5 Go. The eventual response will provide the
exact model/runtime compatibility statement, Lake dependency syntax, Linux/Lean/C
requirements, archive hash and byte count, sidecar hash, manifest/toolchain evidence,
and retained native gate record.

## 9. Jemmet assumptions accepted or rejected

Accepted:

- jemmet owns HTTP/TLS protocol state, listener configuration, staged bytes,
  deadlines, and close intent;
- listener identity selects plaintext/TLS before parsing bytes;
- one driver owns effectful close; and
- IPv4-only initial support is sufficient when IPv6 is explicit.

Rejected or changed:

- jemmet must not use a raw fd as listener or connection identity;
- stable accepted events will not grant raw-fd authority;
- `runStepAuto` is not the jemmet phase-deadline driver;
- returned events and Henret mailboxes cannot both be consumed; and
- no current release or unqualified runtime pin is approved before R5.

Jemmet may amend its RFCs 017, 018, and 009 around these decisions, but should keep
implementation gated on the final API and release evidence.
