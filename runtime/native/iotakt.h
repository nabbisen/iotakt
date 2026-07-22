/*
 * iotakt native shim — shared header
 * Apache-2.0  Copyright 2026 nabbisen
 *
 * Rules (RFC 009):
 *   - No malloc/free for application data buffers
 *   - No retained Lean object pointers between calls
 *   - No background threads
 *   - errno captured immediately after failing syscalls
 *   - All fds non-blocking and close-on-exec
 */
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <lean/lean.h>

/* -------------------------------------------------------------------------
 * Error encoding convention
 * Non-negative return: success value (fd, byte count, 0 for ok-no-value).
 * Negative return: -errno (e.g. -EAGAIN = -11 on Linux).
 * The value INT32_MIN (-2147483648) is reserved for "unknown error".
 * ---------------------------------------------------------------------- */

/* RFC 065 request-validation statuses. Linux errno values occupy 1..4095. */
#define IOTAKT_STATUS_INVALID_SLICE       (-INT64_C(4096))
#define IOTAKT_STATUS_NATIVE_LENGTH_LIMIT (-INT64_C(4097))

/* Platform errno values we care about (Linux x86-64). */
#define IOTAKT_EAGAIN       11
#define IOTAKT_EWOULDBLOCK  11
#define IOTAKT_EINTR         4
#define IOTAKT_EBADF         9
#define IOTAKT_ECONNRESET  104
#define IOTAKT_EPIPE        32
#define IOTAKT_ENOBUFS     105
#define IOTAKT_ENOMEM       12

/* epoll interest flags (level-triggered; edge-triggered is v0.2+). */
#define IOTAKT_READ_FLAG   0x1u   /* EPOLLIN  */
#define IOTAKT_WRITE_FLAG  0x4u   /* EPOLLOUT */
#define IOTAKT_ERR_FLAG    0x8u   /* EPOLLERR – always active, not registered */
#define IOTAKT_HUP_FLAG    0x10u  /* EPOLLHUP – always active, not registered */
#define IOTAKT_RDHUP_FLAG  0x2000u /* EPOLLRDHUP (Linux 2.6.17+) */

/* Maximum events per wait call (matches DriverConfig.maxEventsPerPoll default). */
#define IOTAKT_MAX_EVENTS 1024
