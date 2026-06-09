# RFC 047: Production Operations Guide, Limits, and Incident Diagnostics

- **Status:** Proposed
- **Intended phase:** v0.3+
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines the operational documentation and diagnostic capabilities needed before iotakt is recommended for serious server experiments.

## 2. Motivation

Even if iotakt is primarily a Lean ecosystem and modeling library, it will be used by henejt and related server experiments. Operators need to understand limits, failures, and diagnostics without reading the source code.

## 3. Operations guide contents

The operations guide should cover:

```text
- supported platforms and backend maturity
- required ulimit / file descriptor settings
- listener configuration examples
- resource limit defaults
- shutdown behavior
- known native-boundary assumptions
- performance expectations
- failure mode interpretation
- trace logging format
- how to collect incident data
```

## 4. Runtime diagnostic counters

Expose optional counters:

```lean
structure IoCounters where
  acceptedConnections : Nat
  closedConnections   : Nat
  readWouldBlock      : Nat
  writeWouldBlock     : Nat
  staleEventsDropped  : Nat
  duplicateEventsCoalesced : Nat
  nativeErrors        : Nat
  forcedCloses        : Nat
```

Counters are diagnostic, not proof inputs.

## 5. Incident trace bundle

A useful incident bundle should include:

```text
- iotakt version
- Lean version
- platform/backend
- relevant socket options
- resource limits
- last N structured trace events
- counter snapshot
- native error summary
```

It must not include raw application payload bytes by default.

## 6. Privacy policy

Iotakt should avoid logging payload data. It should log fd identities, event types, states, and error classes. Applications above iotakt may choose to log protocol details, but iotakt should remain payload-private by default.

## 7. Limit documentation

Document the meaning of:

```text
- max registered fds
- max events per poll wait
- max accept loop iterations per readiness
- max pending readiness entries
- max cleanup batch size
```

## 8. Acceptance criteria

- Operations guide exists as Markdown.
- Diagnostic counters can be read in tests.
- Trace logs avoid payload bytes by default.
- A sample incident bundle can be generated from a fake-poller scenario.
