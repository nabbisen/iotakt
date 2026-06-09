# RFC 046: Security Review Playbook and Native Audit Checklist

- **Status:** Proposed
- **Intended phase:** continuous
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

## 8. Acceptance criteria

- Security checklist is part of the repository.
- Any RFC touching native code must include a security section.
- CI includes at least basic sanitizer/native warning gates where available.
- Release notes explicitly state native-boundary assumptions.
