# RFC 066 — Authoritative event delivery and state-safe native transitions

**Status.** Proposed — release-blocking remediation
**Tracks.** Architecture review B3, N1, N2, and part of N4; Go evidence 4 and 5.
**Touches.** `IotaktRuntime.Bridge`, `IotaktRuntime.Driver`, `IotaktRuntime.Loop`, event/result types, fault-injection seams, loop decomposition.

## Summary

Create one authoritative event-delivery pipeline. Actor injection and public
`LoopEvent` output must be derived from the same validated translation and
coalescing decision. Native state transitions must report errors and update the
model only after the kernel transition succeeds, with explicit cleanup for partial
failure.

## Goals

- Remove the independent raw-event-to-`LoopEvent` path.
- Preserve interest, liveness, generation, and coalescing decisions at the stable
  public boundary.
- Make fatal poll errors observable.
- Prevent pending coalescing state from being committed when delivery cannot occur.
- Make register/modify/deregister/accept/connect/close failures state-safe.
- Give external consumers one mode with no retained duplicate Henret messages.
- Define complete readable/writable/terminal acknowledgement and close cleanup.
- Split the oversized event-loop module by responsibility while changing it.

## Non-goals

- Do not add edge-triggered or one-shot semantics.
- Do not add native background threads.
- Do not turn operational traces into application protocol events.

## External design

The bridge returns an authoritative delivered-event record containing the updated
driver/runtime state and the caller-visible outcome. `EventLoop.runStep` consumes
that result; it never reconstructs readiness from the original raw event list.

Operational outcomes distinguish at least:

- delivered readiness;
- coalesced readiness;
- dropped unknown/stale/no-interest/closed/no-mailbox;
- timeout/tick; and
- fatal poll/backend error.

Only delivered readiness becomes `.dataReady`. Fatal errors must be returned in a
typed form that permits the caller to stop or apply policy.

## Authoritative consumer channel decision

The stable external-consumer mode is returned-event authority (Option A from the
accepted jemmet M2C request). In that mode:

- the delivered-event result is the only source of caller-visible I/O events;
- `EventLoop.runStep` returns those events and does not inject a second copy into a
  Henret mailbox;
- connection mailboxes/tasks are not allocated solely for readiness delivery;
- a slow consumer retains at most one modeled pending slot per `FdKey + PendingKind`;
  and
- the per-step returned collection is bounded by configured poll and accept limits.

Henret-mailbox driving, if retained, is a separate explicitly selected internal or
experimental mode. In mailbox mode delivered readiness is injected there and is not
also returned as public `.dataReady`. One `EventLoop` never has two authoritative
readiness sinks.

Both modes consume the same authoritative translation/coalescing result; the sink is
selected only after that decision. Operational traces/counters may be observed in
either mode but cannot independently drive connection state.

## Acknowledgement and terminal policy

Pending kinds remain independent, including readable and writable in the same native
batch. The normative consumer policy is:

| Event | Pending kind | Required consumer action | Ack operation | Readable bytes may coexist? |
|---|---|---|---|---|
| `.readable` | `.readable` | Attempt bounded receive, or deliberately defer while bounded staged input drains | `recvAck` after the attempt | Yes |
| `.writable` | `.writable` | Attempt send; keep or disable write interest according to remaining output | `sendAck`, or `ackReady` when no send is required | Not applicable |
| `.eof` | `.eof` | Drain any co-delivered readable bytes, then close | `ackReady` if retaining; successful close clears all | Yes |
| `.hangup` | `.hangup` | Drain any available bytes permitted by the platform result, then close | `ackReady` if retaining; successful close clears all | Yes |
| `.error e` | `.error` | Record normalized error, drain co-delivered readable bytes if applicable, then close | `ackReady` if retaining; successful close clears all | Yes |

Within one returned batch, readiness for a key is ordered before its terminal
disposition so a consumer can drain already-received bytes before exactly-once close.
Backends may report several terminal flags, but the consumer performs one close.

`recvAck`/`sendAck` clear only their matching slot after the syscall attempt. EINTR
permits an immediate bounded retry before the next poll step; it does not imply that
bytes were consumed. A consumer may defer readable work by leaving its slot pending,
which coalesces duplicate readiness without losing the eventual retry opportunity.

