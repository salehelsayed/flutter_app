package node

import (
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

func (n *Node) currentFeatureFlags() FeatureFlags {
	if n == nil {
		return DefaultFeatureFlags()
	}

	n.mu.RLock()
	defer n.mu.RUnlock()
	if n.featureFlags != nil {
		return *n.featureFlags
	}
	return DefaultFeatureFlags()
}

func (n *Node) reservationAwareHealthEnabled() bool {
	return n.currentFeatureFlags().EnableReservationAwareHealth
}

func limitRelayAddresses(addrs []string, flags FeatureFlags) []string {
	if len(addrs) == 0 {
		return nil
	}

	if flags.EnableMultiRelayRouting {
		return append([]string(nil), addrs...)
	}

	// The flag limits relay peers, not addresses. Keep every family and
	// transport for the first valid peer so libp2p can race its alternatives.
	var selected peer.ID
	var limited []string
	for _, addr := range addrs {
		maddr, err := ma.NewMultiaddr(addr)
		if err != nil {
			continue
		}
		info, err := peer.AddrInfoFromP2pAddr(maddr)
		if err != nil {
			continue
		}
		if selected == "" {
			selected = info.ID
		}
		if info.ID == selected {
			limited = append(limited, addr)
		}
	}
	if selected == "" {
		// Keep an invalid explicit configuration nonempty. Collapsing it to nil
		// would make buildRelaySelector silently substitute the default relay.
		return append([]string(nil), addrs...)
	}
	return limited
}

func featureFlagsStatusMap(flags FeatureFlags) map[string]bool {
	return map[string]bool{
		"enableSharedRelayBackend":     flags.EnableSharedRelayBackend,
		"enableMultiRelayRouting":      flags.EnableMultiRelayRouting,
		"enableReservationAwareHealth": flags.EnableReservationAwareHealth,
		"enableInPlaceRelayRecovery":   flags.EnableInPlaceRelayRecovery,
		"enableResumeGroupRecovery":    flags.EnableResumeGroupRecovery,
		"enableDeferredDirectAck":      flags.EnableDeferredDirectAck,
		"enableLibp2pLANDial":          flags.EnableLibp2pLANDial,
		"enableLibp2pLANMedia":         flags.EnableLibp2pLANMedia,
	}
}
