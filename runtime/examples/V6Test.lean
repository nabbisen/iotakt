import IotaktRuntime.Loop
import IotaktRuntime.Router
import IotaktRuntime.Http
import IotaktRuntime.Native
import Henret.Model

/-!
# iotakt v0.6 integration test

Tests the v0.6 additions:

* **Router** — exact paths, `:param` capture, multi-param, method matching, 404.
* **Gap 006** — cancel-on-close frees the Henret task; `taskByKey` is cleaned up.
* **henret v0.11.0** — verifies the `cancel` op transitions the task to terminal
  and that `inject` still returns `.ok` (regression for the bridge proof fix).
-/

open IotaktRuntime.Loop IotaktRuntime.Router IotaktRuntime.Http IotaktRuntime.Native Iotakt.Model

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

-- ─────────────────────────────────────────────────────────────────────────
-- A. Router unit tests
-- ─────────────────────────────────────────────────────────────────────────
def testRouter : IO Unit := do
  IO.println "=== A. Router ==="

  let r := Router.empty
    |>.get  "/"          (fun _ => HttpResponse.ok "home")
    |>.get  "/health"    (fun _ => HttpResponse.ok "ok")
    |>.get  "/users/:id" (fun p => HttpResponse.ok (p.get "id"))
    |>.get  "/api/:resource/:id" (fun p =>
        let res := p.get "resource"
        let id  := p.get "id"
        HttpResponse.ok s!"{res}/{id}")
    |>.post "/users"     (fun _ => HttpResponse.ok "created")

  check "router has 5 routes" (r.size == 5)

  -- Exact match
  let home := r.dispatch "GET" "/"
  check "GET / → home" ((String.fromUTF8? home.body |>.getD "") == "home")
  check "GET / → 200"  (home.statusCode == 200)

  let health := r.dispatch "GET" "/health"
  check "GET /health → ok" ((String.fromUTF8? health.body |>.getD "") == "ok")

  -- Single param capture
  let user := r.dispatch "GET" "/users/42"
  check "GET /users/42 → id=42" ((String.fromUTF8? user.body |>.getD "") == "42")

  let user2 := r.dispatch "GET" "/users/abc"
  check "GET /users/abc → id=abc" ((String.fromUTF8? user2.body |>.getD "") == "abc")

  -- Multi-param capture
  let api := r.dispatch "GET" "/api/widgets/7"
  check "GET /api/widgets/7 → widgets/7"
    ((String.fromUTF8? api.body |>.getD "") == "widgets/7")

  -- Method matching: POST /users matches, GET /users does not
  let post := r.dispatch "POST" "/users"
  check "POST /users → created" ((String.fromUTF8? post.body |>.getD "") == "created")

  let getUsers := r.dispatch "GET" "/users"
  check "GET /users → 404 (only POST registered)" (getUsers.statusCode == 404)

  -- Wrong method on existing path
  let postHealth := r.dispatch "POST" "/health"
  check "POST /health → 404 (only GET registered)" (postHealth.statusCode == 404)

  -- Unknown path
  let unknown := r.dispatch "GET" "/nonexistent"
  check "GET /nonexistent → 404" (unknown.statusCode == 404)

  -- Query string is stripped before matching
  let withQuery := r.dispatch "GET" "/users/99?foo=bar"
  check "GET /users/99?foo=bar → id=99 (query stripped)"
    ((String.fromUTF8? withQuery.body |>.getD "") == "99")

  -- Length mismatch does not match a wildcard route
  let tooLong := r.dispatch "GET" "/users/42/extra"
  check "GET /users/42/extra → 404 (segment count mismatch)" (tooLong.statusCode == 404)

