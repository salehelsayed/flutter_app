package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"reflect"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/alicebob/miniredis/v2"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/redis/go-redis/v9"
)

type wakeOutcomeTestFixture struct {
	redis        *miniredis.Miniredis
	pushBackend  *redisPushTokenBackend
	push         *PushService
	state        *redisWakeOutcomeStore
	inboxBackend *redisInboxBackend
	groupBackend *redisGroupInboxBackend
	inbox        *InboxStore
	group        *GroupInboxStore
	now          time.Time
}

func newWakeOutcomeTestFixture(t *testing.T, prefix string) *wakeOutcomeTestFixture {
	t.Helper()
	server, pushBackend, _ := plan367NewEncryptedFixture(t, prefix)
	now := time.UnixMilli(2_100_000_000_000)
	server.SetTime(now)
	state := newRedisWakeOutcomeStore(pushBackend.client, prefix)
	state.now = func() time.Time { return now }
	inboxBackend := newRedisInboxBackend(pushBackend.client, prefix, 64)
	inboxBackend.now = func() time.Time { return now }
	inboxBackend.wakeOutcomes = state
	groupBackend := newRedisGroupInboxBackend(pushBackend.client, prefix, 64, groupMessageTTL)
	groupBackend.wakeOutcomes = state
	push := NewPushServiceWithBackend(pushBackend)
	push.retryDelays = nil
	inbox := NewInboxStoreWithBackendAndCapacity(inboxBackend, push, 64)
	inbox.SetWakeOutcomeAdmissionEnabled(true)
	group := NewGroupInboxStoreWithBackend(groupBackend)
	group.SetPush(push)
	group.SetWakeOutcomeAdmissionEnabled(true)
	return &wakeOutcomeTestFixture{
		redis: server, pushBackend: pushBackend, push: push, state: state,
		inboxBackend: inboxBackend, groupBackend: groupBackend,
		inbox: inbox, group: group, now: now,
	}
}

func wakeOutcomeDirectEnvelope(eventKey string) string {
	return fmt.Sprintf(
		`{"type":"chat_message","version":"2","messageId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
		eventKey,
	)
}

func wakeOutcomeDirectReactionEnvelope(eventKey, sender string) string {
	return fmt.Sprintf(
		`{"type":"message_reaction","version":"2","eventId":%q,"reactionId":%q,"action":"add","targetMessageId":"target","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
		eventKey, eventKey, sender,
	)
}

func wakeOutcomeGroupEnvelope(eventKey, messageID string) string {
	return fmt.Sprintf(
		`{"type":"group_message","groupId":"group","messageId":%q,"logicalDeliveryId":%q}`,
		messageID, eventKey,
	)
}

func wakeOutcomeAdmissionForTest(
	t *testing.T,
	fixture *wakeOutcomeTestFixture,
	peerID string,
	message string,
	producer wakeOutcomeProducerKind,
	capabilities ...string,
) wakeOutcomeAdmission {
	t.Helper()
	capabilities = append(capabilities, opaqueWakeCapability, wakeOutcomeCapability)
	route := plan367RegisterEncrypted(
		t, fixture.pushBackend, peerID, "provider-token-"+peerID, "android", capabilities...,
	)
	admission, ok := newWakeOutcomeAdmission(
		peerID, message, producer, route, fixture.now.UnixMilli(),
		fixture.now.Add(24*time.Hour).UnixMilli(),
	)
	if !ok {
		t.Fatalf("newWakeOutcomeAdmission(%q) rejected exact fixture", peerID)
	}
	return admission
}

func requireWakeOutcomeRecord(
	t *testing.T,
	store *redisWakeOutcomeStore,
	peerID string,
	correlation string,
) redisWakeOutcomeRecord {
	t.Helper()
	payload, err := store.client.HGet(
		context.Background(), store.stateKey(peerID), correlation,
	).Result()
	if err != nil {
		t.Fatalf("read wake outcome record: %v", err)
	}
	record, err := decodeRedisWakeOutcomeRecord(payload)
	if err != nil {
		t.Fatalf("decode wake outcome record: %v", err)
	}
	return record
}

func waitForWakeProviderCalls(t *testing.T, recorder *recordingPushSender, want int) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for recorder.SendCallCount() < want && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if got := recorder.SendCallCount(); got != want {
		t.Fatalf("provider sends = %d, want %d", got, want)
	}
}

