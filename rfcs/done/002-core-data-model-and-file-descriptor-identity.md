# RFC 002: Core Data Model and File Descriptor Identity

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M1  
**Priority:** Critical  
**Primary layer:** Iotakt.Model

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

This RFC defines the core Lean data model for file descriptor identity and ownership. The central decision is that a raw OS fd integer is never treated as stable identity. iotakt uses `FdKey(raw_fd, generation)` so that stale readiness events from a previously closed fd cannot be delivered to a new actor after fd reuse.

## Motivation

Operating systems aggressively reuse fd integers. A model that treats raw fd `17` as identity is vulnerable to misdelivery: a stale readiness event for an old connection may be injected into the actor for a newly accepted connection that received the same raw fd value. This is both a practical bug and a proof obstacle.

By making generation explicit, iotakt turns fd reuse into a modeled transition. The registry can prove that only the current generation for a raw fd may receive messages.

## Goals

- Define `RawFd`, `FdGeneration`, and `FdKey`.
- Define registry entries with actor ownership.
- Define current raw-fd resolution and stale-event rejection prerequisites.
- Define resource kind and minimal resource metadata.
- Prepare theorem targets for uniqueness and no stale injection.

## Non-Goals

- Do not define detailed lifecycle transitions; RFC 003 owns them.
- Do not define event normalization; RFC 004 owns it.
- Do not define bridge injection; RFC 007 owns it.
- Do not define native fd allocation mechanics beyond model requirements.

## External Design

Externally, every resource exposed by iotakt has a stable `FdKey`. User-facing debug output may show raw fd values, but public actor-targeting logic must use `FdKey` or an opaque wrapper containing it.

The design rule is:

```text
RawFd is a handle to the OS.
FdKey is the iotakt identity.
Actor ownership is attached to FdKey, not RawFd alone.
```

When a raw fd is closed and later reused by the OS, iotakt allocates a fresh generation. Old model events referencing the older generation remain distinguishable and are dropped.

## Data Model / Internal Design

Representative Lean model definitions:

```lean
namespace Iotakt.Model

abbrev RawFd := Int
abbrev FdGeneration := Nat
abbrev ActorId := Nat -- or a thin adapter over Henret actor identifiers

structure FdKey where
  raw : RawFd
  gen : FdGeneration
  deriving DecidableEq, Repr

inductive ResourceKind where
  | listener
  | stream
  deriving DecidableEq, Repr

inductive ResourceState where
  | allocated
  | configured
  | listening
  | registered
  | active
  | closing
  | closed
  deriving DecidableEq, Repr

structure RegistryEntry where
  key       : FdKey
  owner     : ActorId
  kind      : ResourceKind
  state     : ResourceState
  interests : InterestSet
  deriving Repr

structure Registry where
  byKey      : Std.HashMap FdKey RegistryEntry
  currentGen : Std.HashMap RawFd FdGeneration
  nextGen    : FdGeneration
  deriving Repr

end Iotakt.Model
```

`currentGen` records which generation is current for a raw fd. `nextGen` is monotonic in the model. A closed key is not reactivated; a later resource with the same raw fd receives a different generation.

## Lifecycle / Workflow

Fd identity lifecycle:

```text
1. Native layer reports a newly allocated raw fd.
2. Model allocates a fresh generation.
3. Model creates FdKey(raw, gen).
4. Registry entry is inserted under FdKey.
5. currentGen[raw] is set to gen.
6. On close, entry moves to closed or is tombstoned according to lifecycle RFC.
7. currentGen[raw] is removed or updated only by a fresh allocation transition.
```

A native event containing only `raw_fd` must be resolved through `currentGen`. If no current generation exists, the event is unknown. If an event carries a stale key in fake tests, it is stale. Native epoll events normally carry raw fds, so stale protection is primarily enforced at registry/current-generation resolution and close/deregister ordering.

## Public API Impact

Public API should avoid exposing bare `RawFd` for application-level ownership.

Recommended API style:

```lean
structure SocketRef where
  key : Iotakt.Model.FdKey

structure ListenerRef where
  key : Iotakt.Model.FdKey
```

Native/debug APIs may expose raw fd values, but any actor-visible `IoMessage` should include `FdKey` or an opaque reference containing it.

## Native Boundary Impact

The native backend returns raw fd integers because that is what POSIX provides. It does not allocate generations. Generation allocation is Lean model responsibility.

The native boundary must not cache actor ownership or generation state. This keeps stale-event logic in the model/bridge, where it can be proven and tested deterministically.

## Henret Integration Impact

Henret actor ownership is represented in registry entries. A `FdKey` maps to exactly one owner actor at a time. Bridge logic must consult the registry and inject messages only to the owner recorded for the current key.

## Security Considerations

Fd identity is a security-relevant property. Misdelivering an event from one connection to another can corrupt protocol state and may cross tenant/request boundaries in higher layers. Generation-based identity is therefore required, not optional.

Debug output should avoid implying that raw fd alone is authoritative.

## Proof Obligations

- Registry uniqueness: a registered `FdKey` has at most one active owner.
- Current-generation soundness: resolving a raw fd yields at most one active generation.
- Closed terminality prerequisite: a closed `FdKey` cannot become active again.
- No stale key can be treated as current after generation advancement.

## Test Obligations

- Fake test: allocate fd 17 generation 1, close it, allocate fd 17 generation 2, ensure old-key event is dropped.
- Fake test: unknown raw fd event is dropped.
- Model regression: registry insertion rejects duplicate active FdKey.
- Model regression: closing a key removes or tombstones ownership consistently.

## Trust / Assumption Changes

- Assume OS may reuse raw fd integers quickly.
- Assume native layer accurately reports raw fd integers returned by syscalls.
- Do not assume native layer understands generations.

## Architecture Gaps

- Whether to preserve tombstones for closed keys or remove entries immediately is finalized in RFC 003.
- Whether `ActorId` is a direct Henret type or an adapter type depends on the bridge design.

## Acceptance Criteria

- No public actor-targeting API uses raw fd alone as identity.
- `FdKey(raw, generation)` is present in the model.
- Registry supports owner lookup by FdKey.
- Raw-fd-to-current-generation resolution is modeled.
- Stale-event tests are possible before native backend exists.

## Alternatives Considered

- Use raw fd only: rejected due to fd reuse and stale-event misdelivery.
- Use OS pointer/userdata only: rejected because it hides identity from Lean model and does not cover all backend semantics cleanly.
- Never reuse model keys but ignore raw fd reuse: rejected because native events arrive by raw fd.

## Open Questions

- Exact tombstone retention policy after close.
- Whether generation is global monotonic or per raw fd; global monotonic is recommended for simplicity.

