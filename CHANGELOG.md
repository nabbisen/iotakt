# Changelog

All notable changes to iotakt are documented here.

## [Unreleased]

Work in progress toward v0.1.0.

## [0.13.3-dev] — 2026-06-16

Dependency adoption: **henret v0.17.7 → v0.34.0** (17 minor versions). Despite the
span, iotakt's narrow consumption surface absorbed it with **one** proof
strengthening; behavior is unchanged. Toolchain unchanged (Lean 4.15.0). 77
theorems, 0 sorry/axiom; CI 26 steps / 333 checks all pass.

### Changed
- **henret pin v0.17.7 → v0.34.0**, as a **CI-portable git require** on the
  published tag `"0.34.0"` (`lake-manifest.json` is a git entry, rev `63f10f48`).
  v0.33.0 → v0.34.0 is a henret mdbook-docs migration only — `Henret/` source is
  byte-identical (verified `diff -rq`), so no model/proof/verification change. A clean checkout/CI builds with no vendoring (Henret published the
  tag); the vendored path remains a documented offline override. Model grew additively: `RuntimeOp` 21 → 29, `StepResult` 8 → 10
  (`.backpressured` RFC 056, `.acquired` RFC 057), `WellFormed` 28 → 33,
  `RuntimeState` +3 fields (`mailboxPolicy`/`resources`/`nextResourceId`).
  `TaskState` (10) unchanged.
- **One proof strengthened** — `Iotakt.Bridge.inject_ok_of_mailbox` gained a fourth
  hypothesis `mailboxFull a mb = false` to discharge RFC 056's (v0.18.0) `inject`
  backpressure guard. No proof callers, so no cascade; the hypothesis holds
  throughout iotakt's driver (unbounded `mailboxPolicy` from `RuntimeState.init`,
  so `mailboxFull` is always `false`; readiness occupancy is independently bounded
  by coalescing).

### Unchanged (verified)
- No compiler-caught break across the 16-version span: no exhaustive
  `RuntimeOp`/`StepResult`/`TraceEvent` match; state via `RuntimeState.init`; no
  references to renamed henret names (RFC 091 `status_irrel` → `runtimeStatus_irrel`,
  `ResourceRecord.owner`); no `ResourceState` namespace clash.
- iotakt does not use the resource ledger (RFC 057/091), so those features are
  vacuous for it. RFC 056 bounded mailboxes is Option A (reject-only); iotakt sets
  no bound and is byte-for-byte behaviourally identical.
- Public theorem surface additive-only since henret's v0.30.0 snapshot (no
  renames/removals), so iotakt's theorem-name dependencies are safe.
- Docs: `docs/src/henret-integration.md` (pin, full version-path table, v0.17.7 →
  v0.34.0 adoption notes) and `proof-trust-test-matrix.md` updated.

## [0.13.2-dev] — 2026-06-15

Dependency adoption: **henret v0.15.2 → v0.17.7** (ten releases). One semantic-core
change (RFC 055 Structured Cancellation & Shutdown) and one optional feature
(RFC 054 Semantic Profiles); the rest is henret release-engineering hardening.
Toolchain unchanged (Lean 4.15.0). 77 theorems, 0 sorry/axiom; CI 26 steps / 333
checks all pass.

### Changed
- **henret pin v0.15.2 → v0.17.7** (`lakefile.lean`, `lake-manifest.json`,
  vendored tree). RFC 055 added +3 `RuntimeOp` (`closeActor`/`shutdown`/
  `stopWhenIdle` → 21), +2 `RuntimeState` fields (`actorStatus`/`runtimeStatus`),
  +2 enums, +3 trace events, +`RuntimeQuiescent`. `StepResult` (8), `TaskState`
  (10), `WellFormed` (28) unchanged.
- **One proof strengthened** — `Iotakt.Bridge.inject_ok_of_mailbox` gained two
  hypotheses (`runtimeStatus = .running`, `actorStatus a ≠ .closed`) to discharge
  RFC 055's new `inject` admission guard. No proof callers, so no cascade; the
  hypotheses hold throughout iotakt's driver (starts from `RuntimeState.init`,
  never issues `closeActor`/`shutdown`/`stopWhenIdle`).

### Unchanged (verified)
- No compiler-caught migration break: no exhaustive `RuntimeOp`/`TraceEvent`
  match; state built via `RuntimeState.init`. iotakt never issues the three
  shutdown ops, so admission guards never fire at runtime — behaviorally
  identical to v0.15.2.
- Docs: `docs/src/henret-integration.md` updated (pin, version-path table,
  RFC 055 adoption notes); iotakt declares dependence on henret's **`actor`**
  semantic profile (RFC 054).

### Build / dependency note
- iotakt requires **Henret v0.17.7**. The lakefile's active require is the
  vendored path form (`../henret/henret-v0.17.7`); the CI-portable git form
  (tag `"0.17.7"`, no `v` prefix, via `LAKE_PKG_URL_MAP`) becomes usable once
  Henret publishes the `0.17.7` tag on GitHub (highest published: `0.15.2`).
  Fixed a latent tag-format bug in the lakefile's documented git pin
  (`v0.17.7` → `0.17.7`). Until Henret publishes the tag, build against a
  vendored Henret tree (see README "Quick Start"). The path-type
  `lake-manifest.json` entry reflects this vendored build and is not portable;
  it is regenerated to a git-based entry when the release switches to the git
  require.

## [0.13.1-dev] — 2026-06-10

Documentation-fitness release: a full audit of the docs against the codebase,
fixing six mismatches found by cross-checking every concrete claim. No code
changes except comments; 77 theorems, 0 sorry/axiom; CI unchanged at 26 steps.

### Fixed — docs now match the code

- **Stale `Router`-in-surface claims** (the v0.13 removal of routing from the
  stable `Iotakt.Server` surface had not propagated to all docs): the
  `Iotakt.Server` module docstring, `docs/src/jemmet-handoff.md` (surface
  tree, minimal-server example, open-list note) now show routing as a separate
  optional `import Iotakt.Router`, not part of the handoff surface.
- **Prototype seed would not compile**: `jemmet-handoff/prototype/Jemmet.lean`
  and `JemmetDemo.lean` did `open Iotakt.Router` without importing it (broken
  by the v0.13 Router removal). Added the explicit imports and **compile-verified
  the prototype against the current iotakt** — the seed jemmet copies is now
  known-buildable.
