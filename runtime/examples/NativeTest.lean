import IotaktRuntime.Native
import Iotakt.Model

/-!
# iotakt native integration test

Tests the native C shim against the real Linux kernel using a loopback
TCP listener. No full driver loop; just the individual primitives:
epoll create/register/wait, socket/bind/listen/accept, recv/send.
-/

open Iotakt.Model IotaktRuntime.Native

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

/-- Convert an Int to Int32 for the raw FFI layer. Truncates negatives to 0. -/
private def toFd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def main : IO Unit := do
  IO.println "native integration test (Linux epoll + sockets)"

  -- ── 1. Create epoll instance ──────────────────────────────────────────
  let epfd ← Unsafe.Epoll.create
  check "epoll_create1 succeeds" (epfd >= 0)
  if epfd < 0 then return

  -- ── 2. Create TCP listener ────────────────────────────────────────────
  let lfd ← Unsafe.Socket.socketTcpRaw 1  -- AF_INET
  check "socket() AF_INET succeeds" (lfd >= 0)
  if lfd < 0 then do Unsafe.Epoll.close (toFd32 epfd); return

  let _ ← Unsafe.Socket.setReuseAddrRaw (toFd32 lfd)

  -- Bind to 127.0.0.1:49878
  let loopback : UInt32 := 0x7f000001
  let bind_r ← Unsafe.Socket.bindIPv4Raw (toFd32 lfd) loopback 49878
  if bind_r != 0 then do
    IO.println s!"  [SKIP] bind failed (port in use? errno={-bind_r}); skipping native test"
    Unsafe.Socket.closeFdRaw (toFd32 lfd); Unsafe.Epoll.close (toFd32 epfd); return
  check "bind 127.0.0.1:49878" (bind_r == 0)

  let listen_r ← Unsafe.Socket.listenRaw (toFd32 lfd) 8
  check "listen() succeeds" (listen_r == 0)

  -- ── 3. Register listener with epoll ───────────────────────────────────
  let reg_r ← Unsafe.Epoll.register (toFd32 epfd) (toFd32 lfd)
    (Unsafe.Epoll.interestFlags InterestSet.readOnly)
  check "epoll register listener" (reg_r == 0)

  -- ── 4. epoll_wait with 0 timeout → no events yet ──────────────────────
  let (wait_status, ba) ← Unsafe.Epoll.wait (toFd32 epfd) 64 0
  check "epoll_wait(timeout=0) returns 0 events" (wait_status == 0 && ba.size == 0)

  -- ── 5. accept on idle listener → wouldBlock ───────────────────────────
  let acc_r ← Unsafe.Socket.accept lfd
  check "accept on idle listener → wouldBlock"
    (match acc_r with | .wouldBlock => true | _ => false)

  -- ── 6. recv on a listener fd → error (not a connected stream) ─────────
  let recv_r ← Unsafe.Io.recv lfd 16
  check "recv on listener fd returns error"
    (match recv_r with | .error _ => true | _ => false)

  -- ── 7. send 0 bytes → wrote 0 ─────────────────────────────────────────
  let send_r ← Unsafe.Io.send lfd ByteArray.empty 0 0
  check "send 0 bytes → wrote 0"
    (match send_r with | .wrote 0 => true | _ => false)

  -- ── 8. epoll deregister and close ─────────────────────────────────────
  let dereg_r ← Unsafe.Epoll.deregister (toFd32 epfd) (toFd32 lfd)
  check "epoll deregister" (dereg_r == 0)

  Unsafe.Socket.closeFdRaw (toFd32 lfd)
  Unsafe.Epoll.close (toFd32 epfd)

  -- ── 9. event normalization: parse a synthetic ByteArray ───────────────
  -- Simulate an epoll wait result: one event with fd=10, flags=EPOLLIN(1)
  let rawEvt : ByteArray :=
    -- [fd:int32_t LE = 10][flags:uint32_t LE = 1 (EPOLLIN)]
    ⟨#[10, 0, 0, 0,   1, 0, 0, 0]⟩
  let evts := Unsafe.Epoll.parseEvents rawEvt
  check "parse 1 epoll event from ByteArray"
    (evts.length == 1)
  check "parsed event has correct rawFd (10)"
    (evts.head?.map (·.rawFd) == some 10)
  check "parsed event is readable"
    (evts.head?.map (·.event) == some IoEvent.readable)

  IO.println "native integration test complete"
