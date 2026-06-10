import Iotakt.Server
import Iotakt.Router  -- optional convenience module; not part of the stable Server surface

/-!
# Jemmet (prototype seed — NOT part of iotakt)

This file is **handoff material for the separate jemmet project**, not a
module that iotakt builds or ships. It is preserved here so the future
jemmet project can start from a working sketch instead of a blank page.

It is a prototype of the **jemmet HTTP server**, built entirely on the
`Iotakt.Server` handoff surface: a configured router, a keep-alive serve
loop, and the connection driver. It demonstrates that iotakt's surface is
sufficient to build a real HTTP/1.1 service — which is the whole reason the
iotakt/jemmet boundary is drawn where it is.

**Boundary reminder.** Everything in this file is the *server's*
responsibility (routing, keep-alive policy, status-code mapping, the serve
loop), which is exactly why it does not live in the iotakt library. iotakt
provides the I/O-boundary building blocks (`readRequestBuffered`, body
framing, the `EventLoop`); jemmet composes them.

To adopt: move this file into the jemmet project, keep iotakt as a
dependency, and grow it (handler abstractions, middleware, streaming
responses, TLS via the RFC 041 boundary, etc.).
-/

namespace Jemmet

open Iotakt.Server Iotakt.Loop Iotakt.Http Iotakt.Router Iotakt.RequestBody
open Iotakt.Native Iotakt.Model

/-- jemmet service configuration. -/
structure Config where
  port          : UInt16 := 8080
  maxBytes      : Nat := 65536       -- per-request size limit (413 above)
  idleTimeoutMs : Nat := 30000       -- connection idle timeout
  maxKeepAlive  : Nat := 100         -- max requests per connection
  deriving Repr

/-- A 413 Payload Too Large response. -/
def payloadTooLarge : HttpResponse :=
  { statusCode := 413
    statusText := "Payload Too Large"
    body       := "request too large".toUTF8
    headers    := [("Content-Type", "text/plain"),
                   ("Content-Length", toString "request too large".toUTF8.size),
                   ("Connection", "close")] }

/-- Send a response on `fd`. -/
def sendResponse (fd : Int) (resp : HttpResponse) : IO Unit := do
  let bytes := resp.toBytes
  let _ ← Io.send fd bytes 0 bytes.size
  pure ()

/-- Serve one connection with HTTP/1.1 keep-alive. Carries a leftover read
buffer across requests so pipelined requests are not dropped. Stops on
`Connection: close`, peer close, an incomplete/too-large request, or
`maxKeepAlive`. Returns the number of requests served. -/
def serveConnection (cfg : Config) (router : Router) (fd : Int) : IO Nat := do
  let mut served := 0
  let mut keepGoing := true
  let mut leftover := ByteArray.empty
  for _ in List.range cfg.maxKeepAlive do
    if !keepGoing then pure ()
    else
      let (result, rest) ← readRequestBuffered fd leftover cfg.maxBytes 30
      leftover := rest
      match result with
      | .request req =>
          let alive := HttpRequest.keepAlive req
          let baseResp := router.dispatchRequest req
          let connVal := if alive then "keep-alive" else "close"
          let hdrs := baseResp.headers.filter (·.1.toLower != "connection")
                        ++ [("Connection", connVal)]
          sendResponse fd { baseResp with headers := hdrs }
          served := served + 1
          keepGoing := alive
      | .tooLarge =>
          sendResponse fd payloadTooLarge
          served := served + 1
          keepGoing := false
      | _ => keepGoing := false
  return served

/-- Run the jemmet service: accept connections, serve each (keep-alive),
close. Bounded by `iterations` driver steps for testability. -/
def run (cfg : Config) (router : Router) (iterations : Nat := 50) :
    IO (Except String Nat) := do
  let some loop ← EventLoop.create { maxReadBytes := cfg.maxBytes }
    | return .error "epoll_create failed"
  let (loop1, ok) ← loop.addListener cfg.port
  if !ok then
    loop.destroy
    return .error s!"bind to port {cfg.port} failed"

  let mut loop := (loop1.withIdleTimeout cfg.idleTimeoutMs)
  let mut total := 0
  for _ in List.range iterations do
    let (l', events) ← loop.runStepAuto
    loop := l'
    for ev in events do
      match ev with
      | .newConnection key _ =>
          total := total + (← serveConnection cfg router key.raw)
          loop ← loop.closeConnection key
      | _ => pure ()
  loop.destroy
  return .ok total

end Jemmet
