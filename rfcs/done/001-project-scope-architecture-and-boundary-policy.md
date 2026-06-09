# RFC 001: Project Scope, Architecture, and Boundary Policy

**Status.** Implemented (v0.1.0-dev)

**Status:** Proposed  
**Milestone:** M0  
**Priority:** Critical  
**Primary layer:** Cross-cutting

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

This RFC defines the identity and architectural boundary of `iotakt`. `iotakt` is a Lean 4 I/O readiness and socket lifecycle library intended to sit between `henejt`, the future HTTP server layer, and `henret`, the executable actor/task runtime model. It must remain a small, auditable boundary rather than becoming a general async runtime.

The main architectural split is:

```text
Iotakt.Model         pure Lean model and proof targets
Iotakt.HenretBridge deterministic translation into Henret operations/messages
Iotakt.Native       optional effectful C FFI backend
Iotakt.Fake         deterministic poller and test backend
```

## Motivation

Without a strict boundary policy, a socket library can quickly become an async runtime, protocol framework, logging system, DNS resolver, TLS wrapper, and performance experiment all at once. That would undermine the main reason to build iotakt in Lean: clear executable models, small trusted boundaries, and claims that are either proven, tested, assumed, or explicitly out of scope.

This RFC prevents scope creep before implementation begins. It also preserves Henret's design culture: pure transition semantics first, backend boundaries second, and native effects only where they are unavoidable.

## Goals

- Define iotakt's role in the `henejt / iotakt / henret` stack.
- Define the top-level package/module split.
- Require a Lean-only default build path for the model and fake backend.
- Require native functionality to be optional, explicit, and tested.
- Establish the proof/trust/test/out-of-scope classification policy.
- Make non-goals visible enough to prevent runtime/protocol scope creep.

## Non-Goals

- Do not define the detailed fd registry model; RFC 002 owns that.
- Do not define epoll or kqueue backend behavior; backend RFCs own that.
- Do not introduce HTTP, TLS, WebSocket, or DNS responsibilities.
- Do not define a production async runtime, thread pool, or scheduler.
- Do not claim that POSIX, the C compiler, the Lean runtime, or the OS kernel is verified by iotakt.

## External Design

The external architecture is intentionally layered.

```text
+---------------------------------------------------------+
| henejt                                                  |
| HTTP routing, protocol state, handlers, request bodies   |
+---------------------------▲-----------------------------+
                            |
                            | IoMessage / public APIs
                            |
+---------------------------+-----------------------------+
| iotakt                                                  |
|                                                         |
|  Iotakt.Model        pure fd/event/registry model        |
|  Iotakt.HenretBridge event-to-Henret translation         |
|  Iotakt.Fake         deterministic fake poller           |
|  Iotakt.Native       optional C FFI socket/poller shim   |
+---------------------------▲-----------------------------+
                            |
                            | RuntimeOp / actor messages
                            |
+---------------------------+-----------------------------+
| henret                                                  |
| scheduler model, mailboxes, timers, executable drivers   |
+---------------------------------------------------------+
```

The default package must support a Lean-only workflow: model definitions, fake poller tests, proof files, and documentation must build without a C compiler. Native backends may be enabled by an explicit build target/profile.

The public project claim is not "verified network I/O." The correct claim is: "a formally disciplined Lean model and translation boundary for non-blocking socket readiness, with an optional tested native backend."

## Data Model / Internal Design

This RFC only fixes the architectural categories. Detailed types are introduced later, but each type must belong to exactly one layer unless explicitly justified.

```text
Iotakt.Model:
  RawFd, FdGeneration, FdKey, Interest, IoEvent,
  ResourceState, Registry, TranslationResult, TraceEvent

Iotakt.HenretBridge:
  IoMessage, bridge operations, driver loop state,
  poller result adapters, acknowledgement helpers

Iotakt.Native:
  extern declarations, native result encodings,
  errno mapping, platform-specific modules

Iotakt.Fake:
  scripted event traces, deterministic poller state,
  expected bridge traces
```

Internal implementation may add private helper modules, but public API exposure should be minimal and stable.

## Lifecycle / Workflow

The required high-level workflow is:

```text
1. Application/henejt creates or receives an actor responsible for a socket.
2. iotakt registers the resource and interest in the Lean model.
3. A poller, fake or native, yields readiness-like events.
4. iotakt normalizes and translates the events.
5. The Henret bridge injects only valid actor messages.
6. The actor performs read/write/accept/close operations through iotakt APIs.
7. Lifecycle changes update the model and native backend consistently.
```

No background native thread is allowed to mutate Henret state. A future multi-driver design would require a separate RFC and new proof/trust classification.

## Public API Impact

This RFC requires public names to be organized so application code can stay independent of backend details.

Expected public namespace shape:

```lean
namespace Iotakt
namespace Model
namespace Bridge
namespace Native
namespace Fake
```

Applications should import public model/result types and bridge helpers, not epoll-specific modules. Backend-specific imports are acceptable only for configuration or tests.

## Native Boundary Impact

The native boundary is optional and trusted/tested, not proven. It must be small enough to audit manually. The v0.1 native implementation policy is raw C, not Rust, because the intended wrapper surface is a small set of POSIX/kernel syscalls and because additional toolchain layers would obscure the boundary.

The native boundary must not contain protocol logic, application buffering, retained Lean pointers, background threads, or native queues.

## Henret Integration Impact

The bridge must interact with Henret through public operations/messages. It must not depend on private Henret scheduler internals. Because Henret's blocked receive is currently a result rather than a full parked wait-state mechanism, iotakt v0.1 must model readiness as externally injected messages rather than assuming native Henret wait queues.

## Security Considerations

The architecture must support later security obligations:

- fd leak prevention,
- stale event rejection,
- double-close prevention,
- non-blocking enforcement,
- close-on-exec policy,
- SIGPIPE prevention,
- resource limits.

Security-sensitive claims must be assigned to the layer that can actually support them. For example, stale event rejection is a model/bridge claim; OS readiness correctness is an assumption/tested native behavior.

## Proof Obligations

- This RFC itself has no theorem targets beyond enforcing the classification discipline.
- All later RFCs must classify claims as PROVEN, TESTED, ASSUMED, or OUTSCOPE.
- The Lean-only model must be the primary place where PROVEN claims live.

## Test Obligations

- Lean-only build target exists and does not require native C.
- Fake poller tests run without native backend.
- Native build, when enabled, is separate from model/proof build.

## Trust / Assumption Changes

- The Lean kernel and Lean runtime are trusted according to normal Lean project expectations.
- The native C shim, OS kernel, POSIX semantics, and C compiler are trusted/tested boundaries.
- No proof claim may silently depend on native behavior unless classified as ASSUMED or TESTED.

## Architecture Gaps

- Henret wait-queue/blocked-task parking is not assumed for v0.1.
- Native build integration can introduce platform friction and must be isolated.
- The first release may have Linux-only native support while keeping the model kqueue-compatible.

## Acceptance Criteria

- README-level architecture uses `henejt / iotakt / henret` terminology consistently.
- Modules are split into model, bridge, native, and fake/test responsibilities.
- Lean-only default build policy is documented.
- Native functionality is opt-in and classified as trusted/tested.
- Non-goals are explicit in project documentation.

## Alternatives Considered

- Single monolithic Lean module: rejected because it hides proof/native boundaries.
- Rust FFI shim for v0.1: rejected to avoid extra toolchain weight for a tiny syscall surface.
- Background native I/O thread: rejected because it complicates determinism and Henret integration.

## Open Questions

- Exact Lake build profile naming for native-enabled builds.
- Whether native examples live in the main package or a separate examples package.

