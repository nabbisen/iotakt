# iotakt roadmap

This roadmap is the current project schedule. Release history belongs in
[`CHANGELOG.md`](./CHANGELOG.md); design history and decisions belong in
[`rfcs/`](./rfcs/README.md).

## Current decision

**No-Go as of 2026-07-13.** Release publication, v1.0 promotion, and downstream
recommendation of the runtime/native surface are frozen pending remediation and an
independent follow-up architecture/security review.

The pure model and the RFC 061 package split remain useful foundations. The release
freeze applies because effectful fd authority, native buffer bounds, public event
delivery, CI/sanitizer evidence, release packaging, and durable documentation do not
yet meet the project's claimed boundary.

## R0 planning approval

- **Status:** Approved for R1 implementation.
- **Approved by:** Project maintainer.
- **Approval date:** 2026-07-13.
- **Approved planning baseline:** `0929860cbbb76929f548c36ac068b936fe9e6665`.
- **Approval scope:** The roadmap and RFC changes in that baseline; the `.gitignore`
  change in the same commit is outside this planning approval.
- **Release status:** No-Go pending R1–R5 completion and independent
  requalification.

## Scheduling assumptions

- Dates below are planning targets starting 2026-07-13 for one primary maintainer.
- Milestone exit criteria, not dates, authorize progression.
- Security-sensitive changes stay small and reviewable; no release tag is cut during
  R0–R4.
- RFCs 064 and 065 may proceed in parallel because they touch distinct primary
  concerns, but their shared native/API edits must be integrated deliberately.
- The complete 28-step gate is not accepted as release evidence until RFC 067 makes
  it fail closed and a clean-checkout run passes.

Work items use three distinct states:

- **Code complete:** implementation and ordinary tests are complete, but dependent
  release evidence may still be outstanding.
- **Evidence pending:** the implementation is available for dependent work, but a
  required cross-milestone gate has not yet produced retained evidence.
- **Accepted:** every RFC acceptance criterion and required evidence item is complete
  and reviewed. A remediation RFC remains Proposed until this state, then moves to
  Done; code completion alone does not change its lifecycle status.

## Remediation release train

| Milestone | Target window | Theme | Required RFCs | Exit decision |
|---|---|---|---|---|
| R0 | Jul 13–15 | Freeze and approved work plan | 064–069 proposed; roadmap/index repaired | Scope ready for implementation; release remains frozen |
| R1 | Jul 16–24 | Authority and native memory safety | 064, 065 | RFC 064 accepted; RFC 065 code complete with sanitizer evidence explicitly pending R3 |
| R2 | Jul 25–Aug 2 | Event and state integrity | 066, 029 | One delivery path; faulted native transitions remain state-safe |
| R3 | Aug 3–9 | Evidence and supply-chain integrity | 067, 068 | Fail-closed clean gate; real sanitizers; tracked reproducible candidate archive |
| R4 | Aug 10–16 | Architecture and documentation rebaseline | 069, then 032 and 046 review work | Approved scope; current docs/RFC truth; downstream probes pass |
| R5 | Aug 17–23 | Release requalification | 033 | Independent Go/No-Go recorded from complete evidence |

These windows are intentionally short but conditional. A missed exit criterion moves
the following milestone; it does not get waived to preserve a date.

## R0 — Freeze and approved work plan

### Objective

Convert every architecture-review finding into owned RFC work and establish a single
current schedule.

### Work

- Keep release/v1.0/downstream-runtime promotion frozen.
- Review and accept the six focused remediation RFCs:
  - [RFC 064 — Generation-safe effectful fd authority](./rfcs/proposed/064-generation-safe-effectful-fd-authority.md)
  - [RFC 065 — Native buffer bounds and runtime I/O limits](./rfcs/proposed/065-native-buffer-bounds-and-runtime-io-limits.md)
  - [RFC 066 — Authoritative event delivery and state-safe native transitions](./rfcs/proposed/066-authoritative-event-delivery-and-state-safe-native-transitions.md)
  - [RFC 067 — Fail-closed CI, sanitizer, and clean-checkout evidence](./rfcs/proposed/067-fail-closed-ci-sanitizer-and-clean-checkout-evidence.md)
  - [RFC 068 — Tracked-source release packaging and complete provenance](./rfcs/proposed/068-tracked-source-release-packaging-and-complete-provenance.md)
  - [RFC 069 — Architecture baseline, scope, and documentation integrity](./rfcs/proposed/069-architecture-baseline-scope-and-documentation-integrity.md)
