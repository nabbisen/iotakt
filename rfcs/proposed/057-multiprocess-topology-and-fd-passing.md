---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 057: Multi-Process Topology and File Descriptor Passing

## Summary

This RFC defines a post-v1 direction for multi-process service topologies and file descriptor passing.
The v1 iotakt design should remain single-process and actor-oriented. Post-v1 systems may need
supervisor/worker processes, privilege separation, graceful binary restart, or pre-fork style listener
sharing. These require explicit authority and lifecycle models, not ad hoc raw fd transfer.

## Motivation

Production services often use multiple processes for isolation, upgrades, or CPU parallelism. Unix
domain sockets can pass file descriptors using `SCM_RIGHTS`, and supervisors can distribute accepted
connections or listener sockets. However, fd passing reintroduces the same identity and stale-handle
risks that `FdKey(raw, generation)` was designed to solve, now across process boundaries.

## Goals

- Define future multi-process boundaries without making them v1 requirements.
- Preserve fd identity discipline across process transfer.
- Support privilege separation research.
- Avoid raw fd authority leaks.
- Keep Henret actor semantics local unless a separate distributed model is introduced.

## Non-goals

- No multi-process runtime in v1.
- No distributed Henret scheduler.
- No transparent actor migration across processes.
- No cluster management system.
- No mandatory prefork architecture.

## Topologies

### Supervisor owns listener

```text
supervisor process
  owns listening socket
  accepts or passes listener/accepted fd

worker process
  receives fd
  wraps it as new local FdKey
  registers with local iotakt poller
```

### Worker owns listener after handoff

```text
supervisor creates listener
  -> passes listener fd to worker
  -> worker accepts directly
```

### Hot restart

```text
old process owns listener
  -> passes listener to new process
  -> old process drains existing connections
  -> new process accepts new connections
```

## Data model

A received fd must get a new local generation:

```lean
structure ImportedFd where
  raw : Int
  source : ImportSource
  localGen : Nat
```

Never preserve the sender's `FdKey` as authoritative in the receiver. `FdKey` is process-local.

## Authority model

fd passing should use capability-style APIs:

```lean
inductive ImportAuthority where
  | listenerImport
  | acceptedConnectionImport
  | fileTransferImport
```

The receiver must know what kind of fd it is importing. It must not blindly treat any imported fd as a
socket of arbitrary type.

## Workflow: accepted connection handoff

1. Supervisor accepts TCP connection.
2. Supervisor sets nonblock/cloexec before passing, or receiver verifies and enforces it.
3. Supervisor sends fd over Unix domain socket.
4. Worker receives raw fd.
5. Worker creates local `FdKey` with fresh generation.
6. Worker validates nonblocking/cloexec policy.
7. Worker registers fd with poller and actor owner.

## Security considerations

- fd passing is authority passing.
- Peer credentials on Unix domain socket should be checked where supported.
- Imported fd type must be validated if possible.
- Double-close responsibilities must be explicit.
- A compromised supervisor can pass dangerous authority; iotakt cannot solve that alone.

## Proof/trust/test classification

PROVEN candidates:

- Imported fd gets a fresh local generation.
- Imported fd is not usable until registered with an owner actor.
- Deregister/close rules remain local and unchanged after import.

ASSUMED/TESTED:

- Correctness of `SCM_RIGHTS` transfer.
- Peer credential validation.
- Native fd type inspection.

OUTSCOPE:

- Distributed scheduler correctness.
- Cross-process actor identity semantics.

## Acceptance criteria

- Multi-process APIs are absent from v1 stable surface.
- Imported fds never reuse sender-side `FdKey` identity.
- Tests cover fd import, close responsibility, stale imported fd, and wrong-kind rejection where possible.
- Documentation warns that fd passing transfers authority.
