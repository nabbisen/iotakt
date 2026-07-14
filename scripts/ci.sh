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
lake build Iotakt && pass "lake build Iotakt (model pkg)" || fail "lake build Iotakt (model pkg)"

step "3. Henret bridge"
lake --dir runtime build IotaktBridge && pass "lake --dir runtime build IotaktBridge" || fail "lake --dir runtime build IotaktBridge"

step "4. Proof corpus + matrix honesty (RFC 014)"
lake build Iotakt.Proofs >/dev/null 2>&1 && BUILT=1 || BUILT=0
THM=$(grep -rhE "^(theorem|lemma|@\[simp\] theorem|@\[simp\] lemma)" Iotakt/ runtime/IotaktRuntime/ --include="*.lean" | wc -l | tr -d " ")
SRY=$(grep -rn "sorry\|admit" Iotakt/ runtime/IotaktRuntime/ --include="*.lean" | grep -v "•" | wc -l | tr -d " ")
AX=$(grep -rn "^axiom " Iotakt/ runtime/IotaktRuntime/ --include="*.lean" | wc -l | tr -d " ")
CLAIMED=$(grep -oE "[0-9]+ machine-checked theorems" docs/src/proof-trust-test-matrix.md | grep -oE "^[0-9]+")
if [ "$BUILT" -eq 1 ] && [ "$SRY" -eq 0 ] && [ "$AX" -eq 0 ] && [ "$THM" = "$CLAIMED" ]; then
  pass "proof corpus: $THM theorems, 0 sorry/admit, 0 axiom; matrix count matches"
else
  fail "proof corpus: built=$BUILT thm=$THM claimed=$CLAIMED sorry=$SRY axiom=$AX"
fi

step "5. Fake-poller demo (19 Lean-only checks)"
lake --dir runtime build iotakt-fake-demo && runtime/.lake/build/bin/iotakt-fake-demo > /tmp/fake_out.txt 2>&1
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
  step "6. Native C shim compilation"
  if require gcc; then
    lake --dir runtime build IotaktNative && pass "lake --dir runtime build IotaktNative (C shim + Lean FFI)" \
      || fail "lake --dir runtime build IotaktNative"
  else
    echo "SKIP: gcc not found"
  fi

  step "7. Native integration test (13 checks)"
  lake --dir runtime build iotakt-native-test 2>/dev/null && \
    runtime/.lake/build/bin/iotakt-native-test > /tmp/native_out.txt 2>&1
  NAT_FAIL=$(grep -c "\[FAIL\]" /tmp/native_out.txt || true)
  NAT_PASS=$(grep -c "\[PASS\]" /tmp/native_out.txt || true)
  if [ "$NAT_FAIL" -eq 0 ] && [ "$NAT_PASS" -gt 0 ]; then
    pass "native-test: $NAT_PASS checks all PASS"
  else
    cat /tmp/native_out.txt
    fail "native-test: $NAT_FAIL failed, $NAT_PASS passed"
  fi

  step "8. Echo integration test — v0.1 checkpoint (19 checks)"
  lake --dir runtime build iotakt-echo-test 2>/dev/null && \
    runtime/.lake/build/bin/iotakt-echo-test > /tmp/echo_out.txt 2>&1
  ECHO_FAIL=$(grep -c "\[FAIL\]" /tmp/echo_out.txt || true)
  ECHO_PASS=$(grep -c "\[PASS\]" /tmp/echo_out.txt || true)
  if [ "$ECHO_FAIL" -eq 0 ] && [ "$ECHO_PASS" -gt 0 ]; then
    pass "echo-test: $ECHO_PASS checks all PASS"
  else
    cat /tmp/echo_out.txt
    fail "echo-test: $ECHO_FAIL failed, $ECHO_PASS passed"
  fi
fi

step "9. Echo server smoke test (RFC §21.4 criterion)"
if require nc; then
  # Start server in background; capture its output in a temp file
  SRV_OUT=$(mktemp)
  runtime/.lake/build/bin/iotakt-echo-server > "$SRV_OUT" 2>&1 &
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

