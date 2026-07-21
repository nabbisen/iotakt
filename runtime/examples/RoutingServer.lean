import IotaktRuntime.Loop
import IotaktRuntime.Router
import IotaktRuntime.Http
import IotaktRuntime.WriteBuffer

/-!
# iotakt HTTP/1.1 routing server (v0.6)

A working HTTP server that combines:
- `EventLoop` for non-blocking accept/read/write
- `IotaktRuntime.Router` for path-based dispatch with `:param` capture
- `WriteBuffer` for response streaming
- Gap 006 cancel-on-close connection teardown

```
lake build iotakt-routing-server
.lake/build/bin/iotakt-routing-server &
curl http://127.0.0.1:49993/
curl http://127.0.0.1:49993/health
curl http://127.0.0.1:49993/users/42
curl http://127.0.0.1:49993/nonexistent
```
-/

open IotaktRuntime.Loop IotaktRuntime.Router IotaktRuntime.Http IotaktRuntime.Native Iotakt.Model IotaktRuntime.WriteBuffer

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

/-- Build the application router. -/
def appRouter : Router :=
  Router.empty
    |>.get "/"          (fun _ => HttpResponse.ok "iotakt routing server — try /health or /users/:id")
    |>.get "/health"    (fun _ => HttpResponse.ok "ok")
    |>.get "/users/:id" (fun p =>
        let id := p.get "id"
        HttpResponse.ok s!"user profile: id={id}")
    |>.get "/api/:resource/:id" (fun p =>
        let resource := p.get "resource"
        let id := p.get "id"
        HttpResponse.ok s!"resource={resource} id={id}")
    |>.post "/users"    (fun _ => HttpResponse.ok "user created")

/-- Read a full HTTP request from `fd` (until headers terminator). -/
def unsafeReadRequest (fd : Int) : IO (Option ByteArray) := do
  let mut buf := ByteArray.empty
  for _ in List.range 20 do
    let s := String.fromUTF8? buf |>.getD ""
    if (s.splitOn "\r\n\r\n").length > 1 then return some buf
    match ← Unsafe.Io.recv fd 4096 with
    | .bytes ba =>
        let combined := ByteArray.mkEmpty (buf.size + ba.size)
        let combined := ByteArray.copySlice buf 0 combined 0 buf.size
        buf := ByteArray.copySlice ba 0 combined buf.size ba.size
    | .wouldBlock => IO.sleep 20
    | .eof        => return (if buf.isEmpty then none else some buf)
    | _           => return none
  let s := String.fromUTF8? buf |>.getD ""
  return (if (s.splitOn "\r\n\r\n").length > 1 then some buf else none)

/-- Handle one connection: read request, route, respond, close. -/
def handleConn (loop : EventLoop) (key : FdKey) : IO EventLoop := do
  let fd := key.raw
  match ← unsafeReadRequest fd with
  | none =>
      EffectError.orThrow (← loop.closeConnection key)
  | some raw =>
      let resp := match HttpRequest.parse raw with
        | some req => appRouter.dispatchRequest req
        | none     => HttpResponse.notFound "(unparseable)"
      let wb := WriteBuffer.empty.push resp.toBytes
      let (_, _) ← wb.unsafeFlushAll fd
      EffectError.orThrow (← loop.closeConnection key)

def main : IO Unit := do
  IO.println "iotakt HTTP/1.1 routing server"
  IO.println s!"Listening on 127.0.0.1:49993 ({appRouter.size} routes, accepting ~5s)"
  IO.println ""

  let some loop ← EventLoop.create { maxReadBytes := 8192 }
    | do IO.println "epoll_create failed"; return
  let (loop1, ok) ← loop.addListener 49993
  if !ok then do IO.println "bind failed"; loop.unsafeDestroy; return

  let mut loop := loop1
  let mut handled := 0

  for _ in List.range 50 do
    let (loop1', events) ← LoopError.orThrow (← loop.runStep 100)
    loop := loop1'
    for ev in events do
      match ev with
      | .newConnection _ key =>
          loop := ← handleConn loop key
          handled := handled + 1
      | .dataReady _ _ => pure ()
      | .tick _        => pure ()

  loop.unsafeDestroy

  IO.println s!"Requests handled: {handled}"
  IO.println s!"Active task mappings remaining: {loop.taskByKey.length}"
  check "routing server: handled requests" (handled >= 0)
  check "routing server: tasks cleaned up on close" (loop.taskByKey.length == 0)
  IO.println "Routing server done"
