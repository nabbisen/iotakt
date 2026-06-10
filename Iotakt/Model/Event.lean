import Iotakt.Model.Fd
import Iotakt.Model.Interest
/-!
# Iotakt.Model.Event

Normalized event vocabulary (RFC 004).

Readiness is a **hint**, not a guarantee: `readable` means a read *may*
make progress, not that bytes are waiting. After a readiness event the
subsequent syscall may still return `EAGAIN`/`EWOULDBLOCK`. The result
types in `Iotakt.Model.Result` make that explicit.

The vocabulary is kqueue-aware from day one even though Linux epoll
ships first: `eof`, `hangup`, and `error` are kept distinct because
their platform mappings differ (RFC 016).
-/

namespace Iotakt.Model

/-- The errno values iotakt distinguishes, with an escape hatch
(`other`) for platform codes it does not. `again` and `wouldBlock` are
kept separate because `EAGAIN` and `EWOULDBLOCK` may be equal on some
platforms and distinct on others; the model tolerates both. -/
inductive IoErrno where
  | again
  | wouldBlock
  | interrupted
  | badFd
  | connectionReset
  | brokenPipe
  | notConnected
  | invalid
  | permissionDenied
  | addressInUse
  | addressNotAvailable
  | tooManyFiles
  | inProgress   -- EINPROGRESS: non-blocking connect in progress (RFC 039)
  | other (code : Int)
  deriving DecidableEq, Repr, Inhabited

namespace IoErrno

/-- Errnos that represent the normal "no progress right now" outcome of
a non-blocking syscall, never a fatal error. -/
def isWouldBlock : IoErrno → Bool
  | .again | .wouldBlock => true
  | _ => false

@[simp] theorem isWouldBlock_again : isWouldBlock .again = true := rfl
@[simp] theorem isWouldBlock_wouldBlock : isWouldBlock .wouldBlock = true := rfl

end IoErrno

/-- A normalized, backend-neutral readiness event. Backend flags are
mapped into this vocabulary at the native boundary; no `EPOLL*` /
`EVFILT_*` constant ever reaches the bridge or jemmet. -/
inductive IoEvent where
  /-- Reading may make progress (a hint). -/
  | readable
  /-- Writing may make progress (a hint). -/
  | writable
  /-- Peer end-of-stream observed. Distinct from `error`. -/
  | eof
  /-- Socket/peer hangup observed. Distinct from `eof` because platform
      mappings differ. -/
  | hangup
  /-- A backend/native error observed, carrying normalized errno detail
      when available. -/
  | error (errno : Option IoErrno)
  deriving DecidableEq, Repr, Inhabited

namespace IoEvent

/-- A *fatal* event (hangup/error/eof) signals a terminal or
near-terminal socket condition. Fatal events follow a delivery policy
that bypasses ordinary interest checks (RFC 005), because dropping a
hangup because "no interest was registered" would strand the resource. -/
def isFatal : IoEvent → Bool
  | .eof | .hangup => true
  | .error _ => true
  | _ => false

/-- A non-fatal readiness hint (`readable`/`writable`) — the events
that are gated by registered interest and subject to coalescing. -/
def isReadiness : IoEvent → Bool
  | .readable | .writable => true
  | _ => false

/-- The interest that must be registered for a non-fatal readiness
event to be delivered. `none` for fatal events. -/
def requiredInterest : IoEvent → Option Interest
  | .readable => some .readable
  | .writable => some .writable
  | _ => Option.none

@[simp] theorem isFatal_eof : isFatal .eof = true := rfl
@[simp] theorem isFatal_hangup : isFatal .hangup = true := rfl
@[simp] theorem isFatal_error (e : Option IoErrno) : isFatal (.error e) = true := rfl
@[simp] theorem isFatal_readable : isFatal .readable = false := rfl
@[simp] theorem isFatal_writable : isFatal .writable = false := rfl
@[simp] theorem isReadiness_readable : isReadiness .readable = true := rfl
@[simp] theorem isReadiness_writable : isReadiness .writable = true := rfl

end IoEvent

/-- A raw event as a backend poller reports it: a raw fd plus an opaque
backend flag mask. Backend-specific; must not reach the pure model
beyond its normalization module. -/
structure NativeEvent where
  rawFd : RawFd
  mask  : UInt32
  data  : Int := 0
  deriving Repr, Inhabited

/-- The output of native normalization and the *input* to translation:
a raw fd already paired with a backend-neutral `IoEvent`. Generation
resolution and ownership are still unknown at this point. -/
structure NormalizedRawEvent where
  rawFd : RawFd
  event : IoEvent
  deriving Repr, Inhabited

end Iotakt.Model
