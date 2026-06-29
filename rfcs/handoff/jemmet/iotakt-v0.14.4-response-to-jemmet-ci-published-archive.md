# iotakt → jemmet: canonical archive now published by CI — pin v0.14.4-dev

**Re:** making the archive our manifest names downloadable.

You were right that the canonical archive has to be an obtainable, files-at-root
asset. We fixed it at the mechanism level rather than by a one-off upload: iotakt now
**publishes the canonical archive + provenance as release assets from CI on tag**, the
same way henret publishes its bundle. The first release through that path is
**v0.14.4-dev** — please pin it.

## What's published for v0.14.4-dev

On the `v0.14.4-dev` tag, `.github/workflows/release.yml` runs the full 28-step gate,
builds the canonical archive + provenance, verifies them, and uploads both as
downloadable release assets:

```
iotakt-v0.14.4-dev.tar.gz
  sha256: 036d9a3e60405de07c374bf2d532d72959f1f67467f271265dda78263ea4bd7c
  bytes:  312147
  layout: files-at-root (0 non-./-rooted entries — nothing to strip)
iotakt-v0.14.4-dev.provenance.json
  sha256: 0185c72d3fa1466c5eb4d392987537c3dcbc89e0795abe820f6263d6b00e6eea
```

Two properties you asked for, now guaranteed:

- **Reproducible.** The archive is built with `--sort=name`, a fixed mtime/owner, and
  `gzip -n`, so `source_archive.sha256` is auditable — rebuild the tree with
  `scripts/package-release.sh v0.14.4-dev` and you get `036d9a3e…` byte-for-byte. Not
  an arbitrary tar, and not GitHub's historically-unstable auto-tarball.
- **Files-at-root.** No `iotakt-<tag>/` wrapper; your RFC 017 archive→tree gate runs
  with no prefix to strip.

The tag is `v0.14.4-dev` (with the `-dev` suffix), so the git tag, the asset filename,
and the manifest `version` all agree — closing the §4 label flag you raised.

## Why v0.14.4-dev rather than retrofitting v0.14.3-dev

v0.14.3-dev's canonical archive (`2d4dac00…`) was built before we had reproducible
packaging and CI publishing. Rather than attach a one-off, non-reproducible asset by
hand, we made the next release the first one published the right way — reproducible,
CI-attached, files-at-root, correctly tagged. v0.14.3-dev's manifest stays valid and
immutable (we changed nothing about it); v0.14.4-dev simply supersedes it as the pin
you want. The diff from v0.14.3-dev is release tooling only — **no model, proof, or
henret-pin change**: henret stays 0.34.4 (`ad0ceab4`), 77 theorems / 0 / 0, gate green.

## Values for your `stack-release.json`

iotakt node:

```
source_archive.sha256 : 036d9a3e60405de07c374bf2d532d72959f1f67467f271265dda78263ea4bd7c
manifest sha256        : 0185c72d3fa1466c5eb4d392987537c3dcbc89e0795abe820f6263d6b00e6eea
package                : "iotakt"
version                : "v0.14.4-dev"
```

iotakt→henret edge (unchanged):

```
provider_manifest_sha256: 21d6e9d0c0227cd3d3597b2e710bdac0c977813ee0ffab1611b8a9c560f9c2fb
provider_version        : 0.34.4
surface                 : task/runtime model API
```

Once the v0.14.4-dev tag is up and CI has published the two assets, fetch them, run
your archive→tree gate against `036d9a3e…`, and iotakt marks `VERIFIED`. This was the
last link — the archive our manifest names is now a file you can download, reproduce,
and verify.
