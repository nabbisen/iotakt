import Iotakt.Model.Registry
import Iotakt.Model.Event

/-!
# Iotakt.Model.Translate

Pure translation from normalized poller events to actor-targeted
readiness (RFC 005). This is iotakt's core correctness boundary:
unknown and stale events are dropped *before* any owner event is
constructed, so native poller quirks can never corrupt an actor's
mailbox.

`translateOne` is a pure function `Registry → NormalizedRawEvent →
TranslationResult` — it never mutates the registry. The headline
theorems are:

* `translate_no_unknown`    — an unresolvable raw fd yields no owner event;
* `translate_injectable_*`  — every owner event targets the registry owner
                              of the *current* key, which is live;
* `translate_interest_sound`— a `readable`/`writable` owner event requires
                              the matching registered interest;
* `translateKeyed_stale`    — an event carrying a non-current generation is
                              dropped (the direct stale-generation property
                              used by fake tests).
-/

namespace Iotakt.Model

/-- A fully resolved event: which actor owns it, under which stable key,
and what happened. Only `injectable` results carry one. -/
structure OwnerEvent where
  owner : ActorId
  key   : FdKey
  event : IoEvent
  deriving Repr, Inhabited

/-- Why a raw event was dropped. Explicit so traces and tests can assert
the exact reason. -/
inductive DropReason where
  | unknownRawFd
  | staleGeneration
  | noRegisteredInterest
  | resourceClosed
  deriving DecidableEq, Repr, Inhabited

/-- The result of translating one raw event. -/
inductive TranslationResult where
  | injectable (event : OwnerEvent)
  | dropped (rawFd : RawFd) (reason : DropReason)
  deriving Repr, Inhabited

namespace Registry

/-- Validate a resolved entry against an event and either build an owner
event or drop it. The owner event carries the **resolved key** (the key
under which the entry is registered), not `entry.key`, so owner
soundness holds without needing the well-formedness invariant. Fatal
events (eof/hangup/error) bypass the interest check; non-fatal readiness
requires the matching registered interest; closed/closing resources
receive nothing. -/
def validateAndBuild (key : FdKey) (entry : RegistryEntry) (rawFd : RawFd)
    (ev : IoEvent) : TranslationResult :=
  if !entry.state.isLive then
    .dropped rawFd .resourceClosed
  else if ev.isFatal then
    .injectable { owner := entry.owner, key := key, event := ev }
  else
    match ev.requiredInterest with
    | some i =>
        if entry.interests.has i then
          .injectable { owner := entry.owner, key := key, event := ev }
        else
          .dropped rawFd .noRegisteredInterest
    | none =>
        .dropped rawFd .noRegisteredInterest

/-- Translate one raw (native) event. Resolves the raw fd to the current
key, looks up its entry, and validates. Pure: returns no new registry. -/
def translateOne (reg : Registry) (ev : NormalizedRawEvent) : TranslationResult :=
  match reg.resolveCurrent ev.rawFd with
  | none      => .dropped ev.rawFd .unknownRawFd
  | some key  =>
      match reg.byKey key with
      | none       => .dropped ev.rawFd .staleGeneration
      | some entry => validateAndBuild key entry ev.rawFd ev.event

/-- Translate a batch of raw events in order. -/
def translateMany (reg : Registry) : List NormalizedRawEvent → List TranslationResult
  | []      => []
  | e :: es => translateOne reg e :: translateMany reg es

/-- Translate an event carrying an explicit (possibly stale) key — used
by fake tests to exercise the stale-generation drop directly, since real
native events carry only raw fds. The key is accepted only if it is the
current resolution for its raw fd. -/
def translateKeyed (reg : Registry) (key : FdKey) (ev : IoEvent) :
    TranslationResult :=
  if reg.resolveCurrent key.raw = some key then
    match reg.byKey key with
    | none       => .dropped key.raw .staleGeneration
    | some entry => validateAndBuild key entry key.raw ev
  else
    .dropped key.raw .staleGeneration

/-! ## Safety theorems -/

/-- **No unknown injection.** If a raw fd has no current generation, its
event is dropped as unknown — never turned into an owner event. -/
theorem translate_no_unknown (reg : Registry) {raw : RawFd} (ev : IoEvent)
    (h : reg.resolveCurrent raw = none) :
    reg.translateOne ⟨raw, ev⟩ = .dropped raw .unknownRawFd := by
  simp [translateOne, h]

/-- Corollary: an unresolvable raw fd never yields an injectable result. -/
theorem translate_unknown_not_injectable (reg : Registry) {raw : RawFd}
    (ev : IoEvent) (h : reg.resolveCurrent raw = none) :
    ∀ oe, reg.translateOne ⟨raw, ev⟩ ≠ .injectable oe := by
  intro oe; rw [translate_no_unknown reg ev h]; intro hc; cases hc

