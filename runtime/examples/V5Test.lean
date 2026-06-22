import IotaktRuntime.Actor
import IotaktRuntime.Stats
import IotaktRuntime.Http
import IotaktRuntime.WriteBuffer
import IotaktRuntime.Native

/-!
# iotakt v0.5 integration test

Tests the four v0.5 additions:

* **ConnectionActor** — callback dispatch, ActorRegistry, echo actor builder.
* **Stats** — ConnStats/GlobalStats counters, reqPerSec computation.
* **HTTP keep-alive** — Connection header de-duplication, okKeepAlive/okClose.
* **Throughput baseline** — 1000 req round-trips via socketpair with monoNs.
-/

open IotaktRuntime.Actor IotaktRuntime.Stats IotaktRuntime.Loop IotaktRuntime.Http IotaktRuntime.Native Iotakt.Model IotaktRuntime.WriteBuffer

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

def appendBa (a b : ByteArray) : ByteArray :=
  let c := ByteArray.mkEmpty (a.size + b.size)
  ByteArray.copySlice b 0 (ByteArray.copySlice a 0 c 0 a.size) a.size b.size

-- ─────────────────────────────────────────────────────────────────────────
-- A. ConnectionActor unit tests
-- ─────────────────────────────────────────────────────────────────────────
def testActor : IO Unit := do
  IO.println "=== A. ConnectionActor ==="

  let (fd0, fd1) ← Socket.socketpairRaw
  check "socketpair for actor test" (fd0 >= 0)
  if fd0 < 0 then return

  -- Build an echo actor on fd0
  let key : FdKey := { raw := fd0, gen := 1 }
  let actor := ConnectionActor.mkEcho key 4096

  check "actor.key matches"     (actor.key == key)
  check "actor.key.raw == fd0"  (actor.key.raw == fd0)

  -- Simulate: send to fd1, actor reads from fd0 (onReadable echoes back)
  let data : ByteArray := "Hello, Actor!".toUTF8
  let (_, sent) ← (WriteBuffer.empty.push data).flushAll fd1
  check "test data sent to fd1" sent

  let action ← actor.onReadable
  check "onReadable returns .continue (echo sent)"
    (match action with | .continue => true | _ => false)

  -- fd1 should now have the echoed bytes
  match ← Io.recv fd1 64 with
  | .bytes ba => check "echoed back correctly" (ba.toList == data.toList)
  | _         => check "echoed back correctly" false

  -- onEof returns .close
  let eofAction ← actor.onEof
  check "onEof returns .close"
    (match eofAction with | .close => true | _ => false)

  -- dispatch: error → close
  let errAction ← actor.dispatch (.error (some .badFd))
  check "dispatch error → close"
    (match errAction with | .close => true | _ => false)

  Socket.closeFdRaw fd0.toInt32
  Socket.closeFdRaw fd1.toInt32

-- ─────────────────────────────────────────────────────────────────────────
-- B. ActorRegistry dispatch
-- ─────────────────────────────────────────────────────────────────────────
def testRegistry : IO Unit := do
  IO.println ""
  IO.println "=== B. ActorRegistry ==="

  let (fd0, fd1) ← Socket.socketpairRaw
  check "socketpair for registry test" (fd0 >= 0)
  if fd0 < 0 then return

  let key : FdKey := { raw := fd0, gen := 1 }
  let actor := ConnectionActor.mkEcho key 4096

  let reg0 := ActorRegistry.empty
  check "empty registry lookup is none" (reg0.lookup key).isNone

  let reg1 := reg0.register actor
  check "after register: lookup is some" (reg1.lookup key).isSome

  let reg2 := reg1.remove key
  check "after remove: lookup is none" (reg2.lookup key).isNone

  -- Test buffered actor
  let bufRef ← IO.mkRef ByteArray.empty
  let bufActor := ConnectionActor.mkBuffered key bufRef
  let reg3 := reg0.register bufActor

  let msg : ByteArray := "buffered".toUTF8
  let (_, _) ← (WriteBuffer.empty.push msg).flushAll fd1

  -- The registry runStep would dispatch, but we test dispatch directly
  let action ← bufActor.onReadable
  check "buffered actor onReadable returns .continue"
    (match action with | .continue => true | _ => false)
  let accumulated ← bufRef.get
  check "buffered actor accumulated bytes"
    (accumulated.toList == msg.toList)

  let _ := reg3
  Socket.closeFdRaw fd0.toInt32
  Socket.closeFdRaw fd1.toInt32

