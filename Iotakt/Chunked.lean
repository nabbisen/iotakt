import Iotakt.Http

/-!
# Iotakt.Chunked

HTTP/1.1 chunked transfer encoding (RFC 7230 §4.1) for the iotakt
ecosystem (v0.8).

Chunked encoding lets a server stream a response whose total length is
not known up front: the body is sent as a series of size-prefixed chunks,
terminated by a zero-length chunk. This is what jemmet needs for streaming
handlers (large files, server-sent events, generated content).

## Wire format

```text
<hex-size>\r\n
<chunk-data>\r\n
<hex-size>\r\n
<chunk-data>\r\n
0\r\n
\r\n
```

## Usage

```lean
-- Encode a single chunk
let frame := Chunked.encodeChunk "Hello".toUTF8   -- "5\r\nHello\r\n"

-- Encode a full body as one chunk + terminator
let body := Chunked.encodeBody "Hello, world!".toUTF8

-- Build a chunked response header (no Content-Length)
let header := Chunked.responseHeader 200 "OK"

-- Decode a complete chunked body back to bytes
let decoded := Chunked.decode received   -- some bytes | none if malformed
```
-/

namespace Iotakt.Chunked

open Iotakt.Http

/-- Lowercase hex digits for chunk sizes. -/
private def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat (n + 48)        -- '0'..'9'
  else Char.ofNat (n - 10 + 97)             -- 'a'..'f'

/-- Render a Nat as a lowercase hex string (no "0x"). -/
partial def toHex (n : Nat) : String :=
  if n == 0 then "0"
  else
    let rec go (m : Nat) (acc : String) : String :=
      if m == 0 then acc
      else go (m / 16) (String.singleton (hexDigit (m % 16)) ++ acc)
    go n ""

/-- Parse a lowercase/uppercase hex string to a Nat. Returns `none` on a
non-hex character. The chunk-size line may carry chunk extensions after a
';' — those are ignored. -/
def fromHex (s : String) : Option Nat :=
  let sizePart := (s.splitOn ";").headD s |>.trim
  if sizePart.isEmpty then none
  else
    sizePart.foldl (fun acc c =>
      match acc with
      | none => none
      | some v =>
        let d :=
          if c.isDigit then some (c.toNat - 48)
          else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 97 + 10)
          else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 65 + 10)
          else none
        d.map (fun digit => v * 16 + digit)) (some 0)

private def appendBa (a b : ByteArray) : ByteArray :=
  let c := ByteArray.mkEmpty (a.size + b.size)
  ByteArray.copySlice b 0 (ByteArray.copySlice a 0 c 0 a.size) a.size b.size

/-- Encode one chunk: `<hex-size>\r\n<data>\r\n`. -/
def encodeChunk (data : ByteArray) : ByteArray :=
  let sizeLine := (toHex data.size ++ "\r\n").toUTF8
  let suffix := "\r\n".toUTF8
  appendBa (appendBa sizeLine data) suffix

/-- The terminating zero-length chunk: `0\r\n\r\n`. -/
def terminator : ByteArray := "0\r\n\r\n".toUTF8

/-- Encode a whole body as a single chunk followed by the terminator.
For true streaming, call `encodeChunk` repeatedly then append `terminator`. -/
def encodeBody (data : ByteArray) : ByteArray :=
  if data.isEmpty then terminator
  else appendBa (encodeChunk data) terminator

/-- Build the header block for a chunked response (no Content-Length).
Caller streams `encodeChunk` frames and finally `terminator`. -/
def responseHeader (statusCode : Nat := 200) (statusText : String := "OK")
    (contentType : String := "text/plain") : ByteArray :=
  s!"HTTP/1.1 {statusCode} {statusText}\r\nContent-Type: {contentType}\r\nTransfer-Encoding: chunked\r\nConnection: keep-alive\r\n\r\n".toUTF8

/-- Decode a complete chunked body into the concatenated payload bytes.
Returns `none` if the framing is malformed or incomplete. The input must
be the body only (headers already stripped). -/
partial def decode (body : ByteArray) : Option ByteArray :=
  let s := String.fromUTF8? body |>.getD ""
  let rec go (rest : String) (acc : ByteArray) : Option ByteArray :=
    -- Each iteration: read a size line, then that many bytes, then CRLF.
    match rest.splitOn "\r\n" with
    | [] => none
    | sizeLine :: tail =>
        match fromHex sizeLine with
        | none => none
        | some 0 => some acc            -- terminator chunk → done
        | some n =>
            -- Reconstruct the remainder after the size line's CRLF.
            let afterSize := String.intercalate "\r\n" tail
            let chunkData := afterSize.take n
            if chunkData.toUTF8.size < n then none  -- incomplete
            else
              -- Skip the chunk data and its trailing CRLF.
              let afterData := afterSize.drop n
              let afterCRLF :=
                if afterData.startsWith "\r\n" then afterData.drop 2 else afterData
              go afterCRLF (appendBa acc chunkData.toUTF8)
  go s ByteArray.empty

/-- True when a response's headers declare chunked transfer encoding. -/
def isChunked (raw : ByteArray) : Bool :=
  let s := String.fromUTF8? raw |>.getD ""
  let headerPart := (s.splitOn "\r\n\r\n").headD ""
  headerPart.splitOn "\r\n" |>.any fun line =>
    let l := line.toLower
    l.startsWith "transfer-encoding:" && (l.splitOn "chunked").length > 1

end Iotakt.Chunked
