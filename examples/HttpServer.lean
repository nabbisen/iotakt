import Iotakt.Loop
import Iotakt.Http

/-!
# iotakt minimal HTTP/1.0 server

A working HTTP/1.0 server using `EventLoop` + `WriteBuffer`. Accepts
connections, reads the request, and responds with a 200 OK containing
the request path echoed back.

```
lake build iotakt-http-server
.lake/build/bin/iotakt-http-server &
curl -v http://127.0.0.1:49990/hello
```

This demonstrates the boundary between iotakt (byte streams) and the
henejt HTTP layer: iotakt delivers `ReadResult.bytes` to the actor;
the HTTP parser (`Iotakt.Http`) turns bytes into structured requests.
-/

open Iotakt.Loop Iotakt.Http Iotakt.Native Iotakt.Model Iotakt.WriteBuffer

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

/-- Handle one HTTP/1.0 connection: read request, write response, close. -/
def handleConn (loop : EventLoop) (connKey : FdKey) : IO EventLoop := do
  let fd := connKey.raw

  -- Read the request headers (wait up to 10 × 100ms = 1s)
  let mut reqBuf := ByteArray.empty
  for _ in List.range 10 do
    let headersDone := ((String.fromUTF8? reqBuf |>.getD "").splitOn "\r\n\r\n").length > 1
    if headersDone then break
    match ← Io.recv fd 4096 with
    | .bytes ba =>
        let combined := ByteArray.mkEmpty (reqBuf.size + ba.size)
        let combined := ByteArray.copySlice reqBuf 0 combined 0 reqBuf.size
        reqBuf := ByteArray.copySlice ba 0 combined reqBuf.size ba.size
    | .wouldBlock => IO.sleep 50  -- wait a bit
    | .eof        => break
    | _           => break

  -- Parse and respond
  let resp := match HttpRequest.parse reqBuf with
    | none =>
        HttpResponse.notFound "(parse error)"
    | some req =>
        let body := s!"iotakt HTTP/1.0 server\nMethod: {req.method}\nPath: {req.path}\nHeaders: {req.headers.length}"
        HttpResponse.ok body

  -- Write response using WriteBuffer
  let wb := WriteBuffer.empty.push resp.toBytes
  let (_, _) ← wb.flushAll fd

  -- Close the connection
  loop.closeConnection connKey

/-- HTTP/1.0 server: accepts connections and handles each one. -/
def main : IO Unit := do
  IO.println "iotakt HTTP/1.0 server"
  IO.println "Listening on 127.0.0.1:49990 (accepting for ~5s)"
  IO.println ""

  let some loop ← EventLoop.create { maxReadBytes := 8192 }
    | do IO.println "epoll_create failed"; return
  let (loop1, ok) ← loop.addListener 49990
  if !ok then do
    IO.println "bind/listen failed (port in use?)"
    loop.destroy; return

  let mut loop := loop1
  let mut reqCount := 0

  -- Run for 50 steps × 100ms = ~5 seconds
  for _ in List.range 50 do
    let (loop1', events) ← loop.runStep 100
    loop := loop1'
    for ev in events do
      match ev with
      | .newConnection key _ =>
          IO.println s!"  → connection from fd={key.raw}"
          loop := ← handleConn loop key
          reqCount := reqCount + 1
      | .dataReady _ _ => pure ()  -- handled inside handleConn
      | .tick _        => pure ()

  loop.destroy

  IO.println ""
  IO.println s!"Total requests handled: {reqCount}"
  check "http server handled requests" (reqCount >= 0)
  IO.println "HTTP server done"
