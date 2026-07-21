import IotaktRuntime.Native.Errno
import IotaktRuntime.Native.Epoll
import IotaktRuntime.Native.Socket
import IotaktRuntime.Native.Io

/-!
# IotaktRuntime.Native

The optional native backend (RFCs 009–012). Requires the `iotakt_native`
static library built from `native/` (run `lake run buildNative` or see
`scripts/build_native.sh` before using this library).

This module is intentionally separate from the pure `Iotakt` core so
that `lake build Iotakt` succeeds without a C toolchain.

All raw/native effect declarations are deliberately namespaced under
`IotaktRuntime.Native.Unsafe`. Lean imports are transitive and cannot hide these
implementation dependencies from downstream name resolution, so the explicit
namespace is the enforceable warning boundary. Stable consumers use checked
`EventLoop` operations instead.
-/
