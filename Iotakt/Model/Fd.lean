/-!
# Iotakt.Model.Fd

File-descriptor identity (RFC 002).

The central decision of iotakt: a raw OS file descriptor integer is
**never** a stable identity. The OS reuses fd integers aggressively, so
a stale readiness event for a closed connection could otherwise be
delivered to a freshly accepted connection that happens to have been
given the same raw fd. iotakt pairs the raw fd with a monotone
generation — `FdKey (raw, gen)` — and attaches ownership to the
`FdKey`, never to the raw fd alone.
-/

namespace Iotakt.Model

/-- The integer file descriptor returned by the host OS. A handle, not
an identity. Modeled as `Int` because POSIX fds are `int` and error
returns are negative. -/
abbrev RawFd := Int

/-- Monotone generation token. Allocated by the iotakt model, never by
the native layer. A reused raw fd always receives a strictly newer
generation. -/
abbrev FdGeneration := Nat

/-- iotakt's view of a Henret actor identifier. Kept as a plain `Nat`
so the pure model and proofs build without a Henret dependency (RFC
001); the bridge layer maps this to `Henret.ActorId` (also `Nat`),
which is the identity adapter. -/
abbrev ActorId := Nat

/-- Stable iotakt resource identity: a raw fd paired with the
generation current at the time the resource was registered. Ownership
and event delivery key on `FdKey`. -/
structure FdKey where
  raw : RawFd
  gen : FdGeneration
  deriving DecidableEq, Repr, Inhabited, Hashable

/-- The two resource kinds iotakt tracks. iotakt models ownership and
lifecycle, not the TCP state machine, so this is deliberately tiny. -/
inductive ResourceKind where
  | listener   -- TCP listening socket (accepts incoming connections)
  | stream     -- TCP accepted connection or non-blocking outbound connect
  | datagram   -- UDP socket (connectionless; RFC 036)
  deriving DecidableEq, Repr, Inhabited

/-- Lifecycle state of a resource (RFC 003). Models ownership and
readiness lifecycle only; TCP states such as `TIME_WAIT` are out of
scope and are not represented here. `closed` is terminal. -/
inductive ResourceState where
  | allocated
  | configured
  | listening
  | registered
  | active
  | closing
  | closed
  deriving DecidableEq, Repr, Inhabited

namespace ResourceState

/-- `closed` is the single terminal lifecycle state. -/
def isTerminal : ResourceState → Bool
  | .closed => true
  | _ => false

/-- States in which a resource may still receive modeled readiness:
everything that is neither closing nor closed. -/
def isLive : ResourceState → Bool
  | .closing => false
  | .closed  => false
  | _        => true

@[simp] theorem isTerminal_closed : isTerminal .closed = true := rfl
@[simp] theorem isLive_closed : isLive .closed = false := rfl
@[simp] theorem isLive_closing : isLive .closing = false := rfl

end ResourceState

end Iotakt.Model
