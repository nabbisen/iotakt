import Iotakt.Model.Fd
import Iotakt.Native.Errno

/-!
# Iotakt.Native.Socket

POSIX socket primitives (RFC 012): `@[extern]` declarations and a thin
Lean wrapper that interprets the flat C return codes into typed results.

All sockets are set non-blocking and close-on-exec before being
registered. The `accept` wrapper returns `(newFd, peerAddr)` on
success or an `IoErrno` on error.
-/

namespace Iotakt.Native.Socket

open Iotakt.Model

/-! ## Extern declarations -/

/-- Create a non-blocking, close-on-exec TCP socket.
`af4 = true` → AF_INET; `af4 = false` → AF_INET6.
Returns fd ≥ 0 or -errno. -/
@[extern "iotakt_socket_tcp"]
opaque socketTcpRaw (af4 : Int32) : IO Int

/-- Set SO_REUSEADDR on a listener fd. Returns 0 or -errno. -/
@[extern "iotakt_set_reuse_addr"]
opaque setReuseAddrRaw (fd : Int32) : IO Int

/-- Bind a TCP socket to an IPv4 address (host byte order) and port.
`addr = 0` binds to INADDR_ANY. Returns 0 or -errno. -/
@[extern "iotakt_bind_ipv4"]
opaque bindIPv4Raw (fd : Int32) (addr : UInt32) (port : UInt16) : IO Int

/-- Begin listening on a bound TCP socket.
Returns 0 or -errno. -/
@[extern "iotakt_listen"]
opaque listenRaw (fd : Int32) (backlog : Int32) : IO Int

/-- Accept one connection (accept4 with SOCK_NONBLOCK | SOCK_CLOEXEC).
Returns IO (Int × ByteArray):
- Int ≥ 0 = new fd; ByteArray = peer IPv4 address (4 bytes, network order)
- Int < 0 = -errno (EAGAIN = -11 means no connection ready) -/
@[extern "iotakt_accept"]
opaque acceptRaw (listenFd : Int32) : IO (Int × ByteArray)

/-- Apply O_NONBLOCK to a fd (fallback). Returns 0 or -errno. -/
@[extern "iotakt_set_nonblock"]
opaque setNonblockRaw (fd : Int32) : IO Int

/-- Apply FD_CLOEXEC to a fd (fallback). Returns 0 or -errno. -/
@[extern "iotakt_set_cloexec"]
opaque setCloexecRaw (fd : Int32) : IO Int

/-- Close a fd (idempotent on EBADF). -/
@[extern "iotakt_close"]
opaque closeFdRaw (fd : Int32) : IO Unit

/-- Create a connected AF_UNIX socket pair (both non-blocking, close-on-exec).
Returns IO (Int × Int):
- Both ≥ 0 = (fd0, fd1) of the connected pair.
- Both < 0 = -errno on failure. -/
@[extern "iotakt_socketpair"]
opaque socketpairRaw : IO (Int × Int)

/-! ## Typed wrappers -/

/-- Accept result. -/
inductive AcceptResult where
  | accepted (fd : Int) (peerAddr : ByteArray) : AcceptResult
  | wouldBlock  : AcceptResult
  | interrupted : AcceptResult
  | error (e : IoErrno) : AcceptResult
  deriving Inhabited

/-- Accept one connection and return a typed result. -/
def accept (listenFd : Int) : IO AcceptResult := do
  let (status, peer) ← acceptRaw listenFd.toInt32
  if status >= 0 then
    return .accepted status peer
  else
    let e := -status  -- positive errno
    if isWouldBlock e then return .wouldBlock
    else if isInterrupted e then return .interrupted
    else return .error (classifyErrno e)

/-- Close typed wrapper. -/
def closeFd (fd : Int) : IO Unit := closeFdRaw fd.toInt32

end Iotakt.Native.Socket
