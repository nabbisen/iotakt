# iotakt RFC index

RFCs follow [RFC 000 — RFC lifecycle policy](./done/000-rfc-lifecycle-policy.md).
Folder location is the lifecycle source of truth. This index lists every RFC file in
`done/`, `proposed/`, and `archive/`; cross-team correspondence under `handoff/` is
indexed separately by [its own README](./handoff/README.md) and has no RFC lifecycle.

## Current release decision

**No-Go remains in force.** RFCs 064–070 are the release-blocking remediation train;
RFC 070 is the maintainer-approved 2026-07-14 jemmet consumer-scope amendment.
Supporting RFCs 029, 032, 033, and 046 are scheduled by the current
[`ROADMAP.md`](../ROADMAP.md). Release/v1.0 promotion remains frozen until RFC 033
records an evidence-backed independent Go.

## Proposed — release-blocking remediation

| ID | RFC | Primary finding |
|---|---|---|
| 064 | [Generation-safe effectful fd authority](./proposed/064-generation-safe-effectful-fd-authority.md) | B1, N3 |
| 065 | [Native buffer bounds and enforced runtime I/O limits](./proposed/065-native-buffer-bounds-and-runtime-io-limits.md) | B2 |
| 066 | [Authoritative event delivery and state-safe native transitions](./proposed/066-authoritative-event-delivery-and-state-safe-native-transitions.md) | B3, N1, N2, N4 |
| 067 | [Fail-closed CI, sanitizer, and clean-checkout evidence](./proposed/067-fail-closed-ci-sanitizer-and-clean-checkout-evidence.md) | B4, N4 |
| 068 | [Tracked-source release packaging and complete provenance](./proposed/068-tracked-source-release-packaging-and-complete-provenance.md) | B5 |
| 069 | [Architecture baseline, scope, and documentation integrity](./proposed/069-architecture-baseline-scope-and-documentation-integrity.md) | B6 |
| 070 | [Address-aware listener identity and lifecycle](./proposed/070-address-aware-listener-identity-and-lifecycle.md) | Jemmet M2C consumer contract; listener lifecycle |

## Proposed — scheduled remediation support

| ID | RFC | Scheduled role |
|---|---|---|
| 029 | [Fault Injection and Failure Scenario Testing](./proposed/029-fault-injection-and-failure-scenario-testing.md) | R2 transition-failure evidence for RFC 066 |
| 032 | [Documentation, Examples, and Guided Tour](./proposed/032-documentation-examples-and-guided-tour.md) | R4 user documentation after RFC 069 baseline |
| 033 | [Release Candidate Evaluation and Go/No-Go Gate](./proposed/033-release-candidate-evaluation-and-go-no-go-gate.md) | R5 final requalification and independent review |
| 046 | [Security Review Playbook and Native Audit Checklist](./proposed/046-security-review-playbook-and-native-audit-checklist.md) | R4/R5 security audit support |

## Proposed — post-Go and future work

These RFCs are not part of the remediation critical path unless a blocking RFC makes
one an explicit dependency.

