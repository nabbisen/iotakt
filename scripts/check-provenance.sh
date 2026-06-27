#!/usr/bin/env bash
# check-provenance.sh — CI gate: the provenance generator stays consistent with the
# live proof corpus and is reproducible (RFC 062). Runs without a release archive.
set -eu
cd "$(dirname "$0")/.."

# Canonical counts (same greps as ci.sh / gen-provenance.sh).
THM=$(grep -rhE "^(theorem|lemma|@\[simp\] theorem|@\[simp\] lemma)" Iotakt/ runtime/IotaktRuntime/ --include="*.lean" | wc -l | tr -d ' ')

# Exercise the generator twice against a stable stand-in input.
bash scripts/gen-provenance.sh _check lakefile.lean /tmp/_prov_a.json >/dev/null 2>&1
bash scripts/gen-provenance.sh _check lakefile.lean /tmp/_prov_b.json >/dev/null 2>&1

export CP_THM="$THM"
python3 - <<'PY'
import json, os, sys
a=json.load(open('/tmp/_prov_a.json')); b=json.load(open('/tmp/_prov_b.json'))
errs=[]
if a.get("schema")!="iotakt.provenance/v1": errs.append(f"schema={a.get('schema')}")
v=a.get("verification",{})
if v.get("theorems")!=int(os.environ['CP_THM']): errs.append(f"theorems {v.get('theorems')} != corpus {os.environ['CP_THM']}")
if v.get("sorry")!=0: errs.append(f"sorry={v.get('sorry')}")
if v.get("project_axioms")!=0: errs.append(f"axioms={v.get('project_axioms')}")
for k in ("source_tree_sha256","lake_manifest_sha256","henret_pin"):
    if not a.get(k): errs.append(f"missing {k}")
if a.get("source_tree_sha256")!=b.get("source_tree_sha256"):
    errs.append("source_tree_sha256 not reproducible across runs")

# RFC 063 — verify each declared dependency edge re-binds, offline, against the
# vendored sidecar it claims (manifest_sha256) and the henret pin (git_commit).
import hashlib, glob
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for blk in iter(lambda:f.read(65536),b''): h.update(blk)
    return h.hexdigest()
pin=(a.get("henret_pin") or {}).get("rev")
deps=a.get("dependencies",[])
vendored=sorted(glob.glob('provenance/henret-*.release-verification.json'))
if vendored and not deps:
    errs.append("vendored henret sidecar present but dependencies[] is empty")
for d in deps:
    if d.get("git_rev")!=pin:
        errs.append(f"dependency {d.get('package')} git_rev != henret_pin.rev")
    # find the sidecar whose hash matches this edge's manifest_sha256
    match=[s for s in vendored if sha(s)==d.get("manifest_sha256")]
    if not match:
        errs.append(f"dependency {d.get('package')} manifest_sha256 matches no vendored sidecar")
        continue
    sm=json.load(open(match[0]))
    if sm.get("git_commit")!=pin:
        errs.append(f"sidecar git_commit {sm.get('git_commit')} != henret_pin.rev {pin}")
    tb=sm.get("tarball_sha256") or (sm.get("source_archive") or {}).get("sha256")
    if d.get("tarball_sha256")!=tb:
        errs.append(f"dependency {d.get('package')} tarball_sha256 != sidecar")
if errs:
    print("[FAIL] provenance consistency: "+"; ".join(errs)); sys.exit(1)
print(f"provenance: schema ok, verification matches corpus ({v.get('theorems')} thm, 0 sorry/axiom), source_tree hash reproducible"
      + (f", {len(deps)} dependency edge(s) bind to vendored sidecar + henret pin" if deps else ""))
PY
