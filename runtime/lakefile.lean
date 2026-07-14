import Lake
open Lake DSL

package «iotakt-runtime» where
  -- Runtime package (RFC 061): the Henret bridge, native epoll backend, and the
  -- EventLoop/HTTP runtime. Depends on the Henret-free `iotakt` model package
  -- (required below) and on Henret. The pure model, fake poller, API surface, and
  -- proof corpus live in the model package and resolve via that dependency.
  leanOptions := #[⟨`autoImplicit, false⟩]

/-- Pinned Henret dependency (RFC 007 bridge layer only).

    Pinned to the COMMIT that tag `0.34.4` dereferences to (`0.34.4^{}` =
    `ad0ceab4…`). We pin the commit, not `@ "0.34.4"`: upstream release tags are
    *annotated* (`0.34.4` → tag object `059c504e…`), so a tag pin would record the
    tag-object SHA instead of the commit. Henret `Henret/` Lean source is
    byte-identical 0.34.0 → 0.34.4 (0.34.1–0.34.4 are docs / release-CI only —
    RFCs 094/095/096/097); this bump changes no model, no proof, no
    `inject_ok_of_mailbox` guard.

    0.34.4 is the first henret release to publish its RFC 095 release-verification
    sidecar from CI. iotakt's provenance `dependencies[]` entry (RFC 063) is derived
    from that sidecar and bound to this commit via its `git_commit` field; the
    sidecar's own SHA-256 (`21d6e9d0…`) is the value jemmet's stack edge and
    henret's manifest cross-reference.
    Git require → CI-portable via `LAKE_PKG_URL_MAP: henret=…`.

    LOCAL / VENDORED override — swap for a vendored tree:
      require henret from "../henret/henret-v0.34.4"  -/
require henret from git "https://github.com/nabbisen/henret" @ "ad0ceab4ebed2884c9165be44154dca2c1f4816f"

/-- The Henret-free model package (RFC 061): pure model, fake poller, public API,
    and proofs. Full-stack consumers depending on `iotakt-bridge` import
    `Iotakt.Model.*`, `Iotakt.Api`, `Iotakt.Fake` through this transitive
    dependency unchanged (the bridge re-exports them by depending on the model). -/
require iotakt from ".."

/-- Henret bridge library (RFC 007). Imports `Henret.Model`; builds the
    deterministic translation of iotakt events into Henret operations. -/
lean_lib IotaktBridge where
  globs := #[.andSubmodules `IotaktRuntime.Bridge]

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
  globs := #[.one `IotaktRuntime.Native, .andSubmodules `IotaktRuntime.Native]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Typed listener endpoint and error vocabulary (RFC 070). -/
lean_lib IotaktListener where
  globs := #[.one `IotaktRuntime.Listener]

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
  globs := #[.one `IotaktRuntime.Driver]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Multi-connection event loop (v0.2 / RFC 023). Wraps the driver with a
    high-level EventLoop, LoopEvent dispatch, and connection management. -/
lean_lib IotaktLoop where
  globs := #[.one `IotaktRuntime.Loop]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Write buffering for partial-write and wouldBlock handling (v0.4). -/
lean_lib IotaktWriteBuffer where
  globs := #[.one `IotaktRuntime.WriteBuffer]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Minimal HTTP/1.0 parser + response builder (v0.4 jemmet integration prep). -/
lean_lib IotaktHttp where
  globs := #[.one `IotaktRuntime.Http]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Path-based HTTP router with method matching and :param capture (v0.6). -/
lean_lib IotaktRouter where
  globs := #[.one `IotaktRuntime.Router]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- HTTP/1.1 chunked transfer encoding (RFC 7230 §4.1) — v0.8. -/
lean_lib IotaktChunked where
  globs := #[.one `IotaktRuntime.Chunked]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Scheduled connection-actor lifecycle model over Henret (v0.8). -/
lean_lib IotaktSchedConn where
  globs := #[.one `IotaktRuntime.SchedConn]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Body-aware HTTP request reader: Content-Length + chunked (v0.9). -/
lean_lib IotaktRequestBody where
  globs := #[.one `IotaktRuntime.RequestBody]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- jemmet handoff surface: consolidated HTTP server building blocks (v0.9). -/
lean_lib IotaktServer where
  globs := #[.one `IotaktRuntime.Server]
  extraDepTargets := #[`iotaktNativeLib.static]


/-- Connection actor abstraction: callback lifecycle, ActorRegistry (v0.5). -/
lean_lib IotaktActor where
  globs := #[.one `IotaktRuntime.Actor]
  extraDepTargets := #[`iotaktNativeLib.static]

/-- Per-connection and global I/O statistics counters (v0.5). -/
lean_lib IotaktStats where
  globs := #[.one `IotaktRuntime.Stats]

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

/-- v0.8 chunked streaming server: runStepAuto + idle reaping + chunked encoding. -/
lean_exe «iotakt-streaming-server» where
  root := `examples.StreamingServer
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.8 integration test: chunked encode/decode, scheduled connection actor. -/
lean_exe «iotakt-v8-test» where
  root := `examples.V8Test
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.9 upload server: Iotakt.Server handoff surface, chunked + Content-Length bodies. -/
lean_exe «iotakt-upload-server» where
  root := `examples.UploadServer
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.9 integration test: body framing, live request reading, handoff surface. -/
lean_exe «iotakt-v9-test» where
  root := `examples.V9Test
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.10 reference consumer example: keep-alive HTTP/1.1 service on the handoff surface. -/
lean_exe «iotakt-reference-server» where
  root := `examples.ReferenceServer
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.10 integration test: request-size limits, keep-alive serve loop, jemmet router. -/
lean_exe «iotakt-v10-test» where
  root := `examples.V10Test
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.11 integration test: connection limits + graceful shutdown. -/
lean_exe «iotakt-v11-test» where
  root := `examples.V11Test
  extraDepTargets := #[`iotaktNativeLib.static]

/-- v0.13 integration test: explicit coalesce ack + recvAck/sendAck helpers. -/
lean_exe «iotakt-v13-test» where
  root := `examples.V13Test
  extraDepTargets := #[`iotaktNativeLib.static]

/-- R2 regression: returned events are authoritative and mailbox-independent. -/
lean_exe «iotakt-r2-delivery-test» where
  root := `examples.R2DeliveryTest
  extraDepTargets := #[`iotaktNativeLib.static]

/-- R2 regression: typed address-aware listener creation and publication. -/
lean_exe «iotakt-r2-listener-test» where
  root := `examples.R2ListenerTest
  extraDepTargets := #[`iotaktNativeLib.static]

/-- RFC 015 standup: iotakt's listener half — accept TCP, emit `newConnection`,
hand the fd to a consumer seam (kroopt's TLS transport in the harness). -/
lean_exe «iotakt-standup-listener» where
  root := `examples.StandupListener
  extraDepTargets := #[`iotaktNativeLib.static]
