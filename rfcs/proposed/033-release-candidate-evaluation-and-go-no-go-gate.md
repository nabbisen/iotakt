# RFC 033: Release Candidate Evaluation and Go/No-Go Gate

**Status:** Proposed / Release Governance  
**Milestone:** M7  
**Priority:** High before release  
**Primary layer:** Release Engineering / Governance  
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

This RFC defines the evaluation checklist for declaring an iotakt release candidate ready. It ties together RFC completion, model proofs, native tests, documentation, and known gaps.

## Motivation

A boundary library with formal claims should not be released solely because it builds. The project needs an explicit go/no-go gate that checks whether claims, tests, and documentation match the actual implementation.

## Goals

- Define release candidate checklist.
- Prevent overstated proof claims.
- Ensure native backend assumptions are tested or documented.
- Ensure known gaps are accepted explicitly.

## Non-Goals

- Do not create bureaucratic release overhead for every small commit.
- Do not require all future RFCs before v0.1.
- Do not claim production readiness unless separately justified.
- Do not block Lean-only release on future kqueue/io_uring work.

## External Design

Release candidate categories:

```text
RFC status
Lean-only build
proof build
fake poller tests
native epoll build/tests if included
conformance tests
security/limit tests
documentation examples
proof/trust/test matrix
architecture gap register
release notes
```

## Data Model / Internal Design

A release checklist file should live in docs or release:

```text
docs/release/v0.1-rc-checklist.md
```

Each row should include status, evidence link, owner/reviewer, and decision.

## Lifecycle / Workflow

Go/no-go workflow:

```text
implementation frozen for RC
checklist completed
matrix reviewed
known gaps classified
examples tested
release notes drafted
go/no-go decision recorded
```

## Public API Impact

Public API must be frozen for the candidate. Experimental APIs may remain unstable if marked clearly.

## Native Boundary Impact

If native epoll is included in the release, native conformance tests and hardening flags are release gates. If native backend is excluded, the release must clearly say Lean-only/model release.

## Security Considerations

Security-relevant requirements such as non-blocking enforcement, close-on-exec, SIGPIPE prevention, resource limits, stale-event rejection, and bounded readiness must be checked explicitly.

## Proof Obligations

All advertised theorem claims must compile without `sorry` unless a deliberate research/prototype exception is documented. Any assumption must appear in the matrix.

## Test Obligations

All release-blocking tests must be deterministic. Flaky tests cannot be release gates unless quarantined with clear policy.

## Trust / Assumption Changes

The release decision itself is a governance claim. It records evidence but does not prove future behavior.

## Architecture Gaps

Some gaps will remain. The point is not zero gaps; the point is explicit accepted gaps.

## Acceptance Criteria

- RC checklist exists.
- Matrix and gap register are up to date.
- Release notes state whether native backend is included.
- All advertised examples compile/run as documented.
- Go/no-go decision is recorded in English Markdown.

## Alternatives Considered

Release whenever CI passes: rejected because CI may not cover trust claims. Require all future RFCs: rejected. Avoid releases until production-ready: rejected because model-first libraries can release useful milestones.

## Open Questions

- Who signs off on release claims?
- Should v0.1 be Lean-only first or include epoll native backend?
- Should henejt prototype validation be a v0.1 gate or v0.2 gate?
