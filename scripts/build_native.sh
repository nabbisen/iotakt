#!/bin/sh
# scripts/build_native.sh — compile the iotakt native C shim manually.
# Used by CI systems and developers who prefer not to use Lake's extern_lib.
# Lake's extern_lib target is the recommended build path; this script is
# an alternative for environments with unusual build setups.
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_DIR="$REPO_ROOT/native"
OUT_DIR="$REPO_ROOT/.lake/build/lib"
OBJ_DIR="$REPO_ROOT/.lake/build/c"

mkdir -p "$OUT_DIR" "$OBJ_DIR"

# Find Lean include directory
LEAN_INCLUDE=$(lean --print-prefix 2>/dev/null)/include
if [ ! -f "$LEAN_INCLUDE/lean/lean.h" ]; then
  # Try elan default path
  LEAN_INCLUDE="$HOME/.elan/toolchains/$(cat "$REPO_ROOT/lean-toolchain")/include"
fi
if [ ! -f "$LEAN_INCLUDE/lean/lean.h" ]; then
  echo "ERROR: lean/lean.h not found. Is Lean 4 installed?"
  exit 1
fi

CC="${CC:-gcc}"
CFLAGS="-Wall -Wextra -Werror -D_GNU_SOURCE -std=c11 \
  -I${NATIVE_DIR} -I${LEAN_INCLUDE}"

# Add ASan/UBSan in test builds
if [ "${IOTAKT_SANITIZE:-0}" = "1" ]; then
  CFLAGS="$CFLAGS -fsanitize=address,undefined -g"
fi

echo "=== Compiling native C shim ==="
for src in iotakt_epoll.c iotakt_socket.c iotakt_io.c; do
  stem="${src%.c}"
  echo "  $src → $stem.o"
  $CC $CFLAGS -c "$NATIVE_DIR/$src" -o "$OBJ_DIR/$stem.o"
done

AR="${AR:-ar}"
LIB="$OUT_DIR/libiotakt_native.a"
echo "  → $LIB"
$AR rcs "$LIB" "$OBJ_DIR/iotakt_epoll.o" \
               "$OBJ_DIR/iotakt_socket.o" \
               "$OBJ_DIR/iotakt_io.o"

echo "Native build complete: $LIB"
