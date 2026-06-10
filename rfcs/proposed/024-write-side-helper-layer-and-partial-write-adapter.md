# RFC 024: Write-Side Helper Layer and Partial Write Adapter

**Status:** Future / Usability Candidate  
**Milestone:** M7/M8  
**Priority:** Medium  
**Primary layer:** Iotakt API  
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

This RFC designs an optional Lean-side helper for managing partial writes without moving application byte buffering into iotakt's core. The core syscall contract remains one non-blocking send operation returning the number of bytes written.

## Motivation

All non-blocking socket libraries must handle partial writes. If every jemmet or application actor reimplements suffix tracking, mistakes are likely. However, core iotakt must not become an application buffer manager. A small opt-in helper can provide reusable logic while preserving the core boundary.

## Goals

- Offer a Lean-only partial-write helper for common actor workflows.
- Keep application bytes owned by the actor or helper object, not native code.
- Preserve the simple core `send` primitive.
- Integrate write interest registration/deregistration guidance.

## Non-Goals

- Do not create native write queues.
- Do not hide backpressure from jemmet.
- Do not guarantee full send completion in one step.
- Do not make the helper mandatory.

## External Design

The helper can be a small state machine:

```lean
structure PendingWrite where
  bytes  : ByteArray
  offset : USize

inductive FlushResult where
  | complete
  | pending : PendingWrite -> FlushResult
  | wouldBlock : PendingWrite -> FlushResult
  | closed
  | error : IoErrno -> FlushResult
```

The helper consumes a pending write and repeatedly or singly calls core `send` according to a configured budget.

## Data Model / Internal Design

The helper must live above `Iotakt.Native`. It may live in `Iotakt.Util.WriteBuffer` or `Iotakt.ProtocolSupport`. It is pure/stateful Lean code plus calls to the existing send primitive.

No model invariant should depend on this helper. It is a convenience layer.

## Lifecycle / Workflow

Actor workflow:

```text
jemmet produces response bytes
actor stores PendingWrite(bytes, 0)
actor registers write interest
IoReady(writable) arrives
actor calls flushPending with a work budget
if complete: deregister write interest
if pending/wouldBlock: keep write interest
if error/closed: close stream
```

## Public API Impact

Candidate API:

```lean
def PendingWrite.ofByteArray (b : ByteArray) : PendingWrite
def flushOnce (fd : FdKey) (p : PendingWrite) : IO FlushResult
def flushBudgeted (fd : FdKey) (budgetBytes : USize) (p : PendingWrite) : IO FlushResult
```

These should be helpers, not core obligations.

## Native Boundary Impact

No new native calls. The helper uses existing `send`. This is intentionally Lean-side to avoid expanding the trusted native boundary.

## Security Considerations

The helper can prevent unbounded output growth only if jemmet also enforces response-size and per-connection queue limits. iotakt should expose patterns but not silently buffer arbitrary data.

## Proof Obligations

Possible proofs:

```text
flush progress never decreases offset
complete iff offset reaches bytes.size
pending suffix corresponds exactly to unsent bytes
helper never mutates fd registry
```

These are Lean-side proofs and are good candidates for early utility verification.

## Test Obligations

Tests:

- partial writes with fake send primitive,
- would-block after partial progress,
- complete in one write,
- closed/error handling,
- write interest recommendation examples.

## Trust / Assumption Changes

No new native trust assumptions. The helper relies on the existing send result classification.

## Architecture Gaps

This helper may tempt users to treat iotakt as a buffered I/O library. Documentation must be explicit that it is a local actor-owned helper.

## Acceptance Criteria

- Core API remains unchanged.
- Helper proves or tests suffix correctness.
- Examples show write interest enabled only while pending output exists.
- No native buffer or queue is introduced.

## Alternatives Considered

Leave partial write handling entirely to jemmet: simple but repetitive. Add native send queues: rejected. Add a full stream abstraction: deferred because it risks scope creep.

## Open Questions

- Should the helper be inside iotakt or jemmet?
- Should helper functions be fully pure over an abstract send algebra for easier proofs?
- Should budget be byte-based, syscall-count-based, or both?
