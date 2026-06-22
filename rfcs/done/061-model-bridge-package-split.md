---
status: done
track: build-modularity
project: iotakt
scope_class: build-restructure
implemented_in: v0.14.0-dev
---

# RFC 061: Model/Bridge Package Split for Henret-Free Model Resolution

**Status.** Implemented (v0.14.0-dev) — accepted design is **Option B** (see the
Amendment below): model package under `Iotakt.*`, runtime package under
`IotaktRuntime.*`.

## Summary

Split the single `iotakt` Lake package into two: a Henret-free **model** package
(`Iotakt.Model`, `Iotakt.Api`, fake poller, proofs) carrying no `require henret`,
and a **bridge** package (`Iotakt.Bridge` + the native epoll backend) that depends
on the model package and on Henret. This lets a model-only consumer resolve iotakt
with Henret entirely absent from the dependency graph, while keeping the native
runtime path unchanged for consumers that need it.

## Amendment (v0.14.0-dev): Accepted Design — Option B

> **This amendment supersedes the original "External Design", "Data Model",
> "Public API Impact", "Open Questions", and "Acceptance Criteria" sections
> below.** Those sections are retained as historical context for the design that
> was attempted and found unbuildable. The accepted, implemented design is the one
> stated here.

### What changed and why

The original design placed **both** packages under the shared `Iotakt.*` module
root: the model package owning `Iotakt.Model.*`/`Iotakt.Api`/…, and the bridge
package *adding* sibling modules `Iotakt.Bridge.*`, `Iotakt.Native.*`,
`Iotakt.Driver`, `Iotakt.Server`, … under that same root while depending on the
model package. Implementation proved this is **not buildable** in Lean 4.15.0 /
Lake 5.0.0: once the model dependency owns the `Iotakt.*` module root, the bridge
package's imports of its *own* sibling modules (e.g. `Iotakt.Native.Io →
Iotakt.Native.Errno`) resolve against the *dependency's* build directory and fail
("object file '…/Errno.olean' … does not exist"). Two falsification tests confirmed
the cause is module-root ownership, not a target-name collision or source-tree
overlap: (a) renaming the model library target off `Iotakt` had no effect; (b)
moving the model package entirely outside the bridge source tree had no effect. No
Lake facility exists for a dependent package to *extend* a dependency-owned module
root. (`lean_lib` roots/globs/srcDir, `require … with`, and package config were all
checked.) **Importing** a dependency's namespace works; **adding to** it does not.

The decision was escalated to architecture review, which accepted the finding and
selected **Option B**: keep the stable model surface under `Iotakt.*`, and move the
entire runtime/bridge/native/server layer to a **distinct top-level namespace,
`IotaktRuntime.*`**. This puts the migration churn on iotakt's own runtime modules
(which have no external production consumer pre-1.0), not on the model surface that
the only known downstream — jemmet's verified core — binds to.

### Accepted layout

```text
iotakt/                          (repo root = the model package, cleanest path
  lakefile.lean                   for model-only consumers)
  package iotakt                  Henret-free, native-free
  Iotakt.lean                     model umbrella
  Iotakt/Model/…                  pure fd/registry/lifecycle/translation/coalescing
  Iotakt/Api.lean                 stable public model API surface
  Iotakt/Fake/…                   deterministic fake poller (no native, no Henret)
  Iotakt/Proofs.lean              the proof corpus over the model
  lake-manifest.json              ZERO dependencies — Henret absent

  runtime/
    lakefile.lean                 package «iotakt-runtime»
    IotaktRuntime.lean            runtime umbrella
    IotaktRuntime/Bridge/…        driver loop + Henret message injection
    IotaktRuntime/Native/…        epoll extern_lib + FFI
    IotaktRuntime/Driver|Loop|SchedConn|Server|Http|Router|Chunked|
                  RequestBody|WriteBuffer|Actor|Stats.lean
    native/, examples/, Main.lean
    require iotakt from ".."       the model package
    require henret … @ <commit>    Henret, commit-pinned
