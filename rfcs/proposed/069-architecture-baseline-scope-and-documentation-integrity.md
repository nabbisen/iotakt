# RFC 069 — Architecture baseline, scope, and documentation integrity

**Status.** Proposed — release-blocking design/documentation remediation
**Tracks.** Architecture review B6; Go evidence 7 and 8.
**Touches.** Requirements, external design, README, roadmap, proof matrix, API docs, RFC lifecycle/index checks, HTTP/framing module ownership, handoff regeneration.

## Summary

Rebaseline the durable architecture around the implemented two-package design,
decide the ownership of HTTP/framing convenience modules, and make documentation and
RFC lifecycle checks describe the actual tree. Historical evidence remains preserved
but is labeled as historical.

## Goals

- Approve a current requirements and external-design baseline.
- Store that approved release truth at tracked canonical paths
  `docs/src/requirements.md` and `docs/src/external-design.md`.
- Decide whether HTTP/router/request-body/server modules move to examples or a
  consumer package, or formally become supported iotakt runtime scope.
- Repair all build/import/version instructions for `Iotakt` and `IotaktRuntime`.
- Replace stale roadmap and RFC-index state with generated/verifiable truth.
- Strengthen RFC checks for every lifecycle folder, one truthful status field, and
  resolvable Markdown links.
- Regenerate downstream handoff material only after gates pass.

## Non-goals

- Do not delete historical RFCs, changelog entries, or handoff evidence.
- Do not use documentation edits to waive RFCs 064–068 technical requirements.
- Do not expand protocol scope implicitly.

## Required architecture decisions

### Two-package baseline

The baseline names the root `iotakt` package (`Iotakt.*`) as pure/model-only and the
`iotakt-runtime` package (`IotaktRuntime.*`) as the Henret/native layer. Commands,
dependency pins, public surfaces, and proof boundaries must match the current files.

The approved candidate requirements and external design migrate to
`docs/src/requirements.md` and `docs/src/external-design.md`. Approval records their
digests. After migration, `.git-exclude/specs/` remains historical review input only
and cannot be cited as current release truth. The canonical files must be tracked,
linked from the mdbook/README as appropriate, and included in RFC 068's release
manifest.

### HTTP/framing boundary

Choose and record one option:

1. move HTTP, router, request-body, and server stand-ins to examples/a separate
   consumer package, preserving iotakt's protocol-neutral requirements; or
2. expand the project scope explicitly, including support ownership, security
   requirements, compatibility status, and proof/test classification.

No-Go remains until this is an explicit approved decision.

Analysis starts in R0 with a module/API/support inventory. The owner and scope option
must be decided by the R2 exit so required moves or support work can be scheduled.
R4 publishes the already-recorded decision in the canonical baseline; it does not
defer the ownership choice until the end of requalification.

## Documentation work packages

1. Requirements/external-design rebaseline and status approval.
2. README quick start and downstream compile snippets.
3. Proof/trust/test matrix and API stability/current namespace audit.
4. One current roadmap; history delegates to CHANGELOG and implemented RFCs.
5. RFC index rebuilt from actual folders.
6. RFC checker upgraded for folder/status agreement, unique status, complete index,
   unique numbering, and local Markdown target resolution.
7. Current handoff generated after technical and evidence gates pass.

RFC 032 supplies the broader guided-tour work. This RFC owns the release-blocking
truthfulness baseline.

## Test obligations

- Every documented quick-start command is executed from a clean checkout.
- Model-only and runtime downstream probes compile using published instructions.
- RFC checker fails on a synthetic bad status, omitted index entry, duplicate number,
  and broken local link.
- mdbook builds with no missing pages or orphaned intended chapters.
- Repository search finds no current runtime instruction using pre-split namespaces.
- `git ls-files` contains both canonical baseline paths, and the RFC/documentation
  checker verifies that current README/mdbook navigation links to them.
- A retained comparison verifies both canonical files are content-identical to the
  approved candidate baseline, and RFC 068's manifest test verifies their inclusion.

## Security considerations

Documentation defines the claimed trust boundary. Protocol modules, native code, and
release evidence cannot be assigned contradictory ownership. Internal handoff/task
material remains excluded from release archives under RFC 068.

## Dependencies and follow-ups

- Baseline migration design and HTTP/framing analysis begin in R0. Ownership is
  decided by R2; final publication claims wait for RFCs 064–068 and R4.
- RFC 032 follows with user-facing documentation after baseline approval.
- RFC 046 provides the final security-review checklist.
- Blocks RFC 033 and all downstream readiness recommendations.

## Acceptance criteria

- Requirements/external design have an approved current status and package topology
  at the two tracked canonical paths.
- The canonical files are linked, appear in RFC 068's reviewed manifest, and are
  digest/content-identical to the approved candidate baseline.
- HTTP/framing ownership is explicit and reflected in package targets/docs.
- README, matrix, API docs, roadmap, RFC index, and handoffs agree with the tree.
- Strengthened RFC/documentation checks detect the known stale-state classes.
- Clean downstream model/runtime compile probes pass.

## Decision deadlines

- HTTP/framing ownership: analysis begins in R0 and the maintainer records the choice
  by the R2 exit; R4 publishes and implements the resulting baseline changes.
- Handoff form: choose versioned snapshot or validity-window release evidence before
  R4 handoff regeneration begins.
