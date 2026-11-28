package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
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
		HandleInboxStream(stream, inbox, NewGroupInboxStore(8, time.Hour), nil, nil, nil, call)
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
	store, err := newActiveDeviceStore(path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	inbox := NewInboxStore(nil)
	inbox.activeDevices = store
	return inbox, clock
}

func activeDeviceTestExpectCount(t *testing.T, inbox *InboxStore, clock *b29StoreClock, count int) {
	t.Helper()
	b29StoreAdvance(t, inbox.activeDevices.activeIdentityStore, clock, b29StoreMidnight(t, activeDeviceTestTomorrow))
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
	call.activeDevices = inbox.activeDevices
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

func TestActiveDevicesSkipsOptOutAndAmbiguousTraffic(t *testing.T) {
	inbox, clock := activeDeviceTestInbox(t)
	_, recipient := b293Account(t, 99)
	for seed, optOut := range []string{"true", "null", `"false"`} {
		_, actor := b293Account(t, byte(seed+20))
		message := fmt.Sprintf(`{"type":"post_create","post_id":"opt-out-%d","sender_peer_id":%q,"created_at":%q,"thoughts_metrics_opt_out":%s}`, seed, actor, clock.now().Format(time.RFC3339), optOut)
		activeDeviceTestRequest(t, inbox, nil, actor, map[string]any{"action": "store", "to": recipient, "message": message})
	}
	_, actor := b293Account(t, 23)
	activeDeviceTestRequest(t, inbox, nil, actor, map[string]any{
		"action": "store", "to": recipient, "message": fmt.Sprintf(
			`{"type":"post_create","post_id":"claimed-sender","sender_peer_id":%q,"created_at":%q}`,
			recipient, clock.now().Format(time.RFC3339)),
	})
	for seed, flags := range []map[string]any{
		{"action": quietRecoveryStoreAction},
		{"suppressNotification": true},
		{},
	} {
		_, actor := b293Account(t, byte(seed+24))
		edit := ""
		if seed == 2 {
			edit = `,"eventId":"chat-edit"`
		}
		message := fmt.Sprintf(`{"type":"chat_message","version":"2","id":"nonqualifying-%d","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}%s}`, seed, actor, edit)
		request := map[string]any{"action": "store", "to": recipient, "message": message}
		for key, value := range flags {
			request[key] = value
		}
		activeDeviceTestRequest(t, inbox, nil, actor, request)
	}
	_, actor = b293Account(t, 27)
	activeDeviceTestRequest(t, inbox, nil, actor, map[string]any{
		"action": "group_store", "groupId": testCanonicalGroupAuthID,
		"recipientPeerIds": []string{recipient}, "message": `{"type":"group_message","version":"3","messageId":"legacy-control"}`,
	})
	activeDeviceTestExpectCount(t, inbox, clock, 0)
}

func TestActiveDevicesCountsTypedProtectedGroupContent(t *testing.T) {
	seedInbox, clock := activeDeviceTestInbox(t)
	server := miniredis.RunT(t)
	server.SetTime(clock.now())
	inbox := NewInboxStoreWithBackendAndCapacity(newAckCustodyRedisBackend(t, server, "active-devices-group:", 16), nil, 16)
	inbox.SetAckCustodyAdmissionEnabled(true)
	inbox.SetAckCustodyNowForTest(clock.now)
	inbox.activeDevices = seedInbox.activeDevices
	_, recipient := b293Account(t, 99)
	for index, kind := range []string{"group_message", "group_reaction"} {
		_, actor := b293Account(t, byte(index+28))
		fixture := newTC364GroupContentFixture(t, "group-content-devices", "logical-author", actor)
		contentID := "gr1:" + strings.Repeat("a", 32) + ":00000000000000000001:" + strings.Repeat("b", 32)
		action := ""
		if kind == "group_reaction" {
			action = "add"
		}
		receipt := activeDeviceTestRequest(t, inbox, nil, actor, map[string]any{
			"action": ackCustodyStoreAction, "to": recipient,
			"custodyContract": ackCustodyContract, "custodyKind": ackCustodyGroupContentKind,
			"message": fixture.envelope(t, kind, contentID, action, []string{recipient}, kind),
		})
		if receipt["storeStatus"] != string(InboxStoreResultStored) {
			t.Fatalf("protected group event did not reach storage: %v", receipt)
		}
	}
	activeDeviceTestExpectCount(t, inbox, clock, 1)
}

func TestActiveDevicesSnapshotsCheckpointOnlyOnDrainedShutdown(t *testing.T) {
	for _, test := range []struct {
		name        string
		finish      bool
		inflight    bool
		wantPartial int
	}{
		{name: "abrupt-restart", wantPartial: 1},
		{name: "in-flight-at-shutdown", finish: true, inflight: true, wantPartial: 1},
		{name: "drained-shutdown", finish: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			inbox, clock := activeDeviceTestInbox(t)
			store := inbox.activeDevices
			path := store.path
			_, actor := b293Account(t, 31)
			before, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			store.observe(actor)
			after, err := os.ReadFile(path)
			if err != nil || !bytes.Equal(before, after) {
				t.Fatalf("event path wrote the snapshot: %v", err)
			}
			if err := store.advance(); err != nil {
				t.Fatal(err)
			}
			if disk := b29StoreDisk(t, path); disk.ObservedAt != nil {
				t.Fatal("periodic snapshot attested buffered coverage")
			}
			if test.inflight {
				store.beginRequest()
			}
			if test.finish {
				if err := store.finish(true); err != nil {
					t.Fatal(err)
				}
			}
			if test.inflight {
				store.endRequest()
			}
			if disk := b29StoreDisk(t, path); (disk.ObservedAt != nil) != (test.wantPartial == 0) {
				t.Fatalf("unexpected saved coverage checkpoint: %v", disk.ObservedAt)
			}
			clock.set(clock.now().Add(30 * time.Second))
			reopened, err := newActiveDeviceStore(path, b29StoreKey(), clock.now)
			if err != nil {
				t.Fatal(err)
			}
			inbox.activeDevices = reopened
			activeDeviceTestExpectCount(t, inbox, clock, 1)
			b29RuntimeContains(t, b29RuntimeScrape(t, inbox), fmt.Sprintf(
				`relay_active_devices_coverage_partial{day=%q} %d`, activeDeviceTestDay, test.wantPartial))
			disk, err := os.ReadFile(path)
			if err != nil || bytes.Contains(disk, []byte(actor)) {
				t.Fatalf("device ID appeared in the snapshot or read failed: %v", err)
			}
		})
	}
}

