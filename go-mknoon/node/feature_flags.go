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

	// EnableDeferredDirectAck delays direct chat ACK until Flutter confirms
	// receiver-side terminal handling for that chat nonce.
	EnableDeferredDirectAck bool `json:"enableDeferredDirectAck"`

	// EnableLibp2pLANDial gates the FDC-11 bonsoir-fed libp2p LAN-direct dial
	// (HandleLANPeerFound → host.Connect over a same-WiFi QUIC multiaddr). Unlike
	// the relay flags above it defaults to FALSE: the LAN dial is additive and
	// fail-safe (peers fall back to the WS LAN leg + relay), but the new
	// advertise/parse wiring is device-unproven (a wrong port re-triggers the
	// FDC-S2 QUIC-identify hang as a config bug), so it stays off until the D1
	// two-phone device gate is GREEN — matching sibling Phase-3 flag discipline
	// (FDC-12 EnableDcutrUpgrade, FDC-15 EnableLibp2pLANMedia).
	EnableLibp2pLANDial bool `json:"enableLibp2pLANDial"`
}

// DefaultFeatureFlags returns a FeatureFlags with all relay features enabled.
// EnableLibp2pLANDial (FDC-11) is the lone exception — it defaults to false
// until the D1 device gate is GREEN (see the field doc).
func DefaultFeatureFlags() FeatureFlags {
	return FeatureFlags{
		EnableSharedRelayBackend:     true,
		EnableMultiRelayRouting:      true,
		EnableReservationAwareHealth: true,
		EnableInPlaceRelayRecovery:   true,
		EnableResumeGroupRecovery:    true,
		EnableDeferredDirectAck:      true,
		EnableLibp2pLANDial:          false, // FDC-11: off until D1 device-proven
	}
}
