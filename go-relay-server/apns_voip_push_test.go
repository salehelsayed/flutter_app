package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

type vc205ProviderStep struct {
	response apnsVoIPProviderResponse
	err      error
}

type vc205Provider struct {
	steps    []vc205ProviderStep
	requests []apnsVoIPProviderRequest
}

type vc205AuthorizationSource struct {
	authorization string
	allowRefresh  bool
}

func (s *vc205AuthorizationSource) Authorization(context.Context) (string, error) {
	return s.authorization, nil
}

func (s *vc205AuthorizationSource) HandleExpiredProviderToken(used string) bool {
	return s.allowRefresh && used == s.authorization
}

type vc205ES256Signer struct {
	privateKey *ecdsa.PrivateKey
	calls      int
	err        error
}

func (s *vc205ES256Signer) SignDigest(digest []byte) (*big.Int, *big.Int, error) {
	s.calls++
	if s.err != nil {
		return nil, nil, s.err
	}
	return ecdsa.Sign(rand.Reader, s.privateKey, digest)
}

func vc205PrivateKey(t *testing.T) *ecdsa.PrivateKey {
	t.Helper()
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate P-256 key: %v", err)
	}
	return privateKey
}

func vc205PrivateKeyFile(t *testing.T) string {
	t.Helper()
	privateKey := vc205PrivateKey(t)
	der, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		t.Fatalf("marshal PKCS#8 key: %v", err)
	}
	path := filepath.Join(t.TempDir(), "AuthKey_PRIVATE_CANARY.p8")
	if err := os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), 0o600); err != nil {
		t.Fatalf("write key fixture: %v", err)
	}
	return path
}

func (p *vc205Provider) Send(
	_ context.Context,
	request apnsVoIPProviderRequest,
) (apnsVoIPProviderResponse, error) {
	copy := request
	copy.Payload = append([]byte(nil), request.Payload...)
	p.requests = append(p.requests, copy)
	index := len(p.requests) - 1
	if index >= len(p.steps) {
		return apnsVoIPProviderResponse{}, ErrCallBackendUnavailable
	}
	return p.steps[index].response, p.steps[index].err
}

func vc205Route(token string, refreshEpoch, generation uint64) CallWakeRoute {
	return CallWakeRoute{
		Kind: CallTokenKindIOSVoIP, Platform: "ios", Token: token,
		Environment: "sandbox", Topic: callTestVoIPTopic,
		CapabilityVersion: callIOSVoIPCapabilityVersion,
		RefreshEpoch:      refreshEpoch, Generation: generation,
	}
}

func vc205Payload(now time.Time) CallWakePayload {
	return CallWakePayload{
		CallHandle: callTestHandleA, WakeHandle: callTestWake,
		ExpiresAtMs: now.Add(CallMaxPreconnectTTL).UnixMilli(),
	}
}

func vc205Dispatcher(provider apnsVoIPProvider, now time.Time) *apnsVoIPCallWakeDispatcher {
	return &apnsVoIPCallWakeDispatcher{
		providers: map[string]apnsVoIPProvider{"sandbox": provider}, topic: callTestVoIPTopic,
		capabilityVersion: callIOSVoIPCapabilityVersion,
		now:               func() time.Time { return now },
	}
}

func TestVC205IOSVoIPTokenAuthorityIsMonotonicIdempotentAndRotationSafe(t *testing.T) {
	now := time.Unix(1_802_000_000, 0).UTC()
	service, server := callTestService(t, now, nil)
	device := callTestPeerID(t)
	ctx := context.Background()

	ordinary := newRedisPushTokenBackend(service.backend.client, "vc202:")
	ordinary.now = func() time.Time { return now }
	if err := ordinary.RegisterToken(device, "ordinary-ios-notification-token", "ios"); err != nil {
		t.Fatalf("register ordinary notification token: %v", err)
	}
	standard := CallTokenRecord{
		Kind: CallTokenKindStandard, Platform: "android", Token: "standard-call-token",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
	}
	if err := service.SetCallToken(ctx, device, standard); err != nil {
		t.Fatalf("set standard call token: %v", err)
	}

	registration := callTestIOSVoIPToken("same-pushkit-token", now.Add(time.Hour), 41)
	first, err := service.SetCallTokenWithResult(ctx, device, registration)
	if err != nil || first == nil || first.Generation != 1 || first.RefreshEpoch != 41 {
		t.Fatalf("first VoIP registration = (%#v, %v)", first, err)
	}
	key := service.backend.tokenKey(device, CallTokenKindIOSVoIP)
	before, err := service.backend.client.HGet(ctx, key, "record").Result()
	if err != nil {
		t.Fatalf("read first registration: %v", err)
	}
	duplicate, err := service.SetCallTokenWithResult(ctx, device, registration)
	if err != nil || duplicate == nil || duplicate.Generation != first.Generation {
		t.Fatalf("exact duplicate registration = (%#v, %v)", duplicate, err)
	}
	after, err := service.backend.client.HGet(ctx, key, "record").Result()
	if err != nil || after != before {
		t.Fatalf("exact duplicate rewrote durable record = (%q -> %q, %v)", before, after, err)
	}
	extendedRegistration := registration
	extendedRegistration.ExpiresAtMs = now.Add(90 * time.Minute).UnixMilli()
	extended, err := service.SetCallTokenWithResult(ctx, device, extendedRegistration)
	if err != nil || extended == nil || extended.Generation != first.Generation ||
		extended.ExpiresAtMs != extendedRegistration.ExpiresAtMs {
		t.Fatalf("same-epoch monotonic expiry extension = (%#v, %v)", extended, err)
	}
	shortened, err := service.SetCallTokenWithResult(ctx, device, registration)
	if err != nil || shortened == nil || shortened.Generation != first.Generation ||
		shortened.ExpiresAtMs != extendedRegistration.ExpiresAtMs {
		t.Fatalf("same-epoch expiry shortening was not a no-op = (%#v, %v)", shortened, err)
	}

	stale := registration
	stale.Token = "stale-rotation-token"
	if _, err := service.SetCallTokenWithResult(ctx, device, stale); !errors.Is(err, ErrCallStaleEpoch) {
		t.Fatalf("same-epoch nonduplicate error = %v, want stale epoch", err)
	}
	stale.RefreshEpoch--
	if _, err := service.SetCallTokenWithResult(ctx, device, stale); !errors.Is(err, ErrCallStaleEpoch) {
		t.Fatalf("lower-epoch registration error = %v, want stale epoch", err)
	}

	refreshedRegistration := registration
	refreshedRegistration.RefreshEpoch = 42
	refreshedRegistration.ExpiresAtMs = now.Add(2 * time.Hour).UnixMilli()
	refreshed, err := service.SetCallTokenWithResult(ctx, device, refreshedRegistration)
	if err != nil || refreshed == nil || refreshed.Generation != 2 ||
		refreshed.Token != registration.Token {
		t.Fatalf("same-token refresh = (%#v, %v)", refreshed, err)
	}
	if err := service.backend.RevokeCallTokenIfMatch(ctx, device, callWakeRouteFromToken(*first)); err != nil {
		t.Fatalf("old invalid-token CAS: %v", err)
	}
	current, err := service.GetCallToken(ctx, device, CallTokenKindIOSVoIP)
	if err != nil || current == nil || current.Generation != refreshed.Generation {
		t.Fatalf("old invalid response removed same-token refresh: (%#v, %v)", current, err)
	}
	if revoked, err := service.RevokeCallTokenRefreshEpoch(
		ctx, device, CallTokenKindIOSVoIP, registration.RefreshEpoch,
	); err != nil || revoked {
		t.Fatalf("stale client revoke = (%v, %v), want spared", revoked, err)
	}
	if revoked, err := service.RevokeCallTokenRefreshEpoch(
		ctx, device, CallTokenKindIOSVoIP, refreshed.RefreshEpoch,
	); err != nil || !revoked {
		t.Fatalf("current client revoke = (%v, %v), want revoked", revoked, err)
	}
	if _, err := service.SetCallTokenWithResult(ctx, device, registration); !errors.Is(err, ErrCallStaleEpoch) {
		t.Fatalf("revoked refresh epoch was resurrected: %v", err)
	}

	if err := service.backend.client.Close(); err != nil {
		t.Fatalf("close Redis client: %v", err)
	}
	server.Close()
	if err := server.Restart(); err != nil {
		t.Fatalf("restart Redis with generation high-water: %v", err)
	}
	handoff := NewCallControlService(
		newRedisCallControlStore(newTestRedisClient(t, server), "vc202:"), nil,
		func() time.Time { return now },
	)
	rotatedRegistration := callTestIOSVoIPToken("rotated-pushkit-token", now.Add(3*time.Hour), 43)
	rotated, err := handoff.SetCallTokenWithResult(ctx, device, rotatedRegistration)
	if err != nil || rotated == nil || rotated.Generation != 3 {
		t.Fatalf("post-restart rotation generation = (%#v, %v), want 3", rotated, err)
	}
	standardGot, err := handoff.GetCallToken(ctx, device, CallTokenKindStandard)
	if err != nil || standardGot == nil || standardGot.Token != standard.Token {
		t.Fatalf("VoIP updates changed standard_call authority: (%#v, %v)", standardGot, err)
	}
	ordinaryHandoff := newRedisPushTokenBackend(handoff.backend.client, "vc202:")
	route, err := ordinaryHandoff.LookupRoute(device)
	if err != nil || route == nil {
		t.Fatalf("VoIP updates changed ordinary notification route: (%#v, %v)", route, err)
	}
	target, err := ordinaryHandoff.ResolveRoute(*route)
	if err != nil || target == nil || target.Token != "ordinary-ios-notification-token" {
		t.Fatalf("VoIP updates changed ordinary notification token: (%#v, %v)", target, err)
	}
}

