import IotaktRuntime.Loop
import IotaktRuntime.Http

/-!
# iotakt HTTP/1.0 client

Demonstrates outbound TCP connect via `EventLoop.connectTo` followed by
an HTTP/1.0 GET request using `WriteBuffer` for correct write handling.

Intended to be run against `iotakt-http-server` on port 49990:

```
.lake/build/bin/iotakt-http-server &
.lake/build/bin/iotakt-http-client
```
-/

open IotaktRuntime.Loop IotaktRuntime.Http IotaktRuntime.Native Iotakt.Model IotaktRuntime.WriteBuffer

private def LOOPBACK : UInt32 := 0x7f000001   -- 127.0.0.1

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

def main : IO Unit := do
  IO.println "iotakt HTTP/1.0 client"

  let some loop ← EventLoop.create
    | do IO.println "epoll_create failed"; return

  -- Initiate outbound connect to :49990
  let (loop1, outcome) ← loop.connectTo LOOPBACK 49990
  let clientKey ← match outcome with
    | .failed msg => do
        IO.println s!"connect failed: {msg}"
        loop.destroy; return
    | .connected k  => pure k
    | .inProgress k => pure k

  -- Poll until we get writable (connect confirmed) then send request
  let mut loop := loop1
  let mut connected := match outcome with | .connected _ => true | _ => false
  let mut requestSent := false
  let mut responseBytes := ByteArray.empty
  let mut done := false

  for _ in List.range 50 do
    if done then break
    let (loop1', events) ← loop.runStep 100
    loop := loop1'
    for ev in events do
      match ev with
      | .dataReady key event =>
          if key == clientKey then
            match event with
            | .writable =>
                if !connected then
                  match ← Socket.checkConnect key.raw with
                  | .connected => connected := true
                  | _          => done := true
                if connected && !requestSent then
                  let req := HttpRequest.get "127.0.0.1:49990" "/hello/iotakt"
                  let wb  := WriteBuffer.empty.push req
                  let (_, _) ← wb.flushAll key.raw
                  requestSent := true
                  -- disable write interest; wait for readable
                  loop := ← loop.disableWrite key
            | .readable =>
                let resp ← HttpResponse.readAll key.raw
                responseBytes := resp
                done := true
            | .eof | .hangup => done := true
            | .error _ => done := true
      | .newConnection _ _ => pure ()
      | .tick _ => pure ()

  loop := ← loop.closeConnection clientKey
  loop.destroy

  -- Validate response
  IO.println ""
  check "connected to server"  connected
  check "request sent"         requestSent
  check "response received"    (responseBytes.size > 0)

  let status := HttpResponse.parseStatus responseBytes
  check "status 200 OK"
    (match status with | some 200 => true | _ => false)

  let body := HttpResponse.extractBody responseBytes
  check "body contains 'iotakt'"
    (match body with
     | some b => (b.splitOn "iotakt").length > 1
     | none   => false)

  IO.println ""
  match HttpResponse.extractBody responseBytes with
  | some b => IO.println s!"Response body:\n{b}"
  | none   => IO.println "(no body)"

  IO.println ""
  IO.println "HTTP client done"
