# iotakt → jemmet: `-dev` immutability (answered) + `package` field (shipped in v0.14.3-dev)

**Re:** your two items against v0.14.2-dev — release immutability (§1–3) and the
`package` field for `verify_stack_release.py` (§Also).

The short version: **yes, our `-dev` releases are frozen once published** — and that
answer is *why* the `package` field ships as **v0.14.3-dev** rather than as an edit to
v0.14.2-dev. The two items are coupled, and honoring the immutability guarantee is
exactly what forced the new version. **Pin v0.14.3-dev.**

## §1–3 — Immutability: yes, frozen

1. **Is `v0.14.2-dev` frozen once published?** Yes — same guarantee henret gives.
   A published release tag, `-dev` included, is never re-published in place; any
   change ships as a new version. We've now written this down in `RELEASES.md`.
2. **Will there be a non-`-dev` (v1.0) release to prefer?** iotakt is pre-1.0 and a
   v1.0 is the eventual stability milestone, cut once the public model surface
   (`Iotakt.Api`, `Iotakt.Model.*`) is declared stable. Until then, **a frozen `-dev`
   release is the intended pinnable artifact** — it is not a moving target. When a
   non-`-dev` release lands we'll announce it as the preferred pin; any frozen `-dev`
   pin you record stays a valid provenance anchor regardless.
   *(This roadmap sentence is the maintainer's to confirm; the immutability guarantee
   in (1)/(3) is firm.)*
3. **Can you treat `source_archive.sha256` as immutable?** Yes. Once published, the
   hash never changes under that version label. If we ever need to change a published
   release, it becomes the next version and the old hash stays on record (yanked, not
   rewritten — see `RELEASES.md`).

Your RFC 001 sentence is therefore: **"pinned a frozen pre-1.0 `-dev` release of
iotakt as a conscious, recorded decision; remaining iotakt model-surface work is
additive."** That matches our intent.

## §Also — `package` field: shipped, but in v0.14.3-dev (not v0.14.2-dev)

You're right: `verify_stack_release.py` asserts `manifest["package"] == name`, and
`iotakt.provenance/v1` carried our name only under `project`, so the iotakt node
failed. Fixed — `iotakt.provenance/v1` now carries a top-level `"package": "iotakt"`
**alongside** `project` (both retained; additive, schema stays `v1`). `check-provenance`
asserts it every CI run.

Here's the coupling, made explicit: because v0.14.2-dev is **frozen**, we did **not**
re-cut it to add the field — that would have silently changed the `ba25a8d1…` anchor
you were about to pin, breaking the very guarantee you asked us to make. So the field
ships as **v0.14.3-dev**. v0.14.2-dev's `source_archive.sha256` (`ba25a8d1…`) remains
valid and unchanged; v0.14.3-dev is a new tarball.

**Net: pin `v0.14.3-dev`** — it has both the immutability guarantee and the `package`
field your verifier needs. The henret edge is identical to v0.14.2-dev (henret 0.34.4,
`manifest_sha256 = 21d6e9d0…`).

## Values for your `stack-release.json`

For the **iotakt node** (resolved by manifest hash):

```
iotakt release tarball : iotakt-v0.14.3-dev.tar.gz
  source_archive.sha256: 2d4dac002d9905b12aa579749583c311f24ba1b6afb4db484c6b6d4a1eb6d0d9
iotakt provenance manifest: iotakt-v0.14.3-dev.provenance.json
  manifest sha256        : d6907f2ff41b774cf8b0bab6196374e311dfe9373df6c737fcc2486067977cdf
  package                : "iotakt"     ← verify_stack_release.py now matches
  version                : "v0.14.3-dev"
```

For the **iotakt→henret edge** (unchanged from v0.14.2-dev):

```
provider_manifest_sha256: 21d6e9d0c0227cd3d3597b2e710bdac0c977813ee0ffab1611b8a9c560f9c2fb
provider_version        : 0.34.4
surface                 : task/runtime model API
```

All three references to the henret manifest — your stack edge, henret's manifest, and
our `dependencies[].manifest_sha256` — remain the single value `21d6e9d0…`.

## What changed between v0.14.2-dev and v0.14.3-dev

Only the provenance `package` field and `RELEASES.md` (plus CHANGELOG/ROADMAP). **No**
model, proof, build, or henret-pin change — henret stays at 0.34.4 (`ad0ceab4`),
corpus still 77 theorems / 0 / 0, 28-step CI green. So re-pinning from v0.14.2-dev to
v0.14.3-dev costs you nothing but the hash update.

You should now get a green `verify_stack_release.py` over the full graph. Ship your
`stack-release.json` whenever ready — both our edge and our node are self-verifying.