func TestVC205IOSVoIPRedisOutageMutationsFailClosedWithoutOrdinaryFallback(t *testing.T) {
	now := time.Unix(1_802_000_050, 0).UTC()
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{
		Addr: server.Addr(), MaxRetries: -1,
		DialTimeout: 20 * time.Millisecond, ReadTimeout: 20 * time.Millisecond, WriteTimeout: 20 * time.Millisecond,
	})
	t.Cleanup(func() { _ = client.Close() })

	const prefix = "vc205-voip-outage:"
	store := newRedisCallControlStore(client, prefix)
	ordinary := newRedisPushTokenBackend(client, prefix)
	ordinary.now = func() time.Time { return now }
	recorder := newRecordingPushSender()
	push := NewPushServiceWithBackend(ordinary)
	push.sender = recorder.Send
	service := NewCallControlService(
		store,
		platformCallWakeDispatcher{android: pushServiceCallWakeDispatcher{push: push}},
		func() time.Time { return now },
	)
	ctx := context.Background()
	device := callTestPeerID(t)
	newDevice := callTestPeerID(t)

	if err := ordinary.RegisterToken(device, "ordinary-notification-authority", "ios"); err != nil {
		t.Fatal("register ordinary notification authority")
	}
	standard := CallTokenRecord{
		Kind: CallTokenKindStandard, Platform: "android", Token: "standard-call-authority",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
	}
	if err := service.SetCallToken(ctx, device, standard); err != nil {
		t.Fatal("register standard call authority")
	}
	initialRegistration := callTestIOSVoIPToken("initial-voip-authority", now.Add(time.Hour), 17)
	initial, err := service.SetCallTokenWithResult(ctx, device, initialRegistration)
	if err != nil || initial == nil || initial.Generation != 1 {
		t.Fatal("register initial VoIP authority")
	}

	server.Close()

	if stored, err := service.SetCallTokenWithResult(
		ctx, newDevice, callTestIOSVoIPToken("uncommitted-voip-authority", now.Add(time.Hour), 1),
	); stored != nil || !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("first registration during Redis outage = (stored %t, %v), want no result and backend unavailable", stored != nil, err)
	}
	rotation := initialRegistration
	rotation.Token = "uncommitted-rotated-voip-authority"
	rotation.RefreshEpoch++
	rotation.ExpiresAtMs = now.Add(2 * time.Hour).UnixMilli()
	if stored, err := service.SetCallTokenWithResult(ctx, device, rotation); stored != nil || !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("rotation during Redis outage = (stored %t, %v), want no result and backend unavailable", stored != nil, err)
	}
	if revoked, err := service.RevokeCallTokenRefreshEpoch(
		ctx, device, CallTokenKindIOSVoIP, initial.RefreshEpoch,
	); revoked || !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("epoch revoke during Redis outage = (revoked %t, %v), want false and backend unavailable", revoked, err)
	}
	if err := service.backend.RevokeCallTokenIfMatch(
		ctx, device, callWakeRouteFromToken(*initial),
	); !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("provider CAS cleanup during Redis outage error = %v, want backend unavailable", err)
	}
	if err := service.RevokeCallToken(ctx, device, CallTokenKindIOSVoIP); !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("unconditional revoke during Redis outage error = %v, want backend unavailable", err)
	}
	if calls := recorder.SendCallCount(); calls != 0 {
		t.Fatalf("VoIP mutation outage invoked ordinary push %d time(s)", calls)
	}

	if err := client.Close(); err != nil {
		t.Fatal("close unavailable Redis client")
	}
	if err := server.Restart(); err != nil {
		t.Fatal("restart Redis after mutation outage")
	}
	handoffClient := newTestRedisClient(t, server)
	handoff := NewCallControlService(
		newRedisCallControlStore(handoffClient, prefix), nil, func() time.Time { return now },
	)
	current, err := handoff.GetCallToken(ctx, device, CallTokenKindIOSVoIP)
	if err != nil || current == nil || current.Generation != initial.Generation ||
		current.RefreshEpoch != initial.RefreshEpoch || current.Token != initial.Token {
		t.Fatal("failed outage mutations changed the durable VoIP authority")
	}
	if absent, err := handoff.GetCallToken(ctx, newDevice, CallTokenKindIOSVoIP); err != nil || absent != nil {
		t.Fatal("failed first registration gained durable or in-memory success")
	}
	standardCurrent, err := handoff.GetCallToken(ctx, device, CallTokenKindStandard)
	if err != nil || standardCurrent == nil || standardCurrent.Token != standard.Token {
		t.Fatal("VoIP mutation outage changed the standard call authority")
	}
	ordinaryHandoff := newRedisPushTokenBackend(handoffClient, prefix)
	ordinaryHandoff.now = func() time.Time { return now }
	route, err := ordinaryHandoff.LookupRoute(device)
	if err != nil || route == nil {
		t.Fatal("VoIP mutation outage changed the ordinary notification route")
	}
	target, err := ordinaryHandoff.ResolveRoute(*route)
	if err != nil || target == nil || target.Token != "ordinary-notification-authority" {
		t.Fatal("VoIP mutation outage changed the ordinary notification authority")
	}
	if calls := recorder.SendCallCount(); calls != 0 {
		t.Fatalf("outage recovery invoked ordinary push %d time(s)", calls)
	}
}

