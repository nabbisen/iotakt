# RFC 021: BSD and macOS kqueue Native Backend Implementation

**Status:** Future / v0.2 Candidate  
**Milestone:** M6  
**Priority:** High for BSD/macOS support  
**Primary layer:** Iotakt.Native.Kqueue  
**Project:** iotakt  
**Stack position:** `jemmet → iotakt → henret`  
**Date:** 2026-06-08

---

## Document Intent

This RFC belongs to the continuation set after the v0.1 core RFC batch. It is intentionally detailed enough to guide implementation later, but it must not silently expand the v0.1 release boundary unless its status explicitly says so.

The governing principles remain:

- pure Lean model first,
- optional native boundary,
- no hidden async runtime,
- no C-side application buffering,
- readiness is a hint rather than a guarantee,
- file descriptors are identified by `FdKey(raw_fd, generation)`, not by raw fd alone,
- proof/trust/test classification is mandatory for every correctness claim.

## Summary

This RFC designs the future `kqueue` backend that will implement the normalized iotakt poller interface on OpenBSD, FreeBSD, NetBSD, and macOS. The v0.1 model must already be compatible with this RFC, but the native implementation may be delivered after the first Linux `epoll` release.

## Motivation

The first native backend is Linux `epoll`, but iotakt should not become epoll-shaped. OpenBSD and macOS environments expose different readiness and EOF semantics through `kqueue` / `kevent`. Designing the backend now prevents the pure model from accidentally encoding Linux-only assumptions.

## Goals

- Define how `EVFILT_READ`, `EVFILT_WRITE`, `EV_EOF`, and error flags map to normalized `IoEvent` values.
- Preserve the same `FdKey` registry and stale-event rejection semantics used by the epoll backend.
- Define a flat C ABI for `kevent` without returning native structs by value.
- Keep kqueue implementation optional and feature-gated.
- Ensure OpenBSD can be used as a strict POSIX/networking conformance environment later.

## Non-Goals

- Do not implement TLS, DNS, or HTTP protocol logic.
- Do not emulate epoll behavior exactly where kqueue semantics differ.
- Do not alter the pure model to expose backend-specific flags directly to jemmet or Henret.
- Do not make kqueue a blocker for the first Linux-focused native release.

## External Design

The public user-facing behavior must remain identical to the epoll backend: callers register read/write interest for an `FdKey`, the driver waits for events, the backend returns normalized readiness hints, and the bridge injects bounded messages into Henret-owned actor mailboxes.

Normalized mapping policy:

```text
EVFILT_READ without EV_EOF  -> IoEvent.readable
EVFILT_WRITE                -> IoEvent.writable
EV_EOF on stream            -> IoEvent.eof or IoEvent.hangup depending on context
kevent data/error condition -> IoEvent.error errno
unknown/unsupported flags   -> backend diagnostic, no public model expansion without RFC
```

EOF must be first-class because kqueue can surface end-of-file more explicitly than some epoll flows. The model should already distinguish `eof`, `hangup`, and `error` so the backend can map faithfully without leaking OS flags upward.

## Data Model / Internal Design

Suggested modules:

```text
Iotakt.Native.Kqueue.Types
Iotakt.Native.Kqueue.CApi
Iotakt.Native.Kqueue.Normalize
Iotakt.Native.Kqueue.Tests
```

The C boundary should flatten `struct kevent` into an array of records expressible as primitive fields:

```lean
structure NativeKqueueEvent where
  rawFd    : RawFd
  filter   : Int
  flags    : UInt32
  fflags   : UInt32
  data     : Int
  errnoVal : Int
```

The pure normalizer converts this backend record into `RawPollEvent`, then the existing registry translator resolves `RawFd -> FdKey`. No backend should directly create Henret messages.

## Lifecycle / Workflow

Backend workflow:

```text
open kqueue fd
register listener/stream raw fd with read/write filters
wait via kevent(timeout)
copy returned event fields into Lean-visible flat records
normalize flat records to RawPollEvent
pass RawPollEvent list to shared translation/coalescing layer
```

The close workflow must remove filters where needed and then close the stream fd. The kqueue descriptor itself is owned by the driver backend and closed when the driver shuts down.

## Public API Impact

No change to the stable iotakt public API should be necessary if RFC 004 and RFC 005 were designed correctly. The backend selector may gain:

```lean
inductive NativeBackend where
  | epoll
  | kqueue
```

or use module-level feature imports instead of a runtime selector.

## Native Boundary Impact

The native boundary adds wrappers for:

```text
iotakt_kqueue_create
iotakt_kqueue_register_read
iotakt_kqueue_register_write
iotakt_kqueue_unregister_read
iotakt_kqueue_unregister_write
iotakt_kqueue_wait
iotakt_kqueue_close
```

No wrapper may retain Lean pointers. No wrapper may allocate application buffers. Returned event arrays must use Lean-owned objects or copied primitive arrays under documented ownership rules.

## Security Considerations

The backend must preserve non-blocking fd policy, close-on-exec policy, stale-event rejection, bounded event batch size, and no unbounded mailbox injection. OpenBSD/macOS differences around `SO_NOSIGPIPE` must be handled in the send/stream layer, not in kqueue itself.

## Proof Obligations

The existing backend-independent proof obligations should remain valid:

```text
no unknown injection
no stale generation injection
interest soundness
bounded coalesced readiness
closed resources do not become active
```

Additional proof target: kqueue normalization never creates a public event outside the backend-independent `IoEvent` vocabulary.

## Test Obligations

Required tests:

- fake kqueue normalization unit tests,
- socketpair read readiness test,
- EOF detection test,
- write readiness test,
- unregister-after-close stale event test,
- EINTR behavior test if practically injectable,
- OpenBSD CI job when available,
- macOS CI job if supported by the release target.

## Trust / Assumption Changes

Assume host `kevent` implements documented kernel semantics. Assume the C wrapper faithfully copies event fields and errno values. These assumptions must be listed in the proof/trust/test matrix.

## Architecture Gaps

OpenBSD and macOS differ in detail. A single kqueue backend may need small platform conditionals. The pure model should not expose those conditionals. CI coverage may be weaker for OpenBSD unless a dedicated runner is available.

## Acceptance Criteria

- kqueue backend compiles behind an explicit feature/backend option.
- Normalized events match the backend-independent model.
- No public API change is required for ordinary users.
- Conformance tests pass on at least one kqueue platform.
- The trust matrix records all native assumptions.

## Alternatives Considered

Use only epoll and defer BSD/macOS indefinitely: rejected because the model should remain portable. Use libuv: rejected because it violates minimal dependency and transparent boundary goals. Emulate epoll on BSD: rejected because iotakt should respect native platform primitives.

## Open Questions

- Should OpenBSD be the primary kqueue reference platform?
- Should macOS be considered Tier 1 or Tier 2 initially?
- Should runtime backend selection exist, or should users import platform-specific modules?
