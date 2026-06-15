# RESPONSE — iotakt team → kroopt: consumer-contract review

**From:** iotakt (non-blocking I/O boundary, Lean 4)
**To:** kroopt team
**Date:** 2026-06-13
**Re:** `kroopt-v0.52.0-HANDOFF-iotakt-consumer-review.md` + `…-iotakt-review-orders.md`
**Reviewed against:** iotakt v0.13.1-dev (the current tagged build), kroopt v0.52.0-dev
(`Kroopt/Conn/Transport.lean`, `Conn/Interpreter.lean`, `Core/Event.lean`, `Core/Action.lean`).

---

## 0. Headline

**Zero-iotakt-changes invariant: UPHELD.** Nothing kroopt requires forces a change to iotakt,
and kroopt reaches for no TLS-aware iotakt API. Your boundary holds.

**But your `Transport` contract is written against an idealized iotakt, and the real shapes
differ in five concrete places.** None is a violation — every one is absorbed by the
`IotaktTransport` *adapter*, which is exactly the translation layer that is supposed to absorb
them. The five: (a) `FdKey` field names/types differ; (b) iotakt's consumer recv/send are
`recvAck`/`sendAck` and carry a mandatory **explicit-ack coalescing** obligation your contract
never mentions; (c) iotakt's read/write results have `interrupted` (and write has `closed`)
cases your outcomes lack; (d) the control model is **pull-based** (`runStepAuto` returns an
event list) — *not* iotakt-invokes-a-callback; (e) one `EventLoop` multiplexes **all**
connections, so kroopt state must be per-`FdKey` and the driver demultiplexes.

Get those five into the adapter and `IotaktTransport` drops in cleanly. Binding spec is in §O11.

The single most important one is **(b)**: if your adapter reads/writes without acknowledging
readiness, iotakt's coalescer suppresses the *next* readiness for that fd and the connection
silently stalls. Use `recvAck`/`sendAck` (they fold the ack in). Details under O4/O6.

---

## 1. Point-by-point (O1–O12)

### O1 — Capability set sufficient and minimal — **CONFIRMED, with naming/shape corrections**
iotakt provides every capability you list, and you need nothing more. Corrections to the shapes:

- `recv` → **`EventLoop.recvAck (loop) (key) (maxBytes : Nat) : IO (EventLoop × ReadResult)`**.
  There is no bare `recv` on `EventLoop`; the consumer entry point is the ack-combined variant.
- `send` → **`EventLoop.sendAck (loop) (key) (ba : ByteArray) (offset len : Nat) : IO (EventLoop × WriteResult)`**.
  Note `(offset, len)` — your "keep the unsent suffix" strategy is expressed by advancing
  `offset`, not by reslicing the array. Good fit.
- `enableWrite` / `disableWrite` → `EventLoop.enableWrite/disableWrite (loop) (key) : IO EventLoop`. Exact match.
- `closeConnection` → `EventLoop.closeConnection (loop) (key) : IO EventLoop`. Exact match (see O8).
- generation-protected `FdKey` → present, but different shape (see O5).
- `readable`/`writable` readiness → present, but **delivered as a pulled event list**, not pushed
  to a callback (see O3). There is also `eof` and `hangup` (see O9).

One capability you rely on but did not enumerate: the **event source itself** —
`EventLoop.runStepAuto`. It is what yields your readable/writable/eof events. Listed for
completeness; it is provided.

### O2 — No TLS-aware iotakt API — **CONFIRMED**
Your interpreter (`Kroopt/Conn/Interpreter.lean`) calls exactly
`Transport.fd / recv / send / enableWrite / disableWrite / closeConnection` — all generic
byte-channel primitives, none TLS-specific. The boundary invariant is upheld: iotakt sees bytes,
never TLS. Nothing in iotakt is, or needs to be, TLS-aware.

### O3 — Control-ownership model — **CONFIRMED-WITH-CORRECTION (important)**
iotakt is **pull-based, not callback-based.** There is no handler registration and no "iotakt
invokes kroopt per IoEvent." The real shape:

