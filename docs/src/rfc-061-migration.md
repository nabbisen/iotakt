# RFC 061 Migration — Model / Runtime Package Split

As of **v0.14.0-dev**, iotakt ships as **two Lake packages** so that a verified,
model-only consumer can resolve iotakt with **Henret entirely absent** from its
dependency graph and **no C toolchain** materialized.

| Package | Namespace | Role | Depends on |
|---------|-----------|------|------------|
| `iotakt` (repo root) | `Iotakt.*` | Pure model, fake poller, stable API, proof corpus. Henret-free, native-free. | — |
| `«iotakt-runtime»` (`runtime/`) | `IotaktRuntime.*` | Henret bridge, native epoll backend, event-loop driver, HTTP/server stand-ins. | `iotakt`, `henret` |

The model surface (`Iotakt.Api`, `Iotakt.Model.*`, `Iotakt.Fake.*`,
`Iotakt.Proofs`) is **unchanged**. Only the runtime/bridge/native layer moved to a
distinct top-level namespace. (See RFC 061, Amendment / Option B, for why a shared
`Iotakt.*` root across two packages is not buildable in Lean 4.15.0 / Lake 5.0.0.)

## If you consume the model only (e.g. a verified core)

No import changes. Depend on the model package — Henret will not appear in your
manifest:

```lean
-- lakefile
require iotakt from git "https://github.com/nabbisen/iotakt" @ "<rev>"

-- source
import Iotakt.Api      -- or Iotakt.Model.*, Iotakt.Fake.*, Iotakt.Proofs
```

## If you consume the native runtime

Point your `require` at the `runtime/` package and update runtime imports from
`Iotakt.*` to `IotaktRuntime.*`:

```lean
-- lakefile  (was: require iotakt …)
require «iotakt-runtime» from git "https://github.com/nabbisen/iotakt" @ "<rev>" / "runtime"

-- source    (was: import Iotakt.Driver, import Iotakt.Server, …)
import IotaktRuntime.Driver
import IotaktRuntime.Server
```

The runtime package transitively provides the model, so `import Iotakt.Api` /
`Iotakt.Model.*` continues to work alongside the `IotaktRuntime.*` imports.

## Import rename table

| Old runtime import (≤ v0.13.x) | New runtime import (≥ v0.14.0-dev) |
|--------------------------------|-------------------------------------|
| `Iotakt.Bridge` | `IotaktRuntime.Bridge` |
| `Iotakt.Bridge.Driver` | `IotaktRuntime.Bridge.Driver` |
| `Iotakt.Bridge.Message` | `IotaktRuntime.Bridge.Message` |
| `Iotakt.Native` | `IotaktRuntime.Native` |
| `Iotakt.Native.Io` | `IotaktRuntime.Native.Io` |
| `Iotakt.Native.Epoll` | `IotaktRuntime.Native.Epoll` |
| `Iotakt.Native.Socket` | `IotaktRuntime.Native.Socket` |
| `Iotakt.Native.Errno` | `IotaktRuntime.Native.Errno` |
| `Iotakt.Driver` | `IotaktRuntime.Driver` |
| `Iotakt.Loop` | `IotaktRuntime.Loop` |
| `Iotakt.SchedConn` | `IotaktRuntime.SchedConn` |
| `Iotakt.Server` | `IotaktRuntime.Server` |
| `Iotakt.Http` | `IotaktRuntime.Http` |
| `Iotakt.Router` | `IotaktRuntime.Router` |
| `Iotakt.Chunked` | `IotaktRuntime.Chunked` |

The module import paths remain those shown above. After RFC 064 remediation, the raw
declarations inside the native modules resolve under
`IotaktRuntime.Native.Unsafe.{Io,Epoll,Socket}` so transitive imports cannot make an
unchecked escape look stable.
| `Iotakt.RequestBody` | `IotaktRuntime.RequestBody` |
| `Iotakt.WriteBuffer` | `IotaktRuntime.WriteBuffer` |
| `Iotakt.Actor` | `IotaktRuntime.Actor` |
| `Iotakt.Stats` | `IotaktRuntime.Stats` |

Model imports — **no change**:

| Import | Status |
|--------|--------|
| `Iotakt.Api` | unchanged |
| `Iotakt.Model` / `Iotakt.Model.*` | unchanged |
| `Iotakt.Fake` / `Iotakt.Fake.*` | unchanged |
| `Iotakt.Proofs` | unchanged |

## Building from a checkout

```sh
lake build                       # builds the model package (root) — Henret-free
lake --dir runtime build         # builds the runtime package — pulls Henret + native
sh scripts/ci.sh                 # full 28-step gate across both trees
```
