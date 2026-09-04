package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	mocknet "github.com/libp2p/go-libp2p/p2p/net/mock"
)

type callHandlerFixture struct {
	relay     host.Host
	client    host.Host
	recipient host.Host
	handled   chan struct{}
}

func TestVC202RetrieveResponseFitsFrameAndPreservesHasMore(t *testing.T) {
	server := miniredis.RunT(t)
	now := time.Unix(1_801_750_000, 0).UTC()
	service := NewCallControlService(
		newRedisCallControlStore(newTestRedisClient(t, server), "vc202-handler-frame:"),
		nil,
		func() time.Time { return now },
	)
	fixture := newCallHandlerFixture(t, service)
	recipient := fixture.recipient.ID().String()
	sender := fixture.client.ID().String()
	envelope := strings.Repeat("x", 70*1024)
	if response := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_wake_handle_set_v1", "authorizedSenderPeerId": sender,
		"wakeHandle": callTestWake, "expiresAtMs": now.Add(time.Hour).UnixMilli(),
	}); response["status"] != "OK" {
		t.Fatalf("wake authorization response = %#v", response)
	}

	for _, messageID := range []string{callTestMessageA, callTestMessageB} {
		response := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
			"action": "call_store_v1", "to": recipient, "callHandle": callTestHandleA,
			"messageId": messageID, "envelope": envelope,
			"expiresAtMs": now.Add(45 * time.Second).UnixMilli(), "wakeHandle": callTestWake,
		})
		if response["status"] != "OK" {
			t.Fatalf("store %s response = %#v", messageID, response)
		}
	}

	retrieve := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_retrieve_v1", "callHandle": callTestHandleA, "limit": 64,
	})
	events, ok := retrieve["events"].([]any)
	if retrieve["status"] != "OK" || !ok || len(events) != 1 || retrieve["hasMore"] != true {
		t.Fatalf("frame-fitted retrieve response = %#v", retrieve)
	}
	encoded, err := json.Marshal(retrieve)
	if err != nil || len(encoded) > maxFrameLen {
		t.Fatalf("retrieve response frame size = %d, err = %v", len(encoded), err)
	}
}

func newCallHandlerFixture(t *testing.T, service *CallControlService) callHandlerFixture {
	t.Helper()
	mn := mocknet.New()
	relay, err := mn.GenPeer()
	if err != nil {
		t.Fatal("generate relay")
	}
	client, err := mn.GenPeer()
	if err != nil {
		t.Fatal("generate client")
	}
	recipient, err := mn.GenPeer()
	if err != nil {
		t.Fatal("generate recipient")
	}
	if err := mn.LinkAll(); err != nil {
		t.Fatal("link fixture")
	}
	if err := mn.ConnectAllButSelf(); err != nil {
		t.Fatal("connect fixture")
	}
	inbox := NewInboxStore(NewPushServiceWithBackend(newMemoryPushTokenStore()))
	groups := NewGroupInboxStore(8, time.Hour)
	presence := NewPresenceStore()
	handled := make(chan struct{}, 8)
	relay.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		defer func() { handled <- struct{}{} }()
		HandleInboxStream(stream, inbox, groups, relay, presence, nil, service)
	})
	t.Cleanup(func() {
		_ = relay.Close()
		_ = client.Close()
		_ = recipient.Close()
	})
	return callHandlerFixture{relay: relay, client: client, recipient: recipient, handled: handled}
}

func callHandlerRoundTrip(
	t *testing.T,
	fixture callHandlerFixture,
	from host.Host,
	request map[string]any,
) map[string]any {
	t.Helper()
	stream, err := from.NewStream(context.Background(), fixture.relay.ID(), InboxProtocol)
	if err != nil {
		t.Fatal("open call-control stream")
	}
	defer stream.Close()
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal("marshal call-control request")
	}
	if err := writeFrame(stream, raw); err != nil {
		t.Fatal("write call-control request")
	}
	responseRaw, err := readFrame(stream)
	if err != nil {
		t.Fatal("read call-control response")
	}
	select {
	case <-fixture.handled:
	case <-time.After(2 * time.Second):
		t.Fatal("call-control handler did not finish")
	}
	var response map[string]any
	if err := json.Unmarshal(responseRaw, &response); err != nil {
		t.Fatal("decode call-control response")
	}
	return response
}

