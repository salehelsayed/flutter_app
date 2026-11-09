package main

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type thoughtNotificationPushCase struct {
	name     string
	envelope string
}

var thoughtPreferenceEventSequence uint64

// Preference fixtures retain their original authored timestamps while the
// provider clock is fixed inside their lifetime. Custody still uses real time.
func newThoughtNotificationPushService(backend PushTokenBackend) *PushService {
	push := NewPushServiceWithBackend(backend)
	push.now = postCreatePushFixtureNow
	return push
}

func thoughtNotificationPushCases() []thoughtNotificationPushCase {
	return []thoughtNotificationPushCase{
		{name: "encrypted", envelope: postCreatePushFixtureWithPostID},
		{
			name: "oversized_photo_with_compact_ciphertext",
			envelope: thoughtPhotoPushEnvelope(6000,
				thoughtPhotoCompactEncryptedJSON(thoughtPhotoCompactCiphertext)),
		},
		{name: "fallback_without_post_id", envelope: postCreatePushFixture},
		{
			name:     "fallback_without_ciphertext",
			envelope: `{"type":"post_create","version":"2","event_id":"thought-evt-1","post_id":"post-1"}`,
		},
		{
			name: "fallback_oversized_ciphertext",
			envelope: `{"type":"post_create","version":"2","event_id":"thought-evt-1","post_id":"post-1","encrypted":{"kem":"` +
				strings.Repeat("k", 1500) + `","ciphertext":"` + strings.Repeat("c", 5000) + `","nonce":"n"}}`,
		},
	}
}

// A fresh Redis backend uses only persisted records. The memory case similarly
// creates a fresh PushService over the existing store rather than a cached pref.
func thoughtNotificationBackend(t *testing.T, kind string) (PushTokenBackend, func() PushTokenBackend) {
	t.Helper()
	if kind == "memory" {
		backend := newMemoryPushTokenStore()
		return backend, func() PushTokenBackend { return backend }
	}
	config := plan367Config("key-a", "test", map[string][]byte{"key-a": plan367Key('a')})
	_, backend := plan367RedisBackend(t, "thought-notifications:", config)
	if kind == "redis_encrypted" {
		plan367Migrate(t, backend)
	}
	return backend, func() PushTokenBackend {
		reopened := newRedisPushTokenBackend(backend.client, backend.prefix)
		reopened.vaultConfig = config
		return reopened
	}
}

func registerThoughtNotificationPreference(
	t *testing.T,
	env *inboxStreamEnv,
	platform, token string,
	enabled *bool,
	capabilities ...string,
) {
	t.Helper()
	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open registration stream: %v", err)
	}
	defer stream.Close()
	request := map[string]any{
		"action": "register_token", "token": token, "platform": platform,
		"capabilities": capabilities,
		// Registration must still belong to the authenticated stream peer.
		"to": env.recipient.ID().String(), "from": env.intruder.ID().String(),
	}
	if enabled != nil {
		request["thought_notifications_enabled"] = *enabled
	}
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatalf("marshal registration: %v", err)
	}
	if err := writeFrame(stream, raw); err != nil {
		t.Fatalf("write registration: %v", err)
	}
	if response := recvInboxResp(t, stream); response.Status != "OK" || response.Error != "" {
		t.Fatalf("registration response = %#v, want persisted OK", response)
	}
}

func assertThoughtNotificationProviderCalls(
	t *testing.T,
	push *PushService,
	recorder *recordingPushSender,
	recipient, envelope string,
	want int,
) {
	t.Helper()
	// Each preference observation represents a new notification event. Exact
	// event retries have their own provider-admission tests and keep their ID.
	if extractChatPushMetadata(envelope).RouteType == "post_create" {
		envelope = thoughtDeliveryEnvelope(t, envelope, map[string]interface{}{
			"event_id": fmt.Sprintf("thought-preference-%d", atomic.AddUint64(&thoughtPreferenceEventSequence, 1)),
		})
	}
	before := recorder.SendCallCount()
	// SendNotification completes its provider attempt synchronously, so zero
	// calls here proves suppression without a timing-based negative assertion.
	push.SendNotification(context.Background(), recipient, "peer-sender", envelope)
	if got := recorder.SendCallCount() - before; got != want {
		t.Errorf("provider calls = %d, want %d", got, want)
	}
}