| ID | RFC |
|---|---|
| 020 | [Future Optimizations and Advanced Features](./proposed/020-future-optimizations-and-advanced-features.md) |
| 021 | [BSD and macOS kqueue Native Backend Implementation](./proposed/021-bsd-and-macos-kqueue-native-backend-implementation.md) |
| 022 | [recvInto and Reusable Buffer Optimization API](./proposed/022-recvinto-and-reusable-buffer-optimization-api.md) |
| 023 | [Edge-Triggered and One-Shot Polling Semantics](./proposed/023-edge-triggered-and-one-shot-polling-semantics.md) |
| 024 | [Write-Side Helper Layer and Partial Write Adapter](./proposed/024-write-side-helper-layer-and-partial-write-adapter.md) |
| 027 | [jemmet Integration Adapter and Server Driver Preparation](./proposed/027-jemmet-integration-adapter-and-server-driver-preparation.md) |
| 031 | [API Versioning, Feature Flags, and Compatibility Policy](./proposed/031-api-versioning-feature-flags-and-compatibility-policy.md) |
| 034 | [Research Notes for io_uring, IOCP, and Multi-Poller Backends](./proposed/034-research-notes-for-io-uring-iocp-and-multi-poller-backends.md) |
| 035 | [Henret Wait-Queue Parking Integration](./proposed/035-henret-wait-queue-parking-integration.md) |
| 036 | [Supervisor and Actor Lifecycle Integration](./proposed/036-supervisor-and-actor-lifecycle-integration.md) |
| 038 | [Multi-Listener and Service Topology](./proposed/038-multi-listener-and-service-topology.md) |
| 039 | [Outbound TCP Connect and Non-Blocking Connect Workflow](./proposed/039-outbound-tcp-connect-and-non-blocking-connect-workflow.md) |
| 040 | [Socket Options and Operational Configuration](./proposed/040-socket-options-and-operational-configuration.md) |
| 042 | [Unix Domain Socket and Local IPC Backend](./proposed/042-unix-domain-socket-and-local-ipc-backend.md) |
| 043 | [Capability-Oriented Fd Handle API and Authority Minimization](./proposed/043-capability-oriented-fd-handle-api-and-authority-minimization.md) |
| 044 | [Formal Refinement Contracts for Poller Backends](./proposed/044-formal-refinement-contracts-for-poller-backends.md) |
| 045 | [Model-Based Testing, Trace Fuzzing, and Differential Replay](./proposed/045-model-based-testing-trace-fuzzing-and-differential-replay.md) |
| 047 | [Production Operations Guide, Limits, and Incident Diagnostics](./proposed/047-production-operations-guide-limits-and-incident-diagnostics.md) |
| 048 | [Long-Term Governance, RFC Lifecycle, and Ecosystem Fit](./proposed/048-long-term-governance-rfc-lifecycle-and-ecosystem-fit.md) |
| 049 | [UDP and Datagram Socket Boundary](./proposed/049-udp-and-datagram-socket-boundary.md) |
| 050 | [DNS Resolver Boundary](./proposed/050-dns-resolver-boundary.md) |
| 051 | [Windows IOCP Backend](./proposed/051-windows-iocp-backend.md) |
| 052 | [QUIC and HTTP/3 Boundary](./proposed/052-quic-and-http3-boundary.md) |
| 053 | [Zero-Copy and Kernel-Assisted File Transfer](./proposed/053-zero-copy-and-kernel-assisted-file-transfer.md) |
| 054 | [Metrics Export and Operational Telemetry Format](./proposed/054-metrics-export-and-operational-telemetry-format.md) |
| 055 | [Lake Distribution, Package Registry, and Release Channel Policy](./proposed/055-lake-distribution-package-registry-and-release-policy.md) |
| 056 | [io_uring Backend Adoption](./proposed/056-io-uring-backend-adoption.md) |
| 057 | [Multi-Process Topology and File Descriptor Passing](./proposed/057-multiprocess-topology-and-fd-passing.md) |
| 058 | [Advanced Buffer Pool and Memory Strategy](./proposed/058-advanced-buffer-pool-and-memory-strategy.md) |
| 059 | [Post-v1 Formal Verification Expansion](./proposed/059-post-v1-formal-verification-expansion.md) |
| 060 | [Post-v1 API Consolidation and Ecosystem Integration](./proposed/060-post-v1-api-consolidation-and-ecosystem-integration.md) |

## Implemented

