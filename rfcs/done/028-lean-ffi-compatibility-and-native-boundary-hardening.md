# RFC 028: Lean FFI Compatibility and Native Boundary Hardening

**Status.** Implemented (v0.4.0-dev)

**Status:** Proposed / Hardening  
**Milestone:** M5/M7  
**Priority:** High  
**Primary layer:** Native Boundary / Release Engineering  
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

This RFC defines how iotakt will manage Lean FFI instability, C ABI constraints, and native hardening practices over time.

## Motivation

Lean's FFI is powerful but low-level. iotakt depends on it for native sockets. The project must be explicit about supported Lean versions, C ABI patterns, ownership rules, and upgrade testing.

## Goals

- Document supported Lean versions and FFI compatibility policy.
- Keep C ABI flat and auditable.
- Prevent accidental reliance on unstable Lean runtime internals where possible.
- Define hardening flags and sanitizer practices.

## Non-Goals

- Do not abstract over all possible foreign language backends.
- Do not introduce Rust solely to avoid understanding the C boundary.
- Do not promise compatibility with every Lean nightly or future runtime change.
- Do not expose native C structs through Lean APIs.

## External Design

Compatibility policy:

```text
Tier 1 Lean version: pinned in lakefile/toolchain
Tier 2: latest stable Lean after smoke test
Unsupported: nightly/unreleased Lean unless explicitly tested
```

Native wrappers should expose primitive fields and Lean-owned objects only. No C struct by-value ABI should appear in extern signatures.

## Data Model / Internal Design

Hardening structure:

```text
native/include/iotakt.h
native/src/iotakt_posix.c
native/src/iotakt_epoll.c
native/src/iotakt_kqueue.c (future)
Iotakt/Native/Extern.lean
Iotakt/Native/Error.lean
```

All ownership-sensitive functions should have comments describing whether Lean objects are owned or borrowed.

## Lifecycle / Workflow

Upgrade workflow:

```text
Lean version bump proposed
build Lean-only model
build native backend
run FFI smoke tests
run native conformance tests
review ownership-sensitive code
update compatibility notes
```

## Public API Impact

No ordinary public API impact. Internal native modules should avoid exposing raw externs directly. Public APIs should wrap native results into typed Lean result values.

## Native Boundary Impact

Hardening flags:

```text
-Wall -Wextra -Werror
-fno-strict-aliasing if needed
ASAN/UBSAN test builds where available
no malloc/free for application buffers
no retained Lean object pointers
errno captured immediately
```

Build scripts must fail loudly if native features are requested but the compiler/platform is unsupported.

## Security Considerations

FFI mistakes can cause memory unsafety or process crashes. The hardening policy is part of iotakt's security model. Strict compiler flags and sanitizer runs are release gates for native backends.

## Proof Obligations

No proof can establish C memory safety from Lean. The proof/trust/test matrix must classify native memory safety as ASSUMED/TESTED and link to conformance/sanitizer evidence.

## Test Obligations

Tests:

- extern smoke tests,
- ownership path tests for recv ByteArray allocation,
- error path tests,
- sanitizer builds,
- Lean version compatibility CI matrix when feasible.

## Trust / Assumption Changes

Assume Lean runtime FFI functions behave according to the versioned Lean reference and implementation. Assume C compiler respects the configured ABI and flags.

## Architecture Gaps

Lean FFI APIs may change. Some hardening flags are platform/compiler-specific. Sanitizers may not be available in every CI target.

## Acceptance Criteria

- FFI ownership policy is documented.
- Supported Lean versions are declared.
- Native build uses strict warnings.
- CI has at least one sanitizer/hardening job or records why it is unavailable.
- Raw externs are not the main user API.

## Alternatives Considered

Avoid native backend entirely: unacceptable for socket library goals. Use Rust FFI from day one: rejected for v0.1 minimalism. Use libuv: rejected due to heavy dependency and hidden semantics.

## Open Questions

- Should iotakt track one Lean version exactly or a small stable range?
- How should breaking FFI changes be versioned?
- Should native code be optional at package installation time or only at import/build time?
