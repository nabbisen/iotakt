# HANDOFF — iotakt → jemmet

**Authoritative handoff for starting the jemmet Lean 4 HTTP server.**
Companion to `README.md`, `design-notes.md`, and `prototype/` in this
directory.

- **iotakt version at handoff:** v0.13.0-dev (a **v1.0 candidate** — see §6).
- **Henret dependency:** v0.15.2.
- **Toolchain:** Lean 4.15.0 (`leanprover/lean4:v4.15.0`), `lake`.
- **Native:** raw C shim over Linux `epoll` + POSIX sockets.

---

## 0. Are we ready to start jemmet?

**Yes.** iotakt provides a complete, tested, stable I/O-boundary surface that
a server can build on without touching fds, epoll, or the C FFI. Everything
jemmet needs to read framed HTTP requests, write responses, manage connection
lifecycle, and shut down cleanly is in place and exercised by a 26-step CI
gate. The reference server in iotakt (`examples/ReferenceServer.lean`) already
demonstrates a working keep-alive HTTP/1.1 service on this surface.

**One caveat, stated plainly:** iotakt's v1.0 is *not yet cut* — it awaits
maintainer sign-off. jemmet therefore starts against the **v1.0-candidate**
surface. That surface is effectively frozen: the remaining iotakt work
(kqueue, `recvInto`) is **additive only** and cannot break what jemmet builds
on. So it is safe to start now; pin jemmet to the iotakt tag you build
against and bump when v1.0 lands.

---

## 1. What iotakt is

iotakt is a **small, auditable, non-blocking I/O readiness and socket-lifecycle
library** for Lean 4, sitting between a native Linux backend and the Henret
actor/scheduler runtime. It exists to keep OS socket semantics out of both
Henret (which stays a pure runtime model) and jemmet (which stays an HTTP
server). The stack:

```
┌─────────────────────────────────────────────┐
│ jemmet — HTTP server (THIS is what you build)│
│   routing, handlers, keep-alive policy,      │
│   serve loop, response generation, TLS policy│
├─────────────────────────────────────────────┤
│ iotakt — I/O & socket boundary (done)        │
│   fd lifecycle, readiness, body framing,     │
│   OS→actor translation, the handoff surface  │
├─────────────────────────────────────────────┤
│ henret — actor/scheduler runtime (upstream)  │
│   tasks, mailboxes, timers, supervision      │
└─────────────────────────────────────────────┘
```

### Design pillars (these are also iotakt's guarantees to you)

- **`FdKey(raw, generation)`, never a bare fd.** A raw fd can be closed and
  reused by the OS; iotakt assigns each logical connection a generation so a
  stale event for a reused fd cannot be delivered to the wrong connection.
  You always hold an `FdKey`, never a raw int.
- **Readiness is a hint.** `dataReady … .readable` means a read *may* make
  progress, not that bytes are waiting. Always handle `wouldBlock`.
- **Pure model, proven.** 77 machine-checked theorems (0 `sorry`, 0 `axiom`)
  cover registry uniqueness, stale/unknown-event rejection, interest
  soundness, coalescing bounds, and lifecycle terminality.
- **No C-side application buffering.** Bytes are Lean-owned. `recv` allocates
  one Lean `ByteArray` per call (Option A); `send` reads a read-only
  `ByteArray`. There are no native ring buffers or retained Lean pointers.
- **Single-threaded deterministic driver.** No background native threads; the
  driver loop is a pure outer loop you step. This is what makes behavior
  reproducible against the fake poller.
- **Coalescing prevents mailbox floods.** At most one pending readiness per
  `FdKey + kind`, cleared by **explicit acknowledgement** (see §3.4).

---

## 2. Implementation status

| Capability | Status |
|------------|--------|
| Pure model + proofs (registry, lifecycle, translation, coalescing) | Done, proven |
| Linux `epoll` backend (level-triggered) | Done, tested |
| Non-blocking TCP listen / accept / recv / send / close | Done, tested |
| Outbound non-blocking `connect` (EINPROGRESS) | Done, tested (RFC 039) |
| UDP datagrams | Done, tested (RFC 036) |
| `FdKey` generation + stale-event rejection | Done, proven + tested |
| FFI ownership hardening (one `lean_dec` per path; recvfrom double-free avoided) | Done (RFC 028) |
| HTTP/1.0 + HTTP/1.1 request parsing, response building | Done (building block) |
| Body framing: Content-Length + chunked (RFC 7230) | Done, tested |
| `readFull` / `readFromBuffer` (pipelining-correct keep-alive reads) | Done, tested |
| Request-size limits (`ReadResult.tooLarge`) | Done, tested |
| WriteBuffer (partial-write adapter) | Done, tested |
| Connection-actor lifecycle, scheduled actors, failure/restart (Henret RFC 049) | Done, tested |
| Adaptive poll timeout + idle-connection reaping | Done, tested |
| Graceful shutdown (drain + listener stop) | Done, tested (RFC 037) |
| Connection limits / load shedding | Done, tested (RFC 030) |
| Throughput benchmark (~250–400k req/s, socketpair) | Done (RFC 025) |
| Deterministic fake poller (for your tests too) | Done |