- **Wrong build command** in the proof/trust/test matrix: `lake build
  IotaktProofs` → `lake build Iotakt.Proofs` (the former target does not exist).
- **Stale executable-check count** in the matrix: "321 checks across 13 suites"
  → **333 across 14 suites** (v0.13 added a suite); added the v0.13-test row to
  the TESTED table.
- **Broken mdbook `SUMMARY.md`**: it linked to 11 chapters that were never
  written (mdbook would fail to build) while 3 real docs were orphaned
  (`ffi-hardening`, `gap004-actorid`, `kqueue-analysis`). Rewrote `SUMMARY.md`
  to reference exactly the files that exist, indexed the orphans, and added a
  concise `docs/src/introduction.md` landing page. Every link now resolves;
  no orphans.

### Verified — no change needed

All EventLoop/handoff signatures, the `recvAck`/`sendAck`/`ackReady` surface,
result/event/config types, the 15 native FFI function names, all matrix
theorem counts (77), and the documented Lean/FFI gotchas were cross-checked
and match the code.

## [0.13.0-dev] — 2026-06-10

Settles the three v1.0 open items the API-stability audit named, emptying the
Provisional column and producing a **v1.0-candidate surface** (not cut — see
below). No model changes; still henret v0.15.2; 77 theorems, 0 sorry/axiom.

### Changed — v1.0 surface decisions

**1. Coalesce ack API pinned to explicit acknowledgement (RFC 006).**
- Pending readiness clears only via acknowledgement, never implicitly on
  recv/send at the model level. The proven `CoalesceState.ack` is the
  mechanism (`ack_clears`, `deliver_after_ack`); clear-on-recv was rejected
  (it would couple the model to the I/O path and is harder to prove).
- `CoalesceState` promoted Provisional → **Stable** on `Iotakt.Api`;
  `coalesceAck` re-exported.

**2. Routing removed from the stable handoff surface.**
- `Router`, `Route`, `RouteParams`, `Handler` are no longer exported from
  `Iotakt.Server`. Routing is an RFC 001 non-goal; a consumer (jemmet) owns
  dispatch. The `Iotakt.Router` module remains as an **optional convenience**
  (same status as `Iotakt.Http`), imported directly by code that wants it,
  with no stability promise. `examples/ReferenceServer.lean` now imports
  `Iotakt.Router` explicitly.

**3. Gap-006 task-tracking reclassified Internal.**
- The cancel-on-close path is declared **final**; `recordTask`/`forgetTask`/
  `taskOf`/`taskByKey` (and `reapIdle`/`pollTimeoutMs`/`touchConn`) are marked
  Internal — no stability promise, non-`private` only for tests. Consumers use
  `closeConnection`/`connectionCount`/`shutdown`.

### Added

- **`EventLoop.recvAck` / `sendAck`** — combined read/write + acknowledge
  helpers (RFC 006 "together" helpers) so a consumer cannot forget to ack and
  suppress the next readiness. Stable.
- **`iotakt-v13-test`** — explicit-ack coalescing (suppress → deliver-after-ack,
  6) and the `recvAck`/`sendAck` helpers clearing pending readiness (6).
- CI step 23 (v0.13 test); gate renumbered to 26 sequential steps.

### Documentation

- `docs/src/api-stability.md` updated: Provisional column emptied; the core
  consumer surface declared a **v1.0 candidate**. Only kqueue (RFC 021) and
  `recvInto` (RFC 022) remain, neither a surface blocker. Explicitly notes
  v1.0 is not cut and requires maintainer sign-off.

## [0.12.0-dev] — 2026-06-10

iotakt stabilization toward v1.0 — documentation, governance, and CI
hygiene. No model or API changes; still henret v0.15.2.

### Added

**Proof/trust/test matrix refresh (`docs/src/proof-trust-test-matrix.md`)**

- Rewritten from the stale v0.1 / Henret v0.6.0 stamp to current state:
  **77 machine-checked theorems** (0 `sorry`/`admit`/`axiom`), **321
  executable checks** across 13 suites. Native backend reclassified from
  "not yet implemented" to implemented (epoll, FFI hardening, throughput).
- Folds in every TESTED addition from v0.5–v0.11: Gap 006 cancel-on-close,
  SchedConn failure/restart (RFC 049), request-size limits, `readFromBuffer`
  pipelining, graceful shutdown, connection limits.
- Discrepancy log updated: the three Henret discrepancies are noted as
  re-verified through v0.15.2.

**API stability review (`docs/src/api-stability.md`, applies RFC 031)**

- A concrete audit classifying every public name in `Iotakt.Api`,
  `Iotakt.Server`, and the `EventLoop` operational surface as **Stable**,
  **Provisional**, or **Internal** per the RFC 031 policy.
- Names a short list of open items to settle before any v1.0 commitment
  (coalesce ack API, `Router` placement, task-tracking visibility,
  `recvInto`, kqueue). Explicitly notes v1.0 is not cut.
- RFC 031 status annotated: its review portion is applied; feature-flag and
  cross-version policy remain forward-looking.

**Matrix-honesty CI guard (step 4)**

- New CI step builds `Iotakt.Proofs` and asserts: 0 `sorry`/`admit`, 0
  `axiom`, and that the theorem count matches the number the matrix doc
  claims. The matrix can no longer silently drift from the corpus — adding a
  theorem without updating the doc fails CI.

**jemmet handoff seed (`jemmet-handoff/`)**

- Preserved the jemmet prototype (removed from the iotakt *library* in
  v0.10) as **handoff material for the separate jemmet project** — a
  `prototype/` (server + demo built on `Iotakt.Server`), `design-notes.md`,
  and a `README.md`. Not compiled by iotakt; reference material so the
  jemmet project can start from a working sketch.

### Changed

- **CI step numbering** made sequential (1–25); labels had drifted out of
  order across releases. Cosmetic, no behavior change.
- `docs/src/SUMMARY.md` indexes the new API stability page.

## [0.11.0-dev] — 2026-06-10

iotakt stabilization toward v1.0 — resource-lifecycle controls that are
squarely iotakt's responsibility (not server-layer features). No new
dependency; still henret v0.15.2.

### Added

**Graceful shutdown (`Iotakt.Loop`, RFC 037)**

