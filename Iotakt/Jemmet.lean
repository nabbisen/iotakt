import Iotakt.Server

/-!
# Iotakt.Jemmet (prototype)

A **prototype of the jemmet HTTP server** built entirely on the
`Iotakt.Server` handoff surface (v0.10). It is the first genuine downstream
consumer of iotakt — its purpose is to prove the handoff surface is
sufficient to build a real HTTP/1.1 service without reaching into iotakt
internals.

This lives in the iotakt repo as a reference consumer; the real jemmet will
eventually be its own project. It demonstrates:

- a `Router`-driven request/response cycle,
- **HTTP/1.1 keep-alive**: multiple requests served on one connection,
- request bodies in both framings via `readRequest`,
- request-size limits (`maxBytes` → 413),
- `runStepAuto` + idle reaping for connection lifetime.

## What jemmet adds on top of iotakt

iotakt provides the mechanism; jemmet provides the *service*: a configured
router, a serve loop, and the keep-alive policy. Nothing here touches an fd
directly except through `Iotakt.Server`.
-/

namespace Iotakt.Jemmet

open Iotakt.Server Iotakt.Loop Iotakt.Http Iotakt.RequestBody
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

/-- Send a response on `fd`, returning whether the full bytes were written. -/
def sendResponse (fd : Int) (resp : HttpResponse) : IO Unit := do
  let bytes := resp.toBytes
  let _ ← Io.send fd bytes 0 bytes.size
  pure ()

/-- Serve one connection with HTTP/1.1 keep-alive: read successive requests
on the same fd, dispatch each through the router, and respond. Carries a
leftover read buffer across requests so pipelined requests are not dropped.
Stops when the client sends `Connection: close`, the peer closes, a request
is incomplete/too-large, or `maxKeepAlive` requests have been served.

Returns the number of requests served on this connection. -/
def serveConnection (cfg : Config) (router : Router) (fd : Int) : IO Nat := do
  let mut served := 0
  let mut keepGoing := true
  let mut leftover := ByteArray.empty
  for _ in List.range cfg.maxKeepAlive do
    if !keepGoing then pure ()
    else
      let (result, rest) ← readFromBuffer fd leftover cfg.maxBytes 30
      leftover := rest
      match result with
      | .request req =>
          let wantsKeepAlive := HttpRequest.keepAlive req
          let resp := router.dispatchRequest req
          let resp :=
            { resp with headers :=
                resp.headers.filter (·.1.toLower != "connection")
                ++ [("Connection", if wantsKeepAlive then "keep-alive" else "close")] }
          sendResponse fd resp
          served := served + 1
          keepGoing := wantsKeepAlive
      | .tooLarge =>
          sendResponse fd payloadTooLarge
          served := served + 1
          keepGoing := false
      | .incomplete => keepGoing := false
      | .error _    => keepGoing := false
  return served

/-- Run the jemmet service: accept connections, serve each (keep-alive),
close. Bounded by `iterations` driver steps for testability. Returns the
total number of requests served. -/
def run (cfg : Config) (router : Router) (iterations : Nat := 50) :
    IO (Except String Nat) := do
  let some loop ← EventLoop.create { maxReadBytes := cfg.maxBytes }
    | return .error "epoll_create failed"
  let (loop1, ok) ← loop.addListener cfg.port
  if !ok then
    loop.destroy
    return .error s!"bind to port {cfg.port} failed"

  let mut loop := loop1.withIdleTimeout cfg.idleTimeoutMs
  let mut total := 0
  for _ in List.range iterations do
    let (l', events) ← loop.runStepAuto
    loop := l'
    for ev in events do
      match ev with
      | .newConnection key _ =>
          let n ← serveConnection cfg router key.raw
          total := total + n
          loop ← loop.closeConnection key
      | _ => pure ()
  loop.destroy
  return .ok total

end Iotakt.Jemmet
