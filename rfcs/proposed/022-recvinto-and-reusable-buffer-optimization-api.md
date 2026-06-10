# RFC 022: recvInto and Reusable Buffer Optimization API

**Status:** Future / Performance Candidate  
**Milestone:** M8  
**Priority:** Medium after baseline benchmarks  
**Primary layer:** Iotakt API / Native Boundary  
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

This RFC designs a future receive API that allows caller-provided Lean-owned buffers to be reused across reads. It must not replace the v0.1 default receive API unless benchmarks prove allocation overhead matters.

## Motivation

v0.1 intentionally chooses the simpler allocation policy: native `recv` returns a fresh Lean-owned `ByteArray`. This is auditable and safe. After correctness is established, high-throughput servers may benefit from reusing buffers to reduce allocation and copying pressure.

## Goals

- Define a safe contract for caller-owned receive buffers.
- Retain the no-C-side-buffering rule.
- Preserve readiness-as-hint and `EAGAIN` behavior.
- Allow jemmet connection actors to reuse per-connection scratch buffers.
- Define benchmark gates before adoption.

## Non-Goals

- Do not add native ring buffers.
- Do not retain pointers across FFI calls.
- Do not require unsafe buffer mutation in the default v0.1 API.
- Do not optimize before measuring baseline cost.

## External Design

Future API shape:

```lean
inductive RecvIntoResult where
  | read       : bytesRead : USize -> RecvIntoResult
  | wouldBlock : RecvIntoResult
  | eof        : RecvIntoResult
  | interrupted : RecvIntoResult
  | error      : IoErrno -> RecvIntoResult

unsafe def recvInto (fd : FdKey) (buf : ByteArray) (capacity : USize) : IO (ByteArray × RecvIntoResult)
```

The exact Lean signature should be chosen after experimentation. The important rule is that the returned value must re-establish Lean ownership and correct logical length.

## Data Model / Internal Design

The implementation needs an explicit uniqueness story. A safe wrapper may allocate a mutable object internally, call an unsafe primitive, and return a well-formed ByteArray. Directly mutating arbitrary shared ByteArrays is not acceptable.

Model impact is intentionally small: `recvInto` changes allocation strategy, not socket semantics. Read results remain the same.

## Lifecycle / Workflow

Typical jemmet actor workflow:

```text
actor owns reusable input buffer
IoReady(readable) arrives
actor calls recvInto(fd, buffer, capacity)
if bytesRead > 0: parser consumes prefix
if wouldBlock: actor keeps buffer and waits
if eof/error: actor closes stream
```

The actor must not assume the whole capacity was filled.

## Public API Impact

The existing `recv(fd, maxBytes)` remains the default. `recvInto` should be placed in an advanced or unsafe namespace until its contract is mature:

```text
Iotakt.Advanced.recvInto
Iotakt.Unsafe.recvIntoRaw
```

The public stable API should prefer the simpler v0.1 receive function.

## Native Boundary Impact

The C shim may receive a pointer to a mutable ByteArray payload only for the duration of one syscall. It must not store the pointer. It must return the byte count and errno classification immediately. It must not call malloc/free for application data.

## Security Considerations

Incorrect buffer length handling could expose uninitialized bytes. The wrapper must ensure that the returned ByteArray length is exactly the number of bytes read or the prior valid length according to the selected contract.

## Proof Obligations

Proofs should show that `recvInto` result classification is semantically equivalent to the baseline `recv` result classification. Allocation behavior itself is trusted/native, but model-level read state transitions must not differ.

## Test Obligations

Tests must include:

- reads shorter than capacity,
- exactly full capacity reads,
- zero-length/eof behavior,
- would-block behavior,
- repeated reuse of the same actor buffer,
- memory sanitizer/native sanitizer tests,
- parser-facing tests to ensure no stale bytes are exposed.

## Trust / Assumption Changes

This RFC adds a stronger FFI trust assumption: the native function mutates only the intended buffer region and returns the correct byte count. That assumption must be recorded separately from the simpler v0.1 `recv` contract.

## Architecture Gaps

Lean runtime details may change. The implementation should not depend on undocumented internals more than necessary. If Lean's FFI API shifts, this optimization may be postponed.

## Acceptance Criteria

- Baseline benchmarks identify allocation as a meaningful bottleneck.
- The unsafe primitive is wrapped by a narrow safe API.
- No uninitialized data can be observed through the public API.
- Tests compare `recv` and `recvInto` behavior under identical socket scenarios.

## Alternatives Considered

Keep only fresh ByteArray receive: acceptable until performance demands otherwise. Add C ring buffers: rejected as too much native state. Use Rust for buffer safety: rejected for this optimization unless the whole native policy is reconsidered.

## Open Questions

- Should `recvInto` expose capacity separately from ByteArray size?
- Should this be restricted to advanced users?
- Can Lean-side APIs guarantee uniqueness cleanly enough?