- `EventLoop.shutdown : EventLoop → IO EventLoop` — stop accepting and drain
  cleanly: deregister + close every listener fd, then close every active
  stream connection via `closeConnection` (epoll deregister + fd close +
  Henret task cancel). Leaves the poller for `destroy` to finalize. This is
  the clean lifecycle end that replaces the bounded-iteration loop the
  examples use for testability.

**Connection limits / load shedding (`Iotakt.Loop`, RFC 030)**

- `EventLoop.maxConnections : Option Nat` — optional concurrency cap.
- `withMaxConnections`, `connectionCount` (= tracked connections),
  `atCapacity`.
- `runStep` enforces the cap across the accept burst: connections accepted
  past the cap are **shed** — deregistered, closed, their task cancelled, and
  the registry entry dropped — and never surfaced to the caller. A
  resource-exhaustion control complementing the per-request size limit
  (v0.10); both are required by iotakt's security model (RFC 013 §19.1).

**Example**

- `iotakt-v11-test` — connection-cap bookkeeping (7), live load-shedding
  (cap=1 admits ≤1 of 3 real client connects, 3), graceful shutdown
  (listeners closed + connections drained + activity cleared + clean
  destroy, 7).

### Changed

- **CI gate extended to 24 steps** — step 24: v0.11 integration test.
- **RFCs 030 and 037 moved to `rfcs/done/`** (26 done, 35 proposed); README
  Done table updated.

## [0.10.0-dev] — 2026-06-10

**Scope note:** an earlier draft of this release added an `Iotakt.Jemmet`
service-framework module. That was removed before release — jemmet (the HTTP
server) is a *separate project* built on iotakt once iotakt is stable, not
part of the iotakt library. iotakt ships the I/O-boundary building blocks; a
consumer composes them. The keep-alive serve loop now lives only in an
example (`examples/ReferenceServer.lean`), not in a library module.

### Added (iotakt building blocks)

**Request-size limits (`Iotakt.RequestBody`)**

- `ReadResult.tooLarge` — returned when a request exceeds the `maxBytes`
  bound (slow-loris / oversized-body protection).
- `readFull` and `readFromBuffer` enforce `maxBytes` in every read phase:
  header flood, oversized declared Content-Length, and oversized chunked body.
- Internal `ReadPhase` type threads done/incomplete/tooLarge through helpers.

**Pipelining-correct buffered reads (`Iotakt.RequestBody.readFromBuffer`)**

- `readFromBuffer fd initial maxBytes maxPolls : IO (ReadResult × ByteArray)`
  — parses one request from leftover bytes and returns the bytes of the
  *next* request, so a consumer's HTTP/1.1 keep-alive loop loses no pipelined
  data. Computes exact request end for all three framings.
- `findHeaderEnd` — byte offset past the `\r\n\r\n` header terminator.
- Exposed on the handoff surface as `Iotakt.Server.readRequestBuffered`.

**Reference consumer example (not a library module)**

- `examples/ReferenceServer.lean` — a *demonstration* that the
  `Iotakt.Server` handoff surface is sufficient to build a keep-alive
  HTTP/1.1 service. The router, serve loop, and keep-alive policy live in the
  example, since those are a server's responsibility (the future jemmet), not
  iotakt's. Verified live: `/users/42` → JSON, `curl /a /b` on one connection
  → `AB`. Built as `iotakt-reference-server`.
- `iotakt-v10-test` — request-size limits (3), `readFromBuffer` pipelining
  (7 incl. Content-Length-then-pipelined-next), `findHeaderEnd` (3).

**Documentation**

- `docs/src/keep-alive-and-consumers.md` — the v0.10 building blocks
  (size limits, `readFromBuffer`) and the consumer pattern, with the boundary
  restated: iotakt provides reading primitives; a separate server provides
  routing, keep-alive policy, and the serve loop. Indexed in `SUMMARY.md`.

### Changed

**`examples/UploadServer.lean`** — handles the new `.tooLarge` variant (the
compiler caught the missing case).

**CI gate extended to 23 steps** — step 22: v0.10 integration test;
step 23: reference consumer smoke test (handoff surface sufficiency + live
keep-alive). 24 RFCs in done/, 37 in proposed/.

## [0.9.1-dev] — 2026-06-10

### Dependency

**henret v0.12.1 → v0.15.2** (via v0.13.x, v0.14.x, v0.15.0, v0.15.1).
`RuntimeState`, `StepResult`, the `inject` branch, and `Envelope` remain
byte-for-byte identical to v0.11.0, so the bump required **zero** changes to
keep building. The full 21-step CI gate passes unchanged.

| Henret release | RFC | Nature |
|----------------|-----|--------|
| v0.13.0 / v0.13.1 | 045 / 047 | Trace ledger + golden-trace conformance — additive modules |
| v0.14.0 / v0.14.1 | 046 / 048 | Fairness/liveness policy + bounded model explorer — additive |
| v0.15.0 | 049 | **Supervision restart**: `TaskState.failed`, `fail`/`restartOne`, `restartOf` — semantic, but non-breaking for iotakt (catch-all match) |
| v0.15.1 / v0.15.2 | 050 / 051 | Renderers + package/doc maturity — additive |

### Added — adopted RFC 049 (supervision restart)

`Iotakt.SchedConn` extended to model connection-actor failure and supervised
restart, aligning the connection lifecycle with Henret's supervision model:

- `ConnPhase.failed` — terminal failure phase distinct from `.closed`,
  read from `TaskState.failed`.
- `SchedConn.fail` (`fail t`) — fail a connection actor (cleans up like
  cancel but lands in `.failed`, so a supervisor can distinguish error from
  clean close).
- `SchedConn.restart` (`restartOne parent failed actor`) — a running
  supervisor restarts a failed connection into a fresh task, with provenance
  recorded in Henret's `restartOf` field.
- v0.8 test extended (38 → 44 checks): spawn child → fail → supervised
  restart, with fresh-id (`new > old`) and provenance
  (`restartOf new = some old`) invariants verified against real Henret v0.15.0.

### Changed — project rename: henejt → jemmet

The planned upper-layer HTTP server is renamed **henejt → jemmet** (after
Norwegian *jemne*, "smooth"). All references updated across code comments,
docs, and RFCs (206 occurrences). Files renamed:

- `docs/src/henejt-handoff.md` → `docs/src/jemmet-handoff.md`
- `rfcs/proposed/027-henejt-integration-...` → `027-jemmet-integration-...`