func TestVC202CallActionsAreRegisteredOnAuthenticatedInboxProtocol(t *testing.T) {
	server := miniredis.RunT(t)
	now := time.Now().UTC().Truncate(time.Millisecond)
	service := NewCallControlService(
		newRedisCallControlStore(newTestRedisClient(t, server), "vc202-handler:"),
		&callTestWakeDispatcher{},
		func() time.Time { return now },
	)
	fixture := newCallHandlerFixture(t, service)
	recipient := fixture.recipient.ID().String()
	sender := fixture.client.ID().String()

	for _, request := range []map[string]any{
		{
			"action": "call_wake_handle_set_v1", "authorizedSenderPeerId": sender,
			"wakeHandle": callTestWake, "expiresAtMs": now.Add(time.Hour).UnixMilli(),
		},
		{
			"action": "call_token_set_v1", "tokenKind": string(CallTokenKindStandard),
			"platform": "android", "token": "handler-call-token", "expiresAtMs": now.Add(time.Hour).UnixMilli(),
		},
	} {
		response := callHandlerRoundTrip(t, fixture, fixture.recipient, request)
		if response["status"] != "OK" {
			t.Fatalf("setup action failed: %#v", response)
		}
	}

	store := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
		"action": "call_store_v1", "to": recipient, "callHandle": callTestHandleA,
		"messageId": callTestMessageA, "envelope": "encrypted-handler-envelope",
		"expiresAtMs": now.Add(45 * time.Second).UnixMilli(), "wakeHandle": callTestWake,
	})
	if store["status"] != "OK" || store["storeStatus"] != string(CallStoreStatusStored) {
		t.Fatalf("call_store_v1 response = %#v", store)
	}
	if _, forged := store["from"]; forged {
		t.Fatal("call response exposed a caller-claimed sender")
	}

	retrieve := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_retrieve_v1", "callHandle": callTestHandleA, "limit": 64,
	})
	if retrieve["status"] != "OK" {
		t.Fatalf("call_retrieve_v1 response = %#v", retrieve)
	}
	events, ok := retrieve["events"].([]any)
	if !ok || len(events) != 1 || events[0].(map[string]any)["senderPeerId"] != sender {
		t.Fatalf("retrieve lost authenticated sender attribution: %#v", retrieve)
	}

	ack := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_ack_v1", "callHandle": callTestHandleA, "messageIds": []string{callTestMessageA},
	})
	if ack["status"] != "OK" || ack["acked"] != float64(1) {
		t.Fatalf("call_ack_v1 response = %#v", ack)
	}

	missingBackend := newCallHandlerFixture(t, nil)
	failure := callHandlerRoundTrip(t, missingBackend, missingBackend.client, map[string]any{
		"action": "call_store_v1", "to": missingBackend.recipient.ID().String(),
		"callHandle": callTestHandleA, "messageId": callTestMessageA,
		"envelope": "encrypted-handler-envelope", "expiresAtMs": now.Add(time.Second).UnixMilli(),
		"wakeHandle": callTestWake,
	})
	if failure["status"] != "ERROR" || failure["errorCode"] != "CALL_BACKEND_UNAVAILABLE" {
		t.Fatalf("missing durable call backend did not fail closed: %#v", failure)
	}
}

func TestVC202ProductionProtocolRegistrationRoutesCallControlActions(t *testing.T) {
	server := miniredis.RunT(t)
	now := time.Now().UTC().Truncate(time.Millisecond)
	service := NewCallControlService(
		newRedisCallControlStore(newTestRedisClient(t, server), "vc202-production-handler:"),
		&callTestWakeDispatcher{},
		func() time.Time { return now },
	)
	fixture := newProductionCallHandlerFixture(t, service)

	wake := productionCallHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_wake_handle_set_v1", "authorizedSenderPeerId": fixture.client.ID().String(),
		"wakeHandle": callTestWake, "expiresAtMs": now.Add(time.Hour).UnixMilli(),
	})
	if wake["status"] != "OK" {
		t.Fatalf("production call_wake_handle_set_v1 response = %#v", wake)
	}

	retrieve := productionCallHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_retrieve_v1", "limit": 64,
	})
	if retrieve["status"] != "OK" || retrieve["schema"] != CallMailboxSchema ||
		retrieve["version"] != float64(CallControlVersion) || retrieve["error"] != nil {
		t.Fatalf("production call_retrieve_v1 response = %#v", retrieve)
	}
}

