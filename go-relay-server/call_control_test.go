package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"errors"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
)

const (
	callTestHandleA   = "00112233445566778899aabbccddeeff"
	callTestHandleB   = "10112233445566778899aabbccddeeff"
	callTestHandleC   = "20112233445566778899aabbccddeeff"
	callTestMessageA  = "30112233445566778899aabbccddeeff"
	callTestMessageB  = "40112233445566778899aabbccddeeff"
	callTestMessageC  = "50112233445566778899aabbccddeeff"
	callTestWake      = "50112233445566778899aabbccddeeff"
	callTestVoIPTopic = "com.mknoon.test.voip"
)

func callTestIOSVoIPToken(token string, expiresAt time.Time, refreshEpoch uint64) CallTokenRecord {
	return CallTokenRecord{
		Kind: CallTokenKindIOSVoIP, Platform: "ios", Token: token,
		ExpiresAtMs: expiresAt.UnixMilli(), Environment: "sandbox", Topic: callTestVoIPTopic,
		CapabilityVersion: callIOSVoIPCapabilityVersion, RefreshEpoch: refreshEpoch,
	}
}

func TestVC205EndpointCanonicalJSONMatchesDartContract(t *testing.T) {
	canonical, err := canonicalCallEndpointRecord(CallEndpointRecord{
		AccountPeerID:   "contact-account",
		DevicePeerID:    "contact-device",
		Capabilities:    []string{"voice_call_v1", "audio_route_v1"},
		Platform:        "android",
		ExpiresAtMs:     10_000,
		PreferenceEpoch: 4,
		DeviceKeyEpoch:  9,
		RoutingHandle:   "0123456789abcdef0123456789abcdef",
	})
	if err != nil {
		t.Fatalf("canonicalCallEndpointRecord: %v", err)
	}
	want := `{"schema":"mknoon.call_endpoint_set.v1","version":1,"accountPeerId":"contact-account","devicePeerId":"contact-device","capabilities":["audio_route_v1","voice_call_v1"],"platform":"android","expiresAtMs":10000,"preferenceEpoch":4,"deviceKeyEpoch":9,"routingHandle":"0123456789abcdef0123456789abcdef"}`
	if string(canonical) != want {
		t.Fatalf("canonical endpoint bytes = %s, want %s", canonical, want)
	}
}

type callTestWakeDispatcher struct {
	routes     []CallWakeRoute
	payloads   []CallWakePayload
	err        error
	onDispatch func()
}

func (d *callTestWakeDispatcher) DispatchCallWake(
	_ context.Context,
	route CallWakeRoute,
	payload CallWakePayload,
) error {
	d.routes = append(d.routes, route)
	d.payloads = append(d.payloads, payload)
	if d.onDispatch != nil {
		d.onDispatch()
	}
	return d.err
}

func callTestPeerID(t *testing.T) string {
	t.Helper()
	id, _ := callTestPeerIdentity(t)
	return id
}

func callTestPeerIdentity(t *testing.T) (string, libp2pcrypto.PrivKey) {
	t.Helper()
	privateKey, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatal("generate peer key")
	}
	id, err := peer.IDFromPrivateKey(privateKey)
	if err != nil {
		t.Fatal("derive peer ID")
	}
	return id.String(), privateKey
}

func callTestService(
	t *testing.T,
	now time.Time,
	dispatcher CallWakeDispatcher,
) (*CallControlService, *miniredis.Miniredis) {
	t.Helper()
	server := miniredis.RunT(t)
	store := newRedisCallControlStore(newTestRedisClient(t, server), "vc202:")
	service := NewCallControlService(store, dispatcher, func() time.Time { return now })
	return service, server
}

func authorizeCallFixture(
	t *testing.T,
	service *CallControlService,
	now time.Time,
	sender string,
	recipient string,
) {
	t.Helper()
	ctx := context.Background()
	if err := service.backend.SetEndpoint(ctx, CallEndpointRecord{
		Schema: CallEndpointSchema, Version: CallControlVersion,
		AccountPeerID: recipient, DevicePeerID: recipient,
		Capabilities: []string{"voice_call_v1"}, Platform: "android",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(), PreferenceEpoch: 1,
		DeviceKeyEpoch: 1, RoutingHandle: callTestHandleA,
		Signature: []byte("fixture-authorized-outside-service"),
	}, now); err != nil {
		t.Fatalf("SetEndpoint fixture: %v", err)
	}
	if err := service.SetWakeHandle(ctx, recipient, CallWakeHandleRecord{
		AuthorizedSenderPeerID: sender,
		WakeHandle:             callTestWake,
		ExpiresAtMs:            now.Add(time.Hour).UnixMilli(),
	}); err != nil {
		t.Fatalf("SetWakeHandle: %v", err)
	}
	if err := service.SetCallToken(ctx, recipient, CallTokenRecord{
		Kind:        CallTokenKindStandard,
		Platform:    "android",
		Token:       "android-call-token-fixture",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
	}); err != nil {
		t.Fatalf("SetCallToken: %v", err)
	}
}