`Iotakt.Server` is now documented as the **jemmet handoff surface**. The
iotakt project name, module names, and API are unchanged — only the
downstream consumer's name changed.

### Changed — documentation

- `docs/src/SUMMARY.md` (mdbook) now indexes the v0.6–v0.9 pages
  (chunked-and-scheduled, jemmet-handoff, tls-boundary, henret-integration).
- `docs/src/henret-integration.md` updated to v0.15.2 with the full bump path
  and the RFC 049 adoption notes.

## [0.9.0-dev] — 2026-06-10

### Added

**Body-aware request reading (`Iotakt.RequestBody`)**

The live read path that completes the HTTP/1.1 body story in both
directions (v0.8 added chunked *output*; this adds chunked + Content-Length
*input* reassembly off a live socket).

- `BodyFraming` (none / contentLength / chunked) + `framingOf` — classifies
  a request's body framing from its headers (chunked takes precedence over
  Content-Length per RFC 7230 §3.3.3; header names case-insensitive).
- `splitHeaders` — separates the header block from buffered body bytes.
- `readFull fd maxBytes maxPolls` — reads a complete request (headers +
  body) handling all three framings, with `wouldBlock` retry (body may
  arrive after accept). Returns `.request` / `.incomplete` / `.error`.
- `IotaktRequestBody` Lake library target.
- Verified live: Content-Length POST ('hello world' → 11 bytes) and chunked
  POST ('chunked-data-here' → 17 bytes) both reassemble correctly via curl.

**jemmet handoff surface (`Iotakt.Server`)**

The consolidated public API a Lean HTTP server builds on — one import for
the whole request/response stack.

- Re-exports `EventLoop`, `Router`, `HttpRequest`, `HttpResponse`,
  `BodyFraming`, `ReadResult`, `WriteBuffer`.
- Consolidated abbrevs: `readRequest`, `bodyFramingOf`, `encodeChunk`,
  `chunkedTerminator`, `chunkedResponseHeader`, `decodeChunked`, `isChunked`.
- `IotaktServer` Lake library target.

**Examples**

- `iotakt-upload-server` — jemmet-style server on the `Iotakt.Server`
  surface; accepts Content-Length and chunked request bodies via
  `readRequest`, uses `runStepAuto` + idle reaping.
- `iotakt-v9-test` — body framing detection (6), header/body splitting (3),
  live request reading over socketpair for all three framings (8), handoff
  surface re-export resolution (5).

**Documentation**

- `docs/src/jemmet-handoff.md` — the consumer contract: what iotakt
  provides, what jemmet owns, the `readRequest` framing table, a minimal
  server, and the stability guarantee. The iotakt-side mirror of
  `henret-integration.md`.

### Changed

**CI gate extended to 21 steps** — step 20: v0.9 integration test;
step 21: upload server smoke test (live Content-Length + chunked bodies).
24 RFCs in done/, 37 in proposed/.

## [0.8.0-dev] — 2026-06-10

### Added

**HTTP/1.1 chunked transfer encoding (`Iotakt.Chunked`, RFC 7230 §4.1)**

- `toHex` / `fromHex` — hex chunk sizes; `fromHex` ignores chunk extensions
  after `;` and accepts upper/lower case.
- `encodeChunk` — one frame `<hex-size>\r\n<data>\r\n`.
- `terminator` — the final `0\r\n\r\n` chunk.
- `encodeBody` — one chunk + terminator (non-streaming convenience).
- `responseHeader` — chunked response header (Transfer-Encoding, no Content-Length).
- `decode` — parse a complete chunked body back to concatenated payload bytes;
  `none` on malformed/incomplete framing.
- `isChunked` — detect `Transfer-Encoding: chunked` (case-insensitive).
- `IotaktChunked` Lake library target.
- Verified end-to-end: `curl` decodes the streaming server's output to the
  concatenated payload (RFC-compliant 7/8/7-byte chunks + terminator).

**Scheduled connection-actor lifecycle (`Iotakt.SchedConn`)**

The formal specification deferred from v0.7: a connection actor as a genuine
Henret-running task that parks via `receiveUntil`.

- `ConnPhase` (spawned / running / parkedTimed / ready / closed / other) +
  `phaseOf` reading the phase from a Henret task state.
- `SchedConn` state machine over `Henret.RuntimeState`.
- Operations, each over real Henret `step`: `spawn` (→ spawned), `schedule`
  (→ running), `parkWithDeadline` (`receiveUntil`, → parkedTimed + timer),
  `wakeOnIo` (`inject`, → ready), `tick` (timeout path, → ready), `close`
  (`cancel`, → closed).
- `IotaktSchedConn` Lake library target.
- Two-tier design documented: the model shows the full scheduled lifecycle;
  the native driver keeps the optimized single-outer-loop inject path.

**`iotakt-streaming-server` example**

- HTTP/1.1 chunked streaming server using `runStepAuto` (adaptive poll
  timeout, idle = 0% CPU) + `withIdleTimeout 2000` (idle reaping) + chunked
  encoding for `/stream`.
- Demonstrates the v0.7 zero-CPU-idle property end-to-end with real streaming.

**v0.8 integration test (`iotakt-v8-test`, all PASS)**

- Hex (12), chunk encoding (5), chunk decoding (4), isChunked (3),
  scheduled connection actor lifecycle (14).

**Documentation**

- `docs/src/chunked-and-scheduled.md` — chunked encoding API + wire format,
  scheduled connection-actor lifecycle, and the two-tier model/native design.

### Changed

**CI gate extended to 19 steps** — step 18: v0.8 integration test;
step 19: chunked streaming server smoke test (verifies live chunked framing).
24 RFCs in done/, 37 in proposed/.

## [0.7.0-dev] — 2026-06-10

### Dependency

**henret v0.11.0 → v0.12.1** (via v0.11.1, v0.12.0). All three bumps are
non-breaking; `RuntimeState`, `StepResult`, the `inject` branch, and
`Envelope` are byte-for-byte identical to v0.11.0. **Zero iotakt code
changes required.**

| Henret release | RFC | Nature |
|----------------|-----|--------|
| v0.11.1 | 041 | Selective receive (`receiveByOccurrence`, `receiveFrom`) — additive |
| v0.12.0 | 043 | Multi-worker bridge model (`MultiBridgeState`) — additive |
| v0.12.1 | 044 | Integration contract published (`docs/integration-contract.md`) — docs only |

