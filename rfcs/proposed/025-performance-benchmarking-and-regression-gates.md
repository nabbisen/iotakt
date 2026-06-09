# RFC 025: Performance Benchmarking and Regression Gates

**Status:** Proposed / Post-Core Hardening  
**Milestone:** M7/M8  
**Priority:** Medium  
**Primary layer:** Testing / Release Engineering  
**Project:** iotakt  
**Stack position:** `henejt → iotakt → henret`  
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

This RFC defines benchmark categories and regression gates for iotakt after the correctness baseline exists. Performance work must be evidence-based and must not weaken proof or boundary discipline.

## Motivation

Low-level I/O code naturally attracts optimization pressure. Without benchmark policy, optimizations such as `recvInto`, edge-triggered polling, batching, or io_uring may be added based on intuition. iotakt should first measure the simple design.

## Goals

- Define repeatable benchmark scenarios.
- Separate Lean model performance from native socket performance.
- Measure allocation cost before optimizing buffers.
- Prevent performance changes from bypassing safety gates.

## Non-Goals

- Do not require production-grade benchmarking infrastructure for v0.1.
- Do not compare against Tokio/libuv as a release blocker.
- Do not sacrifice determinism or auditability for benchmark wins.
- Do not treat synthetic benchmark results as application performance guarantees.

## External Design

Benchmark categories:

```text
model-only:
  registry translation events/sec
  coalescing overhead
  fake poller driver loop traces

native micro:
  socketpair recv/send latency
  epoll wait+dispatch overhead
  accept loop overhead

integration:
  simple echo server
  henejt hello-world HTTP when available
```

Benchmark reports should include platform, Lean version, compiler, backend, CPU, kernel, and build flags.

## Data Model / Internal Design

The benchmark harness should avoid contaminating the core library. Suggested layout:

```text
bench/
  ModelTranslationBench.lean
  FakeDriverBench.lean
  NativeSocketPairBench.lean
  EchoServerBench.lean
```

Benchmarks may use native helper executables or Lake scripts, but the default library build should remain lightweight.

## Lifecycle / Workflow

Performance workflow:

```text
baseline measured
change proposed
benchmark run before/after
correctness tests run
trust matrix reviewed if boundary changes
regression accepted/rejected with rationale
```

## Public API Impact

No public API impact. Benchmark helpers should not become public unless separately justified.

## Native Boundary Impact

Native benchmarks may exercise C shims heavily, but must not add new shims solely for measurement unless marked internal/test-only.

## Security Considerations

Benchmark modes must not disable important safety policies by default. Any unsafe fast path must require explicit feature selection and separate RFC approval.

## Proof Obligations

No direct proof obligations. However, any optimization motivated by benchmarks must state whether it changes existing theorem statements or assumptions.

## Test Obligations

Benchmark execution should be separate from correctness CI. Nightly or manual benchmark runs are acceptable. Minimal smoke benchmarks can run in CI if stable enough.

## Trust / Assumption Changes

Performance claims are TESTED, never PROVEN. Claims must be scoped to measured platforms.

## Architecture Gaps

Lean runtime and native FFI overhead may vary by Lean version. Kernel/network stack differences can dominate results. CI machines are noisy and should not be the only benchmark source.

## Acceptance Criteria

- Benchmark categories documented.
- Baseline numbers captured before optimization RFCs are promoted.
- Regression threshold policy exists.
- Benchmark artifacts do not expand the trusted boundary.

## Alternatives Considered

Ignore benchmarks until users complain: rejected because future optimization decisions need evidence. Overbuild a full perf lab now: rejected as premature.

## Open Questions

- Which benchmark should be the first release smoke benchmark?
- Should benchmark results be stored in docs or release notes?
- What regression percentage should trigger review?
