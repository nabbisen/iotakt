# Introduction

*A small, auditable, non-blocking I/O readiness boundary for Lean 4 systems.*

`iotakt` bridges operating-system socket readiness with Henret actor
messages. It sits between an HTTP server (`jemmet`, a separate project) and
the Henret actor/scheduler runtime:

```
jemmet  ──▶  iotakt  ──▶  henret
(HTTP)        (I/O)        (actors)
```

Its role is narrow and precise: translate OS readiness events into
Henret-compatible actor messages while keeping the boundary small, proven,
and auditable. It is **not** an HTTP server, not a TLS stack, not a general
async runtime — those live above or below this layer.

## What this book covers

This documentation is organized by reader:

- **Intermediate users** building on iotakt: the jemmet handoff surface,
  keep-alive and consumer patterns, chunked encoding, the TLS boundary, and
  the Henret integration contract.
- **Maintainers and contributors**: the proof/trust/test matrix, the API
  stability review, the native FFI contract and its hardening, the
  architecture gap register, and design analyses (Gap 004 ActorId, kqueue
  compatibility, the benchmark).

For a quick orientation and a build-and-run quick start, see the project
`README.md`. For the precise public surface and its stability classification,
see [API Stability Review](./api-stability.md). For what is proven vs. tested
vs. assumed, see the [Proof, Trust, and Test Matrix](./proof-trust-test-matrix.md).

## Status

iotakt is at a **v1.0-candidate** surface (v0.13.0-dev): the core consumer
API is settled, with 77 machine-checked theorems (no `sorry`/`axiom`) and a
27-step CI gate. The HTTP server that consumes it, **jemmet**, is a separate
project — see `rfcs/handoff/jemmet/prototype/` for its starting material.
