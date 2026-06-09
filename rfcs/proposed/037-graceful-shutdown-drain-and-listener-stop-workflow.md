# RFC 037: Graceful Shutdown, Drain, and Listener Stop Workflow

- **Status:** Proposed
- **Intended phase:** v0.2+
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines graceful shutdown semantics for iotakt-managed listeners and connections. It distinguishes listener stop, connection drain, forced close, and process exit.

## 2. Motivation

A server built on henejt + iotakt + henret must be able to stop accepting new connections while allowing existing actors to finish in-flight work. Without a clear workflow, shutdown can cause data loss, leaked resources, or inconsistent actor states.

## 3. Shutdown modes

```lean
inductive ShutdownMode where
  | stopAccepting
  | drainExisting
  | forceClose
  | processExit
```

These modes are intentionally separate.

- `stopAccepting`: listener remains known but read/accept interest is removed.
- `drainExisting`: existing connections may continue until completed or deadline.
- `forceClose`: all matching resources are deregistered and closed.
- `processExit`: best-effort cleanup before process termination.

## 4. Listener stop workflow

```text
1. Receive stop-listener command.
2. Remove read interest from listener fd.
3. Deregister listener from poller if it has no remaining interests.
4. Close listener fd unless restart is explicitly requested.
5. Remove listener registry entry.
6. Drop pending accept readiness for the listener FdKey.
7. Existing accepted connection actors continue unaffected.
```

## 5. Graceful connection drain

Connection drain is not a protocol-level concept in iotakt. iotakt only supports the resource mechanics.

```text
1. henejt decides that a connection should drain.
2. henejt stops creating new application work for that connection.
3. Actor flushes pending output using iotakt send.
4. Actor requests write shutdown or close.
5. iotakt deregisters and closes the fd.
```

## 6. Deadlines

Iotakt may expose a deadline-aware drain helper only if it uses Henret logical time or an explicitly injected clock event. It must not hide wall-clock timers in native code.

```lean
structure DrainPolicy where
  deadline?      : Option TimePoint
  forceAfter?    : Option Duration
  closeListeners : Bool
```

## 7. Invariants

```text
No-new-accept invariant:
  After stopAccepting reaches the model state, no new accepted connection is produced by that listener.

Connection preservation invariant:
  Stopping a listener does not close already accepted connections.

Deadline determinism invariant:
  Drain deadline behavior is driven by explicit Henret tick/logical-time input.
```

## 8. Failure policy

If deregistration fails during shutdown, iotakt records the failure and proceeds to close according to cleanup policy. If close fails, the resource is removed from the registry and the failure is reported; iotakt must not retry close blindly.

## 9. Observability

Shutdown should emit structured trace records:

```text
listener.stop_requested
listener.interest_removed
listener.closed
connection.drain_started
connection.drain_deadline_expired
connection.force_closed
```

## 10. Acceptance criteria

- A fake-poller test demonstrates listener stop without closing existing connections.
- A drain test demonstrates write flush followed by close.
- A forced shutdown test demonstrates cleanup of all resources for a service.
- The proof/trust/test matrix classifies all shutdown guarantees.