### Added

**Adaptive poll timeout + park/wake driver (v0.7)**

- `EventLoop.pollTimeoutMs (nowNs)` — computes the `epoll_wait` timeout from
  the nearest connection idle deadline; returns `-1` (block indefinitely)
  when nothing is pending. An idle server now uses zero CPU instead of a
  fixed 100ms heartbeat.
- `EventLoop.runStepAuto` — blocks exactly as long as the next deadline
  allows, processes events, touches active connections, then reaps idle ones.

**Idle connection reaping**

- `EventLoop.idleTimeoutMs`, `lastActivityNs` fields.
- `EventLoop.withIdleTimeout (ms)` — configure an idle timeout.
- `EventLoop.touchConn (key, nowNs)` — record activity (wall-clock monotonic ns).
- `EventLoop.idleExpired (nowNs)` — connections past their idle deadline.
- `EventLoop.reapIdle (nowNs)` — close idle connections, returns closed keys.
- `closeConnection` now also clears the activity record.

**v0.7 integration test (21/21 PASS)**

- `iotakt-v7-test`: adaptive poll timeout (4), idle expiry detection (4),
  reapIdle (3), Henret `receiveUntil` timer infrastructure (10).
- Section D verifies the model side is ready for a future scheduled-actor
  park/wake driver: `receiveUntil` parks as `.waitingTimed`, registers a
  timer, and `tick` wakes it.

### Changed

**`docs/src/henret-integration.md`** — updated to v0.12.1, documents the
four-release bump path (all non-breaking), the published RFC 044 contract,
and the honest `receiveUntil` analysis: iotakt adopts a wall-clock park/wake
at the driver level rather than literal `receiveUntil` (which needs a
scheduled, running connection actor — deferred).

**CI gate extended to 17 steps** — step 17: v0.7 integration test.
24 RFCs in done/, 37 in proposed/.

## [0.6.0-dev] — 2026-06-10

### Dependency

**henret v0.6.0 → v0.11.0** — five releases of Henret shipped during this
phase.  Key capabilities added upstream:

| RFC | What landed | iotakt impact |
|-----|-------------|---------------|
| RFC 033 | Envelope occurrence identity — every injected message carries a globally-unique id and source provenance | **Breaking**: `Mailbox.messages` stores `Envelope{occurrence, source, body}` (3 fields); fixed in `Main.lean` and `EchoTest.lean` |
| RFC 029/031 | Blocked receive → `.waiting` task state + mailbox wait queue | Gap 006 wiring now works cleanly |
| RFC 035/036 | Lean-runtime bridge (`Henret.Bridge`) — single-worker queue-projection theorems | Available; iotakt driver not yet changed |
| RFC 039 | `cancelTree` cascade cancellation | Available; `cancel` now used by iotakt |
| RFC 040 | `receiveUntil` timed parking (`TaskState.waitingTimed`, `timedMailboxWaiters`) | **Breaking in proof**: `inject` checks the new timed-waiter queue — `inject_ok_of_mailbox` updated with one extra `cases` |

### Changed

**`inject_ok_of_mailbox` proof updated (Bridge/Driver.lean)** — the proof
now case-splits on both `mailboxWaiters` and `timedMailboxWaiters`.
The theorem statement is unchanged; only the proof tactic gained one `cases`.

**`Main.lean` and `examples/EchoTest.lean`** — `Envelope` construction
updated to 3-field form: `⟨occurrence, source, body⟩`. The `occurrence`
fields are 0 (first inject, `nextMsgId = 0`) and `source = none` (inject
stamps `source = none` per RFC 033).

### Added

**Gap 006 — cancel-on-close (henret v0.11.0)**

- `EventLoop.taskByKey : List (FdKey × Nat)` — maps each connection to its
  spawned Henret task id.
- `EventLoop.recordTask / taskOf / forgetTask` — helper operations.
- `EventLoop.closeConnection` now issues `Henret.step rt (.cancel task)` to
  free the task's `readyQ` / `timers` / `mailboxWaiters` runtime state.
- `AcceptOneResult.accepted` carries the spawned task id.
- `acceptBurst` returns `List (FdKey × Int × Nat)`.
- `runStep` records accepted task ids into `taskByKey`.
- `connectTo` captures the spawned task id in both `.connected` and
  `.inProgress` branches.
- Verified: routing server ends with **0 task mappings remaining** after close.

**`Iotakt.Router` — path-based HTTP router (v0.6)**

- `RouteParams` with `get / get?`.
- `Router.empty / get / post / put / delete / route`.
- `Router.dispatch / dispatchRequest / matchRoute / size`.
- `matchPattern` — segment-by-segment matching with `:param` wildcard capture.
- `pathSegments` — strips query strings, splits on `/`.
- Supports: exact paths, single `:param`, multiple `:params`, method separation.
- `IotaktRouter` Lake library target.

**`iotakt-routing-server` — HTTP/1.1 routing server example**

- 5 routes: `GET /`, `/health`, `/users/:id`, `/api/:resource/:id`, `POST /users`.
- Live-tested: `/users/42`→`id=42`, `/api/widgets/7`→`resource=widgets id=7`, `/nope`→404.
- Uses `EventLoop + Router + WriteBuffer`. Connection teardown verified clean.

**`docs/src/tls-boundary.md` (RFC 041 — done)**

- Boundary contract: iotakt owns the fd, TLS is a consumer.
- Table: every TLS need maps to an existing iotakt mechanism.
- Explicit non-goals: iotakt must not grow TLS-aware APIs.
- RFC 041 moved to `rfcs/done/`.

**`docs/src/henret-integration.md`**

- Consumer-side integration contract (mirrors Henret RFC 044).
- Three discrepancies re-verified against v0.11.0 source.
- Version-bump re-verification checklist for future bumps.
- `receiveUntil` opportunity noted for v0.7 roadmap.

**v0.6 integration test (32/32 PASS)**

- `iotakt-v6-test`: Router (13), matchPattern (8), Gap 006 (6), task tracking (5).

**CI gate extended to 16 steps**

- Step 15: v0.6 integration test.
- Step 16: HTTP/1.1 routing server smoke test.
- 24 RFCs in done/, 37 in proposed/.

