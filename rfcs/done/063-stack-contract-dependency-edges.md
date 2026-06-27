---
status: done
track: release-provenance
project: iotakt
scope_class: provenance-schema-additive
implemented_in: v0.14.2-dev
---

# RFC 063: Stack-Release-Contract Dependency Edges in `iotakt.provenance/v1`

**Status.** Implemented (v0.14.2-dev). Additive to `iotakt.provenance/v1` (schema
stays `v1`). Raised by the jemmet team to make the iotakt→henret edge verifiable
under henret's RFC 096 stack release contract.

## Summary

Add an additive `dependencies` array to `iotakt.provenance/v1` that declares, by
hash, the henret release iotakt built against — in the per-package shape henret's
RFC 096 defines (`package`, `version`, `manifest_sha256`, `tarball_sha256`,
`surface`). This is the ground truth henret's `verify_stack_release.py` cross-checks
the iotakt→henret edge against when jemmet composes the stack manifest. The existing
`henret_pin` (git commit) is **kept** as a second anchor; nothing in the prior schema
changes.

## Motivation

henret publishes a per-release RFC 095 release-verification sidecar
(`henret-<v>.release-verification.json`, `manifest_schema 1`). RFC 096 closes the
stack by checking each dependency edge against a `dependencies[]` entry in the
**consumer's** own manifest, matched on `manifest_sha256`. `iotakt.provenance/v1`
recorded the henret link only as `henret_pin` (a git commit), which RFC 096 does not
cross-reference — so the edge had nothing to verify against and the stack manifest
could not close. jemmet, the stack integrator, asked for exactly this one field.

## Design

### D1 — Additive `dependencies` array

```json
"dependencies": [
  { "package": "henret", "version": "0.34.4",
    "manifest_sha256": "<sha256 of henret-0.34.4.release-verification.json>",
    "tarball_sha256":  "<henret canonical-archive sha256>",
    "surface": "task/runtime model API",
    "scope":   "iotakt-runtime package (the iotakt model package is henret-free)",
    "git_rev": "ad0ceab4…" } ]
```

`package`/`version`/`manifest_sha256`/`tarball_sha256`/`surface` are the RFC 096
required fields. `scope`/`git_rev` are additive extras that tie the entry to
`henret_pin` and record that only the runtime tree depends on henret. The model
package remains dependency-free; a model-only consumer (jemmet's verified core) never
resolves this edge.

### D2 — Derive-and-verify, never transcribe (the honesty rule)

The two henret hashes are **derived** from henret's **published** RFC 095 sidecar,
which iotakt **vendors** under `provenance/henret-<v>.release-verification.json`, and
admitted **only** after binding checks:

1. `manifest_sha256` = SHA-256 of the vendored sidecar file (= the value jemmet's
   stack edge and henret's manifest cross-reference).
2. `tarball_sha256` = the sidecar's published canonical-archive hash.
3. **Binding (verified by us):** the sidecar's `git_commit` MUST equal
   `henret_pin.rev` (the commit iotakt actually builds against). `gen-provenance.sh`
   aborts otherwise; `check-provenance.sh` re-verifies offline against the vendored
   sidecar every CI run.
4. The sidecar's `required_gates_passed` MUST be true.

iotakt does not hand-enter or transcribe relayed hashes. The git-commit link is
**TESTED** by iotakt; `manifest_sha256`/`tarball_sha256` are henret's **published**
values, **TRUSTED** per henret's RFC 080 reproducible-build claim (iotakt builds from
the git commit, not henret's tarball, so it does not independently re-hash henret's
archive). The `bound_by` field records this split.

### D3 — Vendored sidecar travels in the release

The verified henret sidecar is committed under `provenance/` and ships inside the
iotakt release tarball, so any consumer can re-run the binding offline from the
tarball alone. It is henret's artifact, not iotakt source, so it is excluded from
`source_tree_sha256` (which covers iotakt's buildable source only).

## Non-Goals

- Not adopting henret's `manifest_schema 1` or replacing `iotakt.provenance/v1`.
- Not changing or removing `henret_pin`.
- No behavior change to iotakt; no change requested of henret.

## Acceptance Criteria — all met in v0.14.2-dev

- **A.** `dependencies[]` present with the five RFC 096 required fields. ✓
- **B.** `manifest_sha256` equals SHA-256 of the vendored henret sidecar
  (`21d6e9d0…` for 0.34.4) — the value jemmet pins as `provider_manifest_sha256`. ✓
- **C.** `tarball_sha256` equals henret's published canonical-archive hash
  (`ad9f0582…`). ✓
- **D.** Generation aborts if the sidecar `git_commit` ≠ `henret_pin.rev`. ✓
- **E.** `check-provenance.sh` re-verifies the edge offline (sidecar hash, git_commit
  binding, tarball hash) on every CI run; wired into the gate. ✓
- **F.** `henret_pin` retained unchanged; schema stays `iotakt.provenance/v1`. ✓

## As built

henret pin moved 0.34.3 → **0.34.4** because 0.34.4 is the first henret release to
publish its RFC 095 sidecar from CI (RFC 097 release-CI repair); Henret's Lean source
is byte-identical 0.34.0–0.34.4, so the bump is a pin-only change. Edge anchored at
sidecar `21d6e9d0…`, henret commit `ad0ceab4…`, surface "task/runtime model API".

## Follow-up (v0.14.3-dev) — `package` field for the shared verifier

henret's `verify_stack_release.py` resolves every manifest by hash and asserts
`manifest["package"] == name`. `iotakt.provenance/v1` carried iotakt's name only under
`project`, so the verifier rejected the iotakt node. v0.14.3-dev adds a top-level
`"package": "iotakt"` **alongside** `project` (both retained; schema stays `v1`,
additive). `check-provenance.sh` asserts it. Per RELEASES.md immutability, this shipped
as a new version rather than re-cutting v0.14.2-dev.

## Open Questions

None. If jemmet's stack contract later wants additional iotakt fields (detached
signature, per-target hashes), they extend `dependencies[]` additively without a
schema break.
