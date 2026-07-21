import IotaktRuntime.Loop
import IotaktRuntime.Http

/-!
# iotakt v0.4 integration test

Tests the four v0.4 additions:

* **WriteBuffer** — push/unsafeFlush/partial-write/unsafeFlushAll semantics.
* **HTTP/1.0 round-trip** — server + client over a loopback socketpair.
* **RFC 028 FFI invariants** — ByteArray allocation correctness (live checks).
* **RFC 026 native conformance** — recv/send edge cases (zero bytes, EAGAIN,
  ECONNRESET) verified against real syscalls.
-/

open IotaktRuntime.Loop IotaktRuntime.Http IotaktRuntime.Native Iotakt.Model IotaktRuntime.WriteBuffer

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32
private def LOOPBACK : UInt32 := 0x7f000001

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- ─────────────────────────────────────────────────────────────────────────
-- A. WriteBuffer unit tests
-- ─────────────────────────────────────────────────────────────────────────
def testWriteBuffer : IO Unit := do
  IO.println "=== A. WriteBuffer ==="

  let wb := WriteBuffer.empty
  check "empty buffer: isEmpty"  wb.isEmpty
  check "empty buffer: unsent=0" (wb.unsent == 0)

  let data : ByteArray := "Hello, world!".toUTF8
  let wb1 := wb.push data
  check "after push: not empty"      (! wb1.isEmpty)
  check "after push: unsent=13"      (wb1.unsent == 13)

  -- push again while non-empty: should append
  let more : ByteArray := " More.".toUTF8
  let wb2 := wb1.push more
  check "second push appends"        (wb2.unsent == 19)

  -- Flush over a socketpair
  let (fd0, fd1) ← Unsafe.Socket.socketpairRaw
  check "socketpair for WriteBuffer unsafeFlush" (fd0 >= 0)

  let (wb3, flushed) ← wb2.unsafeFlush fd0
  check "unsafeFlush sends all bytes (19)" flushed
  check "buffer empty after unsafeFlush"   wb3.isEmpty

  -- fd1 should have 19 bytes readable
  let rr ← Unsafe.Io.recv fd1 64
  check "recv gets all 19 bytes"
    (match rr with | .bytes ba => ba.size == 19 | _ => false)

  -- unsafeFlushAll on an empty buffer
  let (wb4, ok) ← WriteBuffer.empty.unsafeFlushAll fd0
  check "unsafeFlushAll on empty: returns true" (ok && wb4.isEmpty)

  Unsafe.Socket.closeFdRaw (fd32 fd0)
  Unsafe.Socket.closeFdRaw (fd32 fd1)

-- ─────────────────────────────────────────────────────────────────────────
-- B. HTTP/1.0 round-trip over a socketpair
-- ─────────────────────────────────────────────────────────────────────────
def testHttpRoundTrip : IO Unit := do
  IO.println ""
  IO.println "=== B. HTTP/1.0 round-trip (socketpair) ==="

  let (serverFd, clientFd) ← Unsafe.Socket.socketpairRaw
  check "socketpair for HTTP test" (serverFd >= 0)
  if serverFd < 0 then return

  -- Client sends GET request
  let reqBytes := HttpRequest.get "localhost" "/ping"
  let wb := WriteBuffer.empty.push reqBytes
  let (_, sent) ← wb.unsafeFlushAll clientFd
  check "client: GET request sent" sent

  -- Server reads the request
  let rawReq ← HttpRequest.unsafeReadHeaders serverFd 8192
  check "server: headers received" rawReq.isSome

  let parsedReq := rawReq.bind HttpRequest.parse
  check "server: request parsed"
    (match parsedReq with | some r => r.method == "GET" && r.path == "/ping" | none => false)

  -- Server sends 200 OK response
  let resp := HttpResponse.ok "pong from iotakt"
  let respBytes := resp.toBytes
  check "response serialized (non-empty)" (respBytes.size > 0)

  let wb2 := WriteBuffer.empty.push respBytes
  let (_, sent2) ← wb2.unsafeFlushAll serverFd
  check "server: response sent" sent2

  -- Signal EOF to the client (close server write side)
  Unsafe.Socket.closeFdRaw (fd32 serverFd)

  -- Client reads the full response
  let rawResp ← HttpResponse.unsafeReadAll clientFd
  check "client: response received"  (rawResp.size > 0)

  let status := HttpResponse.parseStatus rawResp
  check "client: status 200"
    (match status with | some 200 => true | _ => false)

  let body := HttpResponse.extractBody rawResp
  check "client: body contains 'pong'"
    (match body with | some b => (b.splitOn "pong").length > 1 | none => false)

  Unsafe.Socket.closeFdRaw (fd32 clientFd)

