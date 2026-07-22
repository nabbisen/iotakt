# Native FFI Contract

**iotakt v0.1 — RFC 009**

This document specifies the rules that every native C function in
`native/` must obey. The native shim is `TRUSTED` in the
proof/trust/test matrix — it is not proven inside Lean, but it is
auditable, small, and must pass sanitizer builds.

## General rules

- No `malloc`/`free` for application data buffers.
- No retained pointers into Lean objects between call boundaries.
- No background native threads.
- No C-side application queues or ring buffers.
- No callback into Lean from signal handlers.
- Every syscall checks `errno` immediately after a -1 return.
- All functions return flat status / result values; no C struct returns.
- All file descriptors are configured non-blocking before registration.
- All file descriptors are configured close-on-exec (`SOCK_CLOEXEC`,
  `EPOLL_CLOEXEC`, or `fcntl` fallback).

## Receive buffer ownership (Option A, v0.1)

```
1. Lean caller invokes  iotakt_recv(fd, maxBytes)
2. C shim allocates a   Lean ByteArray via lean_alloc_array()
3. C shim calls         recv(fd, buf, maxBytes, MSG_NOSIGNAL)
4. C shim returns       the ByteArray to Lean (ownership transferred)
5. C shim retains       no pointer
```

No C-side long-lived buffers. Each recv call allocates and returns
exactly one `ByteArray`. The allocation strategy may be revisited in
v0.2+ once benchmarks show it matters.

## Send semantics

```
1. Lean caller passes   a read-only ByteArray slice
2. Lean wrapper checks  offset <= size and len <= size - offset
3. C shim repeats       the subtraction-safe checks and enforces SSIZE_MAX
4. C shim calls         send(fd, buf + offset, len, MSG_NOSIGNAL)
5. C shim returns       bytes_written or a typed validation/native result
6. Lean caller retains  the unsent suffix
```

Invalid slices return `invalidSlice`; lengths above `SSIZE_MAX` return
`nativeLengthLimit`. Neither case performs pointer arithmetic or reaches a syscall,
and neither is shortened. Partial writes are normal. iotakt does not retry.

## SIGPIPE prevention

- Linux: use `MSG_NOSIGNAL` in every `send` wrapper.
- BSD/macOS (future kqueue backend): use `SO_NOSIGPIPE` or document a
  process-level `signal(SIGPIPE, SIG_IGN)` policy.

## EINTR policy (v0.1)

Return `EINTR` as a typed error to Lean. The Lean driver/actor decides
whether to retry. Rationale: simplicity; the driver can mask EINTR in
a later RFC if benchmarks show it matters.

## Compiler flags (required)

```
-Wall -Wextra -Werror -pedantic
```

Test builds additionally:

```
-fsanitize=address,undefined
```

## Function inventory (design, not yet implemented)

```c
// poller
int iotakt_epoll_create(void);
int iotakt_epoll_register(int epfd, int fd, uint32_t mask);
int iotakt_epoll_modify(int epfd, int fd, uint32_t mask);
int iotakt_epoll_deregister(int epfd, int fd);
int iotakt_epoll_wait(int epfd, struct epoll_event *evs, int maxev, int timeout_ms);
void iotakt_epoll_close(int epfd);

// socket
int iotakt_socket_tcp(int af);
int iotakt_bind(int fd, const char *addr, uint16_t port);
int iotakt_listen(int fd, int backlog);
int iotakt_accept(int fd, char *peer_addr_out, size_t peer_addr_len);
int iotakt_set_nonblock(int fd);
int iotakt_set_cloexec(int fd);
void iotakt_close(int fd);

// I/O
lean_obj_res iotakt_recv(int fd, size_t max_bytes);
lean_obj_res iotakt_send(
    int32_t fd, b_lean_obj_arg ba, size_t offset, size_t len, lean_obj_arg w);
lean_obj_res iotakt_sendto(
    int32_t fd, b_lean_obj_arg ba, size_t offset, size_t len,
    uint32_t addr_hbo, uint16_t port_hbo, lean_obj_arg w);
```

These signatures use borrowed `ByteArray` ownership and return Lean `IO Int` values
whose validation statuses are decoded into typed results.
