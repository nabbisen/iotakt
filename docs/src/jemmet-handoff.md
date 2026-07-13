# jemmet Handoff Surface

This document is the consumer contract for **jemmet** (or any Lean HTTP
server) building on iotakt. It is the iotakt-side mirror of what
`henret-integration.md` does for the Henret dependency: it states exactly
what iotakt provides, what jemmet owns, and where the boundary sits.

The single import is `Iotakt.Server` (v0.9).

---

## What iotakt provides

```text
import Iotakt.Server   -- brings the whole stack transitively

Iotakt.Server
├── EventLoop      — non-blocking accept/read/write, adaptive poll timeout,
│                    idle reaping, Gap 006 connection teardown (Iotakt.Loop)
├── HttpRequest    — request line + headers + body (Iotakt.Http)
├── HttpResponse   — response building, Content-Length / keep-alive (Iotakt.Http)
├── RequestBody    — readFull / readFromBuffer: headers + body, both framings
├── Chunked        — chunked transfer encoding, both directions (Iotakt.Chunked)
└── WriteBuffer    — partial-write-safe response streaming (Iotakt.WriteBuffer)

Routing is NOT in this surface (RFC 001 non-goal). `Iotakt.Router` is an
optional convenience reached via a separate `import Iotakt.Router`; it carries
no stability promise.
```

### The one call that matters: `readRequest`

```lean
match ← Iotakt.Server.readRequest fd 65536 30 with
| .request req => ...   -- req.body is fully reassembled (CL or chunked)
| .incomplete  => ...   -- peer closed before the body finished
| .error e     => ...
```

`readRequest` (= `RequestBody.readFull`) reads the header block, determines
the body framing from the headers, and reassembles the body:

| Header | Framing | Behaviour |
|--------|---------|-----------|
| `Content-Length: N` | exactly N bytes | reads until N body bytes buffered |
| `Transfer-Encoding: chunked` | chunked | reads to `0\r\n\r\n`, decodes |
| neither | none | empty body (typical GET) |

Chunked takes precedence over Content-Length per RFC 7230 §3.3.3.

### Streaming a response

```lean
let _ ← Io.send fd (Iotakt.Server.chunkedResponseHeader 200 "OK") 0 _
for piece in pieces do
  let frame := Iotakt.Server.encodeChunk piece
  let _ ← Io.send fd frame 0 frame.size
let _ ← Io.send fd Iotakt.Server.chunkedTerminator 0 _
```

---

## What jemmet owns

iotakt deliberately stops at the I/O boundary. jemmet owns:

- routing *policy* (iotakt provides the `Router` mechanism; jemmet decides the routes);
- request handlers and application state;
- content negotiation, compression, caching policy;
- sessions, authentication, authorization;
- TLS — via a consumer layer wrapping an `FdKey` (see `tls-boundary.md`);
- HTTP semantics beyond framing (status code policy, conditional requests, etc.).

This is the split stated in the requirements: iotakt is the socket-readiness
boundary, jemmet is the HTTP server. `Iotakt.Server` is where they meet.

---

## A minimal jemmet-style server

```lean
import Iotakt.Server
import Iotakt.Router   -- optional convenience; not part of the stable surface
open Iotakt.Server Iotakt.Loop Iotakt.Http Iotakt.RequestBody
     Iotakt.Router Iotakt.Native Iotakt.Model

def router : Router :=
  Router.empty
    |>.get  "/"          (fun _ => HttpResponse.ok "home")
    |>.get  "/users/:id" (fun p => HttpResponse.ok (p.get "id"))
    |>.post "/upload"    (fun _ => HttpResponse.ok "received")

partial def serve (loop : EventLoop) : IO Unit := do
  let (loop, events) ← loop.runStepAuto
  for ev in events do
    match ev with
    | .newConnection key _ =>
        match ← readRequest key.raw 65536 30 with
        | .request req =>
            let resp := (router.dispatchRequest req).toBytes
            let _ ← Io.send key.raw resp 0 resp.size
            let _ ← EffectError.orThrow (← loop.closeConnection key)
        | _ => let _ ← EffectError.orThrow (← loop.closeConnection key)
    | _ => pure ()
  serve loop

def main : IO Unit := do
  let some loop ← EventLoop.create | return
  let (loop, _) ← loop.addListener 8080
  serve (loop.withIdleTimeout 30000)
```

The `iotakt-upload-server` and `iotakt-routing-server` examples are working
versions of this pattern.

---

## Note on `open` vs the single import

`import Iotakt.Server` brings the entire stack into scope transitively, and
the consolidated chunked/read abbrevs (`encodeChunk`, `readRequest`,
`decodeChunked`, …) are available as `Iotakt.Server.*`. Dot-notation
*constructors* on re-exported types (e.g. `HttpResponse.ok`) live in their
original namespaces, so a consumer still `open`s `Iotakt.Http` and
`Iotakt.Loop` for ergonomic dot-notation. (`Iotakt.Router`, if used, needs
its own `import Iotakt.Router` — it is not part of the `Iotakt.Server`
surface.) The single import is what guarantees the rest of the stack is
present and version-aligned; the `open`s are a notational convenience.

---

## Stability

Everything reachable from `Iotakt.Server` is part of the v0.x public
surface. Internal module *structure* may change without being breaking, as
long as the names and behaviours reachable from `Iotakt.Server` are
preserved — the same guarantee `Iotakt.Api` carries for the core model
(RFC 017).
