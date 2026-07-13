# RFC 043: Capability-Oriented Fd Handle API and Authority Minimization

- **Status:** Proposed — post-remediation authority hardening
- **Intended phase:** After RFC 064 restores checked `FdKey` effects
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC replaces casual raw fd usage in high-level iotakt APIs with an authority-minimized `FdHandle` concept.

RFC 064 is the release-blocking repair for stale/forged authority on the existing
stable API. This RFC must not delay that fix. After RFC 064, this RFC may make valid
handles opaque and add monotone delegation as defense in depth.

## 2. Motivation

Raw integer fds are unsafe as public authority. If an actor can call operations with arbitrary raw integers, it can attempt to read, write, or close resources it does not own. Even if native calls fail, the API design becomes hostile to proof and audit.

Iotakt already uses `FdKey(raw, generation)` internally. This RFC extends that idea to public handles.

## 3. Public handle model

```lean
structure FdHandle where
  key       : FdKey
  authority : FdAuthority

deriving Repr

structure FdAuthority where
  canRead        : Bool
  canWrite       : Bool
  canSetInterest : Bool
  canClose       : Bool
```

The raw fd is never exposed as the ordinary application-facing identity.

## 4. Handle creation

Handles are created only by iotakt-controlled workflows:

```text
- listener creation
- accept result
- outbound connect result
- explicit delegation by owner actor
```

There is no ordinary API for constructing an arbitrary `FdHandle` from an integer.

## 5. Delegation

A future API may allow an actor to delegate limited authority:

```lean
def restrict (h : FdHandle) (auth : FdAuthority) : Option FdHandle
```

Restriction may remove authority but never add authority.

## 6. Enforcement

Before any operation, iotakt checks:

```text
- handle FdKey exists in registry
- generation matches current raw fd mapping
- actor has authority for the operation
- resource state allows the operation
```

Native code receives raw fds only after Lean-side authority checks.

## 7. Invariants

```text
No arbitrary raw fd invariant:
  Public APIs do not permit normal users to operate on unregistered raw fds.

Authority monotonicity:
  Delegation can only reduce authority.

Close authority invariant:
  Only a handle with close authority can request close.

Generation safety:
  A stale handle cannot operate on a newly reused raw fd.
```

## 8. Escape hatch policy

A low-level unsafe API may exist only under an explicit namespace such as:

```lean
namespace Iotakt.Unsafe
```

It must be excluded from the ordinary guided tour and clearly marked outside the proof contract.

## 9. Acceptance criteria

- Public examples never use raw fd integers directly.
- Proof targets cover authority monotonicity and stale handle rejection.
- Tests verify that stale handles fail after close/reuse simulation.
- Documentation explains the relationship between `FdKey`, `FdHandle`, and native raw fds.
