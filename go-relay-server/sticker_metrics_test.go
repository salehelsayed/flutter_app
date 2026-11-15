package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/redis/go-redis/v9"
)

// miniredis has no ACL implementation. Model the Redis 7 ACL predicate and
// actual command refusal together; the test checks persisted effects, not
// whether a particular preflight function was called.
func stickerTestACL(t *testing.T, denySet bool) {
	t.Helper()
	prior := stickerReportScript
	stickerReportScript = redis.NewScript(fmt.Sprintf(`
local originalCall = redis.call
redis.acl_check_cmd = function(cmd, ...) return not (%t and cmd == 'SET') end
redis.call = function(cmd, ...)
 if %t and cmd == 'SET' then error('NOPERM nonce write denied') end
 return originalCall(cmd, ...)
end
`, denySet, denySet) + stickerReportLua)
	t.Cleanup(func() { stickerReportScript = prior })
}

func TestStickerMetricsExactRetryRestartAndPrivacy(t *testing.T) {
	stickerTestACL(t, false)
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	defer client.Close()
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	m := newStickerMetrics(client, "synthetic:", func() time.Time { return now })
	raw := []byte(`{"action":"sticker_usage_v1","day":"2026-11-08","nonce":"7b719404-d2bb-4d98-b3b6-b7be5d8186f1","counts":{"orbit_crew.planet.hello":3,"orbit_crew.planet.love":2}}`)
	for i := 0; i < 2; i++ {
		if r := m.report(raw, "PRIVATE_PEER_ID"); r["accepted"] != true {
			t.Fatalf("not accepted: %v", r)
		}
	}
	restarted := newStickerMetrics(client, "synthetic:", func() time.Time { return now })
	if r := restarted.report(raw, "PRIVATE_PEER_ID"); r["accepted"] != true {
		t.Fatal(r)
	}
	values, err := client.HGetAll(context.Background(), "synthetic:sticker:day:2026-11-08").Result()
	if err != nil || values["total"] != "5" || values["p:orbit_crew"] != "5" || values["s:orbit_crew.planet.hello"] != "3" {
		t.Fatalf("wrong exact totals %v %v", values, err)
	}
	for _, k := range server.Keys() {
		if strings.Contains(k, "PRIVATE") || strings.Contains(server.Dump(), "PRIVATE") {
			t.Fatal("peer stored")
		}
	}
	if ttl := server.TTL("synthetic:sticker:nonce:7b719404-d2bb-4d98-b3b6-b7be5d8186f1"); ttl != 72*time.Hour {
		t.Fatalf("nonce TTL %v", ttl)
	}
	server.FastForward(29 * 24 * time.Hour)
	if len(server.Keys()) != 0 {
		t.Fatal("expired metrics retained")
	}
}

func TestStickerMetricsRegisteredStreamAndReadout(t *testing.T) {
	stickerTestACL(t, false)
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	defer client.Close()
	now := time.Now().UTC()
	day := now.AddDate(0, 0, -1).Format("2006-01-02")
	m := newStickerMetrics(client, "stream:", func() time.Time { return now })
	fixture := newCallHandlerFixture(t, nil)
	inbox := NewInboxStore(nil)
	inbox.stickerMetrics = m
	fixture.relay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		HandleInboxStream(s, inbox, nil, fixture.relay, nil, nil)
		fixture.handled <- struct{}{}
	})
	r := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{"action": stickerUsageAction, "day": day, "nonce": "7b719404-d2bb-4d98-b3b6-b7be5d8186f1", "counts": map[string]int{"orbit_crew.planet.hello": 3}})
	if r["status"] != "OK" || r["data"].(map[string]any)["accepted"] != true {
		t.Fatalf("handler not wired %v", r)
	}
	registry := prometheus.NewRegistry()
	registry.MustRegister(m)
	families, err := registry.Gather()
	if err != nil || len(families) != 4 {
		t.Fatalf("metric contract %v %v", families, err)
	}
	for _, f := range families {
		for _, metric := range f.Metric {
			for _, label := range metric.Label {
				if label.GetName() != "day" && label.GetName() != "pack" && label.GetName() != "sticker" {
					t.Fatal("non-aggregate label")
				}
			}
			if f.GetName() == "relay_sticker_sends_daily" && metric.GetGauge().GetValue() != 3 {
				t.Fatal("wrong sum")
			}
		}
	}
	if inbox.appDiagnostics != nil {
		t.Fatal("anonymous report initialized private diagnostics")
	}
}

func TestStickerMetricsAtomicFailureAndConcurrentRetries(t *testing.T) {
	stickerTestACL(t, false)
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	defer client.Close()
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	m := newStickerMetrics(client, "test:", func() time.Time { return now })
	raw := []byte(`{"action":"sticker_usage_v1","day":"2026-11-08","nonce":"7b719404-d2bb-4d98-b3b6-b7be5d8186f1","counts":{"orbit_crew.planet.hello":2}}`)
	server.HSet("test:sticker:day:2026-11-08", "total", "bad")
	if m.report(raw, "actor")["accepted"] == true {
		t.Fatal("corruption accepted")
	}
	if len(server.Keys()) != 1 {
		t.Fatal("failed batch acquired nonce")
	}
	if values := server.HGet("test:sticker:day:2026-11-08", "p:orbit_crew"); values != "" {
		t.Fatal("partial increment")
	}
	server.Del("test:sticker:day:2026-11-08")
	done := make(chan bool, 4)
	for i := 0; i < 4; i++ {
		go func() { done <- m.report(raw, "actor")["accepted"] == true }()
	}
	for i := 0; i < 4; i++ {
		if !<-done {
			t.Fatal("concurrent retry failed")
		}
	}
	if total := server.HGet("test:sticker:day:2026-11-08", "total"); total != "2" {
		t.Fatal("double count")
	}
}