- Mark supporting RFCs 029, 032, 033, 043, and 046 with their remediation role.
- Rebuild the RFC index from actual folder state.
- Approve RFC 064's stable `EffectError` result shape and RFC 065's reject-without-I/O
  slice/receive-limit policy before R1 implementation starts.
- Start the HTTP/framing module-boundary inventory and ownership analysis; record the
  ownership decision by the R2 exit for publication in the R4 baseline.

### Exit criteria

- Each blocking finding B1–B6 maps to one primary RFC.
- Each missing Go evidence item maps to an acceptance criterion.
- Dependencies and final sign-off authority are explicit.
- Security-sensitive API policies needed by R1 are decisions, not open questions.
- The HTTP/framing analysis has an owner, inventory, and R2 decision deadline.

## R1 — Authority and native memory safety

### Objective

Close the two critical direct security paths before broader refactoring.

### RFC 064 workstream

- Add a shared checked resolver for all effectful `FdKey` operations.
- Make stale/forged/invalid keys typed no-effect failures.
- Repair `Registry.close` generation preservation and settle visible double-close
  semantics.
- Add proofs and live raw-fd-reuse tests for close, recv/send, and interest changes.

### RFC 065 workstream

- Replace overflow-prone native slice checks with subtraction-safe validation.
- Validate TCP/UDP slices in Lean and C; bound syscall lengths.
- Enforce `DriverConfig.maxReadBytes` in stable runtime receive operations.
- Add boundary tests ready to run under the R3 sanitizer path.
- Generate and review inventories covering every stable native-effect path and every
  receive allocation path; bind each inventory row to its enforcement test.

### Exit criteria

- RFC 064 is accepted: no stable native operation can be reached through a stale,
  forged, negative, or out-of-range key, and its effect-path inventory is complete.
- Stale close cannot alter a newer generation's model/native resource.
- No send/sendto slice can overflow validation.
- RFC 065 is code complete: configured receive bounds are enforced by library code
  and its receive-allocation inventory is complete. Its status remains Proposed with
  sanitizer evidence pending until RFC 067 supplies the R3 instrumented run.
- New proof declarations contain no `sorry`, `admit`, or project `axiom`.

## R2 — Event and state integrity

### Objective

Make the verified decision the only public decision and keep model/kernel state
aligned across failures.

### Work

- Implement RFC 066's authoritative delivered-event result.
- Derive Henret injection and public `.dataReady` only from that result.
- Surface fatal poll errors; prevent pending-state leaks on failed delivery.
- Return structured errors from register/modify/deregister/accept/connect/close and
  commit model transitions only after native success.
- Execute [RFC 029](./rfcs/proposed/029-fault-injection-and-failure-scenario-testing.md)
  scenarios over the new transition seam.
- Split polling/delivery and lifecycle responsibilities out of the oversized loop
  module where needed for reviewability.
- Complete the HTTP/framing ownership analysis begun in R0 and record the selected
  owner/scope option before R2 exits; R4 publishes that decision in the baseline.

### Exit criteria

- Duplicate readiness without acknowledgement produces one public delivery.
- No-interest, stale, unknown, closed, and coalesced events produce none.
- Fatal poll and native-transition failures are observable and state-safe.
- Missing-mailbox/injection failure cannot permanently suppress future delivery.
- Fault-injection matrix covers every state-changing native operation.
- Every RFC 029 matrix row records typed outcome, model state, kernel-resource
  disposition, classification, and a passing test/evidence identifier.
- HTTP/framing module ownership is decided, with any implementation/documentation
  rebaseline work scheduled for R4.

## R3 — Evidence and supply-chain integrity

### Objective

Restore trust in the commands and artifacts used to make release claims.

### RFC 067 workstream

- Make any required step failure exit nonzero.
- Add an injected-failure self-test for the gate.
- Build smoke-test targets explicitly and retain failure logs.
- Repair sanitizer paths/linkage and remove masked failures.
- Run the exact RFC 065 boundary suite against instrumented objects.

### RFC 068 workstream

- Package from the exact tracked tag/tree file set.
- Reject dirty publish inputs and audit archive contents.
- Exclude `.git-exclude/`, build outputs, and all untracked/ignored files by
  construction.
