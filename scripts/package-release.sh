#!/usr/bin/env bash
# package-release.sh — build the canonical, files-at-root, reproducible release
# archive and its provenance sidecar, and print the exact assets to publish.
#
# Usage: scripts/package-release.sh <version> [out-dir]
#   e.g. scripts/package-release.sh 0.14.5 /mnt/user-data/outputs
#
# The canonical version label is bare X.Y.Z (no -dev suffix). A leading "v" on the
# git tag is tolerated and stripped, so a tag 0.14.5 or v0.14.5 both yield 0.14.5.
#
# The archive is the artifact iotakt.provenance/v1.source_archive names. It MUST be
# published as a downloadable GitHub *release asset* beside the provenance JSON — NOT
# left to GitHub's auto-generated "Source code (tar.gz)", which wraps every path in a
# parent directory and has different bytes. See RELEASES.md.
#
# Reproducible: --sort=name + fixed mtime/owner + gzip -n make the archive
# byte-identical across machines, so source_archive.sha256 is auditable, not arbitrary.
# Cross-team handoff correspondence (handoff/, jemmet-handoff/) is NOT source and is
# excluded — it would otherwise make the archive hash depend on documents that cite
# that very hash (a self-reference that can never settle).
set -eu

RAW="${1:?usage: package-release.sh <version> [out-dir]}"
VERSION="${RAW#v}"                      # canonical label is bare X.Y.Z
OUTDIR="${2:-/mnt/user-data/outputs}"
cd "$(dirname "$0")/.."
mkdir -p "$OUTDIR"

NAME="iotakt-${VERSION}.tar.gz"
TAR="${OUTDIR}/${NAME}"
PROV="${OUTDIR}/iotakt-${VERSION}.provenance.json"

# Label honesty: the release version must equal the latest CHANGELOG release heading,
# so the tag, the manifest version, and the changelog can never disagree (this is the
# guard that would have caught the 0.14.4 label drift).
CL=$(grep -oE '^## \[[0-9][^]]*\]' CHANGELOG.md | grep -v '\[Unreleased\]' | head -1 | sed -E 's/^## \[([^]]*)\].*/\1/')
if [ "$VERSION" != "$CL" ]; then
  echo "FATAL: release version '$VERSION' != latest CHANGELOG heading '$CL'." >&2
  echo "       Add a '## [$VERSION]' CHANGELOG entry or fix the tag before releasing." >&2
  exit 1
fi

# Stage a clean tree: source only — no build artifacts, no cross-team handoff mail.
ST="$(mktemp -d)"
tar cf - --exclude='.lake' --exclude='*.olean' --exclude='*.o' --exclude='*.a' \
         --exclude='*.ilean' --exclude='./.git' \
         --exclude='./handoff' --exclude='./jemmet-handoff' . | tar xf - -C "$ST"

# Canonical, files-at-root, reproducible archive.
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -cf - -C "$ST" . | gzip -n > "$TAR"
rm -rf "$ST"

# Provenance sidecar (RFC 062/063) over this exact archive.
bash scripts/gen-provenance.sh "$VERSION" "$TAR" "$PROV"

SHA=$(sha256sum "$TAR" | cut -d' ' -f1)
PSHA=$(sha256sum "$PROV" | cut -d' ' -f1)
echo
echo "=== publish these as release assets on tag ${VERSION} (files-at-root, henret-style) ==="
echo "  ${NAME}"
echo "    sha256: ${SHA}"
echo "    bytes:  $(stat -c%s "$TAR")"
echo "  iotakt-${VERSION}.provenance.json"
echo "    sha256: ${PSHA}   (= the manifest hash consumers pin)"
echo
echo "Do NOT rely on GitHub's auto-generated source tarball — attach ${NAME} explicitly."
echo "Tag the release ${VERSION} (canonical bare X.Y.Z) so tag, archive name, and manifest agree."
