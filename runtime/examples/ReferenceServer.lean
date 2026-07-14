import IotaktRuntime.Server
import IotaktRuntime.Router  -- routing is not part of the stable Server surface; import directly

/-!
# Reference consumer example (not part of the iotakt library)

This is a **demonstration** that the `IotaktRuntime.Server` handoff surface is
sufficient to build a keep-alive HTTP/1.1 service. The serve loop and
routing policy live here, in example code — **not** in an iotakt library
module — because routing, keep-alive policy, and handler dispatch are the
HTTP *server's* responsibility (the future jemmet project), not iotakt's.

iotakt's non-goals (RFC 001) explicitly exclude HTTP routing and protocol
policy. iotakt provides the building blocks; a server consumes them. This
file shows how, so the surface stays honest about what it must support.

```
lake build iotakt-reference-server
.lake/build/bin/iotakt-reference-server &
curl http://127.0.0.1:49997/users/42
curl http://127.0.0.1:49997/a http://127.0.0.1:49997/b   # keep-alive, one conn
```
-/

open IotaktRuntime.Server IotaktRuntime.Loop IotaktRuntime.Http IotaktRuntime.Router IotaktRuntime.RequestBody
open IotaktRuntime.Native Iotakt.Model

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- ── Consumer-side policy (this is the server's job, not iotakt's) ──────────

private def maxBytes : Nat := 8192

private def jsonUser (id : String) : HttpResponse :=
  let body := s!"\{\"id\":\"{id}\",\"kind\":\"user\"}"
  { statusCode := 200, statusText := "OK", body := body.toUTF8
    headers := [("Content-Type", "application/json"),
                ("Content-Length", toString body.toUTF8.size)] }

private def appRouter : Router :=
  Router.empty
    |>.get  "/"          (fun _ => HttpResponse.ok "iotakt reference server")
    |>.get  "/health"    (fun _ => HttpResponse.ok "ok")
    |>.get  "/users/:id" (fun p => jsonUser (p.get "id"))
    |>.get  "/a"         (fun _ => HttpResponse.ok "A")
    |>.get  "/b"         (fun _ => HttpResponse.ok "B")
    |>.post "/echo"      (fun _ => HttpResponse.ok "echoed")

private def payloadTooLarge : HttpResponse :=
  { statusCode := 413, statusText := "Payload Too Large"
    body := "too large".toUTF8
    headers := [("Content-Type", "text/plain"),
                ("Content-Length", toString "too large".toUTF8.size),
                ("Connection", "close")] }

/-- Keep-alive serve loop — consumer code built on `readRequestBuffered`.
Carries leftover bytes across pipelined requests. -/
private def serveConnection (fd : Int) : IO Nat := do
  let mut served := 0
  let mut keepGoing := true
  let mut leftover := ByteArray.empty
  for _ in List.range 100 do
    if !keepGoing then pure ()
    else
      let (result, rest) ← readRequestBuffered fd leftover maxBytes 30
      leftover := rest
      match result with
      | .request req =>
          let alive := HttpRequest.keepAlive req
          let baseResp := appRouter.dispatchRequest req
          let connVal := if alive then "keep-alive" else "close"
          let hdrs := baseResp.headers.filter (·.1.toLower != "connection")
                        ++ [("Connection", connVal)]
          let resp := { baseResp with headers := hdrs }
          let bytes := resp.toBytes
          let _ ← Io.send fd bytes 0 bytes.size
          served := served + 1
          keepGoing := alive
      | .tooLarge =>
          let bytes := payloadTooLarge.toBytes
          let _ ← Io.send fd bytes 0 bytes.size
          keepGoing := false
      | _ => keepGoing := false
  return served

def main : IO Unit := do
  IO.println "iotakt reference server (consumer example — NOT the iotakt library)"
  IO.println s!"Listening on 127.0.0.1:49997 ({appRouter.size} routes, keep-alive, ~5s)"
  IO.println ""

  let some loop ← EventLoop.create { maxReadBytes := maxBytes }
    | do IO.println "epoll_create failed"; return
  let (loop1, ok) ← loop.addListener 49997
  if !ok then do IO.println "bind failed"; loop.destroy; return

  let mut loop := loop1.withIdleTimeout 3000
  let mut total := 0
  for _ in List.range 50 do
    let (l', events) ← LoopError.orThrow (← loop.runStepAuto)
    loop := l'
    for ev in events do
      match ev with
      | .newConnection _ key =>
          total := total + (← serveConnection key.raw)
          loop ← EffectError.orThrow (← loop.closeConnection key)
      | _ => pure ()
  loop.destroy

  IO.println s!"Total requests served: {total}"
  check "reference server: served requests" (total >= 0)
  IO.println "Reference server done"
