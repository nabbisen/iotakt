import Iotakt.Model.Update
import Iotakt.Model.Fd
import Iotakt.Model.Interest
import Iotakt.Model.Event
import Iotakt.Model.Result
import Iotakt.Model.Registry
import Iotakt.Model.Lifecycle
import Iotakt.Model.Translate
import Iotakt.Model.Coalesce

/-!
# Iotakt.Model

The pure, Lean-only iotakt model (RFC 001–006). Builds with no C
compiler, no OS reactor, and no Henret dependency.

It defines file-descriptor identity (`FdKey`), the resource registry and
its lifecycle, the backend-neutral event vocabulary, the pure event
translator with stale/unknown-event rejection, and readiness coalescing
— together with the PROVEN safety theorems each carries. The Henret
bridge (`Iotakt.Bridge`) and the deterministic fake poller
(`Iotakt.Fake`) are built on top of this model.
-/