/-- **Owner soundness.** Every injectable event targets the owner stored
for the current key, and that key is the current resolution of the
event's raw fd. The proof inspects the `validateAndBuild` branches. -/
theorem translate_injectable_owner (reg : Registry) {ev : NormalizedRawEvent}
    {oe : OwnerEvent} (h : reg.translateOne ev = .injectable oe) :
    reg.resolveCurrent ev.rawFd = some oe.key ∧
    ∃ e, reg.byKey oe.key = some e ∧ e.owner = oe.owner ∧ e.state.isLive := by
  unfold translateOne at h
  cases hres : reg.resolveCurrent ev.rawFd with
  | none => simp only [hres] at h; exact absurd h (by simp)
  | some key =>
    simp only [hres] at h
    cases hby : reg.byKey key with
    | none => simp only [hby] at h; exact absurd h (by simp)
    | some entry =>
      simp only [hby] at h
      unfold validateAndBuild at h
      by_cases hlive : entry.state.isLive
      · simp only [hlive, Bool.not_true, Bool.false_eq_true, if_false] at h
        by_cases hfat : ev.event.isFatal
        · simp only [hfat, if_true] at h
          cases h
          exact ⟨rfl, entry, hby, rfl, hlive⟩
        · simp only [hfat, if_false] at h
          cases hreq : ev.event.requiredInterest with
          | none => simp only [hreq] at h; exact absurd h (by simp)
          | some i =>
            simp only [hreq] at h
            by_cases hint : entry.interests.has i
            · simp only [hint, if_true] at h
              cases h
              exact ⟨rfl, entry, hby, rfl, hlive⟩
            · simp only [hint, if_false] at h; exact absurd h (by simp)
      · simp only [hlive, Bool.not_false, if_true] at h; exact absurd h (by simp)

/-- **Interest soundness (read).** A `readable` injectable event implies
read interest was registered for the entry. -/
theorem translate_readable_interest (reg : Registry) {raw : RawFd}
    {oe : OwnerEvent} (h : reg.translateOne ⟨raw, .readable⟩ = .injectable oe) :
    ∃ e, reg.byKey oe.key = some e ∧ e.interests.read = true := by
  unfold translateOne at h
  cases hres : reg.resolveCurrent raw with
  | none => simp only [hres] at h; exact absurd h (by simp)
  | some key =>
    simp only [hres] at h
    cases hby : reg.byKey key with
    | none => simp only [hby] at h; exact absurd h (by simp)
    | some entry =>
      simp only [hby] at h
      unfold validateAndBuild at h
      by_cases hlive : entry.state.isLive
      · simp only [hlive, Bool.not_true, Bool.false_eq_true, if_false,
                   IoEvent.isFatal, IoEvent.requiredInterest] at h
        by_cases hint : entry.interests.has .readable
        · simp only [hint, if_true] at h
          cases h
          exact ⟨entry, hby, by simpa [InterestSet.has] using hint⟩
        · simp only [hint, if_false] at h; exact absurd h (by simp)
      · simp only [hlive, Bool.not_false, if_true] at h; exact absurd h (by simp)

/-- **Interest soundness (write).** A `writable` injectable event implies
write interest was registered. -/
theorem translate_writable_interest (reg : Registry) {raw : RawFd}
    {oe : OwnerEvent} (h : reg.translateOne ⟨raw, .writable⟩ = .injectable oe) :
    ∃ e, reg.byKey oe.key = some e ∧ e.interests.write = true := by
  unfold translateOne at h
  cases hres : reg.resolveCurrent raw with
  | none => simp only [hres] at h; exact absurd h (by simp)
  | some key =>
    simp only [hres] at h
    cases hby : reg.byKey key with
    | none => simp only [hby] at h; exact absurd h (by simp)
    | some entry =>
      simp only [hby] at h
      unfold validateAndBuild at h
      by_cases hlive : entry.state.isLive
      · simp only [hlive, Bool.not_true, Bool.false_eq_true, if_false,
                   IoEvent.isFatal, IoEvent.requiredInterest] at h
        by_cases hint : entry.interests.has .writable
        · simp only [hint, if_true] at h
          cases h
          exact ⟨entry, hby, by simpa [InterestSet.has] using hint⟩
        · simp only [hint, if_false] at h; exact absurd h (by simp)
      · simp only [hlive, Bool.not_false, if_true] at h; exact absurd h (by simp)

/-- **No closed injection.** An injectable event never targets a closed
or closing resource. -/
theorem translate_injectable_live (reg : Registry) {ev : NormalizedRawEvent}
    {oe : OwnerEvent} (h : reg.translateOne ev = .injectable oe) :
    ∃ e, reg.byKey oe.key = some e ∧ e.state.isLive := by
  obtain ⟨_, e, he, _, hlive⟩ := translate_injectable_owner reg h
  exact ⟨e, he, hlive⟩

/-- **No stale injection (keyed form).** An event whose key is not the
current resolution for its raw fd is dropped as stale. This is the
direct stale-generation property: after a close+reallocate the old key
is no longer current, so `translateKeyed` on it drops. -/
theorem translateKeyed_stale (reg : Registry) {key : FdKey} (ev : IoEvent)
    (h : reg.resolveCurrent key.raw ≠ some key) :
    reg.translateKeyed key ev = .dropped key.raw .staleGeneration := by
  simp [translateKeyed, h]

/-- A closed key cannot produce an injectable keyed event (combines
`close_not_current` with `translateKeyed_stale`). -/
theorem translateKeyed_closed_dropped (reg : Registry) (key : FdKey) (ev : IoEvent) :
    (reg.close key).translateKeyed key ev = .dropped key.raw .staleGeneration :=
  translateKeyed_stale (reg.close key) ev (reg.close_not_current key)

end Registry

end Iotakt.Model