func TestRelayNotificationClosure_WakeOutcomeCapabilityAndLegacyMatrix(t *testing.T) {
	fixture := newWakeOutcomeTestFixture(t, "wake-matrix:")
	const peerID = "wake-matrix-recipient"
	cases := []struct {
		name        string
		producer    wakeOutcomeProducerKind
		message     string
		reactionCap string
	}{
		{"direct", wakeOutcomeProducerDirectMessage, wakeOutcomeDirectEnvelope("direct-event"), ""},
		{"direct reaction", wakeOutcomeProducerDirectReaction, wakeOutcomeDirectReactionEnvelope("direct-reaction", "sender"), directReactionCapability},
		{"group", wakeOutcomeProducerGroupMessage, wakeOutcomeGroupEnvelope("logical-group", "alias-group"), ""},
		{"group reaction", wakeOutcomeProducerGroupReaction, `{"notificationTransitionId":"group-transition"}`, groupReactionCapability},
	}
	for index, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			capabilities := []string{opaqueWakeCapability, wakeOutcomeCapability}
			if tc.reactionCap != "" {
				capabilities = append(capabilities, tc.reactionCap)
			}
			route := plan367RegisterEncrypted(
				t, fixture.pushBackend, fmt.Sprintf("%s-%d", peerID, index),
				fmt.Sprintf("token-%d", index), "android", capabilities...,
			)
			if _, ok := newWakeOutcomeAdmission(
				fmt.Sprintf("%s-%d", peerID, index), tc.message, tc.producer, route,
				fixture.now.UnixMilli(), fixture.now.Add(time.Hour).UnixMilli(),
			); !ok {
				t.Fatal("exact dual-capability encrypted route was not admitted")
			}
		})
	}

	t.Run("real producer adapters commit exact delayed policies", func(t *testing.T) {
		adapterFixture := newWakeOutcomeTestFixture(t, "wake-adapters:")
		requirePending := func(peerID, correlation string, policy wakeOutcomeRoutePolicy) {
			t.Helper()
			record := requireWakeOutcomeRecord(t, adapterFixture.state, peerID, correlation)
			if record.State != wakeOutcomeStatePending || record.Policy != policy ||
				record.DueAtMs != adapterFixture.now.Add(wakeOutcomeDebounce).UnixMilli() {
				t.Fatalf("adapter pending record = %#v, want policy %q", record, policy)
			}
		}

		directPeer := "wake-adapter-direct-peer"
		directMessage := wakeOutcomeDirectEnvelope("wake-adapter-direct-event")
		plan367RegisterEncrypted(
			t,
			adapterFixture.pushBackend,
			directPeer,
			"wake-adapter-direct-token",
			"android",
			opaqueWakeCapability,
			wakeOutcomeCapability,
		)
		if result, err := adapterFixture.inbox.Store(directPeer, inboxMessage{
			ID:        "wake-adapter-direct-entry",
			From:      "wake-adapter-direct-sender",
			Message:   directMessage,
			Timestamp: adapterFixture.now.UnixMilli(),
		}); err != nil || result != InboxStoreResultStored {
			t.Fatalf("direct adapter store = %q/%v", result, err)
		}
		directCorrelation, ok := wakeOutcomeCorrelation(
			directPeer,
			wakeOutcomeProducerDirectMessage,
			directMessage,
		)
		if !ok {
			t.Fatal("direct adapter correlation missing")
		}
		requirePending(directPeer, directCorrelation, wakeOutcomePolicyNone)

		directReactionPeer := "wake-adapter-direct-reaction-peer"
		directReactionSender := "wake-adapter-direct-reaction-sender"
		directReactionEvent := "wake-adapter-direct-reaction-event"
		directReactionMessage := directReactionEnvelope(
			directReactionEvent,
			"add",
			"wake-adapter-direct-target",
			directReactionSender,
		)
		plan367RegisterEncrypted(
			t,
			adapterFixture.pushBackend,
			directReactionPeer,
			"wake-adapter-direct-reaction-token",
			"android",
			directReactionCapability,
			opaqueWakeCapability,
			wakeOutcomeCapability,
		)
		adapterFixture.inbox.SetDirectReactionPushEnabled(true)
		adapterFixture.inbox.RegisterWakeTokens(directReactionPeer, []string{"wake-adapter-reaction-auth"})
		if result, err := adapterFixture.inbox.Store(directReactionPeer, inboxMessage{
			ID:        "wake-adapter-direct-reaction-entry",
			From:      directReactionSender,
			Message:   directReactionMessage,
			Timestamp: adapterFixture.now.UnixMilli(),
			WakeToken: "wake-adapter-reaction-auth",
		}); err != nil || result != InboxStoreResultStored {
			t.Fatalf("direct-reaction adapter store = %q/%v", result, err)
		}
		if _, rawAliasAccepted := wakeOutcomeCorrelation(
			directReactionPeer,
			wakeOutcomeProducerDirectReaction,
			directReactionMessage,
		); rawAliasAccepted {
			t.Fatal("direct-reaction wire eventId was accepted as raw Plan-369 reactionId")
		}
		directReactionCorrelation, ok := wakeOutcomeCorrelationForEvent(
			directReactionPeer,
			wakeOutcomeProducerDirectReaction,
			directReactionEvent,
		)
		if !ok {
			t.Fatal("direct-reaction adapter correlation missing")
		}
		requirePending(
			directReactionPeer,
			directReactionCorrelation,
			wakeOutcomePolicyDirectReaction,
		)

		groupPeer := "wake-adapter-group-peer"
		groupSender := "wake-adapter-group-sender"
		groupMessage := wakeOutcomeGroupEnvelope(
			"wake-adapter-group-logical",
			"wake-adapter-group-alias",
		)
		plan367RegisterEncrypted(
			t,
			adapterFixture.pushBackend,
			groupPeer,
			"wake-adapter-group-token",
			"android",
			opaqueWakeCapability,
			wakeOutcomeCapability,
		)
		if err := adapterFixture.group.StoreWithPushRecipients(
			"wake-adapter-group",
			groupSender,
			groupMessage,
			[]string{groupSender, groupPeer},
		); err != nil {
			t.Fatalf("group adapter store: %v", err)
		}
		groupCorrelation, ok := wakeOutcomeCorrelation(
			groupPeer,
			wakeOutcomeProducerGroupMessage,
			groupMessage,
		)
		if !ok {
			t.Fatal("group adapter correlation missing")
		}
		requirePending(groupPeer, groupCorrelation, wakeOutcomePolicyNone)

		groupReactionPeer := "wake-adapter-group-reaction-peer"
		groupReactionSender := "wake-adapter-group-reaction-sender"
		groupReactionID := "wake-adapter-group-transition"
		groupReactionFixture := newSignedGroupReactionFixture(
			t,
			testCanonicalGroupReactionHandlerID,
			"wake-adapter-reactor-account",
			groupReactionSender,
		)
		groupReactionMessage := groupReactionFixture.envelope(
			t,
			groupReactionID,
			"add",
			"wake-adapter-group-base",
			"wake-adapter-group-target",
			[]string{groupReactionPeer},
			[]string{groupReactionPeer},
		)
		plan367RegisterEncrypted(
			t,
			adapterFixture.pushBackend,
			groupReactionPeer,
			"wake-adapter-group-reaction-token",
			"android",
			groupReactionCapability,
			opaqueWakeCapability,
			wakeOutcomeCapability,
		)
		adapterFixture.group.SetGroupReactionPushEnabled(true)
		if err := adapterFixture.group.StoreWithPushRecipients(
			testCanonicalGroupReactionHandlerID,
			groupReactionSender,
			groupReactionMessage,
			[]string{groupReactionPeer},
		); err != nil {
			t.Fatalf("group-reaction adapter store: %v", err)
		}
		if _, rawAliasAccepted := wakeOutcomeCorrelation(
			groupReactionPeer,
			wakeOutcomeProducerGroupReaction,
			groupReactionMessage,
		); rawAliasAccepted {
			t.Fatal("signed transitionId was accepted as raw Plan-369 notificationTransitionId")
		}
		groupReactionCorrelation, ok := wakeOutcomeCorrelationForEvent(
			groupReactionPeer,
			wakeOutcomeProducerGroupReaction,
			groupReactionID,
		)
		if !ok {
			t.Fatal("group-reaction adapter correlation missing")
		}
		requirePending(
			groupReactionPeer,
			groupReactionCorrelation,
			wakeOutcomePolicyGroupReaction,
		)
	})

	message := wakeOutcomeDirectEnvelope("matrix-negative")
	route := plan367RegisterEncrypted(
		t, fixture.pushBackend, "matrix-negative-peer", "token", "android",
		opaqueWakeCapability, wakeOutcomeCapability,
	)
	for _, mutate := range []func(pushRouteLease) pushRouteLease{
		func(value pushRouteLease) pushRouteLease { value.Handle = ""; return value },
		func(value pushRouteLease) pushRouteLease {
			value.Capabilities = []string{opaqueWakeCapability}
			return value
		},
		func(value pushRouteLease) pushRouteLease {
			value.Capabilities = []string{wakeOutcomeCapability}
			return value
		},
	} {
		if _, ok := newWakeOutcomeAdmission(
			"matrix-negative-peer", message, wakeOutcomeProducerDirectMessage, mutate(route),
			fixture.now.UnixMilli(), fixture.now.Add(time.Hour).UnixMilli(),
		); ok {
			t.Fatal("inexact route was admitted")
		}
	}
	if _, ok := newWakeOutcomeAdmission(
		"matrix-negative-peer", wakeOutcomeDirectReactionEnvelope("r", "s"),
		wakeOutcomeProducerDirectReaction, route, fixture.now.UnixMilli(),
		fixture.now.Add(time.Hour).UnixMilli(),
	); ok {
		t.Fatal("reaction route without its incumbent capability was admitted")
	}

	staleMessage := wakeOutcomeDirectEnvelope("route-cas-event")
	staleAdmission := wakeOutcomeAdmissionForTest(
		t, fixture, "route-cas-peer", staleMessage, wakeOutcomeProducerDirectMessage,
	)
	if err := fixture.pushBackend.RegisterToken(
		"route-cas-peer", "provider-token-route-cas-peer", "android", opaqueWakeCapability,
	); err != nil {
		t.Fatalf("remove capability: %v", err)
	}
	_, _, err := fixture.inboxBackend.StoreWithWakeOutcome(
		"route-cas-peer",
		inboxMessage{ID: "route-cas-row", From: "sender", Message: staleMessage, Timestamp: fixture.now.UnixMilli()},
		staleAdmission,
	)
	if !errors.Is(err, errWakeOutcomeRouteChanged) || fixture.inboxBackend.Count("route-cas-peer") != 0 {
		t.Fatalf("route CAS = error %v count %d, want no commit", err, fixture.inboxBackend.Count("route-cas-peer"))
	}

	t.Run("migrated source digest participates in route CAS", func(t *testing.T) {
		const (
			prefix        = "wake-route-source-cas:"
			peerID        = "wake-route-source-cas-peer"
			providerToken = "wake-route-source-cas-token"
		)
		config := plan367Config(
			"key-a",
			"test",
			map[string][]byte{"key-a": plan367Key('a')},
		)
		server, backend := plan367RedisBackend(t, prefix, config)
		now := time.UnixMilli(2_100_000_100_000)
		server.SetTime(now)
		capabilities := []string{opaqueWakeCapability, wakeOutcomeCapability}
		if err := backend.RegisterToken(
			peerID,
			providerToken,
			"android",
			capabilities...,
		); err != nil {
			t.Fatalf("legacy registration: %v", err)
		}
		plan367Migrate(t, backend)

		capturedRoute := plan367Route(t, backend, peerID)
		message := wakeOutcomeDirectEnvelope("wake-route-source-cas-event")
		admission, ok := newWakeOutcomeAdmission(
			peerID,
			message,
			wakeOutcomeProducerDirectMessage,
			capturedRoute,
			now.UnixMilli(),
			now.Add(time.Hour).UnixMilli(),
		)
		if !ok {
			t.Fatal("migrated encrypted route was not admitted")
		}

		// An exact encrypted refresh preserves handle, generation, and
		// capabilities while deliberately clearing the migration source fence.
		if err := backend.RegisterToken(
			peerID,
			providerToken,
			"android",
			capabilities...,
		); err != nil {
			t.Fatalf("exact encrypted refresh: %v", err)
		}
		directoryPayload, err := backend.client.Get(
			context.Background(),
			backend.directoryKey(peerID),
		).Bytes()
		if err != nil {
			t.Fatalf("read refreshed directory: %v", err)
		}
		refreshedDirectory, err := decodePushTokenDirectoryRecord(directoryPayload)
		if err != nil {
			t.Fatalf("decode refreshed directory: %v", err)
		}
		if refreshedDirectory.Handle != capturedRoute.Handle ||
			refreshedDirectory.Generation != capturedRoute.Generation ||
			!slices.Equal(refreshedDirectory.Capabilities, capturedRoute.Capabilities) ||
			refreshedDirectory.SourceLegacyDigest != "" {
			t.Fatalf(
				"exact encrypted refresh = %#v, want same route with cleared source digest",
				refreshedDirectory,
			)
		}

		state := newRedisWakeOutcomeStore(backend.client, prefix)
		state.now = func() time.Time { return now }
		inboxBackend := newRedisInboxBackend(backend.client, prefix, 64)
		inboxBackend.now = func() time.Time { return now }
		inboxBackend.wakeOutcomes = state
		_, _, err = inboxBackend.StoreWithWakeOutcome(
			peerID,
			inboxMessage{
				ID:        "wake-route-source-cas-entry",
				From:      "wake-route-source-cas-sender",
				Message:   message,
				Timestamp: now.UnixMilli(),
			},
			admission,
		)
		if !errors.Is(err, errWakeOutcomeRouteChanged) {
			t.Fatalf("source-fence CAS error = %v, want route changed", err)
		}
		if capturedRoute.legacyDigest == ([32]byte{}) {
			t.Fatal("captured migrated route lost its nonempty source digest")
		}
		if count := inboxBackend.Count(peerID); count != 0 {
			t.Fatalf("source-fence CAS committed event count=%d", count)
		}
		if count := state.client.HLen(context.Background(), state.stateKey(peerID)).Val(); count != 0 {
			t.Fatalf("source-fence CAS committed wake records=%d", count)
		}
		if count := state.client.ZCard(context.Background(), state.dueKey()).Val(); count != 0 {
			t.Fatalf("source-fence CAS committed due members=%d", count)
		}
	})

	t.Run("direct preflight fallback preserves one lookup and store-before-provider", func(t *testing.T) {
		t.Run("lookup error stores without recovering into a provider send", func(t *testing.T) {
			errorFixture := newWakeOutcomeTestFixture(t, "wake-preflight-direct-error:")
			const errorPeer = "wake-preflight-direct-error-peer"
			plan367RegisterEncrypted(
				t,
				errorFixture.pushBackend,
				errorPeer,
				"wake-preflight-direct-error-token",
				"android",
				opaqueWakeCapability,
				wakeOutcomeCapability,
			)
			probe := &plan368BackendProbe{delegate: errorFixture.pushBackend}
			probe.lookup = func(call int, peerID string) (*pushRouteLease, error) {
				if call == 1 && peerID == errorPeer {
					return nil, errors.New("wake preflight lookup unavailable")
				}
				return probe.delegate.LookupRoute(peerID)
			}
			recorder := newRecordingPushSender()
			push := NewPushServiceWithBackend(probe)
			push.sender = recorder.Send
			errorFixture.inbox.push = push

			result, err := errorFixture.inbox.Store(errorPeer, inboxMessage{
				ID:        "wake-preflight-direct-error-entry",
				From:      "wake-preflight-direct-error-sender",
				Message:   wakeOutcomeDirectEnvelope("wake-preflight-direct-error-event"),
				Timestamp: errorFixture.now.UnixMilli(),
			})
			if err != nil || result != InboxStoreResultStored {
				t.Fatalf("error-first direct store = %q/%v", result, err)
			}
			if count := errorFixture.inboxBackend.Count(errorPeer); count != 1 {
				t.Fatalf("error-first direct durable count = %d, want 1", count)
			}
			time.Sleep(20 * time.Millisecond)
			if got := recorder.SendCallCount(); got != 0 {
				t.Fatalf("error-first direct provider sends = %d, want 0", got)
			}
			lookups, resolves, revokes := probe.counts()
			if lookups != 1 || resolves != 0 || revokes != 0 {
				t.Fatalf(
					"error-first direct route calls = lookup %d resolve %d revoke %d, want 1/0/0",
					lookups,
					resolves,
					revokes,
				)
			}
		})

		t.Run("selected nonqualifying lease sends immediately without relookup", func(t *testing.T) {
			leaseFixture := newWakeOutcomeTestFixture(t, "wake-preflight-direct-lease:")
			const leasePeer = "wake-preflight-direct-lease-peer"
			plan367RegisterEncrypted(
				t,
				leaseFixture.pushBackend,
				leasePeer,
				"wake-preflight-direct-lease-token",
				"android",
				opaqueWakeCapability,
			)
			probe := &plan368BackendProbe{delegate: leaseFixture.pushBackend}
			recorder := newRecordingPushSender()
			push := NewPushServiceWithBackend(probe)
			push.sender = recorder.Send
			leaseFixture.inbox.push = push

			result, err := leaseFixture.inbox.Store(leasePeer, inboxMessage{
				ID:        "wake-preflight-direct-lease-entry",
				From:      "wake-preflight-direct-lease-sender",
				Message:   wakeOutcomeDirectEnvelope("wake-preflight-direct-lease-event"),
				Timestamp: leaseFixture.now.UnixMilli(),
			})
			if err != nil || result != InboxStoreResultStored {
				t.Fatalf("nonqualifying direct store = %q/%v", result, err)
			}
			waitForWakeProviderCalls(t, recorder, 1)
			lookups, resolves, revokes := probe.counts()
			if lookups != 1 || resolves != 1 || revokes != 0 {
				t.Fatalf(
					"nonqualifying direct route calls = lookup %d resolve %d revoke %d, want 1/1/0",
					lookups,
					resolves,
					revokes,
				)
			}
			message := recorder.LastMessage()
			if message == nil || message.Data["v"] != "1" || message.Data["w"] != "1" {
				t.Fatalf("nonqualifying direct provider payload = %#v, want fixed wake", message)
			}
		})
	})

	t.Run("protected and mixed-group preflights preserve per-recipient leases", func(t *testing.T) {
		t.Run("protected selected lease is not looked up twice", func(t *testing.T) {
			protectedFixture := newWakeOutcomeTestFixture(t, "wake-preflight-protected:")
			const (
				protectedPeer   = "wake-preflight-protected-peer"
				protectedSender = "wake-preflight-protected-sender"
			)
			plan367RegisterEncrypted(
				t,
				protectedFixture.pushBackend,
				protectedPeer,
				"wake-preflight-protected-token",
				"android",
				opaqueWakeCapability,
			)
			probe := &plan368BackendProbe{delegate: protectedFixture.pushBackend}
			recorder := newRecordingPushSender()
			push := NewPushServiceWithBackend(probe)
			push.sender = recorder.Send
			protectedFixture.inbox.push = push
			protectedFixture.inbox.SetAckCustodyAdmissionEnabled(true)

			result, _, err := protectedFixture.inbox.StoreAckCustody(
				protectedPeer,
				inboxMessage{
					ID: "wake-preflight-protected-entry", From: protectedSender,
					Message: ackCustodyTextEnvelope(
						"wake-preflight-protected-event",
						protectedSender,
						"wake-preflight-protected-ciphertext",
					),
					Timestamp: protectedFixture.now.UnixMilli(),
				},
				ackCustodyDirectTextKind,
			)
			if err != nil || result != InboxStoreResultStored {
				t.Fatalf("nonqualifying protected store = %q/%v", result, err)
			}
			waitForWakeProviderCalls(t, recorder, 1)
			lookups, resolves, revokes := probe.counts()
			if lookups != 1 || resolves != 1 || revokes != 0 {
				t.Fatalf(
					"nonqualifying protected route calls = lookup %d resolve %d revoke %d, want 1/1/0",
					lookups,
					resolves,
					revokes,
				)
			}
		})

		t.Run("protected near-expiry admission falls back to one fixed wake", func(t *testing.T) {
			nearExpiryFixture := newWakeOutcomeTestFixture(t, "wake-preflight-protected-expiry:")
			const (
				peerID    = "wake-preflight-protected-expiry-peer"
				sender    = "wake-preflight-protected-expiry-sender"
				wakeToken = "wake-preflight-protected-expiry-auth"
			)
			plan367RegisterEncrypted(
				t,
				nearExpiryFixture.pushBackend,
				peerID,
				"wake-preflight-protected-expiry-token",
				"android",
				directReactionCapability,
				opaqueWakeCapability,
				wakeOutcomeCapability,
			)
			probe := &plan368BackendProbe{delegate: nearExpiryFixture.pushBackend}
			recorder := newRecordingPushSender()
			push := NewPushServiceWithBackend(probe)
			push.sender = recorder.Send
			nearExpiryFixture.inbox.push = push
			nearExpiryFixture.inbox.SetAckCustodyAdmissionEnabled(true)
			nearExpiryFixture.inbox.SetDirectReactionPushEnabled(true)
			nearExpiryFixture.inbox.RegisterWakeTokens(peerID, []string{wakeToken})

			entry := inboxMessage{
				ID: "wake-preflight-protected-expiry-entry", From: sender,
				Message: ackCustodyReactionEnvelope(
					"wake-preflight-protected-expiry-event",
					"add",
					"wake-preflight-protected-expiry-target",
					sender,
					"wake-preflight-protected-expiry-ciphertext",
				),
				Timestamp:   nearExpiryFixture.now.UnixMilli(),
				ExpiresAtMs: nearExpiryFixture.now.Add(wakeOutcomeDebounce - time.Millisecond).UnixMilli(),
				WakeToken:   wakeToken,
			}
			if expiry := directWakeOutcomeExpiryMs(entry); expiry != nearExpiryFixture.now.Add(499*time.Millisecond).UnixMilli() {
				t.Fatalf("protected effective expiry = %d, want now+499ms", expiry)
			}
			result, _, err := nearExpiryFixture.inbox.StoreAckCustody(
				peerID,
				entry,
				ackCustodyDirectReactionKind,
			)
			if err != nil || result != InboxStoreResultStored {
				t.Fatalf("near-expiry protected store = %q/%v", result, err)
			}
			waitForWakeProviderCalls(t, recorder, 1)
			if count := nearExpiryFixture.inboxBackend.CountAckCustody(peerID); count != 1 {
				t.Fatalf("near-expiry protected durable rows = %d, want 1", count)
			}
			if count := nearExpiryFixture.inboxBackend.Count(peerID); count != 1 {
				t.Fatalf("near-expiry shadow durable rows = %d, want 1", count)
			}
			if count := nearExpiryFixture.state.client.HLen(
				context.Background(),
				nearExpiryFixture.state.stateKey(peerID),
			).Val(); count != 0 {
				t.Fatalf("near-expiry protected wake records = %d, want 0", count)
			}
			if count := nearExpiryFixture.state.client.ZCard(
				context.Background(),
				nearExpiryFixture.state.dueKey(),
			).Val(); count != 0 {
				t.Fatalf("near-expiry protected due members = %d, want 0", count)
			}
			providerMessage := recorder.LastMessage()
			if providerMessage == nil || providerMessage.Data["v"] != "1" ||
				providerMessage.Data["w"] != "1" || providerMessage.Data["type"] != "" {
				t.Fatalf("near-expiry provider payload = %#v, want immediate fixed wake", providerMessage)
			}
			lookups, resolves, revokes := probe.counts()
			if lookups != 1 || resolves != 1 || revokes != 0 {
				t.Fatalf(
					"near-expiry route calls = lookup %d resolve %d revoke %d, want 1/1/0",
					lookups,
					resolves,
					revokes,
				)
			}
		})

		t.Run("mixed group carries lookup error and selected lease independently", func(t *testing.T) {
			groupFixture := newWakeOutcomeTestFixture(t, "wake-preflight-group:")
			const (
				groupErrorPeer = "wake-preflight-group-error-peer"
				groupLeasePeer = "wake-preflight-group-lease-peer"
				groupSender    = "wake-preflight-group-sender"
			)
			plan367RegisterEncrypted(
				t,
				groupFixture.pushBackend,
				groupErrorPeer,
				"wake-preflight-group-error-token",
				"android",
				opaqueWakeCapability,
				wakeOutcomeCapability,
			)
			plan367RegisterEncrypted(
				t,
				groupFixture.pushBackend,
				groupLeasePeer,
				"wake-preflight-group-lease-token",
				"android",
				opaqueWakeCapability,
			)
			probe := &plan368BackendProbe{delegate: groupFixture.pushBackend}
			errorPeerLookups := 0
			probe.lookup = func(_ int, peerID string) (*pushRouteLease, error) {
				if peerID == groupErrorPeer {
					errorPeerLookups++
					if errorPeerLookups == 1 {
						return nil, errors.New("wake group preflight lookup unavailable")
					}
				}
				return probe.delegate.LookupRoute(peerID)
			}
			recorder := newRecordingPushSender()
			push := NewPushServiceWithBackend(probe)
			push.sender = recorder.Send
			groupFixture.group.SetPush(push)

			err := groupFixture.group.StoreWithPushRecipients(
				"wake-preflight-group-id",
				groupSender,
				wakeOutcomeGroupEnvelope(
					"wake-preflight-group-logical",
					"wake-preflight-group-alias",
				),
				[]string{groupSender, groupErrorPeer, groupLeasePeer},
			)
			if err != nil {
				t.Fatalf("mixed preflight group store: %v", err)
			}
			waitForWakeProviderCalls(t, recorder, 1)
			lookups, resolves, revokes := probe.counts()
			if lookups != 2 || resolves != 1 || revokes != 0 || errorPeerLookups != 1 {
				t.Fatalf(
					"mixed group route calls = lookup %d (error peer %d) resolve %d revoke %d, want 2 (1)/1/0",
					lookups,
					errorPeerLookups,
					resolves,
					revokes,
				)
			}
			if messages := groupFixture.groupBackend.RetrieveSince("wake-preflight-group-id", 0); len(messages) != 1 {
				t.Fatalf("mixed group durable events = %d, want 1", len(messages))
			}
		})
	})

	t.Run("malformed scalar authorities store and wake immediately", func(t *testing.T) {
		fallbackFixture := newWakeOutcomeTestFixture(t, "wake-scalar-fallback:")
		recorder := newRecordingPushSender()
		fallbackFixture.push.sender = recorder.Send

		const directPeer = "wake-scalar-direct-peer"
		plan367RegisterEncrypted(
			t,
			fallbackFixture.pushBackend,
			directPeer,
			"wake-scalar-direct-token",
			"android",
			opaqueWakeCapability,
			wakeOutcomeCapability,
		)
		directMessage := `{"type":"chat_message","version":"2","messageId":"\uD800","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`
		if result, err := fallbackFixture.inbox.Store(directPeer, inboxMessage{
			ID:        "wake-scalar-direct-entry",
			From:      "wake-scalar-direct-sender",
			Message:   directMessage,
			Timestamp: fallbackFixture.now.UnixMilli(),
		}); err != nil || result != InboxStoreResultStored {
			t.Fatalf("malformed-scalar direct store = %q/%v", result, err)
		}
		waitForWakeProviderCalls(t, recorder, 1)
		if count := fallbackFixture.inboxBackend.Count(directPeer); count != 1 {
			t.Fatalf("malformed-scalar direct durable events = %d, want 1", count)
		}
		if count := fallbackFixture.state.client.HLen(
			context.Background(),
			fallbackFixture.state.stateKey(directPeer),
		).Val(); count != 0 {
			t.Fatalf("malformed-scalar direct wake records = %d, want 0", count)
		}

		const (
			groupPeer   = "wake-scalar-group-peer"
			groupSender = "wake-scalar-group-sender"
			groupID     = "wake-scalar-group"
		)
		plan367RegisterEncrypted(
			t,
			fallbackFixture.pushBackend,
			groupPeer,
			"wake-scalar-group-token",
			"android",
			opaqueWakeCapability,
			wakeOutcomeCapability,
		)
		groupMessage := `{"type":"group_message","groupId":"wake-scalar-group","messageId":"wake-scalar-group-alias","logicalDeliveryId":"\uDC00"}`
		if err := fallbackFixture.group.StoreWithPushRecipients(
			groupID,
			groupSender,
			groupMessage,
			[]string{groupSender, groupPeer},
		); err != nil {
			t.Fatalf("malformed-scalar group store: %v", err)
		}
		waitForWakeProviderCalls(t, recorder, 2)
		if events := fallbackFixture.groupBackend.RetrieveSince(groupID, 0); len(events) != 1 {
			t.Fatalf("malformed-scalar group durable events = %d, want 1", len(events))
		}
		if count := fallbackFixture.state.client.HLen(
			context.Background(),
			fallbackFixture.state.stateKey(groupPeer),
		).Val(); count != 0 {
			t.Fatalf("malformed-scalar group wake records = %d, want 0", count)
		}
		if count := fallbackFixture.state.client.ZCard(
			context.Background(),
			fallbackFixture.state.dueKey(),
		).Val(); count != 0 {
			t.Fatalf("malformed-scalar fallback due members = %d, want 0", count)
		}
	})

	memoryTokens := newMemoryPushTokenStore()
	if err := memoryTokens.RegisterToken(
		"memory-peer", "memory-token", "android", opaqueWakeCapability, wakeOutcomeCapability,
	); err != nil {
		t.Fatal(err)
	}
	memoryPush := NewPushServiceWithBackend(memoryTokens)
	recorder := newRecordingPushSender()
	memoryPush.sender = recorder.Send
	memoryInbox := NewInboxStore(memoryPush)
	if _, ok := memoryInbox.backend.(interface {
		StoreWithWakeOutcome(string, inboxMessage, wakeOutcomeAdmission) (InboxStoreResult, wakeOutcomeAdmissionStatus, error)
	}); ok {
		t.Fatal("memory backend unexpectedly exposes durable wake admission")
	}
	if result, err := memoryInbox.Store("memory-peer", inboxMessage{
		ID: "memory-event", From: "sender", Message: wakeOutcomeDirectEnvelope("memory-event"),
		Timestamp: fixture.now.UnixMilli(),
	}); err != nil || result != InboxStoreResultStored {
		t.Fatalf("memory store = %q, %v", result, err)
	}
	waitForWakeProviderCalls(t, recorder, 1)
}

