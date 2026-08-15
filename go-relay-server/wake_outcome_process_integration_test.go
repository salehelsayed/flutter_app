//go:build integration

package main

import (
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

func TestRedisWakeOutcomeObligationSurvivesRelayProcessHandoff(t *testing.T) {
	keyringFile := writeRedisProcessPushKeyring(t)
	const baseNowMs int64 = 2_200_000_000_000
	newBase := func(t *testing.T, redisPrefix, peerID, token, eventID string, nowMs int64) redisHelperRequest {
		server := miniredis.RunT(t)
		base := redisHelperRequest{
			RedisURL:                "redis://" + server.Addr(),
			RedisPrefix:             redisPrefix,
			PeerID:                  peerID,
			From:                    "wake-process-sender",
			Token:                   token,
			Platform:                "android",
			Capabilities:            []string{opaqueWakeCapability, wakeOutcomeCapability},
			PushTokenKeyringFile:    keyringFile,
			PushTokenActiveKeyID:    "retained-key",
			PushProviderEnvironment: "production-eu",
			FleetReceiptSHA256:      strings.Repeat("a", 64),
			NowMs:                   nowMs,
			Messages:                []string{wakeOutcomeDirectEnvelope(eventID)},
		}

		migrated := runRedisHelper(t, withOp(base, "migrate_push_vault", nil))
		if migrated.State != string(pushTokenStateEncrypted) {
			t.Fatalf("migration state = %q", migrated.State)
		}
		runRedisHelper(t, withOp(base, "register_push_route", nil))
		return base
	}

	t.Run("pending before due transfers to a new relay owner", func(t *testing.T) {
		base := newBase(
			t,
			"wake-process-pending:",
			"wake-process-peer-a",
			"wake-process-provider-token-a",
			"wake-process-pending-event",
			baseNowMs,
		)
		stored := runRedisHelper(t, withOp(base, "store_wake_outcome", nil))
		if stored.StoreStatus != string(InboxStoreResultStored) ||
			stored.State != string(wakeOutcomeAdmissionDelayed) || stored.Correlation == "" {
			t.Fatalf("process A store = %#v", stored)
		}
		early := runRedisHelper(t, withOp(base, "claim_wake_outcome", func(req *redisHelperRequest) {
			req.NowMs = baseNowMs + wakeOutcomeDebounce.Milliseconds() - 1
		}))
		if early.Count != 0 {
			t.Fatalf("process B claimed before due: %#v", early)
		}
		due := runRedisHelper(t, withOp(base, "claim_wake_outcome", func(req *redisHelperRequest) {
			req.NowMs = baseNowMs + wakeOutcomeDebounce.Milliseconds()
		}))
		if due.Count != 1 || due.Correlation != stored.Correlation ||
			due.ClaimToken == "" || due.WakeState != string(wakeOutcomeStateClaimed) {
			t.Fatalf("process B due claim = %#v", due)
		}
	})

	t.Run("death after claim before provider call is lease-reclaimed", func(t *testing.T) {
		second := newBase(
			t,
			"wake-process-claimed:",
			"wake-process-peer-b",
			"wake-process-provider-token-b",
			"wake-process-claimed-event",
			baseNowMs+time.Hour.Milliseconds(),
		)
		stored := runRedisHelper(t, withOp(second, "store_wake_outcome", nil))
		if stored.Correlation == "" {
			t.Fatalf("process C store = %#v", stored)
		}
		claimedAtMs := second.NowMs + wakeOutcomeDebounce.Milliseconds()
		owner := runRedisHelper(t, withOp(second, "claim_wake_outcome", func(req *redisHelperRequest) {
			req.NowMs = claimedAtMs
		}))
		if owner.Count != 1 || owner.ClaimToken == "" {
			t.Fatalf("process C claim = %#v", owner)
		}
		beforeLease := runRedisHelper(t, withOp(second, "claim_wake_outcome", func(req *redisHelperRequest) {
			req.NowMs = claimedAtMs + wakeOutcomeClaimLease.Milliseconds() - 1
		}))
		if beforeLease.Count != 0 {
			t.Fatalf("process D overlapped live lease: %#v", beforeLease)
		}
		reclaimed := runRedisHelper(t, withOp(second, "claim_wake_outcome", func(req *redisHelperRequest) {
			req.NowMs = claimedAtMs + wakeOutcomeClaimLease.Milliseconds()
		}))
		if reclaimed.Count != 1 || reclaimed.Correlation != stored.Correlation ||
			reclaimed.ClaimToken == "" || reclaimed.ClaimToken == owner.ClaimToken ||
			reclaimed.ClaimRevision <= owner.ClaimRevision {
			t.Fatalf("process D reclaim = %#v, owner = %#v", reclaimed, owner)
		}
	})
}
