package main

import (
	"encoding/json"
	"os"
	"testing"
)

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