func TestRelayNotificationClosure_WakeOutcomeAtomicStoreAndDeliveryAckSeparation(t *testing.T) {
	t.Run("wrong-typed due index cannot partially commit", func(t *testing.T) {
		cases := []struct {
			name     string
			producer wakeOutcomeProducerKind
			message  func(string) string
			store    func(
				t *testing.T,
				fixture *wakeOutcomeTestFixture,
				peerID string,
				message string,
				admission wakeOutcomeAdmission,
			) error
			assertNoEvent func(t *testing.T, fixture *wakeOutcomeTestFixture, peerID string)
		}{
			{
				name:     "direct",
				producer: wakeOutcomeProducerDirectMessage,
				message: func(peerID string) string {
					return wakeOutcomeDirectEnvelope(peerID + "-event")
				},
				store: func(
					t *testing.T,
					fixture *wakeOutcomeTestFixture,
					peerID string,
					message string,
					admission wakeOutcomeAdmission,
				) error {
					t.Helper()
					_, _, err := fixture.inboxBackend.StoreWithWakeOutcome(
						peerID,
						inboxMessage{
							ID: peerID + "-entry", From: "sender", Message: message,
							Timestamp: fixture.now.UnixMilli(),
						},
						admission,
					)
					return err
				},
				assertNoEvent: func(t *testing.T, fixture *wakeOutcomeTestFixture, peerID string) {
					t.Helper()
					if count := fixture.inboxBackend.Count(peerID); count != 0 {
						t.Fatalf("direct event count=%d", count)
					}
				},
			},
			{
				name:     "protected",
				producer: wakeOutcomeProducerDirectMessage,
				message: func(peerID string) string {
					return wakeOutcomeDirectEnvelope(peerID + "-event")
				},
				store: func(
					t *testing.T,
					fixture *wakeOutcomeTestFixture,
					peerID string,
					message string,
					admission wakeOutcomeAdmission,
				) error {
					t.Helper()
					_, _, _, err := fixture.inboxBackend.StoreAckCustodyWithWakeOutcome(
						peerID,
						inboxMessage{
							ID: peerID + "-entry", From: "sender", Message: message,
							Timestamp: fixture.now.UnixMilli(),
						},
						peerID+"-dedupe",
						admission,
					)
					return err
				},
				assertNoEvent: func(t *testing.T, fixture *wakeOutcomeTestFixture, peerID string) {
					t.Helper()
					ctx := context.Background()
					if protected := fixture.state.client.LLen(
						ctx,
						fixture.inboxBackend.ackCustodyKey(peerID),
					).Val(); protected != 0 {
						t.Fatalf("protected event count=%d", protected)
					}
					if shadow := fixture.state.client.LLen(
						ctx,
						fixture.inboxBackend.key(peerID),
					).Val(); shadow != 0 {
						t.Fatalf("protected shadow event count=%d", shadow)
					}
				},
			},
			{
				name:     "group",
				producer: wakeOutcomeProducerGroupMessage,
				message: func(peerID string) string {
					return wakeOutcomeGroupEnvelope(peerID+"-logical", peerID+"-message")
				},
				store: func(
					t *testing.T,
					fixture *wakeOutcomeTestFixture,
					peerID string,
					message string,
					admission wakeOutcomeAdmission,
				) error {
					t.Helper()
					_, _, err := fixture.groupBackend.StoreWithRecipientsAndWakeOutcomes(
						peerID+"-group",
						"sender",
						message,
						[]string{peerID},
						[]wakeOutcomeAdmission{admission},
					)
					return err
				},
				assertNoEvent: func(t *testing.T, fixture *wakeOutcomeTestFixture, peerID string) {
					t.Helper()
					if count := fixture.state.client.LLen(
						context.Background(),
						fixture.groupBackend.key(peerID+"-group"),
					).Val(); count != 0 {
						t.Fatalf("group event count=%d", count)
					}
				},
			},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				prefix := "wake-atomic-wrong-type-" + tc.name + ":"
				fixture := newWakeOutcomeTestFixture(t, prefix)
				peerID := "wrong-type-" + tc.name + "-peer"
				message := tc.message(peerID)
				admission := wakeOutcomeAdmissionForTest(
					t,
					fixture,
					peerID,
					message,
					tc.producer,
				)
				if err := fixture.state.client.Set(
					context.Background(),
					fixture.state.dueKey(),
					"not-a-zset",
					0,
				).Err(); err != nil {
					t.Fatalf("poison due index type: %v", err)
				}
				if err := tc.store(t, fixture, peerID, message, admission); err == nil {
					t.Fatal("wrong-typed due index unexpectedly accepted atomic store")
				}
				tc.assertNoEvent(t, fixture, peerID)
				if fields := fixture.state.client.HLen(
					context.Background(),
					fixture.state.stateKey(peerID),
				).Val(); fields != 0 {
					t.Fatalf("wake state fields=%d", fields)
				}
				if value := fixture.state.client.Get(
					context.Background(),
					fixture.state.dueKey(),
				).Val(); value != "not-a-zset" {
					t.Fatalf("due-index sentinel changed to %q", value)
				}
				if keyType := fixture.state.client.Type(
					context.Background(),
					fixture.state.dueKey(),
				).Val(); keyType != "string" {
					t.Fatalf("due index type = %q, want unchanged string with zero ZSET members", keyType)
				}
			})
		}
	})

	fixture := newWakeOutcomeTestFixture(t, "wake-atomic:")
	message := wakeOutcomeDirectEnvelope("atomic-direct")
	admission := wakeOutcomeAdmissionForTest(
		t, fixture, "atomic-peer", message, wakeOutcomeProducerDirectMessage,
	)
	entry := inboxMessage{ID: "atomic-entry", From: "sender", Message: message, Timestamp: fixture.now.UnixMilli()}
	result, status, err := fixture.inboxBackend.StoreWithWakeOutcome("atomic-peer", entry, admission)
	if err != nil || result != InboxStoreResultStored || status != wakeOutcomeAdmissionDelayed {
		t.Fatalf("atomic direct store = %q/%q/%v", result, status, err)
	}
	if score, err := fixture.state.client.ZScore(context.Background(), fixture.state.dueKey(), wakeOutcomeDueMember("atomic-peer", admission.correlation)).Result(); err != nil || int64(score) != fixture.now.Add(wakeOutcomeDebounce).UnixMilli() {
		t.Fatalf("due index = %v/%v", score, err)
	}
	if removed, err := fixture.inboxBackend.Ack("atomic-peer", []string{entry.ID}); err != nil || removed != 1 {
		t.Fatalf("delivery ACK = %d/%v", removed, err)
	}
	if record := requireWakeOutcomeRecord(t, fixture.state, "atomic-peer", admission.correlation); record.State != wakeOutcomeStatePending {
		t.Fatalf("delivery ACK changed wake state to %q", record.State)
	}
	if duplicate, _, err := fixture.inboxBackend.StoreWithWakeOutcome("atomic-peer", entry, admission); err != nil || duplicate != InboxStoreResultStored {
		// The delivery ACK intentionally removed only the event. A replay is a new
		// event row but reuses the still-pending obligation rather than duplicating it.
		t.Fatalf("post-ACK replay = %q/%v", duplicate, err)
	}

	beforePeer := "outcome-before-store"
	beforeMessage := wakeOutcomeDirectEnvelope("outcome-before-event")
	beforeAdmission := wakeOutcomeAdmissionForTest(
		t, fixture, beforePeer, beforeMessage, wakeOutcomeProducerDirectMessage,
	)
	if _, err := fixture.state.complete(beforePeer, beforeAdmission.correlation); err != nil {
		t.Fatalf("outcome before store: %v", err)
	}
	result, status, err = fixture.inboxBackend.StoreWithWakeOutcome(
		beforePeer,
		inboxMessage{ID: "before-entry", From: "sender", Message: beforeMessage, Timestamp: fixture.now.UnixMilli()},
		beforeAdmission,
	)
	if err != nil || result != InboxStoreResultStored || status != wakeOutcomeAdmissionSuppressed {
		t.Fatalf("tombstone store = %q/%q/%v", result, status, err)
	}

	protectedMessage := wakeOutcomeDirectEnvelope("protected-event")
	protectedAdmission := wakeOutcomeAdmissionForTest(
		t, fixture, "protected-peer", protectedMessage, wakeOutcomeProducerDirectMessage,
	)
	protectedResult, protectedStored, protectedStatus, err := fixture.inboxBackend.StoreAckCustodyWithWakeOutcome(
		"protected-peer",
		inboxMessage{ID: "protected-entry", From: "sender", Message: protectedMessage, Timestamp: fixture.now.UnixMilli()},
		"protected-dedupe",
		protectedAdmission,
	)
	if err != nil || protectedResult != InboxStoreResultStored || protectedStatus != wakeOutcomeAdmissionDelayed {
		t.Fatalf("protected atomic store = %q/%q/%v", protectedResult, protectedStatus, err)
	}
	if removed, err := fixture.inboxBackend.AckAckCustody(
		"protected-peer",
		[]string{protectedStored.ID},
	); err != nil || removed != 1 {
		t.Fatalf("protected delivery ACK = %d/%v", removed, err)
	}
	if record := requireWakeOutcomeRecord(
		t,
		fixture.state,
		"protected-peer",
		protectedAdmission.correlation,
	); record.State != wakeOutcomeStatePending {
		t.Fatalf("protected delivery ACK changed wake state to %q", record.State)
	}

	groupMessage := wakeOutcomeGroupEnvelope("group-logical", "group-alias")
	groupAdmission := wakeOutcomeAdmissionForTest(
		t, fixture, "group-peer", groupMessage, wakeOutcomeProducerGroupMessage,
	)
	groupResult, groupStatuses, err := fixture.groupBackend.StoreWithRecipientsAndWakeOutcomes(
		"group-id", "sender", groupMessage, []string{"sender", "group-peer"}, []wakeOutcomeAdmission{groupAdmission},
	)
	if err != nil || groupResult != GroupInboxStoreResultStored || len(groupStatuses) != 1 || groupStatuses[0].status != wakeOutcomeAdmissionDelayed {
		t.Fatalf("group atomic store = %q/%#v/%v", groupResult, groupStatuses, err)
	}

	capPeer := "capacity-peer"
	records := make(map[string]redisWakeOutcomeRecord, wakeOutcomePerPeerCapacity)
	for index := 0; index < wakeOutcomePerPeerCapacity; index++ {
		records[fmt.Sprintf("%064x", index+1)] = redisWakeOutcomeRecord{
			State: wakeOutcomeStateCompleted, Revision: 1,
			ExpiresAtMs: fixture.now.Add(wakeOutcomeRetention).UnixMilli(), Policy: wakeOutcomePolicyNone,
		}
	}
	_, err = fixture.state.client.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
		return queueWakeOutcomeHash(context.Background(), pipe, fixture.state.stateKey(capPeer), records)
	})
	if err != nil {
		t.Fatalf("fill capacity: %v", err)
	}
	if _, err := fixture.state.complete(capPeer, strings.Repeat("f", 64)); !errors.Is(err, errWakeOutcomeCapacity) {
		t.Fatalf("absent completion at cap error = %v", err)
	}
	capMessage := wakeOutcomeDirectEnvelope("capacity-event")
	capAdmission := wakeOutcomeAdmissionForTest(t, fixture, capPeer, capMessage, wakeOutcomeProducerDirectMessage)
	capacityRecorder := newRecordingPushSender()
	fixture.push.sender = capacityRecorder.Send
	result, err = fixture.inbox.Store(
		capPeer,
		inboxMessage{ID: "capacity-entry", From: "sender", Message: capMessage, Timestamp: fixture.now.UnixMilli()},
	)
	if err != nil || result != InboxStoreResultStored || fixture.inboxBackend.Count(capPeer) != 1 {
		t.Fatalf("capacity fallback = %q/%v count=%d", result, err, fixture.inboxBackend.Count(capPeer))
	}
	waitForWakeProviderCalls(t, capacityRecorder, 1)
	if message := capacityRecorder.LastMessage(); message == nil ||
		message.Data["v"] != "1" || message.Data["w"] != "1" {
		t.Fatalf("capacity fallback provider payload = %#v, want immediate fixed wake", message)
	}
	if exists := fixture.state.client.HExists(
		context.Background(),
		fixture.state.stateKey(capPeer),
		capAdmission.correlation,
	).Val(); exists {
		t.Fatal("capacity fallback committed a wake obligation")
	}

	tombstoneKey := fixture.state.stateKey(beforePeer)
	if ttl := fixture.state.client.PTTL(context.Background(), tombstoneKey).Val(); ttl != wakeOutcomeRetention {
		t.Fatalf("completed tombstone physical TTL = %s, want %s", ttl, wakeOutcomeRetention)
	}
	fixture.redis.FastForward(wakeOutcomeRetention - time.Millisecond)
	if exists := fixture.state.client.Exists(context.Background(), tombstoneKey).Val(); exists != 1 {
		t.Fatalf("completed tombstone expired before replay horizon: exists=%d", exists)
	}
	fixture.redis.FastForward(time.Millisecond)
	if exists := fixture.state.client.Exists(context.Background(), tombstoneKey).Val(); exists != 0 {
		t.Fatalf("inactive completed tombstone survived replay horizon: exists=%d", exists)
	}
}