func TestThoughtNotificationsRegistration_ControlsOnlyPostCreate(t *testing.T) {
	for _, kind := range []string{"memory", "redis_legacy", "redis_encrypted"} {
		for _, platform := range []string{"android", "ios"} {
			t.Run(kind+"/"+platform, func(t *testing.T) {
				backend, reopen := thoughtNotificationBackend(t, kind)
				push := newThoughtNotificationPushService(backend)
				env := setupInboxStreamEnv(t, NewInboxStore(push), NewGroupInboxStore(500, 0))
				recipient := env.sender.ID().String()
				otherPeer := env.recipient.ID().String()
				if err := backend.RegisterToken(otherPeer, "other-token", platform); err != nil {
					t.Fatalf("register other peer: %v", err)
				}
				recorder := newRecordingPushSender()
				push.sender = recorder.Send
				registerThoughtNotificationPreference(t, env, platform, "original-token", nil, directReactionCapability)
				for _, fixture := range thoughtNotificationPushCases() {
					t.Run("old_registration_defaults_on/"+fixture.name, func(t *testing.T) {
						assertThoughtNotificationProviderCalls(t, push, recorder, recipient, fixture.envelope, 1)
					})
				}

				off := false
				registerThoughtNotificationPreference(t, env, platform, "original-token", &off, directReactionCapability)
				entry := lookupTokenForTest(backend, recipient)
				if entry == nil || entry.Token != "original-token" || entry.Platform != platform ||
					!reflect.DeepEqual(entry.Capabilities, []string{directReactionCapability}) {
					t.Fatalf("authenticated registration = %#v, want unchanged token/platform/capabilities", entry)
				}
				if other := lookupTokenForTest(backend, otherPeer); other == nil || other.Token != "other-token" {
					t.Fatalf("registration changed another peer's token: %#v", other)
				}

				push = newThoughtNotificationPushService(reopen())
				push.sender = recorder.Send
				for _, fixture := range thoughtNotificationPushCases() {
					t.Run("off_after_restart/"+fixture.name, func(t *testing.T) {
						assertThoughtNotificationProviderCalls(t, push, recorder, recipient, fixture.envelope, 0)
					})
				}
				t.Run("off_preserves_chat", func(t *testing.T) {
					assertThoughtNotificationProviderCalls(t, push, recorder, recipient,
						`{"type":"chat_message","version":"2","msgId":"chat-while-thoughts-off","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`, 1)
				})
				t.Run("off_preserves_contact_request", func(t *testing.T) {
					assertThoughtNotificationProviderCalls(t, push, recorder, recipient,
						`{"type":"contact_request","version":"2","msgId":"request-while-thoughts-off","encrypted":{"ephemeralPublicKey":"e","ciphertext":"c","nonce":"n"}}`, 1)
				})
				t.Run("off_is_scoped_to_authenticated_peer", func(t *testing.T) {
					assertThoughtNotificationProviderCalls(t, push, recorder, otherPeer, postCreatePushFixtureWithPostID, 1)
				})

				registerThoughtNotificationPreference(t, env, platform, "refreshed-token", &off, directReactionCapability)
				push = newThoughtNotificationPushService(reopen())
				push.sender = recorder.Send
				t.Run("off_survives_token_refresh", func(t *testing.T) {
					assertThoughtNotificationProviderCalls(t, push, recorder, recipient, postCreatePushFixtureWithPostID, 0)
				})
				on := true
				registerThoughtNotificationPreference(t, env, platform, "refreshed-token", &on, directReactionCapability)
				push = newThoughtNotificationPushService(reopen())
				push.sender = recorder.Send
				for _, fixture := range thoughtNotificationPushCases() {
					t.Run("explicit_on_restores/"+fixture.name, func(t *testing.T) {
						assertThoughtNotificationProviderCalls(t, push, recorder, recipient, fixture.envelope, 1)
						if message := recorder.LastMessage(); message == nil || message.Token != "refreshed-token" {
							t.Fatalf("restored push = %#v, want refreshed provider token", message)
						}
					})
				}
				registerThoughtNotificationPreference(t, env, platform, "refreshed-token", &off, directReactionCapability)
				registerThoughtNotificationPreference(t, env, platform, "refreshed-token", nil, directReactionCapability)
				push = newThoughtNotificationPushService(reopen())
				push.sender = recorder.Send
				t.Run("omitted_field_restores_default_on", func(t *testing.T) {
					assertThoughtNotificationProviderCalls(t, push, recorder, recipient, postCreatePushFixtureWithPostID, 1)
				})
			})
		}
	}
}

