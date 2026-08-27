# Developer Handoff — RFC 070 checked listener close and lifecycle ownership

**Governing RFC.** [RFC 070 — Address-aware listener identity and lifecycle](../../proposed/070-address-aware-listener-identity-and-lifecycle.md)
**Depends on.** [RFC 064](../../done/064-generation-safe-effectful-fd-authority.md) (accepted) ·
[RFC 066](../../proposed/066-authoritative-event-delivery-and-state-safe-native-transitions.md) (in progress)
**Milestone.** R2 — event, listener, and state integrity
**Issued.** 2026-08-27 · **Issued by.** Architect
**Status inheritance.** This companion inherits RFC 070's lifecycle state (Proposed).

## 1. Purpose

Close the last `unreachable` row in the RFC 064 effect inventory by implementing
`EventLoop.closeListener`, and make listener shutdown/destroy ownership coherent and
state-safe. Until this lands, R2 cannot exit and RFC 070 cannot be accepted.

## 2. Background

RFC 064 shipped checked authority for every stable *connection* effect. Listener
lifecycle was deliberately left out of that scope, and RFC 064 recorded
`indirect::EventLoop.closeListener` as `unreachable`, citing RFC 070 as its structural
justification. RFC 064's acceptance text is explicit that this is a loan, not an
exemption: the row "must become `checked-stable` and bind to stale, forged,
invalid-range, wrong-kind, double-close, and raw-fd-reuse tests" before RFC 070 is
accepted.

The address-aware half of RFC 070 is already implemented — `Ipv4Address`,
`BindEndpoint`, `ListenerKey`, `ListenerRecord`, `ListenerError`,
`EventLoop.addListenerAt`, and listener attribution on accept all exist. What remains is
the physical lifecycle.

## 3. Applicable requirements

- RFC 070 §"Transaction and ownership rules", §"Shutdown and destroy", and its test
  obligations and acceptance criteria.
- RFC 064's shared checked resolver and inventory-completeness rule.
- RFC 066 transaction rules: validate → attempt native → commit model only on success →
  bounded cleanup and structured error on partial failure; and "errors may not be
  discarded with `let _ <- ...` on stable paths".
- The API shapes committed to jemmet in
  `rfcs/handoff/jemmet/iotakt-response-to-jemmet-m2c-native-runtime-request.md` §6.

## 4. Defects this handoff must correct

Three are already present in the tree and are in scope:

**D-1 — `unsafeShutdown` discards native errors and never closes listeners in the model.**
`runtime/IotaktRuntime/Loop.lean:515-525` deregisters with `let _ ← …`, closes the fd,
then sets `listeners := []` without ever calling `registry.close` on any listener key. The
model therefore retains live listener entries whose descriptors are gone — precisely the
model/kernel divergence RFC 066 exists to prevent.

**D-2 — `unsafeDestroy` closes listener fds unconditionally and unchecked.**
`runtime/IotaktRuntime/Loop.lean:286-290` iterates `loop.listeners` and closes each with
the truncating `fd32` helper rather than `checkedFd32`, then closes the poller. RFC 070
requires destroy to close **only** the poller handle and to return a typed `notDrained`
error when the loop has not been drained.

**D-3 — no checked listener close exists at all.** There is no path by which a consumer
can close one listener while others keep accepting.

## 5. Change scope

Permitted to change:

- `runtime/IotaktRuntime/Loop.lean` — add `closeListener`; rewrite `unsafeShutdown` and
  `unsafeDestroy` to route through it; the `LoopEvent`/`addListener` conformance renames
  in §7.
- `runtime/IotaktRuntime/Listener.lean` — add the `ListenerError.nativeError` variant and
  any lifecycle error type required by §7.
- `runtime/examples/R2ListenerTest.lean` and the other affected example targets — new
  cases and mechanical updates for renamed constructors.
- `docs/src/native-effect-inventory.tsv` — reclassify the affected rows.
- `docs/src/api-stability.md`, `docs/src/jemmet-handoff.md` — surface documentation.
- `scripts/ci.sh` — expected pass counts only.

## 6. Explicit non-change scope

Do **not** touch, in this unit of work:

- `Iotakt/` — no model change is required; listener authority reuses
  `Registry.resolveEffectKey`, which already accepts an `allowedKinds` list.
- IPv6, ephemeral-port reporting, or any second address family.
- The RFC 066 delivery pipeline beyond carrying `ListenerKey` through accepted events,
  which already works.
- The HTTP/router/request-body/server convenience modules. Their ownership is an
  unresolved R0/R2 decision and is not settled by this work.
