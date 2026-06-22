---
status: done
track: release-provenance
project: iotakt
scope_class: release-process
---

# RFC 062: Release-Provenance Manifest and Stack-Release-Contract Participation

**Status.** Implemented (v0.13.4-dev)

## Summary

Publish a hashed provenance manifest alongside every iotakt release tarball, schema
`iotakt.provenance/v1`, mirroring Henret's RFC 080 release manifest. It anchors the
exact source archive, lake manifest, toolchain, a reproducible source-tree hash, the
pinned Henret revision, and the verification summary — so a downstream consumer
(jemmet) can verify the whole stack jemmet → iotakt → Henret down to the toolchain.

## Motivation

Henret already emits a hashed release manifest (`tarball_sha256`,
`lake_manifest_sha256`, `lean_toolchain_sha256`, gate hashes — RFC 080). iotakt
publishes no equivalent; its only provenance anchors are the git tag and the lake
manifest rev. jemmet's stack-release-contract needs a `SOURCE_ARCHIVE_SHA256`-
equivalent for iotakt to anchor its provenance the way it can Henret's. This is a
small, additive release-process artifact with high integration value and no impact
on the iotakt surface or proofs.

## Goals

- A machine-checkable provenance manifest published with each release tarball.
- Field alignment with Henret RFC 080 so the same verification tooling generalizes.
- A chain link to Henret provenance (the exact pinned rev).
- A reproducible source-tree hash independent of tar/gzip metadata.
- A consumer-runnable verification step.

## Non-Goals

- Cryptographic signing (left as an optional future field; see Open Questions).
- Changing the iotakt API, model, or proofs.
- A package registry or distribution mechanism beyond tarball + companion manifest.

## External Design

A companion file `iotakt-<version>.provenance.json` is published **next to** the
release tarball (not inside it, so it can carry the archive's own hash). Schema
`iotakt.provenance/v1`:

```json
{
  "schema": "iotakt.provenance/v1",
  "project": "iotakt",
  "version": "v0.13.3-dev",
  "source_archive": { "name": "...", "sha256": "...", "bytes": 0 },
  "lake_manifest_sha256": "...",
  "lean_toolchain": { "value": "leanprover/lean4:v4.15.0", "sha256": "..." },
  "source_tree_sha256": "...",
  "henret_pin": { "name": "henret", "type": "git", "inputRev": "0.34.0",
                  "rev": "63f10f48…", "url": "https://github.com/nabbisen/henret" },
  "verification": { "theorems": 77, "sorry": 0, "admit": 0, "project_axioms": 0,
                    "ci_steps": 26, "ci_checks": 333, "toolchain": "…" }
}
```

Field notes:
- `source_archive.sha256` anchors the exact published tarball.
- `source_tree_sha256` is an order-independent content hash over `Iotakt/**`, the
  lakefile, the lake manifest, and the toolchain file — reproducible regardless of
  archive timestamps, so a consumer can recompute it from source.
- `henret_pin` is the chain link: it records the exact Henret rev iotakt builds
  against, so jemmet can follow iotakt → Henret and verify Henret's own RFC 080
  manifest for that rev.
- `verification` records the gate result the release was certified under.

## Workflow

1. **Generate** (`scripts/gen-provenance.sh <version> <archive>`): emits
   `iotakt-<version>.provenance.json` from the repo state + the cut archive.
2. **Publish**: the manifest accompanies the tarball as a release deliverable.
3. **Verify** (`scripts/verify-provenance.sh <archive> <manifest>`): a consumer
   recomputes `source_archive.sha256` and confirms it matches; optionally recomputes
   `source_tree_sha256` from an unpacked tree.
4. **CI check**: a gate step asserts the `verification` counts in a freshly
   generated manifest match the live corpus (theorems / sorry / axiom) and that the
   schema is well-formed — preventing the manifest from drifting from reality.

## Public API Impact

None. This is a release-process artifact, not a code change.

## Native Boundary Impact

None.

## Henret Integration Impact

Consumes Henret's provenance only by reference (records the pinned rev). No build
or contract change. Aligns iotakt with Henret's RFC 080 so a single stack verifier
can walk both.

## Security Considerations

Introduces no new data flow, external integration, or auth logic; it **strengthens**
supply-chain integrity by giving consumers a tamper-evident anchor for the source
archive and a chain to the dependency's provenance. The manifest contains only
hashes and public version metadata — no secrets. Existing controls remain valid;
threat model updated only to note the new (positive) integrity control. Signing is
deferred (Open Questions).

## Proof / Test Obligations

- A CI step generates a manifest and asserts its `verification` block matches the
  live corpus (77 / 0 / 0) and that `source_tree_sha256` is stable across two runs.
- `verify-provenance.sh` round-trips: generate → verify passes; a mutated archive →
  verify fails.

## Trust / Assumption Changes

None to the proof TCB. Adds an integrity artifact consumers may rely on.

## Acceptance Criteria

- `scripts/gen-provenance.sh` and `scripts/verify-provenance.sh` exist and are
  documented.
- A provenance manifest is published with the release that ships this RFC.
- The CI gate verifies manifest/corpus consistency.
- Fields align with Henret RFC 080; `henret_pin` chains to the pinned rev.
- `docs/src` documents the schema and the verify workflow.

## Alternatives Considered

- **Git tag + lake rev only (status quo)**: rejected — no archive hash, so consumers
  cannot detect tarball tampering or anchor a specific build.
- **Embed the manifest inside the tarball**: rejected — cannot carry the archive's
  own hash; companion file is the standard (and Henret's) approach.
- **Reuse Henret's schema verbatim**: rejected — iotakt needs the `henret_pin` chain
  field and a `source_tree_sha256`; we align field *names/semantics* with RFC 080
  rather than copy the schema.

## Open Questions

1. Optional detached signature (`source_archive.sig`) — add a field now (nullable)
   or defer until a signing key exists? Leaning: reserve the field, defer signing.
2. Per-target hashes (model vs bridge) — likely after RFC 061 lands; until then a
   single source-tree hash suffices.
3. Whether jemmet's stack-release-contract wants additional fields (e.g. a combined
   stack digest); coordinate before this RFC is accepted.