- Make the declared source-tree/provenance hash cover its security-relevant scope.
- Reproduce identical artifacts in two independent clean worktrees.
- Treat RFC 068 implementation as code complete until RFC 067's clean gate produces
  the final candidate manifest/archive/provenance evidence.

### Exit criteria

- Gate self-test exits nonzero under an intentional failure.
- A clean checkout with empty caches passes every required gate.
- ASan/UBSan compile, link, and run the intended native objects.
- Canonical archive contents equal the reviewed tracked-file manifest.
- The tracked manifest contains the approved canonical requirements and external
  design at `docs/src/requirements.md` and `docs/src/external-design.md`.
- Two clean worktrees produce identical canonical archive bytes and matching
  provenance.

## R4 — Architecture and documentation rebaseline

### Objective

Make durable project truth match the corrected implementation and explicitly settle
scope.

### Work

- Approve RFC 069's current requirements and external-design baseline for the
  `Iotakt.*` model / `IotaktRuntime.*` runtime split.
- Migrate the approved candidate baseline into tracked canonical files at
  `docs/src/requirements.md` and `docs/src/external-design.md`; thereafter,
  `.git-exclude/specs/` is historical review input rather than release truth.
- Decide whether HTTP/router/request-body/server stand-ins move to examples or a
  consumer package, or become formally supported scope.
- Repair README, mdbook, API stability, proof/trust/test matrix, and build/import
  instructions.
- Strengthen RFC checks across all lifecycle folders, status fields, index entries,
  numbers, and Markdown links.
- Continue [RFC 032](./rfcs/proposed/032-documentation-examples-and-guided-tour.md)
  after the baseline is approved.
- Apply [RFC 046](./rfcs/proposed/046-security-review-playbook-and-native-audit-checklist.md)
  to the remediated native/model boundary.

### Exit criteria

- Requirements/external design have a current approved status and topology in the
  two tracked canonical paths, are linked from the documentation, and are included
  in RFC 068's reviewed release manifest.
- The canonical tracked files are content-identical to the approved candidate
  baseline, as demonstrated by retained digest/comparison evidence.
- Protocol convenience-module ownership and support cost are explicit.
- All documented commands and model/runtime downstream probes pass from clean
  checkouts.
- RFC index and checker agree with every RFC folder/file.
- Proof/trust/test claims cite current names, versions, and observed evidence.

## R5 — Release requalification

### Objective

Decide Go/No-Go from evidence rather than schedule pressure.

### Work

- Execute [RFC 033](./rfcs/proposed/033-release-candidate-evaluation-and-go-no-go-gate.md).
- Assemble the evidence matrix below from clean, retained logs.
- Commission a focused independent architecture/security follow-up review.
- Only after a written Go: choose the next version, prepare release notes, and cut a
  candidate using RFC 068's tracked-source path.

### Required Go evidence

| Evidence | Primary owner RFC |
|---|---|
| Stale/forged keys cause no native effect or cross-generation mutation | 064 |
| Overflow boundaries and receive limits pass under real ASan/UBSan | 065, 067 |
| Clean full gate passes and injected failure exits nonzero | 067 |
| Public delivery respects interest/coalescing/lifecycle and surfaces fatal errors | 066 |
| Native transition fault injection preserves model/kernel correspondence | 066, 029 |
| Tracked manifest excludes ignored/untracked material and reproduces | 068 |
| Approved requirements/design are tracked, linked, baseline-identical, and in the release manifest | 068, 069 |
| Current downstream model/runtime compile probes pass | 069 |
| Approved baseline settles package topology, scope, and public surface | 069 |

### Exit criteria

- RFCs 064–069 satisfy acceptance criteria and have observed evidence.
- RFC 033 checklist is complete.
- Independent review verdict is Go or Accept with no release-blocking findings.
- Maintainer explicitly authorizes the release/version decision.

## Post-Go work

These items do not enter the remediation critical path unless a fixing RFC discovers
that they are required for safety:

- [RFC 043](./rfcs/proposed/043-capability-oriented-fd-handle-api-and-authority-minimization.md): opaque/restricted capabilities after checked `FdKey` effects.
- RFC 021: kqueue native backend.
- RFC 022: `recvInto` optimization.
- RFC 045: broader model-based trace fuzzing/differential replay.
- Full kroopt + jemmet + iotakt TLS standup after the runtime boundary regains Go
  status, unless downstream teams promote it into the release gate.

No post-Go feature work may weaken the authority, buffer, delivery, gate, packaging,
or scope controls established by RFCs 064–069.
