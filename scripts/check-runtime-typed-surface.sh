#!/usr/bin/env bash
# RFC064-TYPED-SURFACE-001 — compile the stable checked-effect API from a
# downstream module, rather than relying on declarations inside iotakt-runtime.
set -eu

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/RuntimeSurfaceProbe.lean" <<'LEAN'
import IotaktRuntime.Loop

open Iotakt.Model IotaktRuntime.Loop

/- Exhaustiveness pins the stable domain errors a consumer must handle. -/
def classifyEffectError : EffectError -> String
  | .invalidKey => "invalid-key"
  | .staleKey => "stale-key"
  | .invalidRawFd => "invalid-raw-fd"
  | .wrongKind => "wrong-kind"
  | .inactive => "inactive"
  | .invalidSlice => "invalid-slice"
  | .nativeLengthLimit => "native-length-limit"
  | .limitExceeded => "limit-exceeded"
  | .nativeError _ => "native-error"

/- Exact annotations make result-shape regressions fail in a downstream build. -/
def enableWriteResult (loop : EventLoop) (key : FdKey) :
    IO (Except EffectError EventLoop) :=
  loop.enableWrite key

def disableWriteResult (loop : EventLoop) (key : FdKey) :
    IO (Except EffectError EventLoop) :=
  loop.disableWrite key

def closeConnectionResult (loop : EventLoop) (key : FdKey) :
    IO (Except EffectError EventLoop) :=
  loop.closeConnection key

def recvAckResult (loop : EventLoop) (key : FdKey) (maxBytes : Nat) :
    IO (Except EffectError (EventLoop × ReadResult)) :=
  loop.recvAck key maxBytes

def sendAckResult (loop : EventLoop) (key : FdKey) (payload : ByteArray)
    (offset len : Nat) : IO (Except EffectError (EventLoop × WriteResult)) :=
  loop.sendAck key payload offset len
LEAN

if ! lake --dir "$ROOT/runtime" env lean "$TMP/RuntimeSurfaceProbe.lean" \
    > "$TMP/build.log" 2>&1; then
  cat "$TMP/build.log"
  exit 1
fi
echo "runtime typed surface: downstream compile PASS (RFC064-TYPED-SURFACE-001)"
