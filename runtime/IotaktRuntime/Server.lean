import IotaktRuntime.Loop
import IotaktRuntime.Http
import IotaktRuntime.Chunked
import IotaktRuntime.RequestBody
import IotaktRuntime.WriteBuffer

/-!
# IotaktRuntime.Server

The **jemmet handoff surface** (v0.9): the consolidated public API a Lean
HTTP server (jemmet) builds on. Import this one module to get the full
request/response stack without reaching into iotakt internals.

## What this gives jemmet

```text
IotaktRuntime.Server
├── EventLoop        — non-blocking accept/read/write, idle reaping (IotaktRuntime.Loop)
├── HttpRequest      — request parsing + header access
├── HttpResponse     — response building (Content-Length or keep-alive)
├── RequestBody      — body-aware reading (Content-Length + chunked)
├── Chunked          — chunked transfer encoding (both directions)
└── WriteBuffer      — partial-write-safe response streaming
```

Routing is **not** part of this surface (an RFC 001 non-goal). The optional
`IotaktRuntime.Router` convenience module is available via a separate
`import IotaktRuntime.Router`, but carries no stability promise — a consumer
(jemmet) owns real dispatch.

## The boundary iotakt guarantees

iotakt owns: fd lifecycle, readiness translation, body framing, the actor
bridge to Henret. jemmet owns: routing policy, handlers, application state,
content negotiation, sessions, TLS (via a consumer layer — see
`docs/src/tls-boundary.md`).

This split is the same one stated in the requirements: iotakt is the I/O
boundary, jemmet is the HTTP server. `IotaktRuntime.Server` is where they meet.

## Stability

Only `EventLoop`, `LoopEvent`, and `LoopError` are stable runtime identities during
the RFC 064–070 remediation train. Protocol/framing re-exports remain provisional
compatibility conveniences pending RFC 069's ownership decision. See
`docs/src/api-stability.md`; no runtime adoption recommendation is currently active.

## Minimal jemmet-style server

```lean
import IotaktRuntime.Server
import IotaktRuntime.Router   -- optional convenience; not part of the stable surface
open IotaktRuntime.Server IotaktRuntime.Router

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

namespace IotaktRuntime.Server

-- ── Event loop / driver ────────────────────────────────────────────────
export IotaktRuntime.Loop (EventLoop LoopEvent LoopError)

-- ── Routing: deliberately NOT exported ───────────────────────────────────
-- Routing is an iotakt non-goal (RFC 001); a consumer (jemmet) owns dispatch.
-- The optional `IotaktRuntime.Router` convenience module remains for examples and
-- quick starts, imported directly by code that wants it — it carries no
-- stability promise. See docs/src/api-stability.md.

-- ── HTTP messages ──────────────────────────────────────────────────────
export IotaktRuntime.Http (HttpRequest HttpResponse)

-- ── Body reading + framing ────────────────────────────────────────────────
export IotaktRuntime.RequestBody (BodyFraming ReadResult)

-- ── Write buffering ──────────────────────────────────────────────────────
export IotaktRuntime.WriteBuffer (WriteBuffer)

/-- The chunked transfer encoding namespace, re-exported under the handoff
surface so jemmet can stream responses without importing internals. -/
abbrev encodeChunk := @IotaktRuntime.Chunked.encodeChunk
abbrev chunkedTerminator := IotaktRuntime.Chunked.terminator
abbrev chunkedResponseHeader := @IotaktRuntime.Chunked.responseHeader
abbrev decodeChunked := @IotaktRuntime.Chunked.decode
abbrev isChunked := @IotaktRuntime.Chunked.isChunked

/-- Read a full request (headers + body, both framings) from an fd.
The one call jemmet needs to get a dispatch-ready `HttpRequest`. -/
abbrev readRequest := @IotaktRuntime.RequestBody.readFull

/-- Keep-alive-aware read carrying leftover bytes between pipelined requests
on one connection. -/
abbrev readRequestBuffered := @IotaktRuntime.RequestBody.readFromBuffer

/-- Determine a request's body framing from its headers. -/
abbrev bodyFramingOf := @IotaktRuntime.RequestBody.framingOf

end IotaktRuntime.Server