func TestVC205IOSVoIPRegistrationValidatesBoundMetadata(t *testing.T) {
	now := time.Unix(1_802_000_100, 0).UTC()
	service, _ := callTestService(t, now, nil)
	device := callTestPeerID(t)
	base := callTestIOSVoIPToken("pushkit-token", now.Add(time.Hour), 1)

	tests := map[string]func(*CallTokenRecord){
		"development environment is not a relay value": func(record *CallTokenRecord) { record.Environment = "development" },
		"missing environment":                          func(record *CallTokenRecord) { record.Environment = "" },
		"ordinary topic":                               func(record *CallTokenRecord) { record.Topic = "com.mknoon.test" },
		"invalid topic characters":                     func(record *CallTokenRecord) { record.Topic = "com.mknoon/test.voip" },
		"unsupported capability":                       func(record *CallTokenRecord) { record.CapabilityVersion++ },
		"missing refresh epoch":                        func(record *CallTokenRecord) { record.RefreshEpoch = 0 },
		"client-supplied generation":                   func(record *CallTokenRecord) { record.Generation = 1 },
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			record := base
			mutate(&record)
			if _, err := service.SetCallTokenWithResult(context.Background(), device, record); !errors.Is(err, ErrCallInvalidRequest) {
				t.Fatalf("error = %v, want invalid request", err)
			}
		})
	}
	standardWithVoIPMetadata := CallTokenRecord{
		Kind: CallTokenKindStandard, Platform: "android", Token: "standard",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(), Environment: "sandbox",
	}
	if err := service.SetCallToken(context.Background(), device, standardWithVoIPMetadata); !errors.Is(err, ErrCallInvalidRequest) {
		t.Fatalf("standard_call accepted VoIP metadata: %v", err)
	}
}

func TestVC205CallTokenSchemaCorruptionFailsClosed(t *testing.T) {
	now := time.Unix(1_802_000_150, 0).UTC()
	corruptions := map[string]func(*CallTokenRecord){
		"missing schema": func(record *CallTokenRecord) { record.Schema = "" },
		"wrong schema":   func(record *CallTokenRecord) { record.Schema = "mknoon.call_token.v0" },
		"missing version": func(record *CallTokenRecord) {
			record.Version = 0
		},
		"wrong version": func(record *CallTokenRecord) { record.Version = CallControlVersion + 1 },
	}
	writeRecord := func(t *testing.T, service *CallControlService, device string, record CallTokenRecord) {
		t.Helper()
		raw, err := marshalCallRecord(record)
		if err != nil {
			t.Fatalf("marshal corrupt token record: %v", err)
		}
		if err := service.backend.client.HSet(
			context.Background(), service.backend.tokenKey(device, record.Kind), "record", raw,
		).Err(); err != nil {
			t.Fatalf("write corrupt token record: %v", err)
		}
	}

	for name, corrupt := range corruptions {
		t.Run("ios_voip "+name, func(t *testing.T) {
			service, _ := callTestService(t, now, nil)
			device := callTestPeerID(t)
			registration := callTestIOSVoIPToken("schema-token", now.Add(time.Hour), 7)
			stored, err := service.SetCallTokenWithResult(context.Background(), device, registration)
			if err != nil || stored == nil {
				t.Fatalf("set valid token fixture: (%#v, %v)", stored, err)
			}
			raw, err := service.backend.client.HGet(
				context.Background(), service.backend.tokenKey(device, CallTokenKindIOSVoIP), "record",
			).Result()
			if err != nil || !strings.Contains(raw, `"schema":"`+CallTokenSchema+`"`) ||
				!strings.Contains(raw, `"version":1`) {
				t.Fatalf("durable token schema/version = (%q, %v)", raw, err)
			}
			corrupt(stored)
			writeRecord(t, service, device, *stored)

			if got, err := service.GetCallToken(context.Background(), device, CallTokenKindIOSVoIP); got != nil || !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("read corrupt token = (%#v, %v)", got, err)
			}
			replacement := callTestIOSVoIPToken("replacement-token", now.Add(2*time.Hour), 8)
			if _, err := service.SetCallTokenWithResult(context.Background(), device, replacement); !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("set over corrupt token error = %v", err)
			}
			if revoked, err := service.RevokeCallTokenRefreshEpoch(
				context.Background(), device, CallTokenKindIOSVoIP, stored.RefreshEpoch,
			); revoked || !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("epoch revoke corrupt token = (%v, %v)", revoked, err)
			}
			if err := service.backend.RevokeCallTokenIfMatch(
				context.Background(), device, callWakeRouteFromToken(*stored),
			); !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("provider CAS revoke corrupt token error = %v", err)
			}
		})

		t.Run("standard_call "+name, func(t *testing.T) {
			dispatcher := &callTestWakeDispatcher{}
			service, _ := callTestService(t, now, dispatcher)
			sender, recipient := callTestPeerID(t), callTestPeerID(t)
			authorizeCallFixture(t, service, now, sender, recipient)
			stored, err := service.GetCallToken(context.Background(), recipient, CallTokenKindStandard)
			if err != nil || stored == nil {
				t.Fatalf("get valid standard token fixture: (%#v, %v)", stored, err)
			}
			corrupt(stored)
			writeRecord(t, service, recipient, *stored)
			if got, err := service.GetCallToken(context.Background(), recipient, CallTokenKindStandard); got != nil || !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("read corrupt standard token = (%#v, %v)", got, err)
			}
			if err := service.SetCallToken(context.Background(), recipient, CallTokenRecord{
				Kind: CallTokenKindStandard, Platform: "android", Token: "replacement-standard",
				ExpiresAtMs: now.Add(2 * time.Hour).UnixMilli(),
			}); !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("set over corrupt standard token error = %v", err)
			}
			if err := service.RevokeCallToken(context.Background(), recipient, CallTokenKindStandard); !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("revoke corrupt standard token error = %v", err)
			}
			if _, err := service.Store(context.Background(), sender, CallStoreRequest{
				RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
				MessageID: callTestMessageA, Envelope: []byte("encrypted-invite"),
				ExpiresAtMs: now.Add(CallMaxPreconnectTTL).UnixMilli(), WakeHandle: callTestWake,
			}); !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("claim with corrupt token error = %v", err)
			}
			if len(dispatcher.routes) != 0 {
				t.Fatalf("corrupt token reached provider: %d dispatches", len(dispatcher.routes))
			}
		})
	}
}

