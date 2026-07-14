# kroopt + jemmet + iotakt — RFC 015 real-socket TLS standup harness

**Purpose.** End-to-end acceptance for RFC 015 §10: a real TCP connection terminated as TLS 1.3 by
kroopt and served as HTTP/1.1 by jemmet, over iotakt's live epoll loop — proving the socket-readiness
boundary with real clients (`curl`/OpenSSL), not a stand-in transport.

**Host.** iotakt hosts the harness (Option A), as a separate example/integration target. iotakt owns the
listener + loop; jemmet brings the TLS adapter (`IotaktTransport`, where the jemmet→iotakt edge lives) and
the HTTP fixture; kroopt brings the TLS engine (`TlsConn`/`Transport`) and the TLS-negative assertions,
carrying no iotakt edge.

**Status.** iotakt's half is staged: `runtime/examples/StandupListener.lean`
(exe `iotakt-standup-listener`) accepts TCP, emits
`newConnection (ListenerKey, connection FdKey)`, and hands both identities to a
consumer seam. jemmet's `IotaktTransport` adapter (kroopt's `TlsConn` inside) and `PlainConn` fixture are wired into this directory
at standup time. No window is set yet — staging does not block on it.

## Boundary / data path

```
TCP accept ──► EventLoop.runStep ──► newConnection (ListenerKey, connection FdKey)
                                              │
                                              ▼  (consumer seam)
                              jemmet IotaktTransport (kroopt TlsConn inside) ── TLS 1.3 handshake + records
                                              │   recvAck / sendAck / enableWrite /
                                              │   disableWrite / closeConnection, keyed on FdKey
                                              ▼
                                    jemmet PlainConn  ── HTTP/1.1 over the uniform conn shape
```

iotakt exposes only the generic non-blocking transport over generation-protected
listener and connection keys plus readiness/loop events. The listener key selects
TLS/plaintext configuration before byte processing; no raw fd is carried by the
stable accepted event. No TLS-aware entry point exists in iotakt (RFC 015 §7).

## 1. Build structure — separate target only (deps point downward)

| Component | Lives in | Depends on |
|---|---|---|
| iotakt listener half | `runtime/examples/StandupListener.lean` (`iotakt-standup-listener`) | **`iotakt-runtime` only** |
| Full standup target | this dir (`runtime/examples/kroopt-jemmet-tls-standup/`) | `iotakt-runtime` + kroopt + jemmet |

The **`iotakt` and `iotakt-runtime` core libraries never depend on kroopt or jemmet** — only the
assembled harness target in this directory reaches up. Every library dependency points downward
(henret → iotakt → kroopt → jemmet); the example target is the single exception, by design, and adds
nothing the proofs depend on.

## 2. Version pinning — released provenance, not floating refs

Every party is pinned by a **released, provenance-verified version plus its sidecar**, not a git ref.
Dev path-overrides are permitted **only** when clearly labeled *dev-only / not release acceptance*.

The acceptance run records this set so any red run is attributable to a known set of builds:

| Party | Pin | Sidecar / hash recorded |
|---|---|---|
| iotakt | released `X.Y.Z` | `iotakt-X.Y.Z.tar.gz` sha256 + `iotakt-X.Y.Z.provenance.json` sha256 |
| kroopt | released `X.Y.Z` | `release-verification.json` sidecar sha256 |
| jemmet | released `X.Y.Z` | sidecar sha256 |
| henret | resolved `X.Y.Z` | manifest/tarball sha256 (from iotakt's provenance `dependencies[]`) |

iotakt's half is intended to be pinned at a released iotakt version (its surface — `Iotakt.Model.*` +
`IotaktRuntime.Loop` — is current as of 0.14.5; the listener example ships from the release that
introduces it). Record the exact versions+hashes in an `acceptance.json` next to the run log.

## 3/4. Ownership of assertions

| Layer | Owner | Owns |
|---|---|---|
| Loop / readiness | **iotakt** | accept → attributed `newConnection`; `recvAck`/`sendAck`/`enableWrite`/`disableWrite`/`closeConnection`; generation-protected listener and connection keys |
| TLS engine + security-negative | **kroopt** | the TLS 1.3 engine (`TlsConn` over the abstract `Transport`); bad TLS never reaches the HTTP path; plaintext to the TLS listener fails cleanly; unsupported negotiation fails at the TLS boundary; ALPN no-overlap matches kroopt policy; SNI route selection happens before any HTTP-path exposure. **Carries no iotakt edge.** |
| iotakt adapter + HTTP fixture | **jemmet** | the `IotaktTransport` adapter — kroopt's `Transport` instantiated over `IotaktRuntime.*`, **where the jemmet→iotakt edge lives**; `PlainConn` boundary; HTTP/1.1 request/response shape; SNI route A/B observable in the response; ALPN `http/1.1` surfaced |

An iotakt-hosted harness does **not** make iotakt the owner of TLS or HTTP failures — see triage below.

## RFC 015 §10 acceptance

- Real `curl` / OpenSSL `s_client` HTTPS through the full stack returns `200 OK`.
- SNI route **A** vs **B** select different cert configs (observable in the served response).
- ALPN `http/1.1` is negotiated and reported to jemmet.
- Negative TLS (bad handshake, plaintext, unsupported group) **never** reaches the HTTP path.

### Curve coverage matrix (kroopt scope)

```text
Baseline standup:                                    x25519 required.
Before kroopt's P-256 advertise-and-test fix lands:  P-256 is NOT a required acceptance dimension.
After it lands:                                      add a P-256 forced-group interop run (kroopt line).
```

secp256r1 is kroopt-internal crypto-capability work, out of scope for this transport standup.

## 5. Failure triage by ownership

When a run goes red, attribute by symptom before assigning to a team:

| Symptom | Owning layer | First check |
|---|---|---|
| No `newConnection`; `curl` connection refused / hangs at TCP | iotakt loop | listener bound? `addListener` returned `ok`? loop being driven (`runStepAuto`)? |
| `newConnection` fires but no bytes flow; readiness stalls after first event | iotakt readiness | missing `recvAck`/`sendAck` ack? `FdKey` generation mismatch (stale fd)? |
| TLS handshake fails / alert; `s_client` can't establish | kroopt TLS | cert/key config, supported groups (x25519), ALPN list, SNI cert selection |
| Plaintext reaches HTTP, or bad TLS yields an HTTP response | kroopt TLS (security-negative) | negative assertions: TLS boundary must reject before HTTP path |
| TLS OK but HTTP response malformed / wrong route | jemmet HTTP | `PlainConn` wiring, HTTP/1.1 shape, SNI route A/B mapping, ALPN surfaced |
| Intermittent / version-specific failure | version-pin mismatch | compare `acceptance.json` versions+hashes against the pinned set; reject dev path-overrides for acceptance |
| Works locally, fails in CI (or vice versa) | environment | OpenSSL/curl version, loopback/port availability, container epoll support |

## Running iotakt's half today (standalone)

```
cd runtime
lake build iotakt-standup-listener
.lake/build/bin/iotakt-standup-listener &
python3 -c "import socket; socket.create_connection(('127.0.0.1',49915)).close()"
# → prints a [handoff] line per connection (ListenerKey + connection FdKey), then exits
```

The standalone seam logs the handoff (no TLS, no HTTP). At standup, swap the seam for jemmet's
`IotaktTransport` attach (kroopt's `TlsConn` inside) and drive `runStepAuto` as the production loop.
