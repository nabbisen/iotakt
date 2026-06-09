/*
 * iotakt_socket.c — POSIX socket primitives (RFC 012)
 * Apache-2.0  Copyright 2026 nabbisen
 *
 * All sockets are configured non-blocking and close-on-exec atomically
 * where possible (SOCK_NONBLOCK | SOCK_CLOEXEC on Linux), with an
 * immediate fcntl fallback otherwise. No application state is retained.
 */
#include "iotakt.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

/* Set O_NONBLOCK and FD_CLOEXEC atomically or via fcntl fallback. */
static int set_nonblocking_cloexec(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return -errno;
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return -errno;
    flags = fcntl(fd, F_GETFD, 0);
    if (flags < 0) return -errno;
    if (fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0) return -errno;
    return 0;
}

/*
 * Create a non-blocking, close-on-exec TCP socket.
 * af4=1 → AF_INET; af4=0 → AF_INET6.
 * Returns fd >= 0 or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_socket_tcp(int32_t af4, lean_obj_arg w) {
    int domain = af4 ? AF_INET : AF_INET6;
    int fd = socket(domain,
                    SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        /* Try without the atomic flags and apply via fcntl. */
        fd = socket(domain, SOCK_STREAM, 0);
        if (fd < 0) {
            lean_dec(w);
            return lean_io_result_mk_ok(lean_int_to_int(-errno));
        }
        int r = set_nonblocking_cloexec(fd);
        if (r < 0) { close(fd); lean_dec(w); return lean_io_result_mk_ok(lean_int_to_int(r)); }
    }
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(fd));
}

/*
 * Set SO_REUSEADDR and optionally SO_REUSEPORT on a listener.
 * Returns 0 or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_set_reuse_addr(int32_t fd, lean_obj_arg w) {
    int one = 1;
    int r = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    int ret = (r < 0) ? -errno : 0;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(ret));
}

/*
 * Bind a TCP socket to a IPv4 address + port.
 * addr is a network-byte-order IPv4 address (0 = INADDR_ANY).
 * Returns 0 or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_bind_ipv4(
    int32_t fd, uint32_t addr, uint16_t port, lean_obj_arg w)
{
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family      = AF_INET;
    sa.sin_addr.s_addr = htonl(addr);
    sa.sin_port        = htons(port);
    int r = bind(fd, (struct sockaddr*)&sa, sizeof(sa));
    int ret = (r < 0) ? -errno : 0;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(ret));
}

/*
 * Begin listening on a bound TCP socket.
 * Returns 0 or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_listen(
    int32_t fd, int32_t backlog, lean_obj_arg w)
{
    int r = listen(fd, backlog);
    int ret = (r < 0) ? -errno : 0;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(ret));
}

/*
 * Accept one connection. Uses accept4 for atomic NONBLOCK + CLOEXEC.
 * Returns the new fd >= 0 or -errno (EAGAIN = -11 = no connection ready).
 * The peer IPv4 address (4 bytes, network order) is returned as a
 * ByteArray; empty on error or for non-IPv4.
 *
 * Returns IO (Int × ByteArray):
 *   Int ≥ 0 = accepted fd; ByteArray = peer_addr (4 bytes IPv4)
 *   Int < 0 = -errno;      ByteArray = empty
 */
LEAN_EXPORT lean_obj_res iotakt_accept(int32_t listen_fd, lean_obj_arg w) {
    struct sockaddr_in peer;
    socklen_t plen = sizeof(peer);
    int fd = accept4(listen_fd, (struct sockaddr*)&peer, &plen,
                     SOCK_NONBLOCK | SOCK_CLOEXEC);
    int saved_errno = errno;

    int64_t status;
    lean_object *ba;

    if (fd >= 0) {
        status = (int64_t)fd;
        if (peer.sin_family == AF_INET) {
            ba = lean_alloc_sarray(1, 4, 4);
            uint32_t a = peer.sin_addr.s_addr; /* network order */
            memcpy(lean_sarray_cptr(ba), &a, 4);
        } else {
            ba = lean_alloc_sarray(1, 0, 0);
        }
    } else {
        status = -(int64_t)saved_errno;
        ba = lean_alloc_sarray(1, 0, 0);
    }

    lean_object *pair = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(pair, 0, lean_int64_to_int(status));
    lean_ctor_set(pair, 1, ba);
    lean_dec(w);
    return lean_io_result_mk_ok(pair);
}

/*
 * Apply O_NONBLOCK to an existing fd (fallback for platforms without
 * SOCK_NONBLOCK on accept). Returns 0 or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_set_nonblock(int32_t fd, lean_obj_arg w) {
    int flags = fcntl(fd, F_GETFL, 0);
    int r = (flags < 0) ? flags : fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    int ret = (r < 0) ? -errno : 0;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(ret));
}

/*
 * Apply FD_CLOEXEC to an existing fd. Returns 0 or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_set_cloexec(int32_t fd, lean_obj_arg w) {
    int flags = fcntl(fd, F_GETFD, 0);
    int r = (flags < 0) ? flags : fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
    int ret = (r < 0) ? -errno : 0;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(ret));
}

/*
 * Close a fd. Idempotent on EBADF. No return value (unit).
 */
LEAN_EXPORT lean_obj_res iotakt_close(int32_t fd, lean_obj_arg w) {
    close(fd); /* ignore EINTR/EBADF */
    lean_dec(w);
    return lean_io_result_mk_ok(lean_box(0));
}

/*
 * Create a connected socket pair (AF_UNIX stream) with NONBLOCK and
 * CLOEXEC set atomically. Useful for tests and IPC.
 *
 * Returns IO (Int × Int):
 *   Both ≥ 0 = (fd0, fd1) connected pair.
 *   Both < 0 = (-errno, -errno) on failure.
 */
LEAN_EXPORT lean_obj_res iotakt_socketpair(lean_obj_arg w) {
    int fds[2] = {-1, -1};
    int r = socketpair(AF_UNIX,
                       SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0, fds);
    int saved_errno = (r < 0) ? errno : 0;

    lean_object *pair = lean_alloc_ctor(0, 2, 0);
    if (r == 0) {
        lean_ctor_set(pair, 0, lean_int64_to_int((int64_t)fds[0]));
        lean_ctor_set(pair, 1, lean_int64_to_int((int64_t)fds[1]));
    } else {
        lean_ctor_set(pair, 0, lean_int64_to_int(-(int64_t)saved_errno));
        lean_ctor_set(pair, 1, lean_int64_to_int(-(int64_t)saved_errno));
    }
    lean_dec(w);
    return lean_io_result_mk_ok(pair);
}