---

## 3. The handoff surface — what jemmet imports

**`import Iotakt.Server`** brings the I/O + framing primitives and the
consolidated abbrevs. (Routing is intentionally *not* here — see §5.)

### 3.1 Connection lifecycle — `Iotakt.Loop.EventLoop`

```lean
EventLoop.create (config : DriverConfig := {})        : IO (Option EventLoop)
EventLoop.addListener (loop) (port : UInt16)          : IO (EventLoop × Bool)
EventLoop.runStepAuto (loop)                          : IO (EventLoop × List LoopEvent)
EventLoop.runStep (loop) (timeoutMs : Int := -1)      : IO (EventLoop × List LoopEvent)
EventLoop.closeConnection (loop) (key : FdKey)        : IO EventLoop
EventLoop.connectTo (loop) (addr : UInt32) (port)     : IO (EventLoop × ConnectOutcome)
EventLoop.enableWrite / disableWrite (loop) (key)     : IO EventLoop
EventLoop.shutdown (loop)                             : IO EventLoop      -- drain + stop
EventLoop.destroy (loop)                              : IO Unit          -- close poller
```

Resource controls (config-as-builder):

```lean
EventLoop.withIdleTimeout (loop) (ms : Nat)           : EventLoop
EventLoop.withMaxConnections (loop) (n : Nat)         : EventLoop
EventLoop.connectionCount (loop)                      : Nat
EventLoop.atCapacity (loop)                           : Bool
```

`DriverConfig` (defaults shown): `maxEventsPerPoll := 1024`,
`maxReadBytes := 16384`, `maxAcceptBurst := 64`.

### 3.2 The event stream — `LoopEvent`

`runStepAuto` returns the events produced by one driver step:

```lean
inductive LoopEvent
  | newConnection (key : FdKey) (rawFd : Int)   -- a client connected (cap-shed accepts are NOT surfaced)
  | dataReady     (key : FdKey) (event : IoEvent)  -- .readable / .writable / .eof / .hangup / .error
  | tick          (now : Nat)                   -- a logical timer fired
```

`runStepAuto` also handles the adaptive poll timeout (idle = block; pending
work = 0 ms) and idle-connection reaping for you.

### 3.3 Reading requests — `Iotakt.RequestBody`

```lean
readRequest         := readFull       fd (maxBytes := 65536) (maxPolls := 50)  : IO ReadResult
readRequestBuffered := readFromBuffer fd (initial : ByteArray) maxBytes maxPolls
                                                       : IO (ReadResult × ByteArray)

inductive ReadResult
  | request (req : HttpRequest)   -- headers + framed body, parsed
  | incomplete                    -- peer closed mid-request
  | tooLarge                      -- exceeded maxBytes → map to 413
  | error (e : IoErrno)
```

**Use `readRequestBuffered` for keep-alive.** It parses one request starting
from the leftover bytes of the previous one and returns the next request's
bytes, so pipelined requests on one connection are not dropped. Feed the
leftover into the next call. `findHeaderEnd` is available if you frame
manually. Body framing is exposed as `bodyFramingOf : HttpRequest → BodyFraming`
(`none` / `contentLength n` / `chunked`).

### 3.4 Coalescing & acknowledgement (important contract)

iotakt suppresses duplicate readiness (at most one pending per `FdKey + kind`).
The pending slot clears **only on explicit acknowledgement** — there is no
implicit clear-on-recv. After you act on a `dataReady`, acknowledge it:

```lean
EventLoop.recvAck (loop) (key) (maxBytes)              : IO (EventLoop × ReadResult)   -- recv + ack readable
EventLoop.sendAck (loop) (key) (ba) (offset len)       : IO (EventLoop × WriteResult)  -- send + ack writable
EventLoop.ackReady (loop) (key) (ev : IoEvent)         : EventLoop                     -- ack only
```

Prefer `recvAck`/`sendAck` — they do the I/O and the ack together so you can't
forget. Forgetting to ack means the next readiness for that fd is silently
coalesced away.

### 3.5 Messages — `Iotakt.Http`

