# RFC 061 — Architect Review Request: package-split design blocked by a Lake namespace constraint

**To:** Architect
**From:** iotakt implementation
**Re:** RFC 061 (Model/Bridge package split) — the approved design is not buildable; a direction decision is needed
**Status:** Open question — implementation paused pending decision
**Toolchain:** Lean 4.15.0 / Lake 5.0.0
**iotakt version at investigation:** v0.13.4-dev (pre-1.0)

---

## 1. Purpose

RFC 061 was approved to split iotakt into a Henret-free **model** package and a
**bridge** (runtime) package, so that a model-only downstream consumer can resolve
iotakt without Henret entering its dependency graph. During implementation the
model half was achieved, but the bridge half cannot be built: **two Lake packages
cannot both contribute modules to the same `Iotakt.*` namespace when one depends on
the other.** This blocks the approved design as specified.

This memo states the background, the finding and the evidence behind it, and the
options as currently understood, so the architect can choose the direction. No
recommendation is offered; the options are presented with their tradeoffs only.

---

## 2. Background

### 2.1 The stack and iotakt's place in it

iotakt is a Lean 4 non-blocking I/O / socket-readiness boundary library. It sits
between an HTTP edge server (`jemmet`) above and an actor/scheduler runtime
(`henret`) below:

```
jemmet (HTTP)  →  iotakt (I/O)  →  henret (actors/scheduler)
```

iotakt is pre-1.0 (v0.13.4-dev). Its current single Lake package, `iotakt`, builds:

- a **pure model** (`Iotakt.Model.*`), a stable public API surface (`Iotakt.Api`),
  a deterministic **fake poller** (`Iotakt.Fake.*`), and a machine-checked **proof
  corpus** (`Iotakt.Proofs`, 77 theorems, 0 `sorry`/axiom) — **none of which import
  Henret**;
- a **Henret bridge** (`Iotakt.Bridge.*`) and runtime/native layers
  (`Iotakt.Native.*`, `Iotakt.Driver`, `Iotakt.Loop`, `Iotakt.Server`,
  `Iotakt.Http`/`Router`/`Chunked`/… HTTP stand-ins) — **which do import Henret
  and/or require the native C epoll backend**.

The single package carries an **unconditional, package-level `require henret`**.

### 2.2 What RFC 061 set out to fix

jemmet's verified core binds only to iotakt's model surface (`Iotakt.Api` /
`Iotakt.Model`) through its own effect seam; that surface imports no Henret at the
source level. However, **Lake resolves the entire dependency graph at configuration
time, regardless of which modules a consumer actually builds.** This was confirmed
empirically (jemmet integration question Q2): a throwaway consumer that requires
only `iotakt` and imports only `Iotakt.Api` still triggers
`cloning https://github.com/nabbisen/henret` and lists `henret` in its own
`lake-manifest.json`. A model-only consumer therefore cannot resolve iotakt without
materializing Henret today.

RFC 061's goal, stated precisely:

> A model-only consumer can resolve and build the iotakt model surface with **no
> Henret dependency present in its graph** (no clone, not listed in its manifest),
> while the full runtime path is unchanged for consumers that need it, and public
> module import paths remain stable.

### 2.3 The approved design

Two Lake packages, in one repository, both under the existing `Iotakt.*` namespace:

- `iotakt` — **model** package: `Iotakt.Model.*`, `Iotakt.Api`, `Iotakt.Fake.*`,
  `Iotakt.Proofs`, and the `Iotakt` umbrella. No `require henret`, no native C.
- `iotakt-bridge` — **runtime** package: `Iotakt.Bridge.*`, `Iotakt.Native.*`,
  `Iotakt.Server`, the HTTP stand-ins, and the native `extern_lib`. Depends on the
  model package **and** on Henret.

Module import paths unchanged; full-stack consumers migrate `require iotakt` →
`require iotakt-bridge`. The split was chosen over a config-gated single package
(see Option A below), which RFC 061 had considered and rejected as awkward.

---

## 3. The finding

### 3.1 The model half works

The model package was implemented and **builds standalone, Henret-free**: 16 build
jobs, and its `lake-manifest.json` lists **zero** dependency packages — Henret is
absent, no GitHub clone occurs, no C toolchain is required. The primary RFC 061
goal (a Henret-free model a downstream can resolve) is demonstrably achievable.

### 3.2 The bridge half does not build

With the model split out into its own package and the runtime left in
`iotakt-bridge` (depending on the model + Henret), the bridge **cannot compile its
own modules**. Building the native library alone fails:

```
✖ Building Iotakt.Native.Io
error: Iotakt/Native/Io.lean:1:0: object file
  './model/.lake/build/lib/Iotakt/Native/Errno.olean'
  of module Iotakt.Native.Errno does not exist
```