func TestVC205IOSVoIPTokenWireReturnsGenerationAndRevokesByRefreshEpoch(t *testing.T) {
	server := miniredis.RunT(t)
	now := time.Unix(1_802_000_200, 0).UTC()
	service := NewCallControlService(
		newRedisCallControlStore(newTestRedisClient(t, server), "vc205-wire:"), nil,
		func() time.Time { return now },
	)
	fixture := newCallHandlerFixture(t, service)
	device := fixture.recipient.ID().String()
	request := map[string]any{
		"action": "call_token_set_v1", "tokenKind": "ios_voip", "platform": "ios",
		"token": "wire-pushkit-token", "expiresAtMs": now.Add(time.Hour).UnixMilli(),
		"environment": "sandbox", "topic": callTestVoIPTopic,
		"capabilityVersion": callIOSVoIPCapabilityVersion, "refreshEpoch": uint64(9),
	}
	first := callHandlerRoundTrip(t, fixture, fixture.recipient, request)
	if first["status"] != "OK" || first["refreshEpoch"] != float64(9) || first["generation"] != float64(1) {
		t.Fatalf("first token set response = %#v", first)
	}
	duplicate := callHandlerRoundTrip(t, fixture, fixture.recipient, request)
	if duplicate["status"] != "OK" || duplicate["generation"] != first["generation"] {
		t.Fatalf("duplicate token set response = %#v", duplicate)
	}
	request["refreshEpoch"] = uint64(10)
	request["expiresAtMs"] = now.Add(2 * time.Hour).UnixMilli()
	refreshed := callHandlerRoundTrip(t, fixture, fixture.recipient, request)
	if refreshed["status"] != "OK" || refreshed["generation"] != float64(2) {
		t.Fatalf("refreshed token set response = %#v", refreshed)
	}
	for name, invalid := range map[string]map[string]any{
		"old revoke field": {
			"action": "call_token_revoke_v1", "tokenKind": "ios_voip", "refreshEpoch": uint64(10),
		},
		"missing expected epoch": {
			"action": "call_token_revoke_v1", "tokenKind": "ios_voip",
		},
		"standard with explicit epoch": {
			"action": "call_token_revoke_v1", "tokenKind": "standard_call", "expectedRefreshEpoch": uint64(0),
		},
	} {
		t.Run(name, func(t *testing.T) {
			response := callHandlerRoundTrip(t, fixture, fixture.recipient, invalid)
			if response["status"] != "ERROR" || response["errorCode"] != "CALL_INVALID_REQUEST" {
				t.Fatalf("invalid revoke wire accepted: %#v", response)
			}
		})
	}
	staleRevoke := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_token_revoke_v1", "tokenKind": "ios_voip", "expectedRefreshEpoch": uint64(9),
	})
	if staleRevoke["status"] != "OK" || staleRevoke["revoked"] != false {
		t.Fatalf("stale revoke response = %#v", staleRevoke)
	}
	current, err := service.GetCallToken(context.Background(), device, CallTokenKindIOSVoIP)
	if err != nil || current == nil || current.RefreshEpoch != 10 {
		t.Fatalf("stale wire revoke removed current token: (%#v, %v)", current, err)
	}
	currentRevoke := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": "call_token_revoke_v1", "tokenKind": "ios_voip", "expectedRefreshEpoch": uint64(10),
	})
	if currentRevoke["status"] != "OK" || currentRevoke["revoked"] != true {
		t.Fatalf("current revoke response = %#v", currentRevoke)
	}
	request["generation"] = uint64(99)
	if response := callHandlerRoundTrip(t, fixture, fixture.recipient, request); response["status"] != "ERROR" || response["errorCode"] != "CALL_INVALID_REQUEST" {
		t.Fatalf("client-supplied generation was accepted: %#v", response)
	}
}

