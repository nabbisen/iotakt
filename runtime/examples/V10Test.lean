import IotaktRuntime.RequestBody
import IotaktRuntime.Http
import IotaktRuntime.Native

/-!
# iotakt v0.10 integration test

Tests the iotakt-owned building blocks added in v0.10 (jemmet, the server
that will consume these, is a separate future project):

* **Request-size limits** — `unsafeReadFull` returns `.tooLarge` when a request
  exceeds `maxBytes` (header flood and oversized Content-Length body).
* **Pipelining-correct buffered reads** — `unsafeReadFromBuffer` parses one
  request and returns the leftover bytes of the next, so a consumer's
  keep-alive loop loses no pipelined data.
-/

open IotaktRuntime.RequestBody IotaktRuntime.Http IotaktRuntime.Native Iotakt.Model

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- A. Request-size limits
def testSizeLimits : IO Unit := do
  IO.println "=== A. Request-size limits ==="

  let (a, b) ← Unsafe.Socket.socketpairRaw
  if a < 0 then check "socketpair (oversized CL)" false
  else do
    let req := "POST /x HTTP/1.1\r\nHost: x\r\nContent-Length: 100000\r\n\r\n".toUTF8
    let _ ← Unsafe.Io.send a req 0 req.size
    Unsafe.Socket.closeFdRaw (fd32 a)
    match ← unsafeReadFull b 8192 30 with
    | .tooLarge => check "oversized Content-Length → .tooLarge" true
    | _         => check "oversized Content-Length → .tooLarge" false
    Unsafe.Socket.closeFdRaw (fd32 b)

  let (a2, b2) ← Unsafe.Socket.socketpairRaw
  if a2 < 0 then check "socketpair (header flood)" false
  else do
    let flood := String.mk (List.replicate 5000 'X') ++ ": v\r\n"
    let floodReq := ("GET / HTTP/1.1\r\n" ++ flood ++ flood).toUTF8
    let _ ← Unsafe.Io.send a2 floodReq 0 floodReq.size
    Unsafe.Socket.closeFdRaw (fd32 a2)
    match ← unsafeReadFull b2 4096 30 with
    | .tooLarge => check "header flood > maxBytes → .tooLarge" true
    | _         => check "header flood > maxBytes → .tooLarge" false
    Unsafe.Socket.closeFdRaw (fd32 b2)

  let (a3, b3) ← Unsafe.Socket.socketpairRaw
  if a3 < 0 then check "socketpair (within limit)" false
  else do
    let req := "POST /ok HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nHELLO".toUTF8
    let _ ← Unsafe.Io.send a3 req 0 req.size
    Unsafe.Socket.closeFdRaw (fd32 a3)
    match ← unsafeReadFull b3 8192 30 with
    | .request r => check "within-limit request → .request" ((String.fromUTF8? r.body |>.getD "") == "HELLO")
    | _          => check "within-limit request → .request" false
    Unsafe.Socket.closeFdRaw (fd32 b3)

-- B. Pipelining-correct buffered reads
def testBufferedRead : IO Unit := do
  IO.println ""
  IO.println "=== B. unsafeReadFromBuffer pipelining ==="

  let (client, server) ← Unsafe.Socket.socketpairRaw
  if client < 0 then check "socketpair (pipelining)" false
  else do
    let reqs :=
      "GET /1 HTTP/1.1\r\nHost: x\r\n\r\n" ++
      "GET /2 HTTP/1.1\r\nHost: x\r\n\r\n" ++
      "GET /3 HTTP/1.1\r\nHost: x\r\n\r\n"
    let rb := reqs.toUTF8
    let _ ← Unsafe.Io.send client rb 0 rb.size
    Unsafe.Socket.closeFdRaw (fd32 client)

    let (r1, rest1) ← unsafeReadFromBuffer server ByteArray.empty 8192 30
    let p1 := match r1 with | .request req => req.path | _ => "?"
    check "pipelined request 1 path = /1" (p1 == "/1")
    check "leftover after req 1 is non-empty" (!rest1.isEmpty)

    let (r2, rest2) ← unsafeReadFromBuffer server rest1 8192 30
    let p2 := match r2 with | .request req => req.path | _ => "?"
    check "pipelined request 2 path = /2" (p2 == "/2")

    let (r3, rest3) ← unsafeReadFromBuffer server rest2 8192 30
    let p3 := match r3 with | .request req => req.path | _ => "?"
    check "pipelined request 3 path = /3" (p3 == "/3")
    check "no leftover after the last request" (rest3.isEmpty)

    Unsafe.Socket.closeFdRaw (fd32 server)

  let (c2, s2) ← Unsafe.Socket.socketpairRaw
  if c2 < 0 then check "socketpair (CL + pipeline)" false
  else do
    let reqs :=
      "POST /up HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nHELLO" ++
      "GET /next HTTP/1.1\r\nHost: x\r\n\r\n"
    let rb := reqs.toUTF8
    let _ ← Unsafe.Io.send c2 rb 0 rb.size
    Unsafe.Socket.closeFdRaw (fd32 c2)

    let (r1, rest1) ← unsafeReadFromBuffer s2 ByteArray.empty 8192 30
    match r1 with
    | .request req =>
        check "CL request body = 'HELLO'" ((String.fromUTF8? req.body |>.getD "") == "HELLO")
    | _ => check "CL request parsed" false
    let (r2, _) ← unsafeReadFromBuffer s2 rest1 8192 30
    let p2 := match r2 with | .request req => req.path | _ => "?"
    check "next request after CL body = /next (body consumed exactly)" (p2 == "/next")

    Unsafe.Socket.closeFdRaw (fd32 s2)

-- C. findHeaderEnd helper
def testFindHeaderEnd : IO Unit := do
  IO.println ""
  IO.println "=== C. findHeaderEnd ==="
  let raw := "GET / HTTP/1.1\r\nHost: x\r\n\r\nBODY".toUTF8
  match findHeaderEnd raw with
  | some n =>
      check "findHeaderEnd points past the terminator"
        (n == "GET / HTTP/1.1\r\nHost: x\r\n\r\n".toUTF8.size)
      check "bytes after header end = 'BODY'"
        ((String.fromUTF8? (raw.extract n raw.size) |>.getD "") == "BODY")
  | none => check "findHeaderEnd on complete headers" false
  check "findHeaderEnd incomplete → none"
    ((findHeaderEnd "GET / HTTP/1.1\r\nHost: x".toUTF8).isNone)

def main : IO Unit := do
  IO.println "iotakt v0.10 integration test (size limits + buffered reads)"
  IO.println ""
  testSizeLimits
  testBufferedRead
  testFindHeaderEnd
  IO.println ""
  IO.println "v0.10 integration test complete"
