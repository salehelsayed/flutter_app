package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

type activeDeviceTestConn struct {
	network.Conn
	actor peer.ID
}

func (s activeDeviceTestConn) RemotePeer() peer.ID { return s.actor }

type activeDeviceTestStream struct {
	network.Stream
	conn activeDeviceTestConn
	in   bytes.Buffer
	out  bytes.Buffer
}

func (s *activeDeviceTestStream) Conn() network.Conn             { return s.conn }
func (s *activeDeviceTestStream) Read(data []byte) (int, error)  { return s.in.Read(data) }
func (s *activeDeviceTestStream) Write(data []byte) (int, error) { return s.out.Write(data) }
func (s *activeDeviceTestStream) Close() error                   { return nil }

func activeDeviceTestRequest(t *testing.T, inbox *InboxStore, call *CallControlService, actor string, request map[string]any) map[string]any {
	t.Helper()
	remote, err := peer.Decode(actor)
	if err != nil {
		t.Fatal(err)
	}
	stream := &activeDeviceTestStream{conn: activeDeviceTestConn{actor: remote}}
	if err := writeFrame(&stream.in, b293Raw(t, request)); err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		HandleInboxStream(stream, inbox, nil, nil, nil, nil, call)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("relay inbox admission did not finish")
	}
	raw, err := readFrame(&stream.out)
	if err != nil {
		t.Fatal(err)
	}
	var response map[string]any
	if err := json.Unmarshal(raw, &response); err != nil {
		t.Fatal(err)
	}
	if response["status"] != "OK" {
		t.Fatalf("relay admission rejected: %v", response)
	}
	return response
}

const activeDeviceTestDay = "2026-03-29"
const activeDeviceTestTomorrow = "2026-03-30"

func activeDeviceTestInbox(t *testing.T) (*InboxStore, *b29StoreClock) {
	t.Helper()
	clock := &b29StoreClock{at: b29StoreMidnight(t, activeDeviceTestDay)}
	path := filepath.Join(t.TempDir(), "active-devices.json")
	store, err := newActiveIdentityStoreWithEngagement(path, b29StoreKey(), clock.now, false)
	if err != nil {
		t.Fatal(err)
	}
	inbox := NewInboxStore(nil)
	inbox.activeDevices = store
	return inbox, clock
}

func activeDeviceTestExpectCount(t *testing.T, inbox *InboxStore, clock *b29StoreClock, count int) {
	t.Helper()
	b29StoreAdvance(t, inbox.activeDevices, clock, b29StoreMidnight(t, activeDeviceTestTomorrow))
	body := b29RuntimeScrape(t, inbox)
	for _, window := range []string{"1d", "7d", "30d"} {
		b29RuntimeContains(t, body, fmt.Sprintf(`relay_active_devices_estimated{day=%q,window=%q} %d`, activeDeviceTestDay, window, count))
	}
}

func TestActiveDevicesEstimatesElevenFromAuthenticatedAdmissions(t *testing.T) {
	inbox, clock := activeDeviceTestInbox(t)
	_, recipient := b293Account(t, 99)
	for seed := byte(1); seed <= 10; seed++ {
		_, actor := b293Account(t, seed)
		thought := fmt.Sprintf(`{"type":"post_create","post_id":"thought-%d","sender_peer_id":%q,"created_at":%q}`, seed, actor, clock.now().Format(time.RFC3339))
		response := activeDeviceTestRequest(t, inbox, nil, actor, map[string]any{"action": "store", "to": recipient, "message": thought})
		if response["storeStatus"] != string(InboxStoreResultStored) {
			t.Fatalf("Thought was not newly stored: %v", response)
		}
	}
	for seed := byte(9); seed <= 11; seed++ {
		_, actor := b293Account(t, seed)
		message := fmt.Sprintf(`{"type":"chat_message","version":"2","id":"chat-%d","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`, seed, actor)
		response := activeDeviceTestRequest(t, inbox, nil, actor, map[string]any{
			"action": "store", "to": recipient, "from": recipient, "message": message,
		})
		if response["storeStatus"] != string(InboxStoreResultStored) {
			t.Fatalf("direct chat was not newly stored: %v", response)
		}
	}
	activeDeviceTestExpectCount(t, inbox, clock, 11)
}

func TestActiveDevicesCountsNewCallMailboxAdmission(t *testing.T) {
	inbox, clock := activeDeviceTestInbox(t)
	_, callActor := b293Account(t, 12)
	_, recipient := b293Account(t, 99)
	at := clock.now()
	server := miniredis.RunT(t)
	server.SetTime(at)
	call := NewCallControlService(newRedisCallControlStore(newTestRedisClient(t, server), "active-devices:"), nil, clock.now)
	activeDeviceTestRequest(t, inbox, call, recipient, map[string]any{
		"action": "call_wake_handle_set_v1", "authorizedSenderPeerId": callActor,
		"wakeHandle": callTestWake, "expiresAtMs": at.Add(time.Hour).UnixMilli(),
	})
	request := map[string]any{
		"action": "call_store_v1", "to": recipient, "callHandle": callTestHandleA,
		"messageId": callTestMessageA, "envelope": "opaque call envelope",
		"wakeHandle": callTestWake, "expiresAtMs": at.Add(45 * time.Second).UnixMilli(),
	}
	receipt := activeDeviceTestRequest(t, inbox, call, callActor, request)
	if receipt["storeStatus"] != string(CallStoreStatusStored) {
		t.Fatalf("call mailbox event was not newly stored: %v", receipt)
	}
	receipt = activeDeviceTestRequest(t, inbox, call, callActor, request)
	if receipt["storeStatus"] != string(CallStoreStatusDuplicate) {
		t.Fatalf("second call mailbox event was not duplicate: %v", receipt)
	}
	activeDeviceTestExpectCount(t, inbox, clock, 1)
}
