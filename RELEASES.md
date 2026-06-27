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

## Yanking

If a published release is found to be broken or unsafe, it is **superseded by a new
version**, and the old one is marked yanked in `CHANGELOG.md` — never silently
re-published. Its hashes remain on record so existing provenance references stay
interpretable (as "yanked", not "changed").
