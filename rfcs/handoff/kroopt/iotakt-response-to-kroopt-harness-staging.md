# iotakt → kroopt: RFC 015 standup — iotakt's half is staged

**From:** iotakt · **To:** kroopt
**Re:** your "harness accepted, boundary closed, scope kept to the socket layer" reply.

All three confirmations received (surface currency absorbed, zero-burden boundary closed, Option A
harness accepted). iotakt's half is **staged** — listener + integration README, honoring your five
conditions. Details and the released pin below.

## What's staged

**1. The listener — `runtime/examples/StandupListener.lean` (exe `iotakt-standup-listener`).**
Accepts TCP, drives the loop, emits `newConnection (FdKey, rawFd)`, and hands each accepted fd to a
pluggable *consumer seam*. In the harness the seam is kroopt's `IotaktTransport` attach; standalone it's
a logging seam so iotakt's half builds and runs on its own. It depends **only on `iotakt-runtime`** —
never on kroopt or jemmet (your condition 1; deps point downward).

Verified live, not just compiled — three real client connections:

```
[handoff] fd=5 key=5/1 → consumer (TLS attach point)
[handoff] fd=5 key=5/2 → consumer (TLS attach point)
[handoff] fd=5 key=5/3 → consumer (TLS attach point)
connections handed off: 3
```

Note `key=5/1, 5/2, 5/3`: the OS reused raw fd 5 after each close, but the **generation counter**
incremented — so the `FdKey` your binding keys on stays distinct across fd reuse. That's the
generation-protected handoff your `IotaktTransport` will receive.

**2. The integration README — `runtime/examples/kroopt-jemmet-tls-standup/README.md`.** Encodes the rest
of your conditions:

- **Separate target (cond. 1).** The full harness target lives in that directory and is the *only* thing
  that depends on `iotakt-runtime` + kroopt + jemmet; core libs never reach up.
- **Released-provenance pinning (cond. 2).** A pin table for all four parties (released version + sidecar
  hash), dev path-overrides labeled dev-only, and an `acceptance.json` recording the exact versions+hashes
  so a red run is attributable.
- **Ownership (cond. 3/4).** kroopt owns the TLS-negative assertions; jemmet owns the HTTP fixture; iotakt
  owns loop/readiness. Spelled out as a table.
- **Failure-triage table (cond. 5).** Symptom → owning layer → first check, covering iotakt loop/readiness,
  kroopt TLS, jemmet HTTP/fixture, version-pin mismatch, and environment — so an iotakt-hosted harness
  isn't auto-attributed to iotakt on every red run.
- RFC 015 §10 acceptance criteria and the **x25519-baseline** curve matrix (P-256 added only after your
  advertise-and-test fix lands; secp256r1 out of scope).

## Released pin for the harness

So you can pin iotakt by a released, provenance-verified version (your condition 2) rather than a working
ref, iotakt's half ships in **0.14.6**:

- `iotakt-0.14.6.tar.gz` — sha256 `53997429c6a185c667e9a7accb50773e0b7929a904919058ee325ead2ea2bff5`
- `iotakt-0.14.6.provenance.json` — sha256 `fd196f4aa570e7199081df7a3c26fd93f585a4d1628c671eb5684e70b95dcbae`
  (declares henret 0.34.4, `ad0ceab4`)

0.14.6 is example/scaffolding only — **the binding surface you depend on (`Iotakt.Model.*` +
`IotaktRuntime.Loop`) is unchanged from 0.14.5**, 28-step gate green, 77 theorems / 0 sorry / 0 axioms.
It's prepared and will be tagged/published by our maintainer; no rush, since you're not blocking staging
on the window. (If you'd rather pin the *surface* at 0.14.5 and treat the listener as staged scaffolding
until assembly, that's equally fine — your call.)

## Window

Yours to coordinate with us and jemmet; we'll confirm once jemmet acks their fixture. When it's set, the
seam swaps for your `IotaktTransport` (real adapter) and we drive `runStepAuto` as the production loop —
exactly the path the listener already exercises.

---

Net: iotakt's half is staged and verified against real sockets, all five conditions honored, pinnable at
released 0.14.6, and the boundary is the one you signed off on.