```lean
structure HttpRequest  where method path version : String; headers : List (String×String); body : ByteArray
structure HttpResponse where statusCode : Nat; statusText : String; headers : List (String×String); body : ByteArray

HttpRequest.parse (raw) : Option HttpRequest      -- if you frame yourself
HttpRequest.keepAlive (req) : Bool                -- HTTP/1.1 default + Connection header
HttpResponse.ok / notFound / okKeepAlive / okClose
HttpResponse.toBytes (r) : ByteArray              -- NOTE: emits "HTTP/1.0" status line today (see §5 limits)
```

### 3.6 Chunked transfer-encoding & WriteBuffer

```lean
encodeChunk (bytes) ; chunkedTerminator ; chunkedResponseHeader ; decodeChunked ; isChunked   -- Iotakt.Server abbrevs
WriteBuffer  -- partial-write adapter: hold unsent suffix, drain on writable
```

---

## 4. Worked shape (from the reference server)

The minimal serve loop a consumer writes (this lives in *your* code, not
iotakt):

```lean
-- accept → serve (keep-alive) → close
for _ in ...:
  let (loop, events) ← loop.runStepAuto
  for ev in events do
    match ev with
    | .newConnection key _ =>
        -- serveConnection: readRequestBuffered → dispatch → respond, carrying leftover
        loop ← loop.closeConnection key
    | _ => pure ()
```

A complete, runnable version is in `prototype/Jemmet.lean` +
`prototype/JemmetDemo.lean` here, and in iotakt's
`examples/ReferenceServer.lean`. Both serve `/users/:id` (JSON-ish),
`/echo` (POST body), and keep-alive `/a`,`/b` → `AB` on one connection.

---

## 5. Limits & gotchas (read before you design)

These are real boundaries of the current iotakt. Some are deliberate
non-goals; some are "not yet"; some are Lean-4 sharp edges.

