# jemmet Prototype — Design Notes

**Handoff material for the separate jemmet project. NOT part of iotakt.**

These notes accompany the prototype seed in `prototype/`. They capture the
design of a keep-alive HTTP/1.1 service built on iotakt's handoff surface,
so the jemmet project can start from a reasoned sketch.

---

## What jemmet adds on top of iotakt

iotakt provides the *mechanism*; jemmet provides the *service*: a configured
router, a serve loop, and keep-alive policy. Nothing in the prototype
touches an fd directly except through `Iotakt.Server`.

| Concern | Owner |
|---------|-------|
| fd lifecycle, readiness translation, body framing, reading primitives | **iotakt** |
| routing, handler dispatch, keep-alive policy, status-code mapping, serve loop, app state, TLS | **jemmet** |

## Request-size limits

The prototype passes a `maxBytes` bound to `readRequestBuffered`; iotakt
returns `ReadResult.tooLarge` when a request exceeds it (header flood,
oversized Content-Length, or oversized chunked body). jemmet maps that to a
`413 Payload Too Large` with `Connection: close`.

## Keep-alive and pipelining

HTTP/1.1 is keep-alive by default; a client may pipeline several requests
that arrive in a single `recv`. A naive reader drops the trailing ones.
iotakt's `readRequestBuffered` carries a leftover buffer:

```text
recv: [req1][req2][req3]
  readRequestBuffered  (req1, [req2][req3])
  readRequestBuffered  (req2, [req3])
  readRequestBuffered  (req3, [])
```

`serveConnection` feeds the leftover from each call into the next, so no
pipelined bytes are lost. It rewrites the response `Connection` header to
match the negotiated intent and stops on `Connection: close`, peer close, an
incomplete/too-large request, or `maxKeepAlive`.

## Driver

`run` is the connection driver: `runStepAuto` (adaptive timeout + idle
reaping from iotakt) → accept → `serveConnection` → `closeConnection`. The
bounded `iterations` count is for testability; a production jemmet would
loop until a shutdown signal and call `EventLoop.shutdown` (iotakt RFC 037)
to drain cleanly.

## Verified behavior (when this was an iotakt example)

Serving `/`, `/health`, `/users/:id` (JSON-ish), `/echo` (POST body), and
`/a`,`/b`, verified live with curl: `/users/42` → JSON, and `curl /a /b`
reusing one connection → `AB`.

## Suggested first steps for the jemmet project

1. Move `prototype/Jemmet.lean` and `prototype/JemmetDemo.lean` into the
   jemmet project; depend on iotakt; build against `Iotakt.Server`.
2. Replace the bounded driver loop with a shutdown-signal loop calling
   `EventLoop.shutdown`.
3. Add a real handler/middleware abstraction (the prototype dispatches
   straight through `Router`).
4. Add streaming (chunked) response bodies using `Iotakt.Chunked`.
5. Layer TLS at the boundary documented in iotakt RFC 041.
6. Keep the iotakt boundary honest: if you find yourself wanting to change
   iotakt to make a server feature easier, first check whether the feature
   belongs in jemmet instead.
