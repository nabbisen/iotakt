import IotaktRuntime.Loop
import IotaktRuntime.Native

/-!
# RFC 070 address-aware listener regression

Exercises typed IPv4 construction, structured validation, duplicate rejection,
generation-safe listener publication, compatibility, and bind-again cleanup.
-/

open Iotakt.Model IotaktRuntime.Driver IotaktRuntime.Listener IotaktRuntime.Loop
  IotaktRuntime.Native

private inductive ListenerMode where
  | plaintext
  | tls (configGeneration : Nat)
  deriving DecidableEq

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

private def isCurrentStream (loop : EventLoop) (key : FdKey) : Bool :=
  loop.nds.ds.registry.resolveCurrent key.raw == some key &&
    match loop.nds.ds.registry.lookup key with
    | some entry => entry.kind == .stream && entry.state.isLive
    | none => false

private def connectClient (address : Ipv4Address) (port : UInt16) : IO Int := do
  let fd ← Socket.socketTcpRaw 1
  if fd < 0 then throw <| IO.userError "client socket create failed"
  match ← Socket.connectIPv4 fd address.value port with
  | .error e =>
      Socket.closeFdRaw (Int32.mk fd.toNat.toUInt32)
      throw <| IO.userError s!"client connect failed: {repr e}"
  | .connected | .inProgress => pure fd

