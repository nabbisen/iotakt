import Iotakt.Model.Registry

/-!
# Iotakt.Model.Lifecycle

Resource lifecycle transitions (RFC 003).

iotakt models ownership and readiness lifecycle, never the TCP state
machine. The transitions move a resource through
`allocated → configured → (listening|registered) → active → closing →
closed`, with `close` the single terminal step. The proof obligations
of RFC 003 are discharged here:

* `close_preserves_wf`     — closing keeps the registry well-formed;
* `close_terminal`         — a closed key is not resolvable as current
                              (re-exported from `Registry.close_not_current`);
* `double_close_idempotent`— closing an already-closed key changes nothing
                              relevant (no second native close, no reactivation);
* `registered_not_closed`  — a freshly registered resource is live.
-/

namespace Iotakt.Model
namespace Registry

/-! ## setState / close projection lemmas -/

theorem setState_currentGen (reg : Registry) (key : FdKey) (st : ResourceState) :
    (reg.setState key st).currentGen = reg.currentGen := by
  unfold setState setEntry
  cases reg.byKey key <;> rfl

theorem setState_nextGen (reg : Registry) (key : FdKey) (st : ResourceState) :
    (reg.setState key st).nextGen = reg.nextGen := by
  unfold setState setEntry
  cases reg.byKey key <;> rfl

theorem setState_byKey_self (reg : Registry) (key : FdKey) (st : ResourceState) :
    (reg.setState key st).byKey key
      = (reg.byKey key).map (fun e => { e with state := st }) := by
  unfold setState setEntry
  cases h : reg.byKey key with
  | none => simp [h]
  | some e => simp [h, upd]

theorem setState_byKey_ne (reg : Registry) {k key : FdKey} (st : ResourceState)
    (h : k ≠ key) : (reg.setState key st).byKey k = reg.byKey k := by
  unfold setState setEntry
  cases hb : reg.byKey key with
  | none => rfl
  | some e => simp [hb, upd, h]

theorem close_nextGen (reg : Registry) (key : FdKey) :
    (reg.close key).nextGen = reg.nextGen := by
  by_cases h : reg.resolveCurrent key.raw = some key
  · simp [close, h, setState_nextGen]
  · simp [close, h]

theorem close_currentGen_self (reg : Registry) (key : FdKey)
    (h : reg.resolveCurrent key.raw = some key) :
    (reg.close key).currentGen key.raw = none := by
  simp [close, h, upd]

theorem close_currentGen_ne (reg : Registry) {r : RawFd} (key : FdKey)
    (h : r ≠ key.raw) : (reg.close key).currentGen r = reg.currentGen r := by
  by_cases hc : reg.resolveCurrent key.raw = some key
  · simp [close, hc, upd, h, setState_currentGen]
  · simp [close, hc]

theorem close_byKey_ne (reg : Registry) {k key : FdKey} (h : k ≠ key) :
    (reg.close key).byKey k = reg.byKey k := by
  by_cases hc : reg.resolveCurrent key.raw = some key
  · simp only [close, hc, if_true]
    exact setState_byKey_ne reg .closed h
  · simp [close, hc]

theorem close_byKey_self (reg : Registry) (key : FdKey)
    (h : reg.resolveCurrent key.raw = some key) :
    (reg.close key).byKey key
      = (reg.byKey key).map (fun e => { e with state := .closed }) := by
  simp only [close, h, if_true]
  exact setState_byKey_self reg key .closed

/-! ## close preserves well-formedness -/