func TestVC202CallMailboxRedisExactIdempotencyBoundsAndTombstone(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, server := callTestService(t, now, dispatcher)
	sender := callTestPeerID(t)
	recipient := callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)

	request := CallStoreRequest{
		RecipientDevicePeerID: recipient,
		CallHandle:            callTestHandleA,
		MessageID:             callTestMessageA,
		Envelope:              []byte("encrypted-envelope-a"),
		ExpiresAtMs:           now.Add(45 * time.Second).UnixMilli(),
		WakeHandle:            callTestWake,
	}
	receipt, err := service.Store(context.Background(), sender, request)
	if err != nil {
		t.Fatalf("Store: %v", err)
	}
	if receipt.StoreStatus != CallStoreStatusStored || receipt.ReceiptAtMs != now.UnixMilli() ||
		receipt.ExpiresAtMs != request.ExpiresAtMs {
		t.Fatalf("unexpected receipt: %#v", receipt)
	}
	duplicate, err := service.Store(context.Background(), sender, request)
	if err != nil || duplicate.StoreStatus != CallStoreStatusDuplicate {
		t.Fatalf("exact duplicate = (%#v, %v)", duplicate, err)
	}
	changed := request
	changed.Envelope = []byte("encrypted-envelope-b")
	if _, err := service.Store(context.Background(), sender, changed); !errors.Is(err, ErrCallIdentityConflict) {
		t.Fatalf("changed duplicate error = %v, want identity conflict", err)
	}
	if len(dispatcher.payloads) != 1 {
		t.Fatalf("wake dispatch count = %d, want 1 after committed unique store", len(dispatcher.payloads))
	}

	result, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{
		CallHandle: callTestHandleA,
		Limit:      64,
	})
	if err != nil || len(result.Events) != 1 {
		t.Fatalf("Retrieve = (%#v, %v)", result, err)
	}
	event := result.Events[0]
	if event.SenderPeerID != sender || event.RecipientDevicePeerID != recipient ||
		event.MessageID != request.MessageID || !bytes.Equal(event.Envelope, request.Envelope) {
		t.Fatalf("retrieved event lost exact bytes or attribution: %#v", event)
	}
	acked, err := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: callTestHandleA,
		MessageIDs: []string{callTestMessageA},
	})
	if err != nil || acked != 1 {
		t.Fatalf("Ack = (%d, %v)", acked, err)
	}
	result, err = service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleA})
	if err != nil || len(result.Events) != 0 {
		t.Fatalf("Retrieve after ACK = (%#v, %v)", result, err)
	}
	afterAck, err := service.Store(context.Background(), sender, request)
	if err != nil || afterAck.StoreStatus != CallStoreStatusDuplicate || afterAck.EventCount != 0 {
		t.Fatalf("replay after ACK = (%#v, %v), want idempotent duplicate without re-store", afterAck, err)
	}
	if len(dispatcher.payloads) != 1 {
		t.Fatalf("wake dispatch count after acked duplicate = %d, want 1", len(dispatcher.payloads))
	}
	later := request
	later.MessageID = callTestMessageB
	later.ExpiresAtMs = now.Add(44 * time.Second).UnixMilli()
	laterReceipt, err := service.Store(context.Background(), sender, later)
	if err != nil || laterReceipt.StoreStatus != CallStoreStatusStored ||
		laterReceipt.ExpiresAtMs != later.ExpiresAtMs || laterReceipt.EventCount != 1 {
		t.Fatalf("same-call event after ACK = (%#v, %v), want stored", laterReceipt, err)
	}
	result, err = service.Retrieve(context.Background(), recipient, CallRetrieveRequest{})
	if err != nil || len(result.Events) != 1 || result.Events[0].MessageID != callTestMessageB {
		t.Fatalf("drain after same-call event = (%#v, %v)", result, err)
	}

	for _, key := range server.Keys() {
		value, valueErr := server.Get(key)
		if valueErr == nil && bytes.Contains([]byte(value), request.Envelope) {
			t.Fatalf("payload survived terminal tombstone in key %q", key)
		}
		if bytes.Contains([]byte(key), []byte("inbox:")) {
			t.Fatalf("call state reused chat inbox key %q", key)
		}
	}
}

