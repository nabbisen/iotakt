import IotaktRuntime.Loop
import IotaktRuntime.Native

/-!
# RFC 015 three-project TLS standup — iotakt's listener half

iotakt's side of the kroopt + jemmet + iotakt real-socket acceptance harness
(RFC 015 §10). The boundary iotakt owns, and nothing more:

    listener accept → runStepAuto → newConnection (FdKey, rawFd) → consumer seam

For each accepted TCP connection the loop surfaces `newConnection key rawFd`;
the listener hands `(key, rawFd)` to a *consumer seam* and stops there. In the
standup harness the seam is jemmet's `IotaktTransport` adapter (kroopt's `TlsConn`
doing TLS 1.3 inside), which then drives jemmet's HTTP/1.1 `PlainConn`. Here the
seam is a logger, so iotakt's half builds and runs standalone — depending only on
`iotakt-runtime`, never on kroopt or jemmet.

Dependency direction: library deps point downward. This example depends only on
`iotakt-runtime`; only the assembled harness target
`runtime/examples/kroopt-jemmet-tls-standup/` reaches up to kroopt + jemmet, and
that target is wired at standup time (see its README).

Driver note: the production harness drives the loop with `runStepAuto` (the
adaptive park/wake step, which blocks until the next deadline). This example
uses the bounded `runStep timeoutMs` loop that the other `runtime/examples` use
for testability, so it terminates cleanly without a client.

Run it:
  ```
  lake build iotakt-standup-listener
  .lake/build/bin/iotakt-standup-listener &
  printf '' | nc 127.0.0.1 49915        # each connect prints a [handoff] line
  ```
-/

open IotaktRuntime.Loop IotaktRuntime.Native Iotakt.Model

/-- The fd-handoff seam. The harness swaps `onNewConnection` for jemmet's
`IotaktTransport` attach (kroopt's `TlsConn` inside); standalone it records the
handoff. A real consumer takes ownership of `(key, rawFd)` and drives
`recvAck`/`sendAck` keyed on the generation-protected `FdKey`. -/
structure ConsumerSeam where
  onNewConnection : FdKey → Int → IO Unit

/-- Default standalone seam: log each handoff so the listener half is runnable
and observable on its own — no TLS, no HTTP. -/
def loggingSeam : ConsumerSeam where
  onNewConnection := fun key rawFd =>
    IO.println s!"  [handoff] fd={rawFd} key={key.raw}/{key.gen} → consumer (TLS attach point)"

/-- iotakt's half of the standup: accept TCP on `port`, surface each accepted
connection as `newConnection`, and hand `(key, rawFd)` to `seam`. Runs at most
`steps` bounded driver iterations (≈ `steps × timeoutMs` ms). Returns the
number of connections handed off. -/
def runStandupListener (port : UInt16) (seam : ConsumerSeam)
    (steps : Nat := 30) (timeoutMs : Int := 100) : IO Nat := do
  let some loop ← EventLoop.create { maxEventsPerPoll := 64, maxReadBytes := 4096 }
    | do IO.println "epoll_create failed"; return 0
  let (loop1, ok) ← loop.addListener port
  if !ok then do
    IO.println s!"bind/listen failed on :{port} (port in use?)"; loop.destroy; return 0
  let mut loop := loop1
  let mut handed : Nat := 0
  for _ in List.range steps do
    let (loop1, events) ← loop.runStep timeoutMs
    loop := loop1
    for ev in events do
      match ev with
      | .newConnection key rawFd =>
          seam.onNewConnection key rawFd
          handed := handed + 1
          -- iotakt's job ends at handoff: the consumer owns the fd and drives
          -- the byte stream. Standalone we close after handoff so the demo is
          -- self-contained; the harness leaves the fd to the consumer.
          loop := ← EffectError.orThrow (← loop.closeConnection key)
      | .dataReady _ _ => pure ()   -- consumer-owned in the harness
      | .tick _        => pure ()
  loop.destroy
  return handed

def main : IO Unit := do
  let port : UInt16 := 49915
  IO.println "RFC 015 standup — iotakt listener half"
  IO.println s!"Listening on 127.0.0.1:{port} (accepting for ~3s)"
  let handed ← runStandupListener port loggingSeam
  IO.println ""
  IO.println s!"connections handed off: {handed}"
  IO.println "iotakt listener half done"
