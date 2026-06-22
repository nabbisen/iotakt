import IotaktRuntime.Bridge
import IotaktRuntime.Driver
import IotaktRuntime.Loop
import IotaktRuntime.Server

/-!
# IotaktRuntime

The Henret/native/runtime layer of iotakt (RFC 061, Option B). Owns the
`IotaktRuntime.*` namespace: the Henret bridge, the native epoll backend, the
event-loop driver, and the HTTP/server stand-ins. Depends on the Henret-free
`iotakt` model package (`Iotakt.Model.*`, `Iotakt.Api`, `Iotakt.Fake.*`) and on
Henret. Model-only consumers depend on `iotakt` and never resolve this package.
-/
