---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 060: Post-v1 API Consolidation and Ecosystem Integration

## Summary

This RFC defines a post-v1 API consolidation phase for iotakt after the initial stable release and
future experiments. The purpose is to prevent the project from accumulating a fragmented API surface as
UDP, kqueue, outbound connect, buffer reuse, metrics, and other features are explored.

## Motivation

Systems libraries often decay after v1 when experimental features are added without a consolidation
cycle. iotakt is especially sensitive because its value depends on a clean boundary, named assumptions,
and simple mental model. A post-v1 consolidation RFC should be scheduled before broad ecosystem
promotion.

## Goals

- Review all stable and experimental modules after v1.
- Identify APIs to stabilize, rename, merge, or remove.
- Preserve a small core surface.
- Keep henejt integration simple.
- Ensure documentation matches actual behavior.

## Non-goals

- No new backend implementation in this RFC.
- No feature expansion.
- No source-breaking changes without migration notes.
- No hiding of experimental status.

## Consolidation targets

### Module layout

Review whether the package still has a comprehensible shape:

```text
Iotakt.Model
Iotakt.Driver
Iotakt.HenretBridge
Iotakt.Native.Epoll
Iotakt.Native.Kqueue
Iotakt.Experimental.*
```

### Result types

Unify naming conventions for:

- read results,
- write results,
- datagram results,
- connect results,
- completion results,
- native error results.

### Feature flags

Remove stale feature flags and ensure experimental flags remain clearly marked.

### Documentation

The guided tour should teach the stable path first:

1. model-only fake poller,
2. TCP listener,
3. accepted connection actor,
4. read/write workflow,
5. close lifecycle,
6. native backend notes.

Advanced features should not obscure the core path.

## Ecosystem integration

Potential integrations to document:

- henejt HTTP server adapter,
- Henret examples,
- educational systems modeling examples,
- native conformance test templates,
- Lake package examples.

## Deprecation policy

An API may be deprecated if:

- it duplicates a clearer API,
- it exposes raw fd authority unnecessarily,
- it depends on an experimental backend no longer pursued,
- it conflicts with proof/model naming.

Deprecation should include:

- reason,
- replacement,
- removal timeline,
- migration example.

## Acceptance criteria

- Stable API index is regenerated.
- Experimental APIs are clearly labeled.
- henejt integration example uses only stable APIs unless explicitly noted.
- Release notes list all breaking changes, deprecations, and promotions.
- The proof/trust/test matrix is consistent with the final API surface.