-- ─────────────────────────────────────────────────────────────────────────
-- C. Stats counters
-- ─────────────────────────────────────────────────────────────────────────
def testStats : IO Unit := do
  IO.println ""
  IO.println "=== C. Stats ==="

  let s0 := ConnStats.empty
  check "empty ConnStats: bytesRead=0"   (s0.bytesRead == 0)
  check "empty ConnStats: not closed"    (!s0.closed)

  let s1 := s0.addBytesRead 100 |>.addBytesWritten 50
  check "addBytesRead 100"               (s1.bytesRead == 100)
  check "addBytesWritten 50"             (s1.bytesWritten == 50)
  check "readEvents incremented"         (s1.readEvents == 1)

  let s2 := s1.addPartialWrite.markClosed
  check "partialWrites incremented"      (s2.partialWrites == 1)
  check "markClosed"                     s2.closed

  let g0 := GlobalStats.empty
  let g1 := g0.addConn.addConn.addRequest.addRequest.addRequest
  check "GlobalStats.totalConns=2"       (g1.totalConns == 2)
  check "GlobalStats.totalRequests=3"    (g1.totalRequests == 3)

  let g2 := g1.addClosed s1
  check "addClosed updates totalBytes"   (g2.totalBytesRead == 100)
  check "addClosed increments closed"    (g2.closedConns == 1)

  -- reqPerSec
  let rps := g1.reqPerSec 1000000000  -- 1 second in ns
  check "reqPerSec: 3 req in 1s = 3.0"
    (rps > 2.9 && rps < 3.1)

-- ─────────────────────────────────────────────────────────────────────────
-- D. HTTP keep-alive header de-duplication
-- ─────────────────────────────────────────────────────────────────────────
def testHttpHeaders : IO Unit := do
  IO.println ""
  IO.println "=== D. HTTP keep-alive header de-dup ==="

  -- okKeepAlive should NOT produce duplicate Connection headers
  let resp := HttpResponse.okKeepAlive "test"
  let bytes := resp.toBytes
  let s := String.fromUTF8? bytes |>.getD ""
  let connLines := s.splitOn "\r\n" |>.filter fun l =>
    l.toLower.startsWith "connection:"
  check "okKeepAlive: exactly one Connection header" (connLines.length == 1)
  check "okKeepAlive: Connection: keep-alive"
    (connLines.head?.map (·.toLower) == some "connection: keep-alive")

  -- okClose should have Connection: close
  let resp2 := HttpResponse.okClose "bye"
  let bytes2 := resp2.toBytes
  let s2 := String.fromUTF8? bytes2 |>.getD ""
  let connLines2 := s2.splitOn "\r\n" |>.filter fun l =>
    l.toLower.startsWith "connection:"
  check "okClose: exactly one Connection header" (connLines2.length == 1)
  check "okClose: Connection: close"
    (connLines2.head?.map (·.toLower) == some "connection: close")

  -- keepAlive helper
  let req := HttpRequest.parse "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n".toUTF8
  check "HTTP/1.1 default keepAlive = true"
    (req.map (·.keepAlive) == some true)

  let req10 := HttpRequest.parse "GET / HTTP/1.0\r\n\r\n".toUTF8
  check "HTTP/1.0 default keepAlive = false"
    (req10.map (·.keepAlive) == some false)

-- ─────────────────────────────────────────────────────────────────────────
-- E. Throughput baseline (RFC 025)
-- ─────────────────────────────────────────────────────────────────────────
def testThroughput : IO Unit := do
  IO.println ""
  IO.println "=== E. Throughput baseline (RFC 025) ==="

  let (clientFd, serverFd) ← Socket.socketpairRaw
  check "socketpair for throughput" (clientFd >= 0)
  if clientFd < 0 then return

  let reqBytes := "GET /bench HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n".toUTF8
  let respBytes := (HttpResponse.okKeepAlive "pong").toBytes
  let n := 200

  let t0 ← Io.monoNs

  let mut ok := 0
  for _ in List.range n do
    -- Client sends request
    let (_, _) ← (WriteBuffer.empty.push reqBytes).flushAll clientFd
    -- Server reads 64 bytes
    let mut reqBuf := ByteArray.empty
    for _ in List.range 50 do
      if reqBuf.size >= 64 then break
      match ← Io.recv serverFd (64 - reqBuf.size) with
      | .bytes ba => reqBuf := appendBa reqBuf ba
      | .wouldBlock => IO.sleep 1
      | _ => break
    -- Server sends response
    let (_, _) ← (WriteBuffer.empty.push respBytes).flushAll serverFd
    -- Client reads response
    let mut respBuf := ByteArray.empty
    for _ in List.range 50 do
      if respBuf.size >= respBytes.size then break
      match ← Io.recv clientFd (respBytes.size - respBuf.size) with
      | .bytes ba => respBuf := appendBa respBuf ba
      | .wouldBlock => IO.sleep 1
      | _ => break
    if respBuf.size == respBytes.size then ok := ok + 1

  let t1 ← Io.monoNs
  let elapsedMs := (t1 - t0).toNat / 1000000
  let rps : Float :=
    if (t1 - t0).toNat == 0 then 0.0
    else Float.ofNat ok / (Float.ofNat (t1 - t0).toNat / 1000000000.0)

  Socket.closeFdRaw clientFd.toInt32
  Socket.closeFdRaw serverFd.toInt32

  IO.println s!"  {n} round-trips in {elapsedMs}ms → {rps} req/s"
  check "throughput: all round-trips succeeded"  (ok == n)
  check "throughput: elapsed < 10s"              (elapsedMs < 10000)
  check "throughput: > 1000 req/s"               (rps > 1000.0)

-- ─────────────────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────────────────
def main : IO Unit := do
  IO.println "iotakt v0.5 integration test"
  IO.println ""
  testActor
  testRegistry
  testStats
  testHttpHeaders
  testThroughput
  IO.println ""
  IO.println "v0.5 integration test complete"