## [0.5.0-dev] — 2026-06-08

### Added

**`Iotakt.Actor` — ConnectionActor lifecycle (v0.5)**

- `ActorAction` — `continue | enableWrite | disableWrite | close`.
- `ConnectionActor` — closure-based actor with `onReadable / onWritable / onEof / onError` callbacks and `dispatch` method.
- `ConnectionActor.mkEcho` — one-liner echo actor builder.
- `ConnectionActor.mkBuffered` — accumulates recv bytes into an `IO.Ref ByteArray`.
- `ActorRegistry` — `register / lookup / remove / runStep`; dispatches `dataReady` events to registered actors, returns unhandled `newConnection` events.
- `IotaktActor` Lake library target.

**`Iotakt.Stats` — I/O statistics counters (v0.5)**

- `ConnStats` — per-connection bytes read/written, event counts, partial-write count, closed flag.
- `GlobalStats` — server-lifetime aggregates: connections, closedConns, errorConns, totalBytes, totalRequests.
- `GlobalStats.reqPerSec` — requests/sec given elapsed nanoseconds.
- `GlobalStats.report` — multi-line benchmark summary.
- `IotaktStats` Lake library target.

**HTTP/1.1 keep-alive improvements**

- `HttpResponse.toBytes` — no longer appends duplicate `Connection: close` when `Connection` header is already present.
- `HttpResponse.okKeepAlive` — `Connection: keep-alive` response builder.
- `HttpResponse.okClose` — `Connection: close` response builder.
- `HttpRequest.keepAlive` — detects whether the request requests a persistent connection (HTTP/1.1 default: true; HTTP/1.0 default: false).
- `HttpRequest.header` — case-insensitive header lookup.

**RFC 025 — Throughput benchmark (done)**

- `Io.monoNs` — `CLOCK_MONOTONIC` nanosecond timestamp via native C shim.
- `iotakt_mono_ns` C function in `iotakt_io.c`.
- `iotakt-bench` executable — 1000 keep-alive round-trips via Unix socketpair; baseline ~300,000–350,000 req/s.
- `iotakt-bench-server` — HTTP/1.1 keep-alive benchmark server on port 49995.
- `docs/src/benchmark.md` — methodology, baseline, and interpretation.
- RFC 025 moved to `rfcs/done/`.

**Gap 004 resolution**

- `docs/src/gap004-actorid.md` — documents `nextActorId` counter pattern as the official ActorId allocation approach for v0.5; records remaining Gap 006 (actor lifecycle notification).

**v0.5 integration test (35/35 PASS + RFC 025 benchmark)**

- `iotakt-v5-test`: ConnectionActor (8), ActorRegistry (6), Stats (12), HTTP keep-alive (6), throughput baseline (3).

**CI gate extended to 14 steps**

- Step 13: v0.5 integration test.
- Step 14: throughput benchmark (RFC 025).
- 23 RFCs in done/, 38 in proposed/.

## [0.4.0-dev] — 2026-06-08

### Added

**WriteBuffer (`Iotakt.WriteBuffer`, RFC 010 completion)**

- `WriteBuffer` struct: `pending : ByteArray`, `offset : Nat`.
- `empty`, `isEmpty`, `unsent`, `push`, `flush`, `flushAll` operations.
- `flush` handles partial writes (`wrote n < len`) and `.wouldBlock`; returns `(buffer, allFlushed)`.
- `flushAll` retries up to `maxRetries` times — for tests and tight loops.
- `IotaktWriteBuffer` Lake library target.

**HTTP/1.0 (`Iotakt.Http`, v0.4 jemmet integration prep)**

- `HttpRequest`: `get (host path)` builder; `readHeaders`; `parse`.
- `HttpResponse`: `ok`, `notFound`, `toBytes`, `readAll`, `parseStatus`, `extractBody`.
- `IotaktHttp` Lake library target.
- `iotakt-http-server` executable: EventLoop + WriteBuffer + HTTP parsing; verified with GET /hello/iotakt.
- `iotakt-http-client` executable: outbound connect + WriteBuffer + response parsing; 5/5 PASS.

**RFC 028 — FFI hardening (done)**

- `docs/src/ffi-hardening.md`: 6-clause formal ByteArray ownership contract (C.1–C.6).
- Documents Option A allocation policy, nested Prod construction, the `recvfrom` double-free anti-pattern.
- 2 known deviations documented (DEV-001, DEV-002) with risk assessment.
- RFC 028 moved to `rfcs/done/`.

**RFC 026 — Native conformance suite (done)**

- v0.4 integration test section D: 6 edge-case checks (recv maxBytes=0, send offset-overflow, epoll fd reuse, FdKey generation).
- RFC 026 moved to `rfcs/done/`.

**v0.4 integration test (34/34 PASS)**

- `iotakt-v4-test`: WriteBuffer (10), HTTP round-trip (9), FFI invariants (6), conformance (6), plus HTTP server+client smoke test.

**CI gate extended to 12 steps**

- Step 10: v0.4 integration test (34 checks).
- Step 11: HTTP/1.0 server+client smoke test.
- Step 12: multi-connection echo server (renumbered).
- 22 RFCs in done/, 39 in proposed/.

## [0.3.0-dev] — 2026-06-08

### Added

**RFC 036 — UDP datagram sockets**

- `iotakt_socket_udp(af4)` — `SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC`.
- `iotakt_recvfrom(fd, maxBytes)` — allocates Lean ByteArray (Option A), returns `(Int × ByteArray × ByteArray)` = `(status, payload, peerAddr)`.
- `iotakt_sendto(fd, buf, offset, len, addr, port)` — sends datagram to IPv4 address.
- `Io.RecvFromResult` — `datagram(bytes, peerAddr) | wouldBlock | interrupted | error`.
- `Io.recvFrom / sendTo` — typed wrappers.
- `Socket.socketUdpRaw` extern declaration.
- `ResourceKind.datagram` — new model variant for UDP sockets.

**RFC 039 — Outbound non-blocking TCP connect**

- `iotakt_connect_tcp(fd, addr_hbo, port)` — returns 0/−EINPROGRESS/−errno.
- `iotakt_get_socket_error(fd)` — checks `SO_ERROR` after EINPROGRESS.
- `IoErrno.inProgress` — model constructor for EINPROGRESS (errno 115).
- `Socket.ConnectResult` — `connected | inProgress | error`.
- `Socket.connectIPv4 / checkConnect` — typed wrappers.
- `EventLoop.ConnectOutcome` — `inProgress(key) | connected(key) | failed`.
- `EventLoop.connectTo(addr, port)` — initiates non-blocking connect, registers write interest.

