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
#include <time.h>
#include "iotakt.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
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

/* ─────────────────────────────────────────────────────────────────────
 * UDP datagram operations (RFC 036)
 * ─────────────────────────────────────────────────────────────────── */

/*
 * Non-blocking recvfrom for UDP datagrams (Option A allocation policy).
 *
 * Returns IO (Int × ByteArray × ByteArray):
 *   Int > 0  = bytes received; first ByteArray = data; second = peer addr (6 bytes: 4 IPv4 + 2 port).
 *   Int = 0  = empty datagram.
 *   Int < 0  = -errno (EAGAIN = would-block, etc.).
 *
 * Each call allocates exactly one Lean ByteArray for the data and one
 * for the peer address. Native code retains no pointer after returning.
 */
LEAN_EXPORT lean_obj_res iotakt_recvfrom(
    int32_t fd, size_t max_bytes, lean_obj_arg w)
{
    lean_object *data_ba;
    lean_object *addr_ba;
    int64_t     status;

    if (max_bytes == 0) {
        data_ba = lean_alloc_sarray(1, 0, 0);
        addr_ba = lean_alloc_sarray(1, 0, 0);
        status  = 0;
    } else {
        struct sockaddr_in peer;
        socklen_t plen = sizeof(peer);
        data_ba = lean_alloc_sarray(1, max_bytes, max_bytes);
        uint8_t *buf = lean_sarray_cptr(data_ba);
        ssize_t n = recvfrom((int)fd, buf, max_bytes,
                             MSG_NOSIGNAL | MSG_DONTWAIT,
                             (struct sockaddr *)&peer, &plen);
        int saved_errno = errno;
        if (n >= 0) {
            lean_to_sarray(data_ba)->m_size = (size_t)n;
            status = (int64_t)n;
            if (peer.sin_family == AF_INET && plen >= (socklen_t)sizeof(peer)) {
                addr_ba = lean_alloc_sarray(1, 6, 6);
                uint8_t *p = lean_sarray_cptr(addr_ba);
                memcpy(p,     &peer.sin_addr.s_addr, 4);
                memcpy(p + 4, &peer.sin_port,        2);
            } else {
                addr_ba = lean_alloc_sarray(1, 0, 0);
            }
        } else {
            lean_to_sarray(data_ba)->m_size = 0;
            addr_ba = lean_alloc_sarray(1, 0, 0);
            status  = -(int64_t)saved_errno;
        }
    }
    /* Prod Int (Prod ByteArray ByteArray) */
    lean_object *inner = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(inner, 0, data_ba);
    lean_ctor_set(inner, 1, addr_ba);
    lean_object *outer = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(outer, 0, lean_int64_to_int(status));
    lean_ctor_set(outer, 1, inner);
    lean_dec(w);
    return lean_io_result_mk_ok(outer);
}

/*
 * Non-blocking sendto for UDP datagrams.
 * Sends `len` bytes from `ba` starting at `offset` to IPv4 addr:port.
 * addr is in host byte order; port is in host byte order.
 *
 * Returns IO Int: bytes sent (≥ 0) or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_sendto(
    int32_t fd, b_lean_obj_arg ba,
    size_t offset, size_t len,
    uint32_t addr_hbo, uint16_t port_hbo, lean_obj_arg w)
{
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family      = AF_INET;
    sa.sin_addr.s_addr = htonl(addr_hbo);
    sa.sin_port        = htons(port_hbo);

    size_t ba_size = lean_sarray_size(ba);
    if (offset > ba_size) len = 0;
    else if (offset + len > ba_size) len = ba_size - offset;

    int64_t status;
    if (len == 0) {
        status = 0;
    } else {
        const uint8_t *buf = lean_sarray_cptr(ba) + offset;
        ssize_t n = sendto((int)fd, buf, len,
                           MSG_NOSIGNAL | MSG_DONTWAIT,
                           (struct sockaddr *)&sa, sizeof(sa));
        int saved_errno = errno;
        status = (n >= 0) ? (int64_t)n : -(int64_t)saved_errno;
    }

    lean_dec(w);
    return lean_io_result_mk_ok(lean_int64_to_int(status));
}

/*
 * Monotonic nanosecond timestamp (CLOCK_MONOTONIC).
 * Returns IO Int.
 */
LEAN_EXPORT lean_obj_res iotakt_mono_ns(lean_obj_arg w) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int64_t ns = (int64_t)ts.tv_sec * (int64_t)1000000000 + (int64_t)ts.tv_nsec;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int64_to_int(ns));
}
