package node

// autorelay_metrics.go provides the foundation for hooking AutoRelay
// reservation events into the relay session manager.
//
// Phase 4 design:
//   - When go-libp2p's AutoRelay exposes a MetricsTracer interface with
//     ReservationOpened/ReservationEnded/RequestFinished hooks, we will
//     implement them here to drive RelaySessionManager state transitions.
//   - Until then, relay session state is inferred from:
//     (a) EvtLocalAddressesUpdated events (circuit addresses appearing/disappearing)
//     (b) EvtPeerConnectednessChanged events for relay peers
//     (c) warmRelayConnection success/failure during RefreshRelaySession
//
// This file exists as a named landing point so the relay-session integration
// is discoverable and can be extended as AutoRelay evolves.
//
// The RelaySessionManager itself (relay_session.go) is already fully functional
// and can be driven by direct calls from watchConnectionEvents and
// RefreshRelaySession.
