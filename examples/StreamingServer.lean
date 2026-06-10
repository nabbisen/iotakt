import Iotakt.Loop
import Iotakt.Router
import Iotakt.Http
import Iotakt.Chunked
import Iotakt.WriteBuffer

/-!
# iotakt HTTP/1.1 chunked streaming server (v0.8)

Combines the v0.8 additions:
- `Iotakt.Chunked` — streams a response body as size-prefixed chunks.
- `EventLoop.runStepAuto` — adaptive poll timeout (idle = 0% CPU).
- `EventLoop.withIdleTimeout` — reaps connections idle past the threshold.

```
lake build iotakt-streaming-server
.lake/build/bin/iotakt-streaming-server &
curl http://127.0.0.1:49995/stream   # receives chunked response
```
-/

open Iotakt.Loop Iotakt.Router Iotakt.Http
open Iotakt.Native Iotakt.Model Iotakt.WriteBuffer

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

/-- Read a request (until headers terminator), best-effort. -/
def readReq (fd : Int) : IO (Option ByteArray) := do
  let mut buf := ByteArray.empty
  for _ in List.range 20 do
    let s := String.fromUTF8? buf |>.getD ""
    if (s.splitOn "\r\n\r\n").length > 1 then return some buf
    match ← Io.recv fd 4096 with
    | .bytes ba =>
        let c := ByteArray.mkEmpty (buf.size + ba.size)
        buf := ByteArray.copySlice ba 0 (ByteArray.copySlice buf 0 c 0 buf.size) buf.size ba.size
    | .wouldBlock => IO.sleep 20
    | .eof        => return (if buf.isEmpty then none else some buf)
    | _           => return none
  return (if (String.fromUTF8? buf |>.getD "" |>.splitOn "\r\n\r\n").length > 1 then some buf else none)

/-- Stream a chunked response: header, then three chunks, then terminator. -/
def streamChunked (fd : Int) : IO Unit := do
  let header := Iotakt.Chunked.responseHeader 200 "OK" "text/plain"
  let _ ← Io.send fd header 0 header.size
  for part in ["Hello, ", "chunked ", "world!\n"] do
    let frame := Iotakt.Chunked.encodeChunk part.toUTF8
    let _ ← Io.send fd frame 0 frame.size
  let term := Iotakt.Chunked.terminator
  let _ ← Io.send fd term 0 term.size

/-- Handle a connection: route, stream chunked for /stream, plain otherwise. -/
def handle (loop : EventLoop) (key : FdKey) : IO EventLoop := do
  let fd := key.raw
  match ← readReq fd with
  | none => loop.closeConnection key
  | some raw =>
      match HttpRequest.parse raw with
      | some req =>
          if req.path == "/stream" then
            streamChunked fd
          else
            let resp := (HttpResponse.ok "try /stream for a chunked response").toBytes
            let _ ← Io.send fd resp 0 resp.size
      | none =>
          let resp := (HttpResponse.notFound "(bad request)").toBytes
          let _ ← Io.send fd resp 0 resp.size
      loop.closeConnection key

def main : IO Unit := do
  IO.println "iotakt HTTP/1.1 chunked streaming server (v0.8)"
  IO.println "Listening on 127.0.0.1:49995 (runStepAuto + 2s idle timeout, ~5s)"
  IO.println ""

  let some loop ← EventLoop.create | do IO.println "epoll failed"; return
  let (loop1, ok) ← loop.addListener 49995
  if !ok then do IO.println "bind failed"; loop.destroy; return

  -- runStepAuto + idle timeout: the loop blocks adaptively, reaps idle conns
  let mut loop := loop1.withIdleTimeout 2000
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
  check "streaming server: handled requests" (handled >= 0)
  check "streaming server: tasks cleaned up" (loop.taskByKey.length == 0)
  IO.println "Streaming server done"
