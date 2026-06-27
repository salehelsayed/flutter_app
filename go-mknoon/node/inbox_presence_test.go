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

// FDC-09 Go-node-tier tests for the client side of the additive `presence_set`
// self-publish action: RelayPresenceSet frames {state, ttlMs}, reports OK on
// accept, and degrades an old relay's "Unknown action" reply to unsupported
// (never a fatal error) so a failed self-publish never throws away a send.

// N1w — RelayPresenceSet sends action:"presence_set" + Metadata{state, ttlMs}.
func TestRelayPresenceSet_SendsPresenceSetAction(t *testing.T) {
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
		_ = writeFrame(s, []byte(`{"status":"OK"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	res, err := n.RelayPresenceSet("foreground", 180000)
	if err != nil {
		t.Fatalf("RelayPresenceSet: %v", err)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "presence_set" {
			t.Fatalf("relay saw action = %q, want %q", req.Action, "presence_set")
		}
		if got := req.Metadata["state"]; got != "foreground" {
			t.Fatalf("relay saw state = %v, want foreground", got)
		}
		// JSON numbers decode to float64 through the interface{} Metadata map.
		if got, ok := req.Metadata["ttlMs"].(float64); !ok || int64(got) != 180000 {
			t.Fatalf("relay saw ttlMs = %v, want 180000", req.Metadata["ttlMs"])
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for presence_set request")
	}

	if !res.OK {
		t.Fatalf("RelayPresenceSet OK = false, want true (relay accepted)")
	}
}

// N3w — an old relay's "Unknown action" reply degrades to unsupported (OK:false
// with the error text), NOT a fatal error (NET-REL-07).
func TestRelayPresenceSet_UnknownActionIsUnsupported(t *testing.T) {
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
		_ = writeFrame(s, []byte(`{"status":"ERROR","error":"Unknown action: presence_set"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	res, err := n.RelayPresenceSet("background", 180000)
	if err != nil {
		t.Fatalf("old-relay reply must not be a fatal error, got: %v", err)
	}
	if res.OK {
		t.Fatalf("old-relay RelayPresenceSet OK = true, want false (unsupported)")
	}
	if !strings.Contains(res.Error, "Unknown action") {
		t.Fatalf("old-relay error = %q, want it to contain 'Unknown action'", res.Error)
	}
}

// FDC-09 §12 — RelayRegisterWakeTokens frames action:"register_wake_tokens" with
// the opaque token SET; an OK reply succeeds.
func TestRelayRegisterWakeTokens_SendsRegisterAction(t *testing.T) {
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
		_ = writeFrame(s, []byte(`{"status":"OK"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	if err := n.RelayRegisterWakeTokens([]string{"tok-1", "tok-2"}); err != nil {
		t.Fatalf("RelayRegisterWakeTokens: %v", err)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "register_wake_tokens" {
			t.Fatalf("relay saw action = %q, want register_wake_tokens", req.Action)
		}
		if len(req.WakeTokens) != 2 {
			t.Fatalf("relay saw %d wake tokens, want 2", len(req.WakeTokens))
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for register_wake_tokens request")
	}
}

// FDC-09 §12 / NET-REL-07 — an old relay's "Unknown action" surfaces as an error
// (FanOut: no relay accepted) so the caller degrades gracefully (plain push
// keeps working), rather than silently succeeding.
func TestRelayRegisterWakeTokens_OldRelayErrors(t *testing.T) {
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
		_ = writeFrame(s, []byte(`{"status":"ERROR","error":"Unknown action: register_wake_tokens"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	if err := n.RelayRegisterWakeTokens([]string{"tok-1"}); err == nil {
		t.Fatal("old relay must surface an error so the caller degrades gracefully")
	}
}
