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
THM=$(grep -rhE "^(theorem|lemma|@\[simp\] theorem|@\[simp\] lemma)" Iotakt/ runtime/IotaktRuntime/ --include="*.lean" | wc -l | tr -d ' ')
SRY=$(grep -rn "sorry\|admit" Iotakt/ runtime/IotaktRuntime/ --include="*.lean" | grep -v "•" | wc -l | tr -d ' ')
AX=$(grep -rn "^axiom " Iotakt/ runtime/IotaktRuntime/ --include="*.lean" | wc -l | tr -d ' ')
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
files=sorted(glob.glob('Iotakt/**/*.lean',recursive=True))+sorted(glob.glob('runtime/IotaktRuntime/**/*.lean',recursive=True))+['Iotakt.lean','runtime/IotaktRuntime.lean','lakefile.lean','runtime/lakefile.lean','lake-manifest.json','runtime/lake-manifest.json','lean-toolchain']
th=hashlib.sha256()
for f in files:
    if os.path.isfile(f):
        th.update(f.encode()); th.update(b'\x00'); th.update(open(f,'rb').read()); th.update(b'\x00')
man=json.load(open('runtime/lake-manifest.json'))
hpin=[p for p in man['packages'] if p['name']=='henret'][0]

# RFC 063 — stack-contract dependency edge, DERIVED from henret's published RFC 095
# sidecar (vendored under provenance/) and VERIFIED to bind to the commit we build
# against. We never transcribe hand-supplied hashes: manifest_sha256 is the SHA-256
# of the sidecar file itself; tarball_sha256 is henret's published canonical-archive
# hash; both are admitted only after the sidecar's git_commit equals our henret pin.
deps=[]
sidecars=sorted(glob.glob('provenance/henret-*.release-verification.json'))
for sc in sidecars:
    sm=json.load(open(sc))
    sc_commit=sm.get('git_commit')
    if sc_commit != hpin.get('rev'):
        sys.stderr.write(f"FATAL: sidecar {sc} git_commit {sc_commit} != henret pin {hpin.get('rev')}\n")
        sys.exit(3)
    if not sm.get('required_gates_passed', False):
        sys.stderr.write(f"FATAL: sidecar {sc} required_gates_passed is not true\n")
        sys.exit(3)
    deps.append({
      "package":"henret",
      "version":sm.get('version'),
      "manifest_sha256":sha(sc),                       # = jemmet's provider_manifest_sha256
      "tarball_sha256":sm.get('tarball_sha256') or (sm.get('source_archive') or {}).get('sha256'),
      "surface":"task/runtime model API",
      "scope":"iotakt-runtime package (the iotakt model package is henret-free)",
      "git_rev":hpin.get('rev'),
      "manifest_schema":sm.get('manifest_schema'),
      "release_profile":sm.get('release_profile'),
      "bound_by":"git_commit (verified) ; manifest_sha256/tarball_sha256 are henret's published values (trusted per henret RFC 080)",
    })
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
  "dependencies":deps,
  "verification":{"theorems":int(os.environ['PV_THM']),"sorry":int(os.environ['PV_SRY']),
                  "admit":0,"project_axioms":int(os.environ['PV_AX']),
                  "ci_steps":int(os.environ['PV_STEPS']),
                  "toolchain":open('lean-toolchain').read().strip()},
}
open(sys.argv[1],'w').write(json.dumps(prov,indent=2)+"\n")
PY
