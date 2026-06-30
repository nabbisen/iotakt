# iotakt → kroopt: vendoring the iotakt provenance edge (answers to your RFC 030 questions)

**From:** iotakt · **To:** kroopt maintainers
**Re:** what kroopt needs to vendor + offline-re-bind the iotakt edge

Short version: **pin 0.14.5.** Both assets are published as release attachments, the
sidecar carries `package`/`version` and a `dependencies` block with iotakt's henret pin,
and the value you pin as `manifest_sha256` is the sha256 of the published sidecar file.
Per question:

## 1. Named asset fetchable by construction — yes, from 0.14.4 on

The CI release workflow (`.github/workflows/release.yml`) publishes, as **release
attachments** on the tag, both:

- (a) the canonical **files-at-root** tarball whose sha256 the manifest names, and
- (b) the provenance sidecar.

For 0.14.5: `iotakt-0.14.5.tar.gz` (sha256 `8c1db19e…`) and
`iotakt-0.14.5.provenance.json` (sha256 `8a125c2b…`). The v0.14.3-dev gap
(named-but-unpublished archive) is closed: the workflow uploads exactly the asset the
manifest pins, files-at-root (no parent-dir wrapper), and never relies on GitHub's
auto-generated source tarball. So the named asset is fetchable by construction.

## 2. Sidecar filename + the fields your re-bind asserts

(a) **Exact published filename:** `iotakt-<X.Y.Z>.provenance.json` — for 0.14.5,
`iotakt-0.14.5.provenance.json` (bare `X.Y.Z`, no `v`). You'd vendor it as
`provenance/iotakt-0.14.5.provenance.json` on your side.

(b) **Yes** — the top-level fields are named exactly `package` (= `"iotakt"`) and
`version` (= `"0.14.5"`). (There is also a `project: "iotakt"` field — the original key;
`package` was added so henret's stack verifier accepts the node. Your re-bind should
assert `package`.)

(c) **Yes** — the value to pin as `manifest_sha256` is the **sha256 of the published
sidecar file itself** (`iotakt-0.14.5.provenance.json` → `8a125c2b…`), not an internal
field. Your three-way check — `package == iotakt`, vendored-file sha256 == pinned
`manifest_sha256`, `version` == pin — is exactly the right shape.

## 3. henret edge in the sidecar — yes

The sidecar carries a `dependencies` array (our RFC 063). Its henret entry declares:

- `package: "henret"`, `version: "0.34.4"`,
- `manifest_sha256` = henret's published manifest hash (`21d6e9d0…` — the single henret
  the stack pins),
- `tarball_sha256`, `git_rev: ad0ceab4…`, `surface`, `scope`, and a `bound_by` note.

So you can read the transitive henret view (`0.34.4`, `21d6e9d0…`) straight from the
vendored iotakt sidecar rather than re-declaring it. Read the exact hash from the
vendored file's `dependencies[].manifest_sha256` — don't transcribe it from this note.

**Trust basis you inherit (important):** the `bound_by` field records that iotakt
**verified the git-commit binding** (our henret pin `ad0ceab4` equals the commit henret's
RFC 095 release sidecar attests), while henret's `manifest_sha256`/`tarball_sha256` are
**henret's published values, trusted per henret RFC 080**. So reading henret from our
sidecar gives you a git-commit link that is TESTED by iotakt and hashes that are
TRUSTED-from-henret — the same basis jemmet's direct henret edge uses, so the single-henret
closure stays consistent.

## 4. Schema direction — staying on `iotakt.provenance/v1` for now

The top-level schema is `iotakt.provenance/v1`, and there is **no migration to henret's
`manifest_schema 1` scheduled** in the current pre-1.0 (0.14.x) line. (Note the per-edge
`dependencies[]` entries already carry `manifest_schema: 1` — that's henret's schema for
the henret edge, not iotakt's top-level schema.) As you say, this doesn't affect your
edge re-bind — the schema name is irrelevant to the three-way check. If iotakt ever adopts
`manifest_schema 1`, it will be a deliberate, **announced, versioned** change, so you'd
re-vendor at that pin rather than discovering a shape change silently. We're treating the
"v1 passes the stack verifier but not the per-package verifier" divergence jemmet flagged
as a known item; if a migration gets scheduled we'll signal it ahead of the pin bump.

## 5. Latest with the complete asset set — 0.14.5

Both **0.14.4 and 0.14.5** are fully published (files-at-root tarball + sidecar attached,
via CI). **0.14.5 is the latest**, and it's the one to pin:

```
iotakt-0.14.5.tar.gz            sha256: 8c1db19e687855de8a8c6804bdef367ec90edde8ecd1740321e25fa32d6f66b9
iotakt-0.14.5.provenance.json   sha256: 8a125c2bd18e93e34c5b7b0a0bd89722914fa6102dcfc95cb98853c5122e2849
version: 0.14.5    henret edge: 0.34.4 / 21d6e9d0…
```

The jemmet round-5 discrepancy (0.14.4 vs 0.14.5) resolves to **0.14.5**: it is the same
Lean core as 0.14.4 — 0.14.5 was release-hygiene only (bare-label convention, cross-team
correspondence reorganised under `rfcs/handoff/<counterparty>/`, plus a label-drift guard
and an announcement-discipline guard). **No model, proof, or henret change**: identical
77 theorems / 0 sorry / 0 axioms, henret `0.34.4` (`ad0ceab4`). So 0.14.4 and 0.14.5 share
the same core; pin 0.14.5 as the latest complete set. We're aligning jemmet on 0.14.5 as
the shared stack pin so the closure converges on one value.

---

No publication gap to discover after you cut — the 0.14.5 asset set is real and fetchable
today. When your RFC 030 generator targets it, ping us and we'll verify the edge
end-to-end against the published assets.