Successful `closeConnection` and `closeListener` atomically clear every pending kind
for that generation. Consumer-event mode has no corresponding mailbox entry. Any
mailbox-mode implementation must remove or invalidate all queued messages for the
closed generation before raw-fd reuse.

## Deadline ownership

Jemmet and similar protocol consumers own phase-specific deadlines and call
`runStep timeoutMs` with their nearest deadline. `idleTimeoutMs = none` disables
iotakt idle reaping. `runStepAuto` is not the supported jemmet deadline API.

No internal path may close a connection after `.newConnection` without returning an
authoritative typed terminal/closed outcome. Capacity shedding before publication is
allowed and recorded as bounded operational evidence rather than a consumer slot.

## Transaction rules

For register, modify, deregister, accept registration, connect registration, and
close:

1. validate the modeled key/transition;
2. attempt the native operation;
3. commit the corresponding model transition only on success; and
4. on partial failure, perform bounded cleanup and return a structured error.

Errors may not be discarded with `let _ <- ...` on stable paths.

If mailbox validation or Henret injection fails, coalescing state must remain
deliverable: validate before setting pending, or roll the pending slot back.

## Implementation sequence

1. Define authoritative delivery and operational error result types.
2. Refactor bridge processing to return delivered events and traces together.
3. Implement returned-event consumer authority with no parallel mailbox injection;
   isolate any mailbox-only mode.
4. Remove `runStep`'s raw-event replay and surface fatal poll errors.
5. Repair pending-state commit ordering around mailbox/injection failures.
6. Add clear-all-pending close semantics and terminal/readiness batch ordering.
7. Introduce state-safe native transition helpers with fault-injection seams.
8. Carry RFC 070 listener identity through accepted outcomes.
9. Split polling/delivery, connection lifecycle, idle policy, and outbound connect
   out of `Loop.lean` where it improves reviewability.
10. Update API stability and consumer migration documentation.

## Proof obligations

- Every public `.dataReady` corresponds to the authoritative delivered translation
  selected for the active sink.
- Coalesced or rejected events produce no public readiness.
- Failed delivery does not leave an unreachable pending slot.
- Consumer-event mode produces no Henret readiness injection or retained mailbox copy.
- Closing a generation clears all of its pending kinds without affecting a newer key.
- Failed modeled/native transitions preserve the pre-operation correspondence.

## Test obligations

- Duplicate readiness without acknowledgement yields one public delivery.
- No-interest, stale, unknown, and closed events yield no public readiness.
- Missing mailbox/injection failure remains deliverable after correction.
- Returned-event mode shows one delivery and zero mailbox growth over a long-lived
  busy connection.
- Same-batch readable/writable and readable/terminal combinations preserve independent
  acknowledgement and the required drain-before-close order.
- EINTR immediate retry and deferred acknowledgement do not lose a wakeup.
- Successful close clears readable, writable, eof, hangup, and error pending slots;
  raw-fd reuse starts with no prior-generation pending/mailbox state.
- Fatal poll failure is observable.
- Fault-injected register/modify/deregister/accept/connect/close failures do not
  leave an active modeled resource with inconsistent kernel state.
- RFC 029's deterministic failure matrix is updated and executed.

## Security considerations

This RFC prevents verification claims from being bypassed by a parallel public
delivery path and prevents kernel/model divergence from granting stale authority or
causing silent denial of service.

## Dependencies and follow-ups

- Depends on RFC 064's checked effect resolution for fd operations.
- Integrates RFC 070 listener attribution, consumer deadline ownership, and listener
  lifecycle.
- Uses RFC 029 for failure-scenario organization.
- Blocks RFC 033 and downstream runtime recommendation.

## Acceptance criteria

- One code path decides both actor injection and public readiness delivery.
- Stable consumer-event mode returns authoritative events with no parallel Henret
  injection; any mailbox mode returns no duplicate public readiness.
- The normative acknowledgement table, EINTR/deferred rules, batch ordering, and
  clear-on-close behavior are implemented and tested.
- Stable native transitions return and preserve structured failure information.
- Required proofs and public-loop/fault-injection tests pass.
- `Loop.lean` responsibilities are reduced enough to keep the security-sensitive
  transition logic independently reviewable.

## Remaining design latitude

Operational drops may be returned in a bounded structured outcome or retained in a
trace/counter channel while only fatal errors enter the main result. They are never
an independent event-consumption channel and cannot weaken the decisions above.
