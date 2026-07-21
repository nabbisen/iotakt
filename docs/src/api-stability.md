# API Stability Review

**iotakt v0.11 — applying RFC 031 — toward a v1.0 commitment**

This is a concrete audit of iotakt's public surface as it stands, classifying
each exported name **Stable**, **Provisional**, or **Internal** per the
versioning policy in [RFC 031](../../rfcs/proposed/031-api-versioning-feature-flags-and-compatibility-policy.md).
It exists so that, when v1.0 is cut, the stability promise is explicit and
deliberate rather than implied by whatever happens to be exported.

| Class | Meaning | Change policy before v1.0 | After v1.0 |
|-------|---------|---------------------------|------------|
| **Stable** | Intended to be part of the v1.0 commitment | May change with a CHANGELOG note | Breaking change ⇒ major version |
| **Provisional** | Useful now, shape may still change | May change freely | Must be promoted to Stable or removed before v1.0 |
| **Internal** | Not a supported entry point | No promise | No promise |

> **v1.0 is not cut.** Nothing here is yet a permanent commitment; this audit
> is the checklist to settle *before* v1.0.

---

## `Iotakt.Api` — the pure-model surface

The model-facing surface for consumers that want fd identity, the event
vocabulary, and the registry/coalescing model without the native backend.

### Stable

| Name | Notes |
|------|-------|
| `RawFd`, `FdKey`, `ActorId` | fd identity is the core invariant; `FdKey(raw, gen)` will not change shape |
| `Interest`, `InterestSet`, `IoEvent`, `IoErrno` | the platform-neutral event vocabulary (RFC 004); kqueue-aware, so no epoll names leak |
| `ReadResult`, `WriteResult`, `IoMessage` | result/message types crossing the boundary |
| `Registry`, `RegistryWellFormed` | the registry and its proven invariant |
| `InterestSet.none/readOnly/enableWrite/disableWrite` | interest-set constructors |
| `mkFdKey`, `FdKey.rawInt`, `FdKey.generation` | fd accessors |

`ReadResult` gained `.tooLarge` in v0.10 — an **additive** constructor.
Additive enum growth is the one expected source of compiler-caught breakage
before v1.0; it is called out in the CHANGELOG each time.

### Provisional

| Name | Why provisional |
|------|------------------|
| `FakePoller`, `FakePollResult` | the deterministic test harness; its scripting DSL may be refined |
| `processEvent` | a convenience string-rendering helper; likely folded into the trace/render layer |

> **Settled in v0.13:** `CoalesceState` is now **Stable**. The coalescing
> contract is pinned to **explicit acknowledgement** — pending readiness
> clears only via `ackReady` / `recvAck` / `sendAck` (proven by
> `ack_clears`, `deliver_after_ack`); clear-on-recv was rejected because it
> would couple the model to the I/O path and is harder to prove. The
> `CoalesceState` abbrev and `coalesceAck` are exposed on `Iotakt.Api`.

---

## `Iotakt.Server` — the consumer handoff surface

The single module a consumer (the future jemmet) imports to get the I/O
building blocks. **This is not a server** — it re-exports primitives; the
serve loop and routing policy live in the consumer.

### Stable runtime identities

| Name | Notes |
|------|-------|
| `EventLoop`, `LoopEvent`, `LoopError` | Runtime state, attributed events, and typed fatal-wait result |

### Provisional compatibility surface

The protocol/framing exports below remain available to legacy examples, but the
approved remediation baseline treats protocol ownership as unresolved. They carry
no stable native-authority promise and must be moved to a consumer/examples package
or explicitly accepted with expanded assurance under RFC 069.

| Name | Notes |
|------|-------|
| `HttpRequest`, `HttpResponse` | request/response value types |
| `BodyFraming`, `ReadResult` | body-framing classification and read outcome |
| `WriteBuffer` | partial-write adapter |
| `unsafeReadRequest` (`unsafeReadFull`), `unsafeReadRequestBuffered` (`unsafeReadFromBuffer`) | Explicitly unsafe raw-fd compatibility entry points; the buffered form is keep-alive-correct |
| `bodyFramingOf` | framing classifier |
| `encodeChunk`, `chunkedTerminator`, `chunkedResponseHeader`, `decodeChunked`, `isChunked` | chunked transfer-encoding (RFC 7230 §4.1) |

### Settled in v0.13: routing is **not** part of the stable surface

`Router`, `Route`, `RouteParams`, `Handler` were **removed from
`Iotakt.Server`'s exports**. Routing is an RFC 001 non-goal; a consumer
(jemmet) owns dispatch. The `Iotakt.Router` module remains in the repo as an
**optional convenience** — the same status as `Iotakt.Http`: a reusable
primitive, imported directly by code that wants it, carrying **no stability
promise**. The reference server and routing-server examples import it directly. The
stable handoff commitment is currently limited to the runtime identities and the
checked `EventLoop` operations listed below.

---

## `EventLoop` operational surface (in `IotaktRuntime.Loop`)

### Stable

Native-effecting operations: `create`, `addListenerAt`, `addListener`, `runStep`,
`runStepAuto`, `closeConnection`, `enableWrite`/`disableWrite`, `recvAck`, and
`sendAck`.

The repository-derived classification and evidence bindings are verified from
[`native-effect-inventory.tsv`](./native-effect-inventory.tsv).

