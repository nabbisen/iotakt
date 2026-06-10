import Lake
open Lake DSL

package iotakt where
  -- Lean-only default build (RFC 001): the model, fake poller, and proofs
  -- build with no C compiler and no OS reactor. The optional native epoll
  -- backend (RFC 009-012) lives behind an explicit target.
  leanOptions := #[⟨`autoImplicit, false⟩]

/-- Pinned Henret dependency (RFC 007 bridge layer only).
    For release, pin an exact tag per the Henret handoff:
      require henret from git "https://github.com/nabbisen/henret" @ "v0.12.1"
    During local development we use a path require to the vendored v0.12.1 tree. -/
require henret from "../henret/henret-v0.12.1"

/-- Core library: pure model, fake poller, and proofs.
    Does NOT import Henret — builds standalone (RFC 001 Lean-only core). -/
@[default_target]
lean_lib Iotakt where
  globs := #[.one `Iotakt, .andSubmodules `Iotakt.Model, .andSubmodules `Iotakt.Fake,
             .andSubmodules `Iotakt.Proofs]

/-- Stable public API surface (RFC 017). Import this instead of internal
    modules for code that needs API stability guarantees. -/
lean_lib IotaktApi where
  globs := #[.one `Iotakt.Api]

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

/-- Multi-connection event loop (v0.2 / RFC 023). Wraps the driver with a
    high-level EventLoop, LoopEvent dispatch, and connection management. -/
lean_lib IotaktLoop where
  globs := #[.one `Iotakt.Loop]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Write buffering for partial-write and wouldBlock handling (v0.4). -/
lean_lib IotaktWriteBuffer where
  globs := #[.one `Iotakt.WriteBuffer]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Minimal HTTP/1.0 parser + response builder (v0.4 henejt integration prep). -/
lean_lib IotaktHttp where
  globs := #[.one `Iotakt.Http]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Path-based HTTP router with method matching and :param capture (v0.6). -/
lean_lib IotaktRouter where
  globs := #[.one `Iotakt.Router]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Connection actor abstraction: callback lifecycle, ActorRegistry (v0.5). -/
lean_lib IotaktActor where
  globs := #[.one `Iotakt.Actor]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Per-connection and global I/O statistics counters (v0.5). -/
lean_lib IotaktStats where
  globs := #[.one `Iotakt.Stats]

/-- HTTP/1.1 keep-alive benchmark server: uses ConnectionActor + ActorRegistry. -/
lean_exe «iotakt-bench-server» where
  root := `examples.BenchServer
  extraDepTargets := #[`iotaktNativeLib.static]

/-- RFC 025 throughput benchmark: N sequential keep-alive requests, reports req/s. -/
lean_exe «iotakt-bench» where
  root := `examples.Bench
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Minimal HTTP/1.0 server demo: EventLoop + WriteBuffer + HTTP parsing. -/
lean_exe «iotakt-http-server» where
  root := `examples.HttpServer
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Minimal HTTP/1.0 client demo: outbound connect + WriteBuffer + response parsing. -/
lean_exe «iotakt-http-client» where
  root := `examples.HttpClient
  extraDepTargets := #[`iotaktNativeLib.static]

/-- RFC §21.4 acceptance criterion: minimal TCP echo server using the
    full iotakt native driver.  Binds to 127.0.0.1:49900. -/
lean_exe «iotakt-echo-server» where
  root := `examples.EchoServer
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.2 multi-connection echo server: accepts N concurrent connections
    using EventLoop, echoes bytes on each independently. -/
lean_exe «iotakt-multi-echo» where
  root := `examples.MultiEcho
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.3 integration test: RFC 036 UDP, RFC 039 outbound connect,
    persistent multi-round connections. -/
lean_exe «iotakt-v3-test» where
  root := `examples.V3Test
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.4 integration test: WriteBuffer, HTTP/1.0 round-trip, RFC 028 FFI
    invariants, RFC 026 native conformance edge cases. -/
lean_exe «iotakt-v4-test» where
  root := `examples.V4Test
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.5 integration test: ConnectionActor, Stats, keep-alive HTTP, throughput. -/
lean_exe «iotakt-v5-test» where
  root := `examples.V5Test
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.6 HTTP/1.1 routing server: EventLoop + Router + keep-alive + Gap 006 cleanup. -/
lean_exe «iotakt-routing-server» where
  root := `examples.RoutingServer
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.6 integration test: Router, Gap 006 cancel-on-close, henret bridge. -/
lean_exe «iotakt-v6-test» where
  root := `examples.V6Test
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.7 integration test: adaptive poll timeout, idle reaping, receiveUntil infra. -/
lean_exe «iotakt-v7-test» where
  root := `examples.V7Test
  extraDepTargets := #[`iotaktNativeLib.static]
