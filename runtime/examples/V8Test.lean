import IotaktRuntime.Chunked
import IotaktRuntime.SchedConn
import IotaktRuntime.Http
import Henret.Model

/-!
# iotakt v0.8 integration test

* **Chunked transfer encoding** — `toHex`/`fromHex`, `encodeChunk`,
  `encodeBody`, `decode` roundtrip, `isChunked` detection.
* **Scheduled connection actor** — the full Henret-running lifecycle:
  spawn → schedule → parkWithDeadline (`receiveUntil`) → wake by I/O
  (`inject`) or timeout (`tick`) → close (`cancel`).
-/

open IotaktRuntime.Chunked IotaktRuntime.SchedConn IotaktRuntime.Http

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- ─────────────────────────────────────────────────────────────────────────
-- A. Hex helpers
-- ─────────────────────────────────────────────────────────────────────────
def testHex : IO Unit := do
  IO.println "=== A. Hex chunk sizes ==="
  check "toHex 0 = 0"      (toHex 0 == "0")
  check "toHex 7 = 7"      (toHex 7 == "7")
  check "toHex 16 = 10"    (toHex 16 == "10")
  check "toHex 255 = ff"   (toHex 255 == "ff")
  check "toHex 4096 = 1000" (toHex 4096 == "1000")
  check "fromHex 0"        (fromHex "0" == some 0)
  check "fromHex ff"       (fromHex "ff" == some 255)
  check "fromHex 1000"     (fromHex "1000" == some 4096)
  check "fromHex with extension '5;foo=bar'" (fromHex "5;foo=bar" == some 5)
  check "fromHex uppercase FF" (fromHex "FF" == some 255)
  check "fromHex invalid → none" (fromHex "xyz" == none)
  -- roundtrip
  check "roundtrip toHex/fromHex 12345" (fromHex (toHex 12345) == some 12345)

-- ─────────────────────────────────────────────────────────────────────────
-- B. Chunk encoding
-- ─────────────────────────────────────────────────────────────────────────
def testEncode : IO Unit := do
  IO.println ""
  IO.println "=== B. Chunk encoding ==="

  let chunk := encodeChunk "Hello".toUTF8
  let chunkStr := String.fromUTF8? chunk |>.getD ""
  check "encodeChunk 'Hello' = '5\\r\\nHello\\r\\n'" (chunkStr == "5\r\nHello\r\n")

  let empty := encodeChunk "".toUTF8
  check "encodeChunk '' = '0\\r\\n\\r\\n'" ((String.fromUTF8? empty |>.getD "") == "0\r\n\r\n")

  let term := terminator
  check "terminator = '0\\r\\n\\r\\n'" ((String.fromUTF8? term |>.getD "") == "0\r\n\r\n")

  let body := encodeBody "Hi".toUTF8
  check "encodeBody 'Hi' = '2\\r\\nHi\\r\\n0\\r\\n\\r\\n'"
    ((String.fromUTF8? body |>.getD "") == "2\r\nHi\r\n0\r\n\r\n")

  let emptyBody := encodeBody "".toUTF8
  check "encodeBody '' = terminator only"
    ((String.fromUTF8? emptyBody |>.getD "") == "0\r\n\r\n")

-- ─────────────────────────────────────────────────────────────────────────
-- C. Chunk decoding (roundtrip)
-- ─────────────────────────────────────────────────────────────────────────
def testDecode : IO Unit := do
  IO.println ""
  IO.println "=== C. Chunk decoding ==="

  -- Single chunk roundtrip
  let body1 := encodeBody "Hello, world!".toUTF8
  match decode body1 with
  | some d => check "decode(encodeBody 'Hello, world!') = 'Hello, world!'"
                ((String.fromUTF8? d |>.getD "") == "Hello, world!")
  | none   => check "decode single chunk" false

  -- Multi-chunk: manually assemble three chunks + terminator
  let multi :=
    let c (s : String) := encodeChunk s.toUTF8
    let cat (a b : ByteArray) :=
      let x := ByteArray.mkEmpty (a.size + b.size)
      ByteArray.copySlice b 0 (ByteArray.copySlice a 0 x 0 a.size) a.size b.size
    cat (cat (cat (c "Hello, ") (c "chunked ")) (c "world!")) terminator
  match decode multi with
  | some d => check "decode 3-chunk stream = 'Hello, chunked world!'"
                ((String.fromUTF8? d |>.getD "") == "Hello, chunked world!")
  | none   => check "decode multi-chunk" false

  -- Empty body
  match decode terminator with
  | some d => check "decode(terminator) = empty" (d.isEmpty)
  | none   => check "decode terminator" false

  -- Malformed: bad hex size
  check "decode malformed (no terminator) → none"
    ((decode "zz\r\ndata\r\n".toUTF8).isNone)

