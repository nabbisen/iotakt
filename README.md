# iotakt

[![Apache 2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)
[![Lean 4](https://img.shields.io/badge/Lean-4.15.0-purple.svg)](https://leanprover.github.io/)
[![Build: passing](https://img.shields.io/badge/build-passing-brightgreen.svg)](#quick-start)

*A small, auditable, non-blocking I/O readiness boundary for Lean 4 systems.*

---

## Overview

`iotakt` bridges operating-system socket readiness with Henret actor
messages. It sits between an HTTP layer (`jemmet`) and the Henret
actor/scheduler runtime:

```
jemmet  ──▶  iotakt  ──▶  henret
(HTTP)        (I/O)        (actors)
```

Its role is narrow and precise: translate OS readiness events into
Henret-compatible actor messages while keeping the boundary small,
proven, and auditable. It is **not** an HTTP server, not a TLS stack,
not a general async runtime.

## Why / When

Use iotakt when you need:

- Non-blocking TCP sockets integrated into a Henret actor system.
- A pure Lean model of file-descriptor lifecycle with machine-checked
  safety theorems.
- A deterministic fake poller backend for proof-adjacent testing,
  without any C or OS dependency.

Do **not** use iotakt if you need HTTP, TLS, DNS, UDP, or a
production-grade async runtime — those live above or below this layer.

## Quick Start

> **Henret dependency.** iotakt requires **Henret v0.17.7**. The lakefile's
> active require is a path to a vendored sibling tree
> (`../henret/henret-v0.17.7`), used for local and CI builds against a
> known Henret. The CI-portable form is the git require shown in the
> lakefile comment (tag `"0.17.7"` — Henret tags carry no `v` prefix),
> resolved via `LAKE_PKG_URL_MAP`; it becomes usable once Henret publishes
> the `0.17.7` tag on GitHub (highest published tag is `0.15.2` at the time
> of this release). Until then, place a Henret v0.17.7 checkout at
> `../henret/henret-v0.17.7` relative to this repo before building.

```bash
# Requires elan and Lean 4.15.0 (see lean-toolchain)
git clone https://github.com/nabbisen/iotakt
cd iotakt
# Provide Henret v0.17.7 at ../henret/henret-v0.17.7 (vendored), OR — once the
# 0.17.7 tag is published — switch the lakefile to the git require.
lake build Iotakt          # pure model + fake poller (Lean-only, no C)
lake build IotaktBridge    # + Henret bridge
lake build iotakt-fake-demo && ./.lake/build/bin/iotakt-fake-demo
```

Expected output:

```
scenario 1: readable delivered, parked actor woken, Mesa re-receive
  [PASS] parked task 0 starts in waiting
  [PASS] readable produced exactly one inject
  [PASS] inject delivered (.ok), head waiter woken to ready
  ...
all demo scenarios executed
```

The demo runs 7 canonical scenarios (19 checks) through the real Henret
v0.6.0 bridge with zero OS calls — fully deterministic.

## Design Notes

**Lean-first with explicit trusted boundaries.** The pure model
(`Iotakt.Model`) builds without a C compiler and carries machine-checked
theorems. The Henret bridge (`Iotakt.Bridge`) is the only Henret-
dependent module. The optional native C shim (`native/`) is the only
trusted boundary and is intentionally small.

**`FdKey(raw_fd, generation)` not raw fd.** Raw file descriptor integers
are OS-temporary and get reused after close. Every resource is identified
by a `(raw_fd, generation)` pair; stale events are dropped at the model
boundary before reaching any actor.

**Readiness is a hint.** A `readable` event means reading *may* make
progress, not that it *will*. `EAGAIN` after readiness is a normal
outcome, not an error.

**No C-side application buffering.** The native shim performs one
syscall per operation and transfers ownership of returned bytes to Lean
immediately. There are no C-side queues or ring buffers.

**Coalescing prevents mailbox floods.** For each `(FdKey, kind)` at most
one readiness notification is outstanding at a time. Duplicate events
from level-triggered polling are suppressed at the model boundary.

## More Detail

- [Full documentation](./docs/src/SUMMARY.md)
- [Proof, Trust, and Test Matrix](./docs/src/proof-trust-test-matrix.md)
- [RFC index](./rfcs/README.md)
- [Henret Integration Notes](./docs/henret-integration-notes.md)
- [Native FFI Contract](./docs/src/native-ffi-contract.md)
