# RFC 042: Unix Domain Socket and Local IPC Backend

- **Status:** Future
- **Intended phase:** Optional backend
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines a future extension for Unix domain sockets and local IPC support.

## 2. Motivation

Unix domain sockets are useful for local admin interfaces, reverse proxies, supervisor control channels, and test harnesses. They share many readiness semantics with TCP sockets but differ in addressing, credential passing, filesystem permissions, and lifecycle management.

## 3. Scope

The future extension may support:

```text
- stream-oriented Unix domain sockets
- bind/listen/accept/read/write/close
- path-based socket addresses
- optional peer credential query where supported
```

Datagram Unix sockets are out of scope for the first IPC extension.

## 4. Data model extension

```lean
inductive LocalAddr where
  | path : String -> LocalAddr

inductive IoEndpoint where
  | tcpLocal  : TcpBindAddr -> IoEndpoint
  | tcpRemote : RemoteAddr -> IoEndpoint
  | unixPath  : LocalAddr -> IoEndpoint
```

Do not overload TCP-specific structures for Unix sockets.

## 5. Filesystem lifecycle

Unix socket paths require explicit lifecycle policy.

```text
- Should iotakt unlink an existing path before bind?
- Should iotakt unlink the socket path after close?
- What permissions should be set on parent directory and socket path?
```

Default policy should be conservative:

```text
- never unlink an existing path unless explicitly requested
- never create parent directories implicitly
- document that directory permissions are the primary access-control mechanism
```

## 6. Peer credentials

Peer credential APIs vary across platforms. If supported, they must be represented as optional, platform-classified native information.

```lean
inductive PeerCredential where
  | unsupported
  | available : uid : UInt32 -> gid : UInt32 -> pid? : Option UInt32 -> PeerCredential
  | failed : IoErrno -> PeerCredential
```

## 7. Security considerations

Unix sockets can be safer than TCP for local control, but only if filesystem permissions are correct. iotakt must not imply that local sockets are automatically secure.

## 8. Acceptance criteria

- This extension does not change TCP model invariants.
- Unix socket path lifecycle is explicit.
- Native support is optional and platform-gated.
- Tests cover stale path behavior and permission-denied behavior where possible.
