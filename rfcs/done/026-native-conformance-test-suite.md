# RFC 026: Native Conformance Test Suite

**Status.** Implemented (v0.4.0-dev)

**Status:** Proposed / Post-Core Hardening  
**Milestone:** M5/M7  
**Priority:** High before native release  
**Primary layer:** Testing / Native Boundary  
**Project:** iotakt  
**Stack position:** `jemmet → iotakt → henret`  
**Date:** 2026-06-08

---

## Document Intent

This RFC belongs to the continuation set after the v0.1 core RFC batch. It is intentionally detailed enough to guide implementation later, but it must not silently expand the v0.1 release boundary unless its status explicitly says so.

The governing principles remain:

- pure Lean model first,
- optional native boundary,
- no hidden async runtime,
- no C-side application buffering,
- readiness is a hint rather than a guarantee,
- file descriptors are identified by `FdKey(raw_fd, generation)`, not by raw fd alone,
- proof/trust/test classification is mandatory for every correctness claim.

## Summary

This RFC defines conformance tests for the C native boundary. The goal is to test exactly the assumptions that the Lean proofs cannot prove: syscall classification, errno handling, non-blocking behavior, close semantics, and backend event normalization.

## Motivation

iotakt can prove the pure translator but must trust the OS and FFI wrappers. A native conformance suite makes these assumptions visible and repeatedly testable.

## Goals

- Test every C wrapper used by the public native backend.
- Validate errno classification for common non-blocking outcomes.
- Test stale event and close/deregister behavior at the integration boundary.
- Run sanitizers where available.

## Non-Goals

- Do not prove OS kernel behavior.
- Do not require network access to external hosts.
- Do not test HTTP/TLS behavior.
- Do not replace Lean model tests.

## External Design

Conformance categories:

```text
fd policy:
  nonblocking set
  close-on-exec set
  double-close behavior classified safely

recv/send:
  would-block
  partial write where inducible
  eof
  interrupted where practical
  sigpipe prevention

poller:
  read readiness
  write readiness
  unregister
  close after register
  bounded event batch
```

Use `socketpair` where possible to avoid external network dependence.

## Data Model / Internal Design

Suggested modules/files:

```text
test/native/c_shim_conformance.c
test/Iotakt/NativeConformance.lean
test/Iotakt/SocketPair.lean
```

The test suite should expose small repeatable fixtures rather than relying on sleeps and timing races.

## Lifecycle / Workflow

Conformance workflow:

```text
build native shim with strict warnings
run C-level unit tests if present
run Lean native integration tests
run sanitizer variant
record tested assumptions in matrix
```

## Public API Impact

No public API change. Test-only helpers must be clearly separated from user modules.

## Native Boundary Impact

The suite directly exercises native wrappers. It may require test-only wrappers for introspection, such as reading fd flags, but those wrappers must not be exported as part of the stable API.

## Security Considerations

Tests should verify `FD_CLOEXEC`, non-blocking mode, and SIGPIPE prevention. These are security/reliability properties, not performance details.

## Proof Obligations

No theorem can replace these tests. The test results support ASSUMED/TESTED entries in the trust matrix.

## Test Obligations

The entire RFC is about tests. Minimum release gate:

- Linux epoll conformance passes,
- socket provisioning conformance passes,
- buffer read/write classification passes,
- sanitizer job passes or documented unavailable,
- failure cases return structured errors rather than crashes.

## Trust / Assumption Changes

The suite reduces but does not eliminate trust in C wrappers and OS behavior. Kernel bugs, platform differences, and Lean runtime FFI changes remain assumptions.

## Architecture Gaps

Some outcomes such as EINTR can be hard to trigger deterministically. Partial writes may require small socket buffers or controlled pipes. Tests must avoid flakiness.

## Acceptance Criteria

- Conformance suite exists and is documented.
- It runs in CI for supported native platforms.
- The trust matrix links each native assumption to at least one test where possible.
- Flaky timing-dependent tests are avoided or quarantined.

## Alternatives Considered

Rely on manual testing: rejected. Rely only on fake poller tests: rejected because fake tests do not validate FFI. Use external network integration tests: rejected for release-critical tests.

## Open Questions

- Should native tests be run by default or only under `lake exe test-native`?
- How should OpenBSD conformance be handled without hosted CI?
- Should the C shim have its own tiny test executable?