**RFC 016 — kqueue model analysis (done)**

- `docs/src/kqueue-analysis.md` — 5 model invariants proving `Iotakt.Model` accepts a kqueue backend without changes.
- RFC 016 moved to `rfcs/done/`.

**v0.3 integration test (18/18 PASS)**

- `iotakt-v3-test`: UDP ping-pong (9 checks), outbound TCP connect (5 checks), persistent 5-round connection (4 checks).

**CI gate extended to 10 steps**

- Step 9: v0.3 integration test (UDP + connect + persistent).
- Step 10: multi-connection echo server.

## [0.2.0-dev] — 2026-06-08

### Added

**Public API surface (RFC 017)**

- `Iotakt.Api` — stable module that jemmet and applications should import;
  exports `RawFd`, `FdKey`, `ActorId`, `Interest`, `InterestSet`, `IoEvent`,
  `IoErrno`, `ReadResult`, `WriteResult`, `IoMessage`, `Registry`,
  `RegistryWellFormed`, `CoalesceState`, `FakePollResult`, `FakePoller`,
  plus convenience constructors `mkFdKey`, `FdKey.rawInt`, `FdKey.generation`.
- `IotaktApi` Lake library target.

**Multi-connection event loop (RFC 023)**

- `Iotakt.Loop` — `EventLoop` wraps driver + epoll + registry into a
  high-level event dispatch loop with `LoopEvent` (newConnection / dataReady / tick).
- `EventLoop.create` / `destroy` / `addListener` / `runStep` / `enableWrite` /
  `disableWrite` / `closeConnection` / `ackReady`.
- `IotaktLoop` Lake library target.

**Multi-connection echo server**

- `iotakt-multi-echo` executable: accepts N concurrent TCP connections, echoes
  all data, logs per-connection state. Verified with two simultaneous clients.
- Demonstrates FdKey generation reuse: `fd=5/key=5/1` then `fd=5/key=5/2` on
  the same raw fd after close.

**GitHub Actions CI (`.github/workflows/ci.yml`)**

- Three jobs: `lean-model` (pure Lean, no C), `native-linux` (full native), `sanitizer`.
- Matrix covers: pure model, bridge, fake-demo, native FFI, native-test, echo-test,
  echo-server, multi-echo, RFC invariant checks.

**RFC lifecycle updates**

- RFC 017 moved to `rfcs/done/` (implemented v0.2.0-dev).
- RFCs 001–015, 018, 019 moved to `rfcs/done/` (implemented v0.1.0-dev).
- 19 RFCs in done/, 42 in proposed/ (v0.2+ future work).

**Throughput baseline script**

- `scripts/bench.sh` (RFC 025 baseline): measures sequential echo throughput;
  establishes baseline before any performance optimization.

**CI gate extended to 9 steps**

- Step 9: multi-connection echo server test (two concurrent connections).

## [0.1.0-dev] — 2026-06-08

Initial development release. Not yet suitable for production use.

### Added

**Native C backend (RFCs 009–012)**

