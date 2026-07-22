# RFC 065 — Native buffer bounds and enforced runtime I/O limits

**Status.** Proposed — release-blocking security remediation
**Tracks.** Architecture review B2; Go evidence 2.
**Touches.** `IotaktRuntime.Native.Io`, `runtime/native/iotakt_io.c`, `DriverConfig`, `EventLoop.recvAck`, native tests, sanitizer cases.

## Summary

Make every native byte slice overflow-safe and enforce receive allocation limits at
the stable runtime boundary. Validation must occur in Lean and be repeated
defensively in C before pointer arithmetic or a syscall.

## Goals

- Eliminate unsigned `offset + len` overflow in TCP and UDP send paths.
- Bound syscall lengths to the buffer remainder and `SSIZE_MAX`.
- Reject invalid slices in Lean before FFI.
- Enforce `DriverConfig.maxReadBytes` inside stable receive APIs.
- Cover boundary values under the repaired ASan/UBSan path from RFC 067.

## Non-goals

- Do not introduce `recvInto` or buffer pooling.
- Do not change Option A ownership except where required for safe bounds handling.
- Do not treat caller convention as a security control.

## External design

The stable send API validates `offset <= size` and `len <= size - offset`. Invalid
slices return `invalidSlice` without invoking native code. Stable APIs reject rather
than shorten an oversized slice; this RFC introduces no truncating helper.

`EventLoop.recvAck requested` checks the request against
`DriverConfig.maxReadBytes`. A request above the configured maximum returns
`limitExceeded` before allocation or syscall. This reject-without-I/O behavior is the
R0 stable policy; callers that want a smaller request must choose it explicitly.
After the configured-limit check, the stable boundary also rejects a request above
the current Linux `SSIZE_MAX` with `nativeLengthLimit` before `Nat.toUSize`
conversion, allocation, or syscall. A configured limit may be a larger `Nat`, but it
does not authorize implicit wrapping or shortening at the native boundary.

## Receive-allocation inventory

Implementation must generate a repository-derived inventory of every stable path
that allocates a receive buffer or selects a receive syscall length. A
reviewer-maintained classification file records each path as `limit-enforced`,
`unsafe-internal`, or `unreachable`, names the governing configuration and test ID,
and fails verification for an unclassified discovered path. Each `limit-enforced`
row must demonstrate that the limit is checked before allocation and native I/O.

## Native contract

TCP and UDP send wrappers must use subtraction-safe checks:

```c
if (offset > size) reject;
remaining = size - offset;
if (len > remaining) reject_invalid_slice;
if (len > SSIZE_MAX) reject_native_length_limit;
```

No pointer addition or syscall occurs until all checks succeed. `len > remaining`
returns the same `invalidSlice` category as the Lean pre-FFI check. A slice that is
within the application buffer but exceeds `SSIZE_MAX` returns the distinct typed
`nativeLengthLimit` error. Neither case is shortened, clamped, or submitted to the
kernel. The C contract remains a defense even when a future caller bypasses the Lean
wrapper.

## Implementation sequence

1. Define typed invalid-slice and limit-exceeded outcomes.
2. Add shared Lean slice validation for TCP and UDP.
3. Replace addition-based C checks and add `SSIZE_MAX` handling.
4. Enforce configured receive limits in `EventLoop.recvAck` and related stable paths.
5. Add ordinary boundary tests, then ASan/UBSan cases after RFC 067 repairs linkage.
6. Update the FFI contract and proof/trust/test matrix.

## Test obligations

- `offset = size`, `offset > size`, `len = 0`, and exact-end slices.
- Maximum `Nat`/`USize` values and deliberately overflowing `(offset, len)` pairs.
- TCP `send` and UDP `sendTo` parity.
- Oversized receive requests with a small configured maximum.
- Instrumented syscall-seam assertions that `len > remaining` returns
  `invalidSlice` and invokes no syscall through both the Lean pre-FFI path and a
  direct defensive-C-path test.
- Instrumented syscall-seam assertions that `len > SSIZE_MAX` returns
  `nativeLengthLimit` and invokes no syscall; stable APIs never shorten the request.
- Inventory completeness and one bound-enforcement test per receive-allocation path.
- Actual sanitized-object execution, not an ordinary Lake rebuild.

## Security considerations

The current defect can turn a public size pair into an out-of-bounds native read.
Both validation layers are mandatory. Tests must avoid printing adjacent memory or
other sensitive process contents.

## Dependencies and follow-ups

- Can be implemented in parallel with RFC 064.
- Sanitizer evidence depends on RFC 067.
- R1 may record code and ordinary-test completion, but RFC 065 remains Proposed with
  evidence pending until RFC 067 runs these cases against instrumented native objects
  in R3.
- Blocks RFC 033 and runtime/native release recommendation.

## Acceptance criteria

- No native application-buffer slice uses overflow-prone addition for validation.
- Lean rejects invalid slices before FFI; C independently rejects them.
- Oversize-slice and native-length-limit tests observe the specified typed error and
  zero syscall invocations in both applicable validation layers.
- Stable receive APIs enforce `maxReadBytes`.
- The receive-allocation inventory has no unclassified stable path and binds every
  `limit-enforced` row to a passing pre-allocation limit test.
- Boundary suite passes normally and under real ASan/UBSan linkage.
- FFI and resource-limit documentation matches the implemented behavior.

## Decision

Invalid slices and receive requests above `maxReadBytes` are rejected with typed
errors before allocation or FFI. Safe shortening is outside this RFC and cannot be
introduced as implicit stable behavior.
