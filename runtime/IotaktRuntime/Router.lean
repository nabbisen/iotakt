import IotaktRuntime.Http

/-!
# IotaktRuntime.Router

A small path-based HTTP router for the iotakt ecosystem (v0.6).

This is the routing layer that jemmet would build on. It maps a
`(method, path)` pair to a handler that produces an `HttpResponse`.
Routes support:

- Exact paths: `/`, `/health`, `/api/status`
- Single-segment wildcards: `/users/:id` (captures `id`)
- Method matching: GET, POST, etc.

The router is pure (no IO): given a request, it returns the matched
handler's response or a 404. Handlers are `RouteParams → HttpResponse`
functions, so they can read captured path parameters.

## Usage

```lean
let router := Router.empty
  |>.get  "/"            (fun _ => HttpResponse.ok "home")
  |>.get  "/health"      (fun _ => HttpResponse.ok "ok")
  |>.get  "/users/:id"   (fun p => HttpResponse.ok s!"user {p.get "id"}")
  |>.post "/users"       (fun _ => HttpResponse.ok "created")

let resp := router.dispatch "GET" "/users/42"
-- resp.body = "user 42"
```
-/

namespace IotaktRuntime.Router

open IotaktRuntime.Http

/-- Captured path parameters, e.g. `:id` → "42". -/
structure RouteParams where
  params : List (String × String) := []

namespace RouteParams

/-- Look up a captured parameter; returns "" if absent. -/
def get (p : RouteParams) (key : String) : String :=
  p.params.find? (·.1 == key) |>.map (·.2) |>.getD ""

/-- Look up a captured parameter as `Option`. -/
def get? (p : RouteParams) (key : String) : Option String :=
  p.params.find? (·.1 == key) |>.map (·.2)

end RouteParams

/-- A handler maps captured params to a response. -/
abbrev Handler := RouteParams → HttpResponse

/-- One route: method, path pattern (segments), and handler. -/
structure Route where
  method  : String
  pattern : List String   -- path split on "/", e.g. ["users", ":id"]
  handler : Handler

/-- Split a path into non-empty segments. `/users/42` → `["users", "42"]`. -/
def pathSegments (path : String) : List String :=
  -- Strip query string, then split on "/"
  let pathOnly := (path.splitOn "?").headD path
  pathOnly.splitOn "/" |>.filter (· != "")

/-- Try to match a pattern against concrete segments, capturing `:params`.
Returns `none` if the pattern does not match. -/
def matchPattern (pattern segments : List String) : Option RouteParams :=
  let rec go (pat seg : List String) (acc : List (String × String)) :
      Option (List (String × String)) :=
    match pat, seg with
    | [], [] => some acc
    | p :: ps, s :: ss =>
        if p.startsWith ":" then
          -- wildcard: capture
          go ps ss ((p.drop 1, s) :: acc)
        else if p == s then
          go ps ss acc
        else
          none
    | _, _ => none  -- length mismatch
  (go pattern segments []).map (fun ps => { params := ps.reverse })

/-- The router: an ordered list of routes plus a fallback. -/
structure Router where
  routes      : List Route := []
  notFoundFn  : String → HttpResponse := HttpResponse.notFound

namespace Router

/-- An empty router (everything 404s). -/
def empty : Router := {}

/-- Register a route for an arbitrary method. -/
def route (r : Router) (method path : String) (h : Handler) : Router :=
  { r with routes := r.routes ++ [{ method, pattern := pathSegments path, handler := h }] }

/-- Register a GET route. -/
def get (r : Router) (path : String) (h : Handler) : Router :=
  r.route "GET" path h

/-- Register a POST route. -/
def post (r : Router) (path : String) (h : Handler) : Router :=
  r.route "POST" path h

/-- Register a PUT route. -/
def put (r : Router) (path : String) (h : Handler) : Router :=
  r.route "PUT" path h

/-- Register a DELETE route. -/
def delete (r : Router) (path : String) (h : Handler) : Router :=
  r.route "DELETE" path h

/-- Find the first matching route for a method + path. -/
def matchRoute (r : Router) (method path : String) : Option (Route × RouteParams) :=
  let segs := pathSegments path
  r.routes.findSome? fun rt =>
    if rt.method == method then
      (matchPattern rt.pattern segs).map (fun p => (rt, p))
    else none

/-- Dispatch a request to the matching handler, or 404. -/
def dispatch (r : Router) (method path : String) : HttpResponse :=
  match r.matchRoute method path with
  | some (rt, params) => rt.handler params
  | none              => r.notFoundFn path

/-- Dispatch a parsed `HttpRequest`. -/
def dispatchRequest (r : Router) (req : HttpRequest) : HttpResponse :=
  r.dispatch req.method req.path

/-- Number of registered routes. -/
def size (r : Router) : Nat := r.routes.length

end Router

end IotaktRuntime.Router
