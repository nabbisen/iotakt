#!/usr/bin/env bash
# check-model-only-resolution.sh — RFC 061 regression guard.
# A model-only consumer resolves and builds the iotakt MODEL package with Henret
# ABSENT from its manifest and no GitHub clone (the inverse of the jemmet Q2 repro).
set -eu
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/lakefile.lean" <<LK
import Lake
open Lake DSL
package probe where
require iotakt from "$ROOT"
lean_lib Probe where
LK
printf 'import Iotakt.Api\n' > "$TMP/Probe.lean"
cp "$ROOT/lean-toolchain" "$TMP/lean-toolchain"
cd "$TMP"
lake update >/dev/null 2>&1
python3 -c "import json,sys; m=json.load(open('lake-manifest.json')); names=[p['name'] for p in m['packages']]; sys.exit(0 if 'henret' not in names else 1)" \
  && echo "model-only resolution: Henret ABSENT from consumer manifest (RFC 061)" \
  || { echo '[FAIL] Henret present in model-only consumer manifest'; exit 1; }
lake build Probe >/dev/null 2>&1 && echo "model-only build: ok (Henret-free)" || { echo '[FAIL] model-only build'; exit 1; }
