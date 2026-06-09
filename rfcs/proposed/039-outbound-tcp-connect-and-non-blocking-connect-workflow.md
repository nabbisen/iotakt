# RFC 039: Outbound TCP Connect and Non-Blocking Connect Workflow

- **Status:** Proposed
- **Intended phase:** v0.2+
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC extends iotakt from server-side accept/read/write support to outbound non-blocking TCP connection establishment.

## 2. Motivation

Although the initial henejt use case is an HTTP server, Lean applications may need outbound connections for proxying, upstream requests, health checks, or test harnesses. Outbound connect has distinct non-blocking semantics and must be modeled explicitly.

## 3. Non-blocking connect semantics

A non-blocking `connect` may return:

```text
- success immediately
- EINPROGRESS / wouldBlock-style in progress
- immediate error
```

When connect is in progress, writable readiness may indicate completion, but the application must query `SO_ERROR` to determine whether the connection succeeded or failed.

Readiness remains a hint.

## 4. Data model

```lean
inductive ConnectState where
  | created
  | connecting
  | connected
  | failed : IoErrno -> ConnectState
  | closed

structure OutboundEntry where
  key        : FdKey
  ownerActor : ActorId
  remote     : RemoteAddr
  state      : ConnectState
```

## 5. API sketch

```lean
namespace Iotakt

def tcpConnectStart
  (remote : RemoteAddr)
  (owner : ActorId) : IO ConnectStartResult

def checkConnectResult
  (handle : FdHandle) : IO ConnectCheckResult

end Iotakt
```

```lean
inductive ConnectStartResult where
  | connected  : FdHandle -> ConnectStartResult
  | inProgress : FdHandle -> ConnectStartResult
  | error      : IoErrno -> ConnectStartResult

inductive ConnectCheckResult where
  | connected
  | stillPending
  | failed : IoErrno -> ConnectCheckResult
```

## 6. Workflow

```text
1. Actor requests outbound connect.
2. iotakt creates socket with nonblock and cloexec.
3. iotakt calls connect.
4. If immediate success:
   a. register read interest as requested
   b. return connected handle
5. If EINPROGRESS:
   a. register write interest
   b. record ConnectState.connecting
   c. return inProgress handle
6. Poller reports writable readiness.
7. Actor or bridge calls checkConnectResult via SO_ERROR.
8. If success, transition to connected and update interests.
9. If failure, report error and close or hand control to actor policy.
```

## 7. Invariants

```text
No-connected-without-check invariant:
  A socket that returned EINPROGRESS cannot transition to connected without SO_ERROR check.

Connect ownership invariant:
  An outbound socket is registered to exactly one actor before readiness is delivered.

Failure cleanup invariant:
  Failed connect either closes or transitions to actor-visible failed state; it is not silently left in registry.
```

## 8. DNS boundary

iotakt does not implement DNS resolution. It accepts already-resolved remote addresses or delegates name resolution to a higher layer.

DNS policy, resolver selection, caching, and hostname validation belong above iotakt.

## 9. Acceptance criteria

- Fake model covers immediate success, EINPROGRESS success, EINPROGRESS failure, and immediate error.
- Native tests cover localhost connect success and refused port failure.
- The proof/trust/test matrix records `SO_ERROR` behavior as assumed/tested native behavior.