def main : IO Unit := do
  let specified := Ipv4Address.ofOctets 127 0 0 2
  ensure "IPv4 octets use host-byte-order representation"
    (specified.value == 0x7f000002)

  let some initial ← EventLoop.create
    | throw <| IO.userError "epoll create failed"
  ensure "stable EventLoop.create selects returned-event authority"
    (initial.deliveryMode == .returned)

  let invalid ← initial.addListenerAt (.loopback 0)
  ensure "port zero is rejected as invalidEndpoint"
    (match invalid with | .error .invalidEndpoint => true | _ => false)

  let endpoint1 := BindEndpoint.loopback 49770
  let (loop1, key1) ← requireListener (← initial.addListenerAt endpoint1)
  ensure "loopback listener publishes current listener authority"
    (isCurrentListener loop1 key1)
  ensure "loopback endpoint metadata is keyed by ListenerKey"
    (loop1.listenerEndpoints.contains (key1, endpoint1))

  -- FI-ACC-001: accepted-fd registration is the native commit point. Force it
  -- to fail and verify that the candidate is closed once without publishing
  -- tentative generation, actor-id, registry, runtime, or consumer authority.
  let closeCount ← IO.mkRef 0
  let failedRegisterOps : AcceptOps := {
    accept := fun _ => pure (.accepted 123456 ByteArray.empty)
    register := fun _ _ _ => pure (-5)
    close := fun _ => closeCount.modify (· + 1)
  }
  let (failedNds, failedRt, failedAccept) ←
    acceptOneWith failedRegisterOps loop1.nds loop1.rt loop1.ph key1.raw
  ensure "FI-ACC-001 returns typed accepted-register failure"
    (match failedAccept with
      | .error (.registerFailed (.other 5)) => true
      | _ => false)
  ensure "FI-ACC-001 closes the unregistered candidate exactly once"
    ((← closeCount.get) == 1)
  ensure "FI-ACC-001 publishes no registry, generation, or actor authority"
    (failedNds.ds.registry.nextGen == loop1.nds.ds.registry.nextGen &&
      failedNds.ds.registry.resolveCurrent 123456 == none &&
      failedNds.nextActorId == loop1.nds.nextActorId)
  ensure "FI-ACC-001 leaves Henret runtime and consumer bookkeeping unchanged"
    (failedRt.nextId == loop1.rt.nextId &&
      failedRt.mailboxes loop1.nds.nextActorId == loop1.rt.mailboxes loop1.nds.nextActorId &&
      loop1.taskByKey.isEmpty)

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
  let runtimeTaskIdBeforeAccept := loop3.rt.nextId
  let firstConnectionActor := loop3.nds.nextActorId

  let client1 ← connectClient .loopback endpoint1.port
  let client2 ← connectClient .loopback endpoint2.port
  let client3 ← connectClient specified endpoint3.port
  IO.sleep 50
  let fatalWaitOps : WaitOps := { wait := fun _ _ _ => pure (-9, ByteArray.empty) }
  let fatalWait ← EventLoop.runStepWith fatalWaitOps loop3 100
  ensure "fatal poll failure is returned as typed LoopError"
    (match fatalWait with | .error (.waitFailed .badFd) => true | _ => false)
  ensure "fatal poll failure publishes no connection authority"
    (loop3.connectionCount == 0 && loop3.taskByKey.isEmpty &&
      loop3.nds.nextActorId == firstConnectionActor)
  let (loop3, events) ← LoopError.orThrow (← loop3.runStep 100)
  let accepted := events.filterMap fun event => match event with
    | .newConnection listener connection => some (listener, connection)
    | _ => none
  ensure "three pending clients produce three accepted events" (accepted.length == 3)
  ensure "each accepted event identifies its exact listener"
    (accepted.any (fun item => item.1 == key1) &&
      accepted.any (fun item => item.1 == key2) &&
      accepted.any (fun item => item.1 == key3))
  ensure "accepted connection keys carry current stream authority"
    (accepted.all (fun item => isCurrentStream loop3 item.2))
  ensure "returned mode accepts without allocating Henret connection tasks"
    (loop3.rt.nextId == runtimeTaskIdBeforeAccept && loop3.taskByKey.isEmpty)
  ensure "returned mode creates no mailbox for the accepted actor range"
    ((List.range accepted.length).all fun offset =>
      (loop3.rt.mailboxes (firstConnectionActor + offset)).isNone)
  ensure "returned mode tracks bounded connection authority without tasks"
    (loop3.connectionCount == accepted.length)
  ensure "listener readiness does not occupy a connection pending slot"
    (!loop3.nds.ds.coalesce.pending { fd := key1, kind := .readable })
  ensure "listener and connection identities are distinct roles"
    (accepted.all (fun item => item.1 != item.2))
  let modeFor := fun listener =>
    if listener == key1 then ListenerMode.plaintext
    else if listener == key2 then ListenerMode.tls 1
    else ListenerMode.tls 2
  let modes := accepted.map (fun item => modeFor item.1)
  ensure "listener identity selects plaintext/TLS configuration before I/O"
    (modes.contains .plaintext && modes.contains (.tls 1) && modes.contains (.tls 2))
  let busyPayload := "busy".toUTF8
  let _ ← Io.send client1 busyPayload 0 busyPayload.size
  let mut busyLoop := loop3
  let mut sawBusyReadiness := false
  for _ in List.range 5 do
    let (nextLoop, busyEvents) ← LoopError.orThrow (← busyLoop.runStep 100)
    busyLoop := nextLoop
    for event in busyEvents do
      match event with
      | .dataReady key ioEvent =>
          sawBusyReadiness := true
          busyLoop := busyLoop.ackReady key ioEvent
      | _ => pure ()
  ensure "busy returned-mode connection remains caller-visible" sawBusyReadiness
  ensure "busy returned-mode steps retain zero connection task/mailbox growth"
    (busyLoop.rt.nextId == runtimeTaskIdBeforeAccept && busyLoop.taskByKey.isEmpty &&
      (List.range accepted.length).all fun offset =>
        (busyLoop.rt.mailboxes (firstConnectionActor + offset)).isNone)
  let loop3 := busyLoop
  Socket.closeFdRaw (Int32.mk client1.toNat.toUInt32)
  Socket.closeFdRaw (Int32.mk client2.toNat.toUInt32)
  Socket.closeFdRaw (Int32.mk client3.toNat.toUInt32)

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

  let some mailboxLoop ← EventLoop.createMailbox
    | throw <| IO.userError "mailbox epoll create failed"
  ensure "mailbox authority requires explicit loop construction"
    (mailboxLoop.deliveryMode == .mailbox)
  let (mailboxLoop, mailboxBound) ← mailboxLoop.addListener 49774
  ensure "explicit mailbox-mode listener binds" mailboxBound
  let mailboxClient ← connectClient .loopback 49774
  IO.sleep 50
  let (mailboxLoop, mailboxAcceptEvents) ← LoopError.orThrow (← mailboxLoop.runStep 100)
  let some mailboxConnection := mailboxAcceptEvents.findSome? fun event =>
      match event with | .newConnection _ connection => some connection | _ => none
    | throw <| IO.userError "mailbox-mode accept missing"
  let mailboxPayload := "mailbox".toUTF8
  let _ ← Io.send mailboxClient mailboxPayload 0 mailboxPayload.size
  let (mailboxLoop, mailboxReadyEvents) ← LoopError.orThrow (← mailboxLoop.runStep 100)
  let mailboxOwner := (mailboxLoop.nds.ds.registry.lookup mailboxConnection).map (·.owner)
  let mailboxHasReadiness := match mailboxOwner with
    | some owner => (mailboxLoop.rt.mailboxes owner).any (fun mb => !mb.messages.isEmpty)
    | none => false
  ensure "mailbox mode injects readiness without returning duplicate dataReady"
    (mailboxHasReadiness && mailboxLoop.taskByKey.length == 1 &&
      !mailboxReadyEvents.any (fun event => match event with | .dataReady _ _ => true | _ => false))
  Socket.closeFdRaw (Int32.mk mailboxClient.toNat.toUInt32)
  let mailboxLoop ← mailboxLoop.shutdown
  mailboxLoop.destroy

  IO.println "RFC 070 address-aware listener regression complete"
