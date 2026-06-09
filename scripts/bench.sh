#!/bin/sh
# scripts/bench.sh — iotakt throughput baseline (RFC 025)
#
# Measures round-trip echo throughput using the multi-connection echo server
# and dd/nc. Establishes a baseline before any performance optimization work.
#
# Usage: sh scripts/bench.sh [bytes] [count]
#   bytes = payload size (default 4096)
#   count = number of sends (default 1000)
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BYTES=${1:-4096}
COUNT=${2:-1000}
PORT=49902

echo "=== iotakt throughput baseline ==="
echo "Payload: ${BYTES}B × ${COUNT} sends"
echo ""

# Start server
.lake/build/bin/iotakt-multi-echo 2>/dev/null &
SRV_PID=$!
# Give server time to bind
sleep 0.5

# Generate payload
PAYLOAD=$(dd if=/dev/urandom bs="$BYTES" count=1 2>/dev/null | base64 | head -c "$BYTES")

# Measure throughput
START=$(date +%s%N 2>/dev/null || date +%s)
TOTAL=0
i=0
while [ $i -lt "$COUNT" ]; do
  echo "$PAYLOAD" | nc -q0 127.0.0.1 49901 2>/dev/null || true
  TOTAL=$((TOTAL + BYTES))
  i=$((i + 1))
done
END=$(date +%s%N 2>/dev/null || date +%s)

kill "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true

# Compute throughput (nanosecond precision if available)
if echo "$START" | grep -q "N" 2>/dev/null; then
  ELAPSED_NS=$((END - START))
  ELAPSED_MS=$((ELAPSED_NS / 1000000))
else
  ELAPSED_MS=$(( (END - START) * 1000 ))
fi

TOTAL_KB=$((TOTAL / 1024))
echo "Sent/echoed: ${TOTAL_KB} KB in ~${ELAPSED_MS}ms"
if [ "$ELAPSED_MS" -gt 0 ]; then
  THROUGHPUT_KBPS=$((TOTAL_KB * 1000 / ELAPSED_MS))
  echo "Throughput:  ~${THROUGHPUT_KBPS} KB/s (baseline; not representative of tuned perf)"
fi
echo ""
echo "Note: this measures single-connection sequential nc round-trips, not"
echo "concurrent throughput. See RFC 025 for the full benchmarking plan."
