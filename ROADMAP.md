# Roadmap

See `rfcs/README.md` for the full RFC index.

## Released: v0.1.0-dev — Pure model + Henret bridge + Linux epoll
All v0.1 RFCs (001–015, 018, 019) implemented. CI gate: 8 steps, 52+ checks.

## Released: v0.2.0-dev — Public API + Multi-connection EventLoop
RFC 017 stable API, `Iotakt.Loop` EventLoop, multi-connection echo server, GitHub Actions CI. 9 steps.

## Released: v0.3.0-dev — UDP + Outbound connect + kqueue analysis
RFC 036 UDP, RFC 039 outbound connect, RFC 016 kqueue analysis, persistent connections. 10 steps.

## Released: v0.4.0-dev — WriteBuffer + HTTP/1.0 + FFI hardening
`WriteBuffer`, `Iotakt.Http`, HTTP server+client, RFC 028 FFI contract, RFC 026 conformance. 12 steps, 22 RFCs done.

## Released: v0.5.0-dev — ConnectionActor + Stats + Throughput baseline
`ConnectionActor` + `ActorRegistry`, `ConnStats`/`GlobalStats`, HTTP/1.1 keep-alive, RFC 025 benchmark (~330k req/s baseline), Gap 004 resolved. 14-step CI, 23 RFCs done.

## Released: v0.6.0-dev — henret v0.11.0 + Router + Gap 006 cancel-on-close
Dependency bumped to henret v0.11.0 (RFCs 033–040). `inject_ok_of_mailbox` updated for timed-waiter queue. `Iotakt.Router` with path params. `EventLoop.closeConnection` issues `cancel` to free Henret runtime state. TLS boundary doc (RFC 041). 16-step CI, 24 RFCs done.

## Released: v0.7.0-dev — henret v0.12.1 + adaptive poll timeout + idle reaping
Dependency to henret v0.12.1 (non-breaking through v0.11.1/v0.12.0/v0.12.1). `pollTimeoutMs`/`runStepAuto` park/wake driver (idle server = 0% CPU). Idle connection reaping. `receiveUntil` timer infrastructure verified. 17-step CI.

## Released: v0.8.0-dev — chunked encoding + scheduled connection actors
HTTP/1.1 chunked transfer encoding (`Iotakt.Chunked`, RFC 7230 §4.1). Scheduled connection-actor lifecycle model (`Iotakt.SchedConn`) — genuine Henret-running task via receiveUntil, verified against real semantics. Chunked streaming server using runStepAuto + idle reaping. 19-step CI.

## Released: v0.9.1-dev — henret v0.15.2 + jemmet rename + supervised restart
Dependency to henret v0.15.2 (non-breaking through v0.13.x–v0.15.2). Adopted RFC 049 supervision restart in `Iotakt.SchedConn` (`fail`/`restart`/`ConnPhase.failed`). Project rename henejt → jemmet across code/docs/RFCs. 21-step CI.

## Released: v0.9.0-dev — body-aware request reading + jemmet handoff surface
`Iotakt.RequestBody.readFull` reassembles Content-Length and chunked request bodies off a live socket (RFC 7230 §3.3.3). `Iotakt.Server` consolidated handoff surface for jemmet. Upload server verified with both framings. jemmet-handoff.md consumer contract. 21-step CI.

## Released: v0.10.0-dev — keep-alive building blocks + request-size limits
`readFromBuffer` for pipelining-correct request reading (consumer keep-alive loses no data); `maxBytes` request-size limits (`ReadResult.tooLarge` → consumer 413). Reference consumer *example* (not a library module) proving the handoff surface is sufficient. jemmet itself remains a separate future project. 23-step CI.

## Released: v0.11.0-dev — graceful shutdown + connection limits (iotakt stabilization)
`EventLoop.shutdown` (RFC 037): stop accepting, drain/close active connections + listeners cleanly. Connection cap (RFC 030): `withMaxConnections`/`connectionCount`/`atCapacity`; `runStep` sheds accepts past the cap. Verified live (cap=1 admits ≤1 of 3 clients; shutdown drains all). 24-step CI. 26 RFCs done.