func newProductionCallHandlerFixture(
	t *testing.T,
	service *CallControlService,
) callHandlerFixture {
	t.Helper()
	mn := mocknet.New()
	relay, err := mn.GenPeer()
	if err != nil {
		t.Fatal("generate production relay")
	}
	client, err := mn.GenPeer()
	if err != nil {
		t.Fatal("generate production client")
	}
	recipient, err := mn.GenPeer()
	if err != nil {
		t.Fatal("generate production recipient")
	}
	if err := mn.LinkAll(); err != nil {
		t.Fatal("link production fixture")
	}
	if err := mn.ConnectAllButSelf(); err != nil {
		t.Fatal("connect production fixture")
	}
	registerRelayProtocolHandlers(relay, relayProtocolDependencies{
		Inbox:       NewInboxStore(NewPushServiceWithBackend(newMemoryPushTokenStore())),
		GroupInbox:  NewGroupInboxStore(8, time.Hour),
		Presence:    NewPresenceStore(),
		CallControl: service,
	})
	t.Cleanup(func() {
		_ = relay.Close()
		_ = client.Close()
		_ = recipient.Close()
	})
	return callHandlerFixture{relay: relay, client: client, recipient: recipient}
}

func productionCallHandlerRoundTrip(
	t *testing.T,
	fixture callHandlerFixture,
	from host.Host,
	request map[string]any,
) map[string]any {
	t.Helper()
	stream, err := from.NewStream(context.Background(), fixture.relay.ID(), InboxProtocol)
	if err != nil {
		t.Fatal("open production call-control stream")
	}
	defer stream.Close()
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal("marshal production call-control request")
	}
	if err := writeFrame(stream, raw); err != nil {
		t.Fatal("write production call-control request")
	}
	responseRaw, err := readFrame(stream)
	if err != nil {
		t.Fatal("read production call-control response")
	}
	var response map[string]any
	if err := json.Unmarshal(responseRaw, &response); err != nil {
		t.Fatal("decode production call-control response")
	}
	return response
}

func TestVC202RedisBootstrapComposesCallControlOnlyForDurableBackend(t *testing.T) {
	server := miniredis.RunT(t)
	redisStores, err := newControlPlaneStores(context.Background(), backendConfig{
		Kind: backendKindRedis, RedisURL: "redis://" + server.Addr(), RedisPrefix: "vc202-bootstrap:",
	}, DefaultServerLimits(), "/missing-fixture.json")
	if err != nil {
		t.Fatalf("newControlPlaneStores redis: %v", err)
	}
	defer func() { _ = redisStores.Close() }()
	if redisStores.CallControl == nil || redisStores.CallControlBackend == nil {
		t.Fatal("Redis bootstrap did not compose the durable call-control authority")
	}

	memoryStores, err := newControlPlaneStores(context.Background(), backendConfig{
		Kind: backendKindMemory,
	}, DefaultServerLimits(), "/missing-fixture.json")
	if err != nil {
		t.Fatalf("newControlPlaneStores memory: %v", err)
	}
	if memoryStores.CallControl != nil || memoryStores.CallControlBackend != nil {
		t.Fatal("memory bootstrap created a fail-open call-control authority")
	}
}

