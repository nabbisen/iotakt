# Keep-Alive Support & the Consumer Pattern

**iotakt — v0.10 design notes**

v0.10 adds the I/O-boundary building blocks an HTTP server needs for
keep-alive connections and request-size safety. **iotakt does not include
an HTTP server** — routing, handler dispatch, and keep-alive *policy* belong
to a separate consumer (the future **jemmet** project), per iotakt's
non-goals (RFC 001). This page documents the building blocks iotakt
provides and shows, in *example* code, how a consumer composes them.

---

## What iotakt provides (building blocks)

The readers below accept raw fds and are therefore explicitly named `unsafe`; they
are provisional compatibility helpers, not part of RFC 064's checked `FdKey`
surface. RFC 069 decides their final ownership.

### Request-size limits (`unsafeReadFull` / `unsafeReadFromBuffer`)

Both readers take a `maxBytes` bound and return `ReadResult.tooLarge` when
a request exceeds it — slow-loris and oversized-body protection. The limit
is checked in every read phase: header flood (no terminator), a declared
`Content-Length` over the bound, or a chunked body that grows past it.
Adding `.tooLarge` is compiler-enforced: every consumer match on
`ReadResult` must handle it.

### Pipelining-correct buffered reads (`unsafeReadFromBuffer`)

HTTP/1.1 connections are keep-alive by default; a client may **pipeline**
several requests, which can all arrive in a single `recv`. A naive reader
that starts a fresh buffer each call drops the trailing requests.
`unsafeReadFromBuffer` carries a leftover buffer:

```lean
unsafeReadFromBuffer fd initial maxBytes maxPolls
  : IO (ReadResult × ByteArray)   -- (parsed request, bytes of the NEXT request)
```

It computes exactly where the current request ends — header terminator for
bodyless requests, `headerEnd + Content-Length` for CL bodies, the position
past `0\r\n\r\n` for chunked — and returns everything after as leftover:

```text
recv: [req1][req2][req3]
  unsafeReadFromBuffer  (req1, [req2][req3])
  unsafeReadFromBuffer  (req2, [req3])
  unsafeReadFromBuffer  (req3, [])
```

`findHeaderEnd` exposes the byte offset past the header terminator for
consumers that frame manually. These are reusable *reading primitives* at
the I/O boundary — not a server.

---

## What a consumer adds (NOT iotakt)

A keep-alive HTTP server — the future jemmet — adds the *policy*: a
configured router and handler dispatch, the decision to keep a connection
alive (reading the `Connection` header), the serve loop, and status-code
policy (e.g. mapping `.tooLarge` to `413`). None of that is iotakt's
responsibility; RFC 001 excludes HTTP routing and protocol policy.

### Reference consumer example

`examples/ReferenceServer.lean` is a **demonstration** (not a library
module) that composes the building blocks into a working keep-alive server.
The serve loop, router, and keep-alive policy live in the example — never in
an iotakt library module:

```lean
def serveConnection (fd : Int) : IO Nat := do
  let mut leftover := ByteArray.empty
  ...
  let (result, rest) <- unsafeReadRequestBuffered fd leftover maxBytes 30
  leftover := rest
  match result with
  | .request req =>
      let alive := HttpRequest.keepAlive req
      let resp := appRouter.dispatchRequest req
      -- send resp; keepGoing := alive
  | .tooLarge => -- send 413; stop
  | _ => -- stop
```

It serves `/`, `/health`, `/users/:id` (JSON-ish), `/echo`, and `/a`,`/b`,
verified live with curl — `curl /a /b` reuses one connection and returns
`AB`. Its OS contact uses explicitly unsafe compatibility helpers exported through
`Iotakt.Server`; the example demonstrates composition but is not a stable consumer
recommendation.

---

## The boundary, restated

iotakt owns: fd lifecycle, readiness translation, body framing, the reading
primitives (`unsafeReadFull`, `unsafeReadFromBuffer`), size limits, the `Iotakt.Server`
handoff surface.

A consumer (jemmet, separately) owns: routing, handlers, keep-alive policy,
status-code mapping, the serve loop, application state, TLS.

iotakt stays a small, auditable I/O boundary. The server is a separate
project, built on this surface once iotakt is stable.