<!-- native-effect-stable: indirect::EventLoop.create -->
<!-- native-effect-stable: indirect::EventLoop.addListenerAt -->
<!-- native-effect-stable: indirect::EventLoop.addListener -->
<!-- native-effect-stable: indirect::EventLoop.runStep -->
<!-- native-effect-stable: indirect::EventLoop.runStepAuto -->
<!-- native-effect-stable: runtime/IotaktRuntime/Loop.lean::closeConnection -->
<!-- native-effect-stable: runtime/IotaktRuntime/Loop.lean::enableWrite -->
<!-- native-effect-stable: runtime/IotaktRuntime/Loop.lean::disableWrite -->
<!-- native-effect-stable: runtime/IotaktRuntime/Loop.lean::recvAck -->
<!-- native-effect-stable: runtime/IotaktRuntime/Loop.lean::sendAck -->

Pure/configuration operations `withIdleTimeout`, `withMaxConnections`,
`connectionCount`, `atCapacity`, and `ackReady` remain stable but cause no native fd
effect and therefore do not appear in RFC 064's effect inventory.

These are the checked connection-authority and resource-control entry points. RFC
064 remains Proposed until its complete inventory and acceptance evidence are
reviewed. Every stable operation that accepts an `FdKey` resolves the current live
registry entry and validates the native fd representation before making a
native call.

The effectful key-based operations return typed results:

```lean
enableWrite / disableWrite / closeConnection
  : EventLoop → FdKey → IO (Except EffectError EventLoop)

recvAck : EventLoop → FdKey → Nat
  → IO (Except EffectError (EventLoop × ReadResult))

sendAck : EventLoop → FdKey → ByteArray → Nat → Nat
  → IO (Except EffectError (EventLoop × WriteResult))
```

`EffectError` distinguishes invalid, stale, out-of-range, wrong-kind,
inactive, and native failures. Authority-validation failure performs no native
call and leaves registry, coalescing, and runtime state unchanged. Examples may
explicitly convert an error to an `IO` exception with `EffectError.orThrow`;
library adapters should normally propagate the typed result.

The downstream compile probe `scripts/check-runtime-typed-surface.sh` compiles an
external consumer module against the runtime package environment, exhaustively
handles `EffectError`, and pins the exact result type of every stable key-based
effect operation (`RFC064-TYPED-SURFACE-001`). Clean package-resolution probes remain
an RFC 069 release-baseline obligation.

### Explicit unsafe and internal surface (no stability promise)

Lean imports expose declarations from transitive dependencies, so the project does
not claim that importing `IotaktRuntime.Loop` makes raw implementation declarations
unresolvable. Instead, every retained downstream-callable escape is enforceably
marked by an `unsafe` declaration name or the `IotaktRuntime.Native.Unsafe`
namespace; genuinely hidden helpers are `private`. The inventory checker rejects
unmarked non-private `unsafe-internal` rows, while
`scripts/check-runtime-unsafe-surface.sh` proves the former unmarked names no longer
compile (`RFC064-UNSAFE-SURFACE-001`). These names are outside the checked stable API
and its proof claim.

| Name | Status |
|------|--------|
| `recordTask`/`forgetTask`/`taskOf`/`taskByKey` | **Internal.** This bookkeeping is non-`private` only so integration tests can inspect it. Consumers use `closeConnection` and `connectionCount`. |
| `reapIdle`, `pollTimeoutMs`, `touchConn` | **Internal.** Adaptive-timeout / idle-reaping internals; inspectable in tests, not a committed API. |
| `unsafeCreateMailbox`, `unsafeCreateWithMode`, `unsafeRunStepWith` | **Explicit unsafe/internal.** Mailbox and injected-operation seams used by integration tests. |
| `unsafeConnectTo` | **Explicit unsafe/internal during remediation.** Its registration transition is not failure-atomic yet. |
| `unsafeShutdown`, `unsafeDestroy` | **Explicit unsafe/internal during remediation.** RFC 070 checked listener close and drained-only finalization are not implemented yet. |
| `IotaktRuntime.Native.Unsafe.*` | **Raw native escape hatch.** Never part of checked `FdKey` authority; intended only for runtime implementation and native conformance tests. |

### `recvAck` / `sendAck` (added v0.13) — Stable

The combined read/write + acknowledge helpers that implement the explicit-ack
contract (RFC 006). Part of the Stable operational surface alongside
`ackReady`.

---

## Status toward v1.0

As of v0.13 the **Provisional column is essentially empty**: the coalesce ack
API is pinned (explicit), routing is decided (not in the stable surface), and
the task-tracking bookkeeping is reclassified Internal. The remaining items do
**not** block the surface:

1. **kqueue (RFC 021)** — the model is already kqueue-aware; a native kqueue
   backend adds a `NativeBackendKind` value, not a surface change. Blocked
   only on a macOS CI runner.
2. **`recvInto` (RFC 022)** — the reusable-buffer optimization is deferred; if
   it lands it *adds* a Stable name, not a breaking change.
3. `FakePoller` DSL and `processEvent` remain Provisional but are test/utility
   surface, not part of the core consumer contract.

The core consumer surface is under the R1–R5 remediation train. It is not a
v1.0 candidate while the project-wide No-Go decision is active.

> **v1.0 is not cut and will not be cut without explicit maintainer sign-off.**
> This audit establishes that the surface is *ready* for that decision; it does
> not make it.
