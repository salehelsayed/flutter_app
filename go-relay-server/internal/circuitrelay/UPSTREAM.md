# Pinned circuit relay implementation

Source: github.com/libp2p/go-libp2p v0.50.0,
commit 3c2c902122cb6fae3897f729a3dbb9d4665ae90d,
directory p2p/protocol/circuitv2/relay.
Module checksum: h1:A0tBP6mr6GV7l5ip2Q04a/IxPqVYYaCiif5s8JuXkN4=.

MIT license is preserved in LICENSE. No wire protocol or module pin changes.

- acl.go, constraints.go, options.go: unchanged upstream source.
- relay.go: LL-24 reservation connection binding, exact-connection STOP
  negotiation, bounded acknowledgement/publication synchronization, and
  connection-aware lifecycle with matching constraint cleanup.
- resources.go and metrics.go: adapters to upstream public types/defaults and
  shared metric collectors, avoiding nominal type and registration conflicts.

Production startup installs the shared default metrics tracer through
`newCircuitRelayService`; its registry is exercised after real relay traffic.

Upstream source SHA-256:

903c5147653d7df85950667ace963d5aa512add8d18bfe1ca81b7941d6f3fdca  acl.go
fb2b6a0e5ef67a5e30d0387bb3c6280998b4ca5423623f66f165b5397a854d46  constraints.go
392bf931d20905de2d28e731fe2991bcdbf959172f713defcf290d05f3060642  options.go
66e9d1bfc4a1dae448250627a6de80681c238f56c7ef0950f30aa9bf4b614d74  relay.go
d0aaf27e3707bc1d96b44b0c4f485dc3dfeef67f07d003fb93a21eac635c8e03  resources.go
d82bcebccc77119252f285beac0b5672514e5d6a1447e8e755d3ddb246da1e06  metrics.go
