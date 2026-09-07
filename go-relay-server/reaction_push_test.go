package main

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
)

// FCM retains at most four outstanding collapse keys per Android token. A
// per-event key therefore loses arbitrary reactions once more than four
// independent events queue. Exercise the serialized platform projection,
// preserving client event IDs and APNs retry identity independently.
func TestBuildReactionPush_DistinctQueuedEventsAreNonCollapsibleOnAndroid(t *testing.T) {
	const sender = "peer-alice"
	seenAPNSIDs := make(map[string]string)
	for index := range 6 {
		eventID := fmt.Sprintf("reaction-queued-%d", index)
		targetID := fmt.Sprintf("target-queued-%d", index)
		t.Run(eventID, func(t *testing.T) {
			envelope := directReactionEnvelope(eventID, "add", targetID, sender)
			message := buildReactionPushMessage("recipient-token", sender, envelope)
			if message == nil {
				t.Fatal("valid reaction builder returned nil")
			}
			android := projectPushMessageForPlatform(message, "android")
			encoded, err := json.Marshal(android)
			if err != nil {
				t.Fatal(err)
			}
			var wire map[string]json.RawMessage
			if err := json.Unmarshal(encoded, &wire); err != nil {
				t.Fatal(err)
			}
			var config map[string]json.RawMessage
			if err := json.Unmarshal(wire["android"], &config); err != nil {
				t.Fatal(err)
			}
			if collapse, exists := config["collapse_key"]; exists {
				t.Errorf("Android reaction must omit collapse_key; got %s", collapse)
			}
			if _, exists := config["notification"]; exists {
				t.Error("Android reaction gained an automatically collapsible notification payload")
			}
			if string(config["priority"]) != `"high"` {
				t.Errorf("Android priority = %s, want high", config["priority"])
			}
			for _, forbidden := range []string{"notification", "apns"} {
				if _, exists := wire[forbidden]; exists {
					t.Errorf("Android projection retained %s", forbidden)
				}
			}
			var data map[string]string
			if err := json.Unmarshal(wire["data"], &data); err != nil {
				t.Fatal(err)
			}
			if data["type"] != "message_reaction" || data["event_id"] != eventID ||
				data["target_message_id"] != targetID || data["sender_id"] != sender ||
				data["action"] != "add" || data["capability_version"] != directReactionCapability {
				t.Fatalf("reaction identity/security metadata changed: %#v", data)
			}
			for _, field := range []string{"kem", "ciphertext", "nonce"} {
				if data[field] == "" {
					t.Errorf("encrypted reaction field %s was lost", field)
				}
			}

			var firstAPNSID string
			for attempt := range 2 {
				retry := buildReactionPushMessage("recipient-token", sender, envelope)
				ios := projectPushMessageForPlatform(retry, "ios")
				if ios == nil || ios.APNS == nil || ios.APNS.Payload == nil || ios.APNS.Payload.Aps == nil {
					t.Fatal("iOS reaction projection lost APNs content")
				}
				identity := ios.APNS.Headers["apns-collapse-id"]
				if identity == "" || len(identity) > 64 {
					t.Fatalf("APNs event identity out of bounds: %q", identity)
				}
				if attempt == 0 {
					firstAPNSID = identity
					if priorEvent, exists := seenAPNSIDs[identity]; exists {
						t.Errorf("distinct events %s and %s share APNs collapse identity", priorEvent, eventID)
					}
					seenAPNSIDs[identity] = eventID
				} else if identity != firstAPNSID {
					t.Errorf("same-event retry changed APNs identity: %q -> %q", firstAPNSID, identity)
				}
				if ios.APNS.Payload.Aps.ThreadID != sender {
					t.Errorf("APNs thread = %q, want sender", ios.APNS.Payload.Aps.ThreadID)
				}
			}
		})
	}
}

func TestReactionAddMetadata_IsOptionalStrictAndLegacyReadable(t *testing.T) {
	valid := extractChatPushMetadata(directReactionEnvelope(
		"reaction-metadata-1",
		"add",
		"target-metadata-1",
		"peer-alice",
	))
	if !valid.ShouldNotify || valid.RouteType != "message_reaction" ||
		valid.ReactionEventID != "reaction-metadata-1" ||
		valid.ReactionAction != "add" ||
		valid.ReactionTargetMessageID != "target-metadata-1" {
		t.Fatalf("valid reaction metadata = %#v", valid)
	}

	legacy := extractChatPushMetadata(
		`{"type":"message_reaction","version":"2","senderPeerId":"peer-alice","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
	)
	if legacy.ShouldNotify || legacy.RouteType != "message_reaction" || legacy.MessageID != "" {
		t.Fatalf("legacy v2 reaction metadata = %#v, want recognized silent envelope", legacy)
	}
}

func TestBuildReactionPush_SharedBoundedIdentityFixture(t *testing.T) {
	raw, err := os.ReadFile("../test_fixtures/si5_dedupe_keys.json")
	if err != nil {
		t.Fatalf("read shared identity fixture: %v", err)
	}
	var rows []struct {
		ReactionEventID          string `json:"reactionEventId"`
		ExpectedReactionIdentity string `json:"expectedReactionIdentity"`
	}
	if err := json.Unmarshal(raw, &rows); err != nil {
		t.Fatalf("decode shared identity fixture: %v", err)
	}
	for _, row := range rows {
		if row.ReactionEventID == "" {
			continue
		}
		got := boundedReactionEventIdentity(row.ReactionEventID)
		if got != row.ExpectedReactionIdentity {
			t.Fatalf("bounded identity = %q, want shared fixture %q", got, row.ExpectedReactionIdentity)
		}
		if len(got) > 64 {
			t.Fatalf("bounded identity length = %d, exceeds 64 bytes", len(got))
		}
		return
	}
	t.Fatal("shared fixture has no direct-reaction identity row")
}

func TestInboxStore_ReactionRolloutFlagDefaultsOff(t *testing.T) {
	t.Setenv(directReactionPushEnabledEnv, "")
	if loadDirectReactionPushEnabledFromEnv() {
		t.Fatal("empty environment must leave typed reaction push disabled")
	}
	t.Setenv(directReactionPushEnabledEnv, "true")
	if !loadDirectReactionPushEnabledFromEnv() {
		t.Fatal("explicit true must enable typed reaction push")
	}
	t.Setenv(directReactionPushEnabledEnv, "unexpected")
	if loadDirectReactionPushEnabledFromEnv() {
		t.Fatal("unknown values must fail closed to disabled")
	}
}

func TestReactionCapabilityRegistrationIsAdditiveAndExact(t *testing.T) {
	store := newMemoryPushTokenStore()
	store.RegisterToken(
		"peer-capable",
		"token",
		"ios",
		"  "+directReactionCapability+"  ",
		directReactionCapability,
		"future_capability",
	)
	entry := store.LookupToken("peer-capable")
	if entry == nil || !entry.hasCapability(directReactionCapability) {
		t.Fatal("direct reaction capability was not retained")
	}
	if len(entry.Capabilities) != 2 {
		t.Fatalf("normalized capabilities = %#v, want exact deduplicated set", entry.Capabilities)
	}
	store.RegisterToken("peer-legacy", "legacy-token", "android")
	if store.LookupToken("peer-legacy").hasCapability(directReactionCapability) {
		t.Fatal("legacy registration must not gain a typed reaction capability")
	}
}
