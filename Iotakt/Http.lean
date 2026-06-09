import Iotakt.WriteBuffer

/-!
# Iotakt.Http

A minimal HTTP/1.0 parser and response builder for the iotakt ecosystem
(v0.4 henejt integration preparation).

This is not a production HTTP implementation. It demonstrates:
1. Using iotakt's non-blocking `recv` to accumulate request bytes.
2. Using `WriteBuffer` to stream a response with correct `Content-Length`.
3. The read→parse→respond→close connection lifecycle.

`henejt` will replace this with a full HTTP/1.1 parser, routing, and
connection keep-alive. This module documents the boundary between iotakt
(byte streams) and henejt (HTTP protocol state).

## Usage

```lean
-- Server side
let req ← HttpRequest.readFrom fd 4096   -- accumulate until \r\n\r\n
match req with
| some r => do
    let resp := HttpResponse.ok "Hello from iotakt!"
    let wb := WriteBuffer.empty.push resp.toBytes
    let (_, _) ← wb.flushAll fd

-- Client side
let request := HttpRequest.get "127.0.0.1" 49980 "/"
let wb := WriteBuffer.empty.push request.toBytes
let (_, _) ← wb.flushAll fd
let body ← HttpResponse.readBody fd 64 * 1024
```
-/

namespace Iotakt.Http

open Iotakt.WriteBuffer Iotakt.Native

/-! ## Request -/

/-- A parsed HTTP request (minimal, v0.4). -/
structure HttpRequest where
  method  : String
  path    : String
  version : String
  headers : List (String × String)
  body    : ByteArray := ByteArray.empty
  deriving Inhabited

namespace HttpRequest

/-- Build a raw HTTP/1.0 GET request. -/
def get (host : String) (path : String) : ByteArray :=
  let s := s!"GET {path} HTTP/1.0\r\nHost: {host}\r\nConnection: close\r\n\r\n"
  s.toUTF8

/-- Parse the method and path from the first request line. -/
def parseRequestLine (line : String) : Option (String × String × String) :=
  let parts := line.trim.splitOn " "
  match parts with
  | [method, path, version] => some (method, path, version)
  | _ => none

/-- Read up to `maxBytes` from `fd`, accumulating until the HTTP header
terminator `\r\n\r\n` is found. Returns `some buf` when complete or
`none` on error/EOF. -/
def readHeaders (fd : Int) (maxBytes : Nat) : IO (Option ByteArray) := do
  let mut buf := ByteArray.empty
  for _ in List.range 100 do  -- bound iterations
    let chunkSize := min 4096 (maxBytes - buf.size)
    match ← Io.recv fd chunkSize with
    | .bytes ba =>
        buf := ByteArray.copySlice ba 0 (ByteArray.mkEmpty (buf.size + ba.size))
                  0 ba.size |> fun dst =>
          ByteArray.copySlice buf 0 dst 0 buf.size
        -- Check for header terminator
        let s := String.fromUTF8? buf |>.getD ""
        if (s.splitOn "\r\n\r\n").length > 1 then return some buf
    | .wouldBlock => break  -- partial receive; retry when readable
    | .eof        => return none
    | .error _    => return none
    | .interrupted => pure ()
  if buf.isEmpty then return none
  -- May have headers without body; return what we have
  let s := String.fromUTF8? buf |>.getD ""
  if (s.splitOn "\r\n\r\n").length > 1 then return some buf else return none

/-- Parse a raw header buffer into an `HttpRequest`. -/
def parse (raw : ByteArray) : Option HttpRequest :=
  let s := String.fromUTF8? raw |>.getD ""
  let parts := s.splitOn "\r\n\r\n"
  match parts with
  | headerPart :: _ =>
      let lines := headerPart.splitOn "\r\n"
      match lines with
      | [] => none
      | firstLine :: headerLines =>
          match parseRequestLine firstLine with
          | none => none
          | some (method, path, version) =>
              let headers := headerLines.filterMap fun l =>
                match l.splitOn ": " with
                | [k, v] => some (k, v)
                | _ => none
              some { method, path, version, headers }
  | _ => none

end HttpRequest

/-! ## Response -/

/-- An HTTP/1.0 response. -/
structure HttpResponse where
  statusCode : Nat    := 200
  statusText : String := "OK"
  headers    : List (String × String) := []
  body       : ByteArray := ByteArray.empty
  deriving Inhabited

namespace HttpResponse

/-- Build a 200 OK response with a plain-text body. -/
def ok (body : String) : HttpResponse :=
  let ba := body.toUTF8
  { statusCode := 200
    statusText := "OK"
    headers    := [("Content-Type", "text/plain"), ("Content-Length", toString ba.size)]
    body       := ba }

/-- Build a 404 Not Found response. -/
def notFound (path : String) : HttpResponse :=
  let body := s!"404 Not Found: {path}".toUTF8
  { statusCode := 404
    statusText := "Not Found"
    headers    := [("Content-Type", "text/plain"), ("Content-Length", toString body.size)]
    body       := body }

/-- Serialise the response to bytes (headers + body). -/
def toBytes (r : HttpResponse) : ByteArray :=
  let headerLines := r.headers.map fun (k, v) => s!"{k}: {v}"
  let headerStr := String.intercalate "\r\n" headerLines
  let headersBA :=
    s!"HTTP/1.0 {r.statusCode} {r.statusText}\r\n{headerStr}\r\nConnection: close\r\n\r\n"
    |>.toUTF8
  -- Concatenate headers + body
  let total := headersBA.size + r.body.size
  let out := ByteArray.mkEmpty total
  let out := ByteArray.copySlice headersBA 0 out 0 headersBA.size
  ByteArray.copySlice r.body 0 out headersBA.size r.body.size

/-- Read an HTTP/1.0 response body from `fd` until EOF.
Returns the full response bytes (headers + body). -/
def readAll (fd : Int) (maxBytes : Nat := 64 * 1024) : IO ByteArray := do
  let mut buf := ByteArray.empty
  for _ in List.range 200 do
    if buf.size >= maxBytes then break
    let chunkSize := min 4096 (maxBytes - buf.size)
    match ← Io.recv fd chunkSize with
    | .bytes ba =>
        -- Append ba to buf
        let newSize := buf.size + ba.size
        let newBuf := ByteArray.mkEmpty newSize
        let newBuf := ByteArray.copySlice buf 0 newBuf 0 buf.size
        buf := ByteArray.copySlice ba 0 newBuf buf.size ba.size
    | .eof       => break
    | .wouldBlock => break  -- connection closed or no more data
    | _          => break
  return buf

/-- Parse the status code from a raw HTTP response. -/
def parseStatus (raw : ByteArray) : Option Nat :=
  let s := String.fromUTF8? raw |>.getD ""
  let firstLine := (s.splitOn "\r\n").head?
  firstLine.bind fun l =>
    (l.splitOn " ").get? 1 |>.bind fun code => code.toNat?

/-- Extract the response body (everything after `\r\n\r\n`). -/
def extractBody (raw : ByteArray) : Option String :=
  let s := String.fromUTF8? raw |>.getD ""
  match s.splitOn "\r\n\r\n" with
  | _ :: bodyPart :: _ => some bodyPart
  | _ => none

end HttpResponse

end Iotakt.Http
