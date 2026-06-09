/*
 * iotakt_io.c — recv and send wrappers (RFC 010)
 * Apache-2.0  Copyright 2026 nabbisen
 *
 * Option A receive policy (RFC 010): the native shim allocates one
 * Lean ByteArray per successful recv, performs one non-blocking syscall,
 * and immediately transfers ownership to Lean. No C-side buffers are
 * retained.
 *
 * Send reads from a borrowed (read-only) Lean ByteArray and returns the
 * number of bytes written or -errno. Partial writes are normal.
 */
#include "iotakt.h"
#include <sys/socket.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

/*
 * Non-blocking recv (Option A).
 *
 * Returns IO (Int × ByteArray):
 *   Int > 0 → bytes received; ByteArray holds that many valid bytes.
 *   Int == 0 → EOF (peer closed).
 *   Int == -EAGAIN (-11) → would-block.
 *   Int == -EINTR  (-4)  → interrupted, may retry.
 *   Int < 0 (other)      → fatal error; ByteArray is empty.
 *
 * The ByteArray is freshly allocated using lean_alloc_sarray (backed by
 * Lean's scalar-array, i.e. the C representation of ByteArray). After
 * this function returns, no C pointer into the ByteArray is retained.
 */
LEAN_EXPORT lean_obj_res iotakt_recv(
    int32_t fd, size_t max_bytes, lean_obj_arg w)
{
    int64_t status;
    lean_object *ba;

    if (max_bytes == 0) {
        ba     = lean_alloc_sarray(1, 0, 0);
        status = 0;
    } else {
        /* Pre-allocate a ByteArray of capacity max_bytes. */
        ba = lean_alloc_sarray(1, max_bytes, max_bytes);
        uint8_t *buf = lean_sarray_cptr(ba);

        ssize_t n = recv((int)fd, buf, max_bytes,
                         MSG_NOSIGNAL | MSG_DONTWAIT);
        int saved_errno = errno;

        if (n > 0) {
            /* Trim the size to actual bytes received. */
            lean_to_sarray(ba)->m_size = (size_t)n;
            status = (int64_t)n;
        } else if (n == 0) {
            /* EOF: reuse the (empty) allocation. */
            lean_to_sarray(ba)->m_size = 0;
            status = 0;
        } else {
            /* Error: return an empty ByteArray. */
            lean_to_sarray(ba)->m_size = 0;
            status = -(int64_t)saved_errno;
        }
    }

    lean_object *pair = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(pair, 0, lean_int64_to_int(status));
    lean_ctor_set(pair, 1, ba);
    lean_dec(w);
    return lean_io_result_mk_ok(pair);
}

/*
 * Non-blocking send.
 *
 * Accepts a borrowed Lean ByteArray (b_lean_obj_arg — no ownership
 * transfer). Reads at most `len` bytes starting at `offset`.
 *
 * Returns IO Int:
 *   Int > 0 → bytes sent (partial write is normal).
 *   Int < 0 → -errno (EAGAIN, EINTR, EPIPE, etc.).
 *
 * MSG_NOSIGNAL prevents SIGPIPE from terminating the process.
 */
LEAN_EXPORT lean_obj_res iotakt_send(
    int32_t fd, b_lean_obj_arg ba, size_t offset, size_t len, lean_obj_arg w)
{
    size_t ba_size = lean_sarray_size(ba);
    if (offset > ba_size) len = 0;
    else if (offset + len > ba_size) len = ba_size - offset;

    int64_t status;
    if (len == 0) {
        status = 0;
    } else {
        const uint8_t *buf = lean_sarray_cptr(ba) + offset;
        ssize_t n = send((int)fd, buf, len, MSG_NOSIGNAL | MSG_DONTWAIT);
        int saved_errno = errno;
        status = (n >= 0) ? (int64_t)n : -(int64_t)saved_errno;
    }

    lean_dec(w);
    return lean_io_result_mk_ok(lean_int64_to_int(status));
}
