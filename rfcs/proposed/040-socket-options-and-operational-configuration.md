# RFC 040: Socket Options and Operational Configuration

- **Status:** Proposed
- **Intended phase:** v0.2+
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines a minimal, explicit allowlist for socket options exposed by iotakt.

## 2. Motivation

Socket options are operationally important but can easily turn into a portability and security mess. iotakt must expose only the options needed for safe server operation while avoiding a general arbitrary `setsockopt` escape hatch in the high-level API.

## 3. Option categories

```lean
structure SocketOptionSet where
  reuseAddr      : Bool
  reusePort      : Bool
  ipv6Only       : Option Bool
  tcpNoDelay     : Bool
  keepAlive      : Option KeepAlivePolicy
  receiveBuffer  : Option Nat
  sendBuffer     : Option Nat
  noSigpipe      : Bool
```

## 4. Default policy

Recommended defaults:

```text
reuseAddr:      true for listeners
reusePort:      false unless explicitly requested
ipv6Only:       explicit per listener, not platform default
TCP_NODELAY:    false by default; jemmet may enable for latency-sensitive use
keepAlive:      disabled by default in v0.1/v0.2
SO_LINGER:      no positive blocking linger by default
SIGPIPE guard:  enabled where platform requires it
```

## 5. Unsafe option policy

The following must not be exposed in the ordinary public API:

```text
- arbitrary raw setsockopt
- positive blocking SO_LINGER by default
- options requiring elevated privileges
- transparent proxy / packet mark options
- platform-specific options that change routing/security semantics
```

They may be added later only through RFC review.

## 6. Native boundary

The native layer should expose small wrappers for allowlisted options rather than a generic `setsockopt(level, optname, ptr, len)` API to Lean.

This keeps the native boundary auditable and prevents high-level Lean code from relying on unstable or unsafe platform-specific integer constants.

## 7. Error policy

Each option application returns a structured result:

```lean
inductive OptionApplyResult where
  | applied
  | unsupported
  | failed : IoErrno -> OptionApplyResult
```

`unsupported` is distinct from `failed`; it allows platform-specific absence to be handled without pretending the operation is a runtime failure.

## 8. Invariants

```text
No implicit default invariant:
  Any platform-sensitive option that affects externally observable behavior must be explicit in ListenerSpec.

Allowlist invariant:
  Public socket configuration is limited to modeled options.

No blocking linger invariant:
  iotakt must not configure positive blocking linger by default.
```

## 9. Acceptance criteria

- Listener creation applies options in a documented order.
- Native conformance tests verify nonblocking and cloexec are always set regardless of option failures.
- Documentation lists option portability notes for Linux and kqueue platforms.
