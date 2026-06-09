# RFC 004: Interest, Readiness, and Normalized Event Vocabulary

**Status:** Proposed  
**Milestone:** M1  
**Priority:** Critical  
**Primary layer:** Iotakt.Model

## Document Control

- **Project:** iotakt
- **Language:** Lean 4 with an optional native C boundary
- **Primary stack position:** `henejt` → `iotakt` → `henret`
- **Design principle:** Lean-first model, explicit trusted boundary, no hidden async runtime
- **Date:** 2026-06-08

## Common Terminology

- **Raw fd:** the integer file descriptor returned by the host OS.
- **FdKey:** stable iotakt identity, composed of `raw_fd` and a monotonic generation.
- **Interest:** what iotakt asked the poller to observe, normally readability or writability.
- **Readiness:** a host hint that an operation may make progress; it is not a guarantee.
- **Registry:** the Lean-side state that maps active `FdKey`s to owner actors and interests.
- **Native boundary:** the optional C FFI layer that performs POSIX socket and poller calls.
- **Bridge:** the deterministic Lean layer that translates iotakt events into Henret operations/messages.

## Summary

This RFC defines backend-neutral interest and event vocabulary. iotakt must model Linux epoll and future BSD/macOS kqueue without letting either backend's exact flags leak into the pure model. The central semantic rule is that readiness is a hint, not a guarantee.

## Motivation

If the model is shaped only around epoll flags, later kqueue support will either require model changes or awkward compatibility shims. Conversely, if the model claims too much about readiness, it will be false in real non-blocking socket programming. `EAGAIN` after a readiness event must be normal.

## Goals

- Define backend-neutral `Interest`, `InterestSet`, and `IoEvent`.
- Define readiness-as-hint semantics.
- Separate EOF, hangup, and error where possible.
- Define event normalization obligations for native backends.
- Keep kqueue compatibility in the v0.1 model even if implementation is deferred.

## Non-Goals

- Do not define exact epoll implementation; RFC 011 owns that.
- Do not implement kqueue; RFC 016 plans it.
- Do not guarantee read/write progress from readiness.
- Do not model packet-level TCP behavior.

## External Design

Application-visible events should be simple and backend-neutral:

```text
Readable: reading may make progress.
Writable: writing may make progress.
Eof: peer closure/end-of-stream observed.
Hangup: peer/socket hangup observed.
Error: native/backend error observed.
```

No public `IoMessage` should expose `EPOLLIN`, `EPOLLOUT`, `EVFILT_READ`, `EV_EOF`, or similar backend flags directly. Such flags belong to native normalization modules and traces.

## Data Model / Internal Design

Representative model:

```lean
inductive Interest where
  | readable
  | writable
  deriving DecidableEq, Repr

structure InterestSet where
  read  : Bool := false
  write : Bool := false
  deriving DecidableEq, Repr

inductive IoEvent where
  | readable
  | writable
  | eof
  | hangup
  | error (errno : Option IoErrno)
  deriving DecidableEq, Repr

structure NativeEvent where
  rawFd : RawFd
  mask  : UInt32
  data  : Int := 0
  deriving Repr

inductive NormalizedEvent where
  | event (rawFd : RawFd) (ev : IoEvent)
  | ignored (rawFd : RawFd) (reason : String)
```

`IoErrno` should be a small typed enumeration for the errno values iotakt distinguishes, with an escape hatch for unknown platform codes.

## Lifecycle / Workflow

Normalization workflow:

```text
native poller output
  → backend-specific normalization
  → normalized raw-fd event list
  → registry/current-generation resolution
  → interest and ownership validation
  → bridge message construction
```

Readiness handling workflow:

```text
Readable message received
  → actor calls recv
  → bytes | wouldBlock | eof | interrupted | error
  → actor/henejt decides protocol progress or close
```

Writable handling workflow:

```text
Writable message received
  → actor calls send with pending output
  → wrote n | wouldBlock | interrupted | closed | error
  → actor retains unsent suffix if n < length
  → actor disables writable interest when output queue is empty
```

## Public API Impact

Public API should use model-level events and result types:

```lean
inductive IoMessage where
  | ready (key : FdKey) (event : IoEvent)

inductive ReadResult where
  | bytes (data : ByteArray)
  | wouldBlock
  | eof
  | interrupted
  | error (errno : IoErrno)

inductive WriteResult where
  | wrote (n : USize)
  | wouldBlock
  | interrupted
  | closed
  | error (errno : IoErrno)
```

## Native Boundary Impact

Native backends must provide a normalization table. For Linux epoll, typical mappings include:

```text
EPOLLIN      → readable
EPOLLOUT     → writable
EPOLLHUP     → hangup or eof/hangup depending policy
EPOLLERR     → error none or error from getsockopt(SO_ERROR) if supported
EPOLLRDHUP   → eof/hangup when available
```

For kqueue planning:

```text
EVFILT_READ + EV_EOF → eof or readable+eof according to backend policy
EVFILT_WRITE         → writable
EV_ERROR             → error
```

The exact table is backend-owned, but its output vocabulary is fixed here.

## Henret Integration Impact

Henret bridge receives normalized `IoEvent`s only. It must not branch on backend-specific flags. This keeps fake poller tests identical in shape to native backend behavior.

## Security Considerations

Treating readiness as a hint prevents unsafe assumptions such as reading without handling `EAGAIN` or assuming a whole write succeeded. Separating error/hangup/eof also prevents protocol code from silently ignoring terminal socket conditions.

## Proof Obligations

- Interest soundness: non-fatal readiness messages are produced only for registered interests.
- Backend neutrality: bridge logic depends only on normalized vocabulary.
- Readiness non-guarantee is represented by result types that include wouldBlock.

## Test Obligations

- Fake poller can produce every normalized event kind.
- Translation drops unregistered readable/writable events.
- Fatal/error events follow documented policy even when interest is absent.
- Native tests verify at least readable, writable, timeout, hangup/EOF where reproducible.

## Trust / Assumption Changes

- Assume backend normalization table accurately represents platform flags according to tests and docs.
- Do not assume readiness guarantees syscall progress.
- Do not assume all platforms distinguish EOF/hangup/error identically.

## Architecture Gaps

- Exact EPOLLHUP/EPOLLRDHUP mapping may need empirical tests.
- kqueue EOF semantics require careful design before native implementation.

## Acceptance Criteria

- Model contains backend-neutral interest and event types.
- Read/write result types include wouldBlock.
- No public API leaks epoll/kqueue flags as primary event types.
- Normalization tables are documented for epoll and future kqueue.

## Alternatives Considered

- Expose raw backend flags: rejected because it contaminates henejt and model proofs.
- Collapse EOF/hangup/error into one event: rejected because cleanup and protocol behavior need distinctions.
- Treat readiness as guaranteed progress: rejected as false for non-blocking sockets.

## Open Questions

- Whether `EPOLLERR` should query `SO_ERROR` in v0.1 or return error none plus trace.
- Whether EOF should be represented as its own message or as readable followed by `ReadResult.eof` only; own event is recommended for kqueue compatibility.

