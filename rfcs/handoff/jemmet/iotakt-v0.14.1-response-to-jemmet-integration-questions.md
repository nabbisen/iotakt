# iotakt → jemmet — response to integration questions (updated for v0.14.1-dev)

**iotakt:** v0.14.1-dev · **henret** pinned to commit `a5f3f116` (tag `0.34.3`,
annotated-tag dereferenced) · Lean 4.15.0. All answers below were verified against
real Lake behavior in this toolchain, not asserted from documentation.

> **You last integrated against v0.13.3-dev.** Since then, all three of your
> questions have advanced from "answered" to **shipped**:
>
> - **Q1 (offline/vendored henret)** — still works; and for your verified core it is
>   now *moot*, because the model package has **no henret dependency at all**.
> - **Q2 (model-only resolution)** — **resolved.** RFC 061 landed (v0.14.0-dev).
>   A model-only consumer resolves iotakt with **henret entirely absent** from its
>   graph and **no C toolchain**. Your imports are unchanged.
> - **Q3 (release provenance)** — **delivered.** RFC 062 landed (v0.13.4-dev). Every
>   release now ships a verifiable `*.provenance.json`. The v0.14.1-dev one is
>   attached.
>
> One design change you should know about: the package split was implemented as
> **Option B**, which differs from the shape we sketched in the v0.13.3 reply (see
> Q2). The difference does **not** affect your verified core — your model imports
> are identical — but it does rename the *runtime* import namespace, which matters
> only if you import the native reactor.

| # | Status | What you do |
|---|--------|-------------|
| 1 | Offline override works; **moot for the model path** (no henret to override) | Nothing for the model core. For the native path, root-override henret 0.34.3 if vendoring. |
| 2 | **Resolved** — `require iotakt` resolves henret-free | `require iotakt`; keep importing `Iotakt.Api`/`Iotakt.Model.*` (unchanged). |
| 3 | **Delivered** — provenance shipped per release | Verify `iotakt-v0.14.1-dev.provenance.json` against the tarball; follow the `henret_pin` chain link. |

---

## Q1 — Offline consumption without editing iotakt's lakefile

**Still confirmed, and now largely irrelevant for your core.**

The root-override precedence we verified at v0.13.3 is unchanged: a root package
(jemmet) requiring `henret from "<vendored-path>"` wins over any transitive git
require by the same package name, with no GitHub fetch and your vendored tree left
clean. Lake dedups dependencies by package **name**, and the root requirement takes
precedence; git-vs-path does not change that.

What changed is **where henret enters the graph at all**:

- **Your verified core (model-only).** The model package now carries **zero
  dependencies** — henret is not in its graph (see Q2). There is nothing to
  override, vendor, or toggle. Q1 simply does not arise for this path.
- **The native reactor (`iotakt-runtime`).** If you also build the OS event loop,
  that package pulls henret (now commit `a5f3f116` = tag `0.34.3`). The root-override
  still works for it: your `require henret from "<path>"` at the jemmet root wins.
  If you vendor, vendor the **0.34.3** source (`a5f3f116`) to avoid API skew — though
  note henret's `Henret/` Lean source is byte-identical 0.34.0 → 0.34.3, so a 0.34.0
  vendored tree is also source-compatible.

We still do **not** think you need a git-vs-vendored toggle in iotakt; root-override
is the idiomatic mechanism and we re-verified it. The optional `-K
henret_source=vendor|git` switch remains on the table if you want it, but it is not
required for a hermetic build.

---

## Q2 — Model-only resolution — **RESOLVED**

**You can now resolve and build iotakt's model surface with henret absent from your
manifest and no C toolchain. Your imports do not change.**

RFC 061 is implemented and released (v0.14.0-dev). iotakt is now **two Lake
packages**:

| Package | Location | Namespace | Dependencies |
|---------|----------|-----------|--------------|
| `iotakt` (model) | repo **root** | `Iotakt.*` | **none** (henret-free, native-free) |
| `«iotakt-runtime»` | `runtime/` | `IotaktRuntime.*` | `iotakt` + `henret` (`a5f3f116`) + native epoll |

