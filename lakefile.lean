import Lake
open Lake DSL

/-- The `iotakt` **model** package (RFC 061, Option B). Owns the `Iotakt.*`
    namespace: the pure model, the deterministic fake poller, the stable public
    API surface, and the machine-checked proof corpus. Henret-free and native-free
    — a model-only consumer (e.g. jemmet's verified core, binding to `Iotakt.Api`/
    `Iotakt.Model`) resolves and builds with no Henret in its graph and no C
    toolchain. The runtime/bridge/native layer lives in the sibling
    `iotakt-runtime` package under the distinct `IotaktRuntime.*` namespace. -/
package iotakt where
  leanOptions := #[⟨`autoImplicit, false⟩]

/-- Core library: pure model, fake poller, and proofs. Henret-free standalone. -/
@[default_target]
lean_lib Iotakt where
  globs := #[.one `Iotakt, .andSubmodules `Iotakt.Model, .andSubmodules `Iotakt.Fake,
             .one `Iotakt.Proofs]

/-- Stable public API surface (RFC 017). -/
lean_lib IotaktApi where
  globs := #[.one `Iotakt.Api]
