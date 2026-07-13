# RFC 070 — Address-aware listener identity and lifecycle

**Status.** Proposed — release-blocking downstream runtime contract
**Milestone.** R2 — event, listener, and state integrity
**Tracks.** Jemmet M2C native-runtime consumer request, accepted 2026-07-14.
**Touches.** Listener endpoint types, native socket bind wrappers, listener registry
metadata, accept results, `LoopEvent`, `EventLoop.closeListener`, shutdown/destroy,
tests, consumer documentation.

## Summary

Add a typed IPv4 bind endpoint, use the listener's generation-safe `FdKey` as its
stable identity, attach that identity to every accepted connection, and provide one
checked exactly-once listener close path. This lets a consumer select plaintext or
TLS configuration before staging accepted bytes without receiving raw-fd authority.

RFC 066 owns the authoritative event channel and acknowledgement contract. This RFC
owns listener address, identity, accept attribution, and physical lifecycle.

## Decisions

### Initial address scope

The first supported endpoint surface is IPv4:

```lean
structure Ipv4Address where
  value : UInt32

structure BindEndpoint where
  address : Ipv4Address
  port : UInt16
```

Reviewed constructors provide loopback, wildcard, and validated four-octet/specified
local addresses. Callers do not pass an address string to the native boundary.

IPv6 is explicitly deferred from the first jemmet M2C-capable release. Adding it
requires an additive address variant, native bind implementation, and platform tests;
it may not be claimed through the IPv4 implementation.

### Listener identity

The stable listener identity is its existing generation-safe `FdKey`, documented as
`ListenerKey` where a role-specific name helps:

```lean
abbrev ListenerKey := FdKey
```

Every listener-key operation validates current generation, live state, native fd
range, and `.listener` resource kind through RFC 064's resolver. A separate numeric
`ListenerId` would duplicate generation and reuse rules and is therefore rejected.

### Stable listener API

The intended stable shapes are:

```lean
inductive ListenerError where
  | invalidEndpoint
  | duplicateEndpoint
  | nativeError (errno : IoErrno)
  | transitionError (detail : ListenerTransitionError)

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
```

Exact type placement may change during implementation, but the typed result,
generation-safe identities, listener attribution, and absence of raw fd from stable
accept events are fixed decisions.

Jemmet maps `ListenerKey` to immutable plaintext/TLS configuration. The mapping is
available before it constructs a connection slot or processes bytes.

### Duplicate endpoints

An exact duplicate active `BindEndpoint` is rejected as `duplicateEndpoint` before a
second modeled listener is published. Other OS-level conflicts, including wildcard
and specific-address overlap, return a normalized `nativeError .addressInUse` when
reported by the kernel. No implementation silently reuses an existing listener.

Errors contain bounded enums and normalized errno values, not peer-controlled text,
secret material, or unbounded native strings.

## Transaction and ownership rules

Listener creation follows one failure-atomic sequence:

1. validate the endpoint and duplicate policy;
2. create a nonblocking, close-on-exec socket;
3. apply required socket options;
4. bind and listen;
5. register with the poller;
6. allocate/publish the listener registry entry and endpoint mapping only after
   native success; and
7. on any earlier failure, close the candidate fd exactly once and return a typed
   error.

Accept follows the same rule: accept the fd, configure/register it, and only then
publish the connection registry entry and `.newConnection listener connection`.
Registration failure closes the accepted fd exactly once and publishes no connection.

`closeListener` validates listener authority, deregisters, closes once, removes its
endpoint/identity record, and commits the closed model state. Unknown, stale,
wrong-kind, and already-closed keys return typed no-effect errors. It cannot close a
reused raw fd.

## Shutdown and destroy

- `closeListener` is the only stable physical close for one listener.
- `shutdown` stops acceptance by applying the same checked close transition to every
  listener, then closes active connections through `closeConnection`.
- After shutdown succeeds, `destroy` closes only the poller handle and does not close
  listener or connection fds again.
- Calling `destroy` on a non-drained loop returns a typed `notDrained` lifecycle
  error and performs no resource close. Callers use `shutdown` explicitly before
  retrying `destroy`.
- An accepted connection already returned before drain is a normal connection and can
  be closed immediately through `closeConnection`.

## Deadline ownership for jemmet

Jemmet owns idle, read, write, handler, and drain deadlines. Its supported loop is
`runStep timeoutMs`, with `timeoutMs` derived from jemmet's nearest deadline.

`idleTimeoutMs = none` must disable iotakt idle reaping. Jemmet does not use
`runStepAuto` for phase deadlines. No internal path may close a connection after it
has been surfaced without returning an authoritative typed terminal/closed outcome.
Capacity rejection before `.newConnection` is allowed but must appear in bounded
operational evidence/counters.

## Implementation sequence

1. Add validated IPv4 endpoint types and normalized listener errors.
2. Refactor native listener setup into failure-atomic transition helpers.
3. Store endpoint and listener identity metadata in `EventLoop` state.
4. Carry `ListenerKey` through accept and the RFC 066 authoritative delivery result.
5. Add checked `closeListener`, then make shutdown reuse it.
6. Make destroy ordering explicit and test double-close prevention.
7. Update API, jemmet adapter, package-consumption, and migration documentation.

## Test obligations

- Bind IPv4 loopback, wildcard, and a specified local IPv4 address.
- Reject an exact duplicate endpoint with a typed error; normalize kernel conflicts.
- Bind multiple listeners and attribute each accepted connection to the correct key.
- Demultiplex plaintext/TLS fixture configuration by listener key before reading.
- Fault-inject socket-option, bind, listen, and epoll-register failures; observe no
  published listener and exactly-once cleanup.
- Fault-inject accepted-fd registration failure; observe no published connection and
  exactly-once cleanup.
- Reject stale/forged/negative/out-of-range/wrong-kind listener closes with no native
  call, including live raw-fd reuse.
- Close one listener while others continue accepting.
- Exercise listener close, shutdown, destroy, and bind-again without descriptor
  growth or a second close.
- Demonstrate that disabled idle reaping never removes a surfaced jemmet connection.

## Security considerations

Listener identity is security-sensitive because it selects plaintext versus TLS
before untrusted bytes are parsed. Port comparison and raw fd identity are forbidden.
Endpoint errors are normalized and bounded. All physical effects follow generation
and resource-kind authority checks, and partial setup cannot publish an unregistered
or already-closed resource.

## Dependencies

- Depends on RFC 064 checked effect authority and extends its inventory with
  `closeListener`.
- Integrates with RFC 066's authoritative consumer-event mode and state-safe native
  transitions.
- Uses RFC 029 fault IDs for listener creation, accepted registration, close,
  shutdown, and cleanup failures.
- Blocks RFC 033, jemmet runtime adoption, and any TLS implementation claim.

## Acceptance criteria

- IPv4 loopback, wildcard, and specified-address listeners use a typed endpoint API.
- Every accepted stable event carries generation-safe listener and connection keys
  and no raw fd.
- Listener creation/accept publication is failure-atomic with exactly-once cleanup.
- `closeListener`, shutdown, and destroy have one coherent, tested ownership order.
- RFC 064's inventory classifies `closeListener` as `checked-stable` and binds it to
  stale/forged/raw-reuse tests.
- Jemmet's consumer-owned deadline mode has no unreported post-surface idle close.
- Required tests pass in retained R2/R3 evidence before any consumer release.

## Non-goals

- No IPv6 claim in the first implementation.
- No TLS configuration or certificate ownership inside iotakt.
- No protocol parsing, routing, or application deadline policy.
- No public raw-fd escape hatch for accepted connections.
