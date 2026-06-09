/-!
# Iotakt.Model.Interest

Backend-neutral interest vocabulary (RFC 004).

An *interest* is what iotakt asked the poller to observe. iotakt
deliberately models only readability and writability; backend-specific
flags (`EPOLLIN`, `EVFILT_READ`, …) never appear in the model — they
are normalised at the native boundary.
-/

namespace Iotakt.Model

/-- A single readiness interest. -/
inductive Interest where
  | readable
  | writable
  deriving DecidableEq, Repr, Inhabited

/-- The set of interests currently registered for a resource.
Represented as two booleans for proof convenience and decidability. -/
structure InterestSet where
  read  : Bool := false
  write : Bool := false
  deriving DecidableEq, Repr, Inhabited

namespace InterestSet

/-- No interests registered. -/
def none : InterestSet := {}

/-- Read-only interest (the default for a freshly registered stream or
listener). -/
def readOnly : InterestSet := { read := true, write := false }

/-- Does this set contain the given interest? -/
def has (s : InterestSet) : Interest → Bool
  | .readable => s.read
  | .writable => s.write

/-- Enable write interest (backpressure: enabled only when the actor
has pending output — RFC 006). -/
def enableWrite (s : InterestSet) : InterestSet := { s with write := true }

/-- Disable write interest (all pending output flushed). -/
def disableWrite (s : InterestSet) : InterestSet := { s with write := false }

@[simp] theorem has_readOnly_readable : readOnly.has .readable = true := rfl
@[simp] theorem has_readOnly_writable : readOnly.has .writable = false := rfl
@[simp] theorem has_none_readable : none.has .readable = false := rfl
@[simp] theorem has_none_writable : none.has .writable = false := rfl

end InterestSet

end Iotakt.Model