func TestThoughtNotificationsLegacyRecords_DefaultOn(t *testing.T) {
	for _, encrypted := range []bool{false, true} {
		for _, platform := range []string{"android", "ios"} {
			name := "legacy/" + platform
			if encrypted {
				name = "migrated_legacy/" + platform
			}
			t.Run(name, func(t *testing.T) {
				config := plan367Config("key-a", "test", map[string][]byte{"key-a": plan367Key('a')})
				_, backend := plan367RedisBackend(t, "thought-notifications-old-record:", config)
				// This is the stored shape from before the preference existed.
				raw, err := json.Marshal(map[string]any{
					"Token": "old-record-token", "Platform": platform,
					"UpdatedAt": "2026-10-23T10:00:00Z",
				})
				if err != nil {
					t.Fatal(err)
				}
				if err := backend.client.Set(context.Background(), backend.key("recipient"), raw, 0).Err(); err != nil {
					t.Fatalf("seed old token record: %v", err)
				}
				if encrypted {
					plan367Migrate(t, backend)
				}
				reopened := newRedisPushTokenBackend(backend.client, backend.prefix)
				reopened.vaultConfig = config
				push := newThoughtNotificationPushService(reopened)
				recorder := newRecordingPushSender()
				push.sender = recorder.Send
				for _, fixture := range thoughtNotificationPushCases() {
					t.Run(fixture.name, func(t *testing.T) {
						assertThoughtNotificationProviderCalls(t, push, recorder, "recipient", fixture.envelope, 1)
					})
				}
			})
		}
	}
}

func TestThoughtNotificationsOpaqueRoute_OnlyThoughtOriginIsSuppressed(t *testing.T) {
	for _, platform := range []string{"android", "ios"} {
		t.Run(platform, func(t *testing.T) {
			backend := newMemoryPushTokenStore()
			push := newThoughtNotificationPushService(backend)
			env := setupInboxStreamEnv(t, NewInboxStore(push), NewGroupInboxStore(500, 0))
			off := false
			registerThoughtNotificationPreference(t, env, platform, "opaque-token", &off, opaqueWakeCapability)
			recipient := env.sender.ID().String()
			recorder := newRecordingPushSender()
			push.sender = recorder.Send
			t.Run("thought_origin", func(t *testing.T) {
				for _, fixture := range thoughtNotificationPushCases() {
					assertThoughtNotificationProviderCalls(t, push, recorder, recipient, fixture.envelope, 0)
				}
			})
			t.Run("chat_origin", func(t *testing.T) {
				assertThoughtNotificationProviderCalls(t, push, recorder, recipient,
					`{"type":"chat_message","version":"2","msgId":"opaque-chat","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`, 1)
			})
			t.Run("mixed_mailbox_wake", func(t *testing.T) {
				before := recorder.SendCallCount()
				if err := push.mailboxDirty(context.Background(), plan367Route(t, backend, recipient)); err != nil {
					t.Fatalf("fixed mailbox wake: %v", err)
				}
				if got := recorder.SendCallCount() - before; got != 1 {
					t.Fatalf("fixed mailbox provider calls = %d, want 1", got)
				}
			})
		})
	}
}

func TestThoughtNotificationsOff_PreservesAndroidCallWake(t *testing.T) {
	backend := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(backend)
	env := setupInboxStreamEnv(t, NewInboxStore(push), NewGroupInboxStore(500, 0))
	off := false
	registerThoughtNotificationPreference(t, env, "android", "call-token", &off)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	err := (pushServiceCallWakeDispatcher{push: push}).DispatchCallWake(context.Background(),
		CallWakeRoute{Kind: CallTokenKindStandard, Platform: "android", Token: "call-token"},
		CallWakePayload{CallHandle: callTestHandleA, WakeHandle: callTestWake, ExpiresAtMs: time.Now().Add(45 * time.Second).UnixMilli()},
	)
	if err != nil {
		t.Fatalf("call wake while Thought notifications are off: %v", err)
	}
	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("call provider calls = %d, want 1", got)
	}
	if message := recorder.LastMessage(); message.Data["w"] != "call" || message.Token != "call-token" {
		t.Fatalf("call wake changed: %#v", message)
	}
}

