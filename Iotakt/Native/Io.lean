import Iotakt.Model.Result
import Iotakt.Native.Errno

/-!
# Iotakt.Native.Io

Non-blocking recv and send wrappers (RFC 010, Option A).

Each `recv` call allocates one fresh Lean `ByteArray` in the C shim,
performs exactly one non-blocking `recv(2)` syscall, and returns
ownership immediately. No C-side application buffers are retained.

`send` reads from a borrowed Lean `ByteArray` and returns the byte count
or an error; partial writes are normal. The caller retains the unsent
suffix.
-/

namespace Iotakt.Native.Io

open Iotakt.Model

/-! ## Extern declarations -/

/-- Non-blocking recv (Option A).
Returns IO (Int × ByteArray):
- Int > 0  → n bytes received; ByteArray holds them.
- Int = 0  → EOF.
- Int < 0  → -errno. -/
@[extern "iotakt_recv"]
opaque recvRaw (fd : Int32) (maxBytes : USize) : IO (Int × ByteArray)

/-- Non-blocking send.
Returns IO Int:
- Int ≥ 0 → bytes sent.
- Int < 0 → -errno. -/
@[extern "iotakt_send"]
opaque sendRaw (fd : Int32) (ba : @& ByteArray) (offset len : USize) : IO Int

/-! ## Typed wrappers -/

/-- Perform one non-blocking recv and return a typed `ReadResult`. -/
def recv (fd : Int) (maxBytes : Nat) : IO ReadResult := do
  let (status, buf) ← recvRaw fd.toInt32 maxBytes.toUSize
  if status > 0 then
    return .bytes buf
  else if status == 0 then
    return .eof
  else
    let e := -status  -- positive errno
    if isWouldBlock e then return .wouldBlock
    else if isInterrupted e then return .interrupted
    else return .error (classifyErrno e)

/-- Perform one non-blocking send and return a typed `WriteResult`. -/
def send (fd : Int) (ba : ByteArray) (offset len : Nat) : IO WriteResult := do
  let status ← sendRaw fd.toInt32 ba offset.toUSize len.toUSize
  if status >= 0 then
    return .wrote status.toNat.toUSize
  else
    let e := -status  -- positive errno
    if isWouldBlock e then return .wouldBlock
    else if isInterrupted e then return .interrupted
    else if e == 32 || e == 104 then return .closed  -- EPIPE or ECONNRESET
    else return .error (classifyErrno e)

end Iotakt.Native.Io
