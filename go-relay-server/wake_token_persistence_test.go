package main

import (
	"context"
	"encoding/json"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

func TestRelayNotificationClosure_ReactionWakeAuthorizationSurvivesRestart(t *testing.T) {
	server := miniredis.RunT(t)
	const prefix = "reaction-wake-restart:"
	first := NewInboxStoreWithBackend(newRedisInboxBackend(newTestRedisClient(t, server), prefix, 100), nil)
	if err := first.RegisterWakeTokens("recipient", []string{"recipient-issued-wake"}); err != nil {
		t.Fatal(err)
	}

	// The replacement process must wake an offline recipient without waiting
	// for that recipient to reopen the app and register its contact set again.
	tokens := newRedisPushTokenBackend(newTestRedisClient(t, server), prefix)
	if err := tokens.RegisterToken("recipient", "fcm-token", "ios", directReactionCapability); err != nil {
		t.Fatal(err)
	}
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	restarted := NewInboxStoreWithBackend(newRedisInboxBackend(newTestRedisClient(t, server), prefix, 100), push)
	restarted.SetDirectReactionPushEnabled(true)
	if !restarted.wakeTokens.HasRegisteredSet("recipient") {
		t.Fatal("relay restart lost the offline recipient's wake authorization")
	}
	result, err := restarted.Store("recipient", inboxMessage{
		From: "sender", Message: directReactionEnvelope("reaction-after-restart", "add", "target", "sender"),
		Timestamp: time.Now().UnixMilli(), WakeToken: "recipient-issued-wake",
	})
	if err != nil || result != InboxStoreResultStored {
		t.Fatalf("store = %v, %v", result, err)
	}
	message := waitForRecordedPush(t, recorder)
	assertAPNSCustomString(t, message, "type", "message_reaction")
	if restarted.wakeTokens.IsAuthorized("recipient", "wrong-token") {
		t.Fatal("durability must preserve contact-only authorization")
	}
}

func TestRelayNotificationClosure_WakeReplacementAndRevocationAcrossClients(t *testing.T) {
	server := miniredis.RunT(t)
	a := &redisWakeTokenStore{client: newTestRedisClient(t, server), prefix: "wake-replace:"}
	b := &redisWakeTokenStore{client: newTestRedisClient(t, server), prefix: a.prefix}
	if err := a.RegisterWakeTokens("recipient", []string{"old-a", "old-b", "old-a", ""}); err != nil {
		t.Fatal(err)
	}
	if !b.AuthorizesWake("recipient", "old-b", true) {
		t.Fatal("second process did not observe registration")
	}
	if err := b.RegisterWakeTokens("recipient", []string{"replacement"}); err != nil {
		t.Fatal(err)
	}
	for _, token := range []string{"old-a", "old-b", "", "unknown"} {
		if a.AuthorizesWake("recipient", token, true) {
			t.Fatal("replacement retained a revoked or absent token")
		}
	}
	if !a.AuthorizesWake("recipient", "replacement", true) {
		t.Fatal("first process cached a stale registration")
	}
	if err := a.ClearWakeTokens("recipient"); err != nil {
		t.Fatal(err)
	}
	if b.HasRegisteredSet("recipient") || b.AuthorizesWake("recipient", "replacement", true) {
		t.Fatal("revoked registration remained eligible for strict reaction wake")
	}
	if !b.IsAuthorized("recipient", "legacy-message") {
		t.Fatal("revocation changed the separate legacy ordinary-message policy")
	}
	for _, emptySet := range [][]string{nil, {}, {"", ""}} {
		if err := a.RegisterWakeTokens("recipient", []string{"replacement"}); err != nil {
			t.Fatal(err)
		}
		if err := b.RegisterWakeTokens("recipient", emptySet); err != nil {
			t.Fatal(err)
		}
		if a.HasRegisteredSet("recipient") || a.AuthorizesWake("recipient", "replacement", true) {
			t.Fatal("empty replacement failed to revoke strict wake authorization")
		}
	}
}

func TestRelayNotificationClosure_WakePersistenceBindsRecipientWithoutBearer(t *testing.T) {
	server := miniredis.RunT(t)
	store := &redisWakeTokenStore{client: newTestRedisClient(t, server), prefix: "wake-secret:"}
	const bearer = "a-high-entropy-recipient-issued-secret-bearer"
	for _, recipient := range []string{"recipient:a/b", "recipient:b/a"} {
		if err := store.RegisterWakeTokens(recipient, []string{bearer, bearer, ""}); err != nil {
			t.Fatal(err)
		}
		if !store.AuthorizesWake(recipient, bearer, true) {
			t.Fatal("recipient could not use its own token")
		}
	}
	for _, key := range server.Keys() {
		payload, err := server.Get(key)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(key, bearer) || strings.Contains(payload, bearer) {
			t.Fatal("Redis persisted a usable wake bearer")
		}
		var digests []string
		if err := json.Unmarshal([]byte(payload), &digests); err != nil || len(digests) != 1 {
			t.Fatalf("registration did not deduplicate/ignore empty tokens: count=%d err=%v", len(digests), err)
		}
		if ttl := server.TTL(key); ttl != 0 {
			t.Fatalf("offline authorization has expiry %s", ttl)
		}
	}
	a, _ := server.Get(store.key("recipient:a/b"))
	b, _ := server.Get(store.key("recipient:b/a"))
	if a == b {
		t.Fatal("persisted digests do not bind their recipient")
	}
	if err := server.Set(store.key("recipient:b/a"), a); err != nil {
		t.Fatal(err)
	}
	if store.AuthorizesWake("recipient:b/a", bearer, true) {
		t.Fatal("a copied recipient's authorization grants another recipient wake access")
	}
	otherDeployment := &redisWakeTokenStore{client: newTestRedisClient(t, server), prefix: "other-deployment:"}
	if otherDeployment.AuthorizesWake("recipient:a/b", bearer, true) {
		t.Fatal("authorization crossed Redis namespace")
	}
}

func TestRelayNotificationClosure_CorruptWakeAuthorizationFailsClosed(t *testing.T) {
	for _, payload := range []string{
		"not-json", "null", "[]", `[null]`, `[17]`, `["short"]`,
		`["` + strings.Repeat("z", 64) + `"]`,
		`["` + wakeTokenDigest("recipient", "valid") + `","invalid"]`,
	} {
		t.Run(payload[:min(len(payload), 20)], func(t *testing.T) {
			server := miniredis.RunT(t)
			store := &redisWakeTokenStore{client: newTestRedisClient(t, server), prefix: "wake-corrupt:"}
			if err := server.Set(store.key("recipient"), payload); err != nil {
				t.Fatal(err)
			}
			if !store.HasRegisteredSet("recipient") {
				t.Fatal("corruption masqueraded as unregistered legacy state")
			}
			for _, strict := range []bool{false, true} {
				if store.AuthorizesWake("recipient", "valid", strict) {
					t.Fatalf("corrupt persisted data authorized a wake (strict=%v)", strict)
				}
			}
		})
	}
}

func TestRelayNotificationClosure_RedisWakeFailureCannotAuthorizeOrAcknowledge(t *testing.T) {
	for _, action := range []string{"register_wake_tokens", "unregister_token"} {
		t.Run(action, func(t *testing.T) {
			server := miniredis.RunT(t)
			client := newTestRedisClient(t, server)
			store := &redisWakeTokenStore{client: client, prefix: "wake-failure:"}
			inbox := NewInboxStore(NewPushServiceWithBackend(newMemoryPushTokenStore()))
			inbox.wakeTokens = store
			env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(100, time.Hour))
			peerID := env.recipient.ID().String()
			if err := store.RegisterWakeTokens(peerID, []string{"original"}); err != nil {
				t.Fatal(err)
			}
			if err := client.Close(); err != nil {
				t.Fatal(err)
			}
			if !store.HasRegisteredSet(peerID) || store.AuthorizesWake(peerID, "original", true) || store.IsAuthorized(peerID, "original") {
				t.Fatal("Redis lookup failure granted authorization or became legacy absence")
			}
			stream, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
			if err != nil {
				t.Fatal(err)
			}
			defer stream.Close()
			sendInboxReq(t, stream, inboxRequest{Action: action, WakeTokens: []string{"replacement-secret"}})
			response := recvInboxResp(t, stream)
			if response.Status != "ERROR" || response.Error == "" {
				t.Fatalf("failed durable operation acknowledged success: %#v", response)
			}
			if strings.Contains(response.Error, "replacement-secret") || strings.Contains(response.Error, server.Addr()) {
				t.Fatal("failure response exposed bearer/backend details")
			}
			healthy := &redisWakeTokenStore{client: newTestRedisClient(t, server), prefix: store.prefix}
			if !healthy.AuthorizesWake(peerID, "original", true) || healthy.AuthorizesWake(peerID, "replacement-secret", true) {
				t.Fatal("failed operation partially changed durable authorization")
			}
		})
	}
}

