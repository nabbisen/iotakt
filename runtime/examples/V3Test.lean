import IotaktRuntime.Loop
import IotaktRuntime.Native

/-!
# iotakt v0.3 integration test

Tests three v0.3 additions:

* **RFC 036 — UDP datagrams**: `recvFrom` / `sendTo` over a loopback UDP socket.
* **RFC 039 — Outbound connect**: non-blocking TCP connect with EINPROGRESS,
  poll for writable, `checkConnect` confirms.
* **Persistent connections**: a long-lived connection that exchanges multiple
  request/response cycles without closing between rounds.
-/

open IotaktRuntime.Loop IotaktRuntime.Native Iotakt.Model

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32
private def LOOPBACK : UInt32 := 0x7f000001  -- 127.0.0.1

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- ─────────────────────────────────────────────────────────────────────────
-- Scenario A: UDP ping-pong (RFC 036)
-- ─────────────────────────────────────────────────────────────────────────
def testUdp : IO Unit := do
  IO.println "=== RFC 036: UDP datagrams ==="

  -- Create two UDP sockets
  let fd_a ← Unsafe.Socket.socketUdpRaw 1
  let fd_b ← Unsafe.Socket.socketUdpRaw 1
  check "udp socket A created" (fd_a >= 0)
  check "udp socket B created" (fd_b >= 0)
  if fd_a < 0 || fd_b < 0 then return

  -- Bind both to loopback on different ports
  let r_a ← Unsafe.Socket.bindIPv4Raw (fd32 fd_a) LOOPBACK 59100
  let r_b ← Unsafe.Socket.bindIPv4Raw (fd32 fd_b) LOOPBACK 59101
  check "bind udp A to :59100" (r_a == 0)
  check "bind udp B to :59101" (r_b == 0)

  -- A sends a datagram to B (port 59101)
  let ping : ByteArray := ⟨#[0x70, 0x69, 0x6e, 0x67]⟩  -- "ping"
  let sr ← Unsafe.Io.sendTo fd_a ping 0 ping.size LOOPBACK 59101
  check "sendTo B succeeds"
    (match sr with | .wrote n => n == 4 | _ => false)

  -- B receives the datagram
  let rr ← Unsafe.Io.recvFrom fd_b 64
  check "recvFrom B gets 'ping'"
    (match rr with | .datagram ba _ => ba.toList == ping.toList | _ => false)
  check "recvFrom B peer addr is 4 bytes (IPv4)"
    (match rr with | .datagram _ addr => addr.size == 6 | _ => false)

  -- B echoes back to A (port 59100)
  let pong : ByteArray := ⟨#[0x70, 0x6f, 0x6e, 0x67]⟩  -- "pong"
  let sr2 ← Unsafe.Io.sendTo fd_b pong 0 pong.size LOOPBACK 59100
  check "sendTo A succeeds"
    (match sr2 with | .wrote n => n == 4 | _ => false)

  let rr2 ← Unsafe.Io.recvFrom fd_a 64
  check "recvFrom A gets 'pong'"
    (match rr2 with | .datagram ba _ => ba.toList == pong.toList | _ => false)

  Unsafe.Socket.closeFdRaw (fd32 fd_a)
  Unsafe.Socket.closeFdRaw (fd32 fd_b)

