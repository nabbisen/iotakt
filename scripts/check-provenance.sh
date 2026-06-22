#!/usr/bin/env bash
# check-provenance.sh — CI gate: the provenance generator stays consistent with the
# live proof corpus and is reproducible (RFC 062). Runs without a release archive.
set -eu
cd "$(dirname "$0")/.."

# Canonical counts (same greps as ci.sh / gen-provenance.sh).
THM=$(grep -rhE "^(theorem|lemma|@\[simp\] theorem|@\[simp\] lemma)" Iotakt/ --include="*.lean" | wc -l | tr -d ' ')

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
if errs:
    print("[FAIL] provenance consistency: "+"; ".join(errs)); sys.exit(1)
print(f"provenance: schema ok, verification matches corpus ({v.get('theorems')} thm, 0 sorry/axiom), source_tree hash reproducible")
PY
