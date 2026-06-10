# RFC 048: Long-Term Governance, RFC Lifecycle, and Ecosystem Fit

- **Status:** Proposed
- **Intended phase:** continuous
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC defines long-term governance for iotakt so that it remains a small, auditable Lean 4 ecosystem library rather than slowly becoming a general-purpose async runtime.

## 2. Motivation

The greatest architectural risk to iotakt is uncontrolled scope growth. Network libraries naturally attract features: TLS, DNS, HTTP, pooling, timers, thread pools, io_uring, Windows IOCP, metrics, tracing, and more. Some are useful, but most belong above or beside iotakt, not inside it.

## 3. Project identity

Iotakt is:

```text
- a Lean 4 I/O readiness and socket lifecycle boundary library
- a pure model of fd identity, interests, readiness translation, and lifecycle
- an optional native POSIX backend with a tiny C shim
- a Henret bridge for deterministic actor message injection
```

Iotakt is not:

```text
- a Tokio clone
- a general async runtime
- an HTTP server
- a TLS stack
- a DNS resolver
- a thread pool
- a platform abstraction mega-library
```

## 4. RFC lifecycle

Recommended RFC states:

```text
proposed -> accepted -> implemented -> validated -> done
                  \-> deferred
                  \-> rejected
                  \-> superseded
```

An RFC that changes public proof claims, native boundary behavior, or security policy must update the proof/trust/test matrix.

## 5. Admission criteria for new features

A feature may enter iotakt only if at least one is true:

```text
- it is necessary for fd lifecycle safety
- it is necessary for readiness translation correctness
- it is necessary for Henret bridge correctness
- it is necessary for a small native backend contract
- it significantly improves auditability without expanding runtime scope
```

Features should be rejected or moved upward if they are mainly protocol, application, cryptographic, or orchestration features.

## 6. Compatibility policy

Public APIs should be versioned. Experimental APIs should be explicitly marked.

Breaking changes are acceptable before a stable release, but they must be recorded in RFCs and migration notes. After a stable release, compatibility requires stronger discipline.

## 7. Ecosystem fit

Iotakt should be presented as a companion pattern to Henret:

```text
Henret demonstrates executable actor/runtime modeling.
Iotakt demonstrates low-level OS readiness boundary modeling.
Jemmet can demonstrate protocol/server construction above these layers.
```

The educational value is as important as the practical library value.

## 8. Documentation policy

Every release should include:

```text
- README
- guided tour
- architecture document
- proof/trust/test matrix
- native boundary notes
- examples
- RFC index
```

## 9. Acceptance criteria

- RFC lifecycle policy is committed to the repository.
- New RFC template includes proof, security, and non-goal sections.
- Feature proposals explicitly state whether they belong in iotakt, jemmet, or another layer.
- A scope guard review is required before accepting advanced backend or protocol-adjacent features.
