# iotakt → kroopt: No-Go advisory and runtime-surface change notice

**Status.** DRAFT — prepared by the architect, pending maintainer approval before sending.
**From:** iotakt · **To:** kroopt
**Date:** 2026-08-27
**Re:** release freeze in force since 2026-07-13; changes to the `IotaktRuntime.*` surface
**Last correspondence:** 2026-06-30 (`iotakt-response-to-kroopt-harness-staging.md`)

## 0. Why this is late

iotakt entered a **No-Go release freeze on 2026-07-13** following an independent
architecture/security review. jemmet was notified on 2026-07-14. **kroopt was not**, and
that is our error, not an oversight of your importance. Six weeks passed in which you may
have continued to plan against a surface we already knew was changing. If that cost you
work, tell us and we will prioritize whatever unblocks you.

## 1. Decision

Release publication, v1.0 promotion, and **any downstream recommendation of the
runtime/native surface** are frozen. The freeze is not a schedule slip: an independent
review found six blocking defects, of which the security-relevant ones were real.

Nothing about this changes a published artifact. Our immutability policy stands —
`0.14.6` and every earlier tag remain frozen and their hashes remain valid anchors. The
freeze governs **what we recommend you adopt**, not what already exists.

## 2. What this means for your pin

The RFC 015 harness was staged against release `0.14.6` / commit
`c6334e58927cf17973d3391e1304c697acee2d01`. That revision **predates the entire
remediation**. Please treat any pin of the *runtime* surface at that revision as
provisional and not endorsed by us.

Please confirm, so we can size your exposure precisely:

1. which iotakt release your build currently resolves;
2. whether you bind only `Iotakt.Model.*` / `Iotakt.Api`, or also `IotaktRuntime.Loop`; and
3. whether any of it is on a path you would consider production or externally exposed.

Our understanding from your 0.14.5 consumer review is that your model-side binding is
`Iotakt.Model.*` / `Iotakt.Api` and that the live-loop link is `IotaktRuntime.Loop`, with
the adapter node itself reconciled as jemmet's per our 2026-06-30 decision (DEC-019). If
that is no longer accurate, correct us rather than working around it.

## 3. Disclosure regarding published artifacts

You pin our archive hashes, so you are entitled to this: the review found that
`scripts/ci.sh` **could not return a nonzero exit status** when a required step failed,
and that our release workflow runs that script as its release gate before packaging and
publishing. The reviewer observed the gate at `c6334e5` reporting `27 passed, 1 failed`
while exiting 0. The failing step was an echo-server smoke test, not a model, proof, or
native-boundary check.

We are not aware of any defect in a published archive's *contents*, and the archives are
built by CI from a clean checkout, so ignored local material cannot have entered them.
What we cannot honestly claim is that the gate qualifying those artifacts was capable of
blocking them. RFC 067 makes the gate fail-closed and adds a self-test that proves it.
That fix is forward-looking; it does not retroactively re-qualify what shipped. If your
stack verifier records a gate-passed assertion sourced from us for any published iotakt
version, treat that assertion as unproven rather than false, and tell us if you need it
formally withdrawn.

## 4. Runtime-surface changes you should plan for

These are decided and partly implemented. They will land before any release we ask you to
adopt, and they are breaking for a `IotaktRuntime.Loop` consumer.

**Typed effect results (RFC 064 — accepted).** Every stable effectful operation now
returns `IO (Except EffectError α)`. `enableWrite`, `disableWrite`, `recvAck`, `sendAck`,
and `closeConnection` changed signature. A stale, forged, negative, or out-of-range
`FdKey` is a typed no-effect failure — it can no longer reach a native call. This closes a
confused-lifetime defect in which a retained key could close a reused fd belonging to
another connection.

**Enforced receive bounds (RFC 065 — code complete).** `recvAck` rejects requests above
`DriverConfig.maxReadBytes` and above the native length ceiling, with typed errors, before
allocation or syscall. Requests are rejected, never silently shortened.

**Returned-event authority (RFC 066 — in progress).** Returned events become the single
authoritative channel for external consumers. There is no parallel Henret mailbox copy,
and one loop never has two readiness sinks.

**Listener identity and accept attribution (RFC 070 — in progress).** This is the one that
touches the staged harness directly. The accepted-event shape you were handed —
`newConnection (FdKey, rawFd)` — **is being withdrawn**. Stable accepted events carry a
generation-safe listener key and connection key and expose **no raw fd**:

```lean
| newConnection (listener : ListenerKey) (connection : FdKey)
```

If your side of the standup seam consumes the raw fd, that code will not survive the
change. Please do not build further against the current shape.

## 5. RFC 015 standup

iotakt's staged half stands, but it is **on hold** and its seam contract will change under
RFC 070. We are not asking you to sequence anything against it until the runtime surface
regains Go status. Your TLS engine work is unaffected by all of the above; the boundary
decision that iotakt exposes only a generic transport with no TLS-aware entry point is
unchanged and not under review.

## 6. Still open: provenance schema direction

The question you and jemmet both raised — stay on `iotakt.provenance/v1` versus adopting
henret's `manifest_schema 1` — remains undecided. RFC 068 will coordinate any schema move
with downstream verifiers rather than changing it unilaterally. If you have a preference
now, this is a good moment to state it; it is cheaper to settle before the packaging work
lands than after.

## 7. What we will send, and when

No version, commit, archive hash, sidecar hash, or Go record is available. Version
selection happens only after an independent requalification review records a written Go
(RFC 033). When it does, you will receive the exact model/runtime compatibility statement,
Lake dependency syntax, toolchain requirements, archive and sidecar hashes, and the
retained gate evidence — in one message, not in pieces.

Until then: **do not adopt, pin, or recommend the iotakt runtime surface.**

## 8. What we are asking of you

1. The three confirmations in §2.
2. Whether you need the §3 gate assertion formally withdrawn.
3. Your position on §6, if you have one.
4. Notice of anything you have already built against `newConnection (FdKey, rawFd)`.
