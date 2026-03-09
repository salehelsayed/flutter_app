package node

// FeatureFlags controls rollout of resilient network architecture features.
// Each flag enables or disables a specific capability, allowing staged
// deployment and quick rollback if needed.
//
// All flags default to true (features enabled) via DefaultFeatureFlags().
type FeatureFlags struct {
	// EnableSharedRelayBackend enables shared state between relay instances
	// (e.g. Redis-backed inbox, rendezvous, push tokens).
	EnableSharedRelayBackend bool `json:"enableSharedRelayBackend"`

	// EnableMultiRelayRouting enables routing operations (rendezvous, inbox,
	// media) across multiple relay servers with failover.
	EnableMultiRelayRouting bool `json:"enableMultiRelayRouting"`

	// EnableReservationAwareHealth uses reservation state (not just circuit
	// addresses) as the source of truth for relay health.
	EnableReservationAwareHealth bool `json:"enableReservationAwareHealth"`

	// EnableInPlaceRelayRecovery enables recovering relay sessions without
	// full host restart (in-place re-reservation).
	EnableInPlaceRelayRecovery bool `json:"enableInPlaceRelayRecovery"`

	// EnableResumeGroupRecovery enables recovering group pubsub topics
	// after relay session recovery.
	EnableResumeGroupRecovery bool `json:"enableResumeGroupRecovery"`
}

// DefaultFeatureFlags returns a FeatureFlags with all features enabled.
func DefaultFeatureFlags() FeatureFlags {
	return FeatureFlags{
		EnableSharedRelayBackend:     true,
		EnableMultiRelayRouting:      true,
		EnableReservationAwareHealth: true,
		EnableInPlaceRelayRecovery:   true,
		EnableResumeGroupRecovery:    true,
	}
}
