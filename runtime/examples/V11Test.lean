import IotaktRuntime.Loop
import IotaktRuntime.Native

/-!
# iotakt v0.11 integration test

iotakt-owned stabilization features (RFC 037, RFC 030):

* **Connection limits** — `withMaxConnections`, `connectionCount`,
  `atCapacity`; accepts past the cap are shed in `runStep`.
* **Graceful shutdown** — `shutdown` deregisters/closes listeners and drains
  active connections (cancelling their Henret tasks), leaving the poller for
  `destroy`.
-/

open IotaktRuntime.Loop IotaktRuntime.Native Iotakt.Model

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- A. Connection-count + capacity bookkeeping
def testCapacityBookkeeping : IO Unit := do
  IO.println "=== A. Connection cap bookkeeping ==="
  let some loop ← EventLoop.create | do IO.println "epoll failed"; return

  check "fresh loop: connectionCount = 0" (loop.connectionCount == 0)
  check "no cap configured: atCapacity = false" (!loop.atCapacity)

  let loop1 := loop.withMaxConnections 2
  check "cap set: still under capacity at 0" (!loop1.atCapacity)

  -- Simulate tracked connections via recordTask
  let k1 : FdKey := { raw := 200, gen := 1 }
  let k2 : FdKey := { raw := 201, gen := 1 }
  let loop2 := (loop1.recordTask k1 10).recordTask k2 11
  check "two connections: connectionCount = 2" (loop2.connectionCount == 2)
  check "at cap (2/2): atCapacity = true" (loop2.atCapacity)

  let loop3 := loop2.forgetTask k1
  check "after one close: connectionCount = 1" (loop3.connectionCount == 1)
  check "back under cap: atCapacity = false" (!loop3.atCapacity)

  loop.destroy

-- B. Live connection-cap enforcement (load shedding)
def testCapEnforcement : IO Unit := do
  IO.println ""
  IO.println "=== B. Connection cap enforcement (load shedding) ==="
  let some loop ← EventLoop.create | do IO.println "epoll failed"; return
  let port : UInt16 := 49998
  let (loop1, ok) ← loop.addListener port
  check "listener bound" ok
  if !ok then do loop.destroy; return

  -- Cap at 1 connection
  let loop2 := loop1.withMaxConnections 1
  let LOOPBACK : UInt32 := 0x7f000001  -- 127.0.0.1, host byte order (C htonl's it)

  -- Open three client connections to the listener (create socket, then connect)
  let mut clients : List Int := []
  for _ in List.range 3 do
    let cfd ← Socket.socketTcpRaw 1
    if cfd >= 0 then do
      let _ ← Socket.connectIPv4 cfd LOOPBACK port
      clients := cfd :: clients
  -- Give the kernel a moment to complete the connects
  IO.sleep 50

  -- One runStep accept burst: at most 1 should be admitted (cap=1)
  let (loop3, events) ← LoopError.orThrow (← loop2.runStep 100)
  let admitted := events.filter (fun e => match e with | .newConnection _ _ => true | _ => false)
  check "cap=1: at most 1 connection admitted in the burst" (admitted.length <= 1)
  check "loop connectionCount respects cap (<= 1)" (loop3.connectionCount <= 1)

  -- Clean up clients
  for fd in clients do Socket.closeFdRaw (Int32.mk fd.toNat.toUInt32)
  loop3.destroy

-- C. Graceful shutdown
def testShutdown : IO Unit := do
  IO.println ""
  IO.println "=== C. Graceful shutdown ==="
  let some loop ← EventLoop.create | do IO.println "epoll failed"; return
  let (loop1, ok) ← loop.addListener 49999
  check "listener bound for shutdown test" ok
  if !ok then do loop.destroy; return

  -- Register real socketpair endpoints so shutdown exercises RFC 064's checked
  -- connection authority and native deregister/close path.
  let (peer1, fd1) ← Socket.socketpairRaw
  let (peer2, fd2) ← Socket.socketpairRaw
  if peer1 < 0 || peer2 < 0 then do
    check "socketpairs for shutdown test" false
    loop1.destroy
    return
  let (reg1, k1) := loop1.nds.ds.registry.allocate fd1 20 .stream
  let reg1 := reg1.setInterests k1 InterestSet.readOnly |>.markActive k1
  let (reg2, k2) := reg1.allocate fd2 21 .stream
  let reg2 := reg2.setInterests k2 InterestSet.readOnly |>.markActive k2
  let ep1 ← Epoll.register (fd32 loop1.ph.epfd) (fd32 fd1)
    (Epoll.interestFlags InterestSet.readOnly)
  let ep2 ← Epoll.register (fd32 loop1.ph.epfd) (fd32 fd2)
    (Epoll.interestFlags InterestSet.readOnly)
  check "socketpairs registered for shutdown test" (ep1 == 0 && ep2 == 0)
  if ep1 != 0 || ep2 != 0 then do
    Socket.closeFdRaw (fd32 peer1)
    Socket.closeFdRaw (fd32 fd1)
    Socket.closeFdRaw (fd32 peer2)
    Socket.closeFdRaw (fd32 fd2)
    loop1.destroy
    return
  let loop1 := { loop1 with nds := { loop1.nds with
    ds := { loop1.nds.ds with registry := reg2 } } }
  let loop2 := (loop1.recordTask k1 20).recordTask k2 21
  check "before shutdown: 1 listener tracked" (loop2.listeners.length == 1)
  check "before shutdown: 2 connections tracked" (loop2.connectionCount == 2)

  let loop3 ← loop2.shutdown
  check "after shutdown: no listeners" (loop3.listeners.isEmpty)
  check "after shutdown: all connections drained" (loop3.connectionCount == 0)
  check "after shutdown: activity records cleared" (loop3.lastActivityNs.isEmpty)

  -- destroy finalizes the poller (no crash)
  loop3.destroy
  Socket.closeFdRaw (fd32 peer1)
  Socket.closeFdRaw (fd32 peer2)
  check "destroy after shutdown completes cleanly" true

def main : IO Unit := do
  IO.println "iotakt v0.11 integration test (connection limits + graceful shutdown)"
  IO.println ""
  testCapacityBookkeeping
  testCapEnforcement
  testShutdown
  IO.println ""
  IO.println "v0.11 integration test complete"
