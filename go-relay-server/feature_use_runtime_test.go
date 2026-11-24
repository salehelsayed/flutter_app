package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

const featureUseTestAction = "feature_use_identity_v1"

func signedFeatureUseFixture(t *testing.T, key libp2pcrypto.PrivKey, week, account, transport string, kinds []string) []byte {
	t.Helper()
	proof := []byte("mknoon/activity-account-proof/v1\x00" + featureUseTestAction + "\x001\x00" + week + "\x00" + strings.Join(kinds, ",") + "\x00" + account + "\x00" + transport)
	signature, err := key.Sign(proof)
	if err != nil {
		t.Fatal(err)
	}
	return b293Raw(t, map[string]any{
		"action": featureUseTestAction, "version": 1, "week": week, "kinds": kinds,
		"accountPeerId": account, "signature": base64.StdEncoding.EncodeToString(signature),
	})
}

func featureUseInboxRoundTrip(t *testing.T, env *inboxStreamEnv, actor host.Host, raw []byte) activeEngagementWireResponse {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	stream, err := actor.NewStream(ctx, env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.Close()
	// Mocknet deadlines are no-ops. Reset the owned stream to bound frame I/O.
	stop := context.AfterFunc(ctx, func() { _ = stream.Reset() })
	defer stop()
	if err := writeFrame(stream, raw); err != nil {
		t.Fatal(err)
	}
	data, err := readFrame(stream)
	if err != nil {
		t.Fatal(err)
	}
	var response activeEngagementWireResponse
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatal(err)
	}
	return response
}

func TestBL78FeatureUseRelayCountsWeeklyAcrossTransportsAndRestart(t *testing.T) {
	path := b29RuntimeEnvironment(t, "true", "true")
	t.Setenv("MKNOON_RELAY_FEATURE_USE_ENABLED", "true")
	stores := b29RuntimeBootstrap(t)
	inbox := stores.Inbox
	env := setupInboxStreamEnv(t, inbox, nil)
	week := activitycalendar.Week(time.Now())
	key, account := b293Account(t, 70)
	otherKey, otherAccount := b293Account(t, 71)
	kinds := []string{"voice_message", "photo_video", "video_call", "translation", "voice_to_text", "view_3d"}
	legacyBefore, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var proofs []string
	for _, actor := range []host.Host{env.sender, env.recipient, env.sender} {
		raw := signedFeatureUseFixture(t, key, week, account, actor.ID().String(), kinds)
		proofs = append(proofs, b29E1Signature(raw))
		b29E1Ack(t, featureUseInboxRoundTrip(t, env, actor, raw))
	}
	b29E1Ack(t, featureUseInboxRoundTrip(t, env, env.sender,
		signedFeatureUseFixture(t, otherKey, week, otherAccount, env.sender.ID().String(), []string{"view_3d"})))
	if after, err := os.ReadFile(path); err != nil || !bytes.Equal(legacyBefore, after) {
		t.Fatal("feature assertions changed the legacy activity snapshot")
	}
	expectCounts := func(inbox *InboxStore) {
		t.Helper()
		scrape := b29RuntimeScrape(t, inbox)
		b29RuntimeContains(t, scrape, "relay_feature_use_storage_ready 1",
			fmt.Sprintf("relay_engagement_weekly_estimated{kind=\"active\",week=\"%s\"} 0", week))
		for _, kind := range kinds {
			count := 1
			if kind == "view_3d" {
				count = 2
			}
			b29RuntimeContains(t, scrape,
				fmt.Sprintf("relay_feature_use_weekly_estimated{feature=%q,week=%q} %d", kind, week, count))
		}
		for _, private := range append(proofs, account, otherAccount, env.sender.ID().String(), env.recipient.ID().String()) {
			if strings.Contains(scrape, private) {
				t.Fatal("account proof escaped into metrics")
			}
		}
	}
	expectCounts(inbox)
	if err := stores.Close(); err != nil {
		t.Fatal(err)
	}
	expectCounts(b29RuntimeBootstrap(t).Inbox)

	files, err := os.ReadDir(filepath.Dir(path))
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 2 {
		t.Fatalf("want two aggregate snapshots, got %d entries", len(files))
	}
	for _, file := range files {
		info, err := file.Info()
		if err != nil || info.Mode().Perm()&0077 != 0 {
			t.Fatalf("aggregate snapshot is not private: %v", err)
		}
		raw, err := os.ReadFile(filepath.Join(filepath.Dir(path), file.Name()))
		if err != nil {
			t.Fatal(err)
		}
		for _, private := range append(proofs, account, otherAccount, env.sender.ID().String(), env.recipient.ID().String()) {
			if bytes.Contains(raw, []byte(private)) {
				t.Fatal("account proof persisted")
			}
		}
	}
}

func TestBL78FeatureUseRelayRejectsWrongTransportAndUnapprovedKinds(t *testing.T) {
	b29RuntimeEnvironment(t, "true", "true")
	t.Setenv("MKNOON_RELAY_FEATURE_USE_ENABLED", "true")
	inbox := b29RuntimeBootstrap(t).Inbox
	env := setupInboxStreamEnv(t, inbox, nil)
	week := activitycalendar.Week(time.Now())
	key, account := b293Account(t, 70)
	transport := env.sender.ID().String()
	wrongTransport := signedFeatureUseFixture(t, key, week, account, env.recipient.ID().String(), []string{"video_call"})
	refuse := func(raw []byte) {
		t.Helper()
		response := featureUseInboxRoundTrip(t, env, env.sender, raw)
		if response.Status != "ERROR" || response.ErrorCode != "FEATURE_USE_INVALID_REQUEST" || response.Data != nil {
			t.Fatalf("expected a fixed invalid feature response, got %+v", response)
		}
	}
	refuse(wrongTransport)
	for _, kinds := range [][]string{{"active"}, {"unknown"}, {"video_call", "video_call"}, {"view_3d", "translation"}} {
		refuse(signedFeatureUseFixture(t, key, week, account, transport, kinds))
	}
	b29RuntimeContains(t, b29RuntimeScrape(t, inbox),
		fmt.Sprintf("relay_feature_use_weekly_estimated{feature=\"video_call\",week=%q} 0", week))
}
