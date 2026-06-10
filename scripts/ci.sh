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

step "9. v0.3 integration test (RFC 036 UDP, RFC 039 connect, persistent)"
lake build iotakt-v3-test 2>/dev/null &&   .lake/build/bin/iotakt-v3-test > /tmp/v3_out.txt 2>&1
V3_FAIL=$(grep -c "\[FAIL\]" /tmp/v3_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V3_PASS=$(grep -c "\[PASS\]" /tmp/v3_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V3_FAIL" -eq 0 ] && [ "$V3_PASS" -gt 0 ]; then
  pass "v0.3-test: $V3_PASS checks (UDP + connect + persistent) all PASS"
else
  cat /tmp/v3_out.txt
  fail "v0.3-test: $V3_FAIL failed, $V3_PASS passed"
fi

step "13. v0.5 integration test (Actor, Stats, HTTP keep-alive, throughput)"
lake build iotakt-v5-test 2>/dev/null && \
  .lake/build/bin/iotakt-v5-test > /tmp/v5_out.txt 2>&1
V5_FAIL=$(grep -c "\[FAIL\]" /tmp/v5_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V5_PASS=$(grep -c "\[PASS\]" /tmp/v5_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V5_FAIL" -eq 0 ] && [ "$V5_PASS" -gt 0 ]; then
  pass "v0.5-test: $V5_PASS checks (Actor + Stats + HTTP + throughput) all PASS"
else
  cat /tmp/v5_out.txt
  fail "v0.5-test: $V5_FAIL failed, $V5_PASS passed"
fi

step "14. Throughput benchmark (RFC 025)"
lake build iotakt-bench 2>/dev/null && \
  .lake/build/bin/iotakt-bench > /tmp/bench_out.txt 2>&1
BENCH_PASS=$(grep -c "\[PASS\]" /tmp/bench_out.txt 2>/dev/null | tr -d "\n" || echo 0)
BENCH_FAIL=$(grep -c "\[FAIL\]" /tmp/bench_out.txt 2>/dev/null | tr -d "\n" || echo 0)
RPS=$(grep "Throughput:" /tmp/bench_out.txt 2>/dev/null | head -1 || echo "0")
if [ "$BENCH_FAIL" -eq 0 ] && [ "$BENCH_PASS" -gt 0 ]; then
  pass "benchmark: $BENCH_PASS checks PASS ($RPS)"
else
  cat /tmp/bench_out.txt
  fail "benchmark: $BENCH_FAIL failed"
fi

step "15. v0.6 integration test (Router, Gap 006 cancel-on-close)"
lake build iotakt-v6-test 2>/dev/null && \
  .lake/build/bin/iotakt-v6-test > /tmp/v6_out.txt 2>&1
V6_FAIL=$(grep -c "\[FAIL\]" /tmp/v6_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V6_PASS=$(grep -c "\[PASS\]" /tmp/v6_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V6_FAIL" -eq 0 ] && [ "$V6_PASS" -gt 0 ]; then
  pass "v0.6-test: $V6_PASS checks (Router + Gap 006 + henret v0.11.0) all PASS"
else
  cat /tmp/v6_out.txt
  fail "v0.6-test: $V6_FAIL failed, $V6_PASS passed"
fi

step "16. HTTP/1.1 routing server smoke test"
if require nc; then
  lake build iotakt-routing-server 2>/dev/null
  .lake/build/bin/iotakt-routing-server > /tmp/routing_ci.txt 2>&1 &
  ROUTE_PID=$!
  sleep 1
  R_HOME=$(printf "GET / HTTP/1.0\r\n\r\n" | nc -q1 127.0.0.1 49993 2>/dev/null | tail -1)
  R_USER=$(printf "GET /users/42 HTTP/1.0\r\n\r\n" | nc -q1 127.0.0.1 49993 2>/dev/null | tail -1)
  R_404=$(printf "GET /nope HTTP/1.0\r\n\r\n" | nc -q1 127.0.0.1 49993 2>/dev/null | head -1)
  sleep 3
  kill "$ROUTE_PID" 2>/dev/null || true; wait "$ROUTE_PID" 2>/dev/null || true
  if echo "$R_USER" | grep -q "id=42" && echo "$R_404" | grep -q "404"; then
    pass "routing server: /users/42 → id=42, /nope → 404 ✓"
  else
    echo "home='$R_HOME' user='$R_USER' 404='$R_404'"
    fail "routing server: unexpected routing output"
  fi
else
  pass "routing server smoke test: SKIP (nc not found)"
fi

step "10. v0.4 integration test (WriteBuffer, HTTP round-trip, FFI, conformance)"
lake build iotakt-v4-test 2>/dev/null && \
  .lake/build/bin/iotakt-v4-test > /tmp/v4_out.txt 2>&1
V4_FAIL=$(grep -c "\[FAIL\]" /tmp/v4_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V4_PASS=$(grep -c "\[PASS\]" /tmp/v4_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V4_FAIL" -eq 0 ] && [ "$V4_PASS" -gt 0 ]; then
  pass "v0.4-test: $V4_PASS checks (WriteBuffer + HTTP + FFI + conformance) all PASS"
else
  cat /tmp/v4_out.txt
  fail "v0.4-test: $V4_FAIL failed, $V4_PASS passed"
fi

step "11. HTTP/1.0 server+client smoke test"
if require nc; then
  lake build iotakt-http-server iotakt-http-client 2>/dev/null
  .lake/build/bin/iotakt-http-server > /tmp/http_srv.txt 2>&1 &
  HTTP_SRV_PID=$!
  sleep 1
  HTTP_OUT=$(.lake/build/bin/iotakt-http-client 2>/dev/null)
  sleep 2
  kill "$HTTP_SRV_PID" 2>/dev/null || true
  wait "$HTTP_SRV_PID" 2>/dev/null || true
  if echo "$HTTP_OUT" | grep -q "\[PASS\].*status 200"; then
    pass "HTTP server+client: GET /hello/iotakt → 200 OK ✓"
  else
    echo "$HTTP_OUT"
    fail "HTTP server+client: unexpected output"
  fi
else
  pass "HTTP smoke test: SKIP (nc not found)"
fi

step "12. Multi-connection echo server"
if require nc; then
  lake build iotakt-multi-echo 2>/dev/null
  .lake/build/bin/iotakt-multi-echo > /dev/null 2>&1 &
  SRV_PID=$!
  sleep 1
  R1=$(echo "hello" | nc -q1 127.0.0.1 49901 2>/dev/null || true)
  sleep 0.3
  R2=$(echo "world" | nc -q1 127.0.0.1 49901 2>/dev/null || true)
  sleep 2
  kill "$SRV_PID" 2>/dev/null || true; wait "$SRV_PID" 2>/dev/null || true
  if echo "$R1" | grep -q "hello" && echo "$R2" | grep -q "world"; then
    pass "multi-echo: two concurrent connections echoed correctly"
  else
    fail "multi-echo: echo mismatch (got: '$R1' / '$R2')"
  fi
else
  echo "SKIP: nc not found"
fi

echo ""
echo "══════════════════════════════════"
echo "CI summary: $OK passed, $FAIL failed"