- `native/iotakt.h` — shared header: errno constants, interest flag macros.
- `native/iotakt_epoll.c` — Linux epoll: `epoll_create1` / `epoll_ctl` / `epoll_wait` / `epoll_close`. Level-triggered default. Zero-copy event ByteArray encoding (8 bytes per event). EINTR treated as 0 events. Compiles clean with `-Wall -Wextra -Werror -D_GNU_SOURCE`.
- `native/iotakt_socket.c` — POSIX TCP: `socket(SOCK_NONBLOCK|SOCK_CLOEXEC)` / `bind` / `listen` / `accept4(SOCK_NONBLOCK|SOCK_CLOEXEC)` / `close`. All sockets non-blocking and close-on-exec. Fallback via `fcntl` where atomic flags unavailable.
- `native/iotakt_io.c` — Option A recv: C allocates one Lean `ByteArray` (`lean_alloc_sarray`) per `recv` call, zero-copy memcpy, immediate ownership transfer to Lean. `MSG_NOSIGNAL` send. Partial writes returned correctly.
- `scripts/build_native.sh` — standalone native build script (alternative to Lake's `extern_lib`). Supports `IOTAKT_SANITIZE=1` for ASan/UBSan builds.
- `docs/src/architecture-gaps.md` — RFC 019 gap register (10 gaps classified).
- `scripts/check-rfcs.sh` — RFC invariant checker.
- `scripts/ci.sh` — RFC 018 CI gate (7 steps, 52 total checks).
- `docs/src/SUMMARY.md` updated.

**Lean FFI layer**

- `Iotakt/Native/Errno.lean` — errno constant classification.
- `Iotakt/Native/Epoll.lean` — `@[extern]` declarations for all epoll ops; `parseEvents` (ByteArray → `List NormalizedRawEvent`); `normalizeFlags` (epoll flags → backend-neutral IoEvent list, kqueue-aware vocabulary).
- `Iotakt/Native/Socket.lean` — socket/bind/listen/accept/close extern + typed `AcceptResult` wrapper.
- `Iotakt/Native/Io.lean` — recv/send extern with `ReadResult`/`WriteResult` typed result interpretation.
- `Iotakt/Native.lean` — native umbrella (separate from Lean-only core).

**Lake integration**

- `extern_lib iotaktNativeLib` — compiles C files and produces `libiotakt_native.a` automatically when `IotaktNative` is built.
- `lean_lib IotaktNative` — native Lean FFI modules linked against the C lib.
- `lean_exe iotakt-native-test` — native integration test (13 checks, all PASS).

**Native integration test (13/13 PASS)**

- epoll_create1 succeeds; register/deregister; wait with 0 timeout returns 0 events.
- accept on idle listener → wouldBlock.
- recv on listener fd → error.
- send 0 bytes → wrote 0.
- ByteArray event parser: 1 epoll event → rawFd + IoEvent.readable.

**RFC 013 — DriverConfig with resource limits**

- `DriverConfig` structure: `maxEventsPerPoll` (1024), `maxReadBytes` (16384), `maxAcceptBurst` (64), `pollInterruptRetries` (0).
- `DriverState` now carries a `DriverConfig` field (default-initialized with safe values).

**v0.1 integration checkpoint — full driver round-trip (19/19 PASS)**

`iotakt-echo-test`: exercises the complete stack end-to-end using a Unix `socketpair`:

```
socketpair → write → epoll_wait → parseEvents → translateMany
→ processEvents (coalesce + guarded inject) → Henret actor woken
→ re-receive (Mesa) → Io.recv → echo send → read on other end
```

Verifies: socketpair, epoll register, readable event, injectable translation, coalescing, `inject_ok_of_mailbox`, Mesa round-trip, recv returns exact bytes, echo arrives, DriverConfig defaults.

**RFC 018 — CI gate (`scripts/ci.sh`)**

- 7 sequential CI steps: RFC checks → pure model → bridge → fake-demo → native shim → native test → echo test.
- `IOTAKT_SKIP_NATIVE=1` skips C-dependent steps for Lean-only CI environments.
- Exits 1 on any failure; clean summary line.





**Pure model (Lean-only, RFC 002–006)**

- `Iotakt.Model.Fd` — `RawFd`, `FdGeneration`, `ActorId`, `FdKey`,
  `ResourceKind`, `ResourceState`.
- `Iotakt.Model.Interest` — `Interest`, `InterestSet` with
  `none`/`readOnly`/`has`/`enableWrite`/`disableWrite`.
- `Iotakt.Model.Event` — `IoEvent` (readable/writable/eof/hangup/error),
  `IoErrno`, `NativeEvent`, `NormalizedRawEvent`.
- `Iotakt.Model.Result` — `ReadResult`, `WriteResult`, `IoMessage`.
- `Iotakt.Model.Registry` — `Registry`, `RegistryEntry`, `WellFormed`
  invariant (current_resolves, current_gen_lt, entry_key_consistent),
  `allocate`, `close`, `setInterests`, `setState`.
- `Iotakt.Model.Lifecycle` — lifecycle transitions
  (markConfigured/Listening/Registered/Active, beginClosing),
  `setState`/`close` projection lemmas, `close_preserves_wf`,
  `double_close_idempotent`, `registered_not_closed`.
- `Iotakt.Model.Translate` — `TranslationResult`, `DropReason`,
  `OwnerEvent`, `validateAndBuild`, `translateOne`, `translateMany`,
  `translateKeyed`.
- `Iotakt.Model.Coalesce` — `CoalesceState`, `PendingKind`, `PendingKey`,
  `CoalesceResult`, `step`, `ack`.
- `Iotakt.Model.Update` — `upd` generic map-update primitive.

**Machine-checked theorems**

- Registry: `wf_empty`, `allocate_preserves_wf`, `close_preserves_wf`,
  `allocate_fresh_gen`, `allocate_is_current`, `close_not_current`,
  `resolveCurrent_sound`.
- Translation: `translate_no_unknown`, `translate_injectable_owner`,
  `translate_readable_interest`, `translate_writable_interest`,
  `translate_injectable_live`, `translateKeyed_stale`,
  `translateKeyed_closed_dropped`.
- Coalescing: `step_twice_coalesced` (flood bound), `ack_clears`,
  `step_preserves_other`, `deliver_after_ack`.
- Lifecycle: `close_state_closed`, `double_close_idempotent`,
  `registered_not_closed`.

**Henret bridge (RFC 007, Henret v0.6.0)**

- `Iotakt.Bridge.Message` — `IoEvent.encode` bitmask,
  `encodeOwnerEvent`.
- `Iotakt.Bridge.Driver` — `DriverState`, `PollWaitResult`,
  `BridgeTrace`, `deliverOne` (guarded inject), `applyResult`,
  `processEvents`, `runPoll`, `nextDeadline`.
- **`inject_ok_of_mailbox`** — formally proven: when the owner mailbox
  exists, Henret `inject` always returns `.ok`. Mitigates Henret v0.6.0
  handoff discrepancy.
- `deliverOne_no_mailbox`, `deliverOne_coalesced`,
  `runPoll_interrupted_unchanged`, `processEvents_nil`.

**Fake poller (RFC 008)**

- `Iotakt.Fake.Poller` — `FakePollResult`, `FakePoller`, `next`,
  `ofScript`, `remaining`.
- `next_deterministic`, `next_scripted`, `next_advances`,
  `next_exhausted`.

**Demo executable**

- `iotakt-fake-demo` — 7 canonical scenarios through the real Henret
  v0.6.0 bridge (19 checks, all PASS). No OS calls, fully deterministic.
  Covers unknown/stale/coalesced/no-interest/EOF-bypass/timeout/
  interrupted cases, plus the complete Mesa round-trip (park → inject →
  wake → re-receive).

**Documentation**

- `docs/src/proof-trust-test-matrix.md` — PROVEN/TESTED/ASSUMED/OUTSCOPE
  claim classification (RFC 014).
- `docs/henret-integration-notes.md` — 3 Henret v0.6.0 discrepancies
  with mitigations and open questions.
- `docs/src/native-ffi-contract.md` — native C shim contract (RFC 009).
- `rfcs/` — all 60 design RFCs (001–060) in proposed; RFC 000 in done.

**RFC §21.4 criterion — Working TCP echo server**

- `iotakt-echo-server`: TCP listener on 127.0.0.1:49900, accepts one connection,
  reads bytes, echoes them back.
- Demonstrates the complete iotakt stack: `epoll_wait → Epoll.parseEvents →
  Registry.translateMany → Bridge.processEvents (coalesce + guarded inject) →
  Henret actor receives readiness → Io.recv → Io.send`.
- Verified end-to-end with `echo "hello from iotakt" | nc 127.0.0.1 49900`.

**IotaktDriver library**

- `Iotakt.Driver` module: `nativeStep`, `computeTimeout`, `setupListener`,
  `acceptOne`, `acceptBurst`, `PollerHandle`, `NativeDriverState` (with
  monotone `nextActorId` counter).

**CI gate updated to 8 steps**

- Step 8: echo server smoke test — starts server, connects nc, verifies echo.

### Not included in v0.1.0-dev

- Native C backend (epoll, POSIX sockets) — RFC 009–012 pending.
- Security hardening and resource limits — RFC 013 pending.
- Public API review — RFC 017 pending.
- CI/CD infrastructure — RFC 018 pending.