func TestVC205APNSVoIPProviderTokenIsES256CachedAndRefreshBounded(t *testing.T) {
	issuedAt := time.Unix(1_802_000_250, 0).UTC()
	clock := issuedAt
	privateKey := vc205PrivateKey(t)
	signer := &vc205ES256Signer{privateKey: privateKey}
	source := &apnsVoIPProviderTokenSource{
		keyID: "KEY123ABCD", teamID: "TEAM12ABCD", signer: signer,
		now: func() time.Time { return clock },
	}
	authorization, err := source.Authorization(context.Background())
	if err != nil {
		t.Fatalf("first provider token: %v", err)
	}
	parts := strings.Split(strings.TrimPrefix(authorization, "bearer "), ".")
	if len(parts) != 3 {
		t.Fatalf("provider token segments = %d", len(parts))
	}
	headerRaw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		t.Fatalf("decode JWT header: %v", err)
	}
	claimsRaw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatalf("decode JWT claims: %v", err)
	}
	var header map[string]any
	var claims map[string]any
	if json.Unmarshal(headerRaw, &header) != nil || header["alg"] != "ES256" || header["kid"] != "KEY123ABCD" {
		t.Fatalf("JWT header = %s", headerRaw)
	}
	if json.Unmarshal(claimsRaw, &claims) != nil || claims["iss"] != "TEAM12ABCD" ||
		claims["iat"] != float64(issuedAt.Unix()) {
		t.Fatalf("JWT claims = %s", claimsRaw)
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(signature) != 64 {
		t.Fatalf("raw ES256 signature = (%d bytes, %v)", len(signature), err)
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if !ecdsa.Verify(
		&privateKey.PublicKey, digest[:], new(big.Int).SetBytes(signature[:32]), new(big.Int).SetBytes(signature[32:]),
	) {
		t.Fatal("provider token ES256 signature did not verify")
	}

	clock = issuedAt.Add(49 * time.Minute)
	cached, err := source.Authorization(context.Background())
	if err != nil || cached != authorization || signer.calls != 1 {
		t.Fatalf("49-minute cached token = (%q == original %v, calls %d, %v)", cached, cached == authorization, signer.calls, err)
	}
	clock = issuedAt.Add(apnsVoIPTokenRefreshAge)
	refreshed, err := source.Authorization(context.Background())
	if err != nil || refreshed == authorization || signer.calls != 2 {
		t.Fatalf("50-minute token refresh = (changed %v, calls %d, %v)", refreshed != authorization, signer.calls, err)
	}

	expiredSigner := &vc205ES256Signer{privateKey: privateKey}
	expiredClock := issuedAt
	expiredSource := &apnsVoIPProviderTokenSource{
		keyID: "KEY123ABCD", teamID: "TEAM12ABCD", signer: expiredSigner,
		now: func() time.Time { return expiredClock },
	}
	expiredToken, err := expiredSource.Authorization(context.Background())
	if err != nil {
		t.Fatalf("expired-token fixture: %v", err)
	}
	expiredClock = issuedAt.Add(apnsVoIPTokenMinRefreshAge - time.Second)
	if expiredSource.HandleExpiredProviderToken(expiredToken) {
		t.Fatal("ExpiredProviderToken forced regeneration before Apple's 20-minute minimum")
	}
	expiredClock = issuedAt.Add(apnsVoIPTokenMinRefreshAge)
	if !expiredSource.HandleExpiredProviderToken(expiredToken) {
		t.Fatal("ExpiredProviderToken did not invalidate the 20-minute-old cached token")
	}
	if next, err := expiredSource.Authorization(context.Background()); err != nil ||
		next == expiredToken || expiredSigner.calls != 2 {
		t.Fatalf("safe expired-token refresh = (changed %v, calls %d, %v)", next != expiredToken, expiredSigner.calls, err)
	}

	failingSigner := &vc205ES256Signer{privateKey: privateKey}
	failureClock := issuedAt
	failureSource := &apnsVoIPProviderTokenSource{
		keyID: "KEY123ABCD", teamID: "TEAM12ABCD", signer: failingSigner,
		now: func() time.Time { return failureClock },
	}
	lastGood, err := failureSource.Authorization(context.Background())
	if err != nil {
		t.Fatalf("last-good token fixture: %v", err)
	}
	failingSigner.err = errors.New("private-signer-canary")
	failureClock = issuedAt.Add(apnsVoIPTokenRefreshAge)
	if got, err := failureSource.Authorization(context.Background()); err != nil || got != lastGood {
		t.Fatalf("valid cached token was not retained after refresh failure: (%v, %v)", got == lastGood, err)
	}
	failureClock = issuedAt.Add(apnsVoIPTokenMaxAge)
	if _, err := failureSource.Authorization(context.Background()); !errors.Is(err, ErrCallBackendUnavailable) ||
		strings.Contains(err.Error(), "private-signer-canary") {
		t.Fatalf("expired signing failure was not redacted: %v", err)
	}
}

func TestVC205APNSVoIPProviderTokenClockRollbackFailsClosedAndEvicts(t *testing.T) {
	issuedAt := time.Unix(1_802_000_275, 0).UTC()
	privateKey := vc205PrivateKey(t)

	t.Run("authorization cache rollback", func(t *testing.T) {
		clock := issuedAt
		signer := &vc205ES256Signer{privateKey: privateKey}
		source := &apnsVoIPProviderTokenSource{
			keyID: "KEY123ABCD", teamID: "TEAM12ABCD", signer: signer,
			now: func() time.Time { return clock },
		}
		futureToken, err := source.Authorization(context.Background())
		if err != nil {
			t.Fatalf("create future-token fixture: %v", err)
		}
		clock = issuedAt.Add(-time.Second)
		if got, err := source.Authorization(context.Background()); got != "" ||
			!errors.Is(err, ErrCallBackendUnavailable) || signer.calls != 1 {
			t.Fatalf("rollback authorization = (%q, %v, %d signer calls)", got, err, signer.calls)
		}
		notBefore := issuedAt.Add(apnsVoIPTokenMinRefreshAge)
		if source.cachedAuthorization != "" || !source.issuedAt.IsZero() ||
			!source.refreshNotBefore.Equal(notBefore) {
			t.Fatalf("rollback cache state = (cached %v, issued %v, not-before %v)",
				source.cachedAuthorization != "", !source.issuedAt.IsZero(), source.refreshNotBefore)
		}
		if source.HandleExpiredProviderToken(futureToken) {
			t.Fatal("stale future-issued token triggered an immediate refresh")
		}
		clock = notBefore.Add(-time.Second)
		if got, err := source.Authorization(context.Background()); got != "" ||
			!errors.Is(err, ErrCallBackendUnavailable) || signer.calls != 1 {
			t.Fatalf("rollback cooldown authorization = (%q, %v, %d calls)", got, err, signer.calls)
		}
		clock = notBefore
		refreshed, err := source.Authorization(context.Background())
		if err != nil || refreshed == "" || refreshed == futureToken || signer.calls != 2 {
			t.Fatalf("post-cooldown authorization = (changed %v, calls %d, %v)", refreshed != futureToken, signer.calls, err)
		}
	})

	t.Run("expired response observes rollback", func(t *testing.T) {
		clock := issuedAt
		signer := &vc205ES256Signer{privateKey: privateKey}
		source := &apnsVoIPProviderTokenSource{
			keyID: "KEY123ABCD", teamID: "TEAM12ABCD", signer: signer,
			now: func() time.Time { return clock },
		}
		futureToken, err := source.Authorization(context.Background())
		if err != nil {
			t.Fatalf("create expired-response fixture: %v", err)
		}
		clock = issuedAt.Add(-time.Minute)
		if source.HandleExpiredProviderToken(futureToken) {
			t.Fatal("rollback ExpiredProviderToken permitted a sub-20-minute refresh")
		}
		notBefore := issuedAt.Add(apnsVoIPTokenMinRefreshAge)
		if source.cachedAuthorization != "" || !source.issuedAt.IsZero() ||
			!source.refreshNotBefore.Equal(notBefore) {
			t.Fatalf("rollback expired-response state = (cached %v, issued %v, not-before %v)",
				source.cachedAuthorization != "", !source.issuedAt.IsZero(), source.refreshNotBefore)
		}
		if got, err := source.Authorization(context.Background()); got != "" ||
			!errors.Is(err, ErrCallBackendUnavailable) || signer.calls != 1 {
			t.Fatalf("rollback expired-response authorization = (%q, %v, %d calls)", got, err, signer.calls)
		}
	})
}

func TestVC205APNSVoIPRequestUsesExactHeadersAndOpaqueBoundedPayload(t *testing.T) {
	now := time.Unix(1_802_000_300, 0).UTC()
	payload := vc205Payload(now)
	type capturedRequest struct {
		path   string
		header http.Header
		body   []byte
	}
	captured := make(chan capturedRequest, 1)
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		body, _ := io.ReadAll(request.Body)
		captured <- capturedRequest{path: request.URL.EscapedPath(), header: request.Header.Clone(), body: body}
		writer.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	provider := &httpAPNSVoIPProvider{
		client: server.Client(), endpoint: server.URL,
		authorization: &vc205AuthorizationSource{authorization: "bearer private-auth-canary"},
		now:           func() time.Time { return now },
	}
	dispatcher := vc205Dispatcher(provider, now)
	if err := dispatcher.DispatchCallWake(context.Background(), vc205Route("device-token-canary", 7, 11), payload); err != nil {
		t.Fatalf("DispatchCallWake: %v", err)
	}
	request := <-captured
	if request.path != "/3/device/device-token-canary" {
		t.Fatalf("APNs path = %q", request.path)
	}
	checks := map[string]string{
		"Authorization":   "bearer private-auth-canary",
		"Apns-Topic":      callTestVoIPTopic,
		"Apns-Push-Type":  "voip",
		"Apns-Priority":   "10",
		"Apns-Expiration": strconv.FormatInt(time.UnixMilli(payload.ExpiresAtMs).Unix(), 10),
		"Content-Type":    "application/json",
	}
	for name, want := range checks {
		if got := request.header.Get(name); got != want {
			t.Fatalf("%s = %q, want %q", name, got, want)
		}
	}
	wantBody := `{"aps":{"content-available":1},"v":"1","w":"call","c":"` +
		callTestHandleA + `","h":"` + callTestWake + `","e":"` + strconv.FormatInt(payload.ExpiresAtMs, 10) + `"}`
	if string(request.body) != wantBody {
		t.Fatalf("APNs payload = %s, want %s", request.body, wantBody)
	}
	if len(request.body) > apnsVoIPPayloadMaxBytes {
		t.Fatalf("APNs payload length = %d, max %d", len(request.body), apnsVoIPPayloadMaxBytes)
	}
	for _, forbidden := range []string{"peerId", "sender", "contactName", "conversation", "sdp", "ice", "turn"} {
		if strings.Contains(strings.ToLower(string(request.body)), strings.ToLower(forbidden)) {
			t.Fatalf("APNs payload exposed forbidden field %q: %s", forbidden, request.body)
		}
	}
	if got := (apnsVoIPConfig{Environment: "sandbox"}).endpoint(); got != apnsVoIPSandboxEndpoint {
		t.Fatalf("sandbox endpoint = %q", got)
	}
	if got := (apnsVoIPConfig{Environment: "production"}).endpoint(); got != apnsVoIPProductionEndpoint {
		t.Fatalf("production endpoint = %q", got)
	}
	productionProvider := newHTTPAPNSVoIPProvider(apnsVoIPConfig{
		Environment: "production", Topic: callTestVoIPTopic, KeyID: "KEY123ABCD",
		TeamID: "TEAM12ABCD", privateKey: vc205PrivateKey(t),
	})
	transport, ok := productionProvider.client.Transport.(*http.Transport)
	if !ok || !transport.ForceAttemptHTTP2 {
		t.Fatal("direct APNs provider transport is not HTTP/2 compatible")
	}
}

func TestVC205APNSVoIPPayloadRejectsStaleMalformedAndOversizedValues(t *testing.T) {
	now := time.Unix(1_802_000_400, 0).UTC()
	valid := vc205Payload(now)
	if raw, err := buildAPNSVoIPPayload(valid, now); err != nil || len(raw) == 0 || len(raw) > apnsVoIPPayloadMaxBytes {
		t.Fatalf("valid payload = (%q, %v)", raw, err)
	}
	tests := map[string]CallWakePayload{
		"missing call handle": {WakeHandle: valid.WakeHandle, ExpiresAtMs: valid.ExpiresAtMs},
		"malformed call UUID": {CallHandle: "not-a-uuid", WakeHandle: valid.WakeHandle, ExpiresAtMs: valid.ExpiresAtMs},
		"missing wake handle": {CallHandle: valid.CallHandle, ExpiresAtMs: valid.ExpiresAtMs},
		"stale expiry":        {CallHandle: valid.CallHandle, WakeHandle: valid.WakeHandle, ExpiresAtMs: now.UnixMilli()},
		"unbounded expiry":    {CallHandle: valid.CallHandle, WakeHandle: valid.WakeHandle, ExpiresAtMs: now.Add(CallMaxPreconnectTTL + time.Millisecond).UnixMilli()},
	}
	for name, payload := range tests {
		t.Run(name, func(t *testing.T) {
			if raw, err := buildAPNSVoIPPayload(payload, now); err == nil || raw != nil {
				t.Fatalf("payload accepted = %q", raw)
			}
		})
	}
}

func TestVC205APNSVoIPRetryTimingHonorsInviteExpiryAndAppleGuidance(t *testing.T) {
	now := time.Unix(1_802_000_500, 0).UTC()
	parsedTests := map[string]struct {
		value string
		want  time.Duration
		valid bool
	}{
		"delta seconds": {value: "7", want: 7 * time.Second, valid: true},
		"HTTP date":     {value: now.Add(12 * time.Second).Format(http.TimeFormat), want: 12 * time.Second, valid: true},
		"absent":        {value: ""},
		"zero":          {value: "0"},
		"past date":     {value: now.Add(-time.Second).Format(http.TimeFormat)},
		"malformed":     {value: "soon"},
		"overflow":      {value: "18446744073709551615"},
	}
	for name, test := range parsedTests {
		t.Run(name, func(t *testing.T) {
			got, valid := parseAPNSVoIPRetryAfter(test.value, now)
			if got != test.want || valid != test.valid {
				t.Fatalf("Retry-After %q = (%v, %v), want (%v, %v)", test.value, got, valid, test.want, test.valid)
			}
		})
	}

	for name, first := range map[string]vc205ProviderStep{
		"network": {err: errAPNSVoIPNetwork},
		"rate limited with bounded delay": {response: apnsVoIPProviderResponse{
			StatusCode: http.StatusTooManyRequests, RetryAfter: time.Nanosecond, RetryAfterValid: true,
		}},
		"safely refreshed provider token": {response: apnsVoIPProviderResponse{
			StatusCode: http.StatusForbidden, Reason: "ExpiredProviderToken", AuthTokenRefresh: true,
		}},
	} {
		t.Run(name, func(t *testing.T) {
			provider := &vc205Provider{steps: []vc205ProviderStep{
				first, {response: apnsVoIPProviderResponse{StatusCode: http.StatusOK}},
			}}
			dispatcher := vc205Dispatcher(provider, now)
			dispatcher.retryDelays = []time.Duration{0}
			if err := dispatcher.DispatchCallWake(context.Background(), vc205Route("token", 1, 1), vc205Payload(now)); err != nil {
				t.Fatalf("bounded retry dispatch: %v", err)
			}
			if len(provider.requests) != 2 {
				t.Fatalf("provider attempts = %d, want 2", len(provider.requests))
			}
		})
	}
	repeatedRateLimit := apnsVoIPProviderResponse{
		StatusCode: http.StatusTooManyRequests, RetryAfter: time.Nanosecond, RetryAfterValid: true,
	}
	rateLimitedProvider := &vc205Provider{steps: []vc205ProviderStep{
		{response: repeatedRateLimit}, {response: repeatedRateLimit}, {response: repeatedRateLimit},
	}}
	rateLimitedDispatcher := vc205Dispatcher(rateLimitedProvider, now)
	if err := rateLimitedDispatcher.DispatchCallWake(
		context.Background(), vc205Route("token", 1, 1), vc205Payload(now),
	); !errors.Is(err, ErrCallBackendUnavailable) ||
		len(rateLimitedProvider.requests) != 1+apnsVoIPRateLimitRetryMax ||
		apnsVoIPRateLimitRetryMax != 1 {
		t.Fatalf("repeated 429 dispatch = (%v, %d attempts, retry max %d)",
			err, len(rateLimitedProvider.requests), apnsVoIPRateLimitRetryMax)
	}

	for name, response := range map[string]apnsVoIPProviderResponse{
		"5xx waits fifteen minutes and is dropped": {
			StatusCode: http.StatusServiceUnavailable,
		},
		"429 without Retry-After": {StatusCode: http.StatusTooManyRequests},
		"429 with invalid Retry-After": {
			StatusCode: http.StatusTooManyRequests, RetryAfter: 0, RetryAfterValid: false,
		},
		"429 outside invite expiry": {
			StatusCode: http.StatusTooManyRequests, RetryAfter: CallMaxPreconnectTTL, RetryAfterValid: true,
		},
		"provider-token update limit is auth failure": {
			StatusCode: http.StatusForbidden, Reason: "TooManyProviderTokenUpdates",
			RetryAfter: time.Nanosecond, RetryAfterValid: true,
		},
		"too-young expired provider token": {
			StatusCode: http.StatusForbidden, Reason: "ExpiredProviderToken", AuthTokenRefresh: false,
		},
	} {
		t.Run(name, func(t *testing.T) {
			provider := &vc205Provider{steps: []vc205ProviderStep{
				{response: response}, {response: apnsVoIPProviderResponse{StatusCode: http.StatusOK}},
			}}
			dispatcher := vc205Dispatcher(provider, now)
			dispatcher.retryDelays = []time.Duration{0, 0}
			if err := dispatcher.DispatchCallWake(context.Background(), vc205Route("token", 1, 1), vc205Payload(now)); !errors.Is(err, ErrCallBackendUnavailable) || len(provider.requests) != 1 {
				t.Fatalf("nonretryable result = (%v, %d attempts)", err, len(provider.requests))
			}
		})
	}
	if apnsVoIPServerRetryDelay != 15*time.Minute || apnsVoIPServerRetryDelay <= CallMaxPreconnectTTL {
		t.Fatalf("APNs 5xx retry guidance = %v", apnsVoIPServerRetryDelay)
	}

	for name, step := range map[string]vc205ProviderStep{
		"bad device token": {response: apnsVoIPProviderResponse{StatusCode: http.StatusBadRequest, Reason: "BadDeviceToken"}},
		"wrong topic":      {response: apnsVoIPProviderResponse{StatusCode: http.StatusBadRequest, Reason: "DeviceTokenNotForTopic"}},
		"unregistered":     {response: apnsVoIPProviderResponse{StatusCode: http.StatusGone, Reason: "Unregistered"}},
	} {
		t.Run(name, func(t *testing.T) {
			provider := &vc205Provider{steps: []vc205ProviderStep{step}}
			dispatcher := vc205Dispatcher(provider, now)
			dispatcher.retryDelays = []time.Duration{0, 0}
			err := dispatcher.DispatchCallWake(context.Background(), vc205Route("token", 1, 1), vc205Payload(now))
			if !errors.Is(err, ErrCallTokenInvalid) || len(provider.requests) != 1 {
				t.Fatalf("invalid-token dispatch = (%v, %d attempts)", err, len(provider.requests))
			}
		})
	}

	provider := &vc205Provider{steps: []vc205ProviderStep{{
		response: apnsVoIPProviderResponse{StatusCode: http.StatusForbidden, Reason: "private-response-canary"},
	}}}
	dispatcher := vc205Dispatcher(provider, now)
	dispatcher.retryDelays = []time.Duration{0, 0}
	err := dispatcher.DispatchCallWake(context.Background(), vc205Route("private-token-canary", 1, 1), vc205Payload(now))
	if !errors.Is(err, ErrCallBackendUnavailable) || strings.Contains(err.Error(), "private") || len(provider.requests) != 1 {
		t.Fatalf("nonretryable provider response leaked/retried = (%v, %d attempts)", err, len(provider.requests))
	}

}

func TestVC205InvalidTokenCleanupUsesExactGenerationAcrossSameTokenRefresh(t *testing.T) {
	now := time.Unix(1_802_000_600, 0).UTC()
	dispatcher := &callTestWakeDispatcher{err: ErrCallTokenInvalid}
	service, _ := callTestService(t, now, dispatcher)
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	if err := service.backend.SetEndpoint(context.Background(), CallEndpointRecord{
		Schema: CallEndpointSchema, Version: CallControlVersion,
		AccountPeerID: recipient, DevicePeerID: recipient,
		Capabilities: []string{"voice_call_v1"}, Platform: "ios",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(), PreferenceEpoch: 2,
		DeviceKeyEpoch: 2, RoutingHandle: callTestHandleB, Signature: []byte("fixture"),
	}, now); err != nil {
		t.Fatalf("set iOS endpoint fixture: %v", err)
	}
	initial := callTestIOSVoIPToken("same-token", now.Add(time.Hour), 1)
	if err := service.SetCallToken(context.Background(), recipient, initial); err != nil {
		t.Fatalf("set initial token: %v", err)
	}
	service.afterWakeDispatchAuthorized = func() {
		refresh := callTestIOSVoIPToken("same-token", now.Add(2*time.Hour), 2)
		if err := service.SetCallToken(context.Background(), recipient, refresh); err != nil {
			t.Fatalf("refresh during provider dispatch: %v", err)
		}
	}
	if _, err := service.Store(context.Background(), sender, CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("encrypted-invite"),
		ExpiresAtMs: now.Add(CallMaxPreconnectTTL).UnixMilli(), WakeHandle: callTestWake,
	}); err != nil {
		t.Fatalf("store with stale invalid response: %v", err)
	}
	current, err := service.GetCallToken(context.Background(), recipient, CallTokenKindIOSVoIP)
	if err != nil || current == nil || current.RefreshEpoch != 2 || current.Generation != 2 {
		t.Fatalf("stale invalid response removed refresh: (%#v, %v)", current, err)
	}
	service.afterWakeDispatchAuthorized = nil
	if _, err := service.Store(context.Background(), sender, CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleB,
		MessageID: callTestMessageB, Envelope: []byte("second-encrypted-invite"),
		ExpiresAtMs: now.Add(CallMaxPreconnectTTL).UnixMilli(), WakeHandle: callTestWake,
	}); err != nil {
		t.Fatalf("store with current invalid response: %v", err)
	}
	current, err = service.GetCallToken(context.Background(), recipient, CallTokenKindIOSVoIP)
	if err != nil || current != nil {
		t.Fatalf("exact invalid response did not clean current token: (%#v, %v)", current, err)
	}
}

