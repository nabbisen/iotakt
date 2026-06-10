import Iotakt.Loop
import Iotakt.Native

/-!
# iotakt v0.11 integration test

iotakt-owned stabilization features (RFC 037, RFC 030):

* **Connection limits** — `withMaxConnections`, `connectionCount`,
  `atCapacity`; accepts past the cap are shed in `runStep`.
* **Graceful shutdown** — `shutdown` deregisters/closes listeners and drains
  active connections (cancelling their Henret tasks), leaving the poller for
  `destroy`.
-/

open Iotakt.Loop Iotakt.Native Iotakt.Model

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
  let (loop1, ok) ← loop.addListener 49998
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
      let _ ← Socket.connectIPv4 cfd LOOPBACK 49998
      clients := cfd :: clients
  -- Give the kernel a moment to complete the connects
  IO.sleep 50

  -- One runStep accept burst: at most 1 should be admitted (cap=1)
  let (loop3, events) ← loop2.runStep 100
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

  -- Track a couple of fake connections so shutdown has something to drain
  let k1 : FdKey := { raw := 210, gen := 1 }
  let k2 : FdKey := { raw := 211, gen := 1 }
  let loop2 := (loop1.recordTask k1 20).recordTask k2 21
  check "before shutdown: 1 listener tracked" (loop2.listeners.length == 1)
  check "before shutdown: 2 connections tracked" (loop2.connectionCount == 2)

  let loop3 ← loop2.shutdown
  check "after shutdown: no listeners" (loop3.listeners.isEmpty)
  check "after shutdown: all connections drained" (loop3.connectionCount == 0)
  check "after shutdown: activity records cleared" (loop3.lastActivityNs.isEmpty)

  -- destroy finalizes the poller (no crash)
  loop3.destroy
  check "destroy after shutdown completes cleanly" true

def main : IO Unit := do
  IO.println "iotakt v0.11 integration test (connection limits + graceful shutdown)"
  IO.println ""
  testCapacityBookkeeping
  testCapEnforcement
  testShutdown
  IO.println ""
  IO.println "v0.11 integration test complete"
