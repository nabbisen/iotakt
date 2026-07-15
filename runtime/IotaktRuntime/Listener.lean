import Iotakt.Model

/-!
# IotaktRuntime.Listener

Typed listener endpoints and errors for RFC 070. IPv4 addresses cross the native
boundary as host-byte-order `UInt32` values; callers use reviewed constructors
instead of address strings or raw socket APIs.
-/

namespace IotaktRuntime.Listener

open Iotakt.Model

/-- A host-byte-order IPv4 address. -/
structure Ipv4Address where
  value : UInt32
  deriving DecidableEq, Repr, Inhabited

namespace Ipv4Address

/-- 127.0.0.1. -/
def loopback : Ipv4Address := ⟨0x7f000001⟩

/-- 0.0.0.0 (`INADDR_ANY`). -/
def wildcard : Ipv4Address := ⟨0⟩

/-- Construct an IPv4 address from four validated octets. -/
def ofOctets (a b c d : UInt8) : Ipv4Address :=
  ⟨a.toUInt32 * 0x1000000 + b.toUInt32 * 0x10000 +
    c.toUInt32 * 0x100 + d.toUInt32⟩

end Ipv4Address

/-- A validated IPv4 listener bind request. Port zero is rejected by the stable
listener API because the selected ephemeral port cannot yet be reported back. -/
structure BindEndpoint where
  address : Ipv4Address
  port : UInt16
  deriving DecidableEq, Repr, Inhabited

namespace BindEndpoint

def loopback (port : UInt16) : BindEndpoint := { address := .loopback, port }
def wildcard (port : UInt16) : BindEndpoint := { address := .wildcard, port }

end BindEndpoint

/-- Listener identity reuses the model's generation-safe fd authority. -/
abbrev ListenerKey := FdKey

/-- Consolidated active-listener state. `key.raw` is the native fd, so the record
stores it once as part of generation-safe identity alongside endpoint metadata. -/
structure ListenerRecord where
  key : ListenerKey
  endpoint : BindEndpoint
  deriving DecidableEq, Repr

/-- Native phase that failed before a listener could be published. -/
inductive ListenerTransitionError where
  | socketFailed (errno : IoErrno)
  | configureFailed (errno : IoErrno)
  | bindFailed (errno : IoErrno)
  | listenFailed (errno : IoErrno)
  | registerFailed (errno : IoErrno)
  deriving DecidableEq, Repr, Inhabited

/-- Structured, bounded failure from address-aware listener creation. -/
inductive ListenerError where
  | invalidEndpoint
  | duplicateEndpoint
  | transitionError (detail : ListenerTransitionError)
  deriving DecidableEq, Repr, Inhabited

end IotaktRuntime.Listener
