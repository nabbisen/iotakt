# jemmet Prototype & Keep-Alive

**iotakt — v0.10 design notes**

v0.10 delivers the first genuine downstream consumer of iotakt: a prototype
of **jemmet**, the HTTP server, built entirely on the `Iotakt.Server`
handoff surface. Its purpose is to prove the surface is sufficient to build
a real HTTP/1.1 service — and in doing so it exercises three new pieces:
request-size limits, keep-alive request loops, and pipelining-correct
buffered reads.

---

## 1. Request-size limits (`readFull` / `readFromBuffer`)

Both readers take a `maxBytes` bound and return `ReadResult.tooLarge` when
a request exceeds it — slow-loris and oversized-body protection. The limit
is checked in every read phase:

- header accumulation exceeding `maxBytes` (header flood, no terminator);
- a declared `Content-Length` greater than `maxBytes`;
- a chunked body whose accumulated bytes exceed `maxBytes`.

`jemmet` maps `.tooLarge` to a `413 Payload Too Large` with
`Connection: close`. The compiler enforces that every consumer handles the
new variant — adding `.tooLarge` immediately surfaced the missing case in
the upload server, which is exactly the safety the type system should give.

---

## 2. Keep-alive and pipelining (`readFromBuffer`)

HTTP/1.1 connections are keep-alive by default: a client sends several
requests on one connection. Two cases:

- **Sequential** — client sends request 1, waits for response 1, sends
  request 2. Each request arrives in its own read.
- **Pipelined** — client sends requests 1, 2, 3 back-to-back without
  waiting. They can all arrive in a *single* `recv`.

The naive `readFull` (one fresh buffer per call) drops pipelined requests:
after parsing request 1, the bytes of requests 2–3 that arrived in the same
`recv` are discarded. `readFromBuffer` fixes this by carrying a leftover
buffer:

```lean
readFromBuffer fd initial maxBytes maxPolls
  : IO (ReadResult × ByteArray)   -- (parsed request, bytes of the NEXT request)
```

It computes exactly where the current request ends — header terminator for
bodyless requests, `headerEnd + Content-Length` for CL bodies, the position
past `0\r\n\r\n` for chunked — and returns everything after as the leftover.
The serve loop feeds that leftover into the next call, so no bytes are lost.

```text
recv: [req1][req2][req3]
  readFromBuffer ⟶ (req1, [req2][req3])
  readFromBuffer ⟶ (req2, [req3])
  readFromBuffer ⟶ (req3, [])
```

Verified: three pipelined requests on one socketpair are all served
(v0.10 test); and `curl /a /b` (which reuses one connection) returns `AB`.

---

## 3. The jemmet prototype (`Iotakt.Jemmet`)

A small service framework on the handoff surface:

```lean
structure Config where
  port          : UInt16 := 8080
  maxBytes      : Nat := 65536     -- per-request limit (413 above)
  idleTimeoutMs : Nat := 30000     -- connection idle timeout
  maxKeepAlive  : Nat := 100       -- max requests per connection

def serveConnection (cfg) (router) (fd) : IO Nat   -- keep-alive serve loop
def run (cfg) (router) (iterations) : IO (Except String Nat)
```

`serveConnection` is the keep-alive loop: read (buffered) → dispatch →
respond → repeat until `Connection: close`, peer close, an
incomplete/too-large request, or `maxKeepAlive`. It rewrites the response's
`Connection` header to match the negotiated intent.

`run` is the driver: `runStepAuto` (adaptive timeout, idle reaping) →
accept → `serveConnection` → close.

### What this proves

The prototype touches no fd directly except through `Iotakt.Server`. It
demonstrates that the handoff surface — `EventLoop`, `Router`, `HttpRequest`/
`HttpResponse`, `readRequestBuffered`, `Chunked` — is sufficient to build a
real keep-alive HTTP/1.1 service. The `iotakt-jemmet-demo` example serves
`/`, `/health`, `/users/:id` (JSON-ish), `/echo` (POST body), and `/a`,`/b`
(keep-alive), all verified live with curl.

### Boundary, unchanged

jemmet owns the service (routes, handlers, keep-alive policy, 413 mapping);
iotakt owns the mechanism (fd lifecycle, readiness, body framing). The
prototype lives in the iotakt repo as a reference consumer; the real jemmet
will be its own project built on the same surface.
