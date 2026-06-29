import «Jemmet»
import Iotakt.Router  -- optional convenience module; imported directly

/-!
# jemmet demo (prototype seed — NOT part of iotakt)

Handoff material for the separate jemmet project. A runnable HTTP/1.1
service built on the `Jemmet` prototype (which is built on iotakt's
`Iotakt.Server` handoff surface). Demonstrates keep-alive, multiple routes,
request bodies, and request-size limits.

```
-- in the jemmet project, with iotakt as a dependency:
lake build jemmet-demo
.lake/build/bin/jemmet-demo &
curl http://127.0.0.1:49997/                       # home
curl http://127.0.0.1:49997/health                 # ok
curl http://127.0.0.1:49997/users/42               # JSON-ish
curl -X POST --data 'payload' http://127.0.0.1:49997/echo
curl http://127.0.0.1:49997/a http://127.0.0.1:49997/b   # keep-alive: 2 on 1 conn
```
-/

open Jemmet Iotakt.Http Iotakt.Router

/-- A small JSON-ish body builder (no real JSON lib — string assembly). -/
def jsonUser (id : String) : HttpResponse :=
  let body := s!"\{\"id\":\"{id}\",\"kind\":\"user\"}"
  { statusCode := 200, statusText := "OK", body := body.toUTF8
    headers := [("Content-Type", "application/json"),
                ("Content-Length", toString body.toUTF8.size)] }

/-- The jemmet application router. -/
def appRouter : Router :=
  Router.empty
    |>.get  "/"          (fun _ => HttpResponse.ok "jemmet prototype on iotakt")
    |>.get  "/health"    (fun _ => HttpResponse.ok "ok")
    |>.get  "/users/:id" (fun p => jsonUser (p.get "id"))
    |>.get  "/a"         (fun _ => HttpResponse.ok "A")
    |>.get  "/b"         (fun _ => HttpResponse.ok "B")
    |>.post "/echo"      (fun _ => HttpResponse.ok "echoed")

def main : IO Unit := do
  let cfg : Config := { port := 49997, maxBytes := 8192, idleTimeoutMs := 3000 }
  IO.println "jemmet prototype demo (built on Iotakt.Server)"
  IO.println s!"Listening on 127.0.0.1:{cfg.port} ({appRouter.size} routes, keep-alive, ~5s)"
  IO.println ""
  match ← Jemmet.run cfg appRouter 50 with
  | .ok total => IO.println s!"Total requests served: {total}"
  | .error e  => IO.println s!"jemmet failed: {e}"
  IO.println "jemmet demo done"
