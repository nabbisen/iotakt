# Releases and provenance policy

## Immutability — a published release is frozen

**A published release tag is never re-published in place. Any change ships as a new
version.** This applies to `-dev`-suffixed tags as well as future non-`-dev` tags.

This is the same discipline henret states for its releases, and it is what makes the
provenance anchor meaningful: once `iotakt-<version>.tar.gz` is published, its
`source_archive.sha256` is **immutable**. A consumer that pins that hash (e.g. in a
stack manifest) can rely on it never silently changing under the same version label.
If iotakt needs to change anything in a published release — even a single field in a
script or a one-line doc fix — it is cut as the next version, not edited in place.

Concretely: when jemmet asked us to add a `package` field for the shared stack
verifier *after* `v0.14.2-dev` was published, we did **not** re-cut `v0.14.2-dev`. We
shipped the field in `v0.14.3-dev`. `v0.14.2-dev`'s `source_archive.sha256`
(`ba25a8d1…`) remains valid and unchanged.

## Versioning and stability (pre-1.0)

iotakt is pre-1.0; every release is `-dev`-suffixed. Per the immutability guarantee
above, a published `-dev` release is a **frozen, pinnable artifact** — not a moving
target. A consumer may pin a `-dev` release and treat its `source_archive.sha256` and
`iotakt-<version>.provenance.json` as stable for provenance purposes.

A non-`-dev` release (v1.0) is the eventual stability milestone, cut once the public
model surface (`Iotakt.Api`, `Iotakt.Model.*`) is declared stable. Until then, the
latest frozen `-dev` release is the artifact to pin, and remaining pre-1.0 work on the
model surface is intended to be additive. When a non-`-dev` release lands, it will be
announced as the preferred pin; existing frozen `-dev` pins remain valid provenance
anchors regardless.

## Provenance

Each release publishes `iotakt-<version>.provenance.json` **beside** the tarball
(`iotakt.provenance/v1`, RFC 062/063). It records the source-archive hash, source-tree
hash, toolchain pin, the henret pin (commit), and — for releases whose runtime pins a
henret version with a published RFC 095 sidecar — a `dependencies[]` edge derived from
and bound to that sidecar (RFC 063). The manifest carries both `package` (the name the
stack verifier matches) and `project`.

Verify a release with:

```sh
scripts/verify-provenance.sh iotakt-<version>.tar.gz iotakt-<version>.provenance.json
```

## Publishing a release (CI publishes the canonical archive on tag)

A provenance anchor is only useful if the artifact it names is **obtainable**. The
archive `iotakt.provenance/v1.source_archive` names is the **canonical, files-at-root**
tarball — *not* GitHub's auto-generated "Source code (tar.gz)", which wraps every path
in an `iotakt-<tag>/` parent directory and has entirely different bytes. Publishing
only GitHub's auto-tarball leaves the manifest pointing at a file no consumer can
download.

Publishing is automated by CI (`.github/workflows/release.yml`), mirroring henret:

1. Cut from a tree whose gate is green and tag the release **`vX.Y.Z-dev`** — with the
   `-dev` suffix — so the git tag, the archive filename, and the manifest `version` all
   agree. (A tag like `0.14.3` produces an `iotakt-0.14.3/` auto-tarball prefix that
   disagrees with the manifest name `iotakt-v0.14.3-dev.tar.gz`; avoid that mismatch.)
2. On the tag push, the `release` workflow runs the full 28-step gate, then
   `scripts/package-release.sh` to build the canonical files-at-root archive and its
   provenance sidecar, verifies them, and **uploads both as downloadable release
   assets** via `gh release upload`:
   - `iotakt-vX.Y.Z-dev.tar.gz` (the canonical archive the manifest names)
   - `iotakt-vX.Y.Z-dev.provenance.json`

   No manual attach step, and GitHub's auto-generated source tarball is never the
   anchor.

The archive is **byte-reproducible** (`package-release.sh` uses `--sort=name`, a fixed
mtime/owner, and `gzip -n`), so `source_archive.sha256` is auditable: anyone can
rebuild the tree and reproduce the hash, the way henret's release archive is
reproducible. `scripts/package-release.sh <version>` can also be run locally to
reproduce or pre-check the exact assets CI will publish.

## Yanking

If a published release is found to be broken or unsafe, it is **superseded by a new
version**, and the old one is marked yanked in `CHANGELOG.md` — never silently
re-published. Its hashes remain on record so existing provenance references stay
interpretable (as "yanked", not "changed").