Your verified core depends on the **root** package and keeps the imports it already
has:

```lean
-- jemmet lakefile
require iotakt from git "https://github.com/nabbisen/iotakt" @ "<v0.14.1-dev rev>"

-- jemmet source — UNCHANGED from what you bind today
import Iotakt.Api          -- and Iotakt.Model.*, Iotakt.Fake.*, Iotakt.Proofs
```

Result, certified by iotakt's own CI gate (step 28, "model-only resolution"): a
fresh consumer requiring only `iotakt` and importing only `Iotakt.Api` resolves with
**`henret` absent from its `lake-manifest.json`**, no `cloning …/henret`, and **no C
compiler** invoked. This is the exact inverse of the v0.13.3 reproduction where
henret was materialized regardless.

### The design change vs. our v0.13.3 sketch

At v0.13.3 we proposed keeping the runtime under `Iotakt.*` with `iotakt-bridge`
**re-exporting** the model modules so existing full-stack imports were untouched.
That shared-`Iotakt.*`-root design proved **unbuildable** in Lean 4.15.0 / Lake
5.0.0: a dependent package cannot *extend* a module root that a dependency already
owns (the bridge's imports of its own `Iotakt.Native.*` siblings resolved against the
model package's build dir and failed). Architecture review accepted the finding and
selected **Option B**: keep the stable model surface on `Iotakt.*`, and move the
runtime/bridge/native layer to a **distinct top-level namespace, `IotaktRuntime.*`**.

What this means for you:

- **Model binding — unchanged.** `Iotakt.Api`, `Iotakt.Model.*`, `Iotakt.Fake.*`,
  `Iotakt.Proofs` keep their exact module paths. Your verified core needs **no
  source change** — only the resolution-level win (henret gone).
- **If (and only if) you import the native reactor**, the runtime imports move:
  `import Iotakt.{Bridge,Native,Driver,Loop,Server,Http,Router,Chunked,
  RequestBody,WriteBuffer,Actor,Stats}` → `import IotaktRuntime.{…}`, and the
  require becomes:

  ```lean
  require «iotakt-runtime» from git "https://github.com/nabbisen/iotakt" @ "<rev>" / "runtime"
  import IotaktRuntime.Driver        -- IotaktRuntime.Server, etc.
  ```

  The full rename table is in `docs/src/rfc-061-migration.md` (shipped in the
  tarball). The runtime transitively provides the model, so `import Iotakt.Api`
  continues to work alongside `IotaktRuntime.*`.

The corpus is preserved exactly across the split: **77 theorems** (68 in the model
tree, 9 in the runtime tree — including `inject_ok_of_mailbox`), **0 sorry/admit, 0
axioms**.

---

## Q3 — Release provenance — **DELIVERED**

**Shipped since v0.13.4-dev; the v0.14.1-dev manifest is attached and verifies
against the tarball.**

RFC 062 is implemented. Each release publishes a companion
`iotakt-<version>.provenance.json` **next to** the tarball (not inside it, so it can
carry the archive's own hash), schema `iotakt.provenance/v1`. For **v0.14.1-dev**:

```json
{
  "schema": "iotakt.provenance/v1",
  "version": "v0.14.1-dev",
  "source_archive": { "name": "iotakt-v0.14.1-dev.tar.gz",
                      "sha256": "b02daa20a009b417170d443a76407ffeeb5cfa3faf179b82647705f1b3391319",
                      "bytes": 292460 },
  "lake_manifest_sha256": "344d7023844bd744e13216d83fadcbd7810d3dc448dd312fd611e26f2ac8a39f",
  "lean_toolchain": { "value": "leanprover/lean4:v4.15.0", "sha256": "aff3a276…" },
  "source_tree_sha256": "e2a8011ab49b10d7825d7c0278a156bd634d18c927727a1ae37fe6b0a68b0215",
  "henret_pin": { "type": "git", "rev": "a5f3f1165718449e1ef4cf87607776af5fb6a1dd",
                  "url": "https://github.com/nabbisen/henret" },
  "verification": { "theorems": 77, "sorry": 0, "admit": 0,
                    "project_axioms": 0, "ci_steps": 28,
                    "toolchain": "leanprover/lean4:v4.15.0" }
}
```

Field notes relevant to the chain, updated for the two-package layout:

- **`henret_pin.rev`** is now read from the **runtime** package's manifest (the model
  manifest is dependency-free by design). It is the commit `0.34.3^{}` dereferences
  to — `a5f3f116` — *not* the annotated-tag object SHA. This is your stack chain
  link: **jemmet → iotakt (this manifest) → henret (its RFC 095 release-verification
  manifest)**, down to the toolchain.
- **`source_tree_sha256`** is an order-independent content hash spanning **both**
  trees — `Iotakt/**` and `runtime/IotaktRuntime/**` — plus both lakefiles, both
  `lake-manifest.json` files, and the toolchain. Reproducible across runs,
  independent of tar/gzip metadata.
- **`verification`** is derived by the same greps the CI gate uses, so the manifest
  cannot drift from the certified corpus (enforced by CI step 27).

To verify a release:

```sh
scripts/verify-provenance.sh iotakt-v0.14.1-dev.tar.gz iotakt-v0.14.1-dev.provenance.json
# → RESULT: OK — archive matches provenance manifest
```

Two henret-side developments strengthen the chain end since v0.13.3: henret 0.34.2
added a published release-verification manifest (its RFC 095) and 0.34.3 added a
stack release contract (RFC 096). iotakt's `henret_pin` references the exact commit
those manifests describe, so the full stack is now verifiable link-by-link. If your
stack-release-contract wants additional iotakt fields (detached signature,
per-target hashes), name them and we'll fold them into the `v1` schema.

---

## Note: the henret 0.34.3 bump does not touch your model path

iotakt v0.14.1-dev moved its henret pin 0.34.0 → 0.34.3. This is a docs/release-
process bump on henret's side (consumer-doc hygiene; RFC 095 release manifest; RFC
096 stack contract) — henret's `Henret/` **Lean source is byte-identical** across
0.34.0–0.34.3, so no model, proof, or behavior changed in iotakt. And because your
verified core resolves the **model** package, it never sees henret at any version
regardless.

