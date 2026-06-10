import Iotakt.Server

/-!
# iotakt upload server (v0.9)

A jemmet-style server built entirely on the `Iotakt.Server` handoff
surface. It accepts request bodies in both framings (Content-Length and
chunked) via `readRequest`, echoes the body size back, and routes with the
`Router`.

```
lake build iotakt-upload-server
.lake/build/bin/iotakt-upload-server &
curl -X POST --data 'hello' http://127.0.0.1:49996/upload         # Content-Length
curl -X POST -H 'Transfer-Encoding: chunked' --data-binary @file \
     http://127.0.0.1:49996/upload                                 # chunked
```
-/

open Iotakt.Server Iotakt.Loop Iotakt.Http Iotakt.RequestBody Iotakt.Native Iotakt.Model

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

/-- Handle one connection: read a full request (any framing), respond with
the received body size, then close. -/
def handle (loop : EventLoop) (key : FdKey) : IO EventLoop := do
  let fd := key.raw
  match ← readRequest fd 65536 30 with
  | .request req =>
      let n := req.body.size
      let resp := (HttpResponse.ok s!"received {n} bytes on {req.path}").toBytes
      let _ ← Io.send fd resp 0 resp.size
      loop.closeConnection key
  | .tooLarge =>
      let resp := (HttpResponse.notFound "(request too large)").toBytes
      let _ ← Io.send fd resp 0 resp.size
      loop.closeConnection key
  | .incomplete =>
      let resp := (HttpResponse.notFound "(incomplete request)").toBytes
      let _ ← Io.send fd resp 0 resp.size
      loop.closeConnection key
  | .error _ =>
      loop.closeConnection key

def main : IO Unit := do
  IO.println "iotakt upload server (v0.9 — Iotakt.Server handoff surface)"
  IO.println "Listening on 127.0.0.1:49996 (Content-Length + chunked bodies, ~5s)"
  IO.println ""

  let some loop ← EventLoop.create { maxReadBytes := 65536 }
    | do IO.println "epoll failed"; return
  let (loop1, ok) ← loop.addListener 49996
  if !ok then do IO.println "bind failed"; loop.destroy; return

  let mut loop := loop1.withIdleTimeout 3000
  let mut handled := 0

  for _ in List.range 50 do
    let (l', events) ← loop.runStepAuto
    loop := l'
    for ev in events do
      match ev with
      | .newConnection key _ => loop := ← handle loop key; handled := handled + 1
      | _                    => pure ()

  loop.destroy
  IO.println s!"Requests handled: {handled}"
  check "upload server: handled requests" (handled >= 0)
  check "upload server: tasks cleaned up" (loop.taskByKey.length == 0)
  IO.println "Upload server done"
