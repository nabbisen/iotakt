/-!
# Iotakt.Model.Update

The single map-mutation primitive used throughout the iotakt model.

Henret keeps every per-id map mutation behind one `upd` helper so that
preservation proofs stay uniform (`Henret.Core.Id`). iotakt follows the
same discipline, but generalised to any key type with decidable
equality, because iotakt maps are keyed by `RawFd` and `FdKey`, not
just `Nat`.
-/

namespace Iotakt.Model

/-- Update a total function-map at one key. Every state change to a
per-key map in the iotakt model goes through `upd`, keeping the
preservation lemmas mechanical. -/
def upd {K : Type} [DecidableEq K] {α : Type} (f : K → α) (k : K) (v : α) : K → α :=
  fun j => if j = k then v else f j

@[simp] theorem upd_self {K : Type} [DecidableEq K] {α : Type}
    (f : K → α) (k : K) (v : α) : upd f k v k = v := by
  simp [upd]

@[simp] theorem upd_ne {K : Type} [DecidableEq K] {α : Type}
    (f : K → α) {k j : K} (v : α) (h : j ≠ k) : upd f k v j = f j := by
  simp [upd, h]

end Iotakt.Model
