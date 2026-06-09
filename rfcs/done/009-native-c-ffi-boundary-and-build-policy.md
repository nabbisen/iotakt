# RFC 009: Native C FFI Boundary and Build Policy

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M3  
**Priority:** Critical  
**Primary layer:** Iotakt.Native

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

This RFC defines the optional raw C FFI boundary, its build policy, ownership restrictions, syscall wrapper shape, and conformance requirements.

## Motivation

The native boundary is where iotakt leaves the pure Lean model and enters POSIX/kernel reality. If this layer is too broad, stateful, or dependency-heavy, the project will lose its auditability. A raw C shim is sufficient for the v0.1 syscall surface and keeps the trusted boundary visible. This RFC makes that boundary explicit so implementation choices do not silently move proof-relevant logic into native code.

## Goals

- Use raw C for v0.1 native shim.
- Keep Lean-only default build.
- Flatten C structs across FFI boundary.
- Capture errno immediately.
- Forbid retained Lean pointers, background threads, native queues, and application-buffer malloc/free.
- Define strict compiler and sanitizer profiles.

## Non-Goals

- Do not implement Rust FFI in v0.1.
- Do not implement libuv/libevent abstraction.
- Do not expose C structs by value to Lean.
- Do not place actor ownership or registry state in C.

## External Design

Native modules are optional. The package should make it obvious whether a build is Lean-only or native-enabled.

Expected C files:

```text
native/iotakt_socket.c
native/iotakt_epoll.c
native/iotakt_errno.c
native/iotakt_lean_bytearray.c
```

Expected Lean modules:

```text
Iotakt/Native/Extern.lean
Iotakt/Native/Errno.lean
Iotakt/Native/Epoll.lean
Iotakt/Native/Socket.lean
```

## Data Model / Internal Design

Native result encodings may be scalar tagged results or Lean constructors created by small wrappers. FFI signatures should use simple types where possible:

```c
int iotakt_set_nonblock(int fd);
int iotakt_set_cloexec(int fd);
int iotakt_close(int fd);
int iotakt_epoll_wait(int epfd, int timeout_ms, lean_object **out_events);
```

The exact shape must respect Lean FFI ownership rules and avoid passing C structs by value.

## Lifecycle / Workflow

Build workflow:

```text
lake build                  # Lean-only model/proofs/tests
lake exe iotakt-fake-demo    # fake backend demo
lake build +native           # native-enabled build, exact profile name TBD
lake exe iotakt-native-test  # Linux native conformance tests
```

Native CI uses Linux for epoll. kqueue builds are future/deferred.

## Public API Impact

Extern declarations are internal unless they are safe wrappers. Public APIs must call safe Lean wrappers that translate native error encodings into typed results.

## Native Boundary Impact

This RFC is the native boundary. It requires wrappers for socket/bind/listen/accept or accept4/recv/send/close/fcntl/epoll operations.

## Henret Integration Impact

Native calls are invoked by the driver and socket APIs. They do not call Henret, do not store actor IDs, and do not inject messages.

## Security Considerations

Native code is the highest-risk boundary. Required hardening: `-Wall -Wextra -Werror`, sanitizer test profile, no long-lived Lean object pointers, errno capture, no native background threads.

## Proof Obligations

- No proof over C code is claimed in v0.1.
- Lean wrappers preserve typed result classification from native scalar encodings.
- Model proofs must not depend on unclassified native behavior.

## Test Obligations

- C compiles with strict warnings.
- ASAN/UBSAN profile where available.
- errno mapping tests.
- non-blocking and close-on-exec tests.
- native functions do not retain pointers across calls by code review.

## Trust / Assumption Changes

- Assume C compiler, OS headers, POSIX/kernel behavior, and Lean runtime FFI helpers behave according to their contracts.
- Native conformance is TESTED, not PROVEN.

## Architecture Gaps

- Lake native-profile ergonomics need implementation work.
- Lean FFI details may require adaptation to current Lean version.
- Cross-platform native build is deferred.

## Acceptance Criteria

- Lean-only build remains working.
- Native build is opt-in.
- C shim is small and audited.
- No application protocol or registry logic exists in C.
- Native wrappers have typed Lean safe wrappers.

## Alternatives Considered

- Rust shim: deferred/rejected for v0.1 due to extra toolchain layer.
- Use libuv/libevent: rejected as too heavy.
- Place registry in C userdata: rejected because it hides proof-relevant state.

## Open Questions

- Exact native build flag/profile name.
- Whether to use constructor-returning C helpers or scalar encodings for all wrappers.