- `scripts/build_native.sh`, sanitizer wiring, `package-release.sh`, or the gate's exit
  semantics. Those are RFC 067/068 and must not be pre-empted here.

## 7. Architect decisions — do not re-litigate, do not guess

Five upstream questions sit between the implemented surface, RFC 070's text, RFC 066's
rules, and what jemmet was told. All five are decided here so you do not inherit any of
them. AD-1..AD-3 are conformance defects, AD-4 is now recorded in the RFC, and AD-5
resolves a seam RFC 066 leaves open for listeners.

| ID | Divergence | Decision |
|---|---|---|
| **AD-1** | `ListenerError` lacks the `nativeError (errno : IoErrno)` variant named in RFC 070 and in the jemmet letter. A kernel `EADDRINUSE` currently surfaces as `transitionError (.bindFailed .addressInUse)`. | **Add the variant.** Normalize kernel-reported address conflicts to `nativeError .addressInUse` as RFC 070 requires. Keep `transitionError` for phase-attributed setup failures. |
| **AD-2** | Code has `LoopEvent.dataReady`; RFC 070 and the jemmet letter both specify `ioEvent (connection) (event)`. | **Rename to `ioEvent`.** The accepted RFC is authoritative and jemmet's adapter is being written against it. Mechanical updates to examples/tests are expected and in scope. |
| **AD-3** | RFC 070 and the letter name the endpoint-taking function `addListener`; the code calls it `addListenerAt` and keeps a legacy `Bool`-returning `addListener`. | **Make `addListener` the endpoint-taking function.** Rename the legacy wrapper to an explicitly unsafe/legacy name or delete it if no target needs it. The stable name must mean the stable thing. |
| **AD-4** | `addListenerAt` rejects `port = 0` with `invalidEndpoint`; RFC 070 said nothing about port 0. | **Resolved 2026-08-27 — behavior unchanged.** RFC 070 now records the rule, its rationale, and the matching non-goal (no ephemeral-port binding, no bound-endpoint reporting). Keep the existing rejection, add the test in §9.11, and do not extend it toward port selection. |
| **AD-5** | RFC 066 requires a successful `closeListener` to "atomically clear every pending kind for that generation", but `closeConnection` does not clear coalescing state today and `CoalesceState` has no clear-all-kinds primitive — only per-`PendingKey` `ack`. | **Clear the listener's pending slot using the existing `ack` path; add no model primitive.** A listener registers read interest only, so `.readable` is the only slot it can hold. This satisfies RFC 066 for listeners with no `Iotakt/` change. **Verify the single-kind assumption before relying on it**: if any path can leave a listener key with a writable or terminal pending slot, stop and file a design request rather than improvising a clear-all. |

AD-1 through AD-3 make the code match an accepted RFC; they are conformance, not new
design. AD-4 is recorded in the RFC and needs only its test. AD-5 is bounded on purpose:
it satisfies RFC 066 for listeners without pre-empting the general clear-all-kinds work
that RFC 066 still owns for connections — do not assume that work is done. If you believe any of them is wrong, stop and file a design request — do not
implement a fourth alternative.

## 8. Required implementation

**8.1 `EventLoop.closeListener (loop) (listener : ListenerKey) : IO (Except EffectError EventLoop)`**

Follow the `closeConnection` shape exactly, with `[.listener]` as the allowed kind:

1. `resolveEffect listener [.listener]` — this yields both the registry entry and the
   range-checked `Int32` fd. Use that checked fd; do not re-derive one from `key.raw`.
2. `Unsafe.Epoll.deregister` and decode via `nativeStatus`; on error return the typed
   error, change no model state, and do not close.
3. Close the descriptor exactly once.
4. Remove the `ListenerRecord` from `loop.listeners` — the endpoint mapping must go with
   it, so a later `addListener` on the same endpoint is not rejected as a duplicate.
5. `registry.close listener` to commit the closed model state.
6. Clear the listener's pending readable slot (AD-5), so no coalescing state survives
   the close into a reused raw fd.
7. Return the updated loop.

Unknown, stale, wrong-kind, out-of-range, and already-closed keys must return typed
no-effect errors. A stale listener key must not close a reused raw fd.

**8.2 `unsafeShutdown` (D-1)** — reuse `closeListener` for every listener rather than
open-coding deregister/close, so listeners are closed in the model as well as the kernel.
Propagate structured failure; do not discard results with `let _ ← …`. Decide and document
whether shutdown aborts on the first listener failure or continues and reports an
aggregate — either is acceptable, but the choice must be explicit and tested.