func TestRelayNotificationClosure_WakeStreamRegistrationUsesAuthenticatedRecipient(t *testing.T) {
	server := miniredis.RunT(t)
	inbox := NewInboxStoreWithBackend(newRedisInboxBackend(newTestRedisClient(t, server), "wake-stream:", 100), NewPushServiceWithBackend(newMemoryPushTokenStore()))
	env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(100, time.Hour))
	other := env.recipient.ID().String()
	if err := inbox.RegisterWakeTokens(other, []string{"other-secret"}); err != nil {
		t.Fatal(err)
	}
	stream, err := env.intruder.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.Close()
	sendInboxReq(t, stream, inboxRequest{
		Action: "register_wake_tokens", From: other, To: other, WakeTokens: []string{"attacker-secret"},
	})
	if response := recvInboxResp(t, stream); response.Status != "OK" {
		t.Fatalf("registration failed: %#v", response)
	}
	if !inbox.wakeTokens.AuthorizesWake(env.intruder.ID().String(), "attacker-secret", true) ||
		!inbox.wakeTokens.AuthorizesWake(other, "other-secret", true) ||
		inbox.wakeTokens.AuthorizesWake(other, "attacker-secret", true) {
		t.Fatal("request fields changed another recipient's authorization")
	}
}

func TestRelayNotificationClosure_WakeLookupFailurePreservesMessageWithoutPush(t *testing.T) {
	for _, corrupt := range []bool{false, true} {
		name := "closed-redis"
		if corrupt {
			name = "corrupt-authorization"
		}
		t.Run(name, func(t *testing.T) {
			server := miniredis.RunT(t)
			client := newTestRedisClient(t, server)
			store := &redisWakeTokenStore{client: client, prefix: "wake-inbox-failure:"}
			inbox, recorder := configuredReactionInbox(t)
			inbox.wakeTokens = store
			if err := store.RegisterWakeTokens("peer-recipient", []string{"reaction-wake-alice"}); err != nil {
				t.Fatal(err)
			}
			if corrupt {
				if err := server.Set(store.key("peer-recipient"), "corrupt"); err != nil {
					t.Fatal(err)
				}
			} else if err := client.Close(); err != nil {
				t.Fatal(err)
			}
			result, err := inbox.Store("peer-recipient", inboxMessage{
				From: "peer-alice", Message: directReactionEnvelope("reaction-lookup-failure", "add", "target", "peer-alice"),
				Timestamp: time.Now().UnixMilli(), WakeToken: "reaction-wake-alice",
			})
			if err != nil || result != InboxStoreResultStored {
				t.Fatalf("authorization outage lost inbox delivery: result=%v err=%v", result, err)
			}
			assertNoRecordedPush(t, recorder)
		})
	}
}

func TestRelayNotificationClosure_ConcurrentWakeClearCannotFailOpenStrictCheck(t *testing.T) {
	server := miniredis.RunT(t)
	stores := []wakeTokenStore{
		newMemoryWakeTokenStore(),
		&redisWakeTokenStore{client: newTestRedisClient(t, server), prefix: "wake-concurrent:"},
	}
	for _, store := range stores {
		var workers sync.WaitGroup
		for worker := 0; worker < 4; worker++ {
			workers.Add(1)
			go func() {
				defer workers.Done()
				for iteration := 0; iteration < 25; iteration++ {
					if err := store.RegisterWakeTokens("recipient", []string{"legitimate"}); err != nil {
						t.Error(err)
						return
					}
					if store.AuthorizesWake("recipient", "never-registered", true) {
						t.Error("strict authorization failed open during concurrent clear")
					}
					if err := store.ClearWakeTokens("recipient"); err != nil {
						t.Error(err)
						return
					}
				}
			}()
		}
		workers.Wait()
		if store.AuthorizesWake("recipient", "legitimate", true) {
			t.Fatal("final revocation did not remove strict wake authorization")
		}
	}
}
