# jemmet Handoff

**Seed material for the separate jemmet project. Not part of the iotakt
library or build.**

[jemmet](https://github.com/nabbisen) (the name is from Norwegian *jemne*,
"smooth") is the HTTP server that will be built **on top of** iotakt, as its
own project, once iotakt is stable. iotakt deliberately does **not** develop
jemmet: routing, handler dispatch, keep-alive policy, and the serve loop are
the server's responsibility (iotakt RFC 001 non-goals).

This directory preserves a working prototype so the jemmet project can start
from a reasoned sketch rather than a blank page. Nothing here is compiled by
iotakt's `lakefile.lean`; it is reference material that travels with the
repository.

## Contents

| File | What it is |
|------|------------|
| `HANDOFF.md` | **Start here.** The authoritative handoff: iotakt's design, the exact surface jemmet consumes, its limits/gotchas, and the direction + milestones for jemmet. |
| `prototype/Jemmet.lean` | A prototype jemmet server (`Config`, `serveConnection` keep-alive loop, `run` driver) built entirely on `Iotakt.Server`. |
| `prototype/JemmetDemo.lean` | A runnable demo: routes, request bodies, keep-alive. |
| `design-notes.md` | The design behind the prototype, the iotakt/jemmet boundary, and suggested first steps. |

## Related iotakt docs (these *do* belong to iotakt)

- `docs/src/jemmet-handoff.md` — the `Iotakt.Server` handoff surface jemmet
  consumes (re-exports + abbrevs).
- `docs/src/keep-alive-and-consumers.md` — the iotakt building blocks
  (`readFromBuffer`, size limits) and the consumer pattern.
- `examples/ReferenceServer.lean` — a minimal consumer example kept in
  iotakt to prove the handoff surface is sufficient.

## How to adopt

1. Start a new `jemmet` project with iotakt as a dependency.
2. Copy `prototype/*.lean` into it and build against `Iotakt.Server`.
3. Grow it per `design-notes.md` (shutdown loop, handler abstraction,
   streaming responses, TLS boundary).
