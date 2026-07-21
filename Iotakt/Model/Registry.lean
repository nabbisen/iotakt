import Iotakt.Model.Update
import Iotakt.Model.Fd
import Iotakt.Model.Interest

/-!
# Iotakt.Model.Registry

The registry: the authoritative Lean-side map from active `FdKey`s to
owner actors, kinds, lifecycle states, and interests (RFC 002, RFC
003).

Following Henret's function-map discipline, the registry maps are total
functions updated through `upd`, which keeps the preservation proofs
mechanical. Two maps are kept:

* `byKey`      : the entry for each `FdKey`.
* `currentGen` : the generation currently active for each raw fd.

The well-formedness invariant `WellFormed` ties the two together: the
generation `currentGen` reports for a raw fd resolves to a live entry
whose key is exactly that `(raw, gen)` pair, and every key's generation
is below the monotone `nextGen` counter. From those two facts the
headline safety theorems follow:

* **current-generation soundness** — resolving a raw fd yields the one
  active key for it;
* **no stale resolution** — once a fresh generation is allocated the old
  key can never again be reported as current;
* **closed terminality** — a closed key is not resolvable as current.
-/

namespace Iotakt.Model

/-- One registry entry: a resource's stable key, owner, kind, lifecycle
state, and registered interests. -/
structure RegistryEntry where
  key       : FdKey
  owner     : ActorId
  kind      : ResourceKind
  state     : ResourceState
  interests : InterestSet
  deriving Repr, Inhabited

/-- Authority-validation failures for operations that can cause an fd effect.
Native wrappers lift these into their domain error type before performing I/O. -/
inductive KeyError where
  | invalidRawFd
  | unknownKey
  | staleKey
  | wrongKind
  | inactive
  deriving DecidableEq, Repr, Inhabited

/-- The registry. `byKey` and `currentGen` are total function-maps;
`nextGen` is a monotone fresh-generation counter. -/
structure Registry where
  byKey      : FdKey → Option RegistryEntry
  currentGen : RawFd → Option FdGeneration
  nextGen    : FdGeneration
  deriving Inhabited

namespace Registry

/-- The empty registry: no entries, no current generations, generation
counter at zero. -/
def empty : Registry where
  byKey      := fun _ => Option.none
  currentGen := fun _ => Option.none
  nextGen    := 0

/-- Look up the entry for a key. -/
def lookup (reg : Registry) (key : FdKey) : Option RegistryEntry :=
  reg.byKey key

/-- Resolve a raw fd to its currently active `FdKey`, if any. This is
the only sanctioned way to turn a native raw fd back into an iotakt
identity. -/
def resolveCurrent (reg : Registry) (raw : RawFd) : Option FdKey :=
  (reg.currentGen raw).map (fun g => ⟨raw, g⟩)

/-- Resolve and validate the authority carried by `key` before an effectful fd
operation. Failure is pure and therefore cannot cause a native side effect. -/
def resolveEffectKey (reg : Registry) (key : FdKey)
    (allowedKinds : List ResourceKind) : Except KeyError RegistryEntry :=
  if key.raw < 0 then
    .error .invalidRawFd
  else
    match reg.resolveCurrent key.raw with
    | none => .error .unknownKey
    | some current =>
        if current != key then
          .error .staleKey
        else
          match reg.lookup key with
          | none => .error .unknownKey
          | some entry =>
              if entry.key != key then .error .staleKey
              else if !entry.state.isLive then .error .inactive
              else if !allowedKinds.contains entry.kind then .error .wrongKind
              else .ok entry

/-- Allocate a fresh resource for `raw`, owned by `owner`. The new key
takes generation `reg.nextGen` (strictly newer than any previously
allocated key), becomes the current generation for `raw`, and the
counter advances. This is the model side of accept/listen; the native
layer supplies only the raw fd. -/
def allocate (reg : Registry) (raw : RawFd) (owner : ActorId)
    (kind : ResourceKind) : Registry × FdKey :=
  let g   := reg.nextGen
  let key : FdKey := ⟨raw, g⟩
  let entry : RegistryEntry :=
    { key := key, owner := owner, kind := kind,
      state := .allocated, interests := InterestSet.none }
  ({ byKey      := upd reg.byKey key (some entry)
     currentGen := upd reg.currentGen raw (some g)
     nextGen    := g + 1 }, key)

/-- Replace the entry stored for `key`, if it exists. Used by the
lifecycle and interest operations below; never changes `currentGen` or
`nextGen`. -/
def setEntry (reg : Registry) (key : FdKey) (f : RegistryEntry → RegistryEntry) :
    Registry :=
  match reg.byKey key with
  | some e => { reg with byKey := upd reg.byKey key (some (f e)) }
  | Option.none => reg

