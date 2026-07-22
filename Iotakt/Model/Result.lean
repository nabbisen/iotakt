import Iotakt.Model.Fd
import Iotakt.Model.Event
/-!
# Iotakt.Model.Result

Read/write result types and the actor-facing message (RFC 004, RFC 010).

These types exist to make the non-guarantee of readiness impossible to
ignore: every read can return `wouldBlock`, every write can be partial.
A caller that pattern-matches a `ReadResult` is forced to consider the
`wouldBlock`/`eof`/`interrupted`/`error` cases.
-/

namespace Iotakt.Model

/-- The outcome of one non-blocking `recv`. `wouldBlock` is a normal
outcome (the socket reported readable but drained), not a failure. -/
inductive ReadResult where
  | bytes (data : ByteArray)
  | wouldBlock
  | eof
  | interrupted
  | error (errno : IoErrno)
  deriving Inhabited

/-- The outcome of one non-blocking `send`. `wrote n` may report fewer
bytes than were offered — a partial write is success, and the caller
above iotakt retains the unsent suffix (RFC 010). -/
inductive WriteResult where
  | wrote (n : USize)
  | wouldBlock
  | interrupted
  | closed
  /-- The requested `(offset, len)` is outside the application buffer. -/
  | invalidSlice
  /-- The requested length cannot be represented safely by the native syscall. -/
  | nativeLengthLimit
  | error (errno : IoErrno)
  deriving Inhabited

/-- Why a resource is being closed, attached to a `closed` message. -/
inductive CloseReason where
  | peerEof
  | hangup
  | localClose
  | error (errno : IoErrno)
  deriving DecidableEq, Repr, Inhabited

/-- The protocol-neutral message iotakt delivers to an owning actor.
Carries an `FdKey` (never a raw fd) and a normalized event. It must not
contain HTTP-specific or other protocol state — that belongs to jemmet. -/
inductive IoMessage where
  | ready  (key : FdKey) (event : IoEvent)
  | closed (key : FdKey) (reason : CloseReason)
  deriving Repr, Inhabited

namespace IoMessage

/-- The `FdKey` an `IoMessage` concerns. -/
def key : IoMessage → FdKey
  | .ready k _  => k
  | .closed k _ => k

end IoMessage

end Iotakt.Model
