/*
 * iotakt_epoll.c — Linux epoll backend (RFC 011)
 * Apache-2.0  Copyright 2026 nabbisen
 *
 * This file is the ENTIRE epoll boundary. It contains thin syscall
 * wrappers only: no application state, no buffers, no threads.
 * Compile with:  -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined
 */
#include "iotakt.h"
#include <sys/epoll.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

/*
 * Create an epoll instance with EPOLL_CLOEXEC.
 * Returns the epoll fd (>= 0) or -errno on error.
 */
LEAN_EXPORT lean_obj_res iotakt_epoll_create(lean_obj_arg w) {
    int fd = epoll_create1(EPOLL_CLOEXEC);
    int r  = (fd < 0) ? -errno : fd;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(r));
}

/*
 * Register a raw fd with the epoll instance.
 * flags: bitmask of IOTAKT_READ_FLAG | IOTAKT_WRITE_FLAG.
 * Returns 0 or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_epoll_register(
    int32_t epfd, int32_t fd, uint32_t flags, lean_obj_arg w)
{
    struct epoll_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.events   = flags | (uint32_t)EPOLLERR | (uint32_t)EPOLLHUP;
    ev.data.fd  = fd;
    int r = epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev);
    int ret = (r < 0) ? -errno : 0;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(ret));
}

/*
 * Modify the interest set for a registered fd.
 * Returns 0 or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_epoll_modify(
    int32_t epfd, int32_t fd, uint32_t flags, lean_obj_arg w)
{
    struct epoll_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.events   = flags | (uint32_t)EPOLLERR | (uint32_t)EPOLLHUP;
    ev.data.fd  = fd;
    int r = epoll_ctl(epfd, EPOLL_CTL_MOD, fd, &ev);
    int ret = (r < 0) ? -errno : 0;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(ret));
}

/*
 * Remove a fd from the epoll instance.
 * Returns 0 or -errno.
 */
LEAN_EXPORT lean_obj_res iotakt_epoll_deregister(
    int32_t epfd, int32_t fd, lean_obj_arg w)
{
    int r = epoll_ctl(epfd, EPOLL_CTL_DEL, fd, NULL);
    int ret = (r < 0) ? -errno : 0;
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int_to_int(ret));
}

/*
 * Wait for events.
 *
 * Returns a Lean ByteArray encoding the events as a flat byte sequence.
 * Each event is 8 bytes: [fd:int32_t LE][flags:uint32_t LE].
 * Empty array means timeout or 0 events.
 * EINTR is treated as 0 events (driver decides whether to retry).
 * Other errors return a negative Int (wrapped in IO.ok, not IO.error,
 * so the Lean driver can log them without an exception path).
 *
 * Return layout: lean_io_result_mk_ok(Int) where Int >= 0 means
 * "n events in the ByteArray" and Int < 0 means "-errno from epoll_wait".
 * The ByteArray is a separate IO.ok returned via the second call style—
 * actually simpler: return IO (Int × ByteArray).
 */
LEAN_EXPORT lean_obj_res iotakt_epoll_wait(
    int32_t epfd, int32_t max_events, int32_t timeout_ms, lean_obj_arg w)
{
    /* Bound max_events defensively. */
    if (max_events <= 0 || max_events > IOTAKT_MAX_EVENTS)
        max_events = IOTAKT_MAX_EVENTS;

    struct epoll_event evs[(size_t)max_events];
    memset(evs, 0, sizeof(struct epoll_event) * (size_t)max_events);

    int n = epoll_wait(epfd, evs, max_events, timeout_ms);
    int saved_errno = errno;

    int64_t status;
    lean_object *ba;

    if (n > 0) {
        /* Encode events into a ByteArray: n * 8 bytes. */
        size_t bsize = (size_t)n * 8;
        ba = lean_alloc_sarray(1, bsize, bsize);
        uint8_t *p = lean_sarray_cptr(ba);
        for (int i = 0; i < n; i++) {
            int32_t  evfd   = evs[i].data.fd;
            uint32_t evmask = evs[i].events;
            memcpy(p + (size_t)i * 8,     &evfd,   4);
            memcpy(p + (size_t)i * 8 + 4, &evmask, 4);
        }
        status = (int64_t)n;
    } else if (n == 0 || (n < 0 && saved_errno == EINTR)) {
        /* Timeout or interrupted: return 0 events. */
        ba     = lean_alloc_sarray(1, 0, 0);
        status = 0;
    } else {
        /* Fatal epoll_wait error. */
        ba     = lean_alloc_sarray(1, 0, 0);
        status = -(int64_t)saved_errno;
    }

    /* Return IO (Int × ByteArray). */
    lean_object *pair = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(pair, 0, lean_int64_to_int(status));
    lean_ctor_set(pair, 1, ba);

    lean_dec(w);
    return lean_io_result_mk_ok(pair);
}

/*
 * Close the epoll fd. Ignores errors (fd may already be closed on
 * process exit; callers should deregister before closing).
 */
LEAN_EXPORT lean_obj_res iotakt_epoll_close(int32_t epfd, lean_obj_arg w) {
    close(epfd);
    lean_dec(w);
    return lean_io_result_mk_ok(lean_box(0));
}
