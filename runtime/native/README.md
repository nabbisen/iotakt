# native/

C source for the iotakt native backend (RFC 009–011).

Files to be added when Phase C RFCs are implemented:
- `iotakt_epoll.c` / `iotakt_epoll.h` — Linux epoll wrapper
- `iotakt_socket.c` / `iotakt_socket.h` — POSIX socket primitives
- `iotakt_io.c` — recv/send wrappers
- `CMakeLists.txt` or Makefile fragment for Lake integration