func TestVC202CallMailboxHardTTLCapacityCancelAndProcessHandoff(t *testing.T) {
	now := time.Unix(1_800_100_000, 0).UTC()
	service, server := callTestService(t, now, &callTestWakeDispatcher{})
	server.SetTime(now)
	sender := callTestPeerID(t)
	recipient := callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)

	base := CallStoreRequest{
		RecipientDevicePeerID: recipient,
		MessageID:             callTestMessageA,
		Envelope:              []byte("encrypted-envelope"),
		ExpiresAtMs:           now.Add(45 * time.Second).UnixMilli(),
		WakeHandle:            callTestWake,
	}
	for _, handle := range []string{callTestHandleA, callTestHandleB} {
		request := base
		request.CallHandle = handle
		if _, err := service.Store(context.Background(), sender, request); err != nil {
			t.Fatalf("Store(%s): %v", handle, err)
		}
	}
	third := base
	third.CallHandle = callTestHandleC
	if _, err := service.Store(context.Background(), sender, third); !errors.Is(err, ErrCallRecipientCapacity) {
		t.Fatalf("third pending handle error = %v, want capacity", err)
	}
	tooLong := base
	tooLong.CallHandle = callTestHandleA
	tooLong.MessageID = callTestMessageB
	tooLong.ExpiresAtMs = now.Add(45*time.Second + time.Millisecond).UnixMilli()
	clamped, err := service.Store(context.Background(), sender, tooLong)
	if err != nil || clamped.ExpiresAtMs != now.Add(45*time.Second).UnixMilli() {
		t.Fatalf("46-second expiry = (%#v, %v), want clamp to the hard bound", clamped, err)
	}
	tooLarge := base
	tooLarge.CallHandle = callTestHandleC
	tooLarge.Envelope = bytes.Repeat([]byte{0x5a}, CallMaxEnvelopeBytes+1)
	if _, err := service.Store(context.Background(), sender, tooLarge); !errors.Is(err, ErrCallEnvelopeTooLarge) {
		t.Fatalf("oversize error = %v, want envelope-too-large", err)
	}

	if err := service.Cancel(context.Background(), sender, CallCancelRequest{
		RecipientDevicePeerID: recipient,
		CallHandle:            callTestHandleA,
	}); err != nil {
		t.Fatalf("Cancel: %v", err)
	}
	result, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleA})
	if err != nil || len(result.Events) != 0 {
		t.Fatalf("Retrieve canceled call = (%#v, %v)", result, err)
	}

	callBKeys := service.backend.callKeys(recipient, callTestHandleB)
	beforeRestartTTL, err := service.backend.client.PTTL(context.Background(), callBKeys.events).Result()
	if err != nil || beforeRestartTTL <= 0 || beforeRestartTTL > CallMaxPreconnectTTL {
		t.Fatalf("payload TTL before Redis restart = (%s, %v)", beforeRestartTTL, err)
	}
	if err := service.backend.client.Close(); err != nil {
		t.Fatalf("close pre-handoff Redis client: %v", err)
	}
	server.Close()
	if err := server.Restart(); err != nil {
		t.Fatalf("restart Redis fixture with preserved data: %v", err)
	}

	clientB := newTestRedisClient(t, server)
	handoff := NewCallControlService(
		newRedisCallControlStore(clientB, "vc202:"),
		&callTestWakeDispatcher{},
		func() time.Time { return now },
	)
	result, err = handoff.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleB})
	if err != nil || len(result.Events) != 1 {
		t.Fatalf("process handoff retrieve = (%#v, %v)", result, err)
	}
	afterRestartTTL, err := clientB.PTTL(context.Background(), callBKeys.events).Result()
	if err != nil || afterRestartTTL != beforeRestartTTL {
		t.Fatalf("payload TTL across Redis restart = (%s -> %s, %v)", beforeRestartTTL, afterRestartTTL, err)
	}

	server.FastForward(CallMaxPreconnectTTL)
	handoff.now = func() time.Time { return now.Add(CallMaxPreconnectTTL) }
	result, err = handoff.Retrieve(context.Background(), recipient, CallRetrieveRequest{
		CallHandle: callTestHandleB,
	})
	if err != nil || len(result.Events) != 0 {
		t.Fatalf("hard-expired payload returned after handoff = (%#v, %v)", result, err)
	}
	replay := base
	replay.CallHandle = callTestHandleB
	replay.MessageID = callTestMessageB
	replay.ExpiresAtMs = now.Add(2 * CallMaxPreconnectTTL).UnixMilli()
	if _, err := handoff.Store(context.Background(), sender, replay); !errors.Is(err, ErrCallReplay) {
		t.Fatalf("replay tombstone after hard expiry error = %v, want replay", err)
	}
}

