package main

import (
	"errors"
	"path/filepath"
	"sort"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

// TC-346-01: admission is an explicit, default-off rollout switch. Disabling
// it is a drain operation: only a new upload is gated; reconciliation,
// download, ACK, expiry, and cleanup of committed rows remain available.
func TestRelayNotificationClosure_DirectMediaBlobCustodyAdmissionOffDrains(t *testing.T) {
	t.Run("default off and fail closed", func(t *testing.T) {
		for _, value := range []string{"", "false", "0", "unexpected", "TRUE-ish"} {
			t.Run(value, func(t *testing.T) {
				t.Setenv(mediaCustodyAdmissionEnabledEnv, value)
				if loadDirectMediaBlobCustodyAdmissionEnabledFromEnv() {
					t.Fatalf("%s=%q unexpectedly enabled protected media admission", mediaCustodyAdmissionEnabledEnv, value)
				}
			})
		}
	})

	t.Run("only explicit true enables", func(t *testing.T) {
		for _, value := range []string{"1", "true", "TRUE", " true "} {
			t.Run(value, func(t *testing.T) {
				t.Setenv(mediaCustodyAdmissionEnabledEnv, value)
				if !loadDirectMediaBlobCustodyAdmissionEnabledFromEnv() {
					t.Fatalf("%s=%q did not enable protected media admission", mediaCustodyAdmissionEnabledEnv, value)
				}
			})
		}
	})

	t.Run("admission off drains existing state only", func(t *testing.T) {
		t.Setenv(mediaCustodyAdmissionEnabledEnv, "true")
		env := setupTestEnv(t)
		now := directMediaCustodyTestNow
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return now })
		body := []byte("rollout drain ciphertext")
		req := directMediaCustodyUploadRequest("rollout-drain", env.recipient.ID().String(), "application/octet-stream", body)
		proof, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
		if !ready {
			t.Fatalf("seed strict upload = %#v", proof)
		}

		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(false)
		duplicate, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
		if ready {
			t.Fatal("admission-off exact duplicate requested a body")
		}
		requireDirectMediaCustodyProof(t, duplicate, req, mediaCustodyStoreDuplicate, "")
		if resp, got := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(proof, "download")); resp.Status != "OK" || string(got) != string(body) {
			t.Fatalf("admission-off strict download = %#v body=%q", resp, got)
		}
		ack := directMediaCustodyRequest(t, env, env.recipient, directMediaCustodyExactRequest(proof, mediaCustodyAckAction))
		requireDirectMediaCustodyProof(t, ack, req, "", mediaCustodyAckAcked)

		newBody := []byte("new admission")
		newReq := directMediaCustodyUploadRequest("rollout-new", req.To, req.Mime, newBody)
		rejected, ready := directMediaCustodyUpload(t, env, env.sender, newReq, newBody)
		if ready || rejected.ErrorCode != mediaCustodyErrorAdmissionOff || rejected.StoreStatus != mediaCustodyStoreDisabled {
			t.Fatalf("admission-off new upload = %#v ready=%v", rejected, ready)
		}
	})
}

