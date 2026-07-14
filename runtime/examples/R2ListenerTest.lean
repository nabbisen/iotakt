import IotaktRuntime.Loop

/-!
# RFC 070 address-aware listener regression

Exercises typed IPv4 construction, structured validation, duplicate rejection,
generation-safe listener publication, compatibility, and bind-again cleanup.
-/

open Iotakt.Model IotaktRuntime.Listener IotaktRuntime.Loop

private def ensure (label : String) (ok : Bool) : IO Unit :=
  if ok then
    IO.println s!"[PASS] {label}"
  else
    throw <| IO.userError s!"FAIL: {label}"

private def requireListener
    (result : Except ListenerError (EventLoop × ListenerKey)) :
    IO (EventLoop × ListenerKey) :=
  match result with
  | .ok value => pure value
  | .error e => throw <| IO.userError s!"listener setup failed: {repr e}"

private def isCurrentListener (loop : EventLoop) (key : ListenerKey) : Bool :=
  loop.nds.ds.registry.resolveCurrent key.raw == some key &&
    match loop.nds.ds.registry.lookup key with
    | some entry => entry.kind == .listener && entry.state.isLive
    | none => false

def main : IO Unit := do
  let specified := Ipv4Address.ofOctets 127 0 0 2
  ensure "IPv4 octets use host-byte-order representation"
    (specified.value == 0x7f000002)

  let some initial ← EventLoop.create
    | throw <| IO.userError "epoll create failed"

  let invalid ← initial.addListenerAt (.loopback 0)
  ensure "port zero is rejected as invalidEndpoint"
    (match invalid with | .error .invalidEndpoint => true | _ => false)

  let endpoint1 := BindEndpoint.loopback 49770
  let (loop1, key1) ← requireListener (← initial.addListenerAt endpoint1)
  ensure "loopback listener publishes current listener authority"
    (isCurrentListener loop1 key1)
  ensure "loopback endpoint metadata is keyed by ListenerKey"
    (loop1.listenerEndpoints.contains (key1, endpoint1))

  let genBeforeDuplicate := loop1.nds.ds.registry.nextGen
  let duplicate ← loop1.addListenerAt endpoint1
  ensure "exact duplicate endpoint is rejected before native publication"
    (match duplicate with | .error .duplicateEndpoint => true | _ => false)
  ensure "duplicate rejection leaves listener and generation state unchanged"
    (loop1.listeners.length == 1 && loop1.listenerEndpoints.length == 1 &&
      loop1.nds.ds.registry.nextGen == genBeforeDuplicate)

  let some conflictingLoop ← EventLoop.create
    | throw <| IO.userError "second epoll create failed"
  let conflict ← conflictingLoop.addListenerAt endpoint1
  ensure "kernel endpoint conflict returns typed addressInUse bind failure"
    (match conflict with
      | .error (.transitionError (.bindFailed .addressInUse)) => true
      | _ => false)
  ensure "bind failure publishes no listener or generation"
    (conflictingLoop.listeners.isEmpty && conflictingLoop.listenerEndpoints.isEmpty &&
      conflictingLoop.nds.ds.registry.nextGen == 0)
  conflictingLoop.destroy

  let endpoint2 := BindEndpoint.wildcard 49771
  let (loop2, key2) ← requireListener (← loop1.addListenerAt endpoint2)
  ensure "IPv4 wildcard listener succeeds" (isCurrentListener loop2 key2)

  let endpoint3 : BindEndpoint := { address := specified, port := 49772 }
  let (loop3, key3) ← requireListener (← loop2.addListenerAt endpoint3)
  ensure "specified local IPv4 listener succeeds" (isCurrentListener loop3 key3)
  ensure "three distinct endpoints are tracked"
    (loop3.listeners.length == 3 && loop3.listenerEndpoints.length == 3)

  let (loop4, compatibilityOk) ← loop3.addListener 49773
  ensure "port-only compatibility wrapper still binds loopback" compatibilityOk
  ensure "compatibility listener also records typed endpoint metadata"
    (loop4.listenerEndpoints.any (fun item => item.2 == .loopback 49773))

  let drained ← loop4.shutdown
  ensure "shutdown clears listener fd and endpoint metadata"
    (drained.listeners.isEmpty && drained.listenerEndpoints.isEmpty)

  let (rebound, _) ← requireListener (← drained.addListenerAt endpoint1)
  ensure "closed endpoint can bind again without stale duplicate state" true
  let rebound ← rebound.shutdown
  rebound.destroy

  IO.println "RFC 070 address-aware listener regression complete"