**Deliberate non-goals (jemmet's job, do not push into iotakt):**
- No routing, handler framework, or middleware. (`Iotakt.Router` exists as an
  *optional, non-stable* convenience — fine for a quick start, but jemmet
  should own real dispatch and likely replace it.)
- No serve loop or keep-alive *policy* — only the reading primitives.
- No TLS. iotakt documents the boundary in RFC 041; jemmet (or a TLS library
  below it) owns the handshake. iotakt deals in plaintext bytes.
- No DNS, no application-level backpressure, no protocol state machines.

**Current implementation limits (may lift later, plan around them):**
- **Linux only** for the native backend (epoll). The model is kqueue-aware
  and RFC 021 plans a macOS/BSD backend, but it is not built yet (blocked on a
  macOS CI runner). jemmet's logic is platform-neutral; only deployment is
  Linux-bound today.
- **Level-triggered epoll**, single-threaded driver. No edge-triggered mode,
  no multi-threaded polling in v0.x. Fine for correctness; if you need many
  cores, that is a future iotakt concern (multi-driver), not a jemmet hack.
- **`HttpResponse.toBytes` emits an `HTTP/1.0` status line.** This is a known
  rough edge in the response builder — keep-alive still works because the
  `Connection` header is set explicitly, but if jemmet wants a proper
  `HTTP/1.1` status line it should build response bytes itself (or send a
  small patch upstream to iotakt — this is arguably an iotakt bug, not a
  jemmet feature).
- **`recv` allocates per call (Option A).** No reusable-buffer API yet
  (`recvInto`, RFC 022, deferred). Throughput is ~250–400k req/s on a
  socketpair; if jemmet needs more, that optimization belongs in iotakt.
- **The driver loop in examples is bounded by iteration count** for
  testability. A real jemmet loops until a shutdown signal and calls
  `EventLoop.shutdown` then `destroy`.

**Lean 4 / FFI gotchas you will hit (iotakt learned these the hard way):**
- `ByteArray` has no `BEq` — compare via `.toList ==` or `String.fromUTF8?`.
- `String.containsSubstr`/`isInfixOf` don't exist — use `.splitOn d |>.length > 1`.
- `USize` literals can't appear in match arms — use `n == 4`.
- Multi-line record-update `{ s with a := …, b := … }` with `++`/lambdas can
  fail to parse — extract to `let` bindings first.
- `deriving Repr` fails if any field type lacks `Repr` (e.g. `HttpRequest`
  derives only `Inhabited`).
- There is no `IO.monoNanoseconds`; iotakt provides `Io.monoNs` via a C
  `clock_gettime` wrapper if you need monotonic time.

**Henret integration notes (already mitigated in iotakt, FYI):**
- `inject` returns `.invalid` if the owner mailbox is absent; iotakt always
  `spawn`s first (which creates the mailbox) and proves the guarded inject
  returns `.ok`. If jemmet talks to Henret directly, follow the same rule.
- These discrepancies were verified to hold from Henret v0.6.0 → v0.15.2.

---

## 6. Direction for jemmet

### 6.1 Scope (mirror iotakt's discipline)

jemmet **is** an HTTP/1.1 server: routing, handlers, request/response
lifecycle, keep-alive policy, status-code mapping, content negotiation,
optional TLS policy, and the serve loop. jemmet **is not** an I/O library — it
never touches an fd, epoll, or the C FFI directly; everything goes through
`Iotakt.Server`. If you find yourself wanting to change iotakt to make a jemmet
feature easier, first ask whether the feature is actually jemmet's.

The same honesty discipline iotakt follows applies: keep a clear non-goals
list, and a proof/trust/test posture (jemmet will be mostly TESTED, with maybe
a proven core for routing/parsing invariants).

### 6.2 Suggested architecture

```
Jemmet/
  Server.lean       -- the serve loop (accept → serveConnection → close), shutdown wiring
  Router.lean       -- real routing (method + path + params); replace iotakt's convenience one
  Handler.lean      -- handler type, context, response helpers
  Middleware.lean   -- composable request/response transforms (logging, auth, etc.)
  Response.lean     -- proper HTTP/1.1 response building (fix the 1.0 status line)
  Streaming.lean    -- chunked response bodies built on Iotakt.Server.encodeChunk
  Config.lean       -- ports, limits, timeouts (wrap iotakt's withMaxConnections/withIdleTimeout)
Jemmet/Examples/    -- demo services
Jemmet/Proofs/      -- routing/parsing invariants, if worth proving
docs/, rfcs/        -- same RFC-lifecycle policy as iotakt (RFC 000)
```

Depend on iotakt by `lake` require (path or git tag). Pin the iotakt version.

### 6.3 First milestones

1. **Bootstrap.** New `lake` project; require iotakt; copy
   `prototype/Jemmet.lean` + `prototype/JemmetDemo.lean` from this directory;
   get the demo serving `/users/:id` and keep-alive `/a`/`/b`. (This is a
   known-good starting point — it ran live in iotakt.)
2. **Real router.** Replace iotakt's convenience `Router` with jemmet's own:
   typed handlers, route groups, params, method dispatch, 404/405.
3. **Proper responses.** Build correct `HTTP/1.1` responses (status line,
   `Date`, `Server`, `Content-Length`/chunked). Decide whether to send the
   `toBytes` `HTTP/1.0` fix upstream to iotakt.
4. **Production serve loop.** Replace the bounded iteration loop with a
   shutdown-signal loop calling `EventLoop.shutdown` + `destroy`. Wire
   `withMaxConnections` and `withIdleTimeout` from config.
5. **Streaming responses.** Handlers that return a chunked body for
   large/generated output, using `Iotakt.Server.encodeChunk`.
6. **Middleware + errors.** Logging, error handling, request size → 413
   mapping (iotakt already gives you `ReadResult.tooLarge`).
7. **TLS boundary.** Per iotakt RFC 041, layer TLS termination; iotakt stays
   plaintext.

### 6.4 Things to watch

- **Always acknowledge readiness** (`recvAck`/`sendAck`), or the next event is
  coalesced away. This is the single most likely correctness bug.
- **Honor `wouldBlock`/partial writes** — use `WriteBuffer` for the unsent
  suffix and toggle write interest (`enableWrite`/`disableWrite`).
- **Hold `FdKey`, not raw fds** — never cache a raw int across a close.
- **Use `readRequestBuffered` for keep-alive**, carrying the leftover buffer;
  `readRequest` is fine for one-shot/close connections.
- **Bound everything** — `withMaxConnections`, per-request `maxBytes`, idle
  timeout. iotakt gives you the controls; jemmet sets the policy.

### 6.5 Upstreaming vs. building locally

If a need is genuinely about the *I/O boundary* (a missing socket option, the
`HTTP/1.0` status-line fix, `recvInto` for throughput, a kqueue backend), it
belongs **upstream in iotakt**. If it is about *serving HTTP* (routing,
handlers, content types, compression, sessions), it belongs **in jemmet**. When
in doubt, the rule is the same one that produced this clean boundary: iotakt
owns *how bytes move*; jemmet owns *what the bytes mean*.

---

## 7. Checklist to start

- [ ] New `lake` project `jemmet`, Lean 4.15.0 toolchain.
- [ ] `require iotakt` (pin the tag you build against; v0.13.0-dev or the v1.0
      tag once cut).
- [ ] Copy `prototype/*.lean`; build against `Iotakt.Server`; run the demo.
- [ ] Stand up the project's RFC dir per iotakt RFC 000.
- [ ] Build the real router + proper HTTP/1.1 responses.
- [ ] Replace the bounded loop with a shutdown-aware serve loop.
- [ ] Keep a non-goals list and a proof/trust/test matrix from day one.