// TC-346-10: the exported Prometheus surface is intentionally small and
// fixed-cardinality. Behavioral delta assertions live beside the framed
// lifecycle tests; this test additionally prevents request-controlled values
// from becoming labels.
func TestRelayNotificationClosure_DirectMediaBlobCustodyMetrics(t *testing.T) {
	families, err := prometheus.DefaultGatherer.Gather()
	if err != nil {
		t.Fatalf("gather metrics: %v", err)
	}

	required := map[string]bool{
		"relay_media_custody_contract_info":     false,
		"relay_media_custody_admission_enabled": false,
		"relay_media_custody_blobs_pending":     false,
		"relay_media_custody_bytes_pending":     false,
		"relay_media_custody_tombstones":        false,
		"relay_media_custody_outcomes_total":    false,
	}
	seenOutcomes := map[string]bool{}
	allowedOutcomes := map[string]bool{
		"stored":            true,
		"duplicate":         true,
		"rejected_full":     true,
		"identity_conflict": true,
		"disabled":          true,
		"ineligible":        true,
		"hash_mismatch":     true,
		"acked":             true,
		"already_acked":     true,
		"expired":           true,
		"cleanup_pending":   true,
		"failed":            true,
	}

	for _, family := range families {
		name := family.GetName()
		if _, ok := required[name]; !ok {
			continue
		}
		required[name] = true
		for _, metric := range family.Metric {
			switch name {
			case "relay_media_custody_contract_info":
				if len(metric.Label) != 1 || metric.Label[0].GetName() != "revision" ||
					metric.Label[0].GetValue() != directMediaBlobCustodyContract {
					t.Fatalf("contract metric labels = %#v, want only revision=%q", metric.Label, directMediaBlobCustodyContract)
				}
			case "relay_media_custody_outcomes_total":
				if len(metric.Label) != 1 || metric.Label[0].GetName() != "outcome" {
					t.Fatalf("outcome metric labels are not fixed outcome-only: %#v", metric.Label)
				}
				outcome := metric.Label[0].GetValue()
				if !allowedOutcomes[outcome] {
					t.Fatalf("unbounded or unknown media custody outcome label %q", outcome)
				}
				seenOutcomes[outcome] = true
			default:
				if len(metric.Label) != 0 {
					t.Fatalf("%s must not have labels, got %#v", name, metric.Label)
				}
			}
		}
	}

	var missingFamilies []string
	for name, seen := range required {
		if !seen {
			missingFamilies = append(missingFamilies, name)
		}
	}
	sort.Strings(missingFamilies)
	if len(missingFamilies) != 0 {
		t.Fatalf("missing media custody metric families: %v", missingFamilies)
	}

	for _, outcome := range []string{
		"stored", "duplicate", "rejected_full", "identity_conflict",
		"acked", "already_acked", "expired", "cleanup_pending",
	} {
		if !seenOutcomes[outcome] {
			t.Errorf("required media custody outcome %q is not pre-registered", outcome)
		}
	}

	t.Run("behavioral deltas and reconstructed gauges", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		now := directMediaCustodyTestNow
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return now })
		env.media.custody.maxCount = 1

		counter := func(outcome string) float64 {
			return testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(outcome))
		}
		before := map[string]float64{}
		for _, outcome := range []string{
			mediaCustodyMetricStored,
			mediaCustodyMetricDuplicate,
			mediaCustodyMetricRejectedFull,
			mediaCustodyMetricIdentityConflict,
			mediaCustodyMetricAcked,
			mediaCustodyMetricAlreadyAcked,
		} {
			before[outcome] = counter(outcome)
		}

		body := []byte("metric bytes")
		req := directMediaCustodyUploadRequest("metric-pending", env.recipient.ID().String(), "application/octet-stream", body)
		proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		_, _ = directMediaCustodyUpload(t, env, env.sender, req, body)
		conflict := req
		conflict.Mime = "image/jpeg"
		_, _ = directMediaCustodyUpload(t, env, env.sender, conflict, body)
		fullBody := []byte("full")
		fullReq := directMediaCustodyUploadRequest("metric-full", req.To, req.Mime, fullBody)
		_, _ = directMediaCustodyUpload(t, env, env.sender, fullReq, fullBody)

		if got := testutil.ToFloat64(mediaCustodyBlobsPendingGauge); got != 1 {
			t.Fatalf("pending blob gauge = %v, want 1", got)
		}
		if got := testutil.ToFloat64(mediaCustodyBytesPendingGauge); got != float64(len(body)) {
			t.Fatalf("pending byte gauge = %v, want %d", got, len(body))
		}
		if got := testutil.ToFloat64(mediaCustodyTombstonesGauge); got != 0 {
			t.Fatalf("pre-ACK tombstone gauge = %v, want 0", got)
		}

		ackReq := directMediaCustodyExactRequest(proof, mediaCustodyAckAction)
		_ = directMediaCustodyRequest(t, env, env.recipient, ackReq)
		_ = directMediaCustodyRequest(t, env, env.recipient, ackReq)
		for _, outcome := range []string{
			mediaCustodyMetricStored,
			mediaCustodyMetricDuplicate,
			mediaCustodyMetricRejectedFull,
			mediaCustodyMetricIdentityConflict,
			mediaCustodyMetricAcked,
			mediaCustodyMetricAlreadyAcked,
		} {
			if delta := counter(outcome) - before[outcome]; delta != 1 {
				t.Errorf("%s metric delta = %v, want 1", outcome, delta)
			}
		}
		if got := testutil.ToFloat64(mediaCustodyBlobsPendingGauge); got != 0 {
			t.Fatalf("post-ACK pending blob gauge = %v, want 0", got)
		}
		if got := testutil.ToFloat64(mediaCustodyBytesPendingGauge); got != 0 {
			t.Fatalf("post-ACK pending byte gauge = %v, want 0", got)
		}
		if got := testutil.ToFloat64(mediaCustodyTombstonesGauge); got != 1 {
			t.Fatalf("post-ACK tombstone gauge = %v, want 1", got)
		}

		reopened, err := NewMediaStore(env.media.dataDir)
		if err != nil {
			t.Fatalf("reopen metric fixture: %v", err)
		}
		if meta := reopened.custody.entries[custodyKeyOf(req.To, req.ID)]; meta == nil || meta.State != mediaCustodyStateAcked {
			t.Fatalf("reconstructed metric fixture state = %#v, want ACK tombstone", meta)
		}
		if got := testutil.ToFloat64(mediaCustodyBlobsPendingGauge); got != 0 {
			t.Fatalf("reconstructed pending blob gauge = %v, want 0", got)
		}
		if got := testutil.ToFloat64(mediaCustodyBytesPendingGauge); got != 0 {
			t.Fatalf("reconstructed pending byte gauge = %v, want 0", got)
		}
		if got := testutil.ToFloat64(mediaCustodyTombstonesGauge); got != 1 {
			t.Fatalf("reconstructed tombstone gauge = %v, want 1", got)
		}

		cleanupEnv := setupTestEnv(t)
		cleanupEnv.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		cleanupReq := directMediaCustodyUploadRequest("metric-cleanup", cleanupEnv.recipient.ID().String(), req.Mime, body)
		cleanupProof, _ := directMediaCustodyUpload(t, cleanupEnv, cleanupEnv.sender, cleanupReq, body)
		cleanupMeta := cleanupEnv.media.custody.entries[custodyKeyOf(cleanupReq.To, cleanupReq.ID)]
		cleanupBlob, _ := cleanupEnv.media.custody.blobPath(cleanupMeta)
		realRemove := cleanupEnv.media.custody.remove
		cleanupEnv.media.custody.remove = func(path string) error {
			if path == cleanupBlob {
				return errors.New("metric cleanup failure")
			}
			return realRemove(path)
		}
		cleanupBefore := counter(mediaCustodyMetricCleanupPending)
		_ = directMediaCustodyRequest(t, cleanupEnv, cleanupEnv.recipient, directMediaCustodyExactRequest(cleanupProof, mediaCustodyAckAction))
		if delta := counter(mediaCustodyMetricCleanupPending) - cleanupBefore; delta != 1 {
			t.Fatalf("cleanup-pending metric delta = %v, want 1", delta)
		}

		expiryEnv := setupTestEnv(t)
		expiryEnv.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		expiryNow := directMediaCustodyTestNow
		expiryEnv.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return expiryNow })
		expiryReq := directMediaCustodyUploadRequest("metric-expiry", expiryEnv.recipient.ID().String(), req.Mime, body)
		expiryProof, _ := directMediaCustodyUpload(t, expiryEnv, expiryEnv.sender, expiryReq, body)
		expiredBefore := counter(mediaCustodyMetricExpired)
		expiryNow = time.UnixMilli(expiryProof.ExpiresAtMs)
		_, _ = directMediaCustodyDownload(t, expiryEnv, expiryEnv.recipient, directMediaCustodyExactRequest(expiryProof, "download"))
		if delta := counter(mediaCustodyMetricExpired) - expiredBefore; delta != 1 {
			t.Fatalf("expired metric delta = %v, want 1", delta)
		}

		failedEnv := setupTestEnv(t)
		failedEnv.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		failedBody := []byte("failed metric")
		failedReq := directMediaCustodyUploadRequest("metric-failed", failedEnv.recipient.ID().String(), req.Mime, failedBody)
		realRename := failedEnv.media.custody.rename
		failedEnv.media.custody.rename = func(from, to string) error {
			if filepath.Ext(to) == ".blob" {
				return errors.New("injected blob rename failure")
			}
			return realRename(from, to)
		}
		failedBefore := counter(mediaCustodyMetricFailed)
		failedResp, ready := directMediaCustodyUpload(t, failedEnv, failedEnv.sender, failedReq, failedBody)
		if !ready || failedResp.ErrorCode != mediaCustodyErrorStorage {
			t.Fatalf("failed metric storage fixture = %#v ready=%v", failedResp, ready)
		}
		if delta := counter(mediaCustodyMetricFailed) - failedBefore; delta != 1 {
			t.Fatalf("failed metric delta = %v, want 1", delta)
		}

		blockedEnv := setupTestEnv(t)
		blockedEnv.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		blockedBody := []byte("initial cleanup metric")
		blockedReq := directMediaCustodyUploadRequest("metric-initial-cleanup", blockedEnv.recipient.ID().String(), req.Mime, blockedBody)
		blockedMeta := &directMediaBlobCustodyMeta{ID: blockedReq.ID, To: blockedReq.To}
		blockedBlob, _ := blockedEnv.media.custody.blobPath(blockedMeta)
		blockedDir, _ := blockedEnv.media.custody.recipientDir(blockedMeta)
		realRemoveBlocked := blockedEnv.media.custody.remove
		realSyncBlocked := blockedEnv.media.custody.syncDir
		blockedEnv.media.custody.remove = func(path string) error {
			if path == blockedBlob {
				return errors.New("injected initial cleanup unlink failure")
			}
			return realRemoveBlocked(path)
		}
		blockedEnv.media.custody.syncDir = func(path string) error {
			if path == blockedDir {
				return errors.New("injected initial blob barrier failure")
			}
			return realSyncBlocked(path)
		}
		cleanupBefore = counter(mediaCustodyMetricCleanupPending)
		blockedResp, ready := directMediaCustodyUpload(t, blockedEnv, blockedEnv.sender, blockedReq, blockedBody)
		if !ready || blockedResp.ErrorCode != mediaCustodyErrorCleanupPending {
			t.Fatalf("initial cleanup metric fixture = %#v ready=%v", blockedResp, ready)
		}
		if delta := counter(mediaCustodyMetricCleanupPending) - cleanupBefore; delta != 1 {
			t.Fatalf("initial cleanup-pending metric delta = %v, want 1", delta)
		}
	})
}