func TestThoughtNotificationsAndroidFallback_RetainsDisplayOwner(t *testing.T) {
	for _, fixture := range thoughtNotificationPushCases()[1:] {
		t.Run(fixture.name, func(t *testing.T) {
			message := projectPushMessageForPlatform(buildPushMessage("token", "sender", fixture.envelope), "android")
			if message == nil || message.Android == nil {
				t.Fatal("generic Thought fallback must retain Android delivery")
			}
			appCanRender := strings.TrimSpace(message.Data["post_id"]) != ""
			providerCanRender := message.Notification != nil || message.Android.Notification != nil
			if appCanRender == providerCanRender {
				t.Fatalf("Thought fallback must have one display owner: app=%t provider=%t", appCanRender, providerCanRender)
			}
			if message.Data["type"] != "post_create" || message.Data["sender_id"] != "sender" {
				t.Fatalf("Thought fallback lost the authenticated sender required by archived-contact policy: %#v", message.Data)
			}
		})
	}
	t.Run("existing_message_channel", func(t *testing.T) {
		message := buildPushMessage("token", "sender", `{"type":"contact_request","version":"2","msgId":"request-1"}`)
		if got := message.Android.Notification.ChannelID; got != "mknoon_messages" {
			t.Fatalf("existing message channel = %q, want mknoon_messages", got)
		}
	})
	t.Run("chat_remains_data_only", func(t *testing.T) {
		message := buildPushMessage("token", "sender", `{"type":"chat_message","version":"2","msgId":"chat-1","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`)
		if message.Notification != nil || message.Android == nil || message.Android.Notification != nil {
			t.Fatal("chat push must retain data-only Android delivery")
		}
	})
}

func TestThoughtNotificationsStaleRoute_RefreshCannotBypassOptOut(t *testing.T) {
	for _, kind := range []string{"memory", "redis_legacy", "redis_encrypted"} {
		for _, opaque := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/opaque_%t", kind, opaque), func(t *testing.T) {
				backend, reopen := thoughtNotificationBackend(t, kind)
				var capabilities []string
				if opaque {
					capabilities = []string{opaqueWakeCapability}
				}
				if err := backend.RegisterToken("recipient", "token", "ios", capabilities...); err != nil {
					t.Fatal(err)
				}
				selectedWhileOn := plan367Route(t, backend, "recipient")
				if err := backend.RegisterTokenWithThoughtNotifications("recipient", "token", "ios", false, capabilities...); err != nil {
					t.Fatal(err)
				}
				if revoked, err := backend.RevokeIfCurrent(selectedWhileOn); err != nil || revoked {
					t.Fatalf("stale ON route revoked OFF registration: revoked=%v error=%v", revoked, err)
				}
				push := newThoughtNotificationPushService(reopen())
				recorder := newRecordingPushSender()
				push.sender = recorder.Send
				for _, fixture := range thoughtNotificationPushCases() {
					push.SendNotification(context.Background(), "recipient", "sender", fixture.envelope, selectedWhileOn)
				}
				if got := recorder.SendCallCount(); got != 0 {
					t.Fatalf("stale ON route bypassed current opt-out: provider calls = %d", got)
				}
			})
		}
	}
}

func TestThoughtNotificationsLegacyOptOut_SurvivesVaultMigration(t *testing.T) {
	for _, platform := range []string{"android", "ios"} {
		t.Run(platform, func(t *testing.T) {
			config := plan367Config("key-a", "test", map[string][]byte{"key-a": plan367Key('a')})
			_, backend := plan367RedisBackend(t, "thought-notifications-off-migration:", config)
			push := newThoughtNotificationPushService(backend)
			env := setupInboxStreamEnv(t, NewInboxStore(push), NewGroupInboxStore(500, 0))
			off := false
			registerThoughtNotificationPreference(t, env, platform, "migration-token", &off)
			plan367Migrate(t, backend)
			reopened := newRedisPushTokenBackend(backend.client, backend.prefix)
			reopened.vaultConfig = config
			push = newThoughtNotificationPushService(reopened)
			recorder := newRecordingPushSender()
			push.sender = recorder.Send
			assertThoughtNotificationProviderCalls(t, push, recorder, env.sender.ID().String(), postCreatePushFixtureWithPostID, 0)
		})
	}
}

