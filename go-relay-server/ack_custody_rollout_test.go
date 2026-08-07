package main

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestRelayNotificationClosure_AckCustodyRolloutContract(t *testing.T) {
	t.Run("admission_defaults_off_and_memory_on_fails", func(t *testing.T) {
		t.Setenv(ackCustodyAdmissionEnabledEnv, "")
		if loadAckCustodyAdmissionEnabledFromEnv() {
			t.Fatal("ack custody admission must default off")
		}
		t.Setenv(ackCustodyAdmissionEnabledEnv, "unexpected")
		if loadAckCustodyAdmissionEnabledFromEnv() {
			t.Fatal("unexpected admission values must fail closed")
		}
		t.Setenv(ackCustodyAdmissionEnabledEnv, "true")
		if !loadAckCustodyAdmissionEnabledFromEnv() {
			t.Fatal("exact true must enable ack custody admission")
		}

		_, err := newControlPlaneStores(
			context.Background(),
			backendConfig{
				Kind:                       backendKindMemory,
				AckCustodyAdmissionEnabled: true,
			},
			DefaultServerLimits(),
			"/path/that/does/not/exist.json",
		)
		if err == nil || !strings.Contains(err.Error(), ackCustodyAdmissionEnabledEnv+"=true requires RELAY_BACKEND=redis") {
			t.Fatalf("memory admission validation error = %v", err)
		}
	})

	t.Run("flag_off_drains_shared_redis", func(t *testing.T) {
		server := miniredis.RunT(t)
		cfg := backendConfig{
			Kind:                       backendKindRedis,
			RedisURL:                   "redis://" + server.Addr(),
			RedisPrefix:                "ack-rollout:",
			AckCustodyAdmissionEnabled: true,
		}
		storesA, err := newControlPlaneStores(
			context.Background(),
			cfg,
			DefaultServerLimits(),
			"/path/that/does/not/exist.json",
		)
		if err != nil {
			t.Fatal(err)
		}
		const (
			peerID = "peer-recipient"
			sender = "peer-sender"
		)
		entry := inboxMessage{
			ID:        "relay-rollout",
			From:      sender,
			Message:   ackCustodyReactionEnvelope("rollout", "add", "target", sender, "cipher"),
			Timestamp: time.Now().UnixMilli(),
		}
		result, stored, err := storesA.Inbox.StoreAckCustody(peerID, entry, ackCustodyDirectReactionKind)
		if err != nil || result != InboxStoreResultStored {
			t.Fatalf("admission-on store = (%q, %v)", result, err)
		}
		if err := storesA.Close(); err != nil {
			t.Fatal(err)
		}

		cfg.AckCustodyAdmissionEnabled = false
		storesB, err := newControlPlaneStores(
			context.Background(),
			cfg,
			DefaultServerLimits(),
			"/path/that/does/not/exist.json",
		)
		if err != nil {
			t.Fatal(err)
		}
		defer func() { _ = storesB.Close() }()
		if storesB.Inbox.AckCustodyAdmissionEnabled() {
			t.Fatal("second relay instance must have admission off")
		}
		pending, hasMore, err := storesB.Inbox.RetrieveAckCustodyPending(peerID, 50)
		if err != nil || hasMore || len(pending) != 1 || pending[0].ID != stored.ID {
			t.Fatalf("flag-off retrieve = (%#v, %v, %v)", pending, hasMore, err)
		}
		acked, err := storesB.Inbox.AckAckCustody(peerID, []string{stored.ID})
		if err != nil || acked != 1 {
			t.Fatalf("flag-off ACK = (%d, %v)", acked, err)
		}
		if storesB.Inbox.CountAckCustody(peerID) != 0 || storesB.Inbox.Count(peerID) != 0 {
			t.Fatal("flag-off ACK did not clear both protected and shadow copies")
		}
		result, _, err = storesB.Inbox.StoreAckCustody(peerID, entry, ackCustodyDirectReactionKind)
		if result != "" || !errors.Is(err, errAckCustodyAdmissionDisabled) {
			t.Fatalf("flag-off new store = (%q, %v), want disabled", result, err)
		}
	})

	t.Run("metrics_are_fixed_cardinality_and_expiry_is_separate", func(t *testing.T) {
		if got := testutil.ToFloat64(inboxCustodyContractInfo.WithLabelValues(ackCustodyContract)); got != 1 {
			t.Fatalf("relay_inbox_custody_contract_info = %v, want 1", got)
		}
		setAckCustodyAdmissionGauge(false)
		if got := testutil.ToFloat64(inboxCustodyAdmissionEnabledGauge); got != 0 {
			t.Fatalf("admission gauge off = %v, want 0", got)
		}
		setAckCustodyAdmissionGauge(true)
		if got := testutil.ToFloat64(inboxCustodyAdmissionEnabledGauge); got != 1 {
			t.Fatalf("admission gauge on = %v, want 1", got)
		}

		server := miniredis.RunT(t)
		backend := newAckCustodyRedisBackend(t, server, "ack-metrics:", 4)
		inbox := NewInboxStoreWithBackendAndCapacity(backend, nil, 4)
		const peerID = "peer-expiry"
		expired := inboxMessage{
			ID:        "relay-expired-protected",
			From:      "peer-sender",
			Message:   ackCustodyTextEnvelope("expired-protected", "peer-sender", "cipher"),
			Timestamp: time.Now().Add(-maxMessageAge - time.Minute).UnixMilli(),
		}
		requireAckCustodyBackendStore(
			t,
			backend,
			peerID,
			expired,
			directInboxTargetIDDedupePrefix+"expired-protected",
			InboxStoreResultStored,
		)
		beforeProtectedExpiry := testutil.ToFloat64(inboxCustodyExpiredCounter)
		beforeLegacyExpiry := testutil.ToFloat64(inboxExpiredCounter)
		pending, _, err := backend.RetrieveAckCustodyPending(peerID, 50)
		if err != nil || len(pending) != 0 {
			t.Fatalf("expiry retrieve = (%d, %v), want empty", len(pending), err)
		}
		if got := testutil.ToFloat64(inboxCustodyExpiredCounter) - beforeProtectedExpiry; got != 1 {
			t.Fatalf("protected expiry delta = %v, want 1", got)
		}
		if got := testutil.ToFloat64(inboxExpiredCounter) - beforeLegacyExpiry; got != 1 {
			t.Fatalf("legacy shadow expiry delta = %v, want 1 physical shadow only", got)
		}

		fresh := inboxMessage{
			ID:        "relay-fresh-protected",
			From:      "peer-sender",
			Message:   ackCustodyTextEnvelope("fresh-protected", "peer-sender", "cipher"),
			Timestamp: time.Now().UnixMilli(),
		}
		requireAckCustodyBackendStore(
			t,
			backend,
			peerID,
			fresh,
			directInboxTargetIDDedupePrefix+"fresh-protected",
			InboxStoreResultStored,
		)
		if got := refreshAckCustodyPendingGauge(inbox); got != 1 {
			t.Fatalf("protected pending refresh = %d, want 1", got)
		}
		if got := testutil.ToFloat64(inboxCustodyMessagesPendingGauge); got != 1 {
			t.Fatalf("protected pending gauge = %v, want 1", got)
		}

		families, err := prometheus.DefaultGatherer.Gather()
		if err != nil {
			t.Fatal(err)
		}
		allowedResults := map[string]struct{}{
			ackCustodyStoreMetricStored:           {},
			ackCustodyStoreMetricDuplicate:        {},
			ackCustodyStoreMetricRejectedFull:     {},
			ackCustodyStoreMetricDisabled:         {},
			ackCustodyStoreMetricIdentityConflict: {},
			ackCustodyStoreMetricIneligible:       {},
			ackCustodyStoreMetricFailed:           {},
		}
		seenFamilies := map[string]bool{}
		for _, family := range families {
			name := family.GetName()
			switch name {
			case "relay_inbox_custody_contract_info",
				"relay_inbox_custody_admission_enabled",
				"relay_inbox_custody_messages_pending",
				"relay_inbox_custody_expired_total",
				"relay_inbox_custody_store_total":
				seenFamilies[name] = true
			}
			if name != "relay_inbox_custody_store_total" {
				continue
			}
			for _, metric := range family.Metric {
				if len(metric.Label) != 1 || metric.Label[0].GetName() != "result" {
					t.Fatalf("store metric labels are not fixed result-only: %#v", metric.Label)
				}
				if _, ok := allowedResults[metric.Label[0].GetValue()]; !ok {
					t.Fatalf("unexpected custody store result label %q", metric.Label[0].GetValue())
				}
			}
		}
		for _, name := range []string{
			"relay_inbox_custody_contract_info",
			"relay_inbox_custody_admission_enabled",
			"relay_inbox_custody_messages_pending",
			"relay_inbox_custody_expired_total",
			"relay_inbox_custody_store_total",
		} {
			if !seenFamilies[name] {
				t.Fatalf("missing required metric family %s", name)
			}
		}
	})
}