-- ─────────────────────────────────────────────────────────────────────────
-- Scenario B: Outbound TCP connect (RFC 039)
-- ─────────────────────────────────────────────────────────────────────────
def testOutboundConnect : IO Unit := do
  IO.println ""
  IO.println "=== RFC 039: Outbound TCP connect ==="

  let some loop ← EventLoop.create | do IO.println "epoll failed"; return
  let (loop1, ok) ← loop.addListener 49950
  check "listener on :49950" ok
  if !ok then do loop.unsafeDestroy; return

  -- Outbound connect to our own listener (loopback)
  let (loop2, outcome) ← loop1.unsafeConnectTo LOOPBACK 49950
  check "unsafeConnectTo returns inProgress or connected"
    (match outcome with | .inProgress _ | .connected _ => true | _ => false)

  -- Drain a few driver steps: accept the connection, then check writable
  let mut loop := loop2
  let mut connKey : Option FdKey := none
  let mut clientKey : Option FdKey := match outcome with
    | .inProgress k | .connected k => some k
    | _ => none
  let mut clientConnected := match outcome with | .connected _ => true | _ => false

  for _ in List.range 20 do
    let (loop1', events) ← LoopError.orThrow (← loop.runStep 100)
    loop := loop1'
    for ev in events do
      match ev with
      | .newConnection _ key =>
          connKey := some key
      | .dataReady key event =>
          match event with
          | .writable =>
              if clientKey == some key && !clientConnected then do
                let r ← Unsafe.Socket.checkConnect key.raw
                match r with
                | .connected => clientConnected := true
                | _ => pure ()
          | _ => pure ()
      | .tick _ => pure ()

  check "listener accepted inbound side of connect" connKey.isSome
  check "outbound connect confirmed connected" clientConnected

  -- Send data on the outbound (client) side, receive on the inbound
  if let some cKey := clientKey then do
    let data : ByteArray := ⟨#[0x48, 0x65, 0x6c, 0x6c, 0x6f]⟩  -- "Hello"
    let _ ← Unsafe.Io.send cKey.raw data 0 data.size
    -- Give the server side a moment then recv
    let (loop3, _) ← LoopError.orThrow (← loop.runStep 50)
    loop := loop3
    if let some sKey := connKey then do
      let rr ← Unsafe.Io.recv sKey.raw 64
      check "data received on server side of connect"
        (match rr with | .bytes ba => ba.toList == data.toList | _ => false)
      loop := ← EffectError.orThrow (← loop.closeConnection sKey)
    loop := ← EffectError.orThrow (← loop.closeConnection cKey)

  loop.unsafeDestroy

-- ─────────────────────────────────────────────────────────────────────────
-- Scenario C: Persistent multi-round connection
-- ─────────────────────────────────────────────────────────────────────────
def testPersistentConn : IO Unit := do
  IO.println ""
  IO.println "=== Persistent connection: multiple recv/send rounds ==="

  -- Use a socketpair for deterministic persistent connection test
  let (fd0, fd1) ← Unsafe.Socket.socketpairRaw
  check "socketpair created" (fd0 >= 0 && fd1 >= 0)
  if fd0 < 0 then return

  -- fd0 = "server side"; fd1 = "client side" (we control both)
  let rounds := 5
  let mut totalSent := 0
  let mut totalEchoed := 0

  for i in List.range rounds do
    -- "client" writes a message on fd1
    let msg : ByteArray := ⟨#[0x52, (i.toUInt8 + 65)]⟩  -- "R" + letter
    let _ ← Unsafe.Io.send fd1 msg 0 msg.size
    -- "server" reads and echoes on fd0
    let rr ← Unsafe.Io.recv fd0 32
    match rr with
    | .bytes ba =>
        totalSent := totalSent + ba.size
        let _ ← Unsafe.Io.send fd0 ba 0 ba.size  -- echo
        -- "client" reads the echo
        let er ← Unsafe.Io.recv fd1 32
        match er with
        | .bytes echoBa => totalEchoed := totalEchoed + echoBa.size
        | _ => pure ()
    | _ => pure ()

  check s!"persistent connection: {rounds} rounds all completed" (totalSent == rounds * 2)
  check "persistent connection: all bytes echoed back" (totalEchoed == totalSent)

  Unsafe.Socket.closeFdRaw (fd32 fd0)
  Unsafe.Socket.closeFdRaw (fd32 fd1)

-- ─────────────────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────────────────
def main : IO Unit := do
  IO.println "iotakt v0.3 integration test"
  IO.println ""
  testUdp
  testOutboundConnect
  testPersistentConn
  IO.println ""
  IO.println "v0.3 integration test complete"
