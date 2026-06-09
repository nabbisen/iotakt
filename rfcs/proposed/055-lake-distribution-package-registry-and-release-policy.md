---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 055: Lake Distribution, Package Registry, and Release Channel Policy

## Summary

This RFC defines a post-v1 policy for distributing iotakt through the Lean/Lake ecosystem while
handling optional native backends responsibly. iotakt should remain easy to build in Lean-only mode,
while native backends must be opt-in, platform-gated, and tested through release channels.

## Motivation

Henret emphasizes Lean-only buildability and auditable optional native boundaries. iotakt will need
native code for real sockets, but the package should not surprise users by requiring unsupported
platform toolchains or native linkage for model-only use. Clear distribution policy is necessary for
adoption.

## Goals

- Define Lean-only, native-enabled, and experimental release channels.
- Preserve model-only builds without C compiler dependency where possible.
- Provide predictable Lake configuration.
- Keep platform backends feature-gated.
- Document compatibility with Lean toolchain versions.

## Non-goals

- No custom package registry implementation.
- No binary package manager in iotakt.
- No vendored large native libraries.
- No support promise for all platforms.

## Release channels

### model-only channel

Builds:

- `Iotakt.Model`
- fake poller
- proof files
- documentation examples that do not require native sockets

Does not build:

- C native backend
- epoll/kqueue modules
- integration examples requiring OS sockets

### native-stable channel

Builds native backends that have passed release gates:

- Linux epoll after v1.
- kqueue after its RFC is ratified and implemented.

### experimental channel

Builds post-v1 experimental backends:

- io_uring
- IOCP
- UDP preview
- zero-copy APIs

Experimental APIs must be explicitly imported or feature-enabled.

## Lake structure

Recommended module layout:

```text
Iotakt.lean
Iotakt/Model/*.lean
Iotakt/Fake/*.lean
Iotakt/Native/*.lean
Iotakt/Native/Epoll/*.lean
Iotakt/Native/Kqueue/*.lean
Iotakt/Experimental/*.lean
```

Native code should live under a clearly named directory such as:

```text
native/iotakt_epoll.c
native/iotakt_kqueue.c
native/iotakt_common.c
```

## Versioning policy

- Public Lean model APIs follow semantic versioning after v1.
- Native backend APIs may have stricter compatibility windows.
- Experimental modules are not stable unless promoted by RFC.
- The proof/trust/test matrix must be updated for every new native backend.

## Toolchain policy

Each release should declare:

- Lean version.
- Lake version assumptions.
- Supported C compiler families.
- Supported OS/backend combinations.
- Whether native tests were run in CI.

## Documentation requirements

Each release must include:

- model-only quickstart,
- native backend quickstart,
- feature flag table,
- platform support table,
- proof/trust/test matrix link,
- known limitations.

## Security considerations

- Native backends must not be silently enabled in contexts that expect model-only builds.
- Experimental backends must not be confused with audited stable backends.
- Release artifacts should disclose which native files were compiled.

## Acceptance criteria

- A user can build model-only iotakt without native backend surprises.
- Native feature flags are explicit and documented.
- Experimental modules are clearly marked in module names and docs.
- Release notes include backend support and trust matrix status.