func TestRelayNotificationClosure_WakeOutcomeAuthenticatedProtocolAndIdempotence(t *testing.T) {
	correlation := strings.Repeat("a", 64)
	valid := fmt.Sprintf(`{"action":"%s","correlation":"%s","wakeNotRequired":true}`, wakeOutcomeAction, correlation)
	if _, err := decodeWakeOutcomeRequest([]byte(valid)); err != nil {
		t.Fatalf("valid strict action: %v", err)
	}
	for _, invalid := range []string{
		fmt.Sprintf(`{"action":"%s","correlation":"%s","wakeNotRequired":false}`, wakeOutcomeAction, correlation),
		fmt.Sprintf(`{"action":"%s","correlation":"%s","wakeNotRequired":true,"to":"victim"}`, wakeOutcomeAction, correlation),
		fmt.Sprintf(`{"action":"%s","correlation":"%s","correlation":"%s","wakeNotRequired":true}`, wakeOutcomeAction, correlation, correlation),
		fmt.Sprintf(`{"action":"%s","correlation":"%s","wakeNotRequired":true}`, wakeOutcomeAction, strings.ToUpper(correlation)),
	} {
		if _, err := decodeWakeOutcomeRequest([]byte(invalid)); err == nil {
			t.Fatalf("strict decoder accepted %s", invalid)
		}
	}

	fixture := newWakeOutcomeTestFixture(t, "wake-protocol:")
	env := setupInboxStreamEnv(t, fixture.inbox, fixture.group)
	sendOutcomeTo := func(target *inboxStreamEnv, client host.Host, body string) inboxResponse {
		t.Helper()
		stream, err := client.NewStream(context.Background(), target.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open outcome stream: %v", err)
		}
		defer stream.Close()
		if err := writeFrame(stream, []byte(body)); err != nil {
			t.Fatalf("write outcome frame: %v", err)
		}
		return recvInboxResp(t, stream)
	}
	sendOutcome := func(client host.Host, body string) inboxResponse {
		t.Helper()
		return sendOutcomeTo(env, client, body)
	}
	senderPeerID := env.sender.ID().String()
	intruderPeerID := env.intruder.ID().String()

	absentCorrelation := strings.Repeat("b", 64)
	absentBody := fmt.Sprintf(
		`{"action":"%s","correlation":"%s","wakeNotRequired":true}`,
		wakeOutcomeAction,
		absentCorrelation,
	)
	if response := sendOutcome(env.sender, absentBody); response.Status != "OK" || response.Error != "" {
		t.Fatalf("authenticated absent response = %#v", response)
	}
	if record := requireWakeOutcomeRecord(t, fixture.state, senderPeerID, absentCorrelation); record.State != wakeOutcomeStateCompleted {
		t.Fatalf("authenticated absent state = %q", record.State)
	}
	if _, err := fixture.state.client.HGet(
		context.Background(), fixture.state.stateKey(intruderPeerID), absentCorrelation,
	).Result(); !errors.Is(err, redis.Nil) {
		t.Fatalf("authenticated sender outcome crossed namespaces: %v", err)
	}
	if response := sendOutcome(env.sender, absentBody); response.Status != "OK" || response.Error != "" {
		t.Fatalf("authenticated idempotent response = %#v", response)
	}

	pendingMessage := wakeOutcomeDirectEnvelope("pending-protocol-event")
	pendingAdmission := wakeOutcomeAdmissionForTest(
		t,
		fixture,
		senderPeerID,
		pendingMessage,
		wakeOutcomeProducerDirectMessage,
	)
	if _, _, err := fixture.inboxBackend.StoreWithWakeOutcome(
		senderPeerID,
		inboxMessage{ID: "pending-entry", From: "sender", Message: pendingMessage, Timestamp: fixture.now.UnixMilli()},
		pendingAdmission,
	); err != nil {
		t.Fatal(err)
	}
	pendingBody := fmt.Sprintf(
		`{"action":"%s","correlation":"%s","wakeNotRequired":true}`,
		wakeOutcomeAction,
		pendingAdmission.correlation,
	)
	if response := sendOutcome(env.sender, pendingBody); response.Status != "OK" || response.Error != "" {
		t.Fatalf("authenticated pending response = %#v", response)
	}
	if record := requireWakeOutcomeRecord(t, fixture.state, senderPeerID, pendingAdmission.correlation); record.State != wakeOutcomeStateCompleted {
		t.Fatalf("pending outcome state = %q", record.State)
	}

	claimedMessage := wakeOutcomeDirectEnvelope("claimed-protocol-event")
	claimedAdmission := wakeOutcomeAdmissionForTest(
		t,
		fixture,
		senderPeerID,
		claimedMessage,
		wakeOutcomeProducerDirectMessage,
	)
	if _, _, err := fixture.inboxBackend.StoreWithWakeOutcome(
		senderPeerID,
		inboxMessage{ID: "claimed-entry", From: "sender", Message: claimedMessage, Timestamp: fixture.now.UnixMilli()},
		claimedAdmission,
	); err != nil {
		t.Fatal(err)
	}
	claims, err := fixture.state.claimDue(fixture.now.Add(wakeOutcomeDebounce), 10)
	if err != nil || len(claims) != 1 || claims[0].correlation != claimedAdmission.correlation {
		t.Fatalf("claim = %#v/%v", claims, err)
	}
	claimedBody := fmt.Sprintf(
		`{"action":"%s","correlation":"%s","wakeNotRequired":true}`,
		wakeOutcomeAction,
		claimedAdmission.correlation,
	)
	if response := sendOutcome(env.intruder, claimedBody); response.Status != "OK" || response.Error != "" {
		t.Fatalf("wrong-peer scoped response = %#v", response)
	}
	if record := requireWakeOutcomeRecord(t, fixture.state, intruderPeerID, claimedAdmission.correlation); record.State != wakeOutcomeStateCompleted {
		t.Fatalf("wrong-peer namespace state = %q", record.State)
	}
	if record := requireWakeOutcomeRecord(t, fixture.state, senderPeerID, claimedAdmission.correlation); record.State != wakeOutcomeStateClaimed {
		t.Fatalf("wrong peer changed target state to %q", record.State)
	}
	if response := sendOutcome(env.sender, claimedBody); response.Status != "OK" || response.Error != "" {
		t.Fatalf("authenticated claimed response = %#v", response)
	}
	if record := requireWakeOutcomeRecord(t, fixture.state, senderPeerID, claimedAdmission.correlation); record.State != wakeOutcomeStateClaimed {
		t.Fatalf("claimed outcome changed state to %q", record.State)
	}

	invalidCorrelation := strings.Repeat("c", 64)
	invalidBody := fmt.Sprintf(
		`{"action":"%s","correlation":"%s","wakeNotRequired":true,"to":"victim"}`,
		wakeOutcomeAction,
		invalidCorrelation,
	)
	if response := sendOutcome(env.sender, invalidBody); response.Status != "ERROR" || response.Error != "invalid wake outcome request" || strings.Contains(response.Error, invalidCorrelation) {
		t.Fatalf("strict wire rejection = %#v", response)
	}
	if _, err := fixture.state.client.HGet(
		context.Background(), fixture.state.stateKey(senderPeerID), invalidCorrelation,
	).Result(); !errors.Is(err, redis.Nil) {
		t.Fatalf("invalid outcome mutated state: %v", err)
	}

	t.Run("memory participants are terminal while Redis ownership remains durable", func(t *testing.T) {
		const mixedEvent = "wake-protocol-mixed-event"
		mixedAdmission := wakeOutcomeAdmissionForTest(
			t,
			fixture,
			senderPeerID,
			wakeOutcomeDirectEnvelope(mixedEvent),
			wakeOutcomeProducerDirectMessage,
		)
		if _, _, err := fixture.inboxBackend.StoreWithWakeOutcome(
			senderPeerID,
			inboxMessage{
				ID: "wake-protocol-mixed-entry", From: "sender",
				Message: wakeOutcomeDirectEnvelope(mixedEvent), Timestamp: fixture.now.UnixMilli(),
			},
			mixedAdmission,
		); err != nil {
			t.Fatalf("store mixed Redis obligation: %v", err)
		}
		fixture.inbox.SetWakeOutcomeAdmissionEnabled(false)
		mixedBody := fmt.Sprintf(
			`{"action":"%s","correlation":"%s","wakeNotRequired":true}`,
			wakeOutcomeAction,
			mixedAdmission.correlation,
		)

		memoryInbox := NewInboxStore(nil)
		memoryGroup := NewGroupInboxStore(16, groupMessageTTL)
		memoryEnv := setupInboxStreamEnv(t, memoryInbox, memoryGroup)
		for _, enabled := range []bool{false, true} {
			memoryInbox.SetWakeOutcomeAdmissionEnabled(enabled)
			response := sendOutcomeTo(memoryEnv, memoryEnv.sender, mixedBody)
			if response.Status != "OK" || response.Error != "" {
				t.Fatalf("memory terminal outcome (admission=%v) = %#v", enabled, response)
			}
		}

		if response := sendOutcome(env.sender, mixedBody); response.Status != "OK" || response.Error != "" {
			t.Fatalf("admission-off Redis owner outcome = %#v", response)
		}
		if record := requireWakeOutcomeRecord(
			t,
			fixture.state,
			senderPeerID,
			mixedAdmission.correlation,
		); record.State != wakeOutcomeStateCompleted {
			t.Fatalf("admission-off Redis owner state = %#v", record)
		}
	})

	t.Run("Redis completion faults remain retryable", func(t *testing.T) {
		faultFixture := newWakeOutcomeTestFixture(t, "wake-protocol-fault:")
		faultEnv := setupInboxStreamEnv(t, faultFixture.inbox, faultFixture.group)
		if err := faultFixture.state.client.Set(
			context.Background(),
			faultFixture.state.dueKey(),
			"wrong-type",
			0,
		).Err(); err != nil {
			t.Fatalf("seed wrong-type completion due index: %v", err)
		}
		body := fmt.Sprintf(
			`{"action":"%s","correlation":"%s","wakeNotRequired":true}`,
			wakeOutcomeAction,
			strings.Repeat("d", 64),
		)
		response := sendOutcomeTo(faultEnv, faultEnv.sender, body)
		if response.Status != "ERROR" || response.Error != "wake outcome retryable" {
			t.Fatalf("Redis completion fault response = %#v", response)
		}
	})
}

