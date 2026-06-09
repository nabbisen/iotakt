# RFC 045: Model-Based Testing, Trace Fuzzing, and Differential Replay

- **Status:** Proposed
- **Intended phase:** v0.2+ test hardening
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines a model-based testing strategy for iotakt using event trace generation, fuzzing, and deterministic replay.

## 2. Motivation

Socket bugs often appear only under unusual event orderings: duplicate readiness, stale events after close, partial writes, immediate EOF, errors racing with hangup, and accept storms. A fake poller enables these scenarios to be generated deterministically.

## 3. Trace format

Define a simple text or JSON-lines trace format:

```json
{"step":1,"op":"register","fd":{"raw":17,"gen":1},"interest":["read"]}
{"step":2,"op":"event","raw":17,"event":"readable"}
{"step":3,"op":"close","fd":{"raw":17,"gen":1}}
{"step":4,"op":"event","raw":17,"event":"readable"}
```

Late event at step 4 should be dropped.

## 4. Trace classes

Required generated classes:

```text
- normal accept/read/write/close
- duplicate readiness
- stale event after close
- fd reuse with new generation
- writable storm with no pending output
- EINTR around wait/read/write
- EAGAIN after readiness
- EOF mixed with readable
- listener shutdown while accept readiness is pending
- actor cancellation during pending readiness
```

## 5. Differential replay

A trace should be replayable against:

```text
- pure model translator
- fake poller driver
- native-backed integration harness where possible
```

The expected actor-visible message sequence should match where native nondeterminism is controlled. Where exact matching is impossible, the allowed equivalence relation must be documented.

## 6. Fuzzing boundary

Fuzzing should primarily target pure Lean structures and generated traces. Native fuzzing is useful but secondary. The most important safety properties should not depend on native backend honesty.

## 7. Oracle properties

```text
- no message for unknown fd
- no message for stale generation
- no duplicate pending readiness beyond coalescing policy
- no write-ready message when write interest is disabled
- close removes registry ownership
- forced cleanup leaves no actor-owned resources
```

## 8. CI policy

- Small deterministic trace suite runs on every CI build.
- Larger randomized trace suite runs nightly or before release candidates.
- Native stress tests may be platform-gated.

## 9. Acceptance criteria

- A trace schema is documented.
- At least 20 hand-written regression traces exist.
- A generator creates randomized traces with reproducible seeds.
- Failing traces are minimized or saved as regression inputs.
