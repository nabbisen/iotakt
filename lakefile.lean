import Lake
open Lake DSL

package iotakt where
  -- Lean-only default build (RFC 001): the model, fake poller, and proofs
  -- build with no C compiler and no OS reactor. The optional native epoll
  -- backend (RFC 009-012) lives behind an explicit target.
  leanOptions := #[⟨`autoImplicit, false⟩]

/-- Pinned Henret dependency (RFC 007 bridge layer only).
    For release, pin an exact tag per the Henret handoff:
      require henret from git "https://github.com/nabbisen/henret" @ "v0.6.0"
    During local development we use a path require to the vendored v0.6.0 tree. -/
require henret from "../henret/henret-v0.6.0"

/-- Core library: pure model, fake poller, and proofs.
    Does NOT import Henret — builds standalone (RFC 001 Lean-only core). -/
@[default_target]
lean_lib Iotakt where
  globs := #[.one `Iotakt, .andSubmodules `Iotakt.Model, .andSubmodules `Iotakt.Fake,
             .andSubmodules `Iotakt.Proofs]

/-- Henret bridge library (RFC 007). Imports `Henret.Model`; builds the
    deterministic translation of iotakt events into Henret operations. -/
lean_lib IotaktBridge where
  globs := #[.andSubmodules `Iotakt.Bridge]

/-- Build the native C shim (RFC 009-012) as a static library.
    Requires gcc and Linux headers.  Automatically re-run when
    any C source file in native/ changes. -/
extern_lib iotaktNativeLib (pkg : NPackage _package.name) := do
  let nativeDir   := pkg.dir / "native"
  let leanInclude ← getLeanIncludeDir
  let cFlags := #["-Wall", "-Wextra", "-Werror", "-D_GNU_SOURCE", "-std=c11",
                  "-I" ++ nativeDir.toString, "-I" ++ leanInclude.toString]
  let sourceFiles : Array (String × String) :=
    #[("iotakt_epoll.c",  "iotakt_epoll.o"),
      ("iotakt_socket.c", "iotakt_socket.o"),
      ("iotakt_io.c",     "iotakt_io.o")]
  let oJobs ← sourceFiles.mapM fun (cFile, oFile) => do
    let src    := nativeDir / cFile
    let obj    := pkg.buildDir / "c" / oFile
    let srcJob ← inputFile src false
    buildO obj srcJob cFlags
  buildStaticLib (pkg.buildDir / "lib" / "libiotakt_native.a") oJobs

/-- Native backend library: epoll + sockets + recv/send (RFC 009–012).
    Only builds when `extern_lib iotaktNativeLib` has compiled the C shim. -/
lean_lib IotaktNative where
  globs := #[.one `Iotakt.Native, .andSubmodules `Iotakt.Native]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Deterministic, Lean-only demo: drives the fake poller through the
    bridge and prints/asserts the resulting Henret operation trace. -/
@[default_target]
lean_exe «iotakt-fake-demo» where
  root := `Main

/-- Native integration test: exercises epoll, socket, recv/send against
    the real Linux kernel (requires gcc; Linux only). -/
lean_exe «iotakt-native-test» where
  root := `examples.NativeTest
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.1 integration checkpoint: full driver loop through a Unix socketpair
    (epoll → parse → translate → coalesce → inject → Henret → recv → echo). -/
lean_exe «iotakt-echo-test» where
  root := `examples.EchoTest
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Full native driver integration layer (RFC 007+011+012): nativeStep,
    setupListener, acceptBurst.  Requires both native C shim and Henret. -/
lean_lib IotaktDriver where
  globs := #[.one `Iotakt.Driver]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- RFC §21.4 acceptance criterion: minimal TCP echo server using the
    full iotakt native driver.  Binds to 127.0.0.1:49900. -/
lean_exe «iotakt-echo-server» where
  root := `examples.EchoServer
  extraDepTargets := #[`iotaktNativeLib.static]
