import IotaktRuntime.Loop
import IotaktRuntime.WriteBuffer

/-!
# IotaktRuntime.Actor

A callback-based `ConnectionActor` abstraction for v0.5 (RFC 035 prep).

Each accepted connection can be wrapped in a `ConnectionActor` that
encapsulates:
- Its per-connection mutable state (via `IO.Ref`).
- Four event callbacks: `onReadable`, `onWritable`, `onEof`, `onError`.
- An `ActorAction` return value that drives the EventLoop's interest
  management and connection lifetime.

## Design rationale

The `EventLoop` delivers raw `LoopEvent` values — the actor layer above
it handles protocol logic. `ConnectionActor` makes that handler layer
explicit and uniform: each connection is an actor with a well-defined
lifecycle rather than ad-hoc `match ev` branches.

## Actor lifecycle

```
accepted
  → ACTIVE (onReadable / onWritable callbacks run)
    → ActorAction.enableWrite  → arm write interest
    → ActorAction.disableWrite → disarm write interest
    → ActorAction.close        → deregister + close fd
    → ActorAction.continue     → no change
  → CLOSED (EventLoop.closeConnection called)
```

## Usage pattern

```lean
-- Build an actor with IO.Ref state
let ref ← IO.mkRef MyState.initial
let actor : ConnectionActor := {
  key := key,
  onReadable := do
    let bytes ← Io.recv key.raw 4096
    -- handle bytes, update ref
    return .continue,
  onWritable := do
    let (wb, done) ← (← ref.get).wbuf.flush key.raw
    ref.modify (·.setWb wb)
    return if done then .disableWrite else .continue,
  onEof := do
    return .close,
  onError := fun _ => return .close
}
```
-/

namespace IotaktRuntime.Actor

open IotaktRuntime.Loop Iotakt.Model IotaktRuntime.Native IotaktRuntime.WriteBuffer

/-- What a `ConnectionActor` wants to do after handling an event. -/
inductive ActorAction where
  /-- Keep running; no interest-set change. -/
  | continue
  /-- Arm write interest: actor has bytes to send. -/
  | enableWrite
  /-- Disarm write interest: output buffer drained. -/
  | disableWrite
  /-- Close the connection immediately. -/
  | close
  deriving Repr, Inhabited

/-- A per-connection actor. Callbacks are closures over `IO.Ref` state;
the actor struct itself is plain data (no generic type parameter). -/
structure ConnectionActor where
  /-- The fd key this actor owns. -/
  key        : FdKey
  /-- Called when the fd is readable. -/
  onReadable : IO ActorAction
  /-- Called when the fd is writable. -/
  onWritable : IO ActorAction
  /-- Called when the peer closed the write side (EOF). -/
  onEof      : IO ActorAction
  /-- Called on a hard I/O error. -/
  onError    : IoErrno → IO ActorAction

namespace ConnectionActor

/-- Dispatch one `IoEvent` to the actor and return the requested action. -/
def dispatch (actor : ConnectionActor) (ev : IoEvent) : IO ActorAction :=
  match ev with
  | .readable        => actor.onReadable
  | .writable        => actor.onWritable
  | .eof | .hangup   => actor.onEof
  | .error (some e)  => actor.onError e
  | .error none      => actor.onError .badFd

/-- Build a simple echo actor over a socketpair/stream fd. -/
def mkEcho (key : FdKey) (maxRead : Nat := 4096) : ConnectionActor := {
  key
  onReadable := do
    match ← Io.recv key.raw maxRead with
    | .bytes ba =>
        let _ ← Io.send key.raw ba 0 ba.size
        return .continue
    | .eof        => return .close
    | .wouldBlock => return .continue
    | _           => return .close
  onWritable := return .disableWrite  -- echo uses synchronous send
  onEof      := return .close
  onError    := fun _ => return .close
}

/-- Build an actor that accumulates read bytes into a `Ref` buffer. -/
def mkBuffered (key : FdKey) (ref : IO.Ref ByteArray)
    (maxRead : Nat := 4096) : ConnectionActor := {
  key
  onReadable := do
    match ← Io.recv key.raw maxRead with
    | .bytes ba =>
        ref.modify fun buf =>
          let combined := ByteArray.mkEmpty (buf.size + ba.size)
          let combined := ByteArray.copySlice buf 0 combined 0 buf.size
          ByteArray.copySlice ba 0 combined buf.size ba.size
        return .continue
    | .eof        => return .close
    | .wouldBlock => return .continue
    | _           => return .close
  onWritable := return .disableWrite
  onEof      := return .close
  onError    := fun _ => return .close
}

end ConnectionActor

/-- A registry of active `ConnectionActor`s, keyed by `FdKey`. -/
structure ActorRegistry where
  actors : List ConnectionActor := []

namespace ActorRegistry

def empty : ActorRegistry := {}

/-- Register a new actor. -/
def register (reg : ActorRegistry) (actor : ConnectionActor) : ActorRegistry :=
  { reg with actors := actor :: reg.actors }

/-- Look up the actor for a key. -/
def lookup (reg : ActorRegistry) (key : FdKey) : Option ConnectionActor :=
  reg.actors.find? (·.key == key)

/-- Remove the actor for a key. -/
def remove (reg : ActorRegistry) (key : FdKey) : ActorRegistry :=
  { reg with actors := reg.actors.filter (·.key != key) }

/-- Run one EventLoop step, dispatching `dataReady` events to registered
actors. Returns the updated loop, updated registry, the list of
`newConnection` events (unhandled by actors), and a list of `FdKey`s that
requested close. -/
def runStep
    (loop : EventLoop)
    (reg  : ActorRegistry)
    (timeoutMs : Int := -1) :
    IO (EventLoop × ActorRegistry × List (FdKey × Int) × List FdKey) := do
  let (loop1, events) ← loop.runStep timeoutMs
  let mut loop := loop1
  let mut reg  := reg
  let mut newConns  : List (FdKey × Int) := []
  let mut toClose   : List FdKey         := []

  for ev in events do
    match ev with
    | .newConnection key rawFd =>
        newConns := newConns ++ [(key, rawFd)]
    | .dataReady key event =>
        match reg.lookup key with
        | none => pure ()
        | some actor =>
            let action ← actor.dispatch event
            match action with
            | .continue     => pure ()
            | .enableWrite  => loop := ← Loop.EffectError.orThrow (← loop.enableWrite key)
            | .disableWrite => loop := ← Loop.EffectError.orThrow (← loop.disableWrite key)
            | .close        =>
                toClose := toClose ++ [key]
                reg := reg.remove key
    | .tick _ => pure ()

  return (loop, reg, newConns, toClose)

end ActorRegistry

end IotaktRuntime.Actor
