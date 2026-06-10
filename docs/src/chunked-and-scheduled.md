# Chunked Transfer Encoding & Scheduled Connection Actors

**iotakt — v0.8 design notes**

Two additions in v0.8: HTTP/1.1 chunked transfer encoding (a concrete wire
feature) and the scheduled connection-actor lifecycle model (the formal
specification deferred from v0.7).

---

## 1. Chunked transfer encoding (`Iotakt.Chunked`)

Chunked encoding (RFC 7230 §4.1) lets a server send a response whose total
length is unknown up front. The body is a series of size-prefixed chunks,
terminated by a zero-length chunk. This is what henejt needs for streaming
handlers: large files, generated content, server-sent events.

### Wire format

```text
7\r\nHello, \r\n8\r\nchunked \r\n7\r\nworld!\n\r\n0\r\n\r\n
```

Each chunk is `<hex-size>\r\n<data>\r\n`; the stream ends with `0\r\n\r\n`.

### API

| Function | Purpose |
|----------|---------|
| `toHex` / `fromHex` | hex chunk sizes; `fromHex` ignores chunk extensions after `;` |
| `encodeChunk data` | one frame: `<hex>\r\n<data>\r\n` |
| `terminator` | the final `0\r\n\r\n` |
| `encodeBody data` | one chunk + terminator (non-streaming convenience) |
| `responseHeader` | chunked response header (no Content-Length) |
| `decode body` | parse a complete chunked body back to bytes |
| `isChunked raw` | detect `Transfer-Encoding: chunked` (case-insensitive) |

### Streaming pattern

A handler streams by sending the header, then `encodeChunk` per piece, then
`terminator`:

```lean
let _ ← Io.send fd (Chunked.responseHeader 200 "OK") 0 _
for piece in pieces do
  let frame := Chunked.encodeChunk piece
  let _ ← Io.send fd frame 0 frame.size
let _ ← Io.send fd Chunked.terminator 0 _
```

`iotakt-streaming-server` demonstrates this; `curl` decodes the result to
the concatenated payload, confirming RFC compliance.

---

## 2. Scheduled connection actors (`Iotakt.SchedConn`)

This is the model that closes the gap noted in v0.7. It makes a connection
actor a *genuine Henret-running task* that parks on its mailbox with a
deadline via `receiveUntil`, rather than the passive mailbox target the
live driver injects into.

### Lifecycle

```text
  spawn ──▶ spawned ──schedule──▶ running ──receiveUntil(d)──▶ parkedTimed
                                     ▲                              │
                                     │                    inject(I/O)│  tick≥d
                                     └──────schedule◀────ready◀──────┘
  running ──cancel──▶ closed
```

`phaseOf` reads the phase from a task's Henret state:

| Henret `taskState` | `ConnPhase` |
|--------------------|-------------|
| `.new` | `spawned` |
| `.running` | `running` |
| `.waitingTimed` | `parkedTimed` |
| `.ready` | `ready` |
| `.cancelled` | `closed` |

### Operations (all over real Henret `step`)

| `SchedConn` op | Henret op | Effect |
|----------------|-----------|--------|
| `spawn` | `spawn a` | create task + mailbox, phase `spawned` |
| `schedule` | `schedule` | phase `running` |
| `parkWithDeadline d` | `receiveUntil t d` | phase `parkedTimed`, timer registered, `.blocked` |
| `wakeOnIo msg` | `inject a msg` | phase `ready`, timer cleared |
| `tick now` | `tick now` | timeout path: phase `ready` when deadline expired |
| `close` | `cancel t` | phase `closed` |

The v0.8 test exercises the entire lifecycle and confirms both wake paths
(I/O and timeout) resume the actor.

### Why this is a model, not the live driver

iotakt keeps two views of every mechanism, consistent with its philosophy:

- **The model** (`SchedConn`) shows the full scheduled lifecycle, verified
  against Henret's actual semantics. It is the specification a future
  scheduled driver — or henejt — would implement, and it unifies the
  logical and wall-clock clocks (Henret `now`/timers as the single source).
- **The native driver** (`Iotakt.Loop`) keeps the optimized single-outer-loop
  path: the driver does the syscalls and injects readiness, without
  scheduling each connection actor per event. For a single-threaded epoll
  loop, per-connection scheduling would cost more than it saves.

When henejt or a multi-worker driver needs genuine per-connection
scheduling, `SchedConn` is the proven contract it builds on.
