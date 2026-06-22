import IotaktRuntime.Bridge.Message
import IotaktRuntime.Bridge.Driver

/-!
# IotaktRuntime.Bridge

The Henret v0.6.0 bridge (RFC 007): the only part of iotakt that depends
on Henret. It encodes readiness into Henret messages and drives readiness
into actor mailboxes through a guarded inject that respects Henret's
actual `inject` precondition (mailbox must exist).
-/