| ID | RFC | Shipped/recorded state |
|---|---|---|
| 000 | [RFC lifecycle policy](./done/000-rfc-lifecycle-policy.md) | Implemented |
| 001 | [Project Scope, Architecture, and Boundary Policy](./done/001-project-scope-architecture-and-boundary-policy.md) | v0.1.0-dev |
| 002 | [Core Data Model and File Descriptor Identity](./done/002-core-data-model-and-file-descriptor-identity.md) | v0.1.0-dev |
| 003 | [Resource Lifecycle Model](./done/003-resource-lifecycle-model.md) | v0.1.0-dev |
| 004 | [Interest, Readiness, and Normalized Event Vocabulary](./done/004-interest-readiness-and-normalized-event-vocabulary.md) | v0.1.0-dev |
| 005 | [Registry, Event Translation, and Stale Event Rejection](./done/005-registry-event-translation-and-stale-event-rejection.md) | v0.1.0-dev |
| 006 | [Readiness Coalescing and Mailbox Flood Prevention](./done/006-readiness-coalescing-and-mailbox-flood-prevention.md) | v0.1.0-dev |
| 007 | [Henret Bridge and Deterministic Driver Loop](./done/007-henret-bridge-and-deterministic-driver-loop.md) | v0.1.0-dev |
| 008 | [Fake Poller and Deterministic Test Harness](./done/008-fake-poller-and-deterministic-test-harness.md) | v0.1.0-dev |
| 009 | [Native C FFI Boundary and Build Policy](./done/009-native-c-ffi-boundary-and-build-policy.md) | v0.1.0-dev |
| 010 | [Buffer Ownership, Read Semantics, and Write Semantics](./done/010-buffer-ownership-read-semantics-and-write-semantics.md) | v0.1.0-dev |
| 011 | [Linux epoll Backend](./done/011-linux-epoll-backend.md) | v0.1.0-dev |
| 012 | [Socket Provisioning and Listener/Stream API](./done/012-socket-provisioning-and-listener-stream-api.md) | v0.1.0-dev |
| 013 | [Security, Operational Limits, and Failure Policy](./done/013-security-operational-limits-and-failure-policy.md) | v0.1.0-dev |
| 014 | [Proof, Trust, and Test Matrix](./done/014-proof-trust-and-test-matrix.md) | v0.1.0-dev |
| 015 | [Observability, Debugging, and Trace Format](./done/015-observability-debugging-and-trace-format.md) | v0.1.0-dev |
| 016 | [kqueue Compatibility and BSD/macOS Backend Plan](./done/016-kqueue-compatibility-and-bsd-macos-backend-plan.md) | v0.3.0-dev analysis; native deferred |
| 017 | [Public API Surface and Developer Experience](./done/017-public-api-surface-and-developer-experience.md) | v0.2.0-dev |
| 018 | [CI, Packaging, and Release Gates](./done/018-ci-packaging-and-release-gates.md) | v0.1.0-dev; remediation RFCs 067–068 follow |
| 019 | [Architecture Gap Register and Risk Management](./done/019-architecture-gap-register-and-risk-management.md) | v0.1.0-dev |
| 025 | [Performance Benchmarking and Regression Gates](./done/025-performance-benchmarking-and-regression-gates.md) | v0.5.0-dev |
| 026 | [Native Conformance Test Suite](./done/026-native-conformance-test-suite.md) | v0.4.0-dev |
| 028 | [Lean FFI Compatibility and Native Boundary Hardening](./done/028-lean-ffi-compatibility-and-native-boundary-hardening.md) | v0.4.0-dev; remediation RFC 065 follows |
| 030 | [Resource Limits and Load-Shedding Policy](./done/030-resource-limits-and-load-shedding-policy.md) | v0.11.0-dev |
| 037 | [Graceful Shutdown, Drain, and Listener Stop Workflow](./done/037-graceful-shutdown-drain-and-listener-stop-workflow.md) | v0.11.0-dev |
| 041 | [TLS Boundary, ALPN, and Secure Transport Handoff](./done/041-tls-boundary-alpn-and-secure-transport-handoff.md) | v0.6.0-dev design boundary |
| 061 | [Model/Bridge Package Split](./done/061-model-bridge-package-split.md) | v0.14.0-dev, Option B |
| 062 | [Release-Provenance Manifest](./done/062-release-provenance-manifest.md) | v0.13.4-dev; remediation RFC 068 follows |
| 063 | [Stack-Contract Dependency Edges](./done/063-stack-contract-dependency-edges.md) | v0.14.2-dev |

## Archive

No RFCs are currently archived.

## Lifecycle operations

- New design work starts in `proposed/` with a stable unused number.
- Implemented work moves to `done/` with its Status field and this index updated in
  the same change.
- Withdrawn or superseded work moves to `archive/` with the reason/replacement.
- Numbers are never reused or renumbered.
