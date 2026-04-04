package node

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

	limited := append([]string(nil), addrs...)
	if !flags.EnableMultiRelayRouting && len(limited) > 1 {
		return limited[:1]
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
	}
}
