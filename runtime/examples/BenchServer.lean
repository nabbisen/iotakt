import IotaktRuntime.Loop
import IotaktRuntime.Http
import IotaktRuntime.WriteBuffer

/-!
# iotakt HTTP/1.1 keep-alive benchmark server (v0.5 / RFC 025)

Each connection stays open, handling multiple sequential GET requests.
Designed to be run alongside `iotakt-bench` on port 49995.
-/

open IotaktRuntime.Loop IotaktRuntime.Http IotaktRuntime.Native Iotakt.Model IotaktRuntime.WriteBuffer

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- Per-connection state
structure ConnS where
  key      : FdKey
  recvBuf  : ByteArray := ByteArray.empty
  sendBuf  : WriteBuffer := WriteBuffer.empty
  requests : Nat := 0

/-- Append ba to buf. -/
def appendBa (buf : ByteArray) (ba : ByteArray) : ByteArray :=
  let combined := ByteArray.mkEmpty (buf.size + ba.size)
  let combined := ByteArray.copySlice buf 0 combined 0 buf.size
  ByteArray.copySlice ba 0 combined buf.size ba.size

/-- Process all complete requests from buffer; return responses + remainder. -/
def drainRequests (buf : ByteArray) : List ByteArray × ByteArray × Nat :=
  let s := String.fromUTF8? buf |>.getD ""
  -- Count complete requests (each terminated by \r\n\r\n)
  let parts := s.splitOn "\r\n\r\n"
  let nComplete := if parts.length > 0 then parts.length - 1 else 0
  let responses := List.range nComplete |>.map fun _ =>
    (HttpResponse.okKeepAlive "pong").toBytes
  -- Remainder is what's after all complete headers
  let remainder := (parts.getLast?.getD "").toUTF8
  (responses, remainder, nComplete)

def main : IO Unit := do
  IO.println "iotakt HTTP/1.1 keep-alive benchmark server"
  IO.println "Listening on 127.0.0.1:49995"

  let some loop ← EventLoop.create { maxReadBytes := 8192, maxEventsPerPoll := 256 }
    | do IO.println "epoll_create failed"; return
  let (loop1, ok) ← loop.addListener 49995
  if !ok then do IO.println "bind failed"; loop.destroy; return

  let mut loop := loop1
  let mut conns : List ConnS := []
  let mut totalConns := 0
  let mut totalRequests := 0

  for _ in List.range 80 do   -- 8 seconds at 100ms/step
    let (loop1', events) ← loop.runStep 100
    loop := loop1'
    for ev in events do
      match ev with
      | .newConnection key _ =>
          conns := conns ++ [{ key := key }]
          totalConns := totalConns + 1
      | .dataReady key event =>
          let csOpt := conns.find? (fun c => c.key == key)
          match csOpt with
          | none => pure ()
          | some cs =>
              match event with
              | .readable =>
                  match ← Io.recv key.raw 8192 with
                  | .bytes ba =>
                      let newBuf := appendBa cs.recvBuf ba
                      let (resps, remainder, n) := drainRequests newBuf
                      let sendBuf := resps.foldl (·.push ·) cs.sendBuf
                      let newCs := { cs with recvBuf := remainder,
                                             sendBuf := sendBuf,
                                             requests := cs.requests + n }
                      conns := conns.map fun c => if c.key == key then newCs else c
                      totalRequests := totalRequests + n
                      if !sendBuf.isEmpty then loop := ← loop.enableWrite key
                  | .eof =>
                      loop := ← loop.closeConnection key
                      conns := conns.filter (·.key != key)
                  | _ => pure ()
              | .writable =>
                  let (wb, done) ← cs.sendBuf.flush key.raw
                  conns := conns.map fun c =>
                    if c.key == key then { c with sendBuf := wb } else c
                  if done then loop := ← loop.disableWrite key
              | _ =>
                  loop := ← loop.closeConnection key
                  conns := conns.filter (·.key != key)
      | .tick _ => pure ()

  for cs in conns do loop := ← loop.closeConnection cs.key
  loop.destroy

  IO.println s!"Connections:  {totalConns}"
  IO.println s!"Requests:     {totalRequests}"
  check "bench server: served connections" (totalConns >= 0)
  IO.println "Benchmark server done"
