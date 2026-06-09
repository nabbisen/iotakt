import Iotakt.Model

/-!
# Iotakt.Fake.Poller

The Lean-only deterministic fake poller (RFC 008).

It replays an exact script of poll outcomes, so edge cases that are
impossible to time on a real OS — stale events, duplicate readiness
bursts, deterministic timeout/interrupted paths — become ordinary unit
inputs. It depends only on the pure model (no Henret, no native code),
so it builds in the Lean-only profile. The harness that feeds these
outcomes through the Henret bridge lives with the bridge-dependent
executable, not here.
-/

namespace Iotakt.Fake

open Iotakt.Model

/-- One scripted poll outcome. Mirrors the backend-neutral poll-wait
vocabulary so the fake drives exactly the same bridge path as a native
poller. -/
inductive FakePollResult where
  | events (events : List NormalizedRawEvent)
  | timeout
  | interrupted
  | fatal (err : IoErrno)
  deriving Repr, Inhabited

/-- A scripted poller: a fixed list of outcomes and a cursor. -/
structure FakePoller where
  script : List FakePollResult
  cursor : Nat := 0
  deriving Repr, Inhabited

namespace FakePoller

/-- Produce the next scripted outcome and advance the cursor. When the
script is exhausted the poller reports `timeout` forever (a real poller
with no registered fds and no timers blocks; the fake reports timeout so
test loops terminate). -/
def next (p : FakePoller) : FakePoller × FakePollResult :=
  match p.script[p.cursor]? with
  | some r => ({ p with cursor := p.cursor + 1 }, r)
  | none   => (p, .timeout)

/-- A fresh poller over a script. -/
def ofScript (s : List FakePollResult) : FakePoller := { script := s, cursor := 0 }

/-- Remaining (unconsumed) outcomes. -/
def remaining (p : FakePoller) : List FakePollResult := p.script.drop p.cursor

/-! ## Determinism lemmas -/

/-- **Replay determinism.** `next` is a pure function of the poller
state, so two replays from the same state are identical. -/
theorem next_deterministic (p : FakePoller) : p.next = p.next := rfl

/-- `next` returns exactly the scripted outcome at the cursor. -/
theorem next_scripted (p : FakePoller) {r : FakePollResult}
    (h : p.script[p.cursor]? = some r) :
    (p.next).2 = r := by
  simp [next, h]

/-- `next` advances the cursor by one when the script is not exhausted. -/
theorem next_advances (p : FakePoller) {r : FakePollResult}
    (h : p.script[p.cursor]? = some r) :
    (p.next).1.cursor = p.cursor + 1 := by
  simp [next, h]

/-- Past the end of the script, `next` reports `timeout` and does not
advance (so it cannot run off into undefined behavior). -/
theorem next_exhausted (p : FakePoller) (h : p.script[p.cursor]? = none) :
    p.next = (p, .timeout) := by
  simp [next, h]

end FakePoller
end Iotakt.Fake
