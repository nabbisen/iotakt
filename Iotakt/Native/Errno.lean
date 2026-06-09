import Iotakt.Model.Event

/-!
# Iotakt.Native.Errno

Platform errno constants (Linux x86-64) and helper to classify a
raw -errno return into an `IoErrno`. Numbers match the Lean model's
`IoErrno` constructors but are defined once here to avoid magic
literals in the recv/send wrappers.
-/

namespace Iotakt.Native

/-- Classify a raw errno value (positive) into a model `IoErrno`. -/
def classifyErrno : Int → Iotakt.Model.IoErrno
  | 11  => .again           -- EAGAIN / EWOULDBLOCK
  | 4   => .interrupted     -- EINTR
  | 9   => .badFd           -- EBADF
  | 104 => .connectionReset -- ECONNRESET
  | 32  => .brokenPipe      -- EPIPE
  | 107 => .notConnected    -- ENOTCONN
  | 22  => .invalid         -- EINVAL
  | 1   => .permissionDenied -- EPERM
  | 13  => .permissionDenied -- EACCES
  | 98  => .addressInUse    -- EADDRINUSE
  | 99  => .addressNotAvailable -- EADDRNOTAVAIL
  | 24  => .tooManyFiles    -- EMFILE (open file descriptors)
  | 23  => .tooManyFiles    -- ENFILE (system-wide limit)
  | n   => .other n

/-- True when the errno means "operation would block; try again". -/
@[inline] def isWouldBlock (e : Int) : Bool := e == 11

/-- True when the errno means "interrupted by signal; may retry". -/
@[inline] def isInterrupted (e : Int) : Bool := e == 4

end Iotakt.Native