func TestVC205APNSVoIPBootstrapFailsClosedAndUsesSeparateKillSwitch(t *testing.T) {
	for _, name := range []string{
		apnsVoIPPushEnabledEnv, apnsVoIPEnvironmentEnv, apnsVoIPTopicEnv,
		apnsVoIPKeyIDEnv, apnsVoIPTeamIDEnv, apnsVoIPPrivateKeyFileEnv,
	} {
		t.Setenv(name, "")
	}
	disabled, err := loadAPNSVoIPConfigFromEnv()
	if err != nil || disabled.Enabled {
		t.Fatalf("default APNs VoIP config = (%#v, %v)", disabled, err)
	}

	t.Setenv(apnsVoIPPushEnabledEnv, "true")
	t.Setenv(apnsVoIPEnvironmentEnv, "sandbox")
	t.Setenv(apnsVoIPTopicEnv, callTestVoIPTopic)
	t.Setenv(apnsVoIPKeyIDEnv, "KEY123ABCD")
	t.Setenv(apnsVoIPTeamIDEnv, "TEAM12ABCD")
	t.Setenv(apnsVoIPPrivateKeyFileEnv, "/missing/private-auth-marker.p8")
	t.Setenv("APNS_VOIP_AUTHORIZATION", "bearer static-private-auth-marker")
	if _, err := loadAPNSVoIPConfigFromEnv(); err == nil || strings.Contains(err.Error(), "private-auth-marker") {
		t.Fatalf("invalid credentials did not fail redacted: %v", err)
	}
	t.Setenv(apnsVoIPPrivateKeyFileEnv, vc205PrivateKeyFile(t))
	for name, test := range map[string]struct {
		environmentName string
		value           string
	}{
		"short key id":       {environmentName: apnsVoIPKeyIDEnv, value: "ABC123456"},
		"key id punctuation": {environmentName: apnsVoIPKeyIDEnv, value: "ABC12345-9"},
		"long team id":       {environmentName: apnsVoIPTeamIDEnv, value: "ABC12345678"},
		"lowercase team id":  {environmentName: apnsVoIPTeamIDEnv, value: "ABC12345a9"},
	} {
		t.Run(name, func(t *testing.T) {
			t.Setenv(test.environmentName, test.value)
			if _, err := loadAPNSVoIPConfigFromEnv(); !errors.Is(err, errAPNSVoIPInvalidConfig) {
				t.Fatalf("invalid provider identifier error = %v", err)
			}
		})
	}
	config, err := loadAPNSVoIPConfigFromEnv()
	if err != nil || !config.Enabled || config.endpoint() != apnsVoIPSandboxEndpoint {
		t.Fatalf("enabled APNs VoIP config = (%#v, %v)", config, err)
	}
	authorization, err := newAPNSVoIPProviderTokenSource(config).Authorization(context.Background())
	if err != nil || strings.Contains(authorization, "static-private-auth-marker") {
		t.Fatalf("production config used deprecated static authorization: %v", err)
	}
	if _, err := newControlPlaneStores(context.Background(), backendConfig{
		Kind: backendKindMemory,
	}, DefaultServerLimits(), "/missing-firebase.json"); err == nil ||
		!strings.Contains(err.Error(), "requires RELAY_BACKEND=redis") {
		t.Fatalf("enabled APNs VoIP with memory backend error = %v", err)
	}

	server := miniredis.RunT(t)
	stores, err := newControlPlaneStores(context.Background(), backendConfig{
		Kind: backendKindRedis, RedisURL: "redis://" + server.Addr(), RedisPrefix: "vc205-bootstrap:",
	}, DefaultServerLimits(), "/missing-firebase.json")
	if err != nil {
		t.Fatalf("enabled Redis bootstrap: %v", err)
	}
	defer func() { _ = stores.Close() }()
	mux, ok := stores.CallControl.dispatcher.(platformCallWakeDispatcher)
	if !ok || mux.ios == nil || mux.android == nil || !stores.APNSVoIPPushEnabled ||
		stores.APNSVoIPEnvironment != "sandbox" {
		t.Fatalf("enabled dispatcher mux = (%T, %#v)", stores.CallControl.dispatcher, stores)
	}

	t.Setenv(apnsVoIPPushEnabledEnv, "false")
	disabledStores, err := newControlPlaneStores(context.Background(), backendConfig{
		Kind: backendKindRedis, RedisURL: "redis://" + server.Addr(), RedisPrefix: "vc205-disabled:",
	}, DefaultServerLimits(), "/missing-firebase.json")
	if err != nil {
		t.Fatalf("disabled Redis bootstrap: %v", err)
	}
	defer func() { _ = disabledStores.Close() }()
	disabledMux, ok := disabledStores.CallControl.dispatcher.(platformCallWakeDispatcher)
	if !ok || disabledMux.ios != nil || disabledMux.android == nil || disabledStores.APNSVoIPPushEnabled {
		t.Fatalf("disabled dispatcher mux = (%T, %#v)", disabledStores.CallControl.dispatcher, disabledStores)
	}
	androidRecorder := &callTestWakeDispatcher{}
	noFallback := platformCallWakeDispatcher{android: androidRecorder}
	if err := noFallback.DispatchCallWake(
		context.Background(), vc205Route("pushkit-token", 1, 1), vc205Payload(time.Now()),
	); !errors.Is(err, ErrCallBackendUnavailable) || len(androidRecorder.routes) != 0 {
		t.Fatalf("disabled iOS route fell back to Android/ordinary push: (%v, %d)", err, len(androidRecorder.routes))
	}
}