-- ─────────────────────────────────────────────────────────────────────────
-- D. isChunked detection
-- ─────────────────────────────────────────────────────────────────────────
def testIsChunked : IO Unit := do
  IO.println ""
  IO.println "=== D. isChunked detection ==="

  let chunkedResp := responseHeader 200 "OK" "text/plain"
  check "isChunked on chunked response = true" (isChunked chunkedResp)

  let plainResp := (HttpResponse.ok "hi").toBytes
  check "isChunked on Content-Length response = false" (!isChunked plainResp)

  -- Case-insensitive header name
  check "isChunked case-insensitive"
    (isChunked "HTTP/1.1 200 OK\r\nTRANSFER-ENCODING: chunked\r\n\r\n".toUTF8)

-- ─────────────────────────────────────────────────────────────────────────
-- E. Scheduled connection actor lifecycle (over real Henret)
-- ─────────────────────────────────────────────────────────────────────────
def testSchedConn : IO Unit := do
  IO.println ""
  IO.println "=== E. Scheduled connection actor lifecycle ==="

  let rt0 := Henret.RuntimeState.init

  -- 1. spawn
  let (rt1, conn) := spawn rt0 7
  check "spawned actor: phase = .spawned" (phaseOf rt1 conn.task == .spawned)
  check "spawn allocated a task id" (conn.task == 0)
  check "spawn recorded actor = 7" (conn.actor == 7)

  -- 2. schedule → running
  let rt2 := schedule rt1
  check "after schedule: phase = .running" (phaseOf rt2 conn.task == .running)

  -- 3. parkWithDeadline → parkedTimed
  let (rt3, conn3, parkRes) := parkWithDeadline rt2 conn 100
  check "park returns .blocked" (match parkRes with | .blocked => true | _ => false)
  check "after park: phase = .parkedTimed" (phaseOf rt3 conn.task == .parkedTimed)
  check "park recorded deadline = 100" (conn3.deadline == some 100)
  check "park registered a timer" (rt3.timers.any (·.task == conn.task))

  -- 4a. wake by I/O (inject) → ready
  let rtIo := wakeOnIo rt3 conn3 { id := 5, payload := 1 }
  check "wakeOnIo: phase = .ready" (phaseOf rtIo conn.task == .ready)
  check "wakeOnIo cleared the timer" (!rtIo.timers.any (·.task == conn.task))

  -- 4b. (alternate) wake by timeout (tick) from the parked state → ready
  let rtTo := tick rt3 100
  check "wakeOnTimeout (tick): phase = .ready" (phaseOf rtTo conn.task == .ready)
  check "tick woke the timed waiter" (!rtTo.timers.any (·.task == conn.task))

  -- 5. close (cancel) → closed
  let rtClosed := close rtIo conn3
  check "close: phase = .closed" (phaseOf rtClosed conn.task == .closed)

  -- Full lifecycle is internally consistent: the I/O-woken and timeout-woken
  -- runtimes both reach .ready, demonstrating either event resumes the actor.
  check "both wake paths reach .ready"
    (phaseOf rtIo conn.task == ConnPhase.ready && phaseOf rtTo conn.task == ConnPhase.ready)

  -- 6. failure + supervised restart (henret ≥ v0.15.0, RFC 049)
  -- A running supervisor spawns a child connection, the child fails, and the
  -- supervisor restarts it into a fresh task.
  let rtSup0 := Henret.RuntimeState.init
  let rtSup1 := Henret.run rtSup0 [.spawn 100, .schedule]   -- supervisor task 0 running
  let supTask := 0
  let (rtSup2, childRes) := Henret.step rtSup1 (.spawnChild supTask 101)
  let childTask := match childRes with | .spawned t => t | _ => 0
  let child : SchedConn := { actor := 101, task := childTask }
  check "supervised child spawned (running phase after schedule? new here)"
    (phaseOf rtSup2 childTask == .spawned || phaseOf rtSup2 childTask == .ready)

  let rtFailed := fail rtSup2 child
  check "fail: child phase = .failed (distinct from closed)"
    (phaseOf rtFailed childTask == .failed)
  check "failed is not closed" (phaseOf rtFailed childTask != .closed)

  let (rtRestarted, newChild) := restart rtFailed supTask child 101
  check "restart: fresh task id allocated (new > old)" (newChild.task > child.task)
  check "restart: replacement is live (not failed/closed)"
    (phaseOf rtRestarted newChild.task != .failed
      && phaseOf rtRestarted newChild.task != .closed)
  check "restart: provenance recorded (restartOf new = some old)"
    (rtRestarted.restartOf newChild.task == some child.task)

-- ─────────────────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────────────────
def main : IO Unit := do
  IO.println "iotakt v0.8 integration test (chunked encoding + scheduled actors)"
  IO.println ""
  testHex
  testEncode
  testDecode
  testIsChunked
  testSchedConn
  IO.println ""
  IO.println "v0.8 integration test complete"
