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

## Next: v0.8.0 — scheduled connection actors + chunked encoding

Priority items:
- **Scheduled connection actors** — restructure so connection actors are genuine Henret-running tasks that can call `receiveUntil` directly, unifying iotakt's wall-clock park/wake with Henret's logical timer model. This is the deferred deep change from v0.7.
- **HTTP/1.1 chunked transfer encoding** — `Transfer-Encoding: chunked` in `Iotakt.Http` for streaming responses.
- **RFC 021** — BSD/macOS kqueue native backend (macOS CI runner).
- **runStepAuto adoption in examples** — migrate the routing/bench servers to `runStepAuto` with idle timeouts to demonstrate the zero-CPU-idle property end-to-end.

Priority items:
- **`receiveUntil` driver** — replace the 100ms `epoll_wait` poll loop with a park/wake pattern using Henret's `receiveUntil`; the driver blocks indefinitely in `epoll_wait` and wakes only on real I/O or timer expiry. Estimated ≥10× idle CPU reduction.
- **RFC 044 tracking** — Henret's integration contract targets v0.12.0; once it ships, iotakt's `docs/src/henret-integration.md` can reference stable import tiers explicitly.
- **RFC 021** — BSD/macOS kqueue native backend (requires macOS CI runner).
- **HTTP/1.1 chunked encoding** — `Transfer-Encoding: chunked` support in `Iotakt.Http`; needed for streaming responses in henejt.
- **RFC 044 external review prep** — iotakt is now a real downstream consumer of Henret; could serve as the motivating example for RFC 044.

Priority items:
- **RFC 035** — Henret wait-queue parking: when the Henret maintainer ships it, replace 100ms poll loops with park/wake for ≥10× idle CPU reduction.
- **Gap 006** — Actor lifecycle: call `Henret.terminate actorId` when closing a connection to free the mailbox.
- **henejt prototype** — First real HTTP/1.1 GET/POST request handling using `Iotakt.Actor` in the henejt layer.
- **RFC 021** — BSD/macOS kqueue native backend (macOS CI runner).
- **RFC 041** — TLS boundary document: where TLS sits relative to iotakt (iotakt hands off raw fd after accept; TLS layer wraps it).

Priority items:
- **`Iotakt.Actor`** — `ConnectionActor` abstraction: state machine (connecting / reading / writing / closing), integrates with Henret task model (RFC 035 prep).
- **RFC 035** — Henret wait-queue parking: when the Henret maintainer ships it, replace the poll loop with park/wake.
- **RFC 025** — Formal throughput benchmark: connection reuse, concurrent clients, bytes/sec, latency histogram.
- **Gap 004 resolution** — Document `nextActorId` counter as the official ActorId allocation pattern.
- **henejt prototype** — First HTTP/1.1 GET using iotakt outbound connect in the henejt layer.

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

## v0.3.0 — API stabilization and henejt integration

- RFC 028: Lean FFI hardening (ByteArray ownership formal contract).
- RFC 035: Henret wait-queue parking integration (when available from Henret maintainer).
- Stable API review based on henejt feedback.
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

## v0.3.0 — API stabilization and henejt integration

- RFC 025: performance benchmarks.
- RFC 017 rev: stable public API based on henejt feedback.
- RFC 020 / RFC 026: native conformance suite.

## Future (v0.2+ → long-term)

- RFC 028: Lean FFI hardening.
- RFC 035: Henret wait-queue parking integration (when available).
- RFC 036: UDP sockets.
- RFC 041: TLS boundary.
- RFC 056: io_uring backend research.
- RFC 059: post-v1 formal verification expansion.
