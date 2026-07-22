# FFI Hardening and ByteArray Ownership Contract

**iotakt — RFC 028**

This document specifies the formal ownership contract between iotakt's Lean
code and the native C shim (`native/iotakt_io.c`, `native/iotakt_socket.c`).
All current C functions comply with this contract, and all future native
additions must comply before merging.

---

## Motivation

Lean 4 uses a reference-counted memory model. C code that touches Lean
heap objects must follow Lean's ownership protocol exactly:

- Every `lean_object *` has a reference count managed by `lean_inc` / `lean_dec`.
- A function that *owns* a parameter is responsible for calling `lean_dec` on it
  (or transferring ownership to a return value).
- A function that *borrows* a parameter must not call `lean_dec`; the caller
  owns it.
- Returning a `lean_object *` transfers ownership to the caller.

Violating this contract causes either a **double-free** (use-after-free,
segfault) or a **memory leak** (refcount never reaches zero). Both are
silent data corruption in a production server.

---

## Contract specification

### C.1 — `lean_obj_arg` parameters (owned)

Any `lean_obj_arg w` parameter (the world token in `IO` functions) is
**owned** by the callee. The callee must call `lean_dec(w)` exactly once
before returning, or pass ownership to `lean_io_result_mk_ok`.

```c
// CORRECT: lean_dec called once
LEAN_EXPORT lean_obj_res iotakt_send(..., lean_obj_arg w) {
    ...
    lean_dec(w);
    return lean_io_result_mk_ok(lean_int64_to_int(status));
}
```

```c
// WRONG: lean_dec not called on error path → memory leak
LEAN_EXPORT lean_obj_res bad_send(..., lean_obj_arg w) {
    if (fd < 0) return lean_io_result_mk_ok(...);  // BUG: w leaked
    lean_dec(w);
    return lean_io_result_mk_ok(...);
}
```

### C.2 — `b_lean_obj_arg` parameters (borrowed)

Any `b_lean_obj_arg` parameter is **borrowed**: the callee must not call
`lean_inc` or `lean_dec` on it, and must not store a pointer to it beyond
the lifetime of the call.

```c
// CORRECT: ba is borrowed — never call lean_dec(ba)
LEAN_EXPORT lean_obj_res iotakt_send(
    int32_t fd, b_lean_obj_arg ba, ..., lean_obj_arg w)
{
    int64_t status = iotakt_validate_send_slice(
        lean_sarray_size(ba), offset, len);
    if (status != 0) {
        lean_dec(w);
        return lean_io_result_mk_ok(lean_int64_to_int(status));
    }
    const uint8_t *buf = lean_sarray_cptr(ba) + offset;  // borrow pointer only
    ssize_t n = send((int)fd, buf, len, MSG_NOSIGNAL);
    lean_dec(w);  // only w is owned
    return lean_io_result_mk_ok(lean_int64_to_int(n >= 0 ? n : -errno));
}
```

### C.3 — Returned `lean_object *` (ownership transferred)

Objects passed to `lean_io_result_mk_ok(x)` transfer ownership of `x` to
the Lean runtime. The C function must not touch `x` after this call. Each
object (`inner`, `outer`) must be set up completely before being passed to
`lean_io_result_mk_ok`.

### C.4 — Nested `Prod` construction

Lean's `A × B × C` is right-associative: `A × (B × C)`. To build
`Prod.mk a (Prod.mk b c)` in C:

```c
lean_object *inner = lean_alloc_ctor(0, 2, 0);
lean_ctor_set(inner, 0, b_obj);   // field 0 = b
lean_ctor_set(inner, 1, c_obj);   // field 1 = c

lean_object *outer = lean_alloc_ctor(0, 2, 0);
lean_ctor_set(outer, 0, a_obj);   // field 0 = a
lean_ctor_set(outer, 1, inner);   // field 1 = inner (ownership transferred)

return lean_io_result_mk_ok(outer);
```