**8.3 `unsafeDestroy` (D-2)** — close **only** the poller handle. Return a typed
`notDrained` lifecycle error when listeners or connections remain, performing no resource
close. Callers run `shutdown` first. Ensure no path can close a listener fd twice across
`closeListener` → `shutdown` → `destroy`.

**8.4 Inventory** — move `indirect::EventLoop.closeListener` from `unreachable` to
`checked-stable`, naming `EventLoop.resolveEffect(listener)` as its resolver and binding
its test IDs. Re-examine the `unsafeShutdown` and `unsafeDestroy` rows: once they route
through checked transitions their justification text no longer matches, and stale
justification is itself an inventory defect. Both checkers must pass.

### 8.5 Expected implementation slices

Four independently reviewable commits, in this order. Do not collapse them: slice 1 is
large and mechanical, and slices 2–4 are security-relevant. Reviewing them together
would hide the latter in the former.

| # | Slice | Contents | Gate expectation |
|---|---|---|---|
| 1 | Conformance renames | AD-1..AD-3 only: `nativeError` variant, `dataReady` → `ioEvent`, `addListener`/legacy wrapper, plus the §10 `Loop.lean` docstring repair. No behavior change. | Full gate green with updated counts |
| 2 | Checked `closeListener` | §8.1 including AD-5, plus the §9.1–9.3 authority/reuse/double-close tests | New tests pass; inventory row still `unreachable` |
| 3 | Lifecycle ownership | §8.2 shutdown and §8.3 destroy, plus §9.7–9.9 | No descriptor growth; no second close |
| 4 | Inventory and docs | §8.4 reclassification and §10 documentation | Both inventory checkers green with **zero** `unreachable` rows |

Stop and report after slice 2 if the authority tests reveal anything about listener
registration that contradicts this handoff.

## 9. Required tests

Use the established convention `RFC070-<TOPIC>-001` (matching `RFC064-AUTH-MATRIX-001`,
`RFC065-LEAN-BOUNDARY-001`). Extend `runtime/examples/R2ListenerTest.lean` for listener
lifecycle and `runtime/examples/V13Test.lean` for authority-matrix cases that belong beside
the existing RFC 064 matrix. Update the expected pass counts in `scripts/ci.sh` in the same
commit as the tests. Bind each ID to its inventory row.

1. Authority matrix for `closeListener`: unknown, stale, forged, negative, out-of-range,
   wrong-kind (connection key passed as listener), and already-closed — each returns the
   typed error and performs **no** native call.
2. Live raw-fd reuse: close a listener, cause the OS to reuse that raw fd, then attempt
   the stale listener close; the new owner must be unaffected.
3. Double close: the second `closeListener` is rejected and issues no second native close.
4. Bind IPv4 loopback, wildcard, and a specified local address.
5. Duplicate endpoint rejected as `duplicateEndpoint`; a kernel conflict normalized to
   `nativeError .addressInUse` (AD-1).
6. Multi-listener attribution: two listeners accepting concurrently; every accepted event
   carries the correct `ListenerKey` and no raw fd.
7. Close one listener while another continues accepting.
8. `closeListener` → `shutdown` → `destroy` → bind again, with no descriptor growth and no
   second close. Assert the fd count before and after.
9. `destroy` on a non-drained loop returns `notDrained` and closes nothing.
10. Fault injection over the RFC 029 seam: deregister failure and close failure each leave
    model and kernel state consistent and produce a structured error.
11. `port = 0` is rejected as `invalidEndpoint` before any socket is created (AD-4).
12. A successful `closeListener` leaves no pending readiness for that generation, and a
    subsequent listener on a reused raw fd starts with no prior-generation pending state
    (AD-5).
13. Closing one listener does not clear another live listener's pending readiness.

## 10. Required documentation updates

- RFC 070 itself: no edit required. The AD-4 amendment has landed; do not modify the RFC.
- `runtime/IotaktRuntime/Loop.lean` module docstring (review 011 N1). Its usage sketch
  currently reads `bytes ← Unsafe.Io.recv key.raw maxBytes` in the readiness branch —
  the stable module teaching raw-fd authority and a bypass of both RFC 065 receive
  checks, contradicting `api-stability.md`. Replace it with `loop.recvAck key maxBytes`.
  AD-2 forces you into these exact lines anyway, since the sketch uses `.dataReady`.
