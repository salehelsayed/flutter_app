package node

// FeatureFlags controls rollout of resilient network architecture features.
// Each flag enables or disables a specific capability, allowing staged
// deployment and quick rollback if needed.
//
// All flags default to true (features enabled) via DefaultFeatureFlags(), with
// the explicit exceptions of the Phase-3 device-gated flags EnableDcutrUpgrade
// (FDC-12) and EnableLibp2pLANMedia (FDC-15), which default to FALSE until their
// device gates are GREEN (see each field's doc). EnableLibp2pLANDial (FDC-11) was
// the third such exception until CV-09 graduated it to true (CV-08 D1 proof).
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
	// (HandleLANPeerFound → host.Connect over a same-WiFi QUIC multiaddr). CV-09
	// graduated it to default TRUE now that the D1 two-phone device gate closed
	// (CV-08, commit 121f0551: real Pixel 6 ↔ iPhone 11 reached
	// MSG_RECEIVED_TRANSPORT:"direct" both directions). The dial stays additive and
	// fail-safe (peers fall back to the WS LAN leg + relay). NOTE: in production the
	// load-bearing default is the Dart feature-flags map, which is always sent in
	// full to node:start and applied wholesale by EffectiveFlags; this Go default is
	// the nil-map fallback only. The two sibling Phase-3 flags (FDC-12
	// EnableDcutrUpgrade, FDC-15 EnableLibp2pLANMedia) stay dark until their own
	// device gates close.
	EnableLibp2pLANDial bool `json:"enableLibp2pLANDial"`

	// EnableDcutrUpgrade gates the FDC-12 opportunistic DCUtR relay->direct
	// upgrade. When OFF (the default) the host runs ForceReachabilityPrivate(),
	// so the holepuncher only OBSERVES — zero punches fire (the
	// holepunch_tracer.go ZERO-punch invariant). When ON the host opts into
	// ForceReachabilityPublic() so a relay-connected reachable pair can actively
	// hole-punch to a durable direct conn. Like EnableLibp2pLANDial it defaults
	// to FALSE: FDC-S2 resolved direct-conn identify but left the production
	// reachability flip-safety + real-NAT punch payoff DEVICE-only, so it stays
	// off until the DCUtR device campaign is GREEN. The session re-point layer
	// (peer_session.go) and the transport:upgraded/downgraded telemetry run
	// regardless of this flag — they only correct an already-opened direct conn;
	// this flag solely controls whether the host is ALLOWED to open one via DCUtR.
	EnableDcutrUpgrade bool `json:"enableDcutrUpgrade"`

	// EnableLibp2pLANMedia gates the FDC-15 1:1 media byte stream over a
	// peer-authenticated libp2p LAN-direct conn (MediaLANProtocol). When OFF (the
	// default) the node registers NO MediaLANProtocol handler and the Dart send
	// leg never fires, so media rides only the existing ws://+HTTP-PUT LAN leg +
	// the unconditional relay-CDN upload. Like EnableLibp2pLANDial / EnableDcutrUpgrade
	// it defaults to FALSE: the lane is additive and fail-safe but streams over
	// FDC-11's direct conn, which is itself device-unproven, so it stays off until
	// the D1 two-phone media gate is GREEN.
	EnableLibp2pLANMedia bool `json:"enableLibp2pLANMedia"`
}

// DefaultFeatureFlags returns a FeatureFlags with all relay features enabled.
// EnableLibp2pLANDial (FDC-11) graduated to true at CV-09 (CV-08 D1 two-phone
// proof closed). EnableDcutrUpgrade (FDC-12) and EnableLibp2pLANMedia (FDC-15)
// remain the exceptions — both default to false until their device gates are
// GREEN (see the field docs).
func DefaultFeatureFlags() FeatureFlags {
	return FeatureFlags{
		EnableSharedRelayBackend:     true,
		EnableMultiRelayRouting:      true,
		EnableReservationAwareHealth: true,
		EnableInPlaceRelayRecovery:   true,
		EnableResumeGroupRecovery:    true,
		EnableDeferredDirectAck:      true,
		EnableLibp2pLANDial:          true,  // FDC-11: graduated at CV-09 (CV-08 D1 two-phone proof closed)
		EnableDcutrUpgrade:           false, // FDC-12: off until DCUtR device campaign is GREEN
		EnableLibp2pLANMedia:         false, // FDC-15: off until D1 two-phone media gate is GREEN
	}
}
