import Iotakt.Model.Fd

/-!
# IotaktRuntime.Stats

Per-connection and global I/O statistics counters (v0.5).

`ConnStats` tracks bytes and events for a single connection.
`GlobalStats` aggregates across all connections over the server lifetime.

Both are plain structures updated by the actor layer; iotakt itself does
not automatically populate them.

## Usage

```lean
let statsRef ← IO.mkRef ConnStats.empty
-- In onReadable:
let bytes ← Unsafe.Io.recv key.raw 4096
statsRef.modify (·.addBytesRead bytes.size)
```
-/

namespace IotaktRuntime.Stats

open Iotakt.Model

/-- Per-connection statistics. -/
structure ConnStats where
  /-- Total bytes received on this connection. -/
  bytesRead    : Nat := 0
  /-- Total bytes sent on this connection. -/
  bytesWritten : Nat := 0
  /-- Number of readable events handled. -/
  readEvents   : Nat := 0
  /-- Number of writable events handled. -/
  writeEvents  : Nat := 0
  /-- Number of times a write was partially completed (wouldBlock). -/
  partialWrites : Nat := 0
  /-- True once the connection has been closed. -/
  closed       : Bool := false
  deriving Repr, Inhabited

namespace ConnStats

def empty : ConnStats := {}

def addBytesRead   (s : ConnStats) (n : Nat) : ConnStats :=
  { s with bytesRead  := s.bytesRead  + n, readEvents  := s.readEvents  + 1 }

def addBytesWritten (s : ConnStats) (n : Nat) : ConnStats :=
  { s with bytesWritten := s.bytesWritten + n, writeEvents := s.writeEvents + 1 }

def addPartialWrite (s : ConnStats) : ConnStats :=
  { s with partialWrites := s.partialWrites + 1 }

def markClosed (s : ConnStats) : ConnStats := { s with closed := true }

/-- One-line summary string for logging. -/
def summary (s : ConnStats) : String :=
  s!"read={s.bytesRead}B write={s.bytesWritten}B readEv={s.readEvents} writeEv={s.writeEvents}"

end ConnStats

/-- Global server-lifetime statistics. -/
structure GlobalStats where
  /-- Total connections ever accepted (not decremented on close). -/
  totalConns       : Nat := 0
  /-- Connections that were fully closed cleanly. -/
  closedConns      : Nat := 0
  /-- Connections that closed with an error. -/
  errorConns       : Nat := 0
  /-- Aggregate bytes received across all connections. -/
  totalBytesRead   : Nat := 0
  /-- Aggregate bytes sent across all connections. -/
  totalBytesWritten : Nat := 0
  /-- Total requests handled (application-level; caller must update). -/
  totalRequests    : Nat := 0
  deriving Repr, Inhabited

namespace GlobalStats

def empty : GlobalStats := {}

def addConn (g : GlobalStats) : GlobalStats :=
  { g with totalConns := g.totalConns + 1 }

def addClosed (g : GlobalStats) (s : ConnStats) : GlobalStats :=
  { g with
    closedConns       := g.closedConns + 1
    totalBytesRead    := g.totalBytesRead    + s.bytesRead
    totalBytesWritten := g.totalBytesWritten + s.bytesWritten }

def addError (g : GlobalStats) : GlobalStats :=
  { g with errorConns := g.errorConns + 1 }

def addRequest (g : GlobalStats) : GlobalStats :=
  { g with totalRequests := g.totalRequests + 1 }

/-- Requests per second given elapsed nanoseconds. -/
def reqPerSec (g : GlobalStats) (elapsedNs : Nat) : Float :=
  if elapsedNs == 0 then 0.0
  else Float.ofNat g.totalRequests / (Float.ofNat elapsedNs / 1000000000.0)

/-- Multi-line summary for benchmark output. -/
def report (g : GlobalStats) (elapsedNs : Nat) : String :=
  let rps := g.reqPerSec elapsedNs
  let elapsedMs := elapsedNs / 1000000
  String.intercalate "\n" [
    s!"Total connections:  {g.totalConns}",
    s!"Closed cleanly:     {g.closedConns}",
    s!"Connection errors:  {g.errorConns}",
    s!"Total requests:     {g.totalRequests}",
    s!"Bytes received:     {g.totalBytesRead}",
    s!"Bytes sent:         {g.totalBytesWritten}",
    s!"Elapsed:            {elapsedMs}ms",
    s!"Throughput:         {rps} req/s"
  ]

end GlobalStats

end IotaktRuntime.Stats
