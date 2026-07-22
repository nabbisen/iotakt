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

def isStale {α : Type} : Except EffectError α → Bool
  | .error .staleKey => true
  | _ => false

def isInvalidRaw {α : Type} : Except EffectError α → Bool
  | .error .invalidRawFd => true
  | _ => false

def isInvalidKey {α : Type} : Except EffectError α → Bool
  | .error .invalidKey => true
  | _ => false

def hasEffectError {α : Type} (expected : EffectError) : Except EffectError α → Bool
  | .error actual => actual == expected
  | .ok _ => false

def checkAuthorityCase (label : String) (loop : EventLoop) (key : FdKey)
    (expected : EffectError) : IO Unit := do
  let payload := "blocked".toUTF8
  check s!"{label}: enableWrite" <|
    hasEffectError expected (← loop.enableWrite key)
  check s!"{label}: disableWrite" <|
    hasEffectError expected (← loop.disableWrite key)
  check s!"{label}: closeConnection" <|
    hasEffectError expected (← loop.closeConnection key)
  check s!"{label}: recvAck" <|
    hasEffectError expected (← loop.recvAck key 1)
  check s!"{label}: sendAck" <|
    hasEffectError expected (← loop.sendAck key payload 0 payload.size)

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

  let (a, b) ← Unsafe.Socket.socketpairRaw
  if a < 0 then check "socketpair" false
  else do
    -- Register `b` as a live stream, then mark its readable readiness pending
    -- so we can observe checked authority and recvAck clearing it.
    let (reg1, key) := loop.nds.ds.registry.allocate b 1 .stream
    let reg2 := reg1.setInterests key InterestSet.readOnly |>.markActive key
    let loop0 := { loop with nds := { loop.nds with
                    ds := { loop.nds.ds with registry := reg2 } } }
    let pk : PendingKey := { fd := key, kind := .readable }
    -- Manually set pending via a step on the coalesce state
    let oe : OwnerEvent := { owner := 1, key := key, event := .readable }
    let cs1 := (loop0.nds.ds.coalesce.step oe).1
    let loop1 := { loop0 with nds := { loop0.nds with
                    ds := { loop0.nds.ds with coalesce := cs1 } } }
    check "readable readiness pending before recvAck" (loop1.nds.ds.coalesce.pending pk)

    -- Queue bytes before the rejected authority calls. A later successful
    -- recv proves those calls neither consumed data nor closed the live fd.
    let msg := "ping".toUTF8
    let pingWrite ← Unsafe.Io.send a msg 0 msg.size
    match pingWrite with
    | .wrote n => IO.println s!"    peer send count={n.toNat}"
    | .wouldBlock => IO.println "    peer send result=wouldBlock"
    | .interrupted => IO.println "    peer send result=interrupted"
    | .closed => IO.println "    peer send result=closed"
    | .invalidSlice => IO.println "    peer send result=invalidSlice"
    | .nativeLengthLimit => IO.println "    peer send result=nativeLengthLimit"
    | .error e => IO.println s!"    peer send error={repr e}"
    check "peer send before authority checks wrote bytes"
      (match pingWrite with | .wrote n => n.toNat == 4 | _ => false)
    IO.sleep 20

    let stale : FdKey := { key with gen := key.gen + 1 }
    let invalid : FdKey := { raw := -1, gen := key.gen }
    let outOfRange : FdKey := { raw := 2147483648, gen := key.gen }
    check "stale enableWrite rejected" (isStale (← loop1.enableWrite stale))
    check "stale disableWrite rejected" (isStale (← loop1.disableWrite stale))
    check "stale close rejected" (isStale (← loop1.closeConnection stale))
    check "stale close preserves current key"
      (loop1.nds.ds.registry.resolveCurrent key.raw == some key)
    check "invalid-raw enableWrite rejected" (isInvalidRaw (← loop1.enableWrite invalid))
    check "invalid-raw disableWrite rejected" (isInvalidRaw (← loop1.disableWrite invalid))
    check "invalid-raw close rejected" (isInvalidRaw (← loop1.closeConnection invalid))
    check "out-of-range raw fd rejected before native conversion"
      (isInvalidRaw (← loop1.closeConnection outOfRange))

    check "stale recvAck rejected without consuming data"
      (isStale (← loop1.recvAck stale 64))
    check "invalid-raw recvAck rejected" (isInvalidRaw (← loop1.recvAck invalid 64))

    let (loop2, rr) ← EffectError.orThrow (← loop1.recvAck key 64)
    match rr with
    | .bytes d => IO.println s!"    recvAck bytes={d.size}"
    | .wouldBlock => IO.println "    recvAck result=wouldBlock"
    | .eof => IO.println "    recvAck result=eof"
    | .interrupted => IO.println "    recvAck result=interrupted"
    | .error e => IO.println s!"    recvAck error={repr e}"
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
    check "stale sendAck rejected" (isStale (← loop3.sendAck stale out 0 out.size))
    check "invalid-raw sendAck rejected"
      (isInvalidRaw (← loop3.sendAck invalid out 0 out.size))
    let (loop4, wr) ← EffectError.orThrow (← loop3.sendAck key out 0 out.size)
    match wr with
    | .wrote n => IO.println s!"    sendAck count={n.toNat}"
    | .wouldBlock => IO.println "    sendAck result=wouldBlock"
    | .interrupted => IO.println "    sendAck result=interrupted"
    | .closed => IO.println "    sendAck result=closed"
    | .invalidSlice => IO.println "    sendAck result=invalidSlice"
    | .nativeLengthLimit => IO.println "    sendAck result=nativeLengthLimit"
    | .error e => IO.println s!"    sendAck error={repr e}"
    check "sendAck wrote bytes"
      (match wr with | .wrote n => n.toNat == 4 | _ => false)
    check "sendAck cleared writable pending" (!loop4.nds.ds.coalesce.pending wpk)

    Unsafe.Socket.closeFdRaw (fd32 a)
    Unsafe.Socket.closeFdRaw (fd32 b)
  loop.unsafeDestroy