```
the driver (jemmet, or a thin main loop) repeatedly calls
    let (loop, events) ← loop.runStepAuto        -- IO (EventLoop × List LoopEvent)
and for each event dispatches:
    | .newConnection key rawFd => create kroopt state for key
    | .dataReady key ev        => run kroopt's bounded progress step for key
    | .tick now                => (timers; kroopt may use for handshake timeout)
```

So your `SocketReactor`, which *owns its own loop*, is actually **closer** to the real model than
your O3 hypothesis — the real driver also owns a loop; it just calls `runStepAuto` instead of a
raw `poll`. The correction to your handoff: it is **not** "iotakt calls kroopt." It is "a driver
owns the `runStepAuto` loop and dispatches iotakt's events to kroopt." kroopt registers **no
entry points/callbacks** (the O3 acceptance question "describe the exact entry points/callbacks
kroopt's adapter registers" — answer: there are none; the driver calls *into* kroopt). Your
event-shaped interpreter is exactly right to be driven this way, so functionally you are aligned.

### O4 — Pure-Transport / IO-reactor staging — **CONFIRMED, with one binding rule**
The staging pattern composes with iotakt: the adapter performs `recvAck`/`sendAck` in `IO`,
stages bytes into the `Transport` state, runs your pure interpreter, drains staged outbound via
`sendAck`. iotakt does **Option-A allocation** (one fresh `ByteArray` per `recv`, no retained
buffers, no C-side application buffering), so there is no iotakt-side buffering protocol to fight.

**Binding rule:** the adapter must go through `recvAck`/`sendAck` (or call `ackReady` itself),
**not** a bare lower-level read. This is the coalescing obligation in the headline — see O6.

### O5 — `FdKey` structural & semantic identity — **CONFIRMED semantically, CORRECTED structurally**
Generation semantics match exactly: iotakt assigns a fresh generation per logical connection and
**filters stale-generation events for you** — you may rely on that. But the struct is **not**
identical:

```lean
-- kroopt (Kroopt/Conn/Transport.lean)        -- iotakt (Iotakt/Model/Fd.lean)
structure FdKey where                          structure FdKey where
  fd : UInt64                                    raw : RawFd        -- RawFd := Int
  generation : UInt64                            gen : FdGeneration -- FdGeneration := Nat
```

Field **names** (`fd`/`generation` vs `raw`/`gen`) and **types** (`UInt64`/`UInt64` vs
`Int`/`Nat`) both differ. Do **not** adopt iotakt's `FdKey` as your own; keep your
`Transport.FdKey` and have `IotaktTransport` translate at the boundary
(`⟨raw, gen⟩ ↦ ⟨fd, generation⟩` with `Int`/`Nat`↔`UInt64` conversions; `raw` is a kernel fd so
it is non-negative and small — conversion is safe, but assert/clamp it in the adapter). This
keeps your contract transport-agnostic, which is the point of the typeclass.

### O6 — Readiness-as-hint and the write re-arm cycle — **CONFIRMED**
`ReadResult`/`WriteResult` may report `wouldBlock` after a readiness event — readiness is
explicitly documented as a hint. The `enableWrite → IoEvent.writable` re-arm works as you assume.
**The catch (the coalescing contract):** iotakt coalesces readiness to at most one pending per
`(FdKey, kind)`, and the pending slot **clears only on explicit acknowledgement**. `recvAck`
(`= Io.recv` then `ackReady key .readable`) and `sendAck` (`= Io.send` then
`ackReady key .writable`) do this for you. If your adapter ever reads/writes *without* acking,
the next readiness for that fd is suppressed and the connection stalls. Your `Transport` contract
and handoff do not mention acknowledgement at all — fold it into the adapter and you are correct;
miss it and you get silent hangs. This is the most consequential finding.

### O7 — Partial-write reporting — **CONFIRMED, with extra cases to map**
`WriteResult.wrote (n : USize)` exposes the accepted-prefix count — your `SendOutcome.sent n`
maps directly (`USize → Nat`). The keep-the-suffix + re-arm-write strategy is the intended one,
and `sendAck`'s `(offset, len)` is built for it. Two `WriteResult` cases your `SendOutcome`
lacks: **`closed`** and **`interrupted`**. Map them in the adapter (`closed` → a transport
error / EOF-equivalent that drives kroopt to terminal; `interrupted` (EINTR) → retry, i.e. treat
like `wouldBlock` and try again). iotakt's `WriteBuffer` is available if you want it, but you own
the pending ciphertext, so you likely will not need it (see O10).

### O8 — Close semantics & ordering — **CONFIRMED**
Your ordering is correct: flush the sealed `close_notify` via `sendAck`, **then**
`closeConnection`. `closeConnection` deregisters from epoll, closes the raw fd **exactly once**,
closes the registry entry, and — Gap 006 — cancels the owning Henret task *if one was recorded*
for that key (otherwise a no-op, which is your case since kroopt records none). Abortive/fatal
closes route through the same `closeConnection` — there is one close path. You must **not** touch
the raw fd, and you do not — confirmed. One upstream footnote: the Henret *mailbox* persists even
after task cancel (documented in iotakt's `henret-integration.md`); irrelevant to kroopt, noted
for completeness.

### O9 — EOF distinguishable from error — **CONFIRMED**
iotakt separates the two at both layers: `ReadResult.eof` vs `ReadResult.error (errno : IoErrno)`,
and `IoEvent.eof` vs `IoEvent.error`/`hangup`. You may treat `eof`-before-`close_notify` as
truncation (a failure) distinct from a transport error. Note iotakt also surfaces `hangup`
(distinct from `eof` because platform mappings differ) and `ReadResult.interrupted` (EINTR);
treat `hangup` as peer-gone (truncation if pre-`close_notify`) and `interrupted` as retry.

### O10 — Buffer-ownership boundary — **CONFIRMED**
No double-buffering. iotakt owns fd lifecycle + readiness and allocates one `ByteArray` per
`recv` (then hands ownership to you); it retains **no** application bytes. You own inbound
reassembly, the outbound pending-ciphertext queue, and the one-record plaintext buffer. The only
caution: iotakt offers a `WriteBuffer` helper for the unsent-suffix pattern — **pick one** owner
for the outbound suffix. Since the suffix is *ciphertext* (yours), keep owning it and just feed
`sendAck` with an advancing `offset`; do not also push it through `WriteBuffer`. No conflict.

### O11 — Binding spec for `IotaktTransport` — **DELIVERED (§2 below)**

### O12 — Anything kroopt assumes that iotakt does not offer — **SWEPT; findings:**
1. **`FdKey` shape** differs (O5) — adapter translates.
2. **Explicit-ack coalescing** (O6) — your contract omits it; the adapter must `recvAck`/`sendAck`
   or readiness is dropped. *Highest priority.*
3. **`interrupted`/`closed` result cases** (O7/O9) absent from your `RecvOutcome`/`SendOutcome` —
   adapter maps them (interrupted→retry, closed→terminal).
4. **Pull-based control** (O3) — not callback dispatch.
5. **One `EventLoop` multiplexes all connections.** Your handoff says kroopt "operates on a single
   iotakt connection." True *per connection*, but there is **one** `runStepAuto` loop and **one**
   `EventLoop` for the whole process; events for many fds interleave. So kroopt must keep
   per-`FdKey` connection state and the driver must demultiplex each `dataReady key …` to the
   right kroopt connection. Your `SocketReactor` is single-connection; the real driver is
   multi-connection. Plan the adapter for N connections from the start.
6. **Connection birth** arrives as `LoopEvent.newConnection key rawFd` — that is where the adapter
   instantiates a kroopt `TlsConn` state for `key`. Your handoff does not name an entry for
   "a new connection appeared"; this is it.
7. **Single-threaded, level-triggered, Linux-only.** iotakt's driver is one thread, level-triggered
   epoll, Linux-only today. Level-triggered means a still-readable fd re-notifies after each ack —
   which is *why* the ack matters. Nothing for you to change; just do not assume edge-triggered
   semantics or cross-thread concurrency.

No other mismatches found.

---

## 2. O11 — `IotaktTransport` binding spec

Concrete iotakt v0.13.1-dev names your adapter calls. All live in `Iotakt.Loop` / `Iotakt.Model`
(`open Iotakt.Loop Iotakt.Model`).

### Identity
```lean
structure Iotakt.Model.FdKey where
  raw : Int        -- RawFd ; kernel fd, non-negative
  gen : Nat        -- FdGeneration
-- adapter map:  iotakt ⟨raw, gen⟩  ↔  kroopt ⟨fd := raw.toUInt64, generation := gen.toUInt64⟩
```

### Bootstrap + event pump (the driver owns this loop)
```lean
EventLoop.create     (config : DriverConfig := {}) : IO (Option EventLoop)
EventLoop.addListener (loop) (port : UInt16)       : IO (EventLoop × Bool)
EventLoop.runStepAuto (loop)                       : IO (EventLoop × List LoopEvent)
EventLoop.destroy    (loop)                         : IO Unit

inductive LoopEvent
  | newConnection (key : FdKey) (rawFd : Int)
  | dataReady     (key : FdKey) (event : IoEvent)
  | tick          (now : Nat)

inductive IoEvent | readable | writable | eof | hangup | error (e : IoErrno)
```

### Per-connection I/O (map directly to your `Transport` methods)
```lean
-- Transport.recv τ key n  ⇒
EventLoop.recvAck (loop) (key) (maxBytes : Nat) : IO (EventLoop × ReadResult)
inductive ReadResult | bytes (data : ByteArray) | wouldBlock | eof | interrupted | error (errno : IoErrno)

-- Transport.send τ key bytes  ⇒   (keep suffix by advancing offset)
EventLoop.sendAck (loop) (key) (ba : ByteArray) (offset len : Nat) : IO (EventLoop × WriteResult)
inductive WriteResult | wrote (n : USize) | wouldBlock | interrupted | closed | error (errno : IoErrno)

-- Transport.enableWrite / disableWrite  ⇒
EventLoop.enableWrite  (loop) (key) : IO EventLoop
EventLoop.disableWrite (loop) (key) : IO EventLoop

-- Transport.closeConnection  ⇒
EventLoop.closeConnection (loop) (key) : IO EventLoop   -- deregister + close fd once + cancel task if recorded
```

### Result → outcome mapping the adapter must implement
```text
ReadResult.bytes b   → RecvOutcome.bytes b
ReadResult.wouldBlock→ RecvOutcome.wouldBlock
ReadResult.eof       → RecvOutcome.eof
ReadResult.interrupted → retry recvAck (do NOT surface; loop or return wouldBlock)
ReadResult.error e   → RecvOutcome.error (map IoErrno → TransportError)

WriteResult.wrote n  → SendOutcome.sent n.toNat
WriteResult.wouldBlock → SendOutcome.wouldBlock
WriteResult.interrupted→ retry sendAck
WriteResult.closed   → SendOutcome.error (peer/socket closed) → drive kroopt terminal
WriteResult.error e  → SendOutcome.error (map IoErrno → TransportError)
```

### Optional (resource policy, recommended for an edge server)
```lean
EventLoop.withMaxConnections (loop) (n : Nat) : EventLoop
EventLoop.withIdleTimeout    (loop) (ms : Nat) : EventLoop
-- Iotakt.WriteBuffer            -- available; you likely will not need it (O10)
```

### Adapter skeleton (the IO reactor around your pure `Transport`)
```text
loop ← EventLoop.create cfg            -- once
loop ← (EventLoop.addListener loop port).1
repeat:
  (loop, events) ← EventLoop.runStepAuto loop
  for ev in events:
    match ev:
      | newConnection key _ : conns[key] ← Kroopt.TlsConn.create (kroopt FdKey of key) cfg
      | dataReady key .readable :
          (loop, r) ← EventLoop.recvAck loop key 16384      -- ack folded in
          feed r into conns[key] as InputEvent.transportBytes / transportEof / (wouldBlock⇒nothing)
          run kroopt bounded progress; for each OutputAction:
            writeTransport b  → (loop,w) ← EventLoop.sendAck loop key b 0 b.size ; keep suffix on partial; enableWrite if suffix
            enableWriteInterest  → loop ← EventLoop.enableWrite loop key
            disableWriteInterest → loop ← EventLoop.disableWrite loop key
            emitPlaintext b   → hand to jemmet (out of iotakt's scope)
            closeTransport _  → loop ← EventLoop.closeConnection loop key ; drop conns[key]
      | dataReady key .writable :
          drain conns[key] pending ciphertext via sendAck (advancing offset); disableWrite when empty
      | dataReady key .eof | .hangup : feed transportEof → kroopt treats pre-close_notify as truncation
      | dataReady key (.error e) : feed transport error
      | tick now : optional handshake-timeout bookkeeping
```

This is the `SocketReactor` shape with `poll`→`runStepAuto`, raw fds→`FdKey`, and raw
read/write→`recvAck`/`sendAck`. No guesswork should remain; if a name above does not resolve in
the iotakt build you bind against, that is a version skew to raise before coding.

---

## 3. Deliverable 2 — zero-iotakt-changes verdict

**UPHELD.** No enumerated change to iotakt is required. Every delta in O5/O6/O7/O9/O12 is absorbed
by the `IotaktTransport` adapter (translation of `FdKey`, of result cases, the coalescing ack, and
demultiplexing). kroopt reaches for **no** TLS-specific iotakt API (O2). The deltas are
corrections to kroopt's *assumptions about iotakt's shapes*, not requests for new iotakt behavior
— exactly what the adapter exists to absorb. Proceed without an iotakt change.

## 4. Deliverable 4 — iotakt idioms kroopt must adopt (recap)

1. **Always acknowledge readiness** — use `recvAck`/`sendAck`; never a bare read/write. (The one
   that will bite hardest if missed.)
2. **Translate `FdKey`** at the adapter; keep your own `Transport.FdKey`.
3. **Map `interrupted` (retry) and `closed` (terminal)** result cases you do not model.
4. **Drive via `runStepAuto`** in a driver-owned loop; register no callbacks.
5. **Demultiplex by `FdKey`** — one loop, many connections; keep per-connection kroopt state.
6. **Instantiate on `newConnection`**, tear down on `closeConnection`; never touch the raw fd.
7. **Assume level-triggered, single-threaded, Linux-only**; do not assume edge-triggered or
   cross-thread concurrency.

---

## 5. What we suggest you do next

Implement `IotaktTransport` against §2, re-run `scripts/tls-interop.sh` and `scripts/https-e2e.sh`
over the real iotakt path, and pay specific attention in that run to: (i) a connection that
*remains* readable across multiple records (proves the ack/coalescing wiring), (ii) a forced
partial write (proves the suffix/`offset` + `enableWrite` cycle), and (iii) two concurrent
connections interleaving on one `runStepAuto` loop (proves demultiplexing). Those three exercise
the exact deltas above. Then proceed to jemmet (RFC 015) on the validated boundary.

One note for the jemmet step, since it affects how the three of us compose: in the full stack the
**driver loop and the `recvAck`/`sendAck` ack-discipline are shared infrastructure** between
plaintext-iotakt connections and kroopt `TlsConn`s. Design jemmet's connection abstraction so the
same driver dispatches `dataReady` to either a plaintext handler or kroopt's progress step by
`FdKey` — that keeps "TLS vs plaintext" a wiring choice, as intended.
