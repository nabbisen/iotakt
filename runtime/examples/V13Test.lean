import IotaktRuntime.Loop
import IotaktRuntime.Native

/-!
# iotakt v0.13 integration test

Settles the v1.0 open items from the API stability audit:

* **Coalesce ack — pinned to explicit acknowledgement.** `recvAck`/`sendAck`
  perform the I/O and clear the pending readiness in one step (RFC 006
  "together" helpers), so a consumer cannot forget to ack. Verified that a
  coalesced (suppressed) readiness is delivered again only after an ack.
* The Router-removal and task-tracking-internal decisions are compile-time /
  documentation changes verified by the rest of the gate (Server no longer
  exports Router; ReferenceServer imports it directly and still builds).
-/

open IotaktRuntime.Loop IotaktRuntime.Native Iotakt.Model

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- A. Explicit ack via the coalesce model (pure)
def testCoalesceAck : IO Unit := do
  IO.println "=== A. Coalesce: explicit ack pinned ==="
  let k : FdKey := { raw := 300, gen := 1 }
  let oe : OwnerEvent := { owner := 1, key := k, event := .readable }
  let st0 := CoalesceState.empty

  -- First readiness delivers and marks pending
  let (st1, r1) := st0.step oe
  check "first readiness delivers"
    (match r1 with | .deliver _ => true | _ => false)
  check "slot now pending" (st1.pending (CoalesceState.keyOf oe))

  -- Second readiness (no ack) is coalesced
  let (st2, r2) := st1.step oe
  check "second readiness coalesced (suppressed)"
    (match r2 with | .coalesced _ => true | _ => false)
  check "still exactly one pending" (st2.pending (CoalesceState.keyOf oe))

  -- After explicit ack, the slot clears
  let st3 := st2.ack (CoalesceState.keyOf oe)
  check "ack clears the pending slot" (!st3.pending (CoalesceState.keyOf oe))

  -- Now a fresh readiness delivers again (progress preserved)
  let (_, r3) := st3.step oe
  check "post-ack readiness delivers again"
    (match r3 with | .deliver _ => true | _ => false)

-- B. recvAck / sendAck combined helpers (live, over a socketpair)
def testRecvSendAck : IO Unit := do
  IO.println ""
  IO.println "=== B. recvAck / sendAck combined helpers ==="
  let some loop ← EventLoop.create | do IO.println "epoll failed"; return

  let (a, b) ← Socket.socketpairRaw
  if a < 0 then check "socketpair" false
  else do
    -- Pretend `b` is a registered connection key; mark its readable readiness
    -- pending so we can observe recvAck clearing it.
    let key : FdKey := { raw := b, gen := 1 }
    let pk : PendingKey := { fd := key, kind := .readable }
    -- Manually set pending via a step on the coalesce state
    let oe : OwnerEvent := { owner := 1, key := key, event := .readable }
    let cs1 := (loop.nds.ds.coalesce.step oe).1
    let loop1 := { loop with nds := { loop.nds with
                    ds := { loop.nds.ds with coalesce := cs1 } } }
    check "readable readiness pending before recvAck" (loop1.nds.ds.coalesce.pending pk)

    -- Send some bytes on `a` so recvAck on `b` returns data
    let msg := "ping".toUTF8
    let _ ← Io.send a msg 0 msg.size
    IO.sleep 20

    let (loop2, rr) ← loop1.recvAck key 64
    check "recvAck returned the bytes"
      (match rr with | .bytes d => (String.fromUTF8? d |>.getD "") == "ping" | _ => false)
    check "recvAck cleared readable pending" (!loop2.nds.ds.coalesce.pending pk)

    -- sendAck writes and clears writable pending
    let wpk : PendingKey := { fd := key, kind := .writable }
    let woe : OwnerEvent := { owner := 1, key := key, event := .writable }
    let cs2 := (loop2.nds.ds.coalesce.step woe).1
    let loop3 := { loop2 with nds := { loop2.nds with
                    ds := { loop2.nds.ds with coalesce := cs2 } } }
    check "writable readiness pending before sendAck" (loop3.nds.ds.coalesce.pending wpk)
    let out := "pong".toUTF8
    let (loop4, wr) ← loop3.sendAck key out 0 out.size
    check "sendAck wrote bytes"
      (match wr with | .wrote n => n.toNat == 4 | _ => false)
    check "sendAck cleared writable pending" (!loop4.nds.ds.coalesce.pending wpk)

    Socket.closeFdRaw (fd32 a)
    Socket.closeFdRaw (fd32 b)
  loop.destroy

def main : IO Unit := do
  IO.println "iotakt v0.13 integration test (explicit ack + recvAck/sendAck)"
  IO.println ""
  testCoalesceAck
  testRecvSendAck
  IO.println ""
  IO.println "v0.13 integration test complete"
