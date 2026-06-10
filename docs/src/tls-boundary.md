# TLS Boundary Design

**iotakt — RFC 041**

This document specifies where TLS sits relative to iotakt. It is a design
artifact: iotakt does **not** implement TLS, and v0.6 ships no TLS code.
The purpose is to fix the boundary now so that a future TLS layer (in
henejt or a separate library) can be added without changing iotakt's
model or native shim.

---

## Principle: iotakt owns the fd, not the bytes' meaning

iotakt's job ends at "this fd is readable / writable, here are the raw
bytes." It has no opinion about whether those bytes are plaintext HTTP,
a TLS record, or anything else. This is consistent with the v0.1
non-goal list (RFC 001): *iotakt does not implement TLS, DNS, or HTTP.*

A TLS layer is therefore a **consumer** of iotakt, sitting between iotakt
and the application protocol:

```text
┌─────────────────────────────────────────┐
│ henejt (HTTP/1.1 routing, handlers)       │
├─────────────────────────────────────────┤
│ TLS layer (handshake, record framing)     │  ← future; not iotakt
│  - wraps a connected fd                    │
│  - plaintext API up, ciphertext down       │
├─────────────────────────────────────────┤
│ iotakt (readiness, fd lifecycle, recv/send)│  ← unchanged
├─────────────────────────────────────────┤
│ Linux epoll + sockets                      │
└─────────────────────────────────────────┘
```

---

## The handoff contract

When a TLS layer is added, the boundary works as follows:

1. **iotakt accepts the TCP connection** exactly as today: `acceptOne`
   returns a non-blocking, close-on-exec fd wrapped in an `FdKey`,
   registered in the registry and epoll.

2. **The TLS layer drives the handshake** using iotakt's `recv`/`send`
   on that fd. A TLS handshake is just more non-blocking reads and
   writes — the same `ReadResult` / `WriteResult` types apply. When the
   handshake needs to read, it calls `Io.recv`; when it needs to write,
   it calls `Io.send` (or enables write interest via the EventLoop).

3. **`wouldBlock` during the handshake** is handled identically to data
   I/O: the TLS layer yields, and the next readiness event resumes the
   handshake. iotakt's readiness-as-hint semantics (RFC §5.1) already
   cover this — a TLS `WANT_READ` / `WANT_WRITE` maps directly to
   waiting for the corresponding interest.

4. **After the handshake**, the TLS layer presents a plaintext
   `recv`/`send` API to henejt. Under the hood each plaintext `recv`
   may perform one or more iotakt `recv` calls to gather a full TLS
   record, decrypt it, and return plaintext.

5. **Close**: the TLS layer sends `close_notify` (one iotakt `send`),
   then iotakt closes the fd via `EventLoop.closeConnection` — which
   also cancels the owning Henret task (Gap 006).

---

## Why no iotakt changes are needed

| TLS need | iotakt mechanism (already present) |
|----------|-------------------------------------|
| Read handshake bytes | `Io.recv` → `ReadResult` |
| Write handshake bytes | `Io.send` → `WriteResult` |
| WANT_READ | wait for `IoEvent.readable` |
| WANT_WRITE | `EventLoop.enableWrite` → `IoEvent.writable` |
| Partial record reads | `WriteBuffer` pattern / actor accumulation |
| Connection close | `EventLoop.closeConnection` |
| fd lifecycle / generations | `FdKey` (unchanged) |

The TLS layer needs **buffering** of partial records — but that buffer is
owned by the TLS layer (or the connection actor), not by iotakt. This is
the same ownership rule as application byte buffers (RFC §15.1: iotakt
does not buffer application bytes).

---

## What iotakt must NOT do

- iotakt must not grow a `recvDecrypted` or any TLS-aware API.
- iotakt must not link a TLS library in its native shim.
- iotakt must not add TLS state to the registry or the model.
- The `IoEvent` vocabulary must stay protocol-neutral (no `handshakeComplete`).

If any of these become tempting, the boundary has been violated and the
TLS logic belongs one layer up.

---

## Future work (not v0.6)

- A `henejt-tls` or standalone `lean-tls` library that wraps an `FdKey`.
- A documented `TlsConn` type with plaintext `recv`/`send` over iotakt.
- Possibly an iotakt example showing the fd handoff (no real crypto —
  just demonstrating that the handshake-as-I/O pattern works).

These are recorded here so the boundary is fixed before any TLS code is
written. RFC 041 remains a design artifact until a TLS consumer exists.
