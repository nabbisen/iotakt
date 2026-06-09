import Iotakt.Model

/-!
# Iotakt.Proofs

Aggregator for iotakt's machine-checked safety theorems (RFC 014).

The theorems themselves live next to the definitions they constrain
(Registry well-formedness, lifecycle terminality, translator
no-stale/no-unknown/owner/interest soundness, coalescing flood bound).
This module re-exports them under a single target so `lake build
Iotakt.Proofs` checks the entire proven core in one command, and so the
proof/trust/test matrix (`docs/proof-trust-test-matrix.md`) has a stable
import surface.

The headline PROVEN properties:

* `Registry.allocate_preserves_wf`, `Registry.close_preserves_wf` —
  the registry invariant survives every modeled transition;
* `Registry.allocate_fresh_gen`, `Registry.close_not_current`,
  `Registry.double_close_idempotent` — generations are strictly fresh and
  closing is terminal, so a raw fd can never resolve to a stale owner;
* `Registry.translate_no_unknown`, `Registry.translateKeyed_stale`,
  `Registry.translate_injectable_owner`, `Registry.translate_readable_interest`,
  `Registry.translate_writable_interest`, `Registry.translate_injectable_live`
  — every injected event targets the live registry owner of the current
  key and matches a registered interest (or is fatal); unknown/stale
  events are dropped;
* `CoalesceState.step_twice_coalesced`, `CoalesceState.ack_clears`,
  `CoalesceState.deliver_after_ack` — at most one outstanding readiness
  per fd/kind, cleared by ack, with progress preserved.

The Henret-bridge theorem `Iotakt.Bridge.inject_ok_of_mailbox` (every
guarded inject returns `.ok`) lives in `Iotakt.Bridge.Driver` because it
depends on Henret; it is the formal mitigation of Henret v0.6.0's
`inject` mailbox precondition.
-/

namespace Iotakt.Proofs

/-- Sanity façade: a single name whose elaboration forces the proven
core to typecheck. `True` by construction; depend on this in CI to
require the proof modules. -/
theorem core_is_checked : True := trivial

end Iotakt.Proofs
