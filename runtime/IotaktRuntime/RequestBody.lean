import IotaktRuntime.Http
import IotaktRuntime.Chunked
import IotaktRuntime.Native

/-!
# IotaktRuntime.RequestBody

Body-aware HTTP request reading for the iotakt ecosystem (v0.9).

`IotaktRuntime.Http.parse` parses request headers, and `IotaktRuntime.Chunked.decode`
decodes a complete chunked body — but nothing yet reads a full request
*including its body* off a live socket, handling both framings:

- **Content-Length: N** — read exactly N body bytes.
- **Transfer-Encoding: chunked** — read chunks until the `0\r\n\r\n`
  terminator, then reassemble.
- **neither** — no body (typical GET).

This module is the live read path jemmet needs: hand it an fd, get back a
fully-assembled `HttpRequest` with `body` populated.

## Usage

```lean
match ← RequestBody.readFull fd 65536 with
| .request req => ... -- req.body is the reassembled payload
| .incomplete  => ... -- peer closed early / framing not finished
| .error e     => ...
```
-/

namespace IotaktRuntime.RequestBody

open IotaktRuntime.Http IotaktRuntime.Native Iotakt.Model

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
  | tooLarge                   -- request exceeded maxBytes (413-style)
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

/-- Internal three-valued result for the read-phase helpers. -/
private inductive ReadPhase where
  | done (bytes : ByteArray)
  | incomplete
  | tooLarge

/-- Read until the header terminator is seen; returns the full raw bytes
read so far (headers + any body bytes that arrived with them). Retries on
`wouldBlock` (data may still be in flight after accept); stops on EOF.
Returns `.tooLarge` if the buffer exceeds `maxBytes`. -/
private def readUntilHeaders (fd : Int) (maxPolls maxBytes : Nat) : IO ReadPhase := do
  let mut buf := ByteArray.empty
  for _ in List.range maxPolls do
    if (splitHeaders buf).isSome then return .done buf
    if buf.size > maxBytes then return .tooLarge
    match ← Io.recv fd 4096 with
    | .bytes ba   => buf := appendBa buf ba
    | .wouldBlock => IO.sleep 10
    | .eof        => return (if (splitHeaders buf).isSome then .done buf else .incomplete)
    | _           => return .incomplete
  return (if (splitHeaders buf).isSome then .done buf else .incomplete)

/-- Read exactly `n` body bytes, given `have_` bytes already buffered. -/
private def readContentLength (fd : Int) (have_ : ByteArray) (n : Nat)
    (maxPolls maxBytes : Nat) : IO ReadPhase := do
  if n > maxBytes then return .tooLarge
  let mut body := have_
  for _ in List.range maxPolls do
    if body.size >= n then return .done (body.extract 0 n)
    match ← Io.recv fd 4096 with
    | .bytes ba   => body := appendBa body ba
    | .wouldBlock => IO.sleep 10
    | .eof        => return (if body.size >= n then .done (body.extract 0 n) else .incomplete)
    | _           => return .incomplete
  return (if body.size >= n then .done (body.extract 0 n) else .incomplete)

/-- Read a chunked body (given bytes already buffered) until the `0\r\n\r\n`
terminator, then decode it to the payload. -/
private def readChunked (fd : Int) (have_ : ByteArray) (maxPolls maxBytes : Nat) :
    IO ReadPhase := do
  let mut raw := have_
  let isComplete (b : ByteArray) : Bool :=
    ((String.fromUTF8? b |>.getD "").splitOn "0\r\n\r\n").length > 1
  let finish (b : ByteArray) : ReadPhase :=
    match IotaktRuntime.Chunked.decode b with | some d => .done d | none => .incomplete
  for _ in List.range maxPolls do
    if isComplete raw then return finish raw
    if raw.size > maxBytes then return .tooLarge
    match ← Io.recv fd 4096 with
    | .bytes ba   => raw := appendBa raw ba
    | .wouldBlock => IO.sleep 10
    | .eof        => return (if isComplete raw then finish raw else .incomplete)
    | _           => return .incomplete
  return (if isComplete raw then finish raw else .incomplete)

/-- Read a complete HTTP request — headers plus body — handling both
Content-Length and chunked framing. `maxBytes` bounds the total request
size (returns `.tooLarge` if exceeded — slow-loris / oversized-body
protection); `maxPolls` bounds each read phase. -/
def readFull (fd : Int) (maxBytes : Nat := 65536) (maxPolls : Nat := 50) :
    IO ReadResult := do
  match ← readUntilHeaders fd maxPolls maxBytes with
  | .incomplete => return .incomplete
  | .tooLarge   => return .tooLarge
  | .done raw =>
      match splitHeaders raw with
      | none => return .incomplete
      | some (header, bodySoFar) =>
          match HttpRequest.parse header with
          | none => return .incomplete
          | some req =>
              match framingOf req with
              | .none => return .request req
              | .contentLength n =>
                  match ← readContentLength fd bodySoFar n maxPolls maxBytes with
                  | .done body  => return .request { req with body := body }
                  | .incomplete => return .incomplete
                  | .tooLarge   => return .tooLarge
              | .chunked =>
                  match ← readChunked fd bodySoFar maxPolls maxBytes with
                  | .done body  => return .request { req with body := body }
                  | .incomplete => return .incomplete
                  | .tooLarge   => return .tooLarge

