# Gap 004 — ActorId Allocation Pattern

**Status:** Resolved in v0.5.0-dev

---

## Problem statement

The iotakt model uses `ActorId = Nat` (matching Henret's `ActorId = Nat`)
to identify which actor owns a given `FdKey`. The bridge injects
`IoMessage.ready key event` into the Henret runtime by looking up the
owning actor's mailbox.

The gap: Henret v0.6.0 does not expose a public API for allocating actor
IDs. There is no `Henret.freshActorId` or `Henret.RuntimeState.addActor`.
The requirement was "defer to native integration milestone" but iotakt
needed to allocate IDs to accept connections.

---

## Resolution: the `nextActorId` counter

`NativeDriverState` carries a monotone `nextActorId : Nat` counter.
When a new resource is registered, iotakt allocates the next available ID
and increments the counter:

```lean
structure NativeDriverState where
  ds          : DriverState
  nextActorId : Nat := 1

namespace NativeDriverState

def freshActorId (nds : NativeDriverState) : NativeDriverState × Nat :=
  ({ nds with nextActorId := nds.nextActorId + 1 }, nds.nextActorId)
```

The allocated ID is then passed to both:
1. `Registry.allocate` — so the registry knows which actor owns the fd.
2. `Henret.RuntimeState.step (.spawn actorId)` — so Henret creates a mailbox
   for that actor.

This means every fd accepted by iotakt creates one Henret actor (a mailbox).
The actor's lifecycle is tied to the fd: when the fd is closed, the actor
is not explicitly terminated in Henret (Gap 006), but its mailbox is never
used again because the fd key becomes stale.

---

## Why this is acceptable for v0.5

1. **Correctness**: the `inject_ok_of_mailbox` theorem proves that delivery
   only succeeds when the mailbox exists. Since `spawn` is called before any
   inject, the mailbox is always present for the first delivery.

2. **No ID collisions**: the counter is monotone and never reuses IDs within
   a driver lifetime. FdKey generations protect against stale events even if
   raw fd integers are reused by the OS.

3. **Memory**: each spawned actor creates one Henret mailbox entry. In a
   server that handles millions of short connections, this accumulates. The
   mitigation is explicit actor cleanup when a connection closes (Gap 006).

---

## Remaining gaps

Gap 006 (actor lifecycle notification) is still open: iotakt closes the fd
and removes the registry entry, but does not call `Henret.terminate actorId`
to free the mailbox. This is a memory concern for long-running servers.
Resolution depends on Henret exposing a termination API (RFC 035 scope).

Gap 004 is considered **resolved** for the purposes of v0.5 design. The
`nextActorId` pattern will be replaced by a proper Henret API when available.