/-- Set the registered interests for a key. -/
def setInterests (reg : Registry) (key : FdKey) (i : InterestSet) : Registry :=
  reg.setEntry key (fun e => { e with interests := i })

/-- Move a key to a new lifecycle state. -/
def setState (reg : Registry) (key : FdKey) (st : ResourceState) : Registry :=
  reg.setEntry key (fun e => { e with state := st })

/-- Close a key only when it is the current generation: mark its entry `closed`
and remove it from `currentGen`. Unknown and stale keys are pure no-ops, so an old
key can never clear a newer generation's authority. Effectful callers must use
`resolveEffectKey` first so the no-op is surfaced as a typed error. -/
def close (reg : Registry) (key : FdKey) : Registry :=
  if reg.resolveCurrent key.raw = some key then
    let reg' := reg.setState key .closed
    { reg' with currentGen := upd reg'.currentGen key.raw Option.none }
  else
    reg

/-! ## Allocate projection lemmas

Small `rfl`/`simp` facts about the shape of `allocate`'s result. They
keep the well-formedness preservation proof free of `simp [allocate]`
unfolding and let `omega` see the literal `nextGen + 1`. -/

/-- The entry `allocate` installs for `raw`. -/
def allocatedEntry (reg : Registry) (raw : RawFd) (owner : ActorId)
    (kind : ResourceKind) : RegistryEntry :=
  { key := ⟨raw, reg.nextGen⟩, owner := owner, kind := kind,
    state := .allocated, interests := InterestSet.none }

@[simp] theorem allocatedEntry_state (reg : Registry) (raw : RawFd)
    (owner : ActorId) (kind : ResourceKind) :
    (reg.allocatedEntry raw owner kind).state = .allocated := rfl

@[simp] theorem allocatedEntry_key (reg : Registry) (raw : RawFd)
    (owner : ActorId) (kind : ResourceKind) :
    (reg.allocatedEntry raw owner kind).key = ⟨raw, reg.nextGen⟩ := rfl

@[simp] theorem allocate_nextGen (reg : Registry) (raw : RawFd) (owner : ActorId)
    (kind : ResourceKind) :
    (reg.allocate raw owner kind).1.nextGen = reg.nextGen + 1 := rfl

@[simp] theorem allocate_currentGen_self (reg : Registry) (raw : RawFd)
    (owner : ActorId) (kind : ResourceKind) :
    (reg.allocate raw owner kind).1.currentGen raw = some reg.nextGen := by
  simp [allocate, upd]

theorem allocate_currentGen_ne (reg : Registry) {r raw : RawFd}
    (owner : ActorId) (kind : ResourceKind) (h : r ≠ raw) :
    (reg.allocate raw owner kind).1.currentGen r = reg.currentGen r := by
  simp [allocate, upd, h]

@[simp] theorem allocate_byKey_self (reg : Registry) (raw : RawFd)
    (owner : ActorId) (kind : ResourceKind) :
    (reg.allocate raw owner kind).1.byKey ⟨raw, reg.nextGen⟩
      = some (reg.allocatedEntry raw owner kind) := by
  simp [allocate, allocatedEntry, upd]

theorem allocate_byKey_ne (reg : Registry) {k : FdKey} (raw : RawFd)
    (owner : ActorId) (kind : ResourceKind) (h : k ≠ ⟨raw, reg.nextGen⟩) :
    (reg.allocate raw owner kind).1.byKey k = reg.byKey k := by
  simp [allocate, upd, h]

/-! ## Well-formedness invariant -/

/-- The registry invariant. Each conjunct is named so individual
preservation lemmas can target it.

1. `current_resolves` — if `currentGen raw = some g`, the key
   `(raw, g)` has a live entry whose own `key` field is `(raw, g)`.
2. `current_gen_lt` — every current generation is below `nextGen`.
3. `entry_key_consistent` — every stored entry's `key` field matches the
   key it is stored under, and its generation is below `nextGen`. -/
structure WellFormed (reg : Registry) : Prop where
  current_resolves : ∀ raw g, reg.currentGen raw = some g →
    ∃ e, reg.byKey ⟨raw, g⟩ = some e ∧ e.key = ⟨raw, g⟩ ∧ e.state ≠ .closed
  current_gen_lt : ∀ raw g, reg.currentGen raw = some g → g < reg.nextGen
  entry_key_consistent : ∀ k e, reg.byKey k = some e →
    e.key = k ∧ k.gen < reg.nextGen

