# iotakt → jemmet — response to integration questions

**iotakt:** v0.13.3-dev · henret pinned to git tag `0.34.0` (rev `63f10f48`) ·
Lean 4.15.0. All answers below were verified against real Lake behavior in this
toolchain, not asserted from documentation.

---

## Q1 — Offline consumption without editing iotakt's lakefile

**Confirmed: root-override precedence holds for a git-vs-path conflict. No iotakt
change is needed, and your vendored copy stays clean.**

We reproduced your exact scenario: a root package requiring
`henret from "../henret/henret-0.34.0"` (path) **and** `iotakt from "../iotakt"`,
where iotakt's own lakefile carries `require henret from git … @ "0.34.0"`. Result:

- The root's path require **won**. The consumer's `lake-manifest.json` resolved
  `henret` as `type: path → ../henret/henret-0.34.0`.
- **No GitHub fetch occurred** — there was no `cloning …/henret` line and no
  `henret` under `.lake/packages/`. Lake referenced your vendored tree in place, so
  it remains `MIRROR_CLEAN`.

Lake dedups dependencies by package **name**, and the root package's requirement
takes precedence over any transitive one. Since your root require and iotakt's
transitive require both name `henret`, yours wins outright — git-vs-path does not
change that.

**Two caveats, both easy to satisfy:**
1. Vendor the **same** henret your build needs. For the **bridge** (`Iotakt.Bridge`,
   which imports henret) the vendored copy must be API-compatible with the tag
   iotakt pins (`0.34.0`, rev `63f10f48`) — vendor that source to avoid API skew.
   For a **model-only** consumer this is moot (the model imports no henret — see Q2).
2. The override must come from the **root** package (jemmet). A sibling/transitive
   path require would not take precedence; the root one does.

We therefore do **not** think you need a git-vs-vendored toggle — root-override is
the idiomatic Lake mechanism and we verified it works for you. If you'd nonetheless
prefer an explicit switch insulated from any future Lake dedup-behavior drift, we
can add a config option (`-K henret_source=vendor|git`) to iotakt's lakefile; say
the word and we'll spec it. But it is not required for your hermetic build today.

---

## Q2 — Model-only resolution

**Today: no — henret is materialized at package-resolution time regardless of which
target you build. We can fix this properly with a package split; proposing it as an
RFC.**

Verified: a consumer requiring only `iotakt` (no root henret) and importing only
`Iotakt.Api` — the henret-free model surface — still triggered
`cloning https://github.com/nabbisen/henret` and listed `henret` in its manifest.
Lake resolves the **entire** dependency graph at configuration time, and iotakt's
`require henret` is unconditional and package-level, so it is materialized even for
a model-only build. A model-only consumer cannot currently resolve iotakt without
henret present.

This is a real build-boundary limitation, and it is exactly the case the project's
"workspaces" guideline anticipates. **Proposed RFC 061 — model/bridge package
split:**

- `iotakt` (model package): `Iotakt.Model`, `Iotakt.Api`, the fake poller, and the
  proofs — **no `require henret`**. A verified, henret-free dependency. Your core
  binds to this and resolves with henret entirely absent from the graph.
- `iotakt-bridge` (runtime package): `Iotakt.Bridge` (driver + henret integration)
  and the native epoll `extern_lib`; depends on the model package **and** henret.
  Consumers needing the OS reactor depend on this.

This gives you a clean source-level *and* resolution-level seam: the model carries
no henret, the bridge carries it where it belongs. It preserves the public API and
is additive for existing consumers (the bridge re-exports what the single package
exports today). Because it changes the build structure, it is RFC-level work under
"design before coding" — we'll file 061 on maintainer approval.

*Interim option, if you need it before 061 lands:* a config-gated henret require
(`-K with_henret=false` omits both the require and the bridge `lean_lib`). It works
but is less clean than the split; we'd prefer to do the split once rather than ship
a toggle we later remove. Your call on urgency.

---

## Q3 — Release provenance

**Agreed — adopting a provenance manifest aligned with henret's RFC 080. A first one
for v0.13.3-dev is attached; formalizing the contract as an RFC.**

A companion `iotakt-<version>.provenance.json` will be published **alongside** each
release tarball (not inside it, so it can carry the archive's own hash), schema
`iotakt.provenance/v1`:

- `source_archive` — name, `sha256`, byte size of the release tarball.
- `lake_manifest_sha256`, `lean_toolchain` (value + `sha256`).
- `source_tree_sha256` — order-independent content hash over `Iotakt/**`, the
  lakefile, the manifest, and the toolchain (a reproducible anchor independent of
  tar/gzip metadata).
- `henret_pin` — `{ type, inputRev: "0.34.0", rev: "63f10f48…", url }`. This is the
  key chain link: iotakt's provenance references the exact henret rev it pins, so
  you can verify the whole stack — **jemmet → iotakt (this manifest) → henret (RFC
  080 manifest)** — down to the toolchain.
- `verification` — `{ theorems: 77, sorry: 0, axiom: 0, ci_steps: 26, ci_checks:
  333, toolchain }`.

The attached `iotakt-v0.13.3-dev.provenance.json` is the concrete first instance.
We'll formalize the format and the publish-on-release process as **proposed RFC
062 — release-provenance manifest**, and we're glad to align its fields with your
stack-release-contract — if you want additional fields (e.g. a detached signature,
or per-target hashes), name them and we'll fold them into 062 before it's accepted.

---

## Summary

| # | Answer | iotakt action |
|---|--------|---------------|
| 1 | Root path-override **works** (tested); no fetch, vendored copy clean. | None required; optional `henret_source` toggle on request. |
| 2 | Model-only resolution **not** possible today (henret materialized at resolution). | Proposed **RFC 061** model/bridge split → henret-free model package. |
| 3 | **Yes**, adopting a provenance manifest. | First manifest attached; **RFC 062** to formalize; fields open to your contract. |

Nothing here requires a breaking change to the iotakt surface; Q1 needs nothing,
Q2 is an additive build-structure split, and Q3 is a new companion artifact.
