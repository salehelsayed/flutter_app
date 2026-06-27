package node

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/network"
)

// FDC-08 Go-node-tier tests for the client side of the additive `presence_get`
// inbox action: RelayPresenceLookup frames the request, decodes
// {presence, ageMs}, rolls over to the next relay on connect failure, and
// degrades an old relay's "Unknown action" reply to `unknown` (never throws away
// a send). These are truth-source-agnostic: the relay reply is faked in-test.

// N1 — RelayPresenceLookup sends action:"presence_get" + decodes {presence, ageMs}.
func TestRelayPresenceLookup_SendsPresenceAction(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan inboxRequest, 1)
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		var req inboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			return
		}
		requestSeen <- req
		_ = writeFrame(s, []byte(`{"status":"OK","presence":"reachable","ageMs":1200}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	const targetPeer = "target-peer-fdc08"
	res, err := n.RelayPresenceLookup(targetPeer)
	if err != nil {
		t.Fatalf("RelayPresenceLookup: %v", err)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "presence_get" {
			t.Fatalf("relay saw action = %q, want %q", req.Action, "presence_get")
		}
		if req.To != targetPeer {
			t.Fatalf("relay saw to = %q, want %q", req.To, targetPeer)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for presence_get request")
	}

	if res.Presence != RelayPresenceReachable {
		t.Fatalf("presence = %q, want %q", res.Presence, RelayPresenceReachable)
	}
	if res.AgeMs != 1200 {
		t.Fatalf("ageMs = %d, want 1200", res.AgeMs)
	}
}

// N2 — presence lookup rolls over to the next relay on failure (parity with
// DialPeerViaRelay_TriesSecondRelayWhenFirstFails).
func TestRelayPresenceLookup_TriesSecondRelay(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, n) // two unreachable fake relays

	res, err := n.RelayPresenceLookup("target-peer-fdc08")
	if err == nil {
		t.Fatal("expected error (both fake relays unreachable)")
	}
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("error should indicate multi-relay attempt, got: %v", err)
	}
	// Even on total relay failure the result degrades to unknown, never offline.
	if res.Presence != RelayPresenceUnknown {
		t.Fatalf("presence on relay outage = %q, want %q (must not be unreachable)", res.Presence, RelayPresenceUnknown)
	}
}

// N3 — an old relay's "Unknown action" reply degrades to `unknown`, NOT
// unreachable, and is not propagated as a fatal error (NET-REL-07).
func TestRelayPresenceLookup_UnknownActionIsUnknown(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		if _, err := readFrame(s); err != nil {
			return
		}
		// The literal an OLD relay returns for an action it does not know.
		_ = writeFrame(s, []byte(`{"status":"ERROR","error":"Unknown action: presence_get"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	res, err := n.RelayPresenceLookup("target-peer-fdc08")
	if err != nil {
		t.Fatalf("old-relay reply must not be a fatal error, got: %v", err)
	}
	if res.Presence != RelayPresenceUnknown {
		t.Fatalf("old-relay presence = %q, want %q (never unreachable)", res.Presence, RelayPresenceUnknown)
	}
}
