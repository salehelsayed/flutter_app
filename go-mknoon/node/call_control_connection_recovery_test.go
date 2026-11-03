package node

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
)

func TestCallStoreV1_EstablishedRelayBlackholeRecoversWithoutRestart(t *testing.T) {
	relay, _ := startTurnCredentialsRelayFixture(t, "")
	requests := make(chan callControlWireRequest, 3)
	var entered, headerComplete, payloadComplete, decodeComplete atomic.Int32
	defer func() {
		t.Logf("relay checkpoints: entered=%d header_complete=%d payload_complete=%d decode_complete=%d",
			entered.Load(), headerComplete.Load(), payloadComplete.Load(), decodeComplete.Load())
	}()
	// The existing fixture normally has a static response. This local handler
	// returns a receipt only after receiving and decoding the real frame, using
	// that request's expiry so a 30-second setup receipt cannot expire mid-test.
	relay.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		defer stream.Close()
		entered.Add(1)
		var header [4]byte
		if _, err := io.ReadFull(stream, header[:]); err != nil {
			return
		}
		headerComplete.Add(1)
		length := binary.BigEndian.Uint32(header[:])
		if length > MaxFrameLen {
			return
		}
		raw := make([]byte, length)
		if _, err := io.ReadFull(stream, raw); err != nil {
			return
		}
		payloadComplete.Add(1)
		var request callControlWireRequest
		if json.Unmarshal(raw, &request) != nil {
			return
		}
		decodeComplete.Add(1)
		receiptAt := time.Now().UTC().UnixMilli()
		if request.Action != callStoreAction || request.ExpiresAtMs <= receiptAt {
			return
		}
		requests <- request
		response, err := json.Marshal(callControlWireResponse{
			Status: "OK", Schema: CallMailboxSchema, Version: CallControlVersion,
			StoreStatus: "stored", ReceiptAtMs: receiptAt, ExpiresAtMs: request.ExpiresAtMs,
			EventCount: 1, TotalBytes: len(request.Envelope), PendingHandles: 1, Wake: "dispatched",
		})
		if err == nil {
			_ = writeFrame(stream, response)
		}
	})

	n := startLocalNodeForMultiRelayTest(t)
	originalHost := n.Host()
	originalPeerID := originalHost.ID()
	v4 := relay.Addrs()[0]
	proxy := newEstablishedPathProxy(t, v4)
	pid := relay.ID()
	n.mu.Lock()
	n.relayAddresses = []string{
		proxy.address.String() + "/p2p/" + pid.String(),
		v4.String() + "/p2p/" + pid.String(),
	}
	n.mu.Unlock()
	if err := n.DialPeerWithTimeout(pid.String(), []string{proxy.address.String()}, 3000); err != nil {
		t.Fatal("could not establish the proxied relay transport")
	}
	conns := originalHost.Network().ConnsToPeer(pid)
	if len(conns) != 1 || !conns[0].RemoteMultiaddr().Equal(proxy.address) {
		t.Fatal("fixture must warm only the proxied relay connection")
	}
	original := conns[0]
	sibling, remote := sharedTraffic(t, originalHost, relay)
	if sibling.Conn() != original {
		t.Fatal("call store control sibling used another connection")
	}
	sharedProgress(t, sibling, remote, "before-call-store-blackhole")
	newRequest := func() CallStoreRequest {
		return CallStoreRequest{
			RecipientDevicePeerID: pid.String(), CallHandle: nodeCallHandle,
			MessageID: nodeCallMessage, Envelope: "encrypted-node-envelope",
			ExpiresAtMs: time.Now().Add(30 * time.Second).UnixMilli(), WakeHandle: nodeCallWake,
		}
	}
	assertReceipt := func(receipt CallStoreReceipt, request CallStoreRequest) {
		t.Helper()
		if receipt.Schema != CallMailboxSchema || receipt.Version != CallControlVersion ||
			receipt.StoreStatus != "stored" || receipt.Wake != "dispatched" ||
			receipt.ReceiptAtMs <= 0 || receipt.ReceiptAtMs > request.ExpiresAtMs ||
			receipt.ExpiresAtMs != request.ExpiresAtMs || receipt.EventCount != 1 ||
			receipt.TotalBytes != len(request.Envelope) || receipt.PendingHandles != 1 {
			t.Fatal("call store did not return the real validated receipt and wake outcome")
		}
		select {
		case got := <-requests:
			if got.Action != callStoreAction || got.To != request.RecipientDevicePeerID ||
				got.CallHandle != request.CallHandle || got.MessageID != request.MessageID ||
				got.Envelope != request.Envelope || got.ExpiresAtMs != request.ExpiresAtMs ||
				got.WakeHandle != request.WakeHandle || !got.WakeReceipt {
				t.Fatal("relay received changed call store bytes, recipient, expiry, or wake policy")
			}
		default:
			t.Fatal("relay did not receive the real call store request")
		}
	}

	// Both addresses are known before the fault; the warm request must still
	// reuse the sole proxy connection and receive a valid store/wake receipt.
	warmRequest := newRequest()
	warm, err := n.CallStoreV1(warmRequest)
	if err != nil {
		t.Fatal("warm call store failed")
	}
	assertReceipt(warm, warmRequest)
	assertOriginalSharedConnection(t, originalHost, pid, original)
	sharedProgress(t, sibling, remote, "after-warm-call-store")

	// Keep the established socket open but discard its bytes. A failed first
	// store must retain the native API's unchanged fifteen-second timeout and
	// cannot turn local write completion into accepted relay custody.
	proxy.drop.Store(true)
	failed, firstErr := n.CallStoreV1(newRequest())
	if !errors.Is(firstErr, ErrCallControlUnavailable) || failed != (CallStoreReceipt{}) {
		t.Fatal("blackholed call store returned custody or an unexpected failure")
	}
	assertOriginalSharedConnection(t, originalHost, pid, original)
	select {
	case <-requests:
		t.Fatal("blackholed call store unexpectedly reached the relay")
	default:
	}

	// Refresh only the request's normal expiry, never its timeout or route.
	// The next ordinary store owns liveness checking and exact retirement;
	// there is no manual note/check, post-fault predial, or replacement ACK.
	recoveryRequest := newRequest()
	started := time.Now()
	recovered, recoveryErr := n.CallStoreV1(recoveryRequest)
	elapsed := time.Since(started)
	if recoveryErr != nil {
		t.Fatalf("fresh call store remained trapped on the stale relay connection: elapsed_ms=%d stale_closed=%v", elapsed.Milliseconds(), original.IsClosed())
	}
	if elapsed > 15*time.Second {
		t.Fatalf("call store recovery exceeded its original 15000 ms budget: elapsed_ms=%d", elapsed.Milliseconds())
	}
	assertReceipt(recovered, recoveryRequest)
	if n.Host() != originalHost || n.Host().ID() != originalPeerID {
		t.Fatal("call store recovery restarted or replaced the node host")
	}
	conns = originalHost.Network().ConnsToPeer(pid)
	if !original.IsClosed() || len(conns) != 1 || conns[0] == original ||
		conns[0].RemotePeer() != pid || !conns[0].RemoteMultiaddr().Equal(v4) {
		t.Fatal("call store recovery did not retire the exact stale connection and use the healthy address of the same relay")
	}
	assertNoSendChecks(t, n)
}
