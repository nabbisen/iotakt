import Iotakt.Native.Errno
import Iotakt.Native.Epoll
import Iotakt.Native.Socket
import Iotakt.Native.Io

/-!
# Iotakt.Native

The optional native backend (RFCs 009–012). Requires the `iotakt_native`
static library built from `native/` (run `lake run buildNative` or see
`scripts/build_native.sh` before using this library).

This module is intentionally separate from the pure `Iotakt` core so
that `lake build Iotakt` succeeds without a C toolchain.
-/
