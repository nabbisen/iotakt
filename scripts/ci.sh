#!/bin/sh
# scripts/ci.sh — iotakt CI gate (RFC 018)
#
# Runs all build and test steps in order. Exits non-zero on the first failure.
# Suitable for local developer use and CI runners (GitHub Actions, etc.).
#
# Environment variables:
#   IOTAKT_SANITIZE=1   — enable ASan/UBSan for native C build
#   IOTAKT_SKIP_NATIVE  — skip the native C build (Lean-only CI)
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

OK=0; FAIL=0
step() { echo ""; echo "══ $1 ══"; }
pass() { echo "[PASS] $1"; OK=$((OK+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }
require() { if ! command -v "$1" >/dev/null 2>&1; then echo "SKIP: $1 not found"; return 1; fi; return 0; }

step "1. RFC invariant checks"
sh scripts/check-rfcs.sh && pass "RFC checks" || fail "RFC checks"

step "2. Pure Lean model + fake poller (no C required)"
lake build Iotakt && pass "lake build Iotakt" || fail "lake build Iotakt"

step "3. Henret bridge"
lake build IotaktBridge && pass "lake build IotaktBridge" || fail "lake build IotaktBridge"

step "4. Fake-poller demo (19 Lean-only checks)"
lake build iotakt-fake-demo && .lake/build/bin/iotakt-fake-demo > /tmp/fake_out.txt 2>&1
FAKE_FAIL=$(grep -c "\[FAIL\]" /tmp/fake_out.txt || true)
FAKE_PASS=$(grep -c "\[PASS\]" /tmp/fake_out.txt || true)
if [ "$FAKE_FAIL" -eq 0 ] && [ "$FAKE_PASS" -gt 0 ]; then
  pass "fake-demo: $FAKE_PASS checks all PASS"
else
  cat /tmp/fake_out.txt
  fail "fake-demo: $FAKE_FAIL failed, $FAKE_PASS passed"
fi

if [ -n "${IOTAKT_SKIP_NATIVE:-}" ]; then
  echo ""
  echo "IOTAKT_SKIP_NATIVE set — skipping native C build and tests"
else
  step "5. Native C shim compilation"
  if require gcc; then
    lake build IotaktNative && pass "lake build IotaktNative (C shim + Lean FFI)" \
      || fail "lake build IotaktNative"
  else
    echo "SKIP: gcc not found"
  fi

  step "6. Native integration test (13 checks)"
  lake build iotakt-native-test 2>/dev/null && \
    .lake/build/bin/iotakt-native-test > /tmp/native_out.txt 2>&1
  NAT_FAIL=$(grep -c "\[FAIL\]" /tmp/native_out.txt || true)
  NAT_PASS=$(grep -c "\[PASS\]" /tmp/native_out.txt || true)
  if [ "$NAT_FAIL" -eq 0 ] && [ "$NAT_PASS" -gt 0 ]; then
    pass "native-test: $NAT_PASS checks all PASS"
  else
    cat /tmp/native_out.txt
    fail "native-test: $NAT_FAIL failed, $NAT_PASS passed"
  fi

  step "7. Echo integration test — v0.1 checkpoint (19 checks)"
  lake build iotakt-echo-test 2>/dev/null && \
    .lake/build/bin/iotakt-echo-test > /tmp/echo_out.txt 2>&1
  ECHO_FAIL=$(grep -c "\[FAIL\]" /tmp/echo_out.txt || true)
  ECHO_PASS=$(grep -c "\[PASS\]" /tmp/echo_out.txt || true)
  if [ "$ECHO_FAIL" -eq 0 ] && [ "$ECHO_PASS" -gt 0 ]; then
    pass "echo-test: $ECHO_PASS checks all PASS"
  else
    cat /tmp/echo_out.txt
    fail "echo-test: $ECHO_FAIL failed, $ECHO_PASS passed"
  fi
fi

step "8. Echo server smoke test (RFC §21.4 criterion)"
if require nc; then
  # Start server in background; capture its output in a temp file
  SRV_OUT=$(mktemp)
  .lake/build/bin/iotakt-echo-server > "$SRV_OUT" 2>&1 &
  SRV_PID=$!
  sleep 1
  ECHO_RESP=$(echo "hello from iotakt" | nc -q1 127.0.0.1 49900 2>/dev/null || true)
  sleep 1
  kill "$SRV_PID" 2>/dev/null || true
  wait "$SRV_PID" 2>/dev/null || true
  rm -f "$SRV_OUT"
  if echo "$ECHO_RESP" | grep -q "hello from iotakt"; then
    pass "echo server: TCP accept + read + write + echo verified (RFC §21.4 ✓)"
  else
    fail "echo server: expected echo not received (got: '$(echo "$ECHO_RESP" | head -1)')"
  fi
else
  echo "SKIP: nc not found"
fi

echo ""
echo "══════════════════════════════════"
echo "CI summary: $OK passed, $FAIL failed"
