import Iotakt.Model
import Iotakt.Proofs
import Iotakt.Fake

/-!
# iotakt

A Lean-first, non-blocking I/O readiness and socket-lifecycle library
for the Lean 4 ecosystem. iotakt sits between an HTTP layer (`jemmet`)
and an actor/scheduler runtime (`henret`):

```text
jemmet  →  iotakt  →  henret
(HTTP)     (I/O)       (actors)
```

iotakt's design principle is *Lean-first with an explicit trusted
boundary*: the model, the registry and its lifecycle, the event
translator, and readiness coalescing are pure Lean with machine-checked
safety theorems and **no hidden async runtime**. The optional native
reactor (epoll) is a thin, clearly-delimited trusted C shim.

This umbrella imports the Lean-only profile: the pure model
(`Iotakt.Model`), the proven safety theorems (`Iotakt.Proofs`), and the
deterministic fake poller (`Iotakt.Fake`). The Henret bridge is built
separately as `Iotakt.Bridge` (it is the only Henret-dependent module),
and the native backend behind its own optional build target.
-/
