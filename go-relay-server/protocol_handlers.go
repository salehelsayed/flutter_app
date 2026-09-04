package main

import (
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
)

// relayProtocolDependencies is the production protocol-handler graph. Keeping
// the graph behind one registration seam lets tests exercise the exact host
// wiring instead of recreating an inbox handler that can silently drift from
// main.
type relayProtocolDependencies struct {
	Rendezvous      *RendezvousStore
	Inbox           *InboxStore
	GroupInbox      *GroupInboxStore
	Presence        *PresenceStore
	TurnCredentials TurnCredentialIssuer
	CallControl     *CallControlService
	Media           *MediaStore
	Profile         *ProfileStore
}

func registerRelayProtocolHandlers(h host.Host, dependencies relayProtocolDependencies) {
	h.SetStreamHandler(RendezvousProtocol, func(stream network.Stream) {
		HandleRendezvousStream(stream, dependencies.Rendezvous)
	})
	h.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		HandleInboxStream(
			stream,
			dependencies.Inbox,
			dependencies.GroupInbox,
			h,
			dependencies.Presence,
			dependencies.TurnCredentials,
			dependencies.CallControl,
		)
	})
	h.SetStreamHandler(MediaProtocol, func(stream network.Stream) {
		HandleMediaStream(stream, dependencies.Media, dependencies.Profile)
	})
}
