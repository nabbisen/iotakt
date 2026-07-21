import Henret.Model
import IotaktRuntime.Bridge
import IotaktRuntime.Native

/-!
# iotakt echo test — v0.1 integration checkpoint

This test exercises the **complete iotakt stack end-to-end**:

```text
socketpair(fd0, fd1)         ← connected Unix-domain stream pair
epoll register fd0 (read)    ← native poller
registry.allocate fd0 → key  ← pure model
Henret: spawn actor 1        ← mailbox created
write bytes → fd1            ← simulates remote peer sending data
epoll_wait → readable fd0    ← OS event
Unsafe.Epoll.parseEvents            ← NormalizedRawEvent
registry.translateOne        ← injectable OwnerEvent
CoalesceState.step           ← deliver (not duplicate)
Bridge.deliverOne            ← guarded inject (mailbox guard passes)
Henret: inject → .ok         ← confirmed by inject_ok_of_mailbox theorem
Henret: schedule → run       ← actor runs
IotaktRuntime.Native.Unsafe.Io.recv fd0    ← read the bytes
send echo → fd0              ← write back
recv from fd1                ← verify echo arrived
```

The test passes iff the bytes survive the full round-trip through the
real kernel, the pure model, and the Henret actor scheduler.
-/

open Iotakt.Model IotaktRuntime.Bridge IotaktRuntime.Native Henret

/-- Helper: Int → Int32 for raw FFI layer. -/
private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

def main : IO Unit := do
  IO.println "echo integration test (full driver round-trip)"

  -- ── 0. Create epoll ────────────────────────────────────────────────────
  let epfd ← Unsafe.Epoll.create
  check "epoll_create" (epfd >= 0)
  if epfd < 0 then return

  -- ── 1. Connected socket pair ──────────────────────────────────────────
  let (fd0, fd1) ← Unsafe.Socket.socketpairRaw
  check "socketpair" (fd0 >= 0 && fd1 >= 0)
  if fd0 < 0 then do Unsafe.Epoll.close (fd32 epfd); return

  -- ── 2. Build iotakt registry ─────────────────────────────────────────
  -- fd0 = the "server" side; actor 1 owns it
  let (reg0, key) := Registry.empty.allocate fd0 1 .stream
  let reg1 := reg0.setInterests key InterestSet.readOnly |>.markActive key
  let ds : DriverState := { registry := reg1, coalesce := CoalesceState.empty, clock := 0 }

  -- ── 3. Build Henret runtime (actor 1 spawned, parked on receive) ─────
  let parked := (Henret.step
    (Henret.run RuntimeState.init [.spawn 1, .schedule])
    (.receive 0)).1  -- task 0 owned by actor 1, parked waiting

  check "actor 1 has a mailbox" (parked.mailboxes 1 != none)
  check "task 0 starts in waiting state" (parked.taskState 0 == some .waiting)

  -- ── 4. Register fd0 with epoll ───────────────────────────────────────
  let reg_r ← Unsafe.Epoll.register (fd32 epfd) (fd32 fd0)
    (Unsafe.Epoll.interestFlags InterestSet.readOnly)
  check "epoll register fd0" (reg_r == 0)

  -- ── 5. Write 8 known bytes to fd1 (peer side) ────────────────────────
  let msg : ByteArray := ⟨#[0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0x0a, 0x00]⟩ -- "hello!\n\0"
  let wr ← Unsafe.Io.send fd1 msg 0 msg.size
  check "write 8 bytes to fd1" (match wr with | .wrote n => n == 8 | _ => false)

  -- ── 6. epoll_wait (up to 100ms timeout) ─────────────────────────────
  let (waitStatus, evtBytes) ← Unsafe.Epoll.wait (fd32 epfd) 64 100
  check "epoll_wait reports event on fd0" (waitStatus > 0)
  if waitStatus <= 0 then do
    IO.println "  [SKIP] no event arrived, skipping read path"
    Unsafe.Socket.closeFdRaw (fd32 fd0); Unsafe.Socket.closeFdRaw (fd32 fd1)
    Unsafe.Epoll.close (fd32 epfd); return

  -- ── 7. Parse epoll events → NormalizedRawEvent list ──────────────────
  let rawEvts := Unsafe.Epoll.parseEvents evtBytes
  check "at least one normalized event from epoll" (!rawEvts.isEmpty)

  -- ── 8. Translate through pure model ──────────────────────────────────
  let results := ds.registry.translateMany rawEvts
  let injectables := results.filter (fun r => match r with | .injectable _ => true | _ => false)
  check "translated event is injectable" (!injectables.isEmpty)

  -- ── 9. Coalesce + guarded inject into Henret ─────────────────────────
  -- processEvents handles translate + coalesce + inject in one step
  let (_, rt1, trace1) := processEvents ds parked rawEvts
  check "bridge trace contains an injected message"
    (trace1.any fun t => match t with | .injected _ _ => true | _ => false)
  check "inject returned .ok (inject_ok_of_mailbox)" (rt1.taskState 0 == some .ready)

  -- ── 10. Message sits in mailbox (Mesa: no immediate handoff) ─────────
  -- Henret v0.7.0 (RFC 033): Envelope{occurrence, source, body}
  -- inject: occurrence = nextMsgId (= 0 at this point), source = none.
  check "message waits in actor 1's mailbox until re-receive"
    ((rt1.mailboxes 1).map Mailbox.messages == some [⟨0, none, ⟨fd0.toNat, 1⟩⟩])

  -- ── 11. Schedule + re-receive (Mesa round-trip) ──────────────────────
  let rt2 := Henret.run rt1 [.schedule]
  let (_, r_recv) := Henret.step rt2 (.receive 0)
  check "actor re-receive consumes the readiness message"
    (r_recv matches .received ⟨_, _, _⟩)

  -- ── 12. Now actor would call recv; we simulate it ─────────────────────
  let readResult ← Unsafe.Io.recv fd0 ds.config.maxReadBytes
  check "recv on fd0 returns the 8 bytes" (match readResult with
    | .bytes ba => ba.data == msg.data
    | _ => false)

  -- ── 13. Echo: send bytes back on fd0, read from fd1 ───────────────────
  let echoResult ← match readResult with
    | .bytes ba => Unsafe.Io.send fd0 ba 0 ba.size
    | _ => pure (.error (.other 0))
  check "echo send succeeds"
    (match echoResult with | .wrote n => n == 8 | _ => false)

  let echoRecv ← Unsafe.Io.recv fd1 256
  check "echo bytes arrive on fd1"
    (match echoRecv with | .bytes ba => ba.data == msg.data | _ => false)

  -- ── 14. DriverConfig limits are present ───────────────────────────────
  check "DriverConfig.maxReadBytes default is 16384" (ds.config.maxReadBytes == 16384)
  check "DriverConfig.maxEventsPerPoll default is 1024" (ds.config.maxEventsPerPoll == 1024)
  check "DriverConfig.maxAcceptBurst default is 64" (ds.config.maxAcceptBurst == 64)

  -- ── Cleanup ───────────────────────────────────────────────────────────
  Unsafe.Socket.closeFdRaw (fd32 fd0)
  Unsafe.Socket.closeFdRaw (fd32 fd1)
  Unsafe.Epoll.close (fd32 epfd)

  IO.println "echo integration test complete"
