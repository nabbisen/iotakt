import Iotakt.Loop
import Iotakt.Router
import Iotakt.Http
import Iotakt.Chunked
import Iotakt.RequestBody
import Iotakt.WriteBuffer

/-!
# Iotakt.Server

The **henejt handoff surface** (v0.9): the consolidated public API a Lean
HTTP server (henejt) builds on. Import this one module to get the full
request/response stack without reaching into iotakt internals.

## What this gives henejt

```text
Iotakt.Server
├── EventLoop        — non-blocking accept/read/write, idle reaping (Iotakt.Loop)
├── Router           — path + method dispatch with :param capture
├── HttpRequest      — request parsing + header access
├── HttpResponse     — response building (Content-Length or keep-alive)
├── RequestBody      — body-aware reading (Content-Length + chunked)
├── Chunked          — chunked transfer encoding (both directions)
└── WriteBuffer      — partial-write-safe response streaming
```

## The boundary iotakt guarantees

iotakt owns: fd lifecycle, readiness translation, body framing, the actor
bridge to Henret. henejt owns: routing policy, handlers, application state,
content negotiation, sessions, TLS (via a consumer layer — see
`docs/src/tls-boundary.md`).

This split is the same one stated in the requirements: iotakt is the I/O
boundary, henejt is the HTTP server. `Iotakt.Server` is where they meet.

## Stability

Everything re-exported here is part of the v0.x public surface. The
consumer contract is in `docs/src/henejt-handoff.md`.

## Minimal henejt-style server

```lean
open Iotakt.Server

def router : Router :=
  Router.empty
    |>.get  "/"          (fun _ => HttpResponse.ok "home")
    |>.get  "/users/:id" (fun p => HttpResponse.ok (p.get "id"))
    |>.post "/upload"    (fun _ => HttpResponse.ok "received")

def serve : IO Unit := do
  let some loop ← EventLoop.create | return
  let (loop, _) ← loop.addListener 8080
  let mut loop := loop.withIdleTimeout 30000
  -- driver loop: accept → readFull → router.dispatch → respond → close
  ...
```
-/

namespace Iotakt.Server

-- ── Event loop / driver ────────────────────────────────────────────────
export Iotakt.Loop (EventLoop LoopEvent)

-- ── Routing ──────────────────────────────────────────────────────────────
export Iotakt.Router (Router Route RouteParams Handler)

-- ── HTTP messages ──────────────────────────────────────────────────────
export Iotakt.Http (HttpRequest HttpResponse)

-- ── Body reading + framing ────────────────────────────────────────────────
export Iotakt.RequestBody (BodyFraming ReadResult)

-- ── Write buffering ──────────────────────────────────────────────────────
export Iotakt.WriteBuffer (WriteBuffer)

/-- The chunked transfer encoding namespace, re-exported under the handoff
surface so henejt can stream responses without importing internals. -/
abbrev encodeChunk := @Iotakt.Chunked.encodeChunk
abbrev chunkedTerminator := Iotakt.Chunked.terminator
abbrev chunkedResponseHeader := @Iotakt.Chunked.responseHeader
abbrev decodeChunked := @Iotakt.Chunked.decode
abbrev isChunked := @Iotakt.Chunked.isChunked

/-- Read a full request (headers + body, both framings) from an fd.
The one call henejt needs to get a dispatch-ready `HttpRequest`. -/
abbrev readRequest := @Iotakt.RequestBody.readFull

/-- Determine a request's body framing from its headers. -/
abbrev bodyFramingOf := @Iotakt.RequestBody.framingOf

end Iotakt.Server
