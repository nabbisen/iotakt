import Iotakt.Model.Event
import Iotakt.Native.Errno

/-!
# Iotakt.Native.Epoll

Linux epoll backend (RFC 011): `@[extern]` declarations for the C shim
and pure helpers to normalize raw epoll flags into the backend-neutral
`NormalizedRawEvent` vocabulary.

Level-triggered epoll (the v0.1 default) re-reports readiness until
the fd is drained; coalescing at the model layer (RFC 006) prevents
mailbox floods.
-/

namespace Iotakt.Native.Epoll

open Iotakt.Model

/-! ## Epoll extern declarations -/

/-- Create an epoll instance (EPOLL_CLOEXEC).
Returns the epoll fd (≥ 0) or -errno. -/
@[extern "iotakt_epoll_create"]
opaque create : IO Int

/-- Register a raw fd with the epoll instance.
`flags`: bit 0 = readable, bit 2 = writable. Returns 0 or -errno. -/
@[extern "iotakt_epoll_register"]
opaque register (epfd : Int32) (fd : Int32) (flags : UInt32) : IO Int

/-- Modify the interest set for a registered fd. Returns 0 or -errno. -/
@[extern "iotakt_epoll_modify"]
opaque modify (epfd : Int32) (fd : Int32) (flags : UInt32) : IO Int

/-- Remove a fd from the epoll instance. Returns 0 or -errno. -/
@[extern "iotakt_epoll_deregister"]
opaque deregister (epfd : Int32) (fd : Int32) : IO Int

/-- Wait for events.
Returns `(status, data)`:
- `status > 0`: n events encoded in `data` (8 bytes each: `int32_t fd` + `uint32_t flags`, little-endian);
- `status = 0`: timeout or 0 events;
- `status < 0`: -errno (fatal epoll error).
EINTR is treated as 0 events by the C shim. -/
@[extern "iotakt_epoll_wait"]
opaque wait (epfd : Int32) (maxEvents : Int32) (timeoutMs : Int32) : IO (Int × ByteArray)

/-- Close the epoll fd. -/
@[extern "iotakt_epoll_close"]
opaque close (epfd : Int32) : IO Unit

/-! ## Interest flags for register/modify -/

/-- Build the epoll interest bitmask from an `InterestSet`. -/
def interestFlags (i : InterestSet) : UInt32 :=
  (if i.read  then 0x1 else 0) |||   -- EPOLLIN
  (if i.write then 0x4 else 0)        -- EPOLLOUT

/-! ## Event normalization -/

-- Known epoll event masks (kernel always delivers ERR and HUP even
-- when not registered; we must handle them).
private def EPOLLIN   : UInt32 := 0x1
private def EPOLLOUT  : UInt32 := 0x4
private def EPOLLERR  : UInt32 := 0x8
private def EPOLLHUP  : UInt32 := 0x10
private def EPOLLRDHUP: UInt32 := 0x2000

/-- Normalize one raw epoll event (fd + flags) into a list of
`NormalizedRawEvent`s. Order: error → hangup → eof → readable → writable,
so fatal conditions are translated before readiness hints. -/
def normalizeFlags (rawFd : RawFd) (flags : UInt32) : List NormalizedRawEvent :=
  let ev (e : IoEvent) : NormalizedRawEvent := { rawFd := rawFd, event := e }
  let check (mask : UInt32) (e : IoEvent) : List NormalizedRawEvent :=
    if flags &&& mask != 0 then [ev e] else []
  check EPOLLERR   (IoEvent.error none) ++
  check EPOLLHUP   IoEvent.hangup ++
  check EPOLLRDHUP IoEvent.eof ++
  check EPOLLIN    IoEvent.readable ++
  check EPOLLOUT   IoEvent.writable

/-- Parse the `ByteArray` returned by `wait` into a list of normalized
events. Each 8-byte slice encodes one raw epoll event. -/
def parseEvents (ba : ByteArray) : List NormalizedRawEvent :=
  let n := ba.size / 8
  (List.range n).flatMap fun i =>
    let off := i * 8
    -- Read little-endian int32 (the raw fd)
    let b0 := ba.get! off       |>.toNat
    let b1 := ba.get! (off + 1) |>.toNat
    let b2 := ba.get! (off + 2) |>.toNat
    let b3 := ba.get! (off + 3) |>.toNat
    let raw32 := b0 ||| (b1 <<< 8) ||| (b2 <<< 16) ||| (b3 <<< 24)
    -- Sign-extend from 32 bits
    let rawFd : RawFd :=
      if raw32 &&& 0x80000000 != 0
      then -Int.ofNat (0x100000000 - raw32)
      else Int.ofNat raw32
    -- Read little-endian uint32 (the flags)
    let f0 := ba.get! (off + 4) |>.toNat
    let f1 := ba.get! (off + 5) |>.toNat
    let f2 := ba.get! (off + 6) |>.toNat
    let f3 := ba.get! (off + 7) |>.toNat
    let flags : UInt32 :=
      (f0 ||| (f1 <<< 8) ||| (f2 <<< 16) ||| (f3 <<< 24)).toUInt32
    normalizeFlags rawFd flags

end Iotakt.Native.Epoll
