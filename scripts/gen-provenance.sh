#!/usr/bin/env bash
# gen-provenance.sh — emit an iotakt.provenance/v1 manifest for a release (RFC 062).
# Usage: scripts/gen-provenance.sh <version> <archive.tar.gz> [out.json]
# Counts are derived the same way scripts/ci.sh derives them, so the manifest
# cannot drift from the certified gate.
set -eu

VERSION="${1:?usage: gen-provenance.sh <version> <archive> [out.json]}"
ARCHIVE="${2:?usage: gen-provenance.sh <version> <archive> [out.json]}"
OUT="${3:-/dev/stdout}"
cd "$(dirname "$0")/.."

# Integrity counts — identical greps to ci.sh (single source of truth).
THM=$(grep -rhE "^(theorem|lemma|@\[simp\] theorem|@\[simp\] lemma)" Iotakt/ --include="*.lean" | wc -l | tr -d ' ')
SRY=$(grep -rn "sorry\|admit" Iotakt/ --include="*.lean" | grep -v "•" | wc -l | tr -d ' ')
AX=$(grep -rn "^axiom " Iotakt/ --include="*.lean" | wc -l | tr -d ' ')
STEPS=$(grep -cE 'step "[0-9]+\.' scripts/ci.sh | tr -d ' ')

export PV_VERSION="$VERSION" PV_ARCHIVE="$ARCHIVE" PV_THM="$THM" PV_SRY="$SRY" PV_AX="$AX" PV_STEPS="$STEPS"
python3 - "$OUT" <<'PY'
import hashlib, json, os, glob, sys
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(65536),b''): h.update(b)
    return h.hexdigest()
arch=os.environ['PV_ARCHIVE']
# Reproducible, archive-metadata-independent content hash.
files=sorted(glob.glob('Iotakt/**/*.lean',recursive=True))+['lakefile.lean','lake-manifest.json','lean-toolchain']
th=hashlib.sha256()
for f in files:
    if os.path.isfile(f):
        th.update(f.encode()); th.update(b'\x00'); th.update(open(f,'rb').read()); th.update(b'\x00')
man=json.load(open('lake-manifest.json'))
hpin=[p for p in man['packages'] if p['name']=='henret'][0]
prov={
  "schema":"iotakt.provenance/v1",
  "project":"iotakt",
  "version":os.environ['PV_VERSION'],
  "source_archive":{"name":os.path.basename(arch),"sha256":sha(arch),"bytes":os.path.getsize(arch)},
  "lake_manifest_sha256":sha('lake-manifest.json'),
  "lean_toolchain":{"value":open('lean-toolchain').read().strip(),"sha256":sha('lean-toolchain')},
  "source_tree_sha256":th.hexdigest(),
  "henret_pin":{"name":"henret","type":hpin['type'],"inputRev":hpin.get('inputRev'),
                "rev":hpin.get('rev'),"url":hpin.get('url'),"dir":hpin.get('dir')},
  "verification":{"theorems":int(os.environ['PV_THM']),"sorry":int(os.environ['PV_SRY']),
                  "admit":0,"project_axioms":int(os.environ['PV_AX']),
                  "ci_steps":int(os.environ['PV_STEPS']),
                  "toolchain":open('lean-toolchain').read().strip()},
}
open(sys.argv[1],'w').write(json.dumps(prov,indent=2)+"\n")
PY