func TestStickerMetricsBootstrapRequiresRedisAndOptIn(t *testing.T) {
	stickerTestACL(t, false)
	t.Setenv("MKNOON_RELAY_STICKER_METRICS_ENABLED", "true")
	memory, err := newControlPlaneStores(context.Background(), backendConfig{Kind: backendKindMemory}, DefaultServerLimits(), "")
	if err != nil {
		t.Fatal(err)
	}
	defer memory.Close()
	if memory.Inbox.stickerMetrics != nil {
		t.Fatal("advertised nondurable store")
	}
	server := miniredis.RunT(t)
	stores, err := newControlPlaneStores(context.Background(), backendConfig{Kind: backendKindRedis, RedisURL: "redis://" + server.Addr(), RedisPrefix: "test:"}, DefaultServerLimits(), "")
	if err != nil {
		t.Fatal(err)
	}
	defer stores.Close()
	if stores.Inbox.stickerMetrics == nil {
		t.Fatal("production bootstrap missing")
	}
	t.Setenv("MKNOON_RELAY_STICKER_METRICS_ENABLED", "false")
	disabled, err := newControlPlaneStores(context.Background(), backendConfig{Kind: backendKindRedis, RedisURL: "redis://" + server.Addr(), RedisPrefix: "test:"}, DefaultServerLimits(), "")
	if err != nil {
		t.Fatal(err)
	}
	defer disabled.Close()
	if disabled.Inbox.stickerMetrics != nil {
		t.Fatal("disabled collector active")
	}
}

func TestStickerMetricsValidateBeforeMutation(t *testing.T) {
	stickerTestACL(t, false)
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	defer client.Close()
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	m := newStickerMetrics(client, "test:", func() time.Time { return now })
	good := map[string]any{"action": "sticker_usage_v1", "day": "2026-11-08", "nonce": "7b719404-d2bb-4d98-b3b6-b7be5d8186f1", "counts": map[string]int{"orbit_crew.planet.hello": 1}}
	for _, change := range []func(map[string]any){
		func(r map[string]any) { r["peerId"] = "private" },
		func(r map[string]any) { r["nonce"] = "device" },
		func(r map[string]any) { r["day"] = "2026-11-09" },
		func(r map[string]any) { r["day"] = "2026-11-05" },
		func(r map[string]any) { r["counts"] = map[string]int{"private.sticker.id": 1} },
		func(r map[string]any) { r["counts"] = map[string]int{"orbit_crew.planet.hello": 1001} },
		func(r map[string]any) { r["counts"] = map[string]int{"orbit_crew.planet.hello": -1} },
	} {
		r := map[string]any{}
		for k, v := range good {
			r[k] = v
		}
		change(r)
		raw, _ := json.Marshal(r)
		if m.report(raw, "actor")["accepted"] == true {
			t.Fatal("invalid report accepted")
		}
	}
	if len(server.Keys()) != 0 {
		t.Fatal("invalid report mutated store")
	}
}

func TestStickerMetricsRateLimitAndUnavailable(t *testing.T) {
	stickerTestACL(t, false)
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	defer client.Close()
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	m := newStickerMetrics(client, "test:", func() time.Time { return now })
	raw := []byte(`{"action":"sticker_usage_v1","day":"2026-11-08","nonce":"7b719404-d2bb-4d98-b3b6-b7be5d8186f1","counts":{"orbit_crew.planet.hello":1}}`)
	limited := false
	for i := 0; i < 100; i++ {
		if m.report(raw, "actor")["reason"] == "rate_limited" {
			limited = true
			break
		}
	}
	if !limited {
		t.Fatal("unbounded admission")
	}
	server.Close()
	if m.report(raw, "another-actor")["accepted"] == true {
		t.Fatal("unavailable storage ACKed")
	}
}

func TestStickerMetricsRejectedNonceWriteDoesNotCount(t *testing.T) {
	stickerTestACL(t, true)
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	defer client.Close()
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	m := newStickerMetrics(client, "test:", func() time.Time { return now })
	raw := []byte(`{"action":"sticker_usage_v1","day":"2026-11-08","nonce":"7b719404-d2bb-4d98-b3b6-b7be5d8186f1","counts":{"orbit_crew.planet.hello":2}}`)
	for i := 0; i < 2; i++ {
		if m.report(raw, "actor")["accepted"] == true {
			t.Fatal("denied nonce write acknowledged")
		}
		if len(server.Keys()) != 0 {
			t.Fatalf("rejected batch left partial counters: %v", server.Keys())
		}
	}
}

func TestStickerMetricsMissingACLPreflightIsUnsupported(t *testing.T) {
	// The fake Redis lacks the ACL predicate, as pre-7 Redis does. No report
	// may mutate totals when permission preflight is unavailable.
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	defer client.Close()
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	m := newStickerMetrics(client, "test:", func() time.Time { return now })
	raw := []byte(`{"action":"sticker_usage_v1","day":"2026-11-08","nonce":"7b719404-d2bb-4d98-b3b6-b7be5d8186f1","counts":{"orbit_crew.planet.hello":2}}`)
	result := m.report(raw, "actor")
	if result["supported"] != false || result["accepted"] != false || len(server.Keys()) != 0 {
		t.Fatalf("unsupported preflight changed counters: %v %v", result, server.Keys())
	}
}
