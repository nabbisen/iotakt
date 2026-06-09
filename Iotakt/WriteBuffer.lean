import Iotakt.Native.Io
import Iotakt.Model.Interest

/-!
# Iotakt.WriteBuffer

Buffered output for non-blocking sockets (v0.4).

A non-blocking `send` can return `.wrote n` with `n < len` (partial
write) or `.wouldBlock` when the kernel socket buffer is full. Callers
must retain the unsent suffix and retry when the fd becomes writable
again. `WriteBuffer` encapsulates this pattern:

```lean
-- Create empty buffer
let mut wb := WriteBuffer.empty

-- Enqueue data to send
wb := wb.push responseBytes

-- Flush loop (called when fd is writable or on first write attempt)
let (wb', done) ← wb.flush fd
if done then disableWriteInterest fd
else enableWriteInterest fd  -- re-arm; more to send
```

When `flush` returns `true`, all pending bytes have been sent. When it
returns `false`, write interest should be enabled on the fd so the driver
delivers another writable event when the socket can accept more data.
-/

namespace Iotakt.WriteBuffer

open Iotakt.Native

/-- Buffered outgoing data: a `ByteArray` plus an `offset` marking how
far we have already sent. The live slice is `pending[offset..]`. -/
structure WriteBuffer where
  pending : ByteArray := ByteArray.empty
  offset  : Nat       := 0
  deriving Inhabited

namespace WriteBuffer

/-- Empty buffer. -/
def empty : WriteBuffer := {}

/-- True when there is no unsent data. -/
def isEmpty (wb : WriteBuffer) : Bool := wb.offset >= wb.pending.size

/-- Number of unsent bytes. -/
def unsent (wb : WriteBuffer) : Nat :=
  if wb.offset >= wb.pending.size then 0
  else wb.pending.size - wb.offset

/-- Enqueue `data` for sending. If the buffer is fully flushed (`isEmpty`),
the pending bytes are replaced to avoid growing the buffer unboundedly. -/
def push (wb : WriteBuffer) (data : ByteArray) : WriteBuffer :=
  if wb.isEmpty then
    { pending := data, offset := 0 }
  else
    -- Append to the live suffix (rare: only when previous flush was partial)
    let suffix : ByteArray := ⟨wb.pending.data[wb.offset:]⟩
    let combined := ByteArray.copySlice suffix 0 (ByteArray.mkEmpty (suffix.size + data.size))
                      0 suffix.size
    let combined := ByteArray.copySlice data 0 combined suffix.size data.size
    { pending := combined, offset := 0 }

/-- Attempt to flush all pending bytes in one `send` call.
Returns `(updated_buffer, all_flushed)`.
- `all_flushed = true` → nothing pending; disable write interest.
- `all_flushed = false` → partial write or wouldBlock; keep write interest.

The caller MUST enable write interest on the fd when `all_flushed = false`
so the driver delivers another writable event to complete the flush. -/
def flush (wb : WriteBuffer) (fd : Int) : IO (WriteBuffer × Bool) := do
  if wb.isEmpty then return (wb, true)
  let len := wb.pending.size - wb.offset
  let r ← Io.send fd wb.pending wb.offset len
  match r with
  | .wrote n =>
      let newOffset := wb.offset + n.toNat
      if newOffset >= wb.pending.size then
        return ({ pending := ByteArray.empty, offset := 0 }, true)
      else
        return ({ wb with offset := newOffset }, false)
  | .wouldBlock =>
      return (wb, false)
  | .interrupted =>
      -- Transient; caller will retry on next writable event
      return (wb, false)
  | .closed | .error _ =>
      -- Connection broken; discard pending data
      return ({ pending := ByteArray.empty, offset := 0 }, true)

/-- Flush all pending bytes, retrying up to `maxRetries` times on
`wouldBlock`. Returns `true` when fully flushed. Useful in tight loops
where write interest cannot be re-armed (e.g. tests). -/
def flushAll (wb : WriteBuffer) (fd : Int) (maxRetries : Nat := 10) :
    IO (WriteBuffer × Bool) := do
  let mut wb := wb
  let mut done := false
  for _ in List.range maxRetries do
    if done then pure ()
    else do
      let (wb1, flushed) ← wb.flush fd
      wb := wb1; done := flushed
  return (wb, done)

end WriteBuffer

end Iotakt.WriteBuffer
