# RFC 068 — Tracked-source release packaging and complete provenance

**Status.** Proposed — release-blocking supply-chain remediation
**Tracks.** Architecture review B5; Go evidence 6.
**Touches.** Release packaging, provenance generation/verification, archive audit, dirty-tree policy, release workflow.

## Summary

Build canonical releases from the exact tagged tracked-file set, never from arbitrary
working-directory contents. Expand or rename the source-tree hash so it honestly
covers the security-relevant source identified by the release policy.

## Goals

- Use a deterministic tracked-file manifest for archive inputs.
- Prevent ignored/untracked `.git-exclude/` material and build outputs from entering
  releases.
- Define and enforce a dirty-tree policy.
- Audit archive content before provenance generation and publication.
- Cover native C, build, CI, and release tooling in the security-relevant tree hash,
  or give a narrower hash an honest name and scope.

## Non-goals

- Do not publish internal task, review, or secret material.
- Do not rely on a growing exclusion list as the primary source-selection policy.
- Do not mutate a published tag or archive.

## Packaging design

The packager derives its input from the target revision using one reviewed mechanism:

- `git archive` plus deterministic post-processing; or
- `git ls-files`/tag-tree enumeration feeding a deterministic tar operation.

The revision, file manifest, archive, and provenance sidecar must describe the same
source. Local candidate creation fails on a dirty tree unless an explicit candidate
mode records the exact diff and is never publishable.

## Archive policy

An automated content audit rejects at least:

- `.git-exclude/`;
- `.git/`, `.lake/`, runtime build outputs, generated docs, logs, and temporary files;
- untracked/ignored inputs; and
- files outside the tracked manifest.

Required source and license/provenance files are asserted present.

The reviewed tracked-file manifest must contain the canonical approved architecture
baseline at `docs/src/requirements.md` and `docs/src/external-design.md`. Candidate
creation fails if either path is absent, untracked, or differs from the approved
baseline digest recorded by RFC 069.

## Provenance design

`source_tree_sha256` must either hash all tracked security-relevant source and tooling
that determines the artifact or be renamed to state its selective scope. The manifest
must include the tracked revision and a digest of the release file manifest so the
archive input set can be re-derived.

## Implementation sequence

1. Specify the tracked-file manifest and dirty-tree policy.
2. Replace working-directory staging in `package-release.sh`.
3. Add positive/negative archive-content assertions.
4. Rework the tree hash and provenance schema documentation.
5. Test reproducibility across two clean worktrees at the same tag.
6. Verify local and CI candidate bytes and manifests agree.

## Test obligations

- Ignored `.git-exclude/` fixtures cannot enter the archive.
- An untracked source-like file cannot enter the archive.
- Dirty publish mode fails.
- Two clean worktrees produce byte-identical archives and sidecars.
- Native C and release/CI script changes alter the declared security-relevant hash.
- Archive verification rejects extra, missing, or unexpected files.
- `git ls-files` identifies both canonical baseline files; both occur in the release
  manifest and archive, and their digests equal RFC 069's approved candidate digests.

## Security considerations

Release inputs can contain internal reviews, task notes, or secrets even when Git
ignores them. Selection must be allowlist/tracked-set based. Tests use synthetic
fixtures only and must never inspect or print real secret content.

## Dependencies and follow-ups

- Can be implemented after the release freeze independently of RFCs 064–066.
- The final candidate archive is produced only after RFC 067's clean gate.
- Packaging implementation may be code complete earlier, but final RFC 068 candidate
  evidence remains pending until that clean gate produces and audits the manifest,
  archive, and provenance together.
- Blocks RFC 033 and publication.

## Acceptance criteria

- Canonical archives contain exactly the reviewed tracked-file set for the tag.
- Dirty/untracked local state cannot affect a publishable archive.
- Content audits exclude internal/build material and require expected source.
- The canonical requirements and external design are tracked, present in the reviewed
  manifest/archive, and digest-identical to RFC 069's approved candidate baseline.
- Provenance identifies the complete security-relevant input set honestly.
- Reproducibility is observed across independent clean worktrees.

## Open questions

- Whether to evolve `iotakt.provenance/v1` additively or introduce a versioned schema
  revision must be coordinated with downstream verifiers.