## Released: v0.12.0-dev — proof/trust/test-matrix refresh + API stability review
Matrix doc refreshed to current state (77 theorems, 0 sorry/axiom, 321 checks, native implemented); matrix-honesty CI guard added (count can't drift). API stability audit (`docs/src/api-stability.md`, applies RFC 031) classifies the public surface Stable/Provisional/Internal toward v1.0. jemmet prototype preserved as handoff seed in `jemmet-handoff/`. CI renumbered to 25 sequential steps.

## Next: v0.13.0 — settle the v1.0 open items (toward a v1.0 candidate)

Work through the API-stability open items so the Provisional column can be emptied:
- **Coalesce ack API** — decide `ackReady` vs. clear-on-recv (External Design §23.7) and pin it.
- **`Router` placement** — decide whether the convenience router ships in iotakt or moves to the consumer (it is an RFC 001 non-goal); if it stays, justify it; if not, remove it and update examples.
- **Task-tracking visibility** — demote the Gap-006 bookkeeping (`recordTask`/`forgetTask`/`taskByKey`) to internal if the cancel-on-close path is considered final.
- **RFC 021** — BSD/macOS kqueue native backend (still blocked on a macOS CI runner; model is already kqueue-aware).

## Toward v1.0 (requires explicit sign-off — not to be cut autonomously)
- Empty the Provisional column; freeze the Stable surface.
- Final proof/trust/test matrix and API stability sign-off.
- jemmet (the HTTP server) is built **separately** on the stable surface, after v1.0, seeded from `jemmet-handoff/`.

Priority items:
- **Keep-alive in the read path** — `readFull` currently reads one request then the server closes; extend the driver/example to keep the connection open and read successive requests on the same fd (HTTP/1.1 default), reusing the idle-timeout machinery for connection lifetime.
- **jemmet prototype** — a separate small crate/example that builds a real HTTP service on `Iotakt.Server` (multiple routes, JSON-ish responses, request bodies), proving the handoff surface is sufficient. This is the first genuine downstream consumer.
- **Trailers** — chunked trailer headers (RFC 7230 §4.1.2), if the jemmet prototype needs them.
- **RFC 021** — BSD/macOS kqueue native backend (still blocked on a macOS CI runner).
- **Request size limits** — enforce `maxRequestBytes` in `readFull` to bound memory (slow-loris / oversized-body protection); surface a 413-style `.error`.

Priority items:
- **Chunked request decoding in the live read path** — wire `Chunked.decode` into the server read loop so request bodies with `Transfer-Encoding: chunked` are reassembled before dispatch (currently decode is tested standalone).
- **jemmet handoff surface** — package the Router + Http + Chunked + SchedConn as the stable API that jemmet builds its HTTP layer on; document the consumer contract (mirrors what `henret-integration.md` does for the Henret side).
- **RFC 021** — BSD/macOS kqueue native backend (needs a macOS CI runner; model compatibility already documented in RFC 016).
- **Trailers** — chunked trailer headers (RFC 7230 §4.1.2), if jemmet needs them.
- **Scheduled driver prototype** — an optional `runStepScheduled` that actually drives connection actors through the `SchedConn` lifecycle, as an alternative to the inject path, for multi-worker futures.

Priority items:
- **Scheduled connection actors** — restructure so connection actors are genuine Henret-running tasks that can call `receiveUntil` directly, unifying iotakt's wall-clock park/wake with Henret's logical timer model. This is the deferred deep change from v0.7.
- **HTTP/1.1 chunked transfer encoding** — `Transfer-Encoding: chunked` in `Iotakt.Http` for streaming responses.
- **RFC 021** — BSD/macOS kqueue native backend (macOS CI runner).
- **runStepAuto adoption in examples** — migrate the routing/bench servers to `runStepAuto` with idle timeouts to demonstrate the zero-CPU-idle property end-to-end.

Priority items:
- **`receiveUntil` driver** — replace the 100ms `epoll_wait` poll loop with a park/wake pattern using Henret's `receiveUntil`; the driver blocks indefinitely in `epoll_wait` and wakes only on real I/O or timer expiry. Estimated ≥10× idle CPU reduction.
- **RFC 044 tracking** — Henret's integration contract targets v0.12.0; once it ships, iotakt's `docs/src/henret-integration.md` can reference stable import tiers explicitly.
- **RFC 021** — BSD/macOS kqueue native backend (requires macOS CI runner).
- **HTTP/1.1 chunked encoding** — `Transfer-Encoding: chunked` support in `Iotakt.Http`; needed for streaming responses in jemmet.
- **RFC 044 external review prep** — iotakt is now a real downstream consumer of Henret; could serve as the motivating example for RFC 044.

Priority items:
- **RFC 035** — Henret wait-queue parking: when the Henret maintainer ships it, replace 100ms poll loops with park/wake for ≥10× idle CPU reduction.
- **Gap 006** — Actor lifecycle: call `Henret.terminate actorId` when closing a connection to free the mailbox.
- **jemmet prototype** — First real HTTP/1.1 GET/POST request handling using `Iotakt.Actor` in the jemmet layer.
- **RFC 021** — BSD/macOS kqueue native backend (macOS CI runner).
- **RFC 041** — TLS boundary document: where TLS sits relative to iotakt (iotakt hands off raw fd after accept; TLS layer wraps it).

Priority items:
- **`Iotakt.Actor`** — `ConnectionActor` abstraction: state machine (connecting / reading / writing / closing), integrates with Henret task model (RFC 035 prep).
- **RFC 035** — Henret wait-queue parking: when the Henret maintainer ships it, replace the poll loop with park/wake.
- **RFC 025** — Formal throughput benchmark: connection reuse, concurrent clients, bytes/sec, latency histogram.
- **Gap 004 resolution** — Document `nextActorId` counter as the official ActorId allocation pattern.
- **jemmet prototype** — First HTTP/1.1 GET using iotakt outbound connect in the jemmet layer.

## v0.6.0+ — Future

- RFC 021: BSD/macOS kqueue native backend (macOS CI runner).
- RFC 041: TLS boundary document (iotakt hands off the fd after handshake).
- RFC 056: io_uring backend research.
- RFC 059: post-v1 formal verification expansion (connection-level liveness proofs).


All v0.1 RFCs (001–015, 018, 019) implemented. Highlights:
- Pure model with 28+ machine-checked theorems.
- `inject_ok_of_mailbox` theorem (formal proof of Henret discrepancy mitigation).
- Linux epoll native backend (Option A recv, MSG_NOSIGNAL send).
- `iotakt-echo-server`: RFC §21.4 acceptance criterion ✓.
- CI gate: 8 steps, 52+ checks.

## Released: v0.2.0-dev — Public API + Multi-connection event loop

- RFC 017: `Iotakt.Api` stable public API module.
- `Iotakt.Loop` `EventLoop`: multi-connection accept/dispatch.
- `iotakt-multi-echo`: N concurrent connections.
- GitHub Actions CI (3 jobs: lean-model, native-linux, sanitizer).
- 19 RFCs in done/, CI gate 9 steps.

## Next: v0.2.1 — kqueue compatibility + performance baseline

Remaining for v0.2 milestone:
- RFC 016: kqueue model compatibility analysis (model constraints, no native impl yet).
- RFC 025: formal throughput benchmark (not just the baseline script).
- RFC 036: UDP socket support (small, high-value addition).
- Henret open questions resolved (ActorId allocation, RFC 033, drain policy).
- Gap 004 resolution: document the `nextActorId` counter pattern as the official approach.

## v0.3.0 — API stabilization and jemmet integration

- RFC 028: Lean FFI hardening (ByteArray ownership formal contract).
- RFC 035: Henret wait-queue parking integration (when available from Henret maintainer).
- Stable API review based on jemmet feedback.
- RFC 026: native conformance test suite.

## Future (v0.3+ → long-term)

- RFC 021: BSD/macOS kqueue native backend.
- RFC 041: TLS boundary.
- RFC 056: io_uring backend research.
- RFC 059: post-v1 formal verification expansion.


**Status:** In progress.

Completed:
- Pure model (RFCs 002–006): `FdKey`, registry, lifecycle, events,
  translation, coalescing — all with machine-checked theorems.
- Henret bridge (RFC 007): deterministic driver, guarded inject,
  `inject_ok_of_mailbox` theorem.
- Fake poller (RFC 008): deterministic scripted backend, replay lemmas.
- Demo: 7 canonical scenarios, 19 checks, all PASS.
- Proof/trust/test matrix, henret integration notes.

Remaining for v0.1.0:
- RFC 009–012: native C FFI, buffer ownership, Linux epoll, socket API.
- RFC 013: security, operational limits, graceful shutdown.
- RFC 014: full proof matrix review and final CI.
- RFC 015: observability/trace.
- RFC 017: public API review.
- RFC 018: CI, Lake packaging, release gates.
- RFC 016: kqueue model compatibility analysis (implementation deferred).
- RFC 019: architecture gap register.

## v0.2.0 — kqueue backend

- RFC 021: BSD/macOS kqueue native backend.
- RFC 023: echo-server example.
- Additional conformance tests.

## v0.3.0 — API stabilization and jemmet integration

- RFC 025: performance benchmarks.
- RFC 017 rev: stable public API based on jemmet feedback.
- RFC 020 / RFC 026: native conformance suite.

## Future (v0.2+ → long-term)

- RFC 028: Lean FFI hardening.
- RFC 035: Henret wait-queue parking integration (when available).
- RFC 036: UDP sockets.
- RFC 041: TLS boundary.
- RFC 056: io_uring backend research.
- RFC 059: post-v1 formal verification expansion.
