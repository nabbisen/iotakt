import Iotakt.Jemmet
import Iotakt.RequestBody
import Iotakt.Http
import Iotakt.Router
import Iotakt.Native

/-!
# iotakt v0.10 integration test

* **Request-size limits** — `readFull` returns `.tooLarge` when a request
  exceeds `maxBytes` (header flood and oversized Content-Length body).
* **Keep-alive serve loop** — `Jemmet.serveConnection` serves multiple
  requests on one socketpair-backed fd and stops on `Connection: close`.
* **jemmet router** — dispatch + 413 response shape.
-/

open Iotakt.Jemmet Iotakt.RequestBody Iotakt.Http Iotakt.Router
open Iotakt.Native Iotakt.Model

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- ─────────────────────────────────────────────────────────────────────────
-- A. Request-size limits
-- ─────────────────────────────────────────────────────────────────────────
def testSizeLimits : IO Unit := do
  IO.println "=== A. Request-size limits ==="

  -- Oversized Content-Length declared body → .tooLarge (declared n > maxBytes)
  let (a, b) ← Socket.socketpairRaw
  if a < 0 then check "socketpair (oversized CL)" false
  else do
    let req := "POST /x HTTP/1.1\r\nHost: x\r\nContent-Length: 100000\r\n\r\n".toUTF8
    let _ ← Io.send a req 0 req.size
    Socket.closeFdRaw (fd32 a)
    match ← readFull b 8192 30 with
    | .tooLarge => check "oversized Content-Length → .tooLarge" true
    | _         => check "oversized Content-Length → .tooLarge" false
    Socket.closeFdRaw (fd32 b)

  -- Header flood with no terminator → .tooLarge (buffer exceeds maxBytes)
  let (a2, b2) ← Socket.socketpairRaw
  if a2 < 0 then check "socketpair (header flood)" false
  else do
    -- Send > maxBytes of header bytes with no \r\n\r\n
    let flood := String.mk (List.replicate 5000 'X') ++ ": v\r\n"
    let floodReq := ("GET / HTTP/1.1\r\n" ++ flood ++ flood).toUTF8
    let _ ← Io.send a2 floodReq 0 floodReq.size
    Socket.closeFdRaw (fd32 a2)
    match ← readFull b2 4096 30 with
    | .tooLarge => check "header flood > maxBytes → .tooLarge" true
    | _         => check "header flood > maxBytes → .tooLarge" false
    Socket.closeFdRaw (fd32 b2)

  -- A within-limit request still succeeds
  let (a3, b3) ← Socket.socketpairRaw
  if a3 < 0 then check "socketpair (within limit)" false
  else do
    let req := "POST /ok HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nHELLO".toUTF8
    let _ ← Io.send a3 req 0 req.size
    Socket.closeFdRaw (fd32 a3)
    match ← readFull b3 8192 30 with
    | .request r => check "within-limit request → .request" ((String.fromUTF8? r.body |>.getD "") == "HELLO")
    | _          => check "within-limit request → .request" false
    Socket.closeFdRaw (fd32 b3)

-- ─────────────────────────────────────────────────────────────────────────
-- B. Keep-alive serve loop
-- ─────────────────────────────────────────────────────────────────────────
def testKeepAlive : IO Unit := do
  IO.println ""
  IO.println "=== B. Keep-alive serve loop ==="

  let router := Router.empty
    |>.get "/a" (fun _ => HttpResponse.ok "A")
    |>.get "/b" (fun _ => HttpResponse.ok "B")
  let cfg : Config := { maxKeepAlive := 10 }

  -- Two keep-alive requests then a close request on one connection
  let (client, server) ← Socket.socketpairRaw
  if client < 0 then check "socketpair (keep-alive)" false
  else do
    let reqs :=
      "GET /a HTTP/1.1\r\nHost: x\r\nConnection: keep-alive\r\n\r\n" ++
      "GET /b HTTP/1.1\r\nHost: x\r\nConnection: keep-alive\r\n\r\n" ++
      "GET /a HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"
    let rb := reqs.toUTF8
    let _ ← Io.send client rb 0 rb.size
    -- Don't close client yet; serveConnection reads until Connection: close
    let served ← serveConnection cfg router server
    check "serveConnection served 3 requests on one connection" (served == 3)
    -- Read back the responses the server wrote
    let mut acc := ByteArray.empty
    for _ in List.range 5 do
      match ← Io.recv client 4096 with
      | .bytes ba =>
          let c := ByteArray.mkEmpty (acc.size + ba.size)
          acc := ByteArray.copySlice ba 0 (ByteArray.copySlice acc 0 c 0 acc.size) acc.size ba.size
      | _ => pure ()
    let respStr := String.fromUTF8? acc |>.getD ""
    check "keep-alive responses contain bodies A and B"
      ((respStr.splitOn "A").length > 1 && (respStr.splitOn "B").length > 1)
    check "three response status lines present"
      ((respStr.splitOn "HTTP/1.0 200").length == 4)  -- 3 responses → split yields 4
    Socket.closeFdRaw (fd32 client)
    Socket.closeFdRaw (fd32 server)

  -- A single Connection: close request serves exactly one then stops
  let (c2, s2) ← Socket.socketpairRaw
  if c2 < 0 then check "socketpair (single close)" false
  else do
    let req := "GET /a HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".toUTF8
    let _ ← Io.send c2 req 0 req.size
    let served ← serveConnection cfg router s2
    check "Connection: close serves exactly 1 request" (served == 1)
    Socket.closeFdRaw (fd32 c2)
    Socket.closeFdRaw (fd32 s2)

-- ─────────────────────────────────────────────────────────────────────────
-- C. jemmet router + 413 shape
-- ─────────────────────────────────────────────────────────────────────────
def testJemmetRouter : IO Unit := do
  IO.println ""
  IO.println "=== C. jemmet router + 413 ==="

  check "payloadTooLarge status = 413" (payloadTooLarge.statusCode == 413)
  check "payloadTooLarge has Connection: close"
    (payloadTooLarge.headers.any (fun (k, v) => k.toLower == "connection" && v == "close"))

  let router := Router.empty
    |>.get "/health" (fun _ => HttpResponse.ok "ok")
  check "router dispatch /health → 200" ((router.dispatch "GET" "/health").statusCode == 200)
  check "router dispatch /missing → 404" ((router.dispatch "GET" "/missing").statusCode == 404)

  -- Config defaults
  let cfg : Config := {}
  check "default port 8080" (cfg.port == 8080)
  check "default maxBytes 65536" (cfg.maxBytes == 65536)
  check "default idle timeout 30s" (cfg.idleTimeoutMs == 30000)

-- ─────────────────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────────────────
def main : IO Unit := do
  IO.println "iotakt v0.10 integration test (size limits + keep-alive + jemmet)"
  IO.println ""
  testSizeLimits
  testKeepAlive
  testJemmetRouter
  IO.println ""
  IO.println "v0.10 integration test complete"
