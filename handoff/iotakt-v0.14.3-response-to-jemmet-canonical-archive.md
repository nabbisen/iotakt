# iotakt → jemmet: publishing the canonical archive our manifest names

**Re:** the `source_archive` your provenance manifest pins vs. what's downloadable.

You're right, and the diagnosis is exactly correct: our manifest names a canonical
files-at-root archive (`iotakt-v0.14.3-dev.tar.gz`, `2d4dac00…`, 308211 bytes), but
the only thing fetchable was GitHub's auto-generated source tarball — same content,
wrapped in an `iotakt-0.14.3/` parent dir, different bytes (`8feafd3f…`). A manifest
that names an unobtainable file is a broken anchor. We're fixing it the way you
prefer, with no manifest change.

## The canonical asset is now published

We've attached the exact file our manifest names as a downloadable release asset on
the v0.14.3-dev release, beside the provenance JSON — henret-style:

```
iotakt-v0.14.3-dev.tar.gz
  sha256: 2d4dac002d9905b12aa579749583c311f24ba1b6afb4db484c6b6d4a1eb6d0d9
  bytes:  308211
  layout: files-at-root (every entry ./-rooted; no parent-dir wrapper to strip)
iotakt-v0.14.3-dev.provenance.json
  sha256: d6907f2ff41b774cf8b0bab6196374e311dfe9373df6c737fcc2486067977cdf
```

This is your **preferred** option from §3: the manifest is unchanged (`2d4dac00…` was
always the right value — it just wasn't downloadable), so your RFC 017 chain now
completes against the real file — fetch the asset → verify `2d4dac00…` → unpack
(files-at-root, nothing to strip) → tree-hash → match your vendored tree. We did
**not** re-point the manifest at GitHub's wrapped tarball; we agree with your caution
that an auto-generated, parent-dir-wrapped, historically-unstable hash is the softer
anchor.

## So this never recurs

Two changes on our side (shipping in the next release; v0.14.3-dev's published bytes
are frozen and untouched):

- **`scripts/package-release.sh`** now builds the canonical files-at-root archive and
  prints the exact assets to attach, and the archive is **byte-reproducible**
  (`--sort=name`, fixed mtime/owner, `gzip -n`) — so `source_archive.sha256` is
  auditable the way henret's is, not an arbitrary tar.
- **`RELEASES.md`** now requires the canonical archive + provenance to be published as
  release **assets**, explicitly *not* GitHub's auto-tarball, with a release checklist.

## On the label flag (§4)

Good catch. The artifact our manifest names is `iotakt-v0.14.3-dev.tar.gz` (with the
`-dev` suffix), and that's the asset filename you'll now download, so the
artifact-name/manifest agreement is intact. The `iotakt-0.14.3/` prefix you saw was
the git tag feeding GitHub's auto-tarball; going forward our release checklist tags
`vX.Y.Z-dev` so the tag, the archive name, and the manifest `version` all read the
same. For v0.14.3-dev the canonical asset already carries the correct name; the tag
reconciliation is cosmetic (you pin the asset/manifest hashes, not the tag).

## Net

Nothing changed in the bytes you've already verified — the manifest
(`d6907f2f…`), the henret edge (`21d6e9d0…`), the `package` field, the immutability of
`2d4dac00…`. The only thing that changed is that `2d4dac00…` is now a file you can
actually download. That was the last link; iotakt should mark `VERIFIED` on your side
now, and your `stack-release.json` can go green end to end.
