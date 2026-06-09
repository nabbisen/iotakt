# Changelog

All notable changes to iotakt are documented here.

## [Unreleased]

Work in progress toward v0.1.0.

## [0.4.0-dev] — 2026-06-08

### Added

**WriteBuffer (`Iotakt.WriteBuffer`, RFC 010 completion)**

- `WriteBuffer` struct: `pending : ByteArray`, `offset : Nat`.
- `empty`, `isEmpty`, `unsent`, `push`, `flush`, `flushAll` operations.
- `flush` handles partial writes (`wrote n < len`) and `.wouldBlock`; returns `(buffer, allFlushed)`.
- `flushAll` retries up to `maxRetries` times — for tests and tight loops.
- `IotaktWriteBuffer` Lake library target.

**HTTP/1.0 (`Iotakt.Http`, v0.4 henejt integration prep)**

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

- `Iotakt.Api` — stable module that henejt and applications should import;
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
