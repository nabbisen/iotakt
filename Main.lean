import Henret.Model
import Iotakt.Bridge
import Iotakt.Fake

/-!
# iotakt fake-poller demo

A fully deterministic run of the canonical RFC-008 scenarios through the
real Henret v0.6.0 bridge — no native code, no OS timing. It exercises
unknown/stale/no-interest drops, duplicate coalescing, fatal (EOF)
bypass, writable enable, timeout tick, interrupted wait, and the
complete Henret Mesa round-trip (park → inject → wake → re-receive),
using Henret's *actual* semantics: `inject` returns `.ok` (not `.woke`),
and the delivered message waits in the mailbox until the actor re-issues
`receive`.
-/

open Iotakt.Model Iotakt.Bridge Iotakt.Fake Henret

/-- Convert a fake poll outcome into the backend-neutral wait result the
bridge consumes (identical shape; the fake drives the same path). -/
def toWait : FakePollResult → PollWaitResult
  | .events e    => .events e
  | .timeout     => .timeout
  | .interrupted => .interrupted
  | .fatal e     => .fatal e

/-- Drive the whole fake script through the bridge, threading the driver
state and the Henret runtime, accumulating the trace. `now` advances on
each timeout so successive ticks are monotone. -/
def driveAll : Nat → DriverState → RuntimeState → FakePoller → Nat →
    DriverState × RuntimeState × List BridgeTrace
  | 0,      ds, rt, _, _   => (ds, rt, [])
  | fuel+1, ds, rt, p, now =>
      let (p', r)        := p.next
      let (ds1, rt1, t1) := runPoll ds rt now (toWait r)
      let now'           := match r with | .timeout => now + 1 | _ => now
      let (ds2, rt2, t2) := driveAll fuel ds1 rt1 p' now'
      (ds2, rt2, t1 ++ t2)

def traceStr : BridgeTrace → String
  | .injected o m        => s!"injected → actor {o} (id={m.id}, payload={m.payload})"
  | .coalesced k _       => s!"coalesced (fd {k.raw})"
  | .droppedUnknown raw  => s!"dropped unknown (fd {raw})"
  | .droppedStale raw    => s!"dropped stale (fd {raw})"
  | .droppedNoInterest raw => s!"dropped no-interest (fd {raw})"
  | .droppedClosed raw   => s!"dropped closed (fd {raw})"
  | .droppedNoMailbox o  => s!"dropped no-mailbox (actor {o})"
  | .ticked n            => s!"ticked → {n}"
  | .interruptedWait     => "interrupted wait (no mutation)"
  | .fatalWait _         => "fatal wait"

def injectedCount (tr : List BridgeTrace) : Nat :=
  (tr.filter (fun t => match t with | .injected _ _ => true | _ => false)).length

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

/-- A registry with actor 7 owning a readable stream on fd 10, active. -/
def baseSetup : DriverState × FdKey × RuntimeState :=
  let (reg0, key10) := Registry.empty.allocate 10 7 .stream
  let reg1 := (reg0.setInterests key10 InterestSet.readOnly).markActive key10
  let ds : DriverState := { registry := reg1, coalesce := CoalesceState.empty, clock := 0 }
  -- Henret: spawn actor 7 (creates its mailbox), schedule it, then have
  -- its task 0 block on an empty-mailbox receive so it parks as a waiter.
  let parked := (Henret.step (Henret.run RuntimeState.init [.spawn 7, .schedule]) (.receive 0)).1
  (ds, key10, parked)

def main : IO Unit := do
  let (ds, key10, parked) := baseSetup

  IO.println "scenario 1: readable delivered, parked actor woken, Mesa re-receive"
  let script1 := FakePoller.ofScript [.events [⟨10, .readable⟩]]
  let (_, rt1, tr1) := driveAll 1 ds parked script1 0
  for t in tr1 do IO.println s!"    trace: {traceStr t}"
  check "parked task 0 starts in waiting" (parked.taskState 0 == some .waiting)
  check "readable produced exactly one inject" (injectedCount tr1 == 1)
  check "inject delivered (.ok), head waiter woken to ready"
    (rt1.taskState 0 == some .ready)
  check "message waits in mailbox until re-receive (Mesa, no handoff)"
    ((rt1.mailboxes 7).map Mailbox.messages == some [⟨10, 1⟩])
  let s_sched := Henret.run rt1 [.schedule]
  let (_, r_recv) := Henret.step s_sched (.receive 0)
  check "re-issued receive consumes the readiness message"
    (r_recv matches .received ⟨10, 1⟩)

  IO.println "scenario 2: duplicate readiness is coalesced (flood bound)"
  let script2 := FakePoller.ofScript [.events [⟨10, .readable⟩], .events [⟨10, .readable⟩]]
  let (_, _, tr2) := driveAll 2 ds parked script2 0
  for t in tr2 do IO.println s!"    trace: {traceStr t}"
  check "two identical readiness events ⇒ exactly one inject" (injectedCount tr2 == 1)
  check "the duplicate was coalesced"
    (tr2.any (fun t => match t with | .coalesced _ _ => true | _ => false))

  IO.println "scenario 3: unknown raw fd is dropped"
  let script3 := FakePoller.ofScript [.events [⟨99, .readable⟩]]
  let (_, rt3, tr3) := driveAll 1 ds parked script3 0
  for t in tr3 do IO.println s!"    trace: {traceStr t}"
  check "unknown fd produced no inject" (injectedCount tr3 == 0)
  check "unknown fd left the runtime untouched" (rt3.taskState 0 == some .waiting)
  check "trace records droppedUnknown 99"
    (match tr3 with | [.droppedUnknown raw] => raw == 99 | _ => false)

  IO.println "scenario 4: stale generation is dropped (close ⇒ key no longer current)"
  let staleReg := ds.registry.close key10
  let staleRes := staleReg.translateKeyed key10 .readable
  check "translateKeyed on the closed key drops as stale"
    (staleRes matches .dropped _ .staleGeneration)
  -- and through the raw-event path, the closed fd no longer resolves at all
  let dsClosed : DriverState := { ds with registry := staleReg }
  let (_, _, tr4) := driveAll 1 dsClosed parked (FakePoller.ofScript [.events [⟨10, .readable⟩]]) 0
  check "post-close raw event injects nothing" (injectedCount tr4 == 0)

  IO.println "scenario 5: writable without interest is dropped; enabling it delivers"
  let writeNoInterest := ds.registry.translateOne ⟨10, .writable⟩  -- fd10 is read-only
  check "writable on read-only fd ⇒ no-interest drop"
    (writeNoInterest matches .dropped _ .noRegisteredInterest)
  let regW := ds.registry.setInterests key10 (InterestSet.readOnly.enableWrite)
  let writeEnabled := regW.translateOne ⟨10, .writable⟩
  check "writable after enableWrite ⇒ injectable"
    (writeEnabled matches .injectable _)

  IO.println "scenario 6: EOF (fatal) bypasses interest and is delivered"
  let (regE, key20) := ds.registry.allocate 20 7 .stream  -- no interest registered
  let _ := key20
  let eofRes := regE.translateOne ⟨20, .eof⟩
  check "EOF on a no-interest fd is still injectable (fatal bypass)"
    (eofRes matches .injectable _)

  IO.println "scenario 7: timeout ticks the clock; interrupted mutates nothing"
  let (_, rt7, tr7) := driveAll 1 ds parked (FakePoller.ofScript [.timeout]) 5
  check "timeout advanced Henret logical clock to 5" (rt7.now == 5)
  check "timeout trace records the tick" (match tr7 with | [.ticked n] => n == 5 | _ => false)
  let (ds8, rt8, tr8) := driveAll 1 ds parked (FakePoller.ofScript [.interrupted]) 0
  check "interrupted left the runtime unchanged" (rt8.now == parked.now)
  check "interrupted left the registry unchanged" (ds8.registry.nextGen == ds.registry.nextGen)
  check "interrupted trace is just interruptedWait" (match tr8 with | [.interruptedWait] => true | _ => false)

  IO.println "all demo scenarios executed"
