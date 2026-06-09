import Iotakt.Http
import Iotakt.WriteBuffer
import Iotakt.Native

/-!
# iotakt throughput benchmark (RFC 025)

Measures HTTP/1.1-style request/response throughput over a Unix socketpair.
Using a socketpair eliminates network latency and epoll scheduling jitter,
giving a clean measurement of iotakt's I/O layer overhead.

For network-realistic benchmarks see `scripts/bench.sh`.

## Results on this machine (v0.5.0-dev)
Reported in the CI log. Baseline documented in `docs/src/benchmark.md`.
-/

open Iotakt.Http Iotakt.Native Iotakt.WriteBuffer

private def benchN    : Nat := 1000   -- requests per run
private def warmupN   : Nat := 50     -- warm-up requests

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

def appendBa (buf : ByteArray) (ba : ByteArray) : ByteArray :=
  let combined := ByteArray.mkEmpty (buf.size + ba.size)
  let combined := ByteArray.copySlice buf 0 combined 0 buf.size
  ByteArray.copySlice ba 0 combined buf.size ba.size

/-- Read exactly `n` bytes from `fd` into a new ByteArray.
Retries on wouldBlock (non-blocking sockets can return EAGAIN even
on a socketpair when the kernel buffer is momentarily empty). -/
def readExact (fd : Int) (n : Nat) : IO Bool := do
  let mut buf := ByteArray.empty
  for _ in List.range 200 do
    if buf.size >= n then break
    match ← Io.recv fd (n - buf.size) with
    | .bytes ba => buf := appendBa buf ba
    | .wouldBlock => IO.sleep 1
    | .eof => return false
    | _ => return false
  return buf.size >= n

/-- One HTTP request/response round-trip over `fd`.
Server side: reads the request, sends the response.
Client side: sends the request, reads the response.
In the socketpair benchmark both sides run in the same thread. -/
def benchRoundTrip (clientFd serverFd : Int) (respSize : Nat) : IO Bool := do
  -- Client sends request
  let req := "GET /bench HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n".toUTF8
  let (_, sent) ← (WriteBuffer.empty.push req).flushAll clientFd
  if !sent then return false

  -- Server reads request (64 bytes exactly)
  let ok1 ← readExact serverFd 64
  if !ok1 then return false

  -- Server sends response
  let resp := (HttpResponse.okKeepAlive "pong").toBytes
  let (_, sent2) ← (WriteBuffer.empty.push resp).flushAll serverFd
  if !sent2 then return false

  -- Client reads response
  readExact clientFd respSize

def main : IO Unit := do
  IO.println "iotakt throughput benchmark (RFC 025)"
  IO.println s!"  N = {benchN} request/response round-trips via Unix socketpair"
  IO.println ""

  let (clientFd, serverFd) ← Socket.socketpairRaw
  check "socketpair created" (clientFd >= 0)
  if clientFd < 0 then return

  -- Measure response size once
  let resp := (HttpResponse.okKeepAlive "pong").toBytes
  let respSize := resp.size

  -- Measure actual request size
  let reqBytes := "GET /bench HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n".toUTF8
  let reqSize := reqBytes.size
  IO.println s!"  Request size:   {reqSize}B"
  IO.println s!"  Response size:  {respSize}B"

  -- Warm-up
  for _ in List.range warmupN do
    let _ ← benchRoundTrip clientFd serverFd respSize

  -- Timed benchmark
  let t0 ← Io.monoNs
  let mut ok := 0
  for _ in List.range benchN do
    if ← benchRoundTrip clientFd serverFd respSize then
      ok := ok + 1
  let t1 ← Io.monoNs

  Socket.closeFdRaw clientFd.toInt32
  Socket.closeFdRaw serverFd.toInt32

  let elapsedNs  := (t1 - t0).toNat
  let elapsedMs  := elapsedNs / 1000000
  let rps : Float :=
    if elapsedNs == 0 then 0.0
    else Float.ofNat ok / (Float.ofNat elapsedNs / 1000000000.0)

  IO.println s!"Requests:       {benchN}"
  IO.println s!"Succeeded:      {ok}"
  IO.println s!"Elapsed:        {elapsedMs}ms"
  IO.println s!"Throughput:     {rps} req/s"
  IO.println ""
  check "all requests succeeded"  (ok == benchN)
  check "elapsed < 30s"           (elapsedMs < 30000)
  check "throughput > 0 req/s"    (rps > (0 : Float))
  IO.println ""
  IO.println "Benchmark complete. See docs/src/benchmark.md for baseline."