func TestThoughtNotificationsVault_AbsentPreferencePreservesLegacyAAD(t *testing.T) {
	handle := base64.RawURLEncoding.EncodeToString([]byte(strings.Repeat("h", 32)))
	directory := pushTokenDirectoryRecord{
		Handle: handle, Generation: 1, Platform: "ios", Capabilities: []string{},
		ProviderEnvironment: "test",
	}
	aad, err := buildPushTokenVaultAAD("recipient", directory, "key-a")
	if err != nil {
		t.Fatal(err)
	}
	want := fmt.Sprintf(`{"schema":1,"peer_digest":"%x","handle":%q,"generation":1,"platform":"ios","capabilities":[],"source_legacy_digest":"","provider_environment":"test","key_id":"key-a"}`,
		sha256.Sum256([]byte("recipient")), handle)
	if string(aad) != want {
		t.Fatalf("absent preference changed legacy AAD: got %s, want %s", aad, want)
	}
}

func TestThoughtNotificationsVault_OptOutCannotBeFlippedWithoutAuthentication(t *testing.T) {
	_, backend, _ := plan367NewEncryptedFixture(t, "thought-notifications-tamper:")
	if err := backend.RegisterTokenWithThoughtNotifications("recipient", "token", "ios", false); err != nil {
		t.Fatal(err)
	}
	key := backend.directoryKey("recipient")
	directory := plan367ReadJSONMap(t, backend, key)
	directory["thought_notifications_enabled"] = true
	plan367WriteJSONMap(t, backend, key, directory)
	push := newThoughtNotificationPushService(backend)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	assertThoughtNotificationProviderCalls(t, push, recorder, "recipient", postCreatePushFixtureWithPostID, 0)
}

func TestThoughtNotificationsRegistration_FailedWriteIsNotAcknowledged(t *testing.T) {
	backend := newFailingRegisterPushTokenBackend()
	env := setupInboxStreamEnv(t, NewInboxStore(NewPushServiceWithBackend(backend)), NewGroupInboxStore(500, 0))
	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.Close()
	off := false
	sendInboxReq(t, stream, inboxRequest{
		Action: "register_token", Token: "failed-token", Platform: "ios",
		ThoughtNotificationsEnabled: &off,
	})
	response := recvInboxResp(t, stream)
	if response.Status != "ERROR" || response.Error != "Push token persistence failed" {
		t.Fatalf("failed preference registration response = %#v, want persistence error", response)
	}
	if backend.registerCalls != 1 || backend.lastPeerID != env.sender.ID().String() {
		t.Fatalf("failed write calls = %d peer = %q, want authenticated registration", backend.registerCalls, backend.lastPeerID)
	}
	if entry := backend.LookupToken(env.sender.ID().String()); entry != nil {
		t.Fatalf("failed write persisted a token: %#v", entry)
	}
}

func TestThoughtNotificationsWakeAdmission_KeepsThoughtsAtSemanticBoundary(t *testing.T) {
	fixture := newWakeOutcomeTestFixture(t, "thought-notifications-durable-wake:")
	if err := fixture.pushBackend.RegisterTokenWithThoughtNotifications("recipient", "token", "ios", false,
		opaqueWakeCapability, wakeOutcomeCapability); err != nil {
		t.Fatal(err)
	}
	// A messageId alias must not let a Thought lose its event type in a generic
	// durable mailbox obligation, which also serves unrelated notification kinds.
	envelope := strings.Replace(postCreatePushFixtureWithPostID, `"event_id":`, `"messageId":"thought-alias","event_id":`, 1)
	entry := inboxMessage{From: "sender", Message: envelope, Timestamp: fixture.now.UnixMilli()}
	if _, eligible := newWakeOutcomeAdmission("recipient", envelope, wakeOutcomeProducerDirectMessage,
		plan367Route(t, fixture.pushBackend, "recipient"), entry.Timestamp, directWakeOutcomeExpiryMs(entry)); !eligible {
		t.Fatal("fixture must otherwise qualify for generic durable wake admission")
	}
	if _, _, _, _, handled, err := fixture.inbox.storeWithWakeOutcome("recipient", entry); err != nil || handled {
		t.Fatalf("Thought entered generic durable wake admission: handled=%v error=%v", handled, err)
	}
	if result, err := fixture.inbox.Store("recipient", entry); err != nil || result != InboxStoreResultStored {
		t.Fatalf("Thought custody changed: result=%q error=%v", result, err)
	}
	if got := fixture.inbox.Count("recipient"); got != 1 {
		t.Fatalf("Thought custody rows = %d, want 1", got)
	}
}
