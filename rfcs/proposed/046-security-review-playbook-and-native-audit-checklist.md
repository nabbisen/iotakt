# RFC 046: Security Review Playbook and Native Audit Checklist

- **Status:** Proposed — scheduled remediation review support
- **Intended phase:** R4 baseline audit and R5 independent requalification
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines a repeatable security review playbook for iotakt, especially for the native C boundary and fd lifecycle logic.

## 2. Motivation

Iotakt sits at a high-risk boundary: network input, native syscalls, FFI, file descriptor reuse, and actor message injection. Even a small codebase needs a formal review checklist so that future changes do not erode the original safety design.

## 3. Review areas

Security review must cover:

```text
- fd identity and generation handling
- nonblocking enforcement
- close-on-exec enforcement
- SIGPIPE prevention
- EINTR/EAGAIN classification
- partial read/write handling
- no C-side buffering
- no native pointer retention
- no malloc/free for application buffers
- deregister-before-close policy
- stale event rejection
- mailbox flood prevention
- actor authority checks
```

## 4. Native C checklist

Every native C function must answer:

```text
1. Can this function block?
2. Does it capture errno immediately?
3. Does it allocate memory?
4. Does it retain a pointer beyond the call?
5. Does it mutate a Lean object?
6. Does it return structs by value across FFI?
7. Does it expose raw platform constants unnecessarily?
8. Does it handle EINTR intentionally?
9. Does it classify EAGAIN/EWOULDBLOCK as normal?
10. Does it preserve close-on-exec and nonblocking invariants?
```

## 5. Lean model checklist

Every model transition must answer:

```text
1. What state does it mutate?
2. What invariant does it preserve?
3. What happens if the operation is invalid?
4. Can it create duplicate ownership?
5. Can it deliver an event to the wrong actor?
6. Can it turn stale fd identity into current authority?
7. Does it depend on native backend honesty?
```

## 6. Threat model

Primary threats:

```text
- remote client triggers resource exhaustion
- fd reuse causes wrong actor delivery
- actor cancellation leaks fd
- duplicate write readiness floods mailbox
- native FFI misuse corrupts Lean runtime
- accidental blocking call stalls the runtime driver
- unexpected SIGPIPE terminates process
```

## 7. Required artifacts

Each release candidate should include:

```text
- updated proof/trust/test matrix
- native audit checklist result
- sanitizer test result where supported
- stale fd regression test result
- resource-limit test result
- public API review result
```

The remediation requalification artifact must additionally contain this control
matrix. Every row cites the exact RFC acceptance criterion and a retained proof,
test, or gate log; an unchecked box or missing citation is release-blocking.

| Control | Required review question | Minimum evidence |
|---|---|---|
| Stable native-effect authority | Do stale and forged keys fail before every stable native fd effect, including close, recv/send, interest, and lifecycle operations? | RFC 064 complete effect-path inventory plus per-row stale/forged tests and cited proofs |
| Native buffer/resource bounds | Is all buffer arithmetic subtraction-safe, and does every stable receive-allocation path enforce configured limits before allocation/FFI? | RFC 065 receive-path inventory, ordinary boundary log, and RFC 067 ASan/UBSan log |
| Authoritative delivery | Is there exactly one authoritative delivered-event result from which injection and public readiness are derived? | RFC 066 delivery/coalescing/lifecycle tests and result-flow review |
| Failure-atomic transitions | Do register/modify/deregister/accept/connect/close and delivery failures preserve model/native correspondence with bounded orphan cleanup? | RFC 029 complete matrix, state/resource snapshots, and RFC 066 transition tests |
| Fail-closed evidence | Does every mandatory gate fail closed, and do sanitizer claims identify the instrumented objects, command, revision, and retained log? | RFC 067 injected-failure self-test and clean-checkout/sanitizer provenance |
| Tracked-source integrity | Does the archive equal its tracked manifest, exclude ignored/untracked inputs, reproduce, and bind provenance to the same revision/input set? | RFC 068 manifest/archive audit, canonical-baseline checks, and two-worktree reproduction logs |

## 8. Acceptance criteria

- Security checklist is part of the repository.
- Any RFC touching native code must include a security section.
- CI includes at least basic sanitizer/native warning gates where available.
- Release notes explicitly state native-boundary assumptions.
- The final review artifact contains all six remediation controls above, with an
  explicit pass/fail disposition and a resolvable proof/test/log citation per row.
- Missing, stale, or non-reproducible evidence is a failed control rather than a
  reviewer warning.
