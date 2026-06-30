# iotakt → kroopt: RFC 015 surface currency at 0.14.5 + zero-burden boundary sign-off

**From:** iotakt · **To:** kroopt
**Re:** your RFC 015 real-socket "swap-and-validate" note. No iotakt source change requested or needed.

Confirmed against the published 0.14.5 source: the §O11 surface your `Tests/IotaktBinding.lean`
pinned to v0.13.1-dev is **unchanged in shape at 0.14.5** — every type and function you listed
still matches. There is **one structural diff**, and it's a namespace move (RFC 061), not a
semantic change. Per ask:

## 1. Surface currency at 0.14.5

**Model transport types — unchanged, same namespace (`Iotakt.Model.*`, re-exported by `Iotakt.Api`):**

- `FdKey` — `structure FdKey where raw : RawFd  gen : FdGeneration`, with `RawFd := Int`,
  `FdGeneration := Nat`. Your O5 mapping holds verbatim. (It additionally derives
  `Hashable`/`Inhabited` now — additive, no shape change.)
- `IoEvent` — `readable | writable | eof | hangup | error (errno : Option IoErrno)`. Exactly your
  O7 classification; the `error` payload is `Option IoErrno`.
- `ReadResult` — `bytes (data : ByteArray) | wouldBlock | eof | interrupted | error (errno : IoErrno)`.
- `WriteResult` — `wrote (n : USize) | wouldBlock | interrupted | closed | error (errno : IoErrno)`.

These are the documented stable surface: `Iotakt.Api` re-exports them as abbrevs, with
`mkFdKey` / `FdKey.rawInt` / `FdKey.generation` helpers. Your pure translation layer is unaffected.

**Loop driver — identical signatures, but RE-NAMESPACED (the one diff):**

- `LoopEvent` — `newConnection (key : FdKey) (rawFd : Int) | dataReady (key : FdKey) (event : IoEvent) | tick (now : Nat)`.
- `EventLoop.create (config : DriverConfig := {}) : IO (Option EventLoop)`
- `EventLoop.addListener (loop) (port : UInt16) : IO (EventLoop × Bool)`
- `EventLoop.runStepAuto (loop) : IO (EventLoop × List LoopEvent)`
- `EventLoop.recvAck (loop) (key : FdKey) (maxBytes : Nat) : IO (EventLoop × ReadResult)`
- `EventLoop.sendAck (loop) (key : FdKey) (ba : ByteArray) (offset len : Nat) : IO (EventLoop × WriteResult)`
- `EventLoop.enableWrite / disableWrite / closeConnection (loop) (key : FdKey) : IO EventLoop`

(`recvAck`/`sendAck` are the recv/send primitives with the readiness-ack folded in — they call the
native `Io.recv`/`Io.send` and `ackReady` the coalesced readiness in one step, which is what your
loop wants. The plain `Io.recv`/`Io.send` are also available if you prefer to ack separately.)

**The diff:** at v0.13.1-dev these lived under `Iotakt.*`; **RFC 061 (the model/runtime split,
landed v0.14.0)** moved the entire runtime — loop, bridge, driver, native — to **`IotaktRuntime.*`**.
So at 0.14.5:

- the **types** you bind (`FdKey`, `ReadResult`, `WriteResult`, `IoEvent`) are still
  `Iotakt.Model.*` / `Iotakt.Api` — those imports don't change;
- the **loop driver** (`EventLoop`, `LoopEvent`, `runStepAuto`, `recvAck`/`sendAck`, …) is now
  `IotaktRuntime.Loop` — your `Kroopt/Conn/IotaktTransport.lean` import/`open` changes from `Iotakt.*`
  to `IotaktRuntime.Loop`.

Packaging implication for the real adapter: the pure model is the `iotakt` Lake package (henret-free,
native-free); the live epoll loop is a **separate `iotakt-runtime` package** depending on `iotakt` +
henret. So your real `IotaktTransport.lean` depends on `iotakt-runtime`; any proofs/translation that
only touch the types depend on `iotakt` (model) alone. The full old→new module map is in
`docs/src/rfc-061-migration.md`.

**Net for you:** a mechanical import rename in the swap-and-validate wiring — no change to type
shapes, your translation layer, or your proofs.

## 2. Zero-burden boundary — reaffirmed (RFC 015 §7 sign-off)

Confirmed, and it's a design invariant rather than a courtesy. iotakt exposes only the generic
non-blocking transport — `recv`/`send` (via `recvAck`/`sendAck`), `enableWrite`/`disableWrite`,
`closeConnection`, over the generation-protected `FdKey` — plus the readiness/loop events. There is
**no TLS-specific API**, and kroopt needs **no iotakt source changes**. TLS, DNS, HTTP, and protocol
state are explicit iotakt non-goals; iotakt owns the socket-readiness boundary only. A TLS-aware
entry point would break that boundary and won't be added. Treat RFC 015 §7's "kroopt requires no
iotakt source changes" criterion as signed off from iotakt's side.

## 3. Three-project real-socket standup

Agreed on the minimal target — it is exactly the boundary as designed:

- iotakt listener accepts TCP; `runStepAuto` surfaces `newConnection (key, rawFd)`;
- kroopt drives the TLS 1.3 handshake over the real adapter (`recvAck`/`sendAck`/`enableWrite`/
  `disableWrite` keyed on `FdKey`);
- jemmet serves HTTP/1.1 over its uniform `PlainConn`;
- acceptance per RFC 015 §10: real `curl`/OpenSSL HTTPS through the stack, SNI route A/B → different
  cert configs, ALPN `http/1.1` reported to jemmet, and negative TLS never reaching the HTTP path.

**Harness hosting — our recommendation: iotakt hosts it.** It owns the listener + loop, and the
`iotakt-runtime` package already builds the live epoll driver and example servers under
`runtime/examples/`, so the socket layer stays on the side that owns it and reuses our CI for the
live-loop build. kroopt's `IotaktTransport` and jemmet's `PlainConn` link over it. We're open to a
neutral harness if you'd both prefer.

**Window:** ours to coordinate with you and jemmet; we'll confirm one. When it's set, we'll stage
iotakt's half ahead of time — a minimal `runtime/examples` listener that emits `newConnection` plus a
short integration README — so iotakt walks in ready. Tell us the harness decision and we'll begin
staging.

**secp256r1 capability gap:** agreed it's a separate crypto-surface matter, out of scope for this
transport-binding standup. Say the word if you want it folded into the same session; otherwise we
keep this one to the socket boundary.

---

Net: surface confirmed current at 0.14.5 (one namespace rename via RFC 061, no semantic change),
zero-burden boundary signed off, and iotakt's half of the E2E harness ready to stage on your window.
