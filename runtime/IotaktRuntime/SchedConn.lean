import Henret.Model
import Iotakt.Model

/-!
# IotaktRuntime.SchedConn

**Scheduled connection-actor lifecycle (v0.8).**

This is the model that closes the gap noted in v0.7: it makes a connection
actor a *genuine Henret-running task* that parks on its mailbox with a
deadline via `receiveUntil`, rather than a passive mailbox target that the
driver injects into.

## Two-tier design (consistent with iotakt's philosophy)

iotakt deliberately keeps two views of every mechanism:

- **The model** (this file) shows the full scheduled lifecycle, verified
  against Henret's *actual* semantics. A connection actor is scheduled,
  runs, parks with a deadline, and is woken by either I/O (`inject`) or a
  timeout (`tick`).
- **The native driver** (`IotaktRuntime.Loop`) keeps the optimized single-outer-loop
  path where the driver does the syscalls and injects readiness. It does not
  schedule each connection actor, because doing so per-connection per-event
  would cost more than it saves for a single-threaded epoll loop.

This file is the formal specification a future scheduled driver (or jemmet)
would implement, and it unifies the logical and wall-clock clocks *in the
model* (Henret `now`/timers as the single time source).

## Lifecycle phases

```text
  spawned ──schedule──▶ running ──receiveUntil(d)──▶ parkedTimed
                          ▲                              │
                          │                              │ inject (I/O)
                          └───────schedule◀──────ready───┤
                                                         │ tick≥d (timeout)
                                                         └──▶ ready (empty mailbox)
  running ──cancel──▶ cancelled (closed)
```
-/

namespace IotaktRuntime.SchedConn

open Iotakt.Model

/-- The observable phase of a scheduled connection actor, derived from its
Henret task state. -/
inductive ConnPhase where
  /-- Spawned, queued, not yet scheduled. -/
  | spawned
  /-- Scheduled and running; may do I/O or park. -/
  | running
  /-- Parked on its mailbox with a deadline (`.waitingTimed`). -/
  | parkedTimed
  /-- Woken (by I/O or timeout); ready to be scheduled again. -/
  | ready
  /-- Failed (terminal, distinct from a clean close); a supervisor may
  restart it (henret ≥ v0.15.0, RFC 049). -/
  | failed
  /-- Closed via cancel. -/
  | closed
  /-- Any other Henret state (shouldn't occur in this lifecycle). -/
  | other
  deriving Repr, DecidableEq

/-- Read a task's phase out of a Henret runtime. -/
def phaseOf (rt : Henret.RuntimeState) (task : Henret.TaskId) : ConnPhase :=
  match rt.taskState task with
  | some .new          => .spawned
  | some .ready        => .ready
  | some .running      => .running
  | some .waitingTimed => .parkedTimed
  | some .failed       => .failed
  | some .cancelled    => .closed
  | _                  => .other

/-- A scheduled connection actor: the owning actor id, its task id, and the
deadline it last parked with (if any). -/
structure SchedConn where
  actor     : Henret.ActorId
  task      : Henret.TaskId
  deadline  : Option Nat := none
  deriving Repr

/-- Spawn a connection actor. Returns the updated runtime and the SchedConn
with its freshly-allocated task id. The actor's mailbox is auto-created
(henret ≥ v0.6.0). -/
def spawn (rt : Henret.RuntimeState) (actor : Henret.ActorId) :
    Henret.RuntimeState × SchedConn :=
  let (rt1, res) := Henret.step rt (.spawn actor)
  let task := match res with | .spawned t => t | _ => 0
  (rt1, { actor := actor, task := task })

/-- Schedule the connection's task so it becomes `running`. -/
def schedule (rt : Henret.RuntimeState) : Henret.RuntimeState :=
  (Henret.step rt .schedule).1

/-- Park the (running) connection actor on its mailbox with a deadline via
`receiveUntil`. The task transitions to `.waitingTimed`, a timer is
registered, and `waitDeadline` is set. Returns the updated runtime, the
connection with its recorded deadline, and the step result (`.blocked` on a
successful park, `.received` if a message was already waiting, `.timedOut`
if the deadline was already past). -/
def parkWithDeadline (rt : Henret.RuntimeState) (c : SchedConn) (deadline : Nat) :
    Henret.RuntimeState × SchedConn × Henret.StepResult :=
  let (rt1, res) := Henret.step rt (.receiveUntil c.task deadline)
  (rt1, { c with deadline := some deadline }, res)

/-- Wake the connection actor because I/O is ready: inject a readiness
message into its mailbox. A parked timed-waiter is moved to `ready`. -/
def wakeOnIo (rt : Henret.RuntimeState) (c : SchedConn) (msg : Henret.Message) :
    Henret.RuntimeState :=
  (Henret.step rt (.inject c.actor msg)).1

/-- Advance logical time to `now`, waking any timed waiters whose deadline
has expired (the timeout path). -/
def tick (rt : Henret.RuntimeState) (now : Nat) : Henret.RuntimeState :=
  (Henret.step rt (.tick now)).1

/-- Close the connection actor by cancelling its task (Gap 006). -/
def close (rt : Henret.RuntimeState) (c : SchedConn) : Henret.RuntimeState :=
  (Henret.step rt (.cancel c.task)).1

/-- Fail the connection actor (henret ≥ v0.15.0, RFC 049). Like `close`, it
cleans up the task's queue/timer/waiter entries, but lands in `.failed`
rather than `.cancelled` — so a supervisor can distinguish an error from an
intentional close and restart it. -/
def fail (rt : Henret.RuntimeState) (c : SchedConn) : Henret.RuntimeState :=
  (Henret.step rt (.fail c.task)).1

/-- Restart a failed connection actor under a running supervisor task
(henret ≥ v0.15.0, RFC 049). Returns the updated runtime and a fresh
`SchedConn` for the replacement, with restart provenance recorded in
Henret's `restartOf` field. The supervisor (`parent`) must be running, the
failed connection must be parented by it and in `.failed`. -/
def restart (rt : Henret.RuntimeState) (parent : Henret.TaskId)
    (failed : SchedConn) (actor : Henret.ActorId) :
    Henret.RuntimeState × SchedConn :=
  let (rt1, res) := Henret.step rt (.restartOne parent failed.task actor)
  let newTask := match res with | .spawned t => t | _ => failed.task
  (rt1, { actor := actor, task := newTask })

end IotaktRuntime.SchedConn
