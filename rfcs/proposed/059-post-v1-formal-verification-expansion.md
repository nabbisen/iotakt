---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 059: Post-v1 Formal Verification Expansion

## Summary

This RFC defines post-v1 expansion themes for iotakt's formal verification work. v1 should focus on
small, high-value invariants: fd identity, registry uniqueness, stale-event rejection, interest
soundness, lifecycle transitions, and deterministic bridge behavior. After v1, the project may expand
proofs toward refinement contracts, trace equivalence, buffer ownership models, and backend-specific
simulation relations.

## Motivation

A Lean ecosystem library benefits from credible proof claims, but over-proving early can paralyze
systems implementation. Post-v1 proof work should follow evidence from implementation and tests,
not speculative ambition.

## Goals

- Identify proof themes worth pursuing after v1.
- Avoid overclaiming native/backend correctness.
- Provide a route from model tests to refinement contracts.
- Keep the proof/trust/test matrix current.

## Non-goals

- No claim of verified POSIX/kernel behavior.
- No full verification of C code.
- No verification of TCP, TLS, DNS, QUIC, or HTTP semantics inside iotakt.
- No requirement that all post-v1 features are proven before experimentation.

## Proof expansion themes

### Trace preservation

Show that bridge operations preserve an abstract trace relation:

```text
poller events + registry state
  -> normalized iotakt events
  -> Henret messages
```

### Backend refinement contracts

For fake, epoll, kqueue, and later backends, define what it means for a backend to conform to the
normalized event vocabulary.

### Coalescing correctness

Prove that coalescing suppresses duplicate readiness notifications without losing the information
that some readiness hint exists.

### Buffer ownership model

For future `recvInto`, model checked-out buffers, unique ownership, and valid-prefix discipline.

### Resource authority model

For capability-style fd handles and fd passing, prove authority cannot be used before registration or
after revocation/close in the model.

## Suggested theorem targets

```text
translate_never_injects_unknown_fd
translate_drops_stale_generation
interest_sound_for_readiness
coalescing_pending_bound
close_removes_injectable_resource
backend_trace_refines_model_trace
buffer_checkout_unique
recvinto_returns_buffer_to_owner
```

## Proof workflow

1. Keep executable model as the source of truth.
2. Add deterministic examples before proofs.
3. Prove local invariants first.
4. Add refinement contracts only after API stabilizes.
5. Update proof index and proof/trust/test matrix with every new claim.

## Architecture gap management

This RFC tracks the gap:

```text
G-PROOF-POSTV1: v1 proves model-level safety properties, but backend conformance remains tested/assumed.
```

Mitigation:

- Better fake poller coverage.
- Native conformance tests.
- Trace replay and differential testing.
- Backend refinement contracts where realistic.

## Acceptance criteria

- No post-v1 feature may claim verification unless the proof index names the theorem.
- The proof/trust/test matrix remains release-gated.
- Proof work prioritizes invariants that reduce real implementation risk.
- Backend-specific assumptions remain visible and auditable.
