package relay

import upstream "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/relay"

// Reuse the pinned public resource types so existing server fixtures and
// configuration callers remain compatible with the upstream package.
type Resources = upstream.Resources
type RelayLimit = upstream.RelayLimit

func DefaultResources() Resources { return upstream.DefaultResources() }
func DefaultLimit() *RelayLimit   { return upstream.DefaultLimit() }
