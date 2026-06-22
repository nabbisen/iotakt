# Release Provenance

Every iotakt release publishes a companion provenance manifest
`iotakt-<version>.provenance.json` next to the release tarball, schema
`iotakt.provenance/v1`. It lets a downstream consumer anchor the exact source
they build against and verify the whole dependency stack down to the toolchain.
The format aligns with Henret's RFC 080 release manifest, so a single verifier
generalizes across the stack. (Design: RFC 062.)

## Fields

| Field | Meaning |
|-------|---------|
| `source_archive` | name, `sha256`, and byte size of the release tarball |
| `lake_manifest_sha256` | hash of `lake-manifest.json` (pins the resolved deps) |
| `lean_toolchain` | toolchain string and its `sha256` |
| `source_tree_sha256` | order-independent content hash over `Iotakt/**`, the lakefile, the manifest, and the toolchain — reproducible regardless of archive timestamps |
| `henret_pin` | the exact Henret dependency pin (`inputRev`, resolved `rev`, url) — the chain link to Henret's own provenance |
| `verification` | the certified gate result: `theorems`, `sorry`, `admit`, `project_axioms`, `ci_steps`, toolchain |

The `verification` counts are derived by the same greps the CI gate uses
(`scripts/ci.sh`), so the manifest cannot drift from the certified corpus; a CI
step (`scripts/check-provenance.sh`) enforces this on every run.

## Generating (maintainers)

```bash
scripts/gen-provenance.sh <version> <archive.tar.gz> iotakt-<version>.provenance.json
```

Run at release time against the cut tarball; publish the JSON alongside it.

## Verifying (consumers)

```bash
scripts/verify-provenance.sh iotakt-<version>.tar.gz iotakt-<version>.provenance.json
```

Exit 0 and `RESULT: OK` mean the archive's `sha256` matches the manifest. A
mutated archive yields `RESULT: MISMATCH` and a non-zero exit. To anchor the full
stack, follow `henret_pin.rev` into Henret's RFC 080 manifest for that revision.

## Stack-release-contract

`henret_pin` makes iotakt provenance composable: a consumer (e.g. jemmet) can walk
**jemmet → iotakt (this manifest) → Henret (RFC 080)** and confirm every layer's
source archive, lake manifest, and toolchain hash.
