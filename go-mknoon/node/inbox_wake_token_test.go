package node

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/network"
)

// FDC-09 §12 / CV-14 Go-node-tier tests for the SEND-SIDE wake-token attach: the
// sender presents on its `store` request the opaque wake-token the recipient
// issued to it, so the relay's §12 access-token gate authorizes the wake. Today
// the sender attaches NOTHING (register_wake_tokens / IssueWakeTokensUseCase only
// build the recipient SET; the store path never presented a token), so the relay
// gate must stay fail-open until this lands + saturates (INV-2 ship-order vs
// CV-19). The relay reply is faked in-test (truth-source-agnostic).

// CV-14a — InboxStoreDetailedWithWakeToken attaches the recipient-issued opaque
// wake-token to the `store` frame (action:"store" + wakeToken:<tok>).
func TestInboxStoreDetailedWithWakeToken_AttachesTokenToStoreFrame(t *testing.T) {
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
		_ = writeFrame(s, []byte(`{"status":"OK","storeStatus":"stored"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	const (
		targetPeer = "target-peer-cv14"
		wakeToken  = "wake-tok-abc-123"
	)
	if _, err := n.InboxStoreDetailedWithWakeToken(targetPeer, "hello", 0, wakeToken); err != nil {
		t.Fatalf("InboxStoreDetailedWithWakeToken: %v", err)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "store" {
			t.Fatalf("relay saw action = %q, want %q", req.Action, "store")
		}
		if req.To != targetPeer {
			t.Fatalf("relay saw to = %q, want %q", req.To, targetPeer)
		}
		if req.WakeToken != wakeToken {
			t.Fatalf("relay saw wakeToken = %q, want %q (sender did not attach the recipient-issued token)", req.WakeToken, wakeToken)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for store request")
	}
}

// CV-14b — additive / NET-REL-07: a store with NO wake-token (the 3-arg
// InboxStoreDetailed) leaves the frame byte-identical to the pre-FDC-09 frame —
// no wakeToken value AND no wakeToken JSON key (omitempty), so absent-token
// recipients and old relays are unaffected.
func TestInboxStoreDetailed_OmitsWakeTokenWhenAbsent(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	rawSeen := make(chan []byte, 1)
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		rawSeen <- reqBytes
		_ = writeFrame(s, []byte(`{"status":"OK","storeStatus":"stored"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	if _, err := n.InboxStoreDetailed("target-peer-cv14", "hello", 0); err != nil {
		t.Fatalf("InboxStoreDetailed: %v", err)
	}

	select {
	case raw := <-rawSeen:
		var req inboxRequest
		if err := json.Unmarshal(raw, &req); err != nil {
			t.Fatalf("unmarshal store frame: %v", err)
		}
		if req.WakeToken != "" {
			t.Fatalf("no-token store carried wakeToken = %q, want empty", req.WakeToken)
		}
		if strings.Contains(string(raw), "wakeToken") {
			t.Fatalf("no-token store frame must omit the wakeToken key entirely (NET-REL-07), got: %s", string(raw))
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for store request")
	}
}
