# RFC 019: Architecture Gap Register and Risk Management

**Status:** Proposed / Living  
**Milestone:** M7  
**Priority:** Medium  
**Primary layer:** Governance and Design Management

## Document Control

- **Project:** iotakt
- **Language:** Lean 4 with an optional native C boundary
- **Primary stack position:** `henejt` → `iotakt` → `henret`
- **Design principle:** Lean-first model, explicit trusted boundary, no hidden async runtime
- **Date:** 2026-06-08

## Common Terminology

- **Raw fd:** the integer file descriptor returned by the host OS.
- **FdKey:** stable iotakt identity, composed of `raw_fd` and a monotonic generation.
- **Interest:** what iotakt asked the poller to observe, normally readability or writability.
- **Readiness:** a host hint that an operation may make progress; it is not a guarantee.
- **Registry:** the Lean-side state that maps active `FdKey`s to owner actors and interests.
- **Native boundary:** the optional C FFI layer that performs POSIX socket and poller calls.
- **Bridge:** the deterministic Lean layer that translates iotakt events into Henret operations/messages.

## Summary

This RFC defines a living architecture gap register for risks discovered during iotakt design and implementation.

## Motivation

The design intentionally crosses difficult boundaries: Lean runtime FFI, OS readiness semantics, Henret integration, and future portability. Some gaps will remain open during v0.1. A living gap register prevents these issues from being forgotten or accidentally converted into undocumented assumptions.

## Goals

- Track accepted, mitigated, deferred, and out-of-scope gaps.
- Tie gaps to proof/trust/test matrix updates.
- Record severity and mitigation owner/target milestone.
- Prevent known weaknesses from disappearing into implementation notes.

## Non-Goals

- Do not block all development on low-severity future concerns.
- Do not treat gap register as a substitute for RFC updates.
- Do not hide security-relevant gaps in issue comments only.

## External Design

Gap register shape:

```text
ID | Title | Severity | Status | Affected RFCs | Classification impact | Mitigation | Target
```

Initial gaps include Henret blocked-state limitation, ByteArray FFI fragility, kqueue semantic differences, actor cleanup hook maturity, native CI portability, and performance unknowns.

## Data Model / Internal Design

```lean
-- The gap register is documentation, not Lean model code.
```

However, any gap affecting a theorem target must produce either a changed theorem, a weakened claim, or an explicit assumption/out-of-scope entry.

## Lifecycle / Workflow

Gap workflow:

```text
gap discovered → classify severity/status → link RFC/matrix
               → mitigation or deferral decision → review before release
```

## Public API Impact

No direct public API impact unless a gap changes accepted behavior or stability policy.

## Native Boundary Impact

Native-related gaps must be reflected in native build/test plans and matrix classifications.

## Henret Integration Impact

Henret-related gaps must be tracked separately from iotakt model gaps to avoid blaming the wrong layer.

## Security Considerations

Security-relevant gaps cannot be accepted silently. They require either mitigation, release blocker status, or explicit out-of-scope classification.

## Proof Obligations

- No theorem obligations, but proof claims must be updated when gaps affect them.

## Test Obligations

- Release checklist verifies gap register reviewed.
- High/critical open gaps are either mitigated or explicitly accepted by maintainer decision.

## Trust / Assumption Changes

- Some risks are architectural judgments, not mechanically testable facts.
- Gap statuses require governance discipline.

## Architecture Gaps

- The register can become stale if not tied to release gates.
- Severity estimates may change after implementation.

## Acceptance Criteria

- Gap register file exists.
- Initial gaps are listed.
- Each gap has status and mitigation/defer/outscope decision.
- Release checklist includes gap review.

## Alternatives Considered

- Use GitHub issues only: rejected because architectural release decisions need a stable document.
- No gap process: rejected because iotakt has deliberate proof/native boundaries.

## Open Questions

- Exact location; recommended `docs/architecture-gap-register.md`.
- Who approves accepting a high-severity gap.

