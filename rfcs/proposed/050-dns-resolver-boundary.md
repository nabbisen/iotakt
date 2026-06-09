---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 050: DNS Resolver Boundary

## Summary

This RFC defines whether and how iotakt should support DNS after v1. The recommended design is not
to embed a full DNS resolver in iotakt. Instead, iotakt may provide a narrow boundary for asynchronous
name resolution workflows while keeping protocol interpretation, caching, policy, and DNSSEC outside
core iotakt.

The preferred post-v1 design is a separate package, tentatively `iotakt-dns` or a henejt-side adapter,
that uses iotakt sockets and Henret actors. Core iotakt should only define enough contracts to avoid
blocking DNS calls from entering the driver loop.

## Motivation

HTTP clients, outbound TCP connections, service discovery, and QUIC experiments often require name
resolution. However, typical system resolver APIs such as `getaddrinfo` may block, depend on libc
resolver state, read system configuration, invoke NSS modules, or perform network I/O internally.
That conflicts with iotakt's explicit non-blocking and auditable-boundary design.

## Goals

- Prevent accidental blocking resolver calls inside iotakt's event loop.
- Define a clean post-v1 boundary for DNS-related work.
- Support future outbound connect workflows without making DNS a v1 blocker.
- Preserve iotakt's role as an I/O readiness library, not a protocol resolver.
- Permit a DNS actor implementation above iotakt using UDP/TCP sockets.

## Non-goals

- No v1 DNS resolver.
- No synchronous `getaddrinfo` wrapper in the core driver path.
- No DNSSEC validation in iotakt core.
- No resolver cache in iotakt core.
- No policy engine for `/etc/resolv.conf`, search domains, hosts files, or NSS.

## Design decision

Core iotakt should adopt this rule:

```text
Core iotakt must never perform potentially blocking name resolution.
```

Post-v1 DNS support may take one of three forms.

### Option A: external blocking resolver worker

A separate native worker thread or process calls system resolver APIs and reports results back as
Henret messages.

Pros:
- Easy to integrate with platform resolver configuration.
- Good compatibility with existing systems.

Cons:
- Introduces threads/processes outside Henret's deterministic driver.
- Harder to model and test.
- Expands trusted code and operational complexity.

### Option B: pure actor DNS client over UDP/TCP

A Lean-level DNS client actor uses iotakt UDP/TCP sockets to query configured resolvers.

Pros:
- Best fit for Henret/iotakt modeling.
- No hidden blocking calls.
- Good deterministic testing with fake poller.

Cons:
- Requires DNS packet implementation.
- System resolver behavior is not automatically inherited.
- DNSSEC and caching are substantial future work.

### Option C: no DNS package, only documentation

iotakt documents that callers must provide IP endpoints.

Pros:
- Keeps iotakt minimal.

Cons:
- Outbound workflows remain inconvenient.

## Recommendation

Adopt Option B as the preferred long-term direction, but keep it outside iotakt core. The package
boundary should be:

```text
iotakt core:
  non-blocking sockets, readiness, fd lifecycle

iotakt-dns or henejt-dns:
  DNS packet parsing, resolver actor, retries, cache, policy
```

## Data model for a future DNS adapter

```lean
structure HostQuery where
  name : String
  familyPreference : FamilyPreference
  timeoutMs : UInt64
  maxAttempts : Nat

inductive HostResolutionResult where
  | addresses : List IpEndpoint -> HostResolutionResult
  | timeout
  | noRecords
  | temporaryFailure
  | permanentFailure
```

These structures should not enter core iotakt unless a later RFC deliberately accepts that expansion.

## Workflow

1. henejt or another application requests resolution from a DNS actor.
2. DNS actor uses iotakt UDP socket support from RFC 049.
3. DNS actor sends query packet to configured resolver.
4. iotakt only reports readiness and transfers bytes.
5. DNS actor parses response and reports result to the requesting actor.

## Architecture gap management

Open gap:

```text
G-DNS-001: Outbound connections require endpoint resolution, but core iotakt does not resolve names.
```

Mitigation:

- v1 APIs accept already-resolved IP endpoints.
- Documentation explicitly rejects blocking resolver calls in iotakt driver code.
- Post-v1 DNS adapter is tracked separately.

## Proof/trust/test classification

PROVEN:

- Core iotakt remains independent of DNS semantics.
- DNS actor tests can be deterministic when using fake UDP poller events.

ASSUMED/TESTED:

- Correctness of DNS packet parsing, if implemented.
- Correct resolver policy behavior, if system configuration is emulated.

OUTSCOPE:

- DNSSEC in core iotakt.
- Global resolver cache correctness in core iotakt.

## Security considerations

- DNS spoofing, cache poisoning, and downgrade risks are not solved by iotakt.
- DNSSEC, DoT, and DoH belong to future resolver packages, not core iotakt.
- Blocking libc resolver calls must be prohibited in the driver loop.

## Acceptance criteria

- The v1 API remains endpoint-based.
- No core iotakt syscall wrapper calls `getaddrinfo` or equivalent blocking APIs.
- A post-v1 DNS package, if created, is actor-based and explicitly outside core iotakt.