-- C. RFC064-FD-REUSE-001: stale authority must not affect the newer owner.
def testLiveFdReuseAuthority : IO Unit := do
  IO.println ""
  IO.println "=== C. RFC064-FD-REUSE-001: live raw-fd reuse authority ==="
  let some loop ← EventLoop.create | do IO.println "epoll failed"; return

  let (oldPeer, oldFd) ← Unsafe.Socket.socketpairRaw
  check "reuse fixture: initial socketpair created" (oldPeer >= 0 && oldFd >= 0)
  if oldPeer < 0 || oldFd < 0 then do
    loop.unsafeDestroy
    return

  let (oldReg, oldKey) := loop.nds.ds.registry.allocate oldFd 40 .stream
  let oldReg := oldReg.setInterests oldKey InterestSet.readOnly |>.markActive oldKey
  let oldRegister ← Unsafe.Epoll.register (fd32 loop.ph.epfd) (fd32 oldFd)
    (Unsafe.Epoll.interestFlags InterestSet.readOnly)
  check "reuse fixture: original generation registered" (oldRegister == 0)
  if oldRegister != 0 then do
    Unsafe.Socket.closeFdRaw (fd32 oldPeer)
    Unsafe.Socket.closeFdRaw (fd32 oldFd)
    loop.unsafeDestroy
    return

  let oldLoop := ({ loop with nds := { loop.nds with
    ds := { loop.nds.ds with registry := oldReg } } }).recordConnection oldKey
  let closedOld ← EffectError.orThrow (← oldLoop.closeConnection oldKey)
  check "checked close removes original generation authority"
    (closedOld.nds.ds.registry.resolveCurrent oldFd == none &&
      closedOld.connectionCount == 0)

  -- Linux assigns the lowest free descriptor, so keeping oldPeer and the poller
  -- open makes the first endpoint reuse oldFd deterministically.
  let (newFd, newPeer) ← Unsafe.Socket.socketpairRaw
  check "kernel reuses the closed raw fd for a newer owner" (newFd == oldFd)
  if newFd != oldFd then do
    Unsafe.Socket.closeFdRaw (fd32 oldPeer)
    if newFd >= 0 then Unsafe.Socket.closeFdRaw (fd32 newFd)
    if newPeer >= 0 then Unsafe.Socket.closeFdRaw (fd32 newPeer)
    closedOld.unsafeDestroy
    return

  let (newReg, newKey) := closedOld.nds.ds.registry.allocate newFd 41 .stream
  let newReg := newReg.setInterests newKey InterestSet.readOnly |>.markActive newKey
  let newRegister ← Unsafe.Epoll.register (fd32 closedOld.ph.epfd) (fd32 newFd)
    (Unsafe.Epoll.interestFlags InterestSet.readOnly)
  check "new generation registers on the reused raw fd"
    (newRegister == 0 && newKey != oldKey && newKey.raw == oldKey.raw)
  if newRegister != 0 then do
    Unsafe.Socket.closeFdRaw (fd32 oldPeer)
    Unsafe.Socket.closeFdRaw (fd32 newFd)
    Unsafe.Socket.closeFdRaw (fd32 newPeer)
    closedOld.unsafeDestroy
    return

  let newLoop := ({ closedOld with nds := { closedOld.nds with
    ds := { closedOld.nds.ds with registry := newReg } } }).recordConnection newKey

  check "reused-fd stale enableWrite is rejected" (isStale (← newLoop.enableWrite oldKey))
  check "reused-fd stale disableWrite is rejected" (isStale (← newLoop.disableWrite oldKey))
  check "reused-fd stale close is rejected" (isStale (← newLoop.closeConnection oldKey))
  check "stale interest/close attempts preserve newer authority and interests"
    (newLoop.nds.ds.registry.resolveCurrent newFd == some newKey &&
      (newLoop.nds.ds.registry.lookup newKey).map (·.interests) == some InterestSet.readOnly)

  let inbound := "new-owner".toUTF8
  let inboundWrite ← Unsafe.Io.send newPeer inbound 0 inbound.size
  check "new peer queues bytes before stale receive"
    (match inboundWrite with | .wrote n => n.toNat == inbound.size | _ => false)
  check "reused-fd stale recvAck is rejected" (isStale (← newLoop.recvAck oldKey 64))
  let (_, inboundRead) ← EffectError.orThrow (← newLoop.recvAck newKey 64)
  check "stale recvAck did not consume the newer owner's bytes"
    (match inboundRead with | .bytes bytes => bytes.toList == inbound.toList | _ => false)

  let outbound := "still-open".toUTF8
  check "reused-fd stale sendAck is rejected"
    (isStale (← newLoop.sendAck oldKey outbound 0 outbound.size))
  let peerBeforeLiveSend ← Unsafe.Io.recv newPeer 64
  check "stale sendAck emitted no bytes to the newer peer"
    (match peerBeforeLiveSend with | .wouldBlock => true | _ => false)
  let (_, outboundWrite) ←
    EffectError.orThrow (← newLoop.sendAck newKey outbound 0 outbound.size)
  check "new generation sendAck still writes"
    (match outboundWrite with | .wrote n => n.toNat == outbound.size | _ => false)
  let peerAfterLiveSend ← Unsafe.Io.recv newPeer 64
  check "newer peer receives only the live generation's bytes"
    (match peerAfterLiveSend with
      | .bytes bytes => bytes.toList == outbound.toList
      | _ => false)

  let closedNew ← EffectError.orThrow (← newLoop.closeConnection newKey)
  check "new generation closes through checked authority"
    (closedNew.nds.ds.registry.resolveCurrent newFd == none)

  let (thirdFd, thirdPeer) ← Unsafe.Socket.socketpairRaw
  check "raw fd is reused again after checked close" (thirdFd == newFd)
  let doubleClose ← closedNew.closeConnection newKey
  check "double close is visibly rejected before a second native close"
    (isInvalidKey doubleClose)
  let survivor := "survivor".toUTF8
  let survivorWrite ← Unsafe.Io.send thirdPeer survivor 0 survivor.size
  let survivorRead ← Unsafe.Io.recv thirdFd 64
  check "double-close rejection leaves the reused OS descriptor open"
    ((match survivorWrite with | .wrote n => n.toNat == survivor.size | _ => false) &&
      match survivorRead with
      | .bytes bytes => bytes.toList == survivor.toList
      | _ => false)

  Unsafe.Socket.closeFdRaw (fd32 oldPeer)
  Unsafe.Socket.closeFdRaw (fd32 newPeer)
  Unsafe.Socket.closeFdRaw (fd32 thirdFd)
  Unsafe.Socket.closeFdRaw (fd32 thirdPeer)
  closedNew.unsafeDestroy

