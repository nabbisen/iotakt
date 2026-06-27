# Request to henret: point us at (or send) the published RFC 095 sidecar for 0.34.3

**From:** the iotakt maintainers (the henret → iotakt → jemmet stack)
**To:** the henret team
**Re:** fetching henret's published `0.34.3` release-verification sidecar so the
iotakt→henret edge verifies under RFC 096
**Against:** henret v0.34.3 (RFC 095/096), iotakt v0.14.1-dev (`iotakt.provenance/v1`)

## Background — who's asking and why

iotakt is a direct henret consumer. iotakt v0.14.1-dev pins henret at commit
`a5f3f1165718449e1ef4cf87607776af5fb6a1dd` — the commit `0.34.3^{}` dereferences to.
We commit-pin rather than `@ "0.34.3"` deliberately, because your release tags are
*annotated* (`0.34.3` → tag object, `0.34.3^{}` → the commit), so a tag pin would
record the tag-object SHA instead of the source commit.

A structural note that matters for the edge: after our RFC 061 split, henret is a
dependency of iotakt's **runtime** package only. iotakt's **model** package — the
surface jemmet's verified core consumes — is henret-free and resolves with henret
absent from its graph.

jemmet, the top consumer composing the stack manifest, has asked us (under your
**RFC 096** stack contract) to add an additive `dependencies` array to our provenance
manifest declaring the henret release we built against, by `manifest_sha256` +
`tarball_sha256` + `surface`. Per RFC 096 §D3 that per-package entry is the ground
truth `verify_stack_release.py` cross-checks the iotakt→henret edge against. We're on
board with this — it's the last seam needed to make the stack verifiable link by link.

## Our concern — why we're asking you directly, first-hand

To populate that entry **honestly**, we want to derive the two hashes from your
**authoritative published** RFC 095 sidecar
(`henret-0.34.3.release-verification.json`) and verify, on our side, that its
`git_commit` equals the commit we pinned (`a5f3f116…`). We specifically do **not**
want to transcribe hashes relayed second-hand (e.g. quoted to us by jemmet) into our
manifest: that would put values we never verified ourselves into iotakt's provenance,
which cuts against the proof/trust/test discipline we hold to. Fetching your
published artifact first-hand keeps the chain honest — we verify the git-commit
binding; your tarball/manifest hashes remain your published, reproducible values, and
we record them as such.

The blocker is simply that the sidecar is non-self-referential (RFC 095 §D2 —
published *beside*, not inside, the tarball), so it is not in the 0.34.3 source tree
and we can't obtain it from source.

## The ask — three narrow items

1. **Is the RFC 095 sidecar for `0.34.3` published, and what is its canonical fetch
   URL?** If it's a GitHub release asset, point us at it and we'll fetch and hash it
   directly.
2. **Please confirm its `git_commit` is
   `a5f3f1165718449e1ef4cf87607776af5fb6a1dd`** (`0.34.3^{}`), so the edge binds to
   the exact source we built against.
3. **Please confirm the canonical filename** (we expect
   `henret-0.34.3.release-verification.json`) so jemmet's stack edge, your manifest,
   and our `dependencies[]` all reference one identity.

## What we'll do with it

Once we have the sidecar (or its URL), iotakt will, in our generator:
- fetch it and verify `git_commit == a5f3f116…`;
- derive `manifest_sha256 = sha256(<sidecar bytes>)` and `tarball_sha256` from the
  sidecar's canonical-archive hash;
- emit them in an additive `dependencies` entry in `iotakt.provenance/v1` (tracked
  on our side as RFC 063), scoped to the runtime package.

## What we are *not* asking

- No change to henret — this is purely "please point us at (or send) the artifact
  RFC 095 already specifies."
- No change to our `henret_pin` (the git rev stays as a second anchor).

If it's simplest, a maintainer can just attach the published
`henret-0.34.3.release-verification.json` in reply and we'll take it from there.

Thanks — RFC 095/096 did the hard part; this is just getting the published artifact
into our hands so we can verify the edge rather than assert it.
