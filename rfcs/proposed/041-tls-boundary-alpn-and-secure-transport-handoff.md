# RFC 041: TLS Boundary, ALPN, and Secure Transport Handoff

- **Status:** Future / boundary clarification
- **Intended phase:** henejt/TLS integration
- **Package:** iotakt RFC v3 continuation
- **Audience:** Lean 4 library maintainers, Henret integrators, native-boundary reviewers, low-level networking implementers

## 1. Summary

This RFC clarifies that TLS, ALPN, certificates, SNI, and secure transport policy are not implemented inside iotakt. It defines the minimal handoff boundaries needed so that henejt or a future TLS layer can use iotakt safely.

## 2. Motivation

A production HTTP server will need TLS. However, adding TLS into iotakt would destroy the clean separation between byte readiness and protocol/security state. iotakt should remain a transport I/O boundary, not a cryptographic protocol stack.

## 3. Boundary principle

```text
iotakt sees:    bytes, fd identity, readiness, EOF, errors
TLS layer sees: handshake state, certificates, ALPN, SNI, encrypted records
henejt sees:    HTTP semantics, routing, request/response lifecycle
```

## 4. Required iotakt properties for TLS consumers

A TLS layer above iotakt requires:

```text
- non-blocking recv and send
- partial write reporting
- EOF reporting distinct from error
- readiness-as-hint semantics
- ability to request read and write interest independently
- no hidden buffering below the TLS layer
```

The existing iotakt design already supports these requirements if implemented strictly.

## 5. TLS handshake workflow above iotakt

```text
1. Accepted TCP connection is registered to a henejt/TLS actor.
2. Actor receives readable/writable readiness messages.
3. Actor calls TLS engine with bytes received from iotakt.
4. TLS engine may produce encrypted output bytes.
5. Actor writes output through iotakt send.
6. Actor updates iotakt interests based on TLS engine's wanted direction.
7. Once handshake completes, henejt HTTP parsing begins over decrypted bytes.
```

## 6. Interest policy for TLS

TLS handshakes commonly require alternating read and write interest. Therefore, iotakt must allow the actor to set interest dynamically.

```lean
structure InterestSet where
  read  : Bool
  write : Bool
```

No TLS-specific interest mode should be added to iotakt.

## 7. Security non-goals

Iotakt does not verify certificates, manage keys, choose cipher suites, implement ALPN, parse SNI, or terminate TLS.

Iotakt documentation must state this clearly to avoid accidental security claims.

## 8. Acceptance criteria

- Documentation includes a TLS handoff diagram.
- Public API supports independent read/write interest updates.
- No TLS names or certificate concepts are introduced into `Iotakt.Model`.
- henejt integration RFCs may depend on this boundary without moving TLS into iotakt.
