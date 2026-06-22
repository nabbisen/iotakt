#!/usr/bin/env bash
# verify-provenance.sh — verify a release archive against its provenance manifest
# (RFC 062). For downstream consumers (e.g. jemmet) anchoring iotakt provenance.
# Usage: scripts/verify-provenance.sh <archive.tar.gz> <provenance.json>
set -euo pipefail

ARCHIVE="${1:?usage: verify-provenance.sh <archive> <provenance.json>}"
MANIFEST="${2:?usage: verify-provenance.sh <archive> <provenance.json>}"

export VP_ARCHIVE="$ARCHIVE" VP_MANIFEST="$MANIFEST"
python3 - <<'PY'
import hashlib, json, os, sys
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(65536),b''): h.update(b)
    return h.hexdigest()
arch=os.environ['VP_ARCHIVE']; man=json.load(open(os.environ['VP_MANIFEST']))
exp=man.get("source_archive",{}).get("sha256")
got=sha(arch)
ok = exp==got
print(f"schema:        {man.get('schema')}")
print(f"version:       {man.get('version')}")
print(f"henret pin:    {man['henret_pin'].get('inputRev')} ({(man['henret_pin'].get('rev') or '')[:12]})")
print(f"archive sha256 expected: {exp}")
print(f"archive sha256 actual:   {got}")
print(f"verification:  {man.get('verification')}")
if ok:
    print("RESULT: OK — archive matches provenance manifest")
    sys.exit(0)
else:
    print("RESULT: MISMATCH — archive does NOT match provenance manifest", file=sys.stderr)
    sys.exit(1)
PY