/-- Byte index just past the `\r\n\r\n` header terminator, or `none`. -/
def findHeaderEnd (buf : ByteArray) : Option Nat :=
  let s := String.fromUTF8? buf |>.getD ""
  let parts := s.splitOn "\r\n\r\n"
  if parts.length < 2 then none
  else some ((parts.headD "").toUTF8.size + 4)

/-- Byte length of a chunked body up to and including the `0\r\n\r\n`
terminator (measured from the start of `body`), or `none` if incomplete. -/
private def chunkedBodyLen (body : ByteArray) : Option Nat :=
  let s := String.fromUTF8? body |>.getD ""
  let parts := s.splitOn "0\r\n\r\n"
  if parts.length < 2 then none
  else some ((parts.headD "").toUTF8.size + 5)  -- "0\r\n\r\n" = 5 bytes

/-- Keep-alive-aware read: parse one request starting from `initial`
(leftover bytes from a previous request on the same connection), and return
the request plus any bytes that belong to the *next* request. This is what
makes HTTP/1.1 request pipelining correct — no bytes are dropped between
successive requests on one connection. -/
partial def readFromBuffer (fd : Int) (initial : ByteArray)
    (maxBytes : Nat := 65536) (maxPolls : Nat := 50) :
    IO (ReadResult × ByteArray) := do
  -- Phase 1: accumulate until the header terminator is present.
  let mut buf := initial
  let mut he := findHeaderEnd buf
  let mut polls := 0
  let mut stop := false
  while he.isNone && !stop && polls < maxPolls do
    polls := polls + 1
    if buf.size > maxBytes then return (.tooLarge, ByteArray.empty)
    match ← Io.recv fd 4096 with
    | .bytes ba   => buf := appendBa buf ba; he := findHeaderEnd buf
    | .wouldBlock => IO.sleep 10
    | .eof        => stop := true
    | _           => stop := true
  match he with
  | none => return (.incomplete, buf)
  | some headerEnd =>
      let header := buf.extract 0 (headerEnd - 4)
      match HttpRequest.parse header with
      | none => return (.incomplete, buf)
      | some req =>
          match framingOf req with
          | .none =>
              -- Request ends at the header terminator; rest is the next request.
              let leftover := buf.extract headerEnd buf.size
              return (.request req, leftover)
          | .contentLength n =>
              -- Accumulate until headerEnd + n bytes are present.
              let mut b := buf
              let mut p := polls
              let mut s := false
              while b.size < headerEnd + n && !s && p < maxPolls do
                p := p + 1
                if b.size > maxBytes then return (.tooLarge, ByteArray.empty)
                match ← Io.recv fd 4096 with
                | .bytes ba   => b := appendBa b ba
                | .wouldBlock => IO.sleep 10
                | .eof        => s := true
                | _           => s := true
              if b.size < headerEnd + n then return (.incomplete, b)
              else
                let body := b.extract headerEnd (headerEnd + n)
                let leftover := b.extract (headerEnd + n) b.size
                return (.request { req with body := body }, leftover)
          | .chunked =>
              -- Accumulate until the chunked terminator appears in the body region.
              let mut b := buf
              let mut p := polls
              let mut s := false
              let bodyDone (bb : ByteArray) : Bool :=
                (chunkedBodyLen (bb.extract headerEnd bb.size)).isSome
              while !bodyDone b && !s && p < maxPolls do
                p := p + 1
                if b.size > maxBytes then return (.tooLarge, ByteArray.empty)
                match ← Io.recv fd 4096 with
                | .bytes ba   => b := appendBa b ba
                | .wouldBlock => IO.sleep 10
                | .eof        => s := true
                | _           => s := true
              let bodyRegion := b.extract headerEnd b.size
              match chunkedBodyLen bodyRegion with
              | none => return (.incomplete, b)
              | some clen =>
                  let chunkedRaw := bodyRegion.extract 0 clen
                  let leftover := bodyRegion.extract clen bodyRegion.size
                  match IotaktRuntime.Chunked.decode chunkedRaw with
                  | some decoded => return (.request { req with body := decoded }, leftover)
                  | none         => return (.incomplete, b)

end IotaktRuntime.RequestBody