-- ─────────────────────────────────────────────────────────────────────────
-- B. matchPattern unit tests
-- ─────────────────────────────────────────────────────────────────────────
def testMatchPattern : IO Unit := do
  IO.println ""
  IO.println "=== B. matchPattern ==="

  check "exact match []"
    ((matchPattern [] []).isSome)
  check "exact match [a] vs [a]"
    ((matchPattern ["a"] ["a"]).isSome)
  check "no match [a] vs [b]"
    ((matchPattern ["a"] ["b"]).isNone)
  check "no match length mismatch"
    ((matchPattern ["a"] ["a", "b"]).isNone)

  match matchPattern [":id"] ["42"] with
  | some p => check "capture :id=42" (p.get "id" == "42")
  | none   => check "capture :id=42" false

  match matchPattern ["users", ":id"] ["users", "7"] with
  | some p => check "capture users/:id=7" (p.get "id" == "7")
  | none   => check "capture users/:id=7" false

  check "pathSegments /a/b/c → 3 segments"
    ((pathSegments "/a/b/c").length == 3)
  check "pathSegments / → 0 segments"
    ((pathSegments "/").length == 0)

-- ─────────────────────────────────────────────────────────────────────────
-- C. Gap 006: cancel-on-close (henret v0.11.0)
-- ─────────────────────────────────────────────────────────────────────────
def testGap006 : IO Unit := do
  IO.println ""
  IO.println "=== C. Gap 006: cancel-on-close ==="

  -- Verify Henret cancel transitions a spawned task to terminal
  let rt0 := Henret.RuntimeState.init
  let (rt1, spawnRes) := Henret.step rt0 (.spawn 0)
  let task := match spawnRes with | .spawned t => t | _ => 999
  check "Henret spawn returns a task id" (task != 999)

  -- The spawned task is in a non-terminal state
  let stateBefore := rt1.taskState task
  check "spawned task is non-terminal"
    (match stateBefore with
     | some .new | some .ready | some .running => true
     | _ => false)

  -- Cancel it
  let (rt2, _) := Henret.step rt1 (.cancel task)
  let stateAfter := rt2.taskState task
  check "cancelled task is terminal (.cancelled)"
    (match stateAfter with | some .cancelled => true | _ => false)

  -- Verify cancel removes the task from readyQ
  check "cancelled task removed from readyQ"
    (!rt2.readyQ.contains task)

  -- Verify inject still returns .ok (the bridge proof regression)
  let (rt3, _) := Henret.step rt2 (.spawn 1)  -- spawn creates mailbox for actor 1
  let (_, injRes) := Henret.step rt3 (.inject 1 { id := 0, payload := 5 })
  check "inject after spawn returns .ok (mailbox auto-created)"
    (match injRes with | .ok => true | _ => false)

  -- inject to a non-existent actor mailbox returns .invalid (documented discrepancy)
  let (_, injBad) := Henret.step rt0 (.inject 99 { id := 0, payload := 0 })
  check "inject to absent mailbox returns .invalid (discrepancy #1)"
    (match injBad with | .invalid => true | _ => false)

-- ─────────────────────────────────────────────────────────────────────────
-- D. EventLoop task tracking
-- ─────────────────────────────────────────────────────────────────────────
def testTaskTracking : IO Unit := do
  IO.println ""
  IO.println "=== D. EventLoop task tracking ==="

  let some loop ← EventLoop.create | do IO.println "epoll failed"; return

  let key1 : FdKey := { raw := 100, gen := 1 }
  let key2 : FdKey := { raw := 101, gen := 1 }

  let loop1 := loop.recordTask key1 5
  let loop2 := loop1.recordTask key2 6

  check "taskOf key1 = 5" (loop2.taskOf key1 == some 5)
  check "taskOf key2 = 6" (loop2.taskOf key2 == some 6)
  check "taskOf unknown = none" ((loop2.taskOf { raw := 999, gen := 1 }).isNone)

  let loop3 := loop2.forgetTask key1
  check "after forget key1: taskOf key1 = none" ((loop3.taskOf key1).isNone)
  check "after forget key1: taskOf key2 still 6" (loop3.taskOf key2 == some 6)

  loop.unsafeDestroy

-- ─────────────────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────────────────
def main : IO Unit := do
  IO.println "iotakt v0.6 integration test (henret v0.11.0)"
  IO.println ""
  testRouter
  testMatchPattern
  testGap006
  testTaskTracking
  IO.println ""
  IO.println "v0.6 integration test complete"