func TestActiveDevicesOptionalConfigurationLeavesCanonicalStoreIndependent(t *testing.T) {
	for _, state := range []string{"", "false", "invalid", "true"} {
		t.Run("flag="+state, func(t *testing.T) {
			canonical := b29RuntimeEnvironment(t, "true", "false")
			t.Setenv(activeDevicesEnabledEnv, state)
			stores := b29RuntimeBootstrap(t)
			if stores.Inbox.activeIdentities == nil {
				t.Fatal("device option disabled the canonical store")
			}
			devices := stores.Inbox.activeDevices
			if state == "true" {
				if devices == nil || devices.path != canonical+".active-devices" || devices.keyID == stores.Inbox.activeIdentities.keyID {
					t.Fatal("device store was absent or collided with the canonical snapshot or key domain")
				}
			} else {
				if devices != nil || strings.Contains(b29RuntimeScrape(t, stores.Inbox), "relay_active_devices_") {
					t.Fatal("device gauges need explicit beta configuration")
				}
				if _, err := os.Stat(canonical + ".active-devices"); !os.IsNotExist(err) {
					t.Fatalf("disabled or invalid option wrote a device snapshot: %v", err)
				}
			}
		})
	}
}

func TestActiveDevicesInvalidSnapshotDoesNotDisableCanonicalStore(t *testing.T) {
	canonical := b29RuntimeEnvironment(t, "true", "false")
	t.Setenv(activeDevicesEnabledEnv, "true")
	if err := os.MkdirAll(filepath.Dir(canonical), 0700); err != nil {
		t.Fatal(err)
	}
	devicePath := canonical + ".active-devices"
	if err := os.WriteFile(devicePath, []byte("unreadable aggregate snapshot"), 0600); err != nil {
		t.Fatal(err)
	}
	stores := b29RuntimeBootstrap(t)
	if stores.Inbox.activeIdentities == nil || stores.Inbox.activeDevices != nil {
		t.Fatal("invalid device snapshot affected the canonical counter")
	}
}
