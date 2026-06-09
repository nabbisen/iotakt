# kqueue Compatibility Analysis

**iotakt — RFC 016**

This document records the model constraints that ensure `Iotakt.Model`
can accept a BSD/macOS `kqueue` native backend in a future release
without breaking any existing proofs or requiring model changes.

---

## Why kqueue semantics differ from epoll

Linux `epoll` and BSD/macOS `kqueue` share the general concept of
readiness notification, but differ in three ways that matter for iotakt:

| Property | epoll (Linux) | kqueue (BSD/macOS) |
|----------|---------------|--------------------|
| EOF on read side | Reported via `EPOLLHUP` or `EPOLLRDHUP` alongside `EPOLLIN` | Distinct `EV_EOF` flag on `EVFILT_READ` filter |
| Error reporting | `EPOLLERR` event alongside interest events | `EV_ERROR` flag with errno in `data` field |
| Event registration | Single fd registered once, event mask updated | One `kevent` per filter (`EVFILT_READ`, `EVFILT_WRITE` as separate events) |

Each difference has a corresponding invariant in `Iotakt.Model` that
ensures the model is not epoll-specific.

---

## Model invariant 1 — `IoEvent.eof` is distinct from `IoEvent.error`

`IoEvent` defines:

```lean
inductive IoEvent where
  | readable
  | writable
  | eof        -- peer closed the write side (distinct from error)
  | hangup     -- local side hung up (distinct from remote EOF)
  | error : Option IoErrno -> IoEvent
```

The kqueue `EV_EOF` flag on `EVFILT_READ` maps directly to
`IoEvent.eof`. If iotakt had used a combined "readable-or-eof" event,
kqueue's distinct EOF signal would have no clean mapping.

**Model constraint satisfied:** `IoEvent.eof` exists and is distinct
from both `readable` and `error`.

---

## Model invariant 2 — `IoEvent.hangup` is distinct from `IoEvent.eof`

On Linux, `EPOLLHUP` (local hangup) and `EPOLLRDHUP` (remote half-close)
are distinct flags. On kqueue, only `EV_EOF` exists (indicating the
remote peer closed its write side). The hangup/eof split at the model
level ensures that:

- `IoEvent.eof` — peer closed the write side (remote EOF) → maps to kqueue `EV_EOF`
- `IoEvent.hangup` — local side disconnected → maps to `EVFILT_READ` with `EV_EOF` (BSD) or a synthetic hangup

A kqueue backend that cannot distinguish these can map both to `eof`,
since both signal "no more data can be received on this direction". The
model's downstream consumers (actors) must handle both gracefully.

**Model constraint satisfied:** both variants exist; kqueue backend can
use `eof` for both without model changes.

---

## Model invariant 3 — `IoEvent.error` carries optional errno

```lean
| error : Option IoErrno -> IoEvent
```

On kqueue, `EV_ERROR` stores an errno in the `data` field of the
`kevent`. The `Option IoErrno` allows this to be passed through. On
epoll, `EPOLLERR` carries no errno directly (requires `getsockopt
SO_ERROR`). The `none` case handles both.

**Model constraint satisfied:** the error case accepts optional context.

---

## Model invariant 4 — Interest normalization is backend-neutral

`InterestSet` uses a pair of `Bool` fields (`read`, `write`) rather than
encoding epoll or kqueue flags:

```lean
structure InterestSet where
  read  : Bool
  write : Bool
```

`Iotakt.Native.Epoll.interestFlags` converts this to epoll's `EPOLLIN |
EPOLLOUT` masks. A future `Iotakt.Native.Kqueue.keventFilters` would
convert it to `EVFILT_READ` and `EVFILT_WRITE` kevent entries.

The key difference: kqueue registers one kevent per filter, while epoll
registers one fd with a combined event mask. The model uses an
`InterestSet` (not a mask), so the conversion layer can produce either
format. Modifying write interest requires `epoll_ctl MOD` on Linux and
a `DELETE + ADD` kevent on kqueue — but this is an implementation detail
in the native layer, invisible to the model.

**Model constraint satisfied:** `InterestSet` is backend-neutral.

---

## Model invariant 5 — `FdKey` generation is backend-neutral

The `FdKey(raw, generation)` scheme protects against stale events
regardless of whether the backend is epoll or kqueue. Both backends
return raw fd integers in their event structs; both can produce stale
events for recently-closed fds. The generation counter at the model
layer catches these before they reach actors.

kqueue's level-triggered vs edge-triggered behaviour per filter does not
change this: a stale event for a reused fd will fail the `resolveCurrent`
check regardless.

**Model constraint satisfied:** generation-based identity is
backend-neutral.

---

## What the kqueue backend will need (v0.3 implementation notes)

1. **`iotakt_kqueue_create`** — `kqueue()` with `O_CLOEXEC`.
2. **`iotakt_kqueue_register(kq, fd, filters)`** — one `kevent` for
   `EVFILT_READ` and optionally one for `EVFILT_WRITE`.
3. **`iotakt_kqueue_modify(kq, fd, add_write, remove_write)`** — add or
   remove the `EVFILT_WRITE` kevent without touching `EVFILT_READ`.
4. **`iotakt_kqueue_deregister(kq, fd)`** — delete both filters.
5. **`iotakt_kqueue_wait(kq, max_events, timeout_ms)`** — `kevent()` call;
   returns a ByteArray encoding n events (8 bytes each: fd + flags).
6. **Event normalization** in `Iotakt.Native.Kqueue`:
   - `EVFILT_READ` + `EV_EOF` → `IoEvent.eof` + `IoEvent.readable`
   - `EVFILT_READ` + `EV_ERROR` → `IoEvent.error (some errno)`
   - `EVFILT_READ` (no EOF) → `IoEvent.readable`
   - `EVFILT_WRITE` + `EV_EOF` → `IoEvent.hangup`
   - `EVFILT_WRITE` + `EV_ERROR` → `IoEvent.error (some errno)`
   - `EVFILT_WRITE` (no EOF/error) → `IoEvent.writable`

All six mappings stay within the existing `IoEvent` vocabulary. No model
changes are required to implement the kqueue backend.

---

## kqueue implementation status

| Component | Status |
|-----------|--------|
| `Iotakt.Model` — kqueue-aware vocabulary | ✅ Done (v0.1) |
| `Iotakt.Native.Kqueue` — native backend | 🔲 Deferred to v0.3+ |
| CI matrix: macOS runner | 🔲 Deferred to v0.3+ |

The pure model, fake poller, and Henret bridge build and pass all tests
on Linux. The kqueue native backend is isolated to `Iotakt.Native.Kqueue`
and can be added without touching any existing file.