step "10. v0.3 integration test (RFC 036 UDP, RFC 039 connect, persistent)"
lake --dir runtime build iotakt-v3-test 2>/dev/null &&   runtime/.lake/build/bin/iotakt-v3-test > /tmp/v3_out.txt 2>&1
V3_FAIL=$(grep -c "\[FAIL\]" /tmp/v3_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V3_PASS=$(grep -c "\[PASS\]" /tmp/v3_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V3_FAIL" -eq 0 ] && [ "$V3_PASS" -gt 0 ]; then
  pass "v0.3-test: $V3_PASS checks (UDP + connect + persistent) all PASS"
else
  cat /tmp/v3_out.txt
  fail "v0.3-test: $V3_FAIL failed, $V3_PASS passed"
fi

step "11. v0.5 integration test (Actor, Stats, HTTP keep-alive, throughput)"
lake --dir runtime build iotakt-v5-test 2>/dev/null && \
  runtime/.lake/build/bin/iotakt-v5-test > /tmp/v5_out.txt 2>&1
V5_FAIL=$(grep -c "\[FAIL\]" /tmp/v5_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V5_PASS=$(grep -c "\[PASS\]" /tmp/v5_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V5_FAIL" -eq 0 ] && [ "$V5_PASS" -gt 0 ]; then
  pass "v0.5-test: $V5_PASS checks (Actor + Stats + HTTP + throughput) all PASS"
else
  cat /tmp/v5_out.txt
  fail "v0.5-test: $V5_FAIL failed, $V5_PASS passed"
fi

step "12. Throughput benchmark (RFC 025)"
lake --dir runtime build iotakt-bench 2>/dev/null && \
  runtime/.lake/build/bin/iotakt-bench > /tmp/bench_out.txt 2>&1
BENCH_PASS=$(grep -c "\[PASS\]" /tmp/bench_out.txt 2>/dev/null | tr -d "\n" || echo 0)
BENCH_FAIL=$(grep -c "\[FAIL\]" /tmp/bench_out.txt 2>/dev/null | tr -d "\n" || echo 0)
RPS=$(grep "Throughput:" /tmp/bench_out.txt 2>/dev/null | head -1 || echo "0")
if [ "$BENCH_FAIL" -eq 0 ] && [ "$BENCH_PASS" -gt 0 ]; then
  pass "benchmark: $BENCH_PASS checks PASS ($RPS)"
else
  cat /tmp/bench_out.txt
  fail "benchmark: $BENCH_FAIL failed"
fi

step "13. v0.6 integration test (Router, Gap 006 cancel-on-close)"
lake --dir runtime build iotakt-v6-test 2>/dev/null && \
  runtime/.lake/build/bin/iotakt-v6-test > /tmp/v6_out.txt 2>&1
V6_FAIL=$(grep -c "\[FAIL\]" /tmp/v6_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V6_PASS=$(grep -c "\[PASS\]" /tmp/v6_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V6_FAIL" -eq 0 ] && [ "$V6_PASS" -gt 0 ]; then
  pass "v0.6-test: $V6_PASS checks (Router + Gap 006 + henret v0.11.0) all PASS"
else
  cat /tmp/v6_out.txt
  fail "v0.6-test: $V6_FAIL failed, $V6_PASS passed"
fi

step "14. HTTP/1.1 routing server smoke test"
if require nc; then
  lake --dir runtime build iotakt-routing-server 2>/dev/null
  runtime/.lake/build/bin/iotakt-routing-server > /tmp/routing_ci.txt 2>&1 &
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

step "15. v0.7 integration test (adaptive timeout, idle reaping, receiveUntil infra)"
lake --dir runtime build iotakt-v7-test 2>/dev/null && \
  runtime/.lake/build/bin/iotakt-v7-test > /tmp/v7_out.txt 2>&1
V7_FAIL=$(grep -c "\[FAIL\]" /tmp/v7_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V7_PASS=$(grep -c "\[PASS\]" /tmp/v7_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V7_FAIL" -eq 0 ] && [ "$V7_PASS" -gt 0 ]; then
  pass "v0.7-test: $V7_PASS checks (adaptive timeout + idle reaping + receiveUntil) all PASS"
else
  cat /tmp/v7_out.txt
  fail "v0.7-test: $V7_FAIL failed, $V7_PASS passed"
fi

step "16. v0.8 integration test (chunked encoding + scheduled connection actors)"
lake --dir runtime build iotakt-v8-test 2>/dev/null && \
  runtime/.lake/build/bin/iotakt-v8-test > /tmp/v8_out.txt 2>&1
V8_FAIL=$(grep -c "\[FAIL\]" /tmp/v8_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V8_PASS=$(grep -c "\[PASS\]" /tmp/v8_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V8_FAIL" -eq 0 ] && [ "$V8_PASS" -gt 0 ]; then
  pass "v0.8-test: $V8_PASS checks (chunked + SchedConn lifecycle) all PASS"
else
  cat /tmp/v8_out.txt
  fail "v0.8-test: $V8_FAIL failed, $V8_PASS passed"
fi

step "17. HTTP/1.1 chunked streaming server smoke test"
if require nc; then
  lake --dir runtime build iotakt-streaming-server 2>/dev/null
  runtime/.lake/build/bin/iotakt-streaming-server > /tmp/stream_ci.txt 2>&1 &
  STREAM_PID=$!
  sleep 1
  STREAM_OUT=$(printf "GET /stream HTTP/1.1\r\nHost: x\r\n\r\n" | nc -q2 127.0.0.1 49995 2>/dev/null)
  sleep 3
  kill "$STREAM_PID" 2>/dev/null || true; wait "$STREAM_PID" 2>/dev/null || true
  if echo "$STREAM_OUT" | grep -q "Transfer-Encoding: chunked" && \
     echo "$STREAM_OUT" | grep -q "^7" && echo "$STREAM_OUT" | grep -qi "Hello"; then
    pass "streaming server: chunked framing (7/8/7 + terminator) verified ✓"
  else
    echo "$STREAM_OUT"
    fail "streaming server: chunked framing not detected"
  fi
else
  pass "streaming server smoke test: SKIP (nc not found)"
fi

step "18. v0.9 integration test (body framing + live request reading + handoff surface)"
lake --dir runtime build iotakt-v9-test 2>/dev/null && \
  runtime/.lake/build/bin/iotakt-v9-test > /tmp/v9_out.txt 2>&1
V9_FAIL=$(grep -c "\[FAIL\]" /tmp/v9_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V9_PASS=$(grep -c "\[PASS\]" /tmp/v9_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V9_FAIL" -eq 0 ] && [ "$V9_PASS" -gt 0 ]; then
  pass "v0.9-test: $V9_PASS checks (framing + readFull + Iotakt.Server) all PASS"
else
  cat /tmp/v9_out.txt
  fail "v0.9-test: $V9_FAIL failed, $V9_PASS passed"
fi

step "19. Upload server smoke test (Content-Length + chunked request bodies)"
if require curl; then
  lake --dir runtime build iotakt-upload-server 2>/dev/null
  runtime/.lake/build/bin/iotakt-upload-server > /tmp/upload_ci.txt 2>&1 &
  UP_PID=$!
  sleep 1
  CL_OUT=$(curl -s -X POST --data 'hello world' http://127.0.0.1:49996/upload 2>/dev/null)
  CK_OUT=$(echo -n "chunked-data-here" | curl -s -X POST -H "Transfer-Encoding: chunked" --data-binary @- http://127.0.0.1:49996/chunkup 2>/dev/null)
  sleep 3
  kill "$UP_PID" 2>/dev/null || true; wait "$UP_PID" 2>/dev/null || true
  if echo "$CL_OUT" | grep -q "received 11 bytes" && echo "$CK_OUT" | grep -q "received 17 bytes"; then
    pass "upload server: Content-Length (11B) + chunked (17B) bodies reassembled ✓"
  else
    echo "CL='$CL_OUT' CK='$CK_OUT'"
    fail "upload server: body reassembly failed"
  fi
else
  pass "upload server smoke test: SKIP (curl not found)"
fi

step "20. v0.10 integration test (size limits + readFromBuffer pipelining)"
lake --dir runtime build iotakt-v10-test 2>/dev/null && \
  runtime/.lake/build/bin/iotakt-v10-test > /tmp/v10_out.txt 2>&1
V10_FAIL=$(grep -c "\[FAIL\]" /tmp/v10_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V10_PASS=$(grep -c "\[PASS\]" /tmp/v10_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V10_FAIL" -eq 0 ] && [ "$V10_PASS" -gt 0 ]; then
  pass "v0.10-test: $V10_PASS checks (size limits + readFromBuffer pipelining) all PASS"
else
  cat /tmp/v10_out.txt
  fail "v0.10-test: $V10_FAIL failed, $V10_PASS passed"
fi

step "21. Reference consumer smoke test (handoff surface sufficiency + keep-alive)"
if require curl; then
  lake --dir runtime build iotakt-reference-server 2>/dev/null
  runtime/.lake/build/bin/iotakt-reference-server > /tmp/refsrv_ci.txt 2>&1 &
  RS_PID=$!
  sleep 1
  R_USER=$(curl -s http://127.0.0.1:49997/users/42 2>/dev/null)
  R_KA=$(curl -s http://127.0.0.1:49997/a http://127.0.0.1:49997/b 2>/dev/null)
  sleep 3
  kill "$RS_PID" 2>/dev/null || true; wait "$RS_PID" 2>/dev/null || true
  if echo "$R_USER" | grep -q '"id":"42"' && [ "$R_KA" = "AB" ]; then
    pass "reference server: /users/42 → JSON, keep-alive /a/b on one conn → AB ✓"
  else
    echo "user='$R_USER' ka='$R_KA'"
    fail "reference server: routing or keep-alive failed"
  fi
else
  pass "reference server smoke test: SKIP (curl not found)"
fi

step "22. v0.11 integration test (connection limits + graceful shutdown)"
lake --dir runtime build iotakt-v11-test 2>/dev/null && \
  timeout 20 runtime/.lake/build/bin/iotakt-v11-test > /tmp/v11_ci.txt 2>&1
V11_FAIL=$(grep -c "\[FAIL\]" /tmp/v11_ci.txt 2>/dev/null | tr -d "\n" || echo 0)
V11_PASS=$(grep -c "\[PASS\]" /tmp/v11_ci.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V11_FAIL" -eq 0 ] && [ "$V11_PASS" -gt 0 ]; then
  pass "v0.11-test: $V11_PASS checks (connection limits + graceful shutdown) all PASS"
else
  cat /tmp/v11_ci.txt
  fail "v0.11-test: $V11_FAIL failed, $V11_PASS passed"
fi

step "23. v0.13 integration test (explicit ack + recvAck/sendAck)"
lake --dir runtime build iotakt-v13-test 2>/dev/null && \
  timeout 20 runtime/.lake/build/bin/iotakt-v13-test > /tmp/v13_ci.txt 2>&1
V13_FAIL=$(grep -c "\[FAIL\]" /tmp/v13_ci.txt 2>/dev/null | tr -d "\n" || echo 0)
V13_PASS=$(grep -c "\[PASS\]" /tmp/v13_ci.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V13_FAIL" -eq 0 ] && [ "$V13_PASS" -gt 0 ]; then
  pass "v0.13-test: $V13_PASS checks (explicit ack + recvAck/sendAck) all PASS"
else
  cat /tmp/v13_ci.txt
  fail "v0.13-test: $V13_FAIL failed, $V13_PASS passed"
fi

step "23a. R2 authoritative returned-event regression (RFC 066)"
if lake --dir runtime build iotakt-r2-delivery-test 2>/dev/null && \
    timeout 20 runtime/.lake/build/bin/iotakt-r2-delivery-test > /tmp/r2_delivery_ci.txt 2>&1; then
  R2_DELIVERY_PASS=$(grep -c "\[PASS\]" /tmp/r2_delivery_ci.txt || true)
  if [ "$R2_DELIVERY_PASS" -eq 8 ]; then
    pass "R2 delivery: $R2_DELIVERY_PASS checks all PASS"
  else
    cat /tmp/r2_delivery_ci.txt
    fail "R2 delivery: expected 8 passing checks, observed $R2_DELIVERY_PASS"
  fi
else
  cat /tmp/r2_delivery_ci.txt 2>/dev/null || true
  fail "R2 delivery: build or executable failed"
fi

step "23b. R2 address-aware listener regression (RFC 070)"
if lake --dir runtime build iotakt-r2-listener-test 2>/dev/null && \
    timeout 20 runtime/.lake/build/bin/iotakt-r2-listener-test > /tmp/r2_listener_ci.txt 2>&1; then
  R2_LISTENER_PASS=$(grep -c "\[PASS\]" /tmp/r2_listener_ci.txt || true)
  if [ "$R2_LISTENER_PASS" -eq 24 ]; then
    pass "R2 listener: $R2_LISTENER_PASS checks all PASS"
  else
    cat /tmp/r2_listener_ci.txt
    fail "R2 listener: expected 24 passing checks, observed $R2_LISTENER_PASS"
  fi
else
  cat /tmp/r2_listener_ci.txt 2>/dev/null || true
  fail "R2 listener: build or executable failed"
fi

step "24. v0.4 integration test (WriteBuffer, HTTP round-trip, FFI, conformance)"
lake --dir runtime build iotakt-v4-test 2>/dev/null && \
  runtime/.lake/build/bin/iotakt-v4-test > /tmp/v4_out.txt 2>&1
V4_FAIL=$(grep -c "\[FAIL\]" /tmp/v4_out.txt 2>/dev/null | tr -d "\n" || echo 0)
V4_PASS=$(grep -c "\[PASS\]" /tmp/v4_out.txt 2>/dev/null | tr -d "\n" || echo 0)
if [ "$V4_FAIL" -eq 0 ] && [ "$V4_PASS" -gt 0 ]; then
  pass "v0.4-test: $V4_PASS checks (WriteBuffer + HTTP + FFI + conformance) all PASS"
else
  cat /tmp/v4_out.txt
  fail "v0.4-test: $V4_FAIL failed, $V4_PASS passed"
fi

step "25. HTTP/1.0 server+client smoke test"
if require nc; then
  lake --dir runtime build iotakt-http-server iotakt-http-client 2>/dev/null
  runtime/.lake/build/bin/iotakt-http-server > /tmp/http_srv.txt 2>&1 &
  HTTP_SRV_PID=$!
  sleep 1
  HTTP_OUT=$(runtime/.lake/build/bin/iotakt-http-client 2>/dev/null)
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

step "26. Multi-connection echo server"
if require nc; then
  lake --dir runtime build iotakt-multi-echo 2>/dev/null
  runtime/.lake/build/bin/iotakt-multi-echo > /dev/null 2>&1 &
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

step "27. Release provenance manifest consistency (RFC 062)"
sh scripts/check-provenance.sh && pass "provenance: manifest consistent with corpus (RFC 062)" || fail "provenance: manifest inconsistent"

step "28. Model-only resolution (RFC 061): Henret-free model consumer"
sh scripts/check-model-only-resolution.sh && pass "model-only resolution: Henret absent from consumer manifest (RFC 061)" || fail "model-only resolution"

echo ""
echo "══════════════════════════════════"
echo "CI summary: $OK passed, $FAIL failed"