**Anti-pattern (double-free):** allocating extra `lean_object *` wrappers,
setting children of multiple objects to the same pointer, then calling
`lean_dec` on one of the wrappers. This decrements the child's refcount
prematurely while the other wrapper still holds a pointer. See the bug
fixed in `iotakt_recvfrom` during v0.3 development for a concrete example.

### C.5 — `ByteArray` allocation (Option A policy)

iotakt uses **Option A** (allocate-in-C, transfer-to-Lean) for all recv
buffers:

1. Allocate a `lean_sarray_object` with `lean_alloc_sarray(1, capacity, capacity)`.
2. Write data into the underlying buffer with `lean_sarray_cptr(ba)`.
3. Update `lean_to_sarray(ba)->m_size` to the actual bytes received.
4. Return the `lean_object *` via `lean_io_result_mk_ok` (ownership transferred).

```c
lean_object *data_ba = lean_alloc_sarray(1, max_bytes, max_bytes);
uint8_t *buf = lean_sarray_cptr(data_ba);
ssize_t n = recv(fd, buf, max_bytes, MSG_DONTWAIT);
if (n >= 0) lean_to_sarray(data_ba)->m_size = (size_t)n;
else        lean_to_sarray(data_ba)->m_size = 0;
return lean_io_result_mk_ok(data_ba);
```

**Rationale**: Option A eliminates one copy compared to allocating in Lean
and passing the buffer to C. The tradeoff is that C code must correctly
manage the size field. This is documented and tested by INV-1a/INV-1b in
the v0.4 integration test.

### C.6 — No pointer retention across calls

C functions must not retain any `lean_sarray_cptr` pointer past the end of
the call. Lean's GC may move objects (though the current implementation does
not, future versions may). All pointer arithmetic must complete before
`lean_dec(w)` and `lean_io_result_mk_ok`.

---

## Compliance verification

Every native function is verified against this contract in two ways:

1. **Static review**: the diff for any new C function must include a reviewer
   note confirming C.1–C.6 compliance.
2. **Runtime verification**: `iotakt-v4-test` section C and the native boundary
   suite run live FFI and request-validation checks:
   - INV-1a/b: recv buffer sizes match the actual bytes received.
   - INV-2: recv after peer-close returns a Lean value (not a crash).
   - INV-3: send after peer-close returns a Lean error value (not SIGPIPE).
   - INV-4: recvfrom peer-address buffer is exactly 6 bytes.
   - RFC065-C-SLICE-001: TCP/UDP invalid slices return `invalidSlice` through
     the defensive C path with zero syscall-gate invocations.
   - RFC065-C-SLICE-001: a synthetic in-bounds length above `SSIZE_MAX` returns
     `nativeLengthLimit` with zero syscall-gate invocations; a valid positive
     control reaches the gate exactly once.

---

## Known deviations

| ID | Description | Risk | Status |
|----|-------------|------|--------|
| DEV-001 | `lean_alloc_sarray` allocates `capacity` bytes even when `n < capacity`; unused bytes are readable but contain uninitialized data. | Low: Lean code never reads beyond `m_size`. | Accepted |
| DEV-002 | `iotakt_send` and `iotakt_sendto` do not call `lean_inc(ba)` because they use `b_lean_obj_arg` (borrow). If the Lean GC were to collect `ba` during `send()`, the buffer pointer would dangle. This is safe in Lean 4's current non-moving GC. | Low: non-moving GC guarantee. | Accepted; revisit if Lean gains a moving GC. |

---

## Checklist for new native functions

Before merging any new `LEAN_EXPORT` function:

- [ ] Every `lean_obj_arg` parameter has exactly one `lean_dec` call on every code path.
- [ ] No `lean_dec` is called on any `b_lean_obj_arg` parameter.
- [ ] All returned `lean_object *` are fully initialized before passing to `lean_io_result_mk_ok`.
- [ ] No `lean_object *` pointer is used after transferring it to a `lean_ctor_set` parent.
- [ ] `lean_alloc_sarray` size and `m_size` are set consistently.
- [ ] No `lean_sarray_cptr` pointer is retained past the end of the function body.
- [ ] Function compiles clean with `-Wall -Wextra -Werror`.