-- D. RFC064-AUTH-MATRIX-001: every stable key effect rejects invalid authority
-- before reaching its native fd operation.
def testAuthorityErrorMatrix : IO Unit := do
  IO.println ""
  IO.println "=== D. RFC064-AUTH-MATRIX-001: stable effect authority matrix ==="
  let some loop <- EventLoop.create | do IO.println "epoll failed"; return

  -- These registry-only fixtures deliberately do not own corresponding OS fds.
  -- A native call would therefore produce a native error (or observable I/O),
  -- rather than the authority error asserted for every operation below.
  let (reg1, current) := loop.nds.ds.registry.allocate 700 50 .stream
  let reg1 := reg1.markActive current
  let (reg2, listener) := reg1.allocate 701 51 .listener
  let reg2 := reg2.markActive listener
  let (reg3, inactive) := reg2.allocate 702 52 .stream
  let reg3 := reg3.beginClosing inactive
  let checkedLoop := { loop with nds := { loop.nds with
    ds := { loop.nds.ds with registry := reg3 } } }

  let unknown : FdKey := { raw := 703, gen := 0 }
  let forged : FdKey := { current with gen := current.gen + 1000 }
  let negative : FdKey := { raw := -1, gen := 0 }
  let outOfRange : FdKey := { raw := 2147483648, gen := 0 }

  checkAuthorityCase "unknown key rejected" checkedLoop unknown .invalidKey
  checkAuthorityCase "forged generation rejected" checkedLoop forged .staleKey
  checkAuthorityCase "negative raw fd rejected" checkedLoop negative .invalidRawFd
  checkAuthorityCase "out-of-range raw fd rejected" checkedLoop outOfRange .invalidRawFd
  checkAuthorityCase "listener kind rejected" checkedLoop listener .wrongKind
  checkAuthorityCase "closing resource rejected" checkedLoop inactive .inactive

  checkedLoop.unsafeDestroy

