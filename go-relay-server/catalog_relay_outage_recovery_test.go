package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/protocol"
)

// DC-017 transport leg. Remove only this owned relay's inbox service while
// client-to-client sockets still transfer bytes. Restore a fresh handler/store
// over the same owned Redis backend. SQLite sender retry and recipient replay
// are independently covered by relay_outage_sqlite_replay_test.dart.
func TestCatalogDC017OwnedRelayServiceOutageAndReplay(t *testing.T) {
	redis := miniredis.RunT(t)
	backend := newAckCustodyRedisBackend(t, redis, "catalog-relay-outage:", 16)
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStoreWithBackend(backend, push)
	inbox.SetAckCustodyAdmissionEnabled(true)
	groups := NewGroupInboxStore(16, time.Hour)
	env := setupInboxStreamEnv(t, inbox, groups)
	wires := []string{
		ackCustodyTextEnvelope("before-outage", env.sender.ID().String(), "control"),
		ackCustodyTextEnvelope("queued-first", env.sender.ID().String(), "first"),
		ackCustodyTextEnvelope("queued-second", env.sender.ID().String(), "second"),
		ackCustodyTextEnvelope("queued-third", env.sender.ID().String(), "third"),
	}
	store := func(wire string) inboxResponse {
		return sendAckCustodyStoreRequest(t, env, env.recipient.ID().String(), ackCustodyDirectTextKind, ackCustodyContract, wire)
	}
	if response := store(wires[0]); response.Status != "OK" {
		t.Fatal("healthy relay control failed")
	}
	env.server.RemoveStreamHandler(InboxProtocol)
	const healthyClientProtocol = protocol.ID("/catalog/healthy-client/1")
	env.recipient.SetStreamHandler(healthyClientProtocol, func(stream network.Stream) {
		defer stream.Close()
		_, _ = io.Copy(stream, stream)
	})
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	probe, err := env.sender.NewStream(ctx, env.recipient.ID(), healthyClientProtocol)
	if err != nil {
		t.Fatal(err)
	}
	_ = probe.SetDeadline(time.Now().Add(3 * time.Second))
	if _, err := probe.Write([]byte("healthy")); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, len("healthy"))
	if _, err := io.ReadFull(probe, got); err != nil || !bytes.Equal(got, []byte("healthy")) {
		t.Fatal("client networking failed during the relay service outage")
	}
	_ = probe.Close()
	// Negotiation may use a cached protocol advertisement. Either refusal at
	// open or reset on the first exchange is a real unavailable-service result.
	stream, openErr := env.sender.NewStream(ctx, env.server.ID(), InboxProtocol)
	if openErr == nil {
		_ = stream.SetDeadline(time.Now().Add(3 * time.Second))
		req, err := json.Marshal(inboxRequest{Action: ackCustodyStoreAction,
			To: env.recipient.ID().String(), Message: wires[1],
			CustodyKind: ackCustodyDirectTextKind, CustodyContract: ackCustodyContract})
		if err != nil {
			t.Fatal(err)
		}
		writeErr := writeFrame(stream, req)
		if writeErr == nil {
			if _, err := readFrame(stream); err == nil {
				t.Fatal("removed relay service acknowledged a queued message")
			}
		}
		_ = stream.Close()
	}
	if pending, _ := inbox.RetrievePendingWithMeta(env.recipient.ID().String(), 16); len(pending) != 1 {
		t.Fatal("failed relay attempt changed preexisting durable custody")
	}
	restore := func() {
		inbox = NewInboxStoreWithBackend(backend, push)
		inbox.SetAckCustodyAdmissionEnabled(true)
		env.server.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
			HandleInboxStream(stream, inbox, groups, env.server, env.presence, nil)
		})
	}
	restore()
	for _, wire := range wires[1:] {
		if response := store(wire); response.Status != "OK" {
			t.Fatal("queued text did not recover after service restoration")
		}
		if duplicate := store(wire); duplicate.Status != "OK" || duplicate.StoreStatus != string(InboxStoreResultDuplicate) {
			t.Fatal("same queued text was not idempotent")
		}
	}
	retrieve := func() inboxResponse {
		return sendInboxAction(t, env.recipient, env.server, inboxRequest{Action: ackCustodyRetrievePendingAction, CustodyContract: ackCustodyContract, Limit: 16})
	}
	first := retrieve()
	if first.Status != "OK" || len(first.Messages) != len(wires) {
		t.Fatal("recovered inbox lost or duplicated text")
	}
	entryIDs := make([]string, len(wires))
	for i, message := range first.Messages {
		if message.Message != wires[i] || message.ID == "" {
			t.Fatal("relay FIFO order or stable replay identity changed")
		}
		entryIDs[i] = message.ID
	}
	restore()
	second := retrieve()
	if len(second.Messages) != len(wires) {
		t.Fatal("fresh relay handler lost pending replay")
	}
	for i, message := range second.Messages {
		if message.ID != entryIDs[i] || message.Message != wires[i] {
			t.Fatal("fresh-handler replay changed ordered identities")
		}
	}
	acked := sendInboxAction(t, env.recipient, env.server, inboxRequest{Action: ackCustodyAckAction, CustodyContract: ackCustodyContract, EntryIds: entryIDs})
	if acked.Status != "OK" || acked.Acked != len(wires) || len(retrieve().Messages) != 0 {
		t.Fatal("explicit acknowledgement did not converge the recovered queue")
	}
}