`Iotakt.Native.Io` imports `Iotakt.Native.Errno`. Both are built by the **bridge**
package (their oleans are produced under the *bridge's* build directory). But when
`Io` is compiled, Lake/Lean look for `Errno` in the **model** package's build
directory and fail. The same happens for `Iotakt.Bridge.Driver` →
`Iotakt.Bridge.Message`.

In other words: once the model package "owns" the `Iotakt` namespace root (it
provides `Iotakt.Model.*`, `Iotakt.Api`, and the `Iotakt` umbrella), **every**
`Iotakt.*` import — including the bridge's references to its *own* sibling modules —
resolves to the model package's build directory. The bridge's own modules, built
into the bridge's directory, are shadowed and not found.

### 3.3 The finding is fundamental, not incidental

Two falsification tests were run to rule out simpler explanations:

1. **Lib naming.** The model's library was renamed off `Iotakt` (to `IotaktModel`,
   keeping identical globs) so that no library is literally named for the namespace
   root. **No effect** — the bridge still resolves its own modules to the model
   package.
2. **Source-directory overlap.** The model package was moved entirely outside the
   bridge's source tree (to a sibling directory, so the bridge's source root no
   longer physically contains the model). **No effect** — same failure.

The conclusion supported by the evidence: in this Lake/Lean version, **a package
cannot add modules to a namespace whose root is owned by one of its dependencies.**
The model and bridge cannot both live under `Iotakt.*` across a dependency edge.

### 3.4 Limits of this finding

I did not find a Lake mechanism (library `roots`/`globs` configuration, an
"extend-namespace" facility, an import-path override, or similar) that lets two
packages share a namespace across a dependency edge. If such a mechanism exists and
I have missed it, the originally approved split would stand unchanged and none of
the options below would be necessary. This is the first thing worth checking.

---

## 4. Options (presented without recommendation)

All options below deliver, or decline to deliver, the same target: a model-only
consumer resolving iotakt with Henret absent from its graph. Each is annotated with
what it delivers, its costs, its risks, and my confidence level (since not all have
been built end-to-end).

### Option A — Config-gated single package

Keep a single `iotakt` package (no namespace split, so the runtime builds exactly
as it does today). Make `require henret` and the bridge/native libraries
**conditional** on a Lake configuration value, e.g.:

```lean
meta if (get_config? `model_only).isNone then
  require henret from git "…" @ "…"
