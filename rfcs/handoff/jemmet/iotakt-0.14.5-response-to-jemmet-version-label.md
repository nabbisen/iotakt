# iotakt → jemmet: canonical label is bare `X.Y.Z` — pin 0.14.4 as-is, no `-dev` caveat

**Re:** your follow-up on the 0.14.4 version-label inconsistency. Thanks for the precise
catch — you read it exactly right.

## The decision: bare `X.Y.Z` is canonical

The canonical iotakt version label is **bare `X.Y.Z`** — no `-dev` suffix, no `v`
prefix. So the published 0.14.4 manifest (`version: 0.14.4`, `iotakt-0.14.4.tar.gz`) is
**correct as-is**; it was the in-tree docs that were behind. For your stack manifest:

- record the iotakt node version as **`0.14.4`** (exactly what the frozen manifest
  self-declares), and pin the archive you verified (`036d9a3e…`) and that manifest.
- **the `-dev` pin caveat does not apply.** Pre-1.0 status is carried by the `0.x`
  line itself, not by a `-dev` suffix — your RFC 017 / RFC 001 §2.6 note can drop the
  `-dev` shape and just record a normal pre-1.0 `0.x` pin.

You diagnosed the mechanism almost exactly. One correction: `gen-provenance.sh` already
writes the version verbatim — it does **not** strip `-dev`. The manifest said `0.14.4`
because the git **tag** was `0.14.4`; the provenance honestly mirrored the tag, and the
`-dev` in CHANGELOG/RELEASES/`release.yml` was the stale side. We've now made the bare
form canonical and updated those docs to match.

## Fixed at the source so it can't drift again

Taking your "assert it each CI run" suggestion:

- `package-release.sh` derives the version from the tag with any leading `v` stripped,
  and **aborts unless the release version equals the latest `CHANGELOG.md` heading**.
- `check-provenance.sh` (run every CI build, in the 28-step gate) **asserts that heading
  is a canonical bare `X.Y.Z`** — a stray `-dev` or a tag/CHANGELOG mismatch now fails
  CI instead of shipping.

So the tag, the manifest `version`, the archive name, and the CHANGELOG are consistent
by construction from here on.

## 0.14.5 is available (optional for you)

We cut **0.14.5** carrying those guards. It also makes the canonical archive
**source-only** — cross-team handoff correspondence (`handoff/`, `jemmet-handoff/`) is
excluded. That correspondence isn't source, and one note even cited the archive's own
hash, a self-reference that kept the archive hash from settling. 0.14.5 is the same
substance as 0.14.4 — **identical model, proofs, and henret edge** (henret 0.34.4,
`ad0ceab4`; 77 theorems / 0 / 0) — just cleaner packaging:

```
iotakt-0.14.5.tar.gz       sha256: 8c1db19e687855de8a8c6804bdef367ec90edde8ecd1740321e25fa32d6f66b9
iotakt-0.14.5.provenance.json sha256: 8a125c2bd18e93e34c5b7b0a0bd89722914fa6102dcfc95cb98853c5122e2849
package "iotakt", version "0.14.5", files-at-root, reproducible
```

**No need to re-pin on our account.** 0.14.4 is correctly labeled and fully verifiable;
pin it with the `0.14.4` string and no `-dev` caveat. If you'd rather track the
source-only archive, 0.14.5 is there once its tag is published. Either is fine — the
substance is identical.