-- E. RFC065-LEAN-BOUNDARY-001: stable requests reject before allocation/FFI.
def testRfc065LeanBoundary : IO Unit := do
  IO.println ""
  IO.println "=== E. RFC065-LEAN-BOUNDARY-001: stable request validation ==="
  let some loop <- EventLoop.create | do IO.println "epoll failed"; return
  let (reg, key) := loop.nds.ds.registry.allocate 700 50 .stream
  let reg := reg.markActive key
  let config := { loop.nds.ds.config with maxReadBytes := 4 }
  let checkedLoop := { loop with nds := { loop.nds with
    ds := { loop.nds.ds with registry := reg, config := config } } }
  let payload : ByteArray := ⟨#[1, 2, 3]⟩

  check "stable TCP send rejects invalid slice before native fd use" <|
    hasEffectError .invalidSlice (← checkedLoop.sendAck key payload 2 2)
  check "stable receive rejects configured-limit overflow before allocation" <|
    hasEffectError .limitExceeded (← checkedLoop.recvAck key 5)

  -- RFC065-RECV-REPRESENTABLE-001: an equally huge request and configured limit
  -- passes the application-limit comparison but must fail before Nat.toUSize,
  -- allocation, native I/O, or readiness acknowledgement.
  let hugeRequest := 2 ^ System.Platform.numBits + 5
  let pk : PendingKey := { fd := key, kind := .readable }
  let oe : OwnerEvent := { owner := 50, key := key, event := .readable }
  let pending := (checkedLoop.nds.ds.coalesce.step oe).1
  let hugeConfig := { checkedLoop.nds.ds.config with maxReadBytes := hugeRequest }
  let hugeLoop := { checkedLoop with nds := { checkedLoop.nds with
    ds := { checkedLoop.nds.ds with coalesce := pending, config := hugeConfig } } }
  check "non-representable receive starts with readiness pending"
    (hugeLoop.nds.ds.coalesce.pending pk)
  check "stable receive rejects non-representable request before allocation" <|
    hasEffectError .nativeLengthLimit (← hugeLoop.recvAck key hugeRequest)
  check "non-representable receive leaves readiness pending"
    (hugeLoop.nds.ds.coalesce.pending pk)

  checkedLoop.unsafeDestroy

def main : IO Unit := do
  IO.println "iotakt v0.13 integration test (explicit ack + recvAck/sendAck)"
  IO.println ""
  testCoalesceAck
  testRecvSendAck
  testLiveFdReuseAuthority
  testAuthorityErrorMatrix
  testRfc065LeanBoundary
  IO.println ""
  IO.println "v0.13 integration test complete"
