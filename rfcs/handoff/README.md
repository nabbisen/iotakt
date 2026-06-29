# Cross-team handoff record

Outbound cross-team correspondence and integration seeds, kept as the project's
traceability record (the *why* of cross-project decisions, alongside the RFCs that
record design intent). Organised by counterparty:

| Dir | Counterparty | Contents |
|---|---|---|
| `jemmet/` | jemmet (HTTP/1.1 edge consumer) | integration Q&A, provenance/stack-contract deliveries, and `prototype/` — the seed prototype built on `Iotakt.Server` |
| `kroopt/` | kroopt (TLS sibling) | consumer-review responses |
| `henret/` | henret (upstream runtime) | requests to the upstream (e.g. release sidecars) |
| `self/` | iotakt itself | iotakt's own design/governance correspondence — e.g. RFC architect-review requests |

These are **not** RFCs and carry no lifecycle state of their own; `check-rfcs.sh`
excludes this tree from the `NNN-slug.md` naming rule. They are distinct from the RFC
lifecycle policy's `rfcs/handoffs/NNN-slug/` implementation-handoff convention (RFC 000):
that area, if used, holds per-RFC implementation guides; this `rfcs/handoff/` area holds
cross-team correspondence.

## Convention: a release's own announcement is committed after the cut

Announcement docs that quote a release's archive hash (e.g.
`jemmet/iotakt-<version>-response-*.md`) are committed **after** that release is cut, so
they land in the next release's archive — never their own (a doc cannot correctly state
the hash of the archive it sits in). `scripts/package-release.sh` enforces this: it
refuses to cut version `V` while a `rfcs/handoff/` doc named for `V` is staged.