-- ─────────────────────────────────────────────────────────────────────────
-- C. RFC 028 FFI invariants — ByteArray ownership
-- ─────────────────────────────────────────────────────────────────────────
def testFfiInvariants : IO Unit := do
  IO.println ""
  IO.println "=== C. RFC 028 FFI invariants ==="

  -- INV-1: recv returns a fresh ByteArray each call; sizes match
  let (fd0, fd1) ← Unsafe.Socket.socketpairRaw
  check "socketpair for FFI test" (fd0 >= 0)
  if fd0 < 0 then return

  let data1 : ByteArray := ⟨#[1, 2, 3, 4, 5]⟩
  let data2 : ByteArray := ⟨#[10, 20, 30]⟩

  let _ ← Unsafe.Io.send fd1 data1 0 5
  let _ ← Unsafe.Io.send fd1 data2 0 3

  let r1 ← Unsafe.Io.recv fd0 5
  let r2 ← Unsafe.Io.recv fd0 5
  check "INV-1a: first recv returns exactly 5 bytes"
    (match r1 with | .bytes ba => ba.size == 5 | _ => false)
  check "INV-1b: second recv returns exactly 3 bytes"
    (match r2 with | .bytes ba => ba.size == 3 | _ => false)

  -- INV-2: recv on closed fd returns EOF or error (not a crash)
  Unsafe.Socket.closeFdRaw (fd32 fd1)
  let rEof ← Unsafe.Io.recv fd0 64
  check "INV-2: recv after peer-close returns eof or error"
    (match rEof with | .eof | .error _ => true | _ => false)

  -- INV-3: send on closed fd returns error (not a crash)
  let sErr ← Unsafe.Io.send fd0 data1 0 5
  check "INV-3: send after peer-close returns error"
    (match sErr with | .error _ | .closed => true | _ => false)

  Unsafe.Socket.closeFdRaw (fd32 fd0)

  -- INV-4: recvfrom on UDP socket returns peer address of correct size
  let udpA ← Unsafe.Socket.socketUdpRaw 1
  let udpB ← Unsafe.Socket.socketUdpRaw 1
  let _ ← Unsafe.Socket.bindIPv4Raw (fd32 udpA) LOOPBACK 59200
  let _ ← Unsafe.Socket.bindIPv4Raw (fd32 udpB) LOOPBACK 59201
  let _ ← Unsafe.Io.sendTo udpA ⟨#[42]⟩ 0 1 LOOPBACK 59201
  let rfr ← Unsafe.Io.recvFrom udpB 64
  check "INV-4: recvfrom peer addr is exactly 6 bytes (IPv4 + port)"
    (match rfr with | .datagram _ addr => addr.size == 6 | _ => false)
  Unsafe.Socket.closeFdRaw (fd32 udpA)
  Unsafe.Socket.closeFdRaw (fd32 udpB)

-- ─────────────────────────────────────────────────────────────────────────
-- D. RFC 026 native conformance — edge cases
-- ─────────────────────────────────────────────────────────────────────────
def testNativeConformance : IO Unit := do
  IO.println ""
  IO.println "=== D. RFC 026 native conformance edge cases ==="

  -- CONF-1: recv with maxBytes=0 returns wouldBlock or bytes(0)
  let (fd0, fd1) ← Unsafe.Socket.socketpairRaw
  let _ ← Unsafe.Io.send fd1 ⟨#[99]⟩ 0 1
  let r0 ← Unsafe.Io.recv fd0 0
  check "CONF-1: recv maxBytes=0 does not crash"
    (match r0 with | .bytes _ | .wouldBlock | .eof => true | _ => false)

  -- CONF-2: send offset beyond ByteArray size is safe
  let ba : ByteArray := ⟨#[1, 2, 3]⟩
  let rBig ← Unsafe.Io.send fd1 ba 100 3   -- offset 100 > size 3
  check "CONF-2: send with offset > size is safe (0 bytes)"
    (match rBig with | .wrote n => n == 0 | _ => true)  -- either 0 or error

  -- CONF-3: epoll fd survives close-and-reopen cycle
  let some loop ← EventLoop.create | pure ()
  let (loop1, ok) ← loop.addListener 49985
  check "CONF-3a: EventLoop.addListener" ok
  loop1.unsafeDestroy
  -- Creating another loop immediately reuses the epoll fd slot
  let some loop2 ← EventLoop.create | pure ()
  let (loop3, ok2) ← loop2.addListener 49985
  check "CONF-3b: second EventLoop on same port after unsafeDestroy" ok2
  loop3.unsafeDestroy

  -- CONF-4: FdKey generation increments on reallocate
  let some loop4 ← EventLoop.create | pure ()
  let (loop5, ok3) ← loop4.addListener 49986
  check "CONF-4: addListener on fresh port" ok3
  -- Close and immediately reopen the same port
  -- (generation in the registry must have incremented)
  let gen0 := loop5.nds.ds.registry.nextGen
  -- A listener is not connection authority. Until RFC 070's checked
  -- closeListener lands, use the listener-aware unsafeShutdown path.
  let loop5 ← loop5.unsafeShutdown
  let (loop6, _) ← loop5.addListener 49987
  let gen1 := loop6.nds.ds.registry.nextGen
  check "CONF-4: nextGen increments after close+reopen" (gen1 > gen0)
  loop6.unsafeDestroy

  Unsafe.Socket.closeFdRaw (fd32 fd0)
  Unsafe.Socket.closeFdRaw (fd32 fd1)

-- ─────────────────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────────────────
def main : IO Unit := do
  IO.println "iotakt v0.4 integration test"
  IO.println ""
  testWriteBuffer
  testHttpRoundTrip
  testFfiInvariants
  testNativeConformance
  IO.println ""
  IO.println "v0.4 integration test complete"