```

Consumer resolution:
- **Model-only** (jemmet verified core): `require iotakt from <repo>` →
  `import Iotakt.Api` / `Iotakt.Model.*`. Henret **absent** from the graph; no C
  toolchain materialized.
- **Full runtime**: `require «iotakt-runtime» from <repo>/runtime` → pulls the
  model package + Henret + native backend; `import IotaktRuntime.Driver` etc.

### Revised non-goals (architect §9.2)

- RFC 061 does **not** preserve old runtime import paths. Full-stack consumers
  migrate `import Iotakt.{Bridge,Native,Driver,Loop,Server,…}` →
  `import IotaktRuntime.{…}` and `require iotakt` → `require «iotakt-runtime»`.
- RFC 061 **does** preserve model import paths: `Iotakt.Api`, `Iotakt.Model.*`,
  `Iotakt.Fake.*`, `Iotakt.Proofs` are unchanged. jemmet is unaffected.
- RFC 061 provides **no** compatibility shims under `Iotakt.Bridge.*`: a shim would
  either reintroduce the shared-root collision or make the model package depend on
  the runtime package. The runtime namespace moves cleanly instead.

### Revised acceptance criteria (architect §9.3) — all met in v0.14.0-dev

- **A.** Model package manifest has no Henret dependency. ✓ (deps: none)
- **B.** A fresh downstream importing only `Iotakt.Api` resolves with Henret absent
  from its manifest and builds. ✓ (`scripts/check-model-only-resolution.sh`)
- **C.** Runtime package builds from a clean checkout. ✓
- **D.** Runtime package imports the model package and Henret explicitly. ✓
  (`iotakt` path + `henret` commit `63f10f48`)
- **E.** No runtime module remains under `Iotakt.*`. ✓ (19 modules moved to
  `IotaktRuntime.*`)
- **F.** All model proofs build. ✓
- **G.** Bridge theorem(s) move to the runtime package and still build. ✓
  (`inject_ok_of_mailbox` in `IotaktRuntime/Bridge/Driver.lean`)
- **H.** Native Linux test builds and runs. ✓
- **I.** Documentation includes an import migration table. ✓
  (`docs/src/rfc-061-migration.md`)

Corpus preserved exactly: **77 theorems** (68 model-tree + 9 runtime-tree),
**0 sorry/admit, 0 axioms**. Full 28-step CI gate green.

### Open questions — resolved

1. **Naming.** `iotakt` = model (keeps the Henret-free identity on the stable
   surface), `iotakt-runtime` = runtime under `IotaktRuntime.*`. The original
   "re-export the model so `Iotakt.*` full-stack imports keep resolving" is dropped:
   re-export across the shared root is exactly what is unbuildable; full-stack
   consumers migrate their runtime imports instead.
2. **Fake poller** lives in the model package (Henret-free, used by model proofs).
   Confirmed.
3. **Thin top-level meta-target** ("`lake build` at root builds everything") is
   **dropped** in favour of *root = model package*: a model-only consumer's
   `require iotakt from <repo>` then resolves the Henret-free package directly with
   no subdirectory path. Full builds run `lake --dir runtime build` (or `cd
   runtime`); CI builds both trees.

## Motivation

The jemmet verified core binds only to `Iotakt.Api`/`Iotakt.Model` through its own
effect seam; that surface imports no Henret at the source level. But Lake resolves
the **entire** dependency graph at configuration time, and iotakt's `require henret`
is unconditional and package-level. We verified empirically (jemmet integration
question Q2) that a consumer requiring only `iotakt` and importing only
`Iotakt.Api` still triggers `cloning https://github.com/nabbisen/henret` and lists
`henret` in its manifest. A model-only consumer therefore cannot resolve iotakt
without materializing Henret today.

This is a build-boundary concern, exactly the case the project's "workspaces"
guideline anticipates: separating module types to improve build boundaries and
modularity. The model is genuinely Henret-free; only the bridge depends on Henret.
The package layout should reflect that so the dependency follows the actual import
graph.

## Goals

- A model-only consumer can resolve and build `Iotakt.Model`/`Iotakt.Api` with no
  Henret dependency present in the graph.
- The bridge + native runtime path is unchanged for consumers that need it.
- The public API and module paths consumers import remain stable (additive change).
- The proof corpus, CI gate, and theorem count are preserved exactly.
- No new trust assumptions; the proof/trust/test matrix is unchanged in substance.

## Non-Goals

- Changing any model, bridge, or native semantics.
- Renaming public modules or types.
- Touching the Henret integration contract or the version pin.
- Resolving the git-vs-vendored question (that is jemmet Q1, already answered:
  root-override works; this RFC is orthogonal).

## External Design

> **Superseded** by the Amendment (Option B) above — this section describes the
> shared-`Iotakt.*`-root design that was found unbuildable. Retained for history.

A Lake **workspace** with two packages:

```text
iotakt/                      (workspace root)
  model/                     package: iotakt  (Henret-free)
    Iotakt/Model/…           pure fd/registry/lifecycle/translation/coalescing
    Iotakt/Api.lean          public model-facing API surface
    Iotakt/Fake/…            deterministic fake poller (no native, no Henret)
    Iotakt/Proofs.lean       the proof corpus over the model
    lakefile.lean            NO `require henret`
  bridge/                    package: iotakt-bridge
    Iotakt/Bridge/…          driver loop + Henret message injection
    native/, Iotakt/Native/… epoll extern_lib + FFI
    Iotakt/Server.lean       EventLoop public API (native runtime path)
    lakefile.lean            `require iotakt` (model) + `require henret` (git/vendored)
```

