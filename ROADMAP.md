# Roadmap

See `rfcs/README.md` for the full RFC index. This file is a high-level
milestone overview.

## Current milestone: v0.1.0-dev — Pure model + Henret bridge

**Status:** In progress.

Completed:
- Pure model (RFCs 002–006): `FdKey`, registry, lifecycle, events,
  translation, coalescing — all with machine-checked theorems.
- Henret bridge (RFC 007): deterministic driver, guarded inject,
  `inject_ok_of_mailbox` theorem.
- Fake poller (RFC 008): deterministic scripted backend, replay lemmas.
- Demo: 7 canonical scenarios, 19 checks, all PASS.
- Proof/trust/test matrix, henret integration notes.

Remaining for v0.1.0:
- RFC 009–012: native C FFI, buffer ownership, Linux epoll, socket API.
- RFC 013: security, operational limits, graceful shutdown.
- RFC 014: full proof matrix review and final CI.
- RFC 015: observability/trace.
- RFC 017: public API review.
- RFC 018: CI, Lake packaging, release gates.
- RFC 016: kqueue model compatibility analysis (implementation deferred).
- RFC 019: architecture gap register.

## v0.2.0 — kqueue backend

- RFC 021: BSD/macOS kqueue native backend.
- RFC 023: echo-server example.
- Additional conformance tests.

## v0.3.0 — API stabilization and henejt integration

- RFC 025: performance benchmarks.
- RFC 017 rev: stable public API based on henejt feedback.
- RFC 020 / RFC 026: native conformance suite.

## Future (v0.2+ → long-term)

- RFC 028: Lean FFI hardening.
- RFC 035: Henret wait-queue parking integration (when available).
- RFC 036: UDP sockets.
- RFC 041: TLS boundary.
- RFC 056: io_uring backend research.
- RFC 059: post-v1 formal verification expansion.