func TestRelayNotificationClosure_WakeOutcomeDeadlineClaimRaceAndRecovery(t *testing.T) {
	t.Run("production main starts exactly one wake coordinator", func(t *testing.T) {
		const activation = "stores.WakeOutcomeCoordinator.Start(ctx)"
		source, err := os.ReadFile("main.go")
		if err != nil {
			t.Fatalf("read production main.go: %v", err)
		}
		if count := strings.Count(string(source), activation); count != 1 {
			t.Fatalf("production coordinator activation count = %d, want exactly one", count)
		}
		parsed, err := parser.ParseFile(token.NewFileSet(), "main.go", source, 0)
		if err != nil {
			t.Fatalf("parse production main.go: %v", err)
		}
		activationCalls := 0
		ast.Inspect(parsed, func(node ast.Node) bool {
			call, ok := node.(*ast.CallExpr)
			if !ok || len(call.Args) != 1 {
				return true
			}
			start, ok := call.Fun.(*ast.SelectorExpr)
			if !ok || start.Sel.Name != "Start" {
				return true
			}
			coordinator, ok := start.X.(*ast.SelectorExpr)
			if !ok || coordinator.Sel.Name != "WakeOutcomeCoordinator" {
				return true
			}
			stores, ok := coordinator.X.(*ast.Ident)
			ctx, ctxOK := call.Args[0].(*ast.Ident)
			if ok && ctxOK && stores.Name == "stores" && ctx.Name == "ctx" {
				activationCalls++
			}
			return true
		})
		if activationCalls != 1 {
			t.Fatalf("production coordinator AST activations = %d, want exactly one", activationCalls)
		}
	})

	t.Run("production bootstrap owns one Redis coordinator and no memory owner", func(t *testing.T) {
		limits := DefaultServerLimits()
		memoryStores, err := newControlPlaneStores(
			context.Background(),
			backendConfig{Kind: backendKindMemory},
			limits,
			"",
		)
		if err != nil {
			t.Fatalf("build memory control-plane stores: %v", err)
		}
		defer memoryStores.Close()
		if memoryStores.WakeOutcomeBackend != nil || memoryStores.WakeOutcomeCoordinator != nil {
			t.Fatalf(
				"memory wake owners = backend %#v coordinator %#v, want nil/nil",
				memoryStores.WakeOutcomeBackend,
				memoryStores.WakeOutcomeCoordinator,
			)
		}
		if memoryStores.Inbox.WakeOutcomeAdmissionEnabled() ||
			memoryStores.GroupInbox.WakeOutcomeAdmissionEnabled() {
			t.Fatal("memory bootstrap enabled durable wake admission")
		}

		redisServer := miniredis.RunT(t)
		redisStores, err := newControlPlaneStores(
			context.Background(),
			backendConfig{
				Kind:        backendKindRedis,
				RedisURL:    "redis://" + redisServer.Addr(),
				RedisPrefix: "wake-bootstrap:",
			},
			limits,
			"",
		)
		if err != nil {
			t.Fatalf("build Redis control-plane stores: %v", err)
		}
		defer redisStores.Close()
		if redisStores.WakeOutcomeBackend == nil || redisStores.WakeOutcomeCoordinator == nil {
			t.Fatalf(
				"Redis wake owners = backend %#v coordinator %#v, want both nonnil",
				redisStores.WakeOutcomeBackend,
				redisStores.WakeOutcomeCoordinator,
			)
		}
		if redisStores.WakeOutcomeCoordinator.backend != redisStores.WakeOutcomeBackend {
			t.Fatal("Redis coordinator does not share the bootstrap wake backend")
		}
		redisInboxBackend, ok := redisStores.InboxBackend.(*redisInboxBackend)
		if !ok || redisInboxBackend.wakeOutcomes != redisStores.WakeOutcomeBackend {
			t.Fatal("Redis inbox does not share the bootstrap wake backend")
		}
		redisGroupBackend, ok := redisStores.GroupInboxBackend.(*redisGroupInboxBackend)
		if !ok || redisGroupBackend.wakeOutcomes != redisStores.WakeOutcomeBackend {
			t.Fatal("Redis group inbox does not share the bootstrap wake backend")
		}
		if !redisStores.Inbox.WakeOutcomeAdmissionEnabled() ||
			!redisStores.GroupInbox.WakeOutcomeAdmissionEnabled() {
			t.Fatal("Redis bootstrap did not enable both atomic wake admissions")
		}
		if reflect.ValueOf(redisStores.WakeOutcomeCoordinator.send).Pointer() !=
			reflect.ValueOf(redisStores.Push.sendWakeOutcomeThroughGateway).Pointer() {
			t.Fatal("Redis coordinator is not bound to the production wake gateway")
		}

		source, err := os.ReadFile("server_bootstrap.go")
		if err != nil {
			t.Fatalf("read production server_bootstrap.go: %v", err)
		}
		if count := strings.Count(string(source), "WakeOutcomeCoordinator:"); count != 1 {
			t.Fatalf("production coordinator assignments = %d, want exactly one", count)
		}
		parsed, err := parser.ParseFile(token.NewFileSet(), "server_bootstrap.go", source, 0)
		if err != nil {
			t.Fatalf("parse production server_bootstrap.go: %v", err)
		}
		constructorCalls := 0
		ast.Inspect(parsed, func(node ast.Node) bool {
			call, ok := node.(*ast.CallExpr)
			if !ok || len(call.Args) != 3 {
				return true
			}
			constructor, ok := call.Fun.(*ast.Ident)
			if !ok || constructor.Name != "newWakeOutcomeCoordinator" {
				return true
			}
			backend, backendOK := call.Args[0].(*ast.Ident)
			gateway, gatewayOK := call.Args[1].(*ast.SelectorExpr)
			push, pushOK := gateway.X.(*ast.Ident)
			clock, clockOK := call.Args[2].(*ast.SelectorExpr)
			timePackage, timeOK := clock.X.(*ast.Ident)
			if backendOK && gatewayOK && pushOK && clockOK && timeOK &&
				backend.Name == "wakeOutcomeBackend" &&
				push.Name == "push" && gateway.Sel.Name == "sendWakeOutcomeThroughGateway" &&
				timePackage.Name == "time" && clock.Sel.Name == "Now" {
				constructorCalls++
			}
			return true
		})
		if constructorCalls != 1 {
			t.Fatalf("production wake coordinator constructors = %d, want exactly one exact owner", constructorCalls)
		}
	})

	t.Run("Start owns due provider invocation and settlement", func(t *testing.T) {
		cases := []struct {
			name        string
			result      pushDeliveryResult
			wantState   wakeOutcomeState
			wantRetries int
		}{
			{name: "accepted", result: pushDeliveryAccepted, wantState: wakeOutcomeStateCompleted},
			{name: "retryable", result: pushDeliveryRetryable, wantState: wakeOutcomeStatePending, wantRetries: 1},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				startFixture := newWakeOutcomeTestFixture(t, "wake-start-"+tc.name+":")
				peerID := "wake-start-" + tc.name + "-peer"
				message := wakeOutcomeDirectEnvelope("wake-start-" + tc.name + "-event")
				admission := wakeOutcomeAdmissionForTest(
					t,
					startFixture,
					peerID,
					message,
					wakeOutcomeProducerDirectMessage,
				)
				if _, _, err := startFixture.inboxBackend.StoreWithWakeOutcome(
					peerID,
					inboxMessage{
						ID:        "wake-start-" + tc.name + "-entry",
						From:      "sender",
						Message:   message,
						Timestamp: startFixture.now.UnixMilli(),
					},
					admission,
				); err != nil {
					t.Fatalf("store due row: %v", err)
				}

				providerEntered := make(chan struct{}, 1)
				due := startFixture.now.Add(wakeOutcomeDebounce)
				coordinator := newWakeOutcomeCoordinator(
					startFixture.state,
					func(ctx context.Context, gotPeer string, policy wakeOutcomeRoutePolicy) pushDeliveryResult {
						if gotPeer != peerID || policy != wakeOutcomePolicyNone {
							t.Errorf("Start provider authority = %q/%q", gotPeer, policy)
						}
						if _, ok := ctx.Deadline(); !ok {
							t.Error("Start provider context has no deadline")
						}
						providerEntered <- struct{}{}
						return tc.result
					},
					func() time.Time { return due },
				)
				ctx, cancel := context.WithCancel(context.Background())
				defer cancel()
				coordinator.Start(ctx)
				select {
				case <-providerEntered:
				case <-time.After(2 * time.Second):
					t.Fatal("Start did not invoke the due provider")
				}
				deadline := time.Now().Add(2 * time.Second)
				for {
					record := requireWakeOutcomeRecord(
						t,
						startFixture.state,
						peerID,
						admission.correlation,
					)
					if record.State == tc.wantState && record.RetryCount == tc.wantRetries {
						break
					}
					if time.Now().After(deadline) {
						t.Fatalf("Start settlement = %#v, want state %q retries %d", record, tc.wantState, tc.wantRetries)
					}
					time.Sleep(time.Millisecond)
				}
				cancel()
			})
		}
	})

	fixture := newWakeOutcomeTestFixture(t, "wake-race:")
	message := wakeOutcomeDirectEnvelope("race-event")
	admission := wakeOutcomeAdmissionForTest(t, fixture, "race-peer", message, wakeOutcomeProducerDirectMessage)
	_, _, err := fixture.inboxBackend.StoreWithWakeOutcome(
		"race-peer",
		inboxMessage{ID: "race-entry", From: "sender", Message: message, Timestamp: fixture.now.UnixMilli()},
		admission,
	)
	if err != nil {
		t.Fatal(err)
	}
	due := fixture.now.Add(wakeOutcomeDebounce)
	first, err := fixture.state.claimDue(due, 10)
	if err != nil || len(first) != 1 {
		t.Fatalf("first claim = %#v/%v", first, err)
	}
	if overlap, err := fixture.state.claimDue(due, 10); err != nil || len(overlap) != 0 {
		t.Fatalf("overlap claim = %#v/%v", overlap, err)
	}
	var sends atomic.Int32
	recorder := newRecordingPushSender()
	recorder.onSend = func(ctx context.Context, _ *messaging.Message) (string, error) {
		sends.Add(1)
		if _, hasDeadline := ctx.Deadline(); !hasDeadline {
			t.Error("wake provider call had no bounded deadline")
		}
		return "accepted-wake", nil
	}
	fixture.push.sender = recorder.Send
	fixture.push.retryDelays = nil
	acceptedContext, cancelAccepted := context.WithTimeout(
		context.Background(),
		wakeOutcomeProviderTimeout,
	)
	if result := fixture.push.sendWakeOutcomeThroughGateway(
		acceptedContext,
		first[0].peerID,
		first[0].policy,
	); result != pushDeliveryAccepted {
		t.Fatalf("accepted gateway result = %q", result)
	}
	cancelAccepted()
	if record := requireWakeOutcomeRecord(t, fixture.state, "race-peer", admission.correlation); record.State != wakeOutcomeStateClaimed {
		t.Fatalf("crash-after-accept fixture settled before Redis completion: %#v", record)
	}
	second, err := fixture.state.claimDue(due.Add(wakeOutcomeClaimLease), 10)
	if err != nil || len(second) != 1 || second[0].token == first[0].token {
		t.Fatalf("reclaim = %#v/%v", second, err)
	}
	if err := fixture.state.settle(first[0], pushDeliveryAccepted, due.Add(wakeOutcomeClaimLease)); !errors.Is(err, errWakeOutcomeClaimChanged) {
		t.Fatalf("stale claimant settled successor: %v", err)
	}
	if err := fixture.state.settle(second[0], pushDeliveryRetryable, due.Add(wakeOutcomeClaimLease)); err != nil {
		t.Fatalf("retryable settle: %v", err)
	}
	record := requireWakeOutcomeRecord(t, fixture.state, "race-peer", admission.correlation)
	if record.State != wakeOutcomeStatePending || record.RetryCount != 1 {
		t.Fatalf("retry state = %#v", record)
	}

	next := time.UnixMilli(record.DueAtMs)
	fixture.state.now = func() time.Time { return next }
	coordinator := newWakeOutcomeCoordinator(
		fixture.state,
		fixture.push.sendWakeOutcomeThroughGateway,
		func() time.Time { return next },
	)
	if err := coordinator.RunDue(context.Background()); err != nil {
		t.Fatalf("coordinator RunDue: %v", err)
	}
	if sends.Load() != 2 || requireWakeOutcomeRecord(t, fixture.state, "race-peer", admission.correlation).State != wakeOutcomeStateCompleted {
		t.Fatal("accepted provider result did not complete exact claim")
	}
	retryBudget := time.Duration(0)
	for _, delay := range defaultPushRetryDelays() {
		retryBudget += delay
	}
	if wakeOutcomeClaimLease <= wakeOutcomeProviderTimeout+retryBudget {
		t.Fatalf("claim lease %s is not beyond provider timeout+retry budget %s", wakeOutcomeClaimLease, wakeOutcomeProviderTimeout+retryBudget)
	}

	blockedStore := newMemoryPushTokenStore()
	if err := blockedStore.RegisterToken("blocked-peer", "blocked-token", "android", opaqueWakeCapability); err != nil {
		t.Fatal(err)
	}
	blockedPush := NewPushServiceWithBackend(blockedStore)
	blockedPush.retryDelays = nil
	blockedEntered := make(chan struct{}, 1)
	blockedPush.sender = func(ctx context.Context, _ *messaging.Message) (string, error) {
		blockedEntered <- struct{}{}
		<-ctx.Done()
		return "", ctx.Err()
	}
	blockedContext, cancelBlocked := context.WithTimeout(context.Background(), 25*time.Millisecond)
	blockedStarted := time.Now()
	blockedResult := blockedPush.sendWakeOutcomeThroughGateway(
		blockedContext,
		"blocked-peer",
		wakeOutcomePolicyNone,
	)
	cancelBlocked()
	if blockedResult != pushDeliveryRetryable || time.Since(blockedStarted) >= wakeOutcomeClaimLease {
		t.Fatalf("blocked gateway = %q after %s", blockedResult, time.Since(blockedStarted))
	}
	select {
	case <-blockedEntered:
	default:
		t.Fatal("blocked provider boundary was not entered")
	}

	rotationStore := newMemoryPushTokenStore()
	if err := rotationStore.RegisterToken("rotation-peer", "old-token", "android", opaqueWakeCapability); err != nil {
		t.Fatal(err)
	}
	rotationProbe := &plan368BackendProbe{delegate: rotationStore}
	rotationPush := NewPushServiceWithBackend(rotationProbe)
	rotationPush.retryDelays = nil
	rotationPush.sender = func(context.Context, *messaging.Message) (string, error) {
		if err := rotationStore.RegisterToken("rotation-peer", "new-token", "android", opaqueWakeCapability); err != nil {
			t.Errorf("rotate provider route: %v", err)
		}
		return "", errors.New("registration-token-not-registered")
	}
	if result := rotationPush.sendWakeOutcomeThroughGateway(
		context.Background(),
		"rotation-peer",
		wakeOutcomePolicyNone,
	); result != pushDeliveryRetryable {
		t.Fatalf("revoke-CAS loss result = %q, want retryable", result)
	}
	currentRotation := plan367Route(t, rotationStore, "rotation-peer")
	if target := plan367Target(t, rotationStore, currentRotation); target.Token != "new-token" {
		t.Fatalf("revoke-CAS loss removed/refreshed wrong route: %#v", target)
	}
	_, _, rotationRevokes := rotationProbe.counts()
	if rotationRevokes != 1 {
		t.Fatalf("revoke-CAS attempts = %d, want 1", rotationRevokes)
	}

	terminalStore := newMemoryPushTokenStore()
	if err := terminalStore.RegisterToken("terminal-peer", "terminal-token", "android", opaqueWakeCapability); err != nil {
		t.Fatal(err)
	}
	terminalPush := NewPushServiceWithBackend(terminalStore)
	terminalPush.retryDelays = nil
	terminalPush.sender = func(context.Context, *messaging.Message) (string, error) {
		return "", errors.New("registration-token-not-registered")
	}
	terminalResult := terminalPush.sendWakeOutcomeThroughGateway(
		context.Background(),
		"terminal-peer",
		wakeOutcomePolicyNone,
	)
	if terminalResult != pushDeliveryPermanent {
		t.Fatalf("generation-safe permanent result = %q", terminalResult)
	}
	if route, lookupErr := terminalStore.LookupRoute("terminal-peer"); lookupErr != nil || route != nil {
		t.Fatalf("generation-safe permanent route = %#v/%v", route, lookupErr)
	}

	t.Run("nil provider requeues then recovers through gateway and coordinator", func(t *testing.T) {
		recoveryFixture := newWakeOutcomeTestFixture(t, "wake-provider-recovery:")
		const peerID = "wake-provider-recovery-peer"
		message := wakeOutcomeDirectEnvelope("wake-provider-recovery-event")
		admission := wakeOutcomeAdmissionForTest(
			t,
			recoveryFixture,
			peerID,
			message,
			wakeOutcomeProducerDirectMessage,
		)
		if _, _, err := recoveryFixture.inboxBackend.StoreWithWakeOutcome(
			peerID,
			inboxMessage{
				ID:        "wake-provider-recovery-entry",
				From:      "sender",
				Message:   message,
				Timestamp: recoveryFixture.now.UnixMilli(),
			},
			admission,
		); err != nil {
			t.Fatalf("store recovery row: %v", err)
		}

		current := recoveryFixture.now.Add(wakeOutcomeDebounce)
		coordinator := newWakeOutcomeCoordinator(
			recoveryFixture.state,
			recoveryFixture.push.sendWakeOutcomeThroughGateway,
			func() time.Time { return current },
		)
		// NewPushServiceWithBackend has neither an injected sender nor a live
		// provider client, so the real gateway must report retryable.
		recoveryFixture.push.sender = nil
		recoveryFixture.push.client = nil
		if err := coordinator.RunDue(context.Background()); err != nil {
			t.Fatalf("nil-provider coordinator: %v", err)
		}
		record := requireWakeOutcomeRecord(
			t,
			recoveryFixture.state,
			peerID,
			admission.correlation,
		)
		if record.State != wakeOutcomeStatePending || record.RetryCount != 1 {
			t.Fatalf("nil-provider settlement = %#v, want retryable pending", record)
		}

		recorder := newRecordingPushSender()
		recoveryFixture.push.sender = recorder.Send
		current = time.UnixMilli(record.DueAtMs)
		if err := coordinator.RunDue(context.Background()); err != nil {
			t.Fatalf("accepted recovery coordinator: %v", err)
		}
		if recorder.SendCallCount() != 1 {
			t.Fatalf("accepted recovery provider calls = %d, want 1", recorder.SendCallCount())
		}
		if record = requireWakeOutcomeRecord(
			t,
			recoveryFixture.state,
			peerID,
			admission.correlation,
		); record.State != wakeOutcomeStateCompleted {
			t.Fatalf("accepted recovery settlement = %#v", record)
		}
	})

	t.Run("expired pending and claimed heads do not block later valid provider work", func(t *testing.T) {
		expiryFixture := newWakeOutcomeTestFixture(t, "wake-expiry-prune:")
		const (
			pendingPeer = "wake-expiry-pending-peer"
			claimedPeer = "wake-expiry-claimed-peer"
			validPeer   = "wake-expiry-valid-peer"
		)
		due := expiryFixture.now.Add(wakeOutcomeDebounce)
		expires := due.Add(time.Millisecond)
		storeAdmission := func(
			peerID string,
			storedAt time.Time,
			expiresAt time.Time,
		) wakeOutcomeAdmission {
			t.Helper()
			message := wakeOutcomeDirectEnvelope(peerID + "-event")
			route := plan367RegisterEncrypted(
				t,
				expiryFixture.pushBackend,
				peerID,
				peerID+"-token",
				"android",
				opaqueWakeCapability,
				wakeOutcomeCapability,
			)
			admission, ok := newWakeOutcomeAdmission(
				peerID,
				message,
				wakeOutcomeProducerDirectMessage,
				route,
				storedAt.UnixMilli(),
				expiresAt.UnixMilli(),
			)
			if !ok {
				t.Fatalf("expiry admission rejected for %s", peerID)
			}
			if _, _, err := expiryFixture.inboxBackend.StoreWithWakeOutcome(
				peerID,
				inboxMessage{
					ID:        peerID + "-entry",
					From:      "sender",
					Message:   message,
					Timestamp: storedAt.UnixMilli(),
				},
				admission,
			); err != nil {
				t.Fatalf("store expiry %s row: %v", peerID, err)
			}
			return admission
		}
		pendingAdmission := storeAdmission(pendingPeer, expiryFixture.now, expires)
		claimedAdmission := storeAdmission(claimedPeer, expiryFixture.now, expires)
		claim, claimed, err := expiryFixture.state.claimOne(
			wakeOutcomeDueMember(claimedPeer, claimedAdmission.correlation),
			due,
		)
		if err != nil || !claimed {
			t.Fatalf("claim short-lived row = %#v/%t/%v", claim, claimed, err)
		}
		validStoredAt := expiryFixture.now.Add(wakeOutcomeClaimLease + 100*time.Millisecond)
		validDue := validStoredAt.Add(wakeOutcomeDebounce)
		validAdmission := storeAdmission(
			validPeer,
			validStoredAt,
			validStoredAt.Add(time.Hour),
		)

		var providerCalls atomic.Int32
		coordinator := newWakeOutcomeCoordinator(
			expiryFixture.state,
			func(_ context.Context, peerID string, policy wakeOutcomeRoutePolicy) pushDeliveryResult {
				providerCalls.Add(1)
				if peerID != validPeer || policy != wakeOutcomePolicyNone {
					t.Errorf("expiry provider authority = %q/%q, want later valid row", peerID, policy)
				}
				return pushDeliveryAccepted
			},
			func() time.Time { return validDue },
		)
		if err := coordinator.RunDue(context.Background()); err != nil {
			t.Fatalf("expiry pruning coordinator: %v", err)
		}
		if providerCalls.Load() != 1 {
			t.Fatalf("later valid row provider calls = %d, want 1 in the same RunDue", providerCalls.Load())
		}
		for peerID, correlation := range map[string]string{
			pendingPeer: pendingAdmission.correlation,
			claimedPeer: claimedAdmission.correlation,
		} {
			if exists := expiryFixture.state.client.HExists(
				context.Background(),
				expiryFixture.state.stateKey(peerID),
				correlation,
			).Val(); exists {
				t.Fatalf("expired %s wake record survived pruning", peerID)
			}
			if _, err := expiryFixture.state.client.ZScore(
				context.Background(),
				expiryFixture.state.dueKey(),
				wakeOutcomeDueMember(peerID, correlation),
			).Result(); !errors.Is(err, redis.Nil) {
				t.Fatalf("expired %s due member survived pruning: %v", peerID, err)
			}
		}
		if record := requireWakeOutcomeRecord(
			t,
			expiryFixture.state,
			validPeer,
			validAdmission.correlation,
		); record.State != wakeOutcomeStateCompleted {
			t.Fatalf("later valid row settlement = %#v", record)
		}
		if members := expiryFixture.state.client.ZCard(
			context.Background(),
			expiryFixture.state.dueKey(),
		).Val(); members != 0 {
			t.Fatalf("expiry/valid due members after one RunDue = %d, want 0", members)
		}
	})

	multiFixture := newWakeOutcomeTestFixture(t, "wake-race-multi:")
	multiCorrelations := make(map[string]string, 2)
	for _, peerID := range []string{"multi-due-peer-a", "multi-due-peer-b"} {
		multiMessage := wakeOutcomeDirectEnvelope(peerID + "-event")
		multiAdmission := wakeOutcomeAdmissionForTest(
			t,
			multiFixture,
			peerID,
			multiMessage,
			wakeOutcomeProducerDirectMessage,
		)
		if _, _, err := multiFixture.inboxBackend.StoreWithWakeOutcome(
			peerID,
			inboxMessage{ID: peerID + "-entry", From: "sender", Message: multiMessage, Timestamp: multiFixture.now.UnixMilli()},
			multiAdmission,
		); err != nil {
			t.Fatalf("multi-due store %s: %v", peerID, err)
		}
		multiCorrelations[peerID] = multiAdmission.correlation
	}
	multiEntered := make(chan string, 2)
	multiRelease := make(chan struct{})
	multiCoordinator := newWakeOutcomeCoordinator(
		multiFixture.state,
		func(ctx context.Context, peerID string, _ wakeOutcomeRoutePolicy) pushDeliveryResult {
			select {
			case multiEntered <- peerID:
			case <-ctx.Done():
				return pushDeliveryRetryable
			}
			select {
			case <-multiRelease:
				return pushDeliveryAccepted
			case <-ctx.Done():
				return pushDeliveryRetryable
			}
		},
		func() time.Time { return multiFixture.now.Add(wakeOutcomeDebounce) },
	)
	multiResult := make(chan error, 1)
	go func() {
		multiResult <- multiCoordinator.RunDue(context.Background())
	}()
	awaitMultiEntry := func() string {
		t.Helper()
		select {
		case peerID := <-multiEntered:
			return peerID
		case <-time.After(2 * time.Second):
			t.Fatal("timed out waiting for multi-due provider entry")
			return ""
		}
	}
	firstMultiPeer := awaitMultiEntry()
	secondMultiPeer := "multi-due-peer-a"
	if firstMultiPeer == secondMultiPeer {
		secondMultiPeer = "multi-due-peer-b"
	}
	if firstRecord := requireWakeOutcomeRecord(
		t,
		multiFixture.state,
		firstMultiPeer,
		multiCorrelations[firstMultiPeer],
	); firstRecord.State != wakeOutcomeStateClaimed {
		t.Fatalf("active multi-due provider record = %#v", firstRecord)
	}
	if secondRecord := requireWakeOutcomeRecord(
		t,
		multiFixture.state,
		secondMultiPeer,
		multiCorrelations[secondMultiPeer],
	); secondRecord.State != wakeOutcomeStatePending {
		t.Fatalf("queued multi-due record was leased before send began: %#v", secondRecord)
	}
	multiRelease <- struct{}{}
	if enteredPeer := awaitMultiEntry(); enteredPeer != secondMultiPeer {
		t.Fatalf("second multi-due provider peer = %q, want %q", enteredPeer, secondMultiPeer)
	}
	if firstRecord := requireWakeOutcomeRecord(
		t,
		multiFixture.state,
		firstMultiPeer,
		multiCorrelations[firstMultiPeer],
	); firstRecord.State != wakeOutcomeStateCompleted {
		t.Fatalf("first multi-due settle = %#v", firstRecord)
	}
	if secondRecord := requireWakeOutcomeRecord(
		t,
		multiFixture.state,
		secondMultiPeer,
		multiCorrelations[secondMultiPeer],
	); secondRecord.State != wakeOutcomeStateClaimed {
		t.Fatalf("second multi-due claim = %#v", secondRecord)
	}
	multiRelease <- struct{}{}
	select {
	case err := <-multiResult:
		if err != nil {
			t.Fatalf("multi-due coordinator: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("multi-due coordinator did not finish")
	}
}

func TestRelayNotificationClosure_WakeOutcomeCorrelationPrivacyAndEligibility(t *testing.T) {
	payload, err := os.ReadFile("../test/shared/fixtures/wake_outcome_correlation_v1.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Vectors []struct {
			Name           string                 `json:"name"`
			PhysicalPeerID string                 `json:"physicalPeerId"`
			ProducerKind   string                 `json:"producerKind"`
			EventKey       string                 `json:"eventKey"`
			Envelope       map[string]interface{} `json:"envelope"`
			Digest         string                 `json:"digest"`
		} `json:"vectors"`
	}
	if err := json.Unmarshal(payload, &fixture); err != nil {
		t.Fatal(err)
	}
	kinds := map[string]wakeOutcomeProducerKind{
		"direct_message":  wakeOutcomeProducerDirectMessage,
		"direct_reaction": wakeOutcomeProducerDirectReaction,
		"group_message":   wakeOutcomeProducerGroupMessage,
		"group_reaction":  wakeOutcomeProducerGroupReaction,
	}
	for _, vector := range fixture.Vectors {
		envelope, err := json.Marshal(vector.Envelope)
		if err != nil {
			t.Fatal(err)
		}
		got, ok := wakeOutcomeCorrelation(vector.PhysicalPeerID, kinds[vector.ProducerKind], string(envelope))
		if !ok || got != vector.Digest {
			t.Fatalf("%s correlation = %q/%v, want %q", vector.Name, got, ok, vector.Digest)
		}
		framed, ok := wakeOutcomeCorrelationForEvent(
			vector.PhysicalPeerID,
			kinds[vector.ProducerKind],
			vector.EventKey,
		)
		if !ok || framed != vector.Digest {
			t.Fatalf("%s event framing = %q/%v, want %q", vector.Name, framed, ok, vector.Digest)
		}
	}

	t.Run("JSON scalar authority is strict before normalization", func(t *testing.T) {
		correlation := func(token string) (string, bool) {
			t.Helper()
			return wakeOutcomeCorrelation(
				"wake-scalar-vector-peer",
				wakeOutcomeProducerDirectMessage,
				`{"messageId":`+token+`}`,
			)
		}

		escapedSupplementary, escapedOK := correlation(`"\uD83D\uDE00"`)
		literalSupplementary, literalOK := correlation(`"😀"`)
		if !escapedOK || !literalOK || escapedSupplementary != literalSupplementary {
			t.Fatalf(
				"surrogate-pair correlation = %q/%v versus literal %q/%v",
				escapedSupplementary,
				escapedOK,
				literalSupplementary,
				literalOK,
			)
		}
		escapedReplacement, escapedReplacementOK := correlation(`"\uFFFD"`)
		literalReplacement, literalReplacementOK := correlation(`"�"`)
		if !escapedReplacementOK || !literalReplacementOK ||
			escapedReplacement != literalReplacement {
			t.Fatalf(
				"replacement-scalar correlation = %q/%v versus literal %q/%v",
				escapedReplacement,
				escapedReplacementOK,
				literalReplacement,
				literalReplacementOK,
			)
		}
		if _, ok := correlation(`"\\uD800"`); !ok {
			t.Fatal("literal escaped text \\uD800 was rejected")
		}
		for _, token := range []string{
			`"\uFEFFboundary"`,
			`"boundary\uFEFF"`,
			`"` + "\uFEFFboundary" + `"`,
			`"boundary` + "\uFEFF" + `"`,
		} {
			if digest, ok := correlation(token); ok {
				t.Fatalf("boundary BOM token %q produced correlation %q", token, digest)
			}
		}
		if _, ok := correlation(`"interior\uFEFFscalar"`); !ok {
			t.Fatal("interior BOM scalar was rejected")
		}
		for _, peerID := range []string{"\ufeffpeer", "peer\ufeff"} {
			if digest, ok := wakeOutcomeCorrelationForEvent(
				peerID,
				wakeOutcomeProducerDirectMessage,
				"event",
			); ok {
				t.Fatalf("boundary BOM peer %q produced correlation %q", peerID, digest)
			}
		}
		if _, ok := wakeOutcomeCorrelationForEvent(
			"peer\ufeffinterior",
			wakeOutcomeProducerDirectMessage,
			"event",
		); !ok {
			t.Fatal("interior BOM peer was rejected")
		}

		invalidTokens := []string{
			`"\uD800"`,
			`"\uD800\u0041"`,
			`"\uDC00"`,
			`"` + string([]byte{0xff}) + `"`,
		}
		for _, token := range invalidTokens {
			if digest, ok := correlation(token); ok {
				t.Fatalf("invalid JSON scalar token %q produced correlation %q", token, digest)
			}
		}

		directMalformed := `{"type":"message_reaction","version":"2","eventId":"\uD800","action":"add","targetMessageId":"target","senderPeerId":"sender","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`
		if _, recognized, eligible := extractDirectReactionPushMetadata(directMalformed); !recognized || eligible {
			t.Fatalf(
				"malformed direct-reaction authority = recognized %v eligible %v, want true/false",
				recognized,
				eligible,
			)
		}

		const (
			groupID         = testCanonicalGroupReactionHandlerID
			groupSender     = "wake-scalar-reaction-sender"
			groupRecipient  = "wake-scalar-reaction-recipient"
			replacementRune = "�"
		)
		groupFixture := newSignedGroupReactionFixture(
			t,
			groupID,
			"wake-scalar-reaction-account",
			groupSender,
		)
		validGroupReaction := groupFixture.envelope(
			t,
			replacementRune,
			"add",
			"wake-scalar-reaction-base",
			"wake-scalar-reaction-target",
			[]string{groupRecipient},
			[]string{groupRecipient},
		)
		const transitionNeedle = `"transitionId":"�"`
		if strings.Count(validGroupReaction, transitionNeedle) != 1 {
			t.Fatalf("signed group fixture transition token not unique: %s", validGroupReaction)
		}
		malformedGroupReaction := strings.Replace(
			validGroupReaction,
			transitionNeedle,
			`"transitionId":"\uD800"`,
			1,
		)
		if _, recognized, valid := extractGroupReactionPushMetadata(
			malformedGroupReaction,
			groupID,
			groupSender,
			[]string{groupRecipient},
		); !recognized || valid {
			t.Fatalf(
				"malformed signed group-reaction authority = recognized %v valid %v, want true/false",
				recognized,
				valid,
			)
		}
	})

	stateFixture := newWakeOutcomeTestFixture(t, "wake-privacy:")
	message := wakeOutcomeDirectEnvelope("private-event-identifier")
	admission := wakeOutcomeAdmissionForTest(
		t, stateFixture, "private-peer-identifier", message, wakeOutcomeProducerDirectMessage,
	)
	_, _, err = stateFixture.inboxBackend.StoreWithWakeOutcome(
		"private-peer-identifier",
		inboxMessage{ID: "private-entry", From: "private-sender", Message: message, Timestamp: stateFixture.now.UnixMilli()},
		admission,
	)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := stateFixture.state.client.HGet(
		context.Background(), stateFixture.state.stateKey("private-peer-identifier"), admission.correlation,
	).Result()
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"private-event-identifier", "private-peer-identifier", "private-sender", "provider-token"} {
		if strings.Contains(raw, forbidden) {
			t.Fatalf("wake state leaked %q: %s", forbidden, raw)
		}
	}
	if !strings.Contains(raw, `"state":"pending"`) || !strings.Contains(raw, `"policy":"none"`) {
		t.Fatalf("wake state omitted finite authority: %s", raw)
	}
}
