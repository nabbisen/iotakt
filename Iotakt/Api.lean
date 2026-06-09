import Iotakt.Model
import Iotakt.Fake

/-!
# Iotakt.Api

The stable public API of iotakt (RFC 017).

Import this module (not internal submodules) for code that should stay
stable across iotakt releases. Internal modules may change structure or
naming without being considered breaking changes; `Iotakt.Api` carries
the semantic-versioning guarantee.

## Dependency tiers

```text
Iotakt.Api          ← stable API (this module)
  ↓
Iotakt.Model        ← pure model (Lean-only, always available)
Iotakt.Fake         ← deterministic fake poller (Lean-only)
```

Bridge and native modules are imported separately because they have
additional dependencies (Henret and C toolchain respectively):

```lean
import Iotakt.Api    -- always available
import Iotakt.Bridge -- requires Henret
import Iotakt.Native -- requires native C build
import Iotakt.Driver -- requires both
```

## Stable names

All names exported from this module are part of the v0.x stable surface.
-/

namespace Iotakt.Api

-- ── Core model types ────────────────────────────────────────────────────

/-- A raw OS file descriptor integer. Not a stable identity: the OS
reuses fd numbers after close. Use `FdKey` for stable resource identity. -/
abbrev RawFd := Iotakt.Model.RawFd

/-- Stable resource identity: a raw fd paired with a monotone generation
counter. Stale events for old generations are dropped at the model
boundary. -/
abbrev FdKey := Iotakt.Model.FdKey

/-- Owner actor identity (same type as `Henret.ActorId = Nat`). -/
abbrev ActorId := Iotakt.Model.ActorId

/-- A readiness interest: readable or writable. -/
abbrev Interest := Iotakt.Model.Interest

/-- A registered interest set (read/write flags). -/
abbrev InterestSet := Iotakt.Model.InterestSet

/-- A normalized I/O event: readable, writable, eof, hangup, or error. -/
abbrev IoEvent := Iotakt.Model.IoEvent

/-- Platform errno codes in a Lean-friendly form. -/
abbrev IoErrno := Iotakt.Model.IoErrno

/-- Result of a recv call. -/
abbrev ReadResult := Iotakt.Model.ReadResult

/-- Result of a send call. -/
abbrev WriteResult := Iotakt.Model.WriteResult

/-- A readiness message delivered to an owning actor. -/
abbrev IoMessage := Iotakt.Model.IoMessage

-- ── Resource registry ───────────────────────────────────────────────────

/-- The fd registry: maps `FdKey` to ownership and lifecycle state.
The registry is pure (no IO) and carries machine-checked invariants.
Use `Iotakt.Model.Registry.empty` to initialize. -/
abbrev Registry := Iotakt.Model.Registry

/-- The well-formedness invariant on a registry.
All model theorems are stated in terms of `Registry.WellFormed`. -/
abbrev RegistryWellFormed := Iotakt.Model.Registry.WellFormed

-- ── Readiness coalescing ────────────────────────────────────────────────

/-- Coalescing state: the set of outstanding readiness notifications.
Limits actor mailbox growth to at most one pending readiness per
`FdKey + kind` at any time. -/
abbrev CoalesceState := Iotakt.Model.CoalesceState

-- ── Interest set constructors ────────────────────────────────────────────

/-- No registered interests. -/
def InterestSet.none : InterestSet := Iotakt.Model.InterestSet.none

/-- Read interest only (the default for accepted streams and listeners). -/
def InterestSet.readOnly : InterestSet := Iotakt.Model.InterestSet.readOnly

/-- Enable write interest on an interest set. -/
def InterestSet.enableWrite (i : InterestSet) : InterestSet :=
  Iotakt.Model.InterestSet.enableWrite i

/-- Disable write interest. -/
def InterestSet.disableWrite (i : InterestSet) : InterestSet :=
  Iotakt.Model.InterestSet.disableWrite i

-- ── Fake poller (Lean-only testing) ─────────────────────────────────────

/-- A scripted fake poll outcome — used in deterministic tests and
proof-adjacent examples without any native code or OS dependency. -/
abbrev FakePollResult := Iotakt.Fake.FakePollResult

/-- A deterministic scripted poller. Feed a `List FakePollResult` to
drive the bridge in exact replay order. -/
abbrev FakePoller := Iotakt.Fake.FakePoller

-- ── Convenience re-exports ───────────────────────────────────────────────

/-- Construct a `FdKey`. -/
def mkFdKey (raw : RawFd) (gen : Iotakt.Model.FdGeneration) : FdKey :=
  ⟨raw, gen⟩

/-- Return the raw fd integer from a key. -/
def FdKey.rawInt (k : FdKey) : Int := k.raw

/-- Return the generation from a key. -/
def FdKey.generation (k : FdKey) : Iotakt.Model.FdGeneration := k.gen

end Iotakt.Api

/-!
## Usage example

```lean
import Iotakt.Api

open Iotakt.Api

def processEvent (reg : Registry) (ev : IoEvent) (key : FdKey) : String :=
  match ev with
  | .readable => s!"fd {key.rawInt} is readable"
  | .writable => s!"fd {key.rawInt} is writable"
  | .eof      => s!"fd {key.rawInt} reached EOF"
  | .hangup   => s!"fd {key.rawInt} hung up"
  | .error e  => s!"fd {key.rawInt} error: {repr e}"
```
-/
