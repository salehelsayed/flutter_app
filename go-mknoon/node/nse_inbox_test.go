package node

import (
	"crypto/rand"
	"errors"
	"fmt"
	"testing"
	"time"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

func TestNSEInboxOneShotAuthenticatesPeerAndRetrievesProtectedPage(t *testing.T) {
	privateKeyA, peerA := nseInboxTestIdentity(t)
	_, peerB := nseInboxTestIdentity(t)

	protected := startAckCustodyTestRelay(t, func(req inboxRequest) string {
		if req.Action != inboxRetrieveAckCustodyAction {
			return `{"status":"ERROR","error":"protected action required"}`
		}
		return `{"status":"OK","messages":[{"id":"stable-a","from":"sender-a","message":"cipher-a","timestamp":7}],"hasMore":false,"custodyContract":"ack_or_expiry_v1"}`
	})
	legacy := startAckCustodyTestRelay(t, func(req inboxRequest) string {
		if req.Action == inboxRetrieveAckCustodyAction {
			return `{"status":"ERROR","error":"unsupported action"}`
		}
		return `{"status":"OK","messages":[{"id":"stable-a","from":"sender-a","message":"cipher-a","timestamp":7}],"hasMore":false}`
	})
	params := NSEInboxOneShotParams{
		TransportPrivateKey:     privateKeyA,
		ExpectedTransportPeerID: peerA,
		RelayMultiaddrs:         []string{protected.addr(t), legacy.addr(t)},
		TimeoutMs:               750,
	}

	page, err := NSEInboxRetrievePendingOneShot(params)
	if err != nil || page == nil || len(page.Messages) != 1 ||
		page.Messages[0].ID != "stable-a" || page.HasMore ||
		page.CustodyContract != AckOrExpiryCustodyContract {
		t.Fatalf("NSE one-shot must isolate the physical mailbox without the global singleton: page=%#v err=%v", page, err)
	}
	for relayIndex, actions := range [][]inboxRequest{
		protected.snapshotActions(),
		legacy.snapshotActions(),
	} {
		if len(actions) == 0 {
			t.Fatalf("relay %d received no request", relayIndex)
		}
		for _, action := range actions {
			if action.Limit != 1 {
				t.Fatalf("relay %d action=%q limit=%d, want hard-coded 1", relayIndex, action.Action, action.Limit)
			}
			if action.Action == inboxAckCustodyAction || action.Action == "ack" {
				t.Fatalf("NSE one-shot issued ACK action %q", action.Action)
			}
		}
	}

	requestsBeforeMismatch := len(protected.snapshotActions()) + len(legacy.snapshotActions())
	params.ExpectedTransportPeerID = peerB
	if _, mismatchErr := NSEInboxRetrievePendingOneShot(params); !errors.Is(mismatchErr, ErrNSEInboxIdentityMismatch) {
		t.Fatalf("mismatched expected transport peer error=%v, want %v", mismatchErr, ErrNSEInboxIdentityMismatch)
	}
	requestsAfterMismatch := len(protected.snapshotActions()) + len(legacy.snapshotActions())
	if requestsAfterMismatch != requestsBeforeMismatch {
		t.Fatalf("identity mismatch dialed a relay: before=%d after=%d", requestsBeforeMismatch, requestsAfterMismatch)
	}
}

func TestNSEInboxOneShotBoundsDeadlineClosesHostAndNeverAcknowledges(t *testing.T) {
	privateKey, transportPeer := nseInboxTestIdentity(t)
	delayed := startAckCustodyTestRelay(t, func(req inboxRequest) string {
		time.Sleep(2 * time.Second)
		return `{"status":"NO_MESSAGES","messages":[],"hasMore":false,"custodyContract":"ack_or_expiry_v1"}`
	})

	startedAt := time.Now()
	page, err := NSEInboxRetrievePendingOneShot(NSEInboxOneShotParams{
		TransportPrivateKey:     privateKey,
		ExpectedTransportPeerID: transportPeer,
		RelayMultiaddrs:         []string{delayed.addr(t)},
		TimeoutMs:               250,
	})
	elapsed := time.Since(startedAt)
	if err == nil || page != nil {
		t.Fatalf("deadline leg = (%#v, %v), want fail-closed error", page, err)
	}
	if elapsed > time.Second {
		t.Fatalf("one total 250ms deadline took %v", elapsed)
	}

	deadline := time.Now().Add(750 * time.Millisecond)
	for delayed.host.Network().Connectedness(peer.ID(transportPeer)) != network.NotConnected &&
		time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if connected := delayed.host.Network().Connectedness(peer.ID(transportPeer)); connected != network.NotConnected {
		t.Fatalf("ephemeral NSE host remains connected after return: %s", connected)
	}
	for _, action := range delayed.snapshotActions() {
		if action.Action == inboxAckCustodyAction || action.Action == "ack" {
			t.Fatalf("NSE one-shot issued ACK action %q", action.Action)
		}
	}
}

func nseInboxTestIdentity(t *testing.T) ([]byte, string) {
	t.Helper()
	privateKey, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("GenerateEd25519Key: %v", err)
	}
	raw, err := privateKey.Raw()
	if err != nil {
		t.Fatalf("privateKey.Raw: %v", err)
	}
	transportPeer, err := peer.IDFromPrivateKey(privateKey)
	if err != nil {
		t.Fatalf("IDFromPrivateKey: %v", err)
	}
	if len(raw) == 0 || transportPeer == "" {
		t.Fatal(fmt.Errorf("generated empty NSE identity"))
	}
	return raw, transportPeer.String()
}
