import Iotakt.Loop
import Iotakt.Native
import Henret.Model

/-!
# iotakt v0.7 integration test

Tests the v0.7 additions:

* **Adaptive poll timeout** — `pollTimeoutMs` returns -1 (block forever) when
  nothing is pending, and a bounded value when an idle timeout is configured.
* **Idle connection reaping** — `idleExpired` / `reapIdle` close connections
  whose wall-clock idle deadline has passed.
* **Henret receiveUntil timer infrastructure** — verifies that issuing
  `receiveUntil` populates `rt.timers` and that `tick` wakes the timed waiter,
  proving the model side is ready for a future park/wake driver (henret v0.11+).
-/

open Iotakt.Loop Iotakt.Native Iotakt.Model

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- ─────────────────────────────────────────────────────────────────────────
-- A. Adaptive poll timeout
-- ─────────────────────────────────────────────────────────────────────────
def testPollTimeout : IO Unit := do
  IO.println "=== A. Adaptive poll timeout ==="

  let some loop ← EventLoop.create | do IO.println "epoll failed"; return

  -- No idle timeout configured → block indefinitely (-1)
  check "no idle timeout → pollTimeoutMs = -1 (block forever)"
    (loop.pollTimeoutMs 1000000000 == -1)

  -- Idle timeout configured but no connections → still -1
  let loop1 := loop.withIdleTimeout 5000
  check "idle timeout set, no connections → -1"
    (loop1.pollTimeoutMs 1000000000 == -1)

  -- One active connection, just touched → timeout ≈ idle window
  let key : FdKey := { raw := 50, gen := 1 }
  let nowNs := 1000000000  -- 1.0s in ns
  let loop2 := loop1.touchConn key nowNs
  let t := loop2.pollTimeoutMs nowNs
  -- idle window is 5000ms; should be close to 5000 (allow rounding)
  check "active connection → pollTimeoutMs ≈ 5000ms"
    (t >= 4990 && t <= 5000)

  -- Connection already past its deadline → 0 (reap immediately)
  let pastNs := nowNs + 6000 * 1000000  -- 6s later, > 5s window
  check "past-deadline connection → pollTimeoutMs = 0"
    (loop2.pollTimeoutMs pastNs == 0)

  loop.destroy

-- ─────────────────────────────────────────────────────────────────────────
-- B. Idle expiry detection
-- ─────────────────────────────────────────────────────────────────────────
def testIdleExpiry : IO Unit := do
  IO.println ""
  IO.println "=== B. Idle expiry detection ==="

  let some loop ← EventLoop.create | do IO.println "epoll failed"; return
  let loop1 := loop.withIdleTimeout 1000  -- 1s

  let keyOld : FdKey := { raw := 60, gen := 1 }
  let keyNew : FdKey := { raw := 61, gen := 1 }

  let base := 10000000000  -- 10s in ns
  -- keyOld touched at base; keyNew touched 1.5s later
  let loop2 := (loop1.touchConn keyOld base).touchConn keyNew (base + 1500 * 1000000)

  -- At base + 1.2s: keyOld (idle 1.2s > 1s) expired, keyNew not yet (active)
  let checkTime := base + 1200 * 1000000
  let expired := loop2.idleExpired checkTime
  check "keyOld (idle 1.2s) is expired" (expired.contains keyOld)
  check "keyNew (just touched) is not expired" (!expired.contains keyNew)
  check "exactly one connection expired" (expired.length == 1)

  -- With no idle timeout, nothing ever expires
  let loop3 := { loop2 with idleTimeoutMs := none }
  check "no idle timeout → nothing expires" (loop3.idleExpired checkTime |>.isEmpty)

  loop.destroy

-- ─────────────────────────────────────────────────────────────────────────
-- C. reapIdle over real connections (socketpair-backed)
-- ─────────────────────────────────────────────────────────────────────────
def testReapIdle : IO Unit := do
  IO.println ""
  IO.println "=== C. reapIdle ==="

  let some loop ← EventLoop.create | do IO.println "epoll failed"; return
  let (loop1, ok) ← loop.addListener 49994
  check "listener for reap test" ok
  if !ok then do loop.destroy; return

  let loop2 := loop1.withIdleTimeout 100  -- 100ms idle

  -- Manually register a couple of connection activity records with old timestamps
  let key1 : FdKey := { raw := 70, gen := 1 }
  let key2 : FdKey := { raw := 71, gen := 1 }
  let oldNs := 1000000000          -- 1.0s
  let loop3 := (loop2.touchConn key1 oldNs).touchConn key2 oldNs

  -- "now" is 1.0s + 500ms — both are idle past 100ms
  let nowNs := oldNs + 500 * 1000000
  let (loop4, reaped) ← loop3.reapIdle nowNs
  check "reapIdle closed both idle connections" (reaped.length == 2)
  check "lastActivityNs cleared after reap" loop4.lastActivityNs.isEmpty

  loop.destroy

-- ─────────────────────────────────────────────────────────────────────────
-- D. Henret receiveUntil timer infrastructure (model readiness)
-- ─────────────────────────────────────────────────────────────────────────
def testReceiveUntilInfra : IO Unit := do
  IO.println ""
  IO.println "=== D. Henret receiveUntil timer infrastructure ==="

  -- Spawn a task, schedule it (so it is running), then receiveUntil with a
  -- future deadline. The task should park as .waitingTimed and a timer entry
  -- should appear in rt.timers.
  let rt0 := Henret.RuntimeState.init
  let rt1 := Henret.run rt0 [.spawn 0, .schedule]
  -- task 0 is now running
  check "task 0 is running after schedule" (rt1.running == some 0)

  let (rt2, ruRes) := Henret.step rt1 (.receiveUntil 0 100)  -- deadline = 100
  check "receiveUntil on empty mailbox parks (.blocked, not .invalid)"
    (match ruRes with | .blocked => true | _ => false)
  check "task 0 parked as .waitingTimed"
    (rt2.taskState 0 == some .waitingTimed)
  check "timer entry registered in rt.timers"
    (rt2.timers.any (·.task == 0))
  check "waitDeadline recorded = 100"
    (rt2.waitDeadline 0 == some 100)

  -- The nearest deadline (what an adaptive driver would poll on) is 100
  let nextDl := rt2.timers.head?.map (·.deadline)
  check "nearest timer deadline = 100" (nextDl == some 100)

  -- tick past the deadline wakes the timed waiter
  let (rt3, tickRes) := Henret.step rt2 (.tick 100)
  check "tick at deadline wakes the timed waiter"
    (match tickRes with | .woke ts => ts.contains 0 | _ => false)
  check "woken task is back to .ready"
    (rt3.taskState 0 == some .ready)
  check "timer cleared after wake" (!rt3.timers.any (·.task == 0))
  check "waitDeadline cleared after wake" (rt3.waitDeadline 0 == none)

-- ─────────────────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────────────────
def main : IO Unit := do
  IO.println "iotakt v0.7 integration test (adaptive timeout + idle reaping)"
  IO.println ""
  testPollTimeout
  testIdleExpiry
  testReapIdle
  testReceiveUntilInfra
  IO.println ""
  IO.println "v0.7 integration test complete"