- `docs/src/api-stability.md`: the listener lifecycle contract and the AD-2/AD-3 renames.
- `docs/src/jemmet-handoff.md`: the accepted-event and listener-close surface.
- `docs/src/native-effect-inventory.tsv`: as in §8.4.
- `docs/src/proof-trust-test-matrix.md`: any new theorem, and the test-count claims. Note
  the matrix currently claims its theorem count is "across `Iotakt/`" when the counted
  scope is `Iotakt/` **plus** `runtime/IotaktRuntime/`; if you touch that line, correct
  the scope wording rather than propagating it.

## 11. Prohibited shortcuts

- No compatibility shim that preserves unchecked listener authority on the stable path.
- No raw-fd escape hatch for listeners, and no raw fd in any stable accepted event.
- No `let _ ← …` on a stable native transition.
- No use of `fd32` for a stable effect — `resolveEffect`/`checkedFd32` only.
- No widening of `closeListener` to accept connection keys "for convenience".
- Do not disable, skip, or adjust an existing test to make a count line up.
- Do not mark RFC 070 Implemented or move the file. Lifecycle moves are the architect's.

## 12. Compatibility and security constraints

AD-2 and AD-3 are breaking renames on a surface that is already breaking under R2, and no
consumer has been cleared to adopt the runtime — that is why they are acceptable now and
would not be later. Listener identity is security-sensitive because a consumer uses it to
select plaintext versus TLS before parsing untrusted bytes: port comparison and raw-fd
identity are forbidden as identity, error payloads stay bounded enums and normalized
errnos with no peer-controlled text, and partial setup must never publish a listener.

## 13. Known risks

- **Rename blast radius.** AD-2/AD-3 touch many example targets. Land the renames as their
  own commit, separate from the `closeListener` behavior change, so review can separate
  mechanical churn from security-relevant logic.
- **Shutdown aggregate-error choice** (§8.2) is the one place where a reasonable
  implementer could pick either option. If it turns out to affect the public result type,
  stop and ask.
- **Test 2 is environment-sensitive.** Raw-fd reuse needs execution outside a restricted
  syscall sandbox; the existing RFC 064 reuse test is the pattern to copy.

## 14. Required evidence

- Both inventory checkers, both RFC 064 surface probes, and the full gate, with the
  observed pass/fail counts quoted, not summarized.
- The listener and v13 test binaries' actual output counts.
- `git diff --stat` for the range, and a clean `git diff --check`.
- Explicit statement that the gate remains fail-open and that this evidence is
  development-grade until RFC 067 lands. Do not describe any of it as release evidence.
- No ASan/UBSan claim. That is RFC 067/R3's.

Run and quote all of:

```bash
export PATH="$HOME/.elan/bin:$PATH"
python3 scripts/check-native-effect-inventory.py          # must report 0 unreachable
python3 scripts/check-receive-allocation-inventory.py
bash scripts/check-runtime-typed-surface.sh
bash scripts/check-runtime-unsafe-surface.sh
lake --dir runtime build iotakt-v13-test iotakt-r2-listener-test iotakt-native-test
runtime/.lake/build/bin/iotakt-r2-listener-test
runtime/.lake/build/bin/iotakt-v13-test
bash scripts/ci.sh                                        # read the printed count, not $?
git diff --check <base>..<head>
```

The runtime build needs `LAKE_PKG_URL_MAP='{"henret":"https://github.com/nabbisen/henret"}'`
if Henret is not already resolved under `runtime/.lake/packages/`. The raw-fd-reuse cases
(§9.2, §9.12) need execution outside a restricted syscall sandbox.

## 15. Required review-request format

Submit to `.git-exclude/qa/to/architect/NNN-rfc070-listener-lifecycle-review-request-<date>.md`
following the structure of request 011: summary, scope followed, files changed, design
decisions and assumptions, tests and gates run with observed results, generated artifacts,
known limitations, explicit reviewer decisions requested, suggested independent commands,
and recommended next step.

State explicitly in the request:

1. how each AD-1..AD-3 decision was implemented;
2. the shutdown failure-mode choice from §8.2 and why;
3. every inventory row whose classification or justification changed; and
4. confirmation that release and downstream adoption remain No-Go.

## 16. Acceptance criteria

- `closeListener` exists, is checked, and is exercised by every test in §9.
- The RFC 064 inventory has **no `unreachable` rows** and both checkers pass.
- `shutdown` and `destroy` have one coherent, tested ownership order with no double close
  and no orphaned model state.
- AD-1..AD-3 conformance is complete; AD-4 is untouched.
- No new `sorry`, `admit`, or project `axiom`.
- The surface matches what jemmet was promised, or a correction letter is drafted for the
  maintainer — the two must not silently disagree.