-- and define the bridge/native lean_libs only in the same branch
```

A model-only consumer resolves with `-K model_only` (Lake `-K` options are
workspace-global, so a dependency's lakefile observes them), which omits the Henret
require from resolution.

- **Delivers:** Henret-free resolution for consumers who pass the flag.
- **Costs:** none structurally — no module renames, no package split; the runtime
  builds unchanged.
- **Risks / costs of note:**
  - The consumer must pass the flag **on every resolution** (the "easy to forget /
    misuse" concern RFC 061 raised when it rejected this approach). A consumer who
    omits the flag silently gets Henret back in their graph.
  - Conditional `require` and conditional library definitions make the lakefile
    logic harder to read and reason about.
  - Model and bridge remain one package — no enforced boundary.
- **Confidence:** the conditional-require mechanism is documented Lake behavior, but
  I have **not** empirically verified end-to-end that a consumer's manifest ends up
  Henret-free under `-K model_only`. This can be validated on request.
- **Note:** RFC 061 explicitly evaluated and rejected this option. The new
  information is that the package split it preferred is not buildable, which changes
  the comparison.

### Option B — Two packages, runtime under a distinct namespace

`iotakt` = model package keeping `Iotakt.*` (`Iotakt.Model/Api/Fake/Proofs` +
umbrella, Henret-free). `iotakt-bridge` = runtime package whose modules move to a
**new top-level namespace** (for example `IotaktRT.*`): `Iotakt.Bridge.*` →
`IotaktRT.Bridge.*`, `Iotakt.Native.*` → `IotaktRT.Native.*`, `Iotakt.Server` →
`IotaktRT.Server`, and so on. The bridge still imports the model's `Iotakt.*`
modules across the dependency edge (that direction works); it just no longer adds
its own modules under `Iotakt.*`. Distinct namespaces do not collide, so both
packages build.

- **Delivers:** a genuine Henret-free model package that consumers `require`
  directly (no flag); both packages build.
- **Costs:** renames ~19 runtime modules plus all their cross-imports and the
  example/test executables. Mechanical but broad. Contradicts RFC 061's stated
  non-goal of "no module renames" — for the **runtime** modules only.
- **Risks / costs of note:**
  - Any consumer of the runtime namespace must update imports. **jemmet is not such
    a consumer** — it binds to `Iotakt.Api`/`Iotakt.Model`, which are unchanged — so
    jemmet is unaffected. The only current consumer of the runtime namespace is
    iotakt's own examples/tests.
  - The model surface (`Iotakt.*`) stays stable.
- **Confidence:** high that it builds (distinct namespaces do not share a root), but
  the renamed tree has **not** been built end-to-end. Can be prototyped on request.

### Option C — Status quo (decline the split)

Keep the single package with an unconditional `require henret`; document the Lake
limitation; accept that model-only consumers continue to materialize Henret at
resolution time (the Q2 behavior).

- **Delivers:** nothing toward the goal.
- **Costs:** none; zero change/risk.
- **Note:** jemmet's confirmed root-override (Q1) lets jemmet control *where* Henret
  comes from (a vendored path instead of the git clone), but it does **not** make
  Henret absent from jemmet's graph — Henret is still resolved, just vendored. So
  this option does not achieve Henret-free resolution; it only documents that we are
  not pursuing it.

### Option D — Flip the namespace (mentioned for completeness)

The mirror of Option B: the runtime keeps `Iotakt.*` (unchanged) and the **model**
moves to a distinct namespace (e.g. `IotaktModel.*`). Both packages build, same as
B. The difference is **who bears the rename**: here the model surface changes, so
**jemmet would have to update its imports** (`Iotakt.Api` → `IotaktModel.Api`,
etc.). This shifts churn onto the consumer the RFC is meant to serve, and onto the
model surface that the rest of the stack treats as stable. Included only so the
option space is complete.

---

## 5. Facts bearing on the decision

- iotakt is **pre-1.0**; module-path and package-name changes are cheapest now.
- The **only** consumer is jemmet, currently unreleased, and it binds to the
  **model** surface (`Iotakt.Api`/`Iotakt.Model`), not the runtime namespace.
- The **proof corpus** (77 theorems, 0 `sorry`/axiom) and the CI gate must be
  preserved across whichever option is chosen; the corpus is Henret-free except one
  theorem (`inject_ok_of_mailbox`) that reasons about `Henret.step` and lives with
  the bridge.
- Henret is pinned at commit `63f10f48…` (the commit that tag `0.34.0` dereferences
  to; upstream recently re-created `0.34.0` as an *annotated* tag, which changed
  what `@ "0.34.0"` records in the manifest — the commit pin keeps the recorded rev
  stable). This is orthogonal to the namespace question but is part of the same
  release.
- The model-package implementation already exists and is reusable: under Option A as
  the (already Henret-free) model modules in the single package; under Option B as
  the model package verbatim.

---

## 6. Decision requested

Which direction should iotakt take to achieve Henret-free model resolution, given
that the approved two-package split under a shared `Iotakt.*` namespace is not
buildable?

- **A** — config-gated single package (flag-driven; lowest churn; consumer carries a
  resolution-time flag),
- **B** — two packages with the runtime under a distinct namespace (clean boundary +
  flagless Henret-free model package; renames the runtime module paths),
- **C** — status quo (do not pursue Henret-free resolution),
- **D** — flip the namespace (shifts the rename onto the model surface / jemmet),
- **or** — confirm a Lake mechanism for cross-package namespace sharing that would
  let the original split stand unchanged.

On request I can empirically validate Option A (does a consumer's manifest come out
Henret-free under the flag?) or prototype Option B (build the renamed runtime
tree), before any direction is committed.

---

## Appendix — evidence and environment

**Exact failure (bridge building its own native lib):**

```
✖ Building Iotakt.Native.Io
error: Iotakt/Native/Io.lean:1:0: object file
  './model/.lake/build/lib/Iotakt/Native/Errno.olean'
  of module Iotakt.Native.Errno does not exist
error: Lean exited with code 1
```

**Falsification tests run:**

1. Renamed the model library `Iotakt` → `IotaktModel` (identical globs) — failure
   persists.
2. Moved the model package outside the bridge's source tree (sibling directory) —
   failure persists.

**Model-only build (works):** 16 jobs; model `lake-manifest.json` lists zero
dependency packages (Henret absent; no clone; no C toolchain).

**Versions:** Lean 4.15.0, Lake 5.0.0.

**Environment note (not a design factor):** during this investigation the build
container reset, wiping the working tree and the Lean toolchain. The tree was
restored from the last release archive; the toolchain had to be sideloaded from
GitHub because the standard toolchain host `releases.lean-lang.org` is not reachable
through the build proxy (only the singular `release.lean-lang.org` is allowlisted).
Builds are reproducible once the toolchain is present. This does not affect the
namespace finding, which is deterministic.
