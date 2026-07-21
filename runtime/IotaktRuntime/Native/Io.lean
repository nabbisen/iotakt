import Iotakt.Model.Result
import IotaktRuntime.Native.Errno

/-!
# IotaktRuntime.Native.Unsafe.Io

Non-blocking recv and send wrappers (RFC 010, Option A).

Each `recv` call allocates one fresh Lean `ByteArray` in the C shim,
performs exactly one non-blocking `recv(2)` syscall, and returns
ownership immediately. No C-side application buffers are retained.

`send` reads from a borrowed Lean `ByteArray` and returns the byte count
or an error; partial writes are normal. The caller retains the unsent
suffix.
-/

namespace IotaktRuntime.Native.Unsafe.Io

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

/-- Monotonic nanosecond wall-clock timestamp (CLOCK_MONOTONIC).
Suitable for measuring elapsed time in benchmarks. -/
@[extern "iotakt_mono_ns"]
opaque monoNs : IO Int

/-! ## UDP datagram operations (RFC 036) -/

/-- Non-blocking recvfrom for UDP datagrams (Option A allocation policy).
Returns IO (Int × ByteArray × ByteArray):
- Int > 0 = bytes received; first ByteArray = datagram payload;
           second ByteArray = peer address (6 bytes: 4 IPv4 addr + 2 port, network order).
- Int = 0 = empty datagram.
- Int < 0 = -errno. -/
@[extern "iotakt_recvfrom"]
opaque recvFromRaw (fd : Int32) (maxBytes : USize) : IO (Int × ByteArray × ByteArray)

/-- Non-blocking sendto for UDP datagrams.
`addr` and `port` are in host byte order. Returns IO Int (bytes sent or -errno). -/
@[extern "iotakt_sendto"]
opaque sendToRaw (fd : Int32) (ba : @& ByteArray) (offset len : USize)
    (addr : UInt32) (port : UInt16) : IO Int

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

/-- UDP receive result: includes the datagram payload and peer address. -/
inductive RecvFromResult where
  | datagram (bytes : ByteArray) (peerAddr : ByteArray) : RecvFromResult
  | wouldBlock  : RecvFromResult
  | interrupted : RecvFromResult
  | error (e : IoErrno) : RecvFromResult
  deriving Inhabited

/-- Perform one non-blocking UDP recvfrom. -/
def recvFrom (fd : Int) (maxBytes : Nat) : IO RecvFromResult := do
  let (status, data, addr) ← recvFromRaw fd.toInt32 maxBytes.toUSize
  if status >= 0 then return .datagram data addr
  else
    let e := -status
    if isWouldBlock e then return .wouldBlock
    else if isInterrupted e then return .interrupted
    else return .error (classifyErrno e)

/-- Perform one non-blocking UDP sendto.
`addr` is host-byte-order IPv4 (e.g. 0x7f000001 = 127.0.0.1). -/
def sendTo (fd : Int) (ba : ByteArray) (offset len : Nat)
    (addr : UInt32) (port : UInt16) : IO WriteResult := do
  let status ← sendToRaw fd.toInt32 ba offset.toUSize len.toUSize addr port
  if status >= 0 then return .wrote status.toNat.toUSize
  else
    let e := -status
    if isWouldBlock e then return .wouldBlock
    else if isInterrupted e then return .interrupted
    else return .error (classifyErrno e)

end IotaktRuntime.Native.Unsafe.Io
