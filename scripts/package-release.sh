#!/usr/bin/env bash
# package-release.sh — build the canonical, files-at-root, reproducible release
# archive and its provenance sidecar, and print the exact assets to publish.
#
# Usage: scripts/package-release.sh <version> [out-dir]
#   e.g. scripts/package-release.sh v0.14.4-dev /mnt/user-data/outputs
#
# The archive is the artifact iotakt.provenance/v1.source_archive names. It MUST be
# published as a downloadable GitHub *release asset* beside the provenance JSON — NOT
# left to GitHub's auto-generated "Source code (tar.gz)", which wraps every path in a
# parent directory and has different bytes. See RELEASES.md.
#
# Reproducible: --sort=name + fixed mtime/owner + gzip -n make the archive
# byte-identical across machines, so source_archive.sha256 is auditable, not arbitrary.
set -eu

VERSION="${1:?usage: package-release.sh <version> [out-dir]}"
OUTDIR="${2:-/mnt/user-data/outputs}"
cd "$(dirname "$0")/.."
mkdir -p "$OUTDIR"

NAME="iotakt-${VERSION}.tar.gz"
TAR="${OUTDIR}/${NAME}"
PROV="${OUTDIR}/iotakt-${VERSION}.provenance.json"

# Stage a clean tree: source only, no build artifacts.
ST="$(mktemp -d)"
tar cf - --exclude='.lake' --exclude='*.olean' --exclude='*.o' --exclude='*.a' \
         --exclude='*.ilean' --exclude='./.git' . | tar xf - -C "$ST"

# Canonical, files-at-root, reproducible archive.
#  --sort=name        deterministic entry order
#  --mtime=@0         fixed timestamps (epoch)
#  --owner/group=0    fixed ownership
#  gzip -n            omit gzip's embedded timestamp/name
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
echo "Tag the release ${VERSION} (with the -dev suffix) so tag, archive name, and manifest agree."