---

## What to do, concretely

**Verified core (the common case):**

```lean
require iotakt from git "https://github.com/nabbisen/iotakt" @ "<v0.14.1-dev rev>"
-- import Iotakt.Api / Iotakt.Model.* / Iotakt.Fake.* / Iotakt.Proofs  — unchanged
```

No henret in your manifest. No C toolchain. No source changes from v0.13.3.

**If you also run the native reactor:**

```lean
require «iotakt-runtime» from git "https://github.com/nabbisen/iotakt" @ "<rev>" / "runtime"
-- import IotaktRuntime.Driver / IotaktRuntime.Server / …  (was Iotakt.*)
```

henret 0.34.3 is pulled here; root-override it if you vendor.

---

## Summary

| # | v0.13.3 answer | v0.14.1 status |
|---|----------------|----------------|
| 1 | Root path-override works (tested). | Still works; **moot for the model core** — no henret in its graph. |
| 2 | Not possible today; proposed RFC 061. | **Resolved (RFC 061, Option B).** `require iotakt` → henret absent; model imports unchanged; runtime namespace moved to `IotaktRuntime.*`. |
| 3 | Adopting; proposed RFC 062. | **Delivered (RFC 062).** v0.14.1-dev manifest attached; chain link `henret_pin.rev = a5f3f116`. |

Your verified core needs **no source change** to adopt v0.14.1-dev — only the
benefit of a henret-free, C-free resolution. The only migration cost falls on
runtime (native reactor) imports, which move to `IotaktRuntime.*`.