Consumer resolution:
- **Model-only** (jemmet verified core): `require iotakt from …` → resolves the
  model package alone; Henret absent from the graph.
- **Full runtime**: `require iotakt-bridge from …` → pulls the model package +
  Henret + native backend. `iotakt-bridge` re-exports the model modules so existing
  full-stack imports are unaffected.

The exact partition of files between packages follows the import graph: anything
that does not `import Henret` belongs to the model package; the bridge package owns
everything that does, plus the native `extern_lib`.

## Data Model

Unchanged. No type moves namespaces; `Iotakt.Model.*`, `Iotakt.Api`,
`Iotakt.Bridge.*`, `Iotakt.Server` keep their module paths. Only the Lake package
that *builds* each module changes.

## Public API Impact

Additive. Today's single-package consumers keep working by depending on
`iotakt-bridge` (the superset). New model-only consumers gain the option to depend
on `iotakt` (model) alone. Module import paths are identical in both cases.

A migration note documents: "for the native runtime depend on `iotakt-bridge`; for
the verified model only, depend on `iotakt`."

## Native Boundary Impact

The `extern_lib` C build moves to the bridge package (it is only needed by the
native path). The model package builds with no C toolchain — a strict improvement
for model-only/proof consumers.

## Henret Integration Impact

The `require henret` moves to the bridge package's lakefile, where the only
Henret-importing code lives. The pin (git tag `0.34.0`) and the integration
contract are unchanged.

## Security Considerations

No new data flows, external integrations, or auth logic. The split reduces the
trusted surface for model-only consumers (no Henret, no C toolchain materialized).
Existing controls remain valid; the threat model is unchanged in substance and gains
a smaller model-only attack surface. No re-modeling required.

## Proof Obligations

None new. The proof corpus moves to the model package verbatim (the model proofs
are Henret-free) **except** `inject_ok_of_mailbox`, which reasons about
`Henret.step` and therefore stays in the bridge package (where it lives today).
The theorem count (77), `0 sorry`, `0 axiom`, and matrix-honesty must be preserved;
CI is split per package but the aggregate corpus is identical.

## Test Obligations

- The full 26-step CI gate passes unchanged in aggregate (split across the two
  packages as appropriate).
- A new resolution test: a model-only consumer resolves and builds with **no Henret
  in its manifest** and no GitHub clone (the inverse of the Q2 reproduction).
- The native/integration suites run against the bridge package exactly as today.

## Trust / Assumption Changes

None. The proof/trust/test matrix is unchanged in content; only its physical
location splits between two package CI runs.

## Architecture Gaps

Closes the model-only-resolution gap raised by jemmet (Q2). Introduces a minor
maintenance consideration: two lakefiles and a workspace root to keep in sync;
mitigated by CI building the workspace as a unit.

## Acceptance Criteria

- Workspace with `iotakt` (model, Henret-free) and `iotakt-bridge` packages builds.
- Model-only consumer resolves with Henret absent (verified by a resolution test).
- Full-stack consumer (`iotakt-bridge`) builds and passes the native/integration
  suites unchanged.
- 77 theorems, 0 sorry, 0 axiom, matrix-honesty preserved in aggregate.
- Public module import paths unchanged; migration note published.

## Alternatives Considered

- **Config-gated conditional `require henret`** (`-K with_henret=false` omits the
  require and the bridge `lean_lib`): lighter, no package split, but conditional
  requires in `lakefile.lean` are awkward, the toggle is easy to misuse, and it
  leaves the model and bridge entangled in one package. Acceptable as a stopgap if
  jemmet needs model-only resolution before this RFC lands; not the durable answer.
- **Status quo (single package)**: rejected — forces Henret materialization on every
  consumer regardless of what they build.

## Open Questions

1. Package naming: `iotakt` (model) + `iotakt-bridge`, or `iotakt-model` +
   `iotakt`? Keeping `iotakt` as the bridge/full package minimizes churn for
   existing full-stack consumers; keeping `iotakt` as the model package is cleaner
   for the henret-free identity. Leaning toward `iotakt` = model, `iotakt-bridge` =
   runtime, with `iotakt-bridge` re-exporting the model so full-stack imports of
   `Iotakt.*` keep resolving.
2. Whether the fake poller belongs in the model package (yes — it is Henret-free and
   used by model proofs/tests) or a third test package.
3. Whether to keep a thin top-level `iotakt` meta-target that depends on the bridge
   for convenience, so `lake build` at the root still builds everything.
