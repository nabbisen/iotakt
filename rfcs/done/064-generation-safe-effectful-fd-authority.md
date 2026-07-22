# RFC 064 — Generation-safe effectful fd authority

**Status.** Implemented — accepted at reviewed head `e3a6ca8` (2026-07-22)
**Tracks.** Architecture review B1 and N3; Go evidence 1.
**Touches.** `Iotakt.Model.Registry`, `Iotakt.Api`, `IotaktRuntime.Loop`, native-operation wrappers, proofs, fd-reuse tests.

## Summary

Make `FdKey(raw, generation)` authoritative for every effectful operation, not only
for pure event translation. A stale, forged, negative, or out-of-range key must not
read, write, modify interest, deregister, close, or mutate registry state.

This RFC is the immediate correctness repair for the current public surface. RFC 043
may later introduce an opaque capability type and delegation policy, but it is not a
substitute for checking the existing `FdKey` API now.

## Goals

- Introduce one checked resolution path used before every native fd effect.
- Require the key to be current, live, stored under the same key, and of an allowed
  resource kind.
- Return one stable domain-specific `EffectError` result that distinguishes authority,
  lifecycle, resource-kind, and native failures.
- Leave native and model state unchanged when validation fails.
- Prevent `Registry.close staleKey` from clearing a newer generation's mapping.
- Resolve the documented double-close contract explicitly.

## Non-goals

- Do not redesign Henret actor identity.
- Do not add protocol-specific authority.
- Do not complete RFC 043's future delegation model unless the checked-key repair
  requires an opaque internal token.

## External design

All stable effectful operations return `IO (Except EffectError α)`. The error type
contains at least `invalidKey`, `staleKey`, `invalidRawFd`, `wrongKind`, `inactive`,
and `nativeError IoErrno`; callers never need to infer an authority failure from an
unstructured native integer. All such operations pass through a shared resolver with
semantics like:

```lean
resolveEffectKey
  (registry : Registry)
  (key : FdKey)
  (allowedKinds : List ResourceKind)
  : Except EffectError RegistryEntry
```

Success requires:

1. `key.raw` is representable by the native fd type and is non-negative;
2. `registry.resolveCurrent key.raw = some key`;
3. `registry.lookup key = some entry` and `entry.key = key`;
4. `entry.state.isLive = true`; and
5. `entry.kind` is valid for the requested operation.

`enableWrite`, `disableWrite`, `recvAck`, `sendAck`, `closeConnection`, and RFC 070's
`closeListener` must use this resolution. A failure returns a typed result and
performs no native call.

This result shape is the R0 decision for the stable API. Construction opacity is
deferred to RFC 043; until then, construction-safe validation is mandatory at every
effect boundary and no unchecked compatibility shim is stable.

## Effect-path inventory

Implementation must generate a repository-derived inventory of every stable entry
point that can cause a native fd effect. A reviewer-maintained classification file
records each path as `checked-stable`, `unsafe-internal`, or `unreachable`, names the
resolver/native call and test identifier, and fails verification when a discovered
path lacks a row. Lean imports are transitive and do not provide declaration hiding:
an `unsafe-internal` path must therefore either be a `private` declaration or carry
an explicit `unsafe` name/`Unsafe` namespace at every downstream-callable escape
point. The stable API does not re-export these names as checked operations. The
inventory gate rejects an unmarked non-private unsafe row, and a downstream negative
compile probe requires the former unmarked escape names to be unavailable.
`unreachable` rows require a cited proof or structural justification.

The R1 inventory records RFC 070's not-yet-implemented `closeListener` as
`unreachable`, citing the accepted RFC as its structural justification. Before RFC
070 can be accepted in R2, that row must become `checked-stable` and bind to stale,
forged, invalid-range, wrong-kind, double-close, and raw-fd-reuse tests. RFC 064
acceptance does not grant future stable operations an inventory exemption.

## Model and lifecycle changes

`Registry.close` must clear `currentGen key.raw` only when the supplied key is the
current key. Closing an unknown or stale key either returns an explicit model error
or is a proven no-op; the chosen behavior must agree with the public result type.

The double-close rule must be one coherent decision across requirements, model, C,
tests, and documentation. The preferred policy is visible rejection at the stable
API and no second native `close` call.

## Implementation sequence

1. Add model-level checked resolution and error types.
2. Prove stale close preserves the current generation and unrelated entries.
3. Route interest modification and close through checked resolution.
4. Route recv/send helpers through checked resolution and enforce kind/state rules.
5. Validate native fd conversion without `Int.toNat` truncation.
6. Update stable API documentation and migration notes for changed result types.

## Proof obligations

- A stale close cannot change `currentGen` or the entry for a newer generation.
- Invalid resolution does not mutate the registry.
- Successful resolution returns the current live matching entry.
- Checked operations never expose a raw fd derived from a negative or out-of-range
  model value.

## Test obligations

- Model tests for unknown, stale, closed, negative, and out-of-range keys.
- Live fd-reuse tests where stale close/recv/send/interest operations cannot affect
  the new owner.
- Forged-key tests for every stable effectful operation.
- `closeListener` authority tests required by RFC 070 before that operation becomes
  stable.
- An inventory completeness test discovers the stable native-effect surface and
  verifies every row's classification and enforcement test.
- Double-close test proving there is no second native close.
- Downstream compile tests for the final typed result surface.

## Security considerations

This RFC closes a cross-actor confused-lifetime vulnerability. No compatibility
shim may preserve unchecked raw-fd authority on the stable path. Any low-level raw
escape hatch must be explicitly named unsafe, excluded from the documented stable
API, and outside the proof claim. Transitive name resolution is not represented as
visibility isolation; the enforceable boundary is private declarations plus
mandatory `unsafe`/`Unsafe` naming and compile-time regression checks.

## Dependencies and follow-ups

- Blocks RFCs 066, 033, and any release/v1.0 claim.
- RFC 029 supplies fault scenarios after the checked operation seam exists.
- RFC 043 remains a post-remediation capability-hardening follow-up.
- RFC 070 reuses this resolver and must update the effect inventory when
  `closeListener` becomes reachable.

## Acceptance criteria

- Every stable effectful fd operation uses the shared checked resolver.
- Required proofs compile with no new `sorry`, `admit`, or project `axiom`.
- Model and live fd-reuse tests pass for all affected operations.
- The effect-path inventory covers every stable native-effect path, has no
  unclassified entries, and binds every `checked-stable` row to a passing stale and
  forged-key test.
- Requirements, API stability docs, and proof/trust/test matrix state the same close
  and authority semantics.

## Open questions

- The exact internal representation of `EffectError` may evolve without weakening
  its stable variants or the no-effect authority-failure contract.
