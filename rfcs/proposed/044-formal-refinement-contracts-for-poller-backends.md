# RFC 044: Formal Refinement Contracts for Poller Backends

- **Status:** Proposed
- **Intended phase:** v0.2+ proofs
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines a refinement-contract pattern for poller backends, inspired by Henret's backend-contract style.

## 2. Motivation

Iotakt will have at least one fake poller and one native epoll backend, with kqueue planned later. Without a shared contract, each backend can diverge subtly while still compiling.

A formal contract lets iotakt say what all backends must preserve at the model boundary.

## 3. Contract shape

Define a Lean typeclass or structure for poller behavior:

```lean
structure PollerBackend where
  State      : Type
  init       : IO State
  register   : State -> FdKey -> InterestSet -> IO PollerResult
  modify     : State -> FdKey -> InterestSet -> IO PollerResult
  deregister : State -> FdKey -> IO PollerResult
  wait       : State -> Timeout -> IO (List NativeReadyEvent)
```

The native backend may be effectful, but its returned events must be normalized before entering the pure translator.

## 4. Pure contract predicates

```lean
def EventsWellFormed
  (registry : Registry)
  (events : List NativeReadyEvent) : Prop :=
  -- every event either resolves to a current raw fd or will be dropped
  True

def BackendRespectsInterest
  (registry : Registry)
  (event : NativeReadyEvent) : Prop :=
  -- readiness kind must be compatible with registered interest after normalization
  True
```

The exact formal definitions should be refined in implementation RFCs, but the contract must at minimum support stale-event dropping and interest filtering.

## 5. Fake poller role

The fake poller is the reference backend for proofs and deterministic tests. It may generate arbitrary event sequences, including stale events, duplicate events, and contradictory events. The translator must remain safe.

## 6. Native backend role

Native backends are tested against the contract; they are not fully proven. Their assumptions belong in the proof/trust/test matrix.

## 7. Required backend obligations

```text
- never retain Lean object pointers
- return only normalized primitive event records
- expose errors explicitly
- support deregistration before close
- allow duplicate and stale events to be safely handled by Lean translator
```

## 8. Proof targets

```text
Translator safety independent of backend honesty:
  Even if backend returns stale or duplicate events, translator does not inject invalid actor messages.

Backend conformance tested:
  Native epoll/kqueue tests demonstrate expected common behavior but do not replace translator safety proofs.
```

## 9. Acceptance criteria

- A backend contract document exists before adding kqueue.
- Fake poller implements the contract reference behavior.
- epoll backend has conformance tests mapped to contract obligations.
- The proof/trust/test matrix identifies which obligations are proven vs tested vs assumed.
