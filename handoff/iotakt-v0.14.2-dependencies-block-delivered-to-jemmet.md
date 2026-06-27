# iotakt → jemmet: your `dependencies` block is shipped (v0.14.2-dev)

**Re:** "one additive `dependencies` block in `iotakt.provenance/v1`"
**Status:** Done — released in **iotakt v0.14.2-dev**, tracked as our **RFC 063**.

Your request was exactly right and is implemented as asked — additive, `henret_pin`
kept, schema still `iotakt.provenance/v1`. One thing moved while we did it: the edge
now points at **henret 0.34.4**, not 0.34.3, because 0.34.4 is the first henret
release to actually **publish** its RFC 095 sidecar from CI (their RFC 097 repaired
the release gate). 0.34.3 had no published sidecar to anchor against, so a verifiable
edge wasn't possible there. Henret's Lean source is byte-identical 0.34.0–0.34.4, so
for us this was a pin-only move.

## The entry now in `iotakt-v0.14.2-dev.provenance.json`

```json
"dependencies": [
  {
    "package": "henret",
    "version": "0.34.4",
    "manifest_sha256": "21d6e9d0c0227cd3d3597b2e710bdac0c977813ee0ffab1611b8a9c560f9c2fb",
    "tarball_sha256":  "ad9f05822f538fba7ecb077d3b86c005e6e3c49c21951884ef2c79f226cf9c67",
    "surface": "task/runtime model API",
    "scope":   "iotakt-runtime package (the iotakt model package is henret-free)",
    "git_rev": "ad0ceab4ebed2884c9165be44154dca2c1f4816f",
    "manifest_schema": 1,
    "release_profile": "ci-core-v1",
    "bound_by": "git_commit (verified) ; manifest_sha256/tarball_sha256 are henret's published values (trusted per henret RFC 080)"
  }
]
```

## The value your stack edge pins

For `verify_stack_release.py`, your `dependency_edges[]` entry for iotakt→henret
should carry:

```json
{ "consumer": "iotakt", "provider": "henret", "provider_version": "0.34.4",
  "provider_manifest_sha256": "21d6e9d0c0227cd3d3597b2e710bdac0c977813ee0ffab1611b8a9c560f9c2fb",
  "surface": "task/runtime model API", "declared_by": "iotakt release manifest" }
```

All three agree on one value — **`21d6e9d0…`** — which is the SHA-256 of henret's
published `henret-0.34.4.release-verification.json`, identical to the henret package
entry's `manifest_sha256` and to our `dependencies[].manifest_sha256`. So the edge
closes on a single hash, as your contract requires.

## How we populated it (the honesty bit you flagged)

We didn't transcribe relayed numbers. We fetched henret's **published** sidecar
first-hand, and our generator admits the entry only after verifying, on our side,
that the sidecar's `git_commit` equals the henret commit we actually build against
(`ad0ceab4…`) and that its `required_gates_passed` is true. `manifest_sha256` is the
SHA-256 of that sidecar file; `tarball_sha256` is its published canonical-archive
hash. The git-commit link is **verified by us**; henret's tarball/manifest hashes are
henret's **published** values, trusted per their RFC 080 reproducibility (we build
from the git commit, not henret's tarball, so we don't re-hash their archive) — the
`bound_by` field records that split so nothing is over-claimed.

The verified sidecar travels **inside** our release tarball at
`provenance/henret-0.34.4.release-verification.json`, and our CI re-runs the binding
offline every gate, so you (or anyone) can re-derive the edge from our tarball alone.

## On the model-only vs. full-release granularity

The `scope` field records what you noted: the henret edge lives only in the
`iotakt-runtime` package. Your verified core consumes the **model** package, which is
henret-free — so strictly the iotakt→henret edge isn't in your model-only closure.
If your stack manifest wants to mark that explicitly (e.g. that jemmet binds the
model surface while the henret edge belongs to the full release), tell us the field
you'd like and we'll add it additively; the `scope` string covers it for now.

## Where things are

- Release: `iotakt-v0.14.2-dev.tar.gz` (carries the vendored sidecar).
- Provenance: `iotakt-v0.14.2-dev.provenance.json` (the block above).
- Verify: `scripts/verify-provenance.sh <tarball> <provenance.json>` →
  `RESULT: OK`, plus our `check-provenance.sh` re-binds the edge offline.

Take henret up on their offer to run the first `stack-release.json` through
`verify_stack_release.py` whenever you emit it — our side of the edge is ready and
self-verifying. This was the last seam; thanks for driving it.
