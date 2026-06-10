---
status: future
track: post-v1
project: iotakt
scope_class: scope-expansion
---

# RFC 053: Zero-Copy and Kernel-Assisted File Transfer

## Summary

This RFC defines a post-v1 path for kernel-assisted file transfer APIs such as `sendfile`, `splice`,
and `copy_file_range`. These features can improve throughput for static file serving or proxy-like
workloads, but they complicate iotakt's otherwise simple ByteArray-based data transfer model.

The recommendation is to keep zero-copy features outside v1 and introduce them only as explicit,
capability-gated APIs after the core TCP lifecycle and write semantics are stable.

## Motivation

A future jemmet server may serve static files. Copying file data into Lean `ByteArray`s and then into
kernel socket buffers may be acceptable for correctness-first v1, but high-throughput serving could
benefit from kernel-assisted transfer. However, these syscalls have platform-specific behavior,
blocking caveats, filesystem constraints, partial-progress semantics, and security implications.

## Goals

- Add a future strategy for efficient file-to-socket transfer.
- Preserve non-blocking and partial-progress semantics.
- Keep file transfer out of the core verified byte-array model unless explicitly modeled.
- Avoid accidental introduction of blocking file I/O into the driver loop.
- Make capability and authority boundaries explicit.

## Non-goals

- No zero-copy in v1.
- No general filesystem abstraction.
- No static file server inside iotakt.
- No memory-mapped file management.
- No transparent replacement of normal `send`.

## Design principle

Zero-copy APIs should be explicit:

```lean
sendFileStep(socket : FdKey) (file : FileHandleKey) (offset : UInt64) (maxBytes : USize)
  : IO SendFileResult
```

They should not be hidden behind ordinary `write`.

## Data model

```lean
structure FileHandleKey where
  raw : Int
  gen : Nat

inductive SendFileResult where
  | sent : bytes : USize -> nextOffset : UInt64 -> SendFileResult
  | wouldBlock
  | interrupted
  | unsupported
  | error : IoErrno -> SendFileResult
```

File handles require their own generation discipline. File descriptor reuse applies to file handles
as well as sockets.

## Lifecycle

File handle lifecycle is separate from socket lifecycle:

```text
open file outside iotakt or through a future file module
  -> register capability/handle identity
  -> use sendFileStep with explicit socket + file handle
  -> close file handle by owner
```

Core iotakt should not become a general file manager. A future `Iotakt.FileTransfer` module may hold
this API.

## Workflow

1. jemmet determines that a response body can be served from a file.
2. Application obtains a file handle with appropriate authority.
3. Actor calls `sendFileStep socket file offset maxBytes`.
4. Result may report partial progress.
5. Actor updates offset and repeats on writable readiness.
6. Actor falls back to ByteArray reads/writes if unsupported.

## Platform notes

Linux:

- `sendfile` may support file-to-socket transfer.
- `splice` may require pipes and has more complex semantics.
- `copy_file_range` is not socket-oriented.

BSD/macOS:

- `sendfile` exists but differs in signature and behavior.

Therefore, the normalized API must treat unsupported and partial progress as normal outcomes.

## Proof/trust/test classification

PROVEN candidates:

- File handle generation prevents stale handle delivery.
- Sendfile operation cannot be modeled as completing more than `maxBytes`.
- Partial progress updates are monotonic in offset.

ASSUMED/TESTED:

- Native syscall behavior.
- Platform-specific file/socket constraints.
- Non-blocking behavior and partial progress mapping.

## Security considerations

- File authority must not be smuggled through raw fd integers.
- Path traversal prevention is not iotakt's job.
- Static file serving policy belongs to jemmet or application layer.
- File handles should be close-on-exec.

## Acceptance criteria

- Zero-copy APIs are unavailable unless the post-v1 feature is explicitly enabled.
- Normal ByteArray send/recv behavior remains unchanged.
- Unsupported platforms return `.unsupported` rather than silently falling back without visibility.
- Tests cover partial progress, would-block, closed socket, closed file, and stale generation cases.
