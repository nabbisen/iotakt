# RFC 067 — Fail-closed CI, sanitizer, and clean-checkout evidence

**Status.** Proposed — release-blocking operational remediation
**Tracks.** Architecture review B4 and part of N4; Go evidence 2 and 3.
**Touches.** `scripts/ci.sh`, `scripts/build_native.sh`, GitHub workflows, smoke-test orchestration, retained evidence.

## Summary

Make all required gates fail closed, repair sanitizer compilation/linkage, remove
cache-dependent smoke tests, and demonstrate the behavior from a clean checkout.

## Goals

- Return nonzero when any required CI step fails.
- Prove the gate itself detects an intentionally failing step.
- Build every smoke-test target before running it and retain logs on failure.
- Compile, link, and execute the exact ASan/UBSan-instrumented native objects.
- Remove masked failures and distinguish missing optional developer tools from
  mandatory release tools.
- Produce a clean-checkout release-candidate log.

## Non-goals

- Do not increase the step count merely to signal progress.
- Do not accept `|| true` around security evidence.
- Do not treat cached build products as gate inputs.

## Gate design

The gate records step results for readable summaries but exits nonzero when the
required-failure count is nonzero. A final summary is evidence, not the exit policy.

Each smoke step has this shape:

1. build its exact executable target;
2. start it with deterministic setup;
3. run the client/assertions;
4. stop and reap the process; and
5. preserve stdout/stderr when any action fails.

Fixed ports must be isolated or allocated safely enough for clean CI execution.

## Sanitizer design

`build_native.sh` must use `runtime/native` and runtime build outputs. The workflow
must link the test executable against the instrumented objects produced by that
script, then execute boundary cases from RFC 065. A later ordinary Lake build cannot
stand in for sanitized linkage.

## Implementation sequence

1. Fix gate exit semantics and add an injected-failure self-test mode.
2. Repair and simplify the echo/server smoke orchestration.
3. Correct sanitizer paths and linking; remove `|| true`.
4. Add sanitized boundary cases from RFC 065.
5. Run the full gate in a fresh clone/worktree with empty Lake caches.
6. Store the complete log as review evidence without committing generated build
   artifacts.

## Test obligations

- A deliberate failing step makes `scripts/ci.sh` exit nonzero.
- Every required workflow command propagates failure.
- The echo smoke test succeeds after building its own target in an empty cache.
- Sanitized compilation failure stops the job.
- The executed binary is demonstrably linked to instrumented native objects.
- Clean-checkout gate reaches the declared pass count with exit 0.

## Security considerations

CI evidence is part of the project's trust boundary. Masking sanitizer or test
failure is an evidence-integrity defect. Logs must not contain secrets or arbitrary
payload bytes.

## Dependencies and follow-ups

- Sanitizer acceptance consumes RFC 065 boundary tests.
- Final clean-checkout execution follows RFCs 064–066 implementation.
- Blocks RFC 033 and all release tags.

## Acceptance criteria

- Required failure always produces nonzero process/workflow status.
- The gate self-test demonstrates fail-closed behavior.
- Sanitizer job builds and runs the intended instrumented code.
- A clean-checkout full-gate log reports all required steps passed.
- CI documentation describes actual commands and evidence retention.

## Open questions

- Should orchestration move from shell to a small checked test executable? This is
  allowed if it reduces fixed-port/process-management fragility.
