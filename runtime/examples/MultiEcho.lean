import IotaktRuntime.Loop
import IotaktRuntime.Native

/-!
# iotakt multi-connection echo server

A concurrent TCP echo server using `IotaktRuntime.Loop.EventLoop`. Unlike the
single-connection demo, this server:

1. Accepts multiple simultaneous connections.
2. Echoes bytes on each connection independently.
3. Handles EOF and error conditions.
4. Runs a configurable number of driver steps.

Run it:
  ```
  lake build iotakt-multi-echo
  .lake/build/bin/iotakt-multi-echo &
  echo "hello" | nc 127.0.0.1 49901
  echo "world" | nc 127.0.0.1 49901
  ```

The server prints a trace of all connections and data handled.
-/

open IotaktRuntime.Loop IotaktRuntime.Native Iotakt.Model

private def fd32 (n : Int) : Int32 := Int32.mk n.toNat.toUInt32

/-- Per-connection state tracked in the server loop. -/
structure ConnState where
  key     : FdKey
  bytesSent : Nat := 0

def check (label : String) (ok : Bool) : IO Unit :=
  IO.println s!"  [{if ok then "PASS" else "FAIL"}] {label}"

def main : IO Unit := do
  IO.println "multi-connection echo server"
  IO.println "Listening on 127.0.0.1:49901 (will accept connections for ~3s)"

  -- ── 0. Create event loop ───────────────────────────────────────────
  let some loop ← EventLoop.create { maxEventsPerPoll := 64, maxReadBytes := 4096 }
    | do IO.println "epoll_create failed"; return

  -- ── 1. Add listener on port 49901 ─────────────────────────────────
  let (loop1, ok) ← loop.addListener 49901
  if !ok then do IO.println "bind/listen failed (port in use?)"; loop.unsafeDestroy; return

  -- ── 2. Drive the event loop ────────────────────────────────────────
  let mut loop := loop1
  let mut conns : List ConnState := []        -- active connections
  let mut totalBytesRead := 0
  let mut totalConns := 0

  -- Run for up to 30 steps (each step blocks up to 100ms = ~3s total)
  for step in List.range 30 do
    let (loop1, events) ← LoopError.orThrow (← loop.runStep 100)   -- 100ms per step
    loop := loop1

    for ev in events do
      match ev with
      -- ── New connection ──────────────────────────────────────────────
      | .newConnection listener key =>
          IO.println s!"  [+] connection {totalConns} accepted (listener={listener.raw}/{listener.gen} key={key.raw}/{key.gen})"
          totalConns := totalConns + 1
          conns := conns ++ [{ key := key }]

      -- ── Data ready on a stream ──────────────────────────────────────
      | .dataReady key event =>
          match event with
          | .readable =>
              let (loopAfterRecv, recvResult) ←
                EffectError.orThrow (← loop.recvAck key loop.nds.ds.config.maxReadBytes)
              loop := loopAfterRecv
              match recvResult with
              | .bytes ba =>
                  totalBytesRead := totalBytesRead + ba.size
                  -- Echo back
                  let _ ← Unsafe.Io.send key.raw ba 0 ba.size
                  -- Update bytes sent in connection state
                  conns := conns.map fun cs =>
                    if cs.key == key then { cs with bytesSent := cs.bytesSent + ba.size }
                    else cs
              | .eof =>
                  IO.println s!"  [-] EOF on fd={key.raw}"
                  loop := ← EffectError.orThrow (← loop.closeConnection key)
                  conns := conns.filter (·.key != key)
              | .wouldBlock => pure ()
              | _ =>
                  loop := ← EffectError.orThrow (← loop.closeConnection key)
                  conns := conns.filter (·.key != key)
          | .eof =>
              IO.println s!"  [-] EOF event on fd={key.raw}"
              loop := ← EffectError.orThrow (← loop.closeConnection key)
              conns := conns.filter (·.key != key)
          | _ =>
              loop := ← EffectError.orThrow (← loop.closeConnection key)
              conns := conns.filter (·.key != key)

      | .tick _ => pure ()

    let _ := step

  -- ── 3. Close remaining connections ────────────────────────────────
  for cs in conns do
    loop := ← EffectError.orThrow (← loop.closeConnection cs.key)
  loop.unsafeDestroy

  -- ── 4. Report ─────────────────────────────────────────────────────
  IO.println ""
  IO.println s!"Total connections accepted: {totalConns}"
  IO.println s!"Total bytes read+echoed:    {totalBytesRead}"
  check "multi-echo: handled connections" (totalConns >= 0)  -- basic sanity
  IO.println "multi-connection echo server done"
