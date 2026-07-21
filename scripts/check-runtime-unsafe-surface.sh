#!/usr/bin/env bash
# RFC064-UNSAFE-SURFACE-001 — Lean imports are transitive, so unchecked runtime
# dependencies must be explicitly named Unsafe/unsafe and legacy unmarked escape
# names must not resolve for a downstream consumer.
set -eu

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! lake --dir "$ROOT/runtime" build IotaktServer IotaktActor \
    > "$TMP/package-build.log" 2>&1; then
  cat "$TMP/package-build.log"
  exit 1
fi

cat > "$TMP/UnsafeSurfacePositive.lean" <<'LEAN'
import IotaktRuntime.Server
import IotaktRuntime.Actor

#check IotaktRuntime.Native.Unsafe.Epoll.wait
#check IotaktRuntime.Native.Unsafe.Socket.closeFdRaw
#check IotaktRuntime.Native.Unsafe.Io.recv
#check IotaktRuntime.Driver.unsafeNativeStep
#check IotaktRuntime.Driver.unsafeSetupListenerAt
#check IotaktRuntime.Driver.unsafeNativeAcceptOps
#check IotaktRuntime.Loop.EventLoop.unsafeCreateWithMode
#check IotaktRuntime.Loop.EventLoop.unsafeCreateMailbox
#check IotaktRuntime.Loop.EventLoop.unsafeRunStepWith
#check IotaktRuntime.Loop.EventLoop.unsafeConnectTo
#check IotaktRuntime.Loop.EventLoop.unsafeShutdown
#check IotaktRuntime.Loop.EventLoop.unsafeDestroy
#check IotaktRuntime.Actor.ConnectionActor.unsafeMkEcho
#check IotaktRuntime.Actor.ConnectionActor.unsafeMkBuffered
#check IotaktRuntime.Http.HttpRequest.unsafeReadHeaders
#check IotaktRuntime.Http.HttpResponse.unsafeReadAll
#check IotaktRuntime.RequestBody.unsafeReadFull
#check IotaktRuntime.RequestBody.unsafeReadFromBuffer
#check IotaktRuntime.WriteBuffer.WriteBuffer.unsafeFlush
#check IotaktRuntime.WriteBuffer.WriteBuffer.unsafeFlushAll
#check IotaktRuntime.Server.unsafeReadRequest
#check IotaktRuntime.Server.unsafeReadRequestBuffered
LEAN

if ! lake --dir "$ROOT/runtime" env lean "$TMP/UnsafeSurfacePositive.lean" \
    > "$TMP/positive.log" 2>&1; then
  cat "$TMP/positive.log"
  exit 1
fi

checked=0
while IFS='|' read -r legacy replacement; do
  [ -n "$legacy" ] || continue
  cat > "$TMP/UnsafeSurfaceNegative.lean" <<LEAN
import IotaktRuntime.Server
import IotaktRuntime.Actor
#check $legacy
LEAN
  if lake --dir "$ROOT/runtime" env lean "$TMP/UnsafeSurfaceNegative.lean" \
      > "$TMP/negative.log" 2>&1; then
    echo "[FAIL] legacy unchecked escape still resolves: $legacy" >&2
    echo "       expected explicit replacement: $replacement" >&2
    exit 1
  fi
  checked=$((checked + 1))
done <<'SURFACES'
IotaktRuntime.Native.Epoll.wait|IotaktRuntime.Native.Unsafe.Epoll.wait
IotaktRuntime.Native.Socket.closeFdRaw|IotaktRuntime.Native.Unsafe.Socket.closeFdRaw
IotaktRuntime.Native.Io.recv|IotaktRuntime.Native.Unsafe.Io.recv
IotaktRuntime.Driver.nativeStep|IotaktRuntime.Driver.unsafeNativeStep
IotaktRuntime.Driver.setupListenerAt|IotaktRuntime.Driver.unsafeSetupListenerAt
IotaktRuntime.Driver.nativeAcceptOps|IotaktRuntime.Driver.unsafeNativeAcceptOps
IotaktRuntime.Loop.EventLoop.createWithMode|IotaktRuntime.Loop.EventLoop.unsafeCreateWithMode
IotaktRuntime.Loop.EventLoop.createMailbox|IotaktRuntime.Loop.EventLoop.unsafeCreateMailbox
IotaktRuntime.Loop.EventLoop.runStepWith|IotaktRuntime.Loop.EventLoop.unsafeRunStepWith
IotaktRuntime.Loop.EventLoop.connectTo|IotaktRuntime.Loop.EventLoop.unsafeConnectTo
IotaktRuntime.Loop.EventLoop.shutdown|IotaktRuntime.Loop.EventLoop.unsafeShutdown
IotaktRuntime.Loop.EventLoop.destroy|IotaktRuntime.Loop.EventLoop.unsafeDestroy
IotaktRuntime.Actor.ConnectionActor.mkEcho|IotaktRuntime.Actor.ConnectionActor.unsafeMkEcho
IotaktRuntime.Actor.ConnectionActor.mkBuffered|IotaktRuntime.Actor.ConnectionActor.unsafeMkBuffered
IotaktRuntime.Http.HttpRequest.readHeaders|IotaktRuntime.Http.HttpRequest.unsafeReadHeaders
IotaktRuntime.Http.HttpResponse.readAll|IotaktRuntime.Http.HttpResponse.unsafeReadAll
IotaktRuntime.RequestBody.readFull|IotaktRuntime.RequestBody.unsafeReadFull
IotaktRuntime.RequestBody.readFromBuffer|IotaktRuntime.RequestBody.unsafeReadFromBuffer
IotaktRuntime.WriteBuffer.WriteBuffer.flush|IotaktRuntime.WriteBuffer.WriteBuffer.unsafeFlush
IotaktRuntime.WriteBuffer.WriteBuffer.flushAll|IotaktRuntime.WriteBuffer.WriteBuffer.unsafeFlushAll
IotaktRuntime.Server.readRequest|IotaktRuntime.Server.unsafeReadRequest
IotaktRuntime.Server.readRequestBuffered|IotaktRuntime.Server.unsafeReadRequestBuffered
SURFACES

echo "runtime unsafe surface: PASS ($checked legacy escape names unavailable; RFC064-UNSAFE-SURFACE-001)"
