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
| `CoalesceState` | the coalescing model is proven, but the ack/clear *API shape* (explicit `ackReady` vs. clear-on-recv) is still an open RFC question (External Design §23.7) |
| `FakePoller`, `FakePollResult` | the deterministic test harness; its scripting DSL may be refined |
| `processEvent` | a convenience string-rendering helper; likely folded into the trace/render layer |

---

## `Iotakt.Server` — the consumer handoff surface

The single module a consumer (the future jemmet) imports to get the I/O
building blocks. **This is not a server** — it re-exports primitives; the
serve loop and routing policy live in the consumer.

### Stable

| Name | Notes |
|------|-------|
| `EventLoop`, `LoopEvent` | the driver loop and its event stream |
| `HttpRequest`, `HttpResponse` | request/response value types |
| `BodyFraming`, `ReadResult` | body-framing classification and read outcome |
| `WriteBuffer` | partial-write adapter |
| `readRequest` (`readFull`), `readRequestBuffered` (`readFromBuffer`) | the two read entry points; `readRequestBuffered` is the keep-alive-correct one |
| `bodyFramingOf` | framing classifier |
| `encodeChunk`, `chunkedTerminator`, `chunkedResponseHeader`, `decodeChunked`, `isChunked` | chunked transfer-encoding (RFC 7230 §4.1) |

### Provisional

| Name | Why provisional |
|------|------------------|
| `Router`, `Route`, `RouteParams`, `Handler` | a *convenience* router is provided for examples, but routing is properly the consumer's concern (RFC 001 non-goal). It may be moved out of iotakt entirely before v1.0 — a consumer can supply its own. |

The `Router` re-export is the clearest candidate for removal before v1.0:
iotakt should ship the *reading and framing* primitives and let a server
own dispatch. It stays for now because the examples lean on it, but the
v1.0 audit should decide whether it belongs in the boundary library at all.

---

## `EventLoop` operational surface (in `Iotakt.Loop`)

### Stable

`create`, `destroy`, `addListener`, `runStep`, `runStepAuto`,
`closeConnection`, `enableWrite`/`disableWrite`, `connectTo`,
`withIdleTimeout`, `withMaxConnections`, `connectionCount`, `atCapacity`,
`shutdown`.

These are the connection-lifecycle and resource-control entry points; their
signatures are settled and exercised by the integration tests.

### Provisional

| Name | Why |
|------|-----|
| `recordTask`/`forgetTask`/`taskOf`/`taskByKey` | the Gap-006 task-tracking bookkeeping is currently public for testing; it may become internal once the cancel-on-close path is considered final |
| `reapIdle`, `pollTimeoutMs`, `touchConn` | the adaptive-timeout / idle-reaping internals; useful to inspect in tests but not a committed API |

---

## Open items to settle before v1.0

1. **Coalesce ack API** — pin `ackReady` vs. clear-on-recv (External Design §23.7).
2. **Router placement** — decide whether `Router` ships in iotakt or moves to the consumer.
3. **Task-tracking visibility** — demote Gap-006 bookkeeping to internal if final.
4. **`recvInto`** — the reusable-buffer optimization (RFC 022) is deferred; if it lands, it adds a Stable name, not a breaking change.
5. **kqueue (RFC 021)** — the model is already kqueue-aware; a native kqueue backend adds a `NativeBackendKind` value, not a surface change.

When these are resolved and the Provisional column is emptied (promoted or
removed), the surface is ready for a v1.0 stability commitment — pending
explicit sign-off.