func vc206Route(environment string) CallWakeRoute {
	route := vc205Route("token", 1, 1)
	route.Environment = environment
	return route
}

func vc206Dispatcher(sandbox, production apnsVoIPProvider, now time.Time) *apnsVoIPCallWakeDispatcher {
	return &apnsVoIPCallWakeDispatcher{
		providers:         map[string]apnsVoIPProvider{"sandbox": sandbox, "production": production},
		topic:             callTestVoIPTopic,
		capabilityVersion: callIOSVoIPCapabilityVersion,
		retryDelays:       []time.Duration{0, 0},
		now:               func() time.Time { return now },
	}
}

// A device-labelled environment picks Apple's door; a token Apple rejects at
// that door gets exactly one attempt at the other door and is only revoked
// when both doors reject it.
func TestVC206APNSVoIPRoutesByTokenEnvironmentWithCrossEnvironmentFallback(t *testing.T) {
	now := time.Unix(1_802_000_700, 0).UTC()
	ok := vc205ProviderStep{response: apnsVoIPProviderResponse{StatusCode: http.StatusOK}}
	badToken := vc205ProviderStep{response: apnsVoIPProviderResponse{StatusCode: http.StatusBadRequest, Reason: "BadDeviceToken"}}
	unregistered := vc205ProviderStep{response: apnsVoIPProviderResponse{StatusCode: http.StatusGone, Reason: "Unregistered"}}
	serverError := vc205ProviderStep{response: apnsVoIPProviderResponse{StatusCode: http.StatusServiceUnavailable}}
	network := vc205ProviderStep{err: errAPNSVoIPNetwork}

	for name, test := range map[string]struct {
		environment    string
		sandbox        []vc205ProviderStep
		production     []vc205ProviderStep
		wantErr        error
		wantSandbox    int
		wantProduction int
	}{
		"sandbox label goes to sandbox only": {
			environment: "sandbox", sandbox: []vc205ProviderStep{ok}, production: []vc205ProviderStep{ok},
			wantSandbox: 1,
		},
		"production label goes to production only": {
			environment: "production", sandbox: []vc205ProviderStep{ok}, production: []vc205ProviderStep{ok},
			wantProduction: 1,
		},
		"production-labelled sandbox token falls back once and is kept": {
			environment: "production", sandbox: []vc205ProviderStep{ok}, production: []vc205ProviderStep{badToken},
			wantSandbox: 1, wantProduction: 1,
		},
		"sandbox-labelled production token falls back once and is kept": {
			environment: "sandbox", sandbox: []vc205ProviderStep{unregistered}, production: []vc205ProviderStep{ok},
			wantSandbox: 1, wantProduction: 1,
		},
		"rejected at both doors is invalid": {
			environment: "production", sandbox: []vc205ProviderStep{badToken}, production: []vc205ProviderStep{badToken},
			wantErr: ErrCallTokenInvalid, wantSandbox: 1, wantProduction: 1,
		},
		"inconclusive fallback keeps the token": {
			environment: "production", sandbox: []vc205ProviderStep{network, network, network}, production: []vc205ProviderStep{badToken},
			wantErr: ErrCallBackendUnavailable, wantSandbox: 3, wantProduction: 1,
		},
		"non-token failure never crosses environments": {
			environment: "production", sandbox: []vc205ProviderStep{ok}, production: []vc205ProviderStep{serverError},
			wantErr: ErrCallBackendUnavailable, wantProduction: 1,
		},
		"unknown label is rejected before any send": {
			environment: "development", sandbox: []vc205ProviderStep{ok}, production: []vc205ProviderStep{ok},
			wantErr: ErrCallBackendUnavailable,
		},
	} {
		t.Run(name, func(t *testing.T) {
			sandbox := &vc205Provider{steps: test.sandbox}
			production := &vc205Provider{steps: test.production}
			dispatcher := vc206Dispatcher(sandbox, production, now)
			err := dispatcher.DispatchCallWake(context.Background(), vc206Route(test.environment), vc205Payload(now))
			if test.wantErr == nil && err != nil {
				t.Fatalf("dispatch: %v", err)
			}
			if test.wantErr != nil && !errors.Is(err, test.wantErr) {
				t.Fatalf("dispatch error = %v, want %v", err, test.wantErr)
			}
			if len(sandbox.requests) != test.wantSandbox || len(production.requests) != test.wantProduction {
				t.Fatalf("attempts = (sandbox %d, production %d), want (%d, %d)",
					len(sandbox.requests), len(production.requests), test.wantSandbox, test.wantProduction)
			}
			for _, request := range append(append([]apnsVoIPProviderRequest(nil), sandbox.requests...), production.requests...) {
				if request.Token != "token" || request.Topic != callTestVoIPTopic {
					t.Fatalf("fallback changed the request: %#v", request)
				}
			}
		})
	}

	// Without a provider for the other environment there is nothing to fall
	// back to: the single-environment verdict stands.
	single := &vc205Provider{steps: []vc205ProviderStep{badToken}}
	if err := vc205Dispatcher(single, now).DispatchCallWake(
		context.Background(), vc206Route("sandbox"), vc205Payload(now),
	); !errors.Is(err, ErrCallTokenInvalid) || len(single.requests) != 1 {
		t.Fatalf("single-environment invalid token = (%v, %d attempts)", err, len(single.requests))
	}

	// The production constructor wires both doors to one shared provider-token
	// source so the fallback never needs a second key or JWT cache.
	t.Setenv(apnsVoIPPushEnabledEnv, "true")
	t.Setenv(apnsVoIPEnvironmentEnv, "production")
	t.Setenv(apnsVoIPTopicEnv, callTestVoIPTopic)
	t.Setenv(apnsVoIPKeyIDEnv, "KEY123ABCD")
	t.Setenv(apnsVoIPTeamIDEnv, "TEAM12ABCD")
	t.Setenv(apnsVoIPPrivateKeyFileEnv, vc205PrivateKeyFile(t))
	config, err := loadAPNSVoIPConfigFromEnv()
	if err != nil {
		t.Fatalf("config: %v", err)
	}
	real := newAPNSVoIPCallWakeDispatcher(config)
	sandboxHTTP, sandboxOK := real.providers["sandbox"].(*httpAPNSVoIPProvider)
	productionHTTP, productionOK := real.providers["production"].(*httpAPNSVoIPProvider)
	if !sandboxOK || !productionOK || sandboxHTTP.endpoint != apnsVoIPSandboxEndpoint ||
		productionHTTP.endpoint != apnsVoIPProductionEndpoint ||
		sandboxHTTP.authorization == nil || sandboxHTTP.authorization != productionHTTP.authorization {
		t.Fatalf("production dispatcher providers = %#v / %#v", sandboxHTTP, productionHTTP)
	}
	if apnsVoIPOtherEnvironment("sandbox") != "production" || apnsVoIPOtherEnvironment("production") != "sandbox" {
		t.Fatalf("other-environment mapping is not an involution")
	}
}