func TestVC202EndpointWakeAndCallTokensAreTypedDurableAndIndependent(t *testing.T) {
	now := time.Unix(1_800_200_000, 0).UTC()
	service, server := callTestService(t, now, nil)
	server.SetTime(now)
	account, accountKey := callTestPeerIdentity(t)
	device := callTestPeerID(t)
	sender := callTestPeerID(t)

	endpoint := CallEndpointRecord{
		AccountPeerID:   account,
		DevicePeerID:    device,
		Capabilities:    []string{"voice_call_v1"},
		Platform:        "ios",
		ExpiresAtMs:     now.Add(time.Hour).UnixMilli(),
		PreferenceEpoch: 8,
		DeviceKeyEpoch:  13,
		RoutingHandle:   callTestHandleA,
	}
	canonical, err := canonicalCallEndpointRecord(endpoint)
	if err != nil {
		t.Fatalf("canonicalCallEndpointRecord: %v", err)
	}
	endpoint.Signature, err = accountKey.Sign(canonical)
	if err != nil {
		t.Fatalf("sign endpoint: %v", err)
	}
	if err := service.SetEndpoint(context.Background(), device, endpoint); err != nil {
		t.Fatalf("SetEndpoint: %v", err)
	}
	gotEndpoint, err := service.GetEndpoint(context.Background(), sender, account)
	if err != nil || gotEndpoint == nil || gotEndpoint.PreferenceEpoch != endpoint.PreferenceEpoch ||
		gotEndpoint.DevicePeerID != device || len(gotEndpoint.Capabilities) != 1 {
		t.Fatalf("GetEndpoint = (%#v, %v)", gotEndpoint, err)
	}
	stale := endpoint
	stale.PreferenceEpoch--
	canonical, _ = canonicalCallEndpointRecord(stale)
	stale.Signature, _ = accountKey.Sign(canonical)
	if err := service.SetEndpoint(context.Background(), device, stale); !errors.Is(err, ErrCallStaleEpoch) {
		t.Fatalf("stale endpoint error = %v", err)
	}
	forged := endpoint
	forged.PreferenceEpoch++
	forged.RoutingHandle = callTestHandleB
	if err := service.SetEndpoint(context.Background(), device, forged); !errors.Is(err, ErrCallUnauthorized) {
		t.Fatalf("tampered endpoint error = %v, want unauthorized", err)
	}

	if err := service.SetWakeHandle(context.Background(), device, CallWakeHandleRecord{
		AuthorizedSenderPeerID: sender,
		WakeHandle:             callTestWake,
		ExpiresAtMs:            now.Add(time.Hour).UnixMilli(),
	}); err != nil {
		t.Fatalf("SetWakeHandle: %v", err)
	}
	ordinaryPush := newRedisPushTokenBackend(service.backend.client, "vc202:")
	ordinaryPush.now = func() time.Time { return now }
	if err := ordinaryPush.RegisterToken(device, "ordinary-notification-token", "ios"); err != nil {
		t.Fatalf("RegisterToken ordinary notification: %v", err)
	}
	standard := CallTokenRecord{Kind: CallTokenKindStandard, Platform: "android", Token: "same-provider-token", ExpiresAtMs: now.Add(time.Hour).UnixMilli()}
	voip := callTestIOSVoIPToken("same-provider-token", now.Add(time.Hour), 1)
	if err := service.SetCallToken(context.Background(), device, standard); err != nil {
		t.Fatalf("SetCallToken standard: %v", err)
	}
	if err := service.SetCallToken(context.Background(), device, voip); err != nil {
		t.Fatalf("SetCallToken voip: %v", err)
	}

	durableKeys := map[string]string{
		"endpoint":       service.backend.endpointKey(account),
		"endpoint route": service.backend.endpointDeviceKey(device),
		"wake handle":    service.backend.wakeKey(device, sender),
		"standard token": service.backend.tokenKey(device, CallTokenKindStandard),
		"VoIP token":     service.backend.tokenKey(device, CallTokenKindIOSVoIP),
	}
	beforeRestartTTLs := make(map[string]time.Duration, len(durableKeys))
	for name, key := range durableKeys {
		ttl, ttlErr := service.backend.client.PTTL(context.Background(), key).Result()
		if ttlErr != nil || ttl <= 0 || ttl > time.Hour {
			t.Fatalf("%s TTL before Redis restart = (%s, %v)", name, ttl, ttlErr)
		}
		beforeRestartTTLs[name] = ttl
	}
	if exists, existsErr := service.backend.client.Exists(context.Background(), ordinaryPush.key(device)).Result(); existsErr != nil || exists != 1 {
		t.Fatalf("ordinary notification token missing before Redis restart = (%d, %v)", exists, existsErr)
	}
	if err := service.backend.client.Close(); err != nil {
		t.Fatalf("close pre-handoff Redis client: %v", err)
	}
	server.Close()
	if err := server.Restart(); err != nil {
		t.Fatalf("restart Redis fixture with preserved call authority: %v", err)
	}

	dispatcher := &callTestWakeDispatcher{}
	handoff := NewCallControlService(
		newRedisCallControlStore(newTestRedisClient(t, server), "vc202:"),
		dispatcher,
		func() time.Time { return now },
	)
	for name, key := range durableKeys {
		ttl, ttlErr := handoff.backend.client.PTTL(context.Background(), key).Result()
		if ttlErr != nil || ttl != beforeRestartTTLs[name] {
			t.Fatalf("%s TTL across Redis restart = (%s -> %s, %v)", name, beforeRestartTTLs[name], ttl, ttlErr)
		}
	}
	ordinaryHandoff := newRedisPushTokenBackend(handoff.backend.client, "vc202:")
	ordinaryRoute, err := ordinaryHandoff.LookupRoute(device)
	if err != nil || ordinaryRoute == nil {
		t.Fatalf("ordinary notification route process handoff = (%#v, %v)", ordinaryRoute, err)
	}
	ordinaryTarget, err := ordinaryHandoff.ResolveRoute(*ordinaryRoute)
	if err != nil || ordinaryTarget == nil || ordinaryTarget.Token != "ordinary-notification-token" ||
		ordinaryTarget.Platform != "ios" {
		t.Fatalf("ordinary notification token process handoff = (%#v, %v)", ordinaryTarget, err)
	}
	gotEndpoint, err = handoff.GetEndpoint(context.Background(), sender, account)
	if err != nil || gotEndpoint == nil || gotEndpoint.DevicePeerID != device ||
		gotEndpoint.PreferenceEpoch != endpoint.PreferenceEpoch {
		t.Fatalf("endpoint process handoff = (%#v, %v)", gotEndpoint, err)
	}
	standardGot, err := handoff.GetCallToken(context.Background(), device, CallTokenKindStandard)
	if err != nil || standardGot == nil || standardGot.Platform != "android" {
		t.Fatalf("GetCallToken standard = (%#v, %v)", standardGot, err)
	}
	voipGot, err := handoff.GetCallToken(context.Background(), device, CallTokenKindIOSVoIP)
	if err != nil || voipGot == nil || voipGot.Platform != "ios" {
		t.Fatalf("GetCallToken voip = (%#v, %v)", voipGot, err)
	}
	if _, err := handoff.Store(context.Background(), sender, CallStoreRequest{
		RecipientDevicePeerID: device,
		CallHandle:            callTestHandleB,
		MessageID:             callTestMessageA,
		Envelope:              []byte("encrypted-authority-handoff-envelope"),
		ExpiresAtMs:           now.Add(CallMaxPreconnectTTL).UnixMilli(),
		WakeHandle:            callTestWake,
	}); err != nil {
		t.Fatalf("wake authority process handoff store: %v", err)
	}
	if len(dispatcher.routes) != 1 || dispatcher.routes[0].Kind != CallTokenKindIOSVoIP ||
		dispatcher.routes[0].Platform != "ios" {
		t.Fatalf("durable authority handoff selected route %#v", dispatcher.routes)
	}
	if err := handoff.RevokeCallToken(context.Background(), device, CallTokenKindIOSVoIP); err != nil {
		t.Fatalf("RevokeCallToken voip: %v", err)
	}
	standardGot, err = handoff.GetCallToken(context.Background(), device, CallTokenKindStandard)
	if err != nil || standardGot == nil {
		t.Fatalf("VoIP revocation overwrote standard call token: (%#v, %v)", standardGot, err)
	}
	ordinaryRoute, err = ordinaryHandoff.LookupRoute(device)
	if err != nil || ordinaryRoute == nil {
		t.Fatalf("VoIP revocation overwrote ordinary notification route: (%#v, %v)", ordinaryRoute, err)
	}
	ordinaryTarget, err = ordinaryHandoff.ResolveRoute(*ordinaryRoute)
	if err != nil || ordinaryTarget == nil || ordinaryTarget.Token != "ordinary-notification-token" {
		t.Fatalf("VoIP revocation overwrote ordinary notification token: (%#v, %v)", ordinaryTarget, err)
	}
}