/-- The empty registry is well-formed (vacuously: no entries, no current
generations). -/
theorem wf_empty : WellFormed empty := by
  constructor
  · intro raw g h; simp [empty] at h
  · intro raw g h; simp [empty] at h
  · intro k e h; simp [empty] at h

/-! ## Headline safety theorems -/

/-- **Current-generation soundness.** If `resolveCurrent` returns a key,
that key has a live entry whose own `key` field matches — i.e. the
resolved key is exactly the one active resource for the raw fd. -/
theorem resolveCurrent_sound {reg : Registry} (h : WellFormed reg)
    {raw : RawFd} {key : FdKey} (hr : reg.resolveCurrent raw = some key) :
    ∃ e, reg.byKey key = some e ∧ e.key = key ∧ e.state ≠ .closed := by
  unfold resolveCurrent at hr
  cases hg : reg.currentGen raw with
  | none => simp [hg] at hr
  | some g =>
    simp [hg] at hr
    subst hr
    exact h.current_resolves raw g hg

/-- **The resolved key is the current generation.** A raw fd resolves to
at most one key, and that key's generation is exactly `currentGen raw`.
This is the precise statement that "raw fd alone is not identity": the
generation component is pinned by the registry, not by the event. -/
theorem resolveCurrent_gen {reg : Registry} {raw : RawFd} {key : FdKey}
    (hr : reg.resolveCurrent raw = some key) :
    reg.currentGen raw = some key.gen ∧ key.raw = raw := by
  unfold resolveCurrent at hr
  cases hg : reg.currentGen raw with
  | none => simp [hg] at hr
  | some g => simp [hg] at hr; subst hr; exact ⟨rfl, rfl⟩

/-- **No stale resolution after close.** Once a key is closed, that key
can never again be reported as the current resolution for its raw fd.
(The raw fd may later resolve to a *different*, strictly-newer key after
a fresh `allocate`, but never back to the closed one.) -/
theorem close_not_current {reg : Registry} (key : FdKey) :
    (reg.close key).resolveCurrent key.raw ≠ some key := by
  by_cases h : reg.resolveCurrent key.raw = some key
  · unfold close
    rw [if_pos h]
    unfold resolveCurrent setState setEntry
    cases hb : reg.byKey key with
    | none => simp [hb, upd]
    | some e => simp [hb, upd]
  · simp [close, h]

/-- Closing a key that is not current is a pure no-op. -/
theorem close_eq_self_of_not_current {reg : Registry} {key : FdKey}
    (h : reg.resolveCurrent key.raw ≠ some key) :
    reg.close key = reg := by
  simp [close, h]

/-- A stale close cannot clear the newer key currently owning the same raw fd. -/
theorem close_stale_preserves_current {reg : Registry} {stale current : FdKey}
    (hcurrent : reg.resolveCurrent stale.raw = some current)
    (hne : current ≠ stale) :
    (reg.close stale).resolveCurrent stale.raw = some current := by
  have hstale : reg.resolveCurrent stale.raw ≠ some stale := by
    intro hs
    apply hne
    exact Option.some.inj (hcurrent.symm.trans hs)
  rw [close_eq_self_of_not_current hstale]
  exact hcurrent

/-- A stale close cannot alter any registry entry, including the newer owner. -/
theorem close_stale_preserves_entry {reg : Registry} {stale current : FdKey}
    (hcurrent : reg.resolveCurrent stale.raw = some current)
    (hne : current ≠ stale) :
    (reg.close stale).lookup current = reg.lookup current := by
  have hstale : reg.resolveCurrent stale.raw ≠ some stale := by
    intro hs
    apply hne
    exact Option.some.inj (hcurrent.symm.trans hs)
  rw [close_eq_self_of_not_current hstale]

/-- Negative raw fds are rejected before registry lookup. -/
theorem resolveEffectKey_invalidRaw {reg : Registry} {key : FdKey}
    (h : key.raw < 0) (allowedKinds : List ResourceKind) :
    reg.resolveEffectKey key allowedKinds = .error .invalidRawFd := by
  simp [resolveEffectKey, h]

/-- A non-current generation is rejected as stale before entry use. -/
theorem resolveEffectKey_stale {reg : Registry} {key current : FdKey}
    (hraw : ¬key.raw < 0)
    (hcurrent : reg.resolveCurrent key.raw = some current)
    (hne : current ≠ key) (allowedKinds : List ResourceKind) :
    reg.resolveEffectKey key allowedKinds = .error .staleKey := by
  simp [resolveEffectKey, hraw, hcurrent, hne]

