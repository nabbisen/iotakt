import Iotakt.Http
import Iotakt.Chunked
import Iotakt.Native

/-!
# Iotakt.RequestBody

Body-aware HTTP request reading for the iotakt ecosystem (v0.9).

`Iotakt.Http.parse` parses request headers, and `Iotakt.Chunked.decode`
decodes a complete chunked body — but nothing yet reads a full request
*including its body* off a live socket, handling both framings:

- **Content-Length: N** — read exactly N body bytes.
- **Transfer-Encoding: chunked** — read chunks until the `0\r\n\r\n`
  terminator, then reassemble.
- **neither** — no body (typical GET).

This module is the live read path henejt needs: hand it an fd, get back a
fully-assembled `HttpRequest` with `body` populated.

## Usage

```lean
match ← RequestBody.readFull fd 65536 with
| .request req => ... -- req.body is the reassembled payload
| .incomplete  => ... -- peer closed early / framing not finished
| .error e     => ...
```
-/

namespace Iotakt.RequestBody

open Iotakt.Http Iotakt.Native Iotakt.Model

/-- The framing a request declares for its body. -/
inductive BodyFraming where
  | none                       -- no body
  | contentLength (n : Nat)    -- exactly n bytes
  | chunked                    -- chunked until terminator
  deriving Repr, DecidableEq

/-- Result of reading a full request. -/
inductive ReadResult where
  | request (req : HttpRequest)
  | incomplete                 -- peer closed before the body finished
  | error (e : IoErrno)

private def appendBa (a b : ByteArray) : ByteArray :=
  let c := ByteArray.mkEmpty (a.size + b.size)
  ByteArray.copySlice b 0 (ByteArray.copySlice a 0 c 0 a.size) a.size b.size

/-- Determine the body framing from parsed request headers.
Chunked takes precedence over Content-Length per RFC 7230 §3.3.3. -/
def framingOf (req : HttpRequest) : BodyFraming :=
  let hasChunked := req.headers.any fun (k, v) =>
    k.toLower == "transfer-encoding" && (v.toLower.splitOn "chunked").length > 1
  if hasChunked then .chunked
  else
    match req.headers.find? (fun (k, _) => k.toLower == "content-length") with
    | some (_, v) =>
        match v.trim.toNat? with
        | some n => .contentLength n
        | none   => .none
    | none => .none

/-- Split a raw header+partial-body buffer into (headerBytes, bodySoFar).
Returns `none` if the header terminator `\r\n\r\n` is not present yet. -/
def splitHeaders (raw : ByteArray) : Option (ByteArray × ByteArray) :=
  let s := String.fromUTF8? raw |>.getD ""
  let parts := s.splitOn "\r\n\r\n"
  if parts.length < 2 then none
  else
    let headerStr := parts.headD ""
    let headerLen := headerStr.toUTF8.size + 4  -- + "\r\n\r\n"
    let header := raw.extract 0 headerStr.toUTF8.size
    let body := raw.extract headerLen raw.size
    some (header, body)

/-- Read until the header terminator is seen; returns the full raw bytes
read so far (headers + any body bytes that arrived with them). Retries on
`wouldBlock` (data may still be in flight after accept); stops on EOF. -/
private def readUntilHeaders (fd : Int) (maxPolls : Nat) : IO (Option ByteArray) := do
  let mut buf := ByteArray.empty
  for _ in List.range maxPolls do
    if (splitHeaders buf).isSome then return some buf
    match ← Io.recv fd 4096 with
    | .bytes ba   => buf := appendBa buf ba
    | .wouldBlock => IO.sleep 10
    | .eof        => return (if (splitHeaders buf).isSome then some buf else none)
    | _           => return none
  return (if (splitHeaders buf).isSome then some buf else none)

/-- Read exactly `n` body bytes, given `have_` bytes already buffered. -/
private def readContentLength (fd : Int) (have_ : ByteArray) (n : Nat)
    (maxPolls : Nat) : IO (Option ByteArray) := do
  let mut body := have_
  for _ in List.range maxPolls do
    if body.size >= n then return some (body.extract 0 n)
    match ← Io.recv fd 4096 with
    | .bytes ba   => body := appendBa body ba
    | .wouldBlock => IO.sleep 10
    | .eof        => return (if body.size >= n then some (body.extract 0 n) else none)
    | _           => return none
  return (if body.size >= n then some (body.extract 0 n) else none)

/-- Read a chunked body (given bytes already buffered) until the `0\r\n\r\n`
terminator, then decode it to the payload. -/
private def readChunked (fd : Int) (have_ : ByteArray) (maxPolls : Nat) :
    IO (Option ByteArray) := do
  let mut raw := have_
  let isComplete (b : ByteArray) : Bool :=
    ((String.fromUTF8? b |>.getD "").splitOn "0\r\n\r\n").length > 1
  for _ in List.range maxPolls do
    if isComplete raw then return Iotakt.Chunked.decode raw
    match ← Io.recv fd 4096 with
    | .bytes ba   => raw := appendBa raw ba
    | .wouldBlock => IO.sleep 10
    | .eof        => return (if isComplete raw then Iotakt.Chunked.decode raw else none)
    | _           => return none
  return (if isComplete raw then Iotakt.Chunked.decode raw else none)

/-- Read a complete HTTP request — headers plus body — handling both
Content-Length and chunked framing. `maxPolls` bounds each read phase. -/
def readFull (fd : Int) (_maxBytes : Nat := 65536) (maxPolls : Nat := 50) :
    IO ReadResult := do
  match ← readUntilHeaders fd maxPolls with
  | none => return .incomplete
  | some raw =>
      match splitHeaders raw with
      | none => return .incomplete
      | some (header, bodySoFar) =>
          -- Parse headers (parse expects the header block)
          match HttpRequest.parse header with
          | none => return .incomplete
          | some req =>
              match framingOf req with
              | .none => return .request req
              | .contentLength n =>
                  match ← readContentLength fd bodySoFar n maxPolls with
                  | some body => return .request { req with body := body }
                  | none      => return .incomplete
              | .chunked =>
                  match ← readChunked fd bodySoFar maxPolls with
                  | some body => return .request { req with body := body }
                  | none      => return .incomplete

end Iotakt.RequestBody
