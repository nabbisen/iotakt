import Henret.Model
import Iotakt.Model

/-!
# Iotakt.Bridge.Message

Encoding iotakt readiness into Henret's message envelope (RFC 007).

Henret's `Message` is a fixed two-`Nat` envelope `{ id, payload }`
(Henret v0.6.0; a richer envelope is Henret RFC 033, proposed). iotakt
encodes a readiness notification as:

* `id`      = the raw fd (the actor owns the current generation, so the
              generation need not travel in the message);
* `payload` = a readiness bitmask.

This is deliberately lossy and documented as such: it is iotakt's
convention over Henret's envelope, not a Henret type. When Henret RFC
033 ships a structured envelope, this codec is the single place to
update.
-/

namespace Iotakt.Bridge

open Iotakt.Model

/-- Readiness bitmask used in `Message.payload`. -/
def IoEvent.encode : IoEvent → Nat
  | .readable => 1
  | .writable => 2
  | .eof      => 4
  | .hangup   => 8
  | .error _  => 16

/-- Encode an owner event as a Henret message. `id` is the raw fd cast
to `Nat`; `payload` is the readiness bitmask. -/
def encodeOwnerEvent (oe : OwnerEvent) : Henret.Message :=
  { id := oe.key.raw.toNat, payload := IoEvent.encode oe.event }

@[simp] theorem encode_readable : IoEvent.encode .readable = 1 := rfl
@[simp] theorem encode_writable : IoEvent.encode .writable = 2 := rfl
@[simp] theorem encode_eof : IoEvent.encode .eof = 4 := rfl

end Iotakt.Bridge
