import Iotakt.Server
import Iotakt.RequestBody
import Iotakt.Http
import Iotakt.Chunked
import Iotakt.Native

/-!
# iotakt v0.9 integration test

* **Body framing detection** — `framingOf` correctly classifies
  Content-Length, chunked, and bodyless requests.
* **Header/body splitting** — `splitHeaders` separates the header block
  from buffered body bytes.
* **Live request reading** — `readFull` over a real socketpair, for both
  Content-Length and chunked request bodies.
* **Handoff surface** — the `Iotakt.Server` re-exports resolve.
-/

open Iotakt.RequestBody Iotakt.Http Iotakt.Native Iotakt.Model

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

-- ─────────────────────────────────────────────────────────────────────────
-- A. Body framing detection
-- ─────────────────────────────────────────────────────────────────────────
def testFraming : IO Unit := do
  IO.println "=== A. Body framing detection ==="

  let mkReq (hdrs : List (String × String)) : HttpRequest :=
    { method := "POST", path := "/x", version := "HTTP/1.1", headers := hdrs }

  check "no body headers → .none"
    (framingOf (mkReq []) == .none)
  check "Content-Length: 42 → .contentLength 42"
    (framingOf (mkReq [("Content-Length", "42")]) == .contentLength 42)
  check "Transfer-Encoding: chunked → .chunked"
    (framingOf (mkReq [("Transfer-Encoding", "chunked")]) == .chunked)
  check "chunked takes precedence over Content-Length (RFC 7230 §3.3.3)"
    (framingOf (mkReq [("Content-Length", "5"), ("Transfer-Encoding", "chunked")]) == .chunked)
  check "header name case-insensitive"
    (framingOf (mkReq [("content-length", "10")]) == .contentLength 10)
  check "invalid Content-Length → .none"
    (framingOf (mkReq [("Content-Length", "abc")]) == .none)

-- ─────────────────────────────────────────────────────────────────────────
-- B. Header/body splitting
-- ─────────────────────────────────────────────────────────────────────────
def testSplit : IO Unit := do
  IO.println ""
  IO.println "=== B. Header/body splitting ==="

  let raw := "POST /x HTTP/1.1\r\nHost: a\r\n\r\nBODYBYTES".toUTF8
  match splitHeaders raw with
  | some (hdr, body) =>
      check "splitHeaders separates header block"
        ((String.fromUTF8? hdr |>.getD "") == "POST /x HTTP/1.1\r\nHost: a")
      check "splitHeaders extracts body bytes"
        ((String.fromUTF8? body |>.getD "") == "BODYBYTES")
  | none => check "splitHeaders on complete headers" false

  -- No terminator yet → none
  check "splitHeaders incomplete → none"
    ((splitHeaders "POST /x HTTP/1.1\r\nHost: a".toUTF8).isNone)

-- ─────────────────────────────────────────────────────────────────────────
-- C. Live request reading over a socketpair
-- ─────────────────────────────────────────────────────────────────────────
def testLiveRead : IO Unit := do
  IO.println ""
  IO.println "=== C. Live request reading (socketpair) ==="

  -- Content-Length body
  let (a, b) ← Socket.socketpairRaw
  if a < 0 then check "socketpair (Content-Length)" false
  else do
    let req := "POST /cl HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nHELLO".toUTF8
    let _ ← Io.send a req 0 req.size
    Socket.closeFdRaw (fd32 a)  -- EOF after the request
    match ← readFull b 65536 30 with
    | .request r =>
        check "Content-Length: read path = .request" true
        check "Content-Length body = 'HELLO'" ((String.fromUTF8? r.body |>.getD "") == "HELLO")
        check "Content-Length path preserved" (r.path == "/cl")
    | _ => check "Content-Length read returned .request" false
    Socket.closeFdRaw (fd32 b)

  -- Chunked body
  let (a, b) ← Socket.socketpairRaw
  if a < 0 then check "socketpair (chunked)" false
  else do
    let req := "POST /ck HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nHello\r\n6\r\n world\r\n0\r\n\r\n".toUTF8
    let _ ← Io.send a req 0 req.size
    Socket.closeFdRaw (fd32 a)
    match ← readFull b 65536 30 with
    | .request r =>
        check "chunked: read path = .request" true
        check "chunked body reassembled = 'Hello world'"
          ((String.fromUTF8? r.body |>.getD "") == "Hello world")
        check "chunked path preserved" (r.path == "/ck")
    | _ => check "chunked read returned .request" false
    Socket.closeFdRaw (fd32 b)

  -- Bodyless GET
  let (a, b) ← Socket.socketpairRaw
  if a < 0 then check "socketpair (GET)" false
  else do
    let req := "GET /home HTTP/1.1\r\nHost: x\r\n\r\n".toUTF8
    let _ ← Io.send a req 0 req.size
    Socket.closeFdRaw (fd32 a)
    match ← readFull b 65536 30 with
    | .request r =>
        check "GET: read path = .request" true
        check "GET has empty body" r.body.isEmpty
    | _ => check "GET read returned .request" false
    Socket.closeFdRaw (fd32 b)

-- ─────────────────────────────────────────────────────────────────────────
-- D. Handoff surface re-exports
-- ─────────────────────────────────────────────────────────────────────────
def testHandoff : IO Unit := do
  IO.println ""
  IO.println "=== D. Iotakt.Server handoff surface ==="
  -- The handoff value: a single `import Iotakt.Server` brings the whole
  -- stack transitively, plus consolidated abbrevs for the chunked + read ops.
  let _router := Iotakt.Router.Router.empty       -- Router type re-exported by Server
  let frame := Iotakt.Server.encodeChunk "hi".toUTF8
  check "Server.encodeChunk resolves" ((String.fromUTF8? frame |>.getD "") == "2\r\nhi\r\n")
  check "Server.chunkedTerminator resolves"
    ((String.fromUTF8? Iotakt.Server.chunkedTerminator |>.getD "") == "0\r\n\r\n")
  let resp := (Iotakt.Http.HttpResponse.ok "ok").toBytes
  check "Server stack: HttpResponse resolves via single import" (!resp.isEmpty)
  check "Server.decodeChunked resolves"
    (match Iotakt.Server.decodeChunked "2\r\nhi\r\n0\r\n\r\n".toUTF8 with
     | some d => (String.fromUTF8? d |>.getD "") == "hi"
     | none   => false)
  check "Server.isChunked resolves"
    (Iotakt.Server.isChunked "x\r\nTransfer-Encoding: chunked\r\n\r\n".toUTF8)

-- ─────────────────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────────────────
def main : IO Unit := do
  IO.println "iotakt v0.9 integration test (body framing + handoff surface)"
  IO.println ""
  testFraming
  testSplit
  testLiveRead
  testHandoff
  IO.println ""
  IO.println "v0.9 integration test complete"
