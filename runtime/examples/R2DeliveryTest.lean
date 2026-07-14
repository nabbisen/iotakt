import IotaktRuntime.Bridge

/-!
# RFC 066 returned-event authority regression

Exercises the deterministic bridge path used by `EventLoop.runStep`. Only the
post-translation, post-coalescing result is returned, and missing Henret mailboxes
cannot consume a pending slot.
-/

open Iotakt.Model IotaktRuntime.Bridge Henret

private def ensure (label : String) (ok : Bool) : IO Unit :=
  if ok then
    IO.println s!"[PASS] {label}"
  else
    throw <| IO.userError s!"FAIL: {label}"

private def isSingleReadable (key : FdKey) : List OwnerEvent → Bool
  | [oe] => oe.key == key && oe.owner == 7 && oe.event == .readable
  | _ => false

private def returnedCount (traces : List BridgeTrace) : Nat :=
  traces.countP fun trace => match trace with
    | .returned _ _ => true
    | _ => false

private def coalescedCount (traces : List BridgeTrace) : Nat :=
  traces.countP fun trace => match trace with
    | .coalesced _ _ => true
    | _ => false

def main : IO Unit := do
  let (reg0, key) := Registry.empty.allocate 42 7 .stream
  let reg1 := reg0.setInterests key InterestSet.readOnly |>.markActive key
  let ds0 : DriverState := {
    registry := reg1
    coalesce := CoalesceState.empty
    clock := 0
  }
  let readable : NormalizedRawEvent := { rawFd := 42, event := .readable }
  let unknown : NormalizedRawEvent := { rawFd := 999, event := .readable }

  let (ds1, delivered1, traces1) :=
    processEventsReturned ds0 [readable, unknown, readable]
  ensure "only the translated first readiness is returned"
    (isSingleReadable key delivered1)
  ensure "one returned trace is recorded" (returnedCount traces1 == 1)
  ensure "the duplicate readiness is coalesced" (coalescedCount traces1 == 1)
  ensure "the delivered slot is pending"
    (ds1.coalesce.pending { fd := key, kind := .readable })

  let ds2 := { ds1 with
    coalesce := ds1.coalesce.ack { fd := key, kind := .readable } }
  let (_, delivered2, _) := processEventsReturned ds2 [readable]
  ensure "ack permits a later readiness delivery" (isSingleReadable key delivered2)

  let oe : OwnerEvent := { owner := 7, key := key, event := .readable }
  let (dsNoMailbox, rtNoMailbox, _) := deliverOne ds0 RuntimeState.init oe
  ensure "missing mailbox leaves the pending slot clear"
    (!dsNoMailbox.coalesce.pending { fd := key, kind := .readable })
  ensure "missing mailbox remains absent" ((rtNoMailbox.mailboxes 7).isNone)

  let (regNoInterest0, noInterestKey) := Registry.empty.allocate 43 8 .stream
  let regNoInterest := regNoInterest0.markActive noInterestKey
  let dsNoInterest : DriverState := { ds0 with registry := regNoInterest }
  let (_, deliveredNoInterest, _) := processEventsReturned dsNoInterest
    [{ rawFd := 43, event := .writable }]
  ensure "no-interest readiness is not returned" deliveredNoInterest.isEmpty

  IO.println "RFC 066 returned-event authority regression complete"
