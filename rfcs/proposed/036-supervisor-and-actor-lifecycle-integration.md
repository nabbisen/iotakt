# RFC 036: Supervisor and Actor Lifecycle Integration

- **Status:** Proposed
- **Intended phase:** v0.2+
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines how iotakt cooperates with Henret actor lifecycle and supervision. Its core purpose is to prevent file descriptor leaks, stale registry entries, and double-close behavior when actors terminate, fail, or are cancelled.

## 2. Motivation

Network actors can terminate normally, be cancelled by a supervisor, panic at the application layer, or be forcefully stopped during shutdown. In all cases, iotakt must ensure that owned resources are deregistered and closed exactly once.

Without an explicit lifecycle contract, it becomes unclear whether the actor, the supervisor, iotakt, or henejt owns cleanup.

## 3. Ownership rule

An iotakt-managed fd has exactly one close owner at a time.

For accepted connection sockets, the owning actor is the logical owner, but iotakt remains the resource manager that performs native deregistration and close through an explicit command.

```text
Actor owns authority to request operations.
iotakt owns the registry and native close protocol.
Native layer owns no long-lived resource state.
```

## 4. Lifecycle commands

Introduce an actor-to-iotakt control vocabulary:

```lean
inductive IoControl where
  | close        : FdHandle -> IoControl
  | shutdownRead : FdHandle -> IoControl
  | shutdownWrite : FdHandle -> IoControl
  | setInterest  : FdHandle -> InterestSet -> IoControl
  | release      : FdHandle -> IoControl
```

`release` is an internal lifecycle command used during supervised actor termination. It means: remove all interests, deregister if registered, close if still open, invalidate the handle.

## 5. Supervisor workflow

```text
1. Supervisor decides to stop actor A.
2. Supervisor sends or injects cancellation into Henret.
3. iotakt receives an actor termination notification or lifecycle hook.
4. iotakt enumerates FdKeys owned by A.
5. For each FdKey:
   a. clear pending readiness
   b. deregister from poller
   c. close native fd
   d. remove registry entry
   e. increment or retire generation record
6. Late native events for the raw fd are ignored.
```

## 6. Failure handling

Native cleanup failures must be classified but not allowed to resurrect a resource.

```lean
inductive CleanupResult where
  | closed
  | alreadyClosed
  | deregisterFailed : IoErrno -> CleanupResult
  | closeFailed      : IoErrno -> CleanupResult
```

Even if `close` reports an error, the fd must be removed from iotakt's registry. POSIX close error handling is subtle; iotakt must not retry close blindly because the raw fd may already have been released and reused.

## 7. Required invariants

```text
Single-close model invariant:
  A modeled FdKey transitions to closed at most once.

Actor cleanup invariant:
  After actor termination cleanup, no registry entry remains owned by that actor.

Late-event invariant:
  After cleanup, no late event for the cleaned FdKey is delivered.

Supervisor non-interference:
  Cleanup for actor A does not remove resources owned by actor B.
```

## 8. Security considerations

Lifecycle cleanup is a security boundary. Leaked fds can preserve access to network peers after the logical actor has died. Double close can accidentally close an unrelated resource after fd reuse. Therefore, generation-based identity and exactly-once cleanup are mandatory.

## 9. Acceptance criteria

- The model includes actor-to-resource ownership mapping.
- Termination cleanup is deterministic and testable with a fake poller.
- Double close is modeled as invalid or no-op, never as a second native close.
- Native conformance tests cover close-after-deregister, actor cancellation, and stale event after close.
