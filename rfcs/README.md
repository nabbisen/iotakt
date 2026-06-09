# iotakt RFC Index

RFCs are managed according to [RFC 000 — RFC lifecycle policy](./done/000-rfc-lifecycle-policy.md).
The folder is the source of truth for each RFC's state.

## Done

| ID | Title | Status |
|----|-------|--------|
| 000 | [RFC lifecycle policy](./done/000-rfc-lifecycle-policy.md) | Implemented |

## Proposed (v0.1 scope — RFCs 001–015, 017–018)

These are the required RFCs for the v0.1 release. Design begins with the
Phase A (pure model) batch and proceeds through native, hardening, and
release.

### Phase A — Pure Model Foundation

| ID | Title |
|----|-------|
| 001 | [Project Scope, Architecture, and Boundary Policy](./proposed/001-project-scope-architecture-and-boundary-policy.md) |
| 002 | [Core Data Model and File Descriptor Identity](./proposed/002-core-data-model-and-file-descriptor-identity.md) |
| 003 | [Resource Lifecycle Model](./proposed/003-resource-lifecycle-model.md) |
| 004 | [Interest, Readiness, and Normalized Event Vocabulary](./proposed/004-interest-readiness-and-normalized-event-vocabulary.md) |
| 005 | [Registry, Event Translation, and Stale Event Rejection](./proposed/005-registry-event-translation-and-stale-event-rejection.md) |

### Phase B — Translation and Henret Integration

| ID | Title |
|----|-------|
| 006 | [Readiness Coalescing and Mailbox Flood Prevention](./proposed/006-readiness-coalescing-and-mailbox-flood-prevention.md) |
| 007 | [Henret Bridge and Deterministic Driver Loop](./proposed/007-henret-bridge-and-deterministic-driver-loop.md) |
| 008 | [Fake Poller and Deterministic Test Harness](./proposed/008-fake-poller-and-deterministic-test-harness.md) |

### Phase C — Native Boundary

| ID | Title |
|----|-------|
| 009 | [Native C FFI Boundary and Build Policy](./proposed/009-native-c-ffi-boundary-and-build-policy.md) |
| 010 | [Buffer Ownership, Read Semantics, and Write Semantics](./proposed/010-buffer-ownership-read-semantics-and-write-semantics.md) |
| 011 | [Linux epoll Backend](./proposed/011-linux-epoll-backend.md) |
| 012 | [Socket Provisioning and Listener/Stream API](./proposed/012-socket-provisioning-and-listener-stream-api.md) |

### Phase D — Hardening and Release

| ID | Title |
|----|-------|
| 013 | [Security, Operational Limits, and Failure Policy](./proposed/013-security-operational-limits-and-failure-policy.md) |
| 014 | [Proof, Trust, and Test Matrix](./proposed/014-proof-trust-and-test-matrix.md) |
| 015 | [Observability, Debugging, and Trace Format](./proposed/015-observability-debugging-and-trace-format.md) |
| 017 | [Public API Surface and Developer Experience](./proposed/017-public-api-surface-and-developer-experience.md) |
| 018 | [CI, Packaging, and Release Gates](./proposed/018-ci-packaging-and-release-gates.md) |

### Phase E — Compatibility and Future (model-aware, implementation optional for v0.1)

| ID | Title |
|----|-------|
| 016 | [kqueue Compatibility and BSD/macOS Backend Plan](./proposed/016-kqueue-compatibility-and-bsd-macos-backend-plan.md) |
| 019 | [Architecture Gap Register and Risk Management](./proposed/019-architecture-gap-register-and-risk-management.md) |
| 020 | [Future Optimizations and Advanced Features](./proposed/020-future-optimizations-and-advanced-features.md) |

## Proposed (v0.2+ scope — RFCs 021–060)

Post-v0.1 design RFCs for portability, performance, ecosystem, and advanced features.

| Range | Theme |
|-------|-------|
| 021–034 | kqueue backend, write helpers, benchmarking, CI hardening, performance, conformance, fault injection, FFI |
| 035–048 | Henret wait-queue parking, graceful shutdown, multi-listener, outbound connect, UDP, TLS boundary, model-based testing, advanced proofs |
| 049–060 | io_uring, Windows IOCP, QUIC/HTTP3, zero-copy, metrics, Lake packaging, io_uring, multi-process, buffer pools, post-v1 formal verification, API consolidation |

## Archive

No archived RFCs yet.