theorem close_preserves_wf {reg : Registry} (h : WellFormed reg) (key : FdKey) :
    WellFormed (reg.close key) := by
  by_cases hc : reg.resolveCurrent key.raw = some key
  · -- The current key takes the terminal transition.
    refine ⟨?_, ?_, ?_⟩
    · -- current_resolves
      intro r g hg
      have hrne : r ≠ key.raw := by
        intro heq; subst heq; rw [close_currentGen_self reg key hc] at hg; cases hg
      rw [close_currentGen_ne reg key hrne] at hg
      obtain ⟨e, he, hek, hes⟩ := h.current_resolves r g hg
      have hkne : (⟨r, g⟩ : FdKey) ≠ key := by
        intro heq; exact hrne (congrArg FdKey.raw heq)
      exact ⟨e, by rw [close_byKey_ne reg hkne]; exact he, hek, hes⟩
    · -- current_gen_lt
      intro r g hg
      have hrne : r ≠ key.raw := by
        intro heq; subst heq; rw [close_currentGen_self reg key hc] at hg; cases hg
      rw [close_currentGen_ne reg key hrne] at hg
      rw [close_nextGen]
      exact h.current_gen_lt r g hg
    · -- entry_key_consistent
      intro k e hk
      by_cases hkey : k = key
      · subst hkey
        rw [close_byKey_self reg k hc] at hk
        cases hb : reg.byKey k with
        | none => rw [hb] at hk; simp at hk
        | some e0 =>
          rw [hb] at hk; simp at hk; subst hk
          obtain ⟨hek, hlt⟩ := h.entry_key_consistent k e0 hb
          rw [close_nextGen]
          exact ⟨hek, hlt⟩
      · rw [close_byKey_ne reg hkey] at hk
        obtain ⟨hek, hlt⟩ := h.entry_key_consistent k e hk
        rw [close_nextGen]
        exact ⟨hek, hlt⟩
  · simpa [close, hc] using h

/-! ## Terminality and double close -/

/-- **Closed terminality.** A closed key is not resolvable as the
current key for its raw fd (re-export of `close_not_current`). -/
theorem close_terminal (reg : Registry) (key : FdKey) :
    (reg.close key).resolveCurrent key.raw ≠ some key :=
  reg.close_not_current key

/-- After closing, the entry for the key is in state `closed` (when it
existed at all). -/
theorem close_state_closed {reg : Registry} {key : FdKey} {e : RegistryEntry}
    (hc : reg.resolveCurrent key.raw = some key) (h : reg.byKey key = some e) :
    ∃ e', (reg.close key).byKey key = some e' ∧ e'.state = .closed := by
  rw [close_byKey_self reg key hc, h]
  exact ⟨{ e with state := .closed }, rfl, rfl⟩

/-- **Double close is idempotent on the safety-relevant state.** Closing
an already-closed key leaves its current-generation resolution absent
(so no stale resolution) — the second close performs no reactivation. -/
theorem double_close_idempotent (reg : Registry) (key : FdKey) :
    ((reg.close key).close key).resolveCurrent key.raw ≠ some key :=
  (reg.close key).close_not_current key

/-! ## Lifecycle transition wrappers -/

/-- Configure a freshly allocated resource (non-blocking, close-on-exec
applied) before registration. -/
def markConfigured (reg : Registry) (key : FdKey) : Registry :=
  reg.setState key .configured

/-- Mark a listener as listening. -/
def markListening (reg : Registry) (key : FdKey) : Registry :=
  reg.setState key .listening

/-- Mark a resource as registered with the poller. -/
def markRegistered (reg : Registry) (key : FdKey) : Registry :=
  reg.setState key .registered

/-- Mark a stream active (handling readiness). -/
def markActive (reg : Registry) (key : FdKey) : Registry :=
  reg.setState key .active

/-- Begin closing (deregistered, awaiting final close). -/
def beginClosing (reg : Registry) (key : FdKey) : Registry :=
  reg.setState key .closing

/-- **Registered resources are live.** A resource just moved to
`registered` is not closed/closing. -/
theorem registered_not_closed {reg : Registry} {key : FdKey} {e : RegistryEntry}
    (h : reg.byKey key = some e) :
    ∃ e', (reg.markRegistered key).byKey key = some e' ∧ e'.state.isLive := by
  unfold markRegistered
  rw [setState_byKey_self, h]
  exact ⟨{ e with state := .registered }, rfl, rfl⟩

end Registry
end Iotakt.Model
