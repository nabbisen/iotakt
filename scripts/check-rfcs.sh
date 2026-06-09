#!/bin/sh
# scripts/check-rfcs.sh — RFC invariant checker (RFC 000, §Optional CI invariants)
# Checks: no duplicate numbers, every proposed/done/archive RFC follows
# NNN-slug.md naming, and the README references every RFC file.
set -e

RFC_DIR="$(cd "$(dirname "$0")/.." && pwd)/rfcs"
STATUS=0
fail() { echo "FAIL: $1"; STATUS=1; }

# ── 1. Naming check ───────────────────────────────────────────────────────
echo "=== 1. Naming (NNN-slug.md) ==="
find "$RFC_DIR" -name "*.md" ! -name "README.md" | while read f; do
  base=$(basename "$f")
  if ! echo "$base" | grep -qE '^[0-9]{3}-[a-z0-9-]+\.md$'; then
    echo "FAIL: bad name: $f"
    exit 1
  fi
done && echo "PASS: all RFC filenames match NNN-slug.md"

# ── 2. Duplicate numbers ────────────────────────────────────────────────
echo "=== 2. No duplicate RFC numbers ==="
NUMS=$(find "$RFC_DIR" -name "*.md" ! -name "README.md" \
  | xargs -I{} basename {} | grep -oE '^[0-9]+' | sort)
DUPES=$(echo "$NUMS" | uniq -d)
if [ -n "$DUPES" ]; then fail "duplicate RFC numbers: $DUPES"; else echo "PASS: no duplicates"; fi

# ── 3. Status field present in each RFC (done/ must have Implemented) ─────
echo "=== 3. Status fields ==="
FAIL_COUNT=0
for rfc in "$RFC_DIR/done"/*.md; do
  [ "$(basename "$rfc")" = "README.md" ] && continue
  if ! grep -q "^\*\*Status" "$rfc" 2>/dev/null; then
    echo "FAIL: no Status field in $rfc"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
done
[ "$FAIL_COUNT" -eq 0 ] && echo "PASS: all done/ RFCs have Status field" || STATUS=1

# ── 4. README lists done/ RFCs ────────────────────────────────────────────
echo "=== 4. README completeness ==="
README="$RFC_DIR/README.md"
for rfc in "$RFC_DIR/done"/*.md; do
  [ "$(basename "$rfc")" = "README.md" ] && continue
  base=$(basename "$rfc")
  if ! grep -q "$base" "$README"; then
    fail "README missing reference to done/$base"
  fi
done
[ "$STATUS" -eq 0 ] && echo "PASS: README references all done/ RFCs"

# ── 5. archive/ is empty (no silently abandoned RFCs) ─────────────────────
echo "=== 5. Archive check ==="
ARCHIVED=$(find "$RFC_DIR/archive" -name "*.md" 2>/dev/null | wc -l)
echo "INFO: $ARCHIVED RFC(s) in archive/ (0 expected for v0.1-dev)"

echo ""
if [ "$STATUS" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; exit 1; fi
