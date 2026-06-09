---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 054: Metrics Export and Operational Telemetry Format

## Summary

This RFC defines a post-v1 telemetry and metrics export format for iotakt. v1 may include basic trace
logging and debug events, but production users may eventually need stable counters, gauges, histograms,
and diagnostic snapshots. This RFC keeps observability explicit without turning iotakt into a
monitoring framework.

## Motivation

Operational users need to understand connection counts, event-loop behavior, readiness floods,
would-block rates, partial writes, error rates, close reasons, and native backend health. However,
observability code can easily pollute the core model or introduce dependencies. A post-v1 metrics
format should be minimal, pull-based where possible, and compatible with plain-text export.

## Goals

- Define stable metric names and meanings.
- Keep metrics optional and dependency-light.
- Support both test diagnostics and production operations.
- Avoid background exporter threads in core iotakt.
- Preserve deterministic model tests.

## Non-goals

- No built-in Prometheus HTTP server in core iotakt.
- No OpenTelemetry dependency in core iotakt.
- No distributed tracing system.
- No automatic PII or payload logging.
- No metrics that require storing application data.

## Metric categories

### Resource lifecycle metrics

```text
iotakt_fd_open_total
iotakt_fd_close_total
iotakt_fd_current
iotakt_fd_stale_event_dropped_total
iotakt_fd_double_close_rejected_total
```

### Poller metrics

```text
iotakt_poll_wait_total
iotakt_poll_wait_interrupted_total
iotakt_poll_events_total
iotakt_poll_timeout_total
iotakt_poll_backend_errors_total
```

### Read/write metrics

```text
iotakt_recv_bytes_total
iotakt_recv_would_block_total
iotakt_recv_eof_total
iotakt_send_bytes_total
iotakt_send_partial_total
iotakt_send_would_block_total
```

### Coalescing and mailbox protection metrics

```text
iotakt_ready_injected_total
iotakt_ready_coalesced_total
iotakt_ready_suppressed_total
```

## Data model

```lean
structure MetricsSnapshot where
  counters : List (String × UInt64)
  gauges : List (String × Int64)
```

Histograms may be added later, but v1-style simplicity should prefer counters and gauges first.

## Export options

### Option A: Lean snapshot API

```lean
snapshotMetrics : IotaktDriver -> IO MetricsSnapshot
```

The application decides how to expose the metrics.

### Option B: plain-text renderer

```lean
renderMetricsText : MetricsSnapshot -> String
```

This can support Prometheus-like scraping without requiring an HTTP server inside iotakt.

### Option C: structured JSON renderer

Useful for tests and offline diagnostics, but should remain optional.

## Workflow

1. Driver maintains counters in Lean-owned state where possible.
2. Native backend may report low-level counters through explicit query calls.
3. Application requests snapshot.
4. Application exports through its own HTTP/admin endpoint if desired.

## Security and privacy

Metrics must not include:

- raw payload bytes,
- full peer addresses by default,
- HTTP paths,
- TLS information,
- actor-private protocol state.

Peer address aggregation may be added only with explicit privacy review.

## Proof/trust/test classification

PROVEN candidates:

- Metrics updates do not affect modeled event translation results.
- Snapshot is observational and does not mutate driver state except optional read counters.

TESTED:

- Counters increment for known workflows.
- Renderers produce stable output.

OUTSCOPE:

- Correctness of external monitoring systems.

## Acceptance criteria

- Metrics are optional and do not add external dependencies.
- Export is pull-based or application-owned.
- Metric names are documented and versioned.
- Tests confirm that disabling metrics does not change driver behavior.