/-- Successful effect-key resolution returns exactly the current, stored, live
entry, and its resource kind is one of those authorized by the caller. Native ABI
upper-bound validation is deliberately proved/tested at the runtime `checkedFd32`
layer; the pure model owns the non-negative and registry-authority conditions. -/
theorem resolveEffectKey_ok {reg : Registry} {key : FdKey}
    {allowedKinds : List ResourceKind} {entry : RegistryEntry}
    (h : reg.resolveEffectKey key allowedKinds = .ok entry) :
    (¬key.raw < 0) ∧
      reg.resolveCurrent key.raw = some key ∧
      reg.lookup key = some entry ∧
      entry.key = key ∧
      entry.state.isLive = true ∧
      allowedKinds.contains entry.kind = true := by
  unfold resolveEffectKey at h
  split at h <;> simp_all
  split at h <;> simp_all
  split at h <;> simp_all
  split at h <;> simp_all
  split at h <;> try simp_all
  split at h <;> try simp_all
  split at h <;> simp_all

/-- **Fresh allocation is strictly newer.** The key produced by
`allocate` carries generation `reg.nextGen`, so it differs from every
key already constrained by `WellFormed` (whose generations are
`< nextGen`). This is the model fact behind stale-event rejection. -/
theorem allocate_fresh_gen (reg : Registry) (raw : RawFd) (owner : ActorId)
    (kind : ResourceKind) :
    (reg.allocate raw owner kind).2.gen = reg.nextGen := rfl

/-- After `allocate`, the new key is the current generation for its raw
fd. -/
theorem allocate_is_current (reg : Registry) (raw : RawFd) (owner : ActorId)
    (kind : ResourceKind) :
    (reg.allocate raw owner kind).1.resolveCurrent raw
      = some (reg.allocate raw owner kind).2 := by
  simp [allocate, resolveCurrent, upd]

/-- **Allocation preserves well-formedness**, provided the raw fd being
allocated has no live current generation conflicting with the freshly
allocated entry. Because the new key uses `nextGen` (strictly above all
existing generations) and bumps the counter, the three invariant
conjuncts are re-established. -/
theorem allocate_preserves_wf {reg : Registry} (h : WellFormed reg)
    (raw : RawFd) (owner : ActorId) (kind : ResourceKind) :
    WellFormed (reg.allocate raw owner kind).1 := by
  refine ⟨?_, ?_, ?_⟩
  · -- current_resolves
    intro r g' hg
    by_cases hr : r = raw
    · subst hr
      rw [allocate_currentGen_self] at hg
      have hgg : g' = reg.nextGen := by injection hg with hgg; exact hgg.symm
      subst hgg
      refine ⟨reg.allocatedEntry r owner kind, allocate_byKey_self reg r owner kind,
              rfl, by rw [allocatedEntry_state]; decide⟩
    · rw [allocate_currentGen_ne reg owner kind hr] at hg
      obtain ⟨e, he, hek, hes⟩ := h.current_resolves r g' hg
      have hkne : (⟨r, g'⟩ : FdKey) ≠ ⟨raw, reg.nextGen⟩ := by
        intro hc; exact hr (FdKey.mk.injEq .. ▸ hc).1
      exact ⟨e, by rw [allocate_byKey_ne reg raw owner kind hkne]; exact he, hek, hes⟩
  · -- current_gen_lt
    intro r g' hg
    by_cases hr : r = raw
    · subst hr
      rw [allocate_currentGen_self] at hg
      have : g' = reg.nextGen := by injection hg with hgg; exact hgg.symm
      subst this
      exact Nat.lt_succ_self reg.nextGen
    · rw [allocate_currentGen_ne reg owner kind hr] at hg
      have hlt := h.current_gen_lt r g' hg
      exact Nat.lt_succ_of_lt hlt
  · -- entry_key_consistent
    intro k e hk
    by_cases hkey : k = ⟨raw, reg.nextGen⟩
    · subst hkey
      rw [allocate_byKey_self] at hk
      have hee : e = reg.allocatedEntry raw owner kind := by
        injection hk with he; exact he.symm
      subst hee
      exact ⟨rfl, Nat.lt_succ_self reg.nextGen⟩
    · rw [allocate_byKey_ne reg raw owner kind hkey] at hk
      obtain ⟨hek, hlt⟩ := h.entry_key_consistent k e hk
      exact ⟨hek, Nat.lt_succ_of_lt hlt⟩

end Registry

end Iotakt.Model