func TestVC202CallHandlerEnforcesActionLocalFieldsAndSignedAuthorityLifecycle(t *testing.T) {
	server := miniredis.RunT(t)
	now := time.Now().UTC().Truncate(time.Millisecond)
	dispatcher := &callTestWakeDispatcher{}
	service := NewCallControlService(
		newRedisCallControlStore(newTestRedisClient(t, server), "vc202-authority-handler:"),
		dispatcher,
		func() time.Time { return now },
	)
	fixture := newCallHandlerFixture(t, service)
	sender := fixture.client.ID().String()
	recipient := fixture.recipient.ID().String()

	invalid := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
		"action": "call_store_v1", "to": recipient, "callHandle": callTestHandleA,
		"messageId": callTestMessageA, "envelope": "encrypted", "expiresAtMs": now.Add(time.Second).UnixMilli(),
		"wakeHandle": callTestWake, "tokenKind": "ios_voip",
	})
	if invalid["status"] != "ERROR" || invalid["errorCode"] != "CALL_INVALID_REQUEST" {
		t.Fatalf("action-irrelevant field was accepted: %#v", invalid)
	}

	privateKey := fixture.recipient.Peerstore().PrivKey(fixture.recipient.ID())
	if privateKey == nil {
		t.Fatal("recipient fixture private key missing")
	}
	endpoint := CallEndpointRecord{
		AccountPeerID: recipient, DevicePeerID: recipient,
		Capabilities: []string{"voice_call_v1"}, Platform: "ios",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(), PreferenceEpoch: 1,
		DeviceKeyEpoch: 1, RoutingHandle: callTestHandleA,
	}
	canonical, err := canonicalCallEndpointRecord(endpoint)
	if err != nil {
		t.Fatal("canonical endpoint")
	}
	endpoint.Signature, err = privateKey.Sign(canonical)
	if err != nil {
		t.Fatal("sign endpoint")
	}
	setEndpoint := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_endpoint_set_v1", "accountPeerId": recipient, "devicePeerId": recipient,
		"capabilities": []string{"voice_call_v1"}, "platform": "ios",
		"expiresAtMs": endpoint.ExpiresAtMs, "preferenceEpoch": 1, "deviceKeyEpoch": 1,
		"routingHandle": callTestHandleA,
		"signature":     base64.StdEncoding.EncodeToString(endpoint.Signature),
	})
	if setEndpoint["status"] != "OK" {
		t.Fatalf("endpoint set response = %#v", setEndpoint)
	}
	getEndpoint := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
		"action": "call_endpoint_get_v1", "accountPeerId": recipient,
	})
	if getEndpoint["status"] != "OK" || getEndpoint["found"] != true ||
		getEndpoint["canonicalRecord"] != base64.StdEncoding.EncodeToString(canonical) {
		t.Fatalf("endpoint get response = %#v", getEndpoint)
	}

	for _, request := range []map[string]any{
		{
			"action": "call_wake_handle_set_v1", "authorizedSenderPeerId": sender,
			"wakeHandle": callTestWake, "expiresAtMs": now.Add(time.Hour).UnixMilli(),
		},
		{
			"action": "call_token_set_v1", "tokenKind": "standard_call",
			"platform": "android", "token": "standard-handler-token", "expiresAtMs": now.Add(time.Hour).UnixMilli(),
		},
		{
			"action": "call_token_set_v1", "tokenKind": "ios_voip",
			"platform": "ios", "token": "voip-handler-token", "expiresAtMs": now.Add(time.Hour).UnixMilli(),
			"environment": "sandbox", "topic": callTestVoIPTopic,
			"capabilityVersion": callIOSVoIPCapabilityVersion, "refreshEpoch": uint64(1),
		},
	} {
		if response := callHandlerRoundTrip(t, fixture, fixture.recipient, request); response["status"] != "OK" {
			t.Fatalf("authority setup action failed: %#v", response)
		}
	}
	store := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
		"action": "call_store_v1", "to": recipient, "callHandle": callTestHandleA,
		"messageId": callTestMessageA, "envelope": "encrypted-ios-handler",
		"expiresAtMs": now.Add(45 * time.Second).UnixMilli(), "wakeHandle": callTestWake,
	})
	if store["status"] != "OK" || len(dispatcher.routes) != 1 ||
		dispatcher.routes[0].Kind != CallTokenKindIOSVoIP || dispatcher.routes[0].Token != "voip-handler-token" {
		t.Fatalf("iOS handler call route/store = (%#v, %#v)", store, dispatcher.routes)
	}

	if response := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_token_revoke_v1", "tokenKind": "ios_voip", "expectedRefreshEpoch": uint64(1),
	}); response["status"] != "OK" || response["revoked"] != true {
		t.Fatalf("VoIP token revoke response = %#v", response)
	}
	standard, err := service.GetCallToken(context.Background(), recipient, CallTokenKindStandard)
	if err != nil || standard == nil || standard.Token != "standard-handler-token" {
		t.Fatalf("VoIP revoke overwrote standard token: (%#v, %v)", standard, err)
	}
	if response := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_wake_handle_revoke_v1", "authorizedSenderPeerId": sender,
	}); response["status"] != "OK" || response["revoked"] != true {
		t.Fatalf("wake revoke response = %#v", response)
	}
	if response := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_endpoint_revoke_v1", "accountPeerId": recipient, "preferenceEpoch": 2,
	}); response["status"] != "OK" || response["revoked"] != true {
		t.Fatalf("endpoint revoke response = %#v", response)
	}
	missing := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
		"action": "call_endpoint_get_v1", "accountPeerId": recipient,
	})
	if missing["status"] != "OK" || missing["found"] == true {
		t.Fatalf("revoked endpoint remained visible: %#v", missing)
	}
}
