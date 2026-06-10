# Throughput Benchmark

**iotakt — RFC 025**

This document records the methodology and baseline results for iotakt's
throughput benchmark (`iotakt-bench`).

---

## Methodology

The `iotakt-bench` binary measures HTTP/1.1-style request/response throughput
using a Unix `socketpair`. This eliminates network latency and kernel TCP
scheduling, giving a clean measurement of iotakt's I/O layer overhead:

- `ByteArray` allocation per `recv` (Option A policy)
- `WriteBuffer.flush` per `send`
- HTTP request serialisation and response deserialisation
- Non-blocking `recv`/`send` syscalls

The benchmark is **not** measuring:

- Real TCP/IP network latency
- Concurrent connection throughput
- Production HTTP server performance

For network-realistic single-connection sequential throughput, use
`scripts/bench.sh`.

### Protocol

```
Request:  GET /bench HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n
          = 64 bytes

Response: HTTP/1.0 200 OK\r\n
          Content-Type: text/plain\r\nContent-Length: 4\r\n
          Connection: keep-alive\r\n\r\n
          pong
          = 92 bytes
```

### Procedure

1. Create one Unix `socketpair` (non-blocking, close-on-exec).
2. Warm up with 50 round-trips (JIT and branch predictor warm-up).
3. Time 1000 sequential round-trips with `CLOCK_MONOTONIC`.
4. Report: succeeded/total, elapsed ms, requests/sec.

---

## Baseline results (v0.5.0-dev, 2026-06-08)

| Metric | Value |
|--------|-------|
| Platform | Ubuntu 24 on x86-64 (container) |
| Lean | 4.15.0 |
| Requests | 1000 |
| Elapsed | ~2–3 ms |
| **Throughput** | **~300,000–350,000 req/s** |

These numbers are not representative of production performance. They establish
a lower bound on iotakt's per-request overhead before any application logic:
each request requires two non-blocking syscalls (`recv` + `send`), two Lean
`ByteArray` allocations (one for recv output, one for response body), and two
`WriteBuffer` flush calls.

---

## Interpretation

At ~330k req/s with a 92-byte response:

```
Bandwidth ≈ 330,000 × (64 + 92) bytes = 51 MB/s per connection
```

This is close to the theoretical limit for a Unix socketpair in this
container environment. Real TCP connections will be 2–10× slower due to
kernel networking overhead; real application logic (HTTP parsing, routing,
handler execution) adds further overhead that is jemmet's responsibility.

---

## Future benchmarks

- RFC 025 v2: multi-connection concurrent throughput (N connections).
- RFC 025 v3: real TCP loopback vs socketpair comparison.
- RFC 025 v4: after `recvInto` optimization (MutableByteArray).
- RFC 025 v5: after Henret wait-queue parking (RFC 035).

These will be added in future releases.
