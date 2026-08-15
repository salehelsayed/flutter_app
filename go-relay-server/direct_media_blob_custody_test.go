package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

var directMediaCustodyTestNow = time.UnixMilli(1_900_000_000_000)

func directMediaCustodyUploadRequest(id, recipient, mime string, body []byte) mediaRequest {
	sum := sha256.Sum256(body)
	return mediaRequest{
		Action:          mediaCustodyUploadAction,
		ID:              id,
		To:              recipient,
		Size:            int64(len(body)),
		Mime:            mime,
		ContentHash:     hex.EncodeToString(sum[:]),
		CustodyKind:     directMediaBlobCustodyKind,
		CustodyContract: directMediaBlobCustodyContract,
	}
}

func directMediaCustodyExactRequest(proof mediaResponse, action string) mediaRequest {
	return mediaRequest{
		Action:          action,
		ID:              proof.ID,
		Size:            proof.Size,
		Mime:            proof.Mime,
		ContentHash:     proof.ContentHash,
		CustodyKind:     proof.CustodyKind,
		CustodyContract: proof.CustodyContract,
		ExpiresAtMs:     proof.ExpiresAtMs,
	}
}

func directMediaCustodyOpen(t *testing.T, env *testEnv, from host.Host) network.Stream {
	t.Helper()
	stream, err := from.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatalf("open media custody stream: %v", err)
	}
	return stream
}

func directMediaCustodyUpload(
	t *testing.T,
	env *testEnv,
	from host.Host,
	req mediaRequest,
	body []byte,
) (mediaResponse, bool) {
	t.Helper()
	stream := directMediaCustodyOpen(t, env, from)
	defer stream.Close()
	sendMediaReq(t, stream, req)
	resp := recvMediaResp(t, stream)
	if resp.Status != "READY" {
		return resp, false
	}
	if _, err := stream.Write(body); err != nil {
		t.Fatalf("write media custody body: %v", err)
	}
	return recvMediaResp(t, stream), true
}

func directMediaCustodyRequest(
	t *testing.T,
	env *testEnv,
	from host.Host,
	req mediaRequest,
) mediaResponse {
	t.Helper()
	stream := directMediaCustodyOpen(t, env, from)
	defer stream.Close()
	sendMediaReq(t, stream, req)
	return recvMediaResp(t, stream)
}

func directMediaCustodyDownload(
	t *testing.T,
	env *testEnv,
	from host.Host,
	req mediaRequest,
) (mediaResponse, []byte) {
	t.Helper()
	stream := directMediaCustodyOpen(t, env, from)
	defer stream.Close()
	sendMediaReq(t, stream, req)
	resp := recvMediaResp(t, stream)
	if resp.Status != "OK" {
		return resp, nil
	}
	body := make([]byte, resp.Size)
	if _, err := io.ReadFull(stream, body); err != nil {
		t.Fatalf("read strict media body: %v", err)
	}
	return resp, body
}

func requireDirectMediaCustodyProof(
	t *testing.T,
	resp mediaResponse,
	req mediaRequest,
	storeStatus string,
	ackStatus string,
) {
	t.Helper()
	if resp.Status != "OK" || resp.Error != "" || resp.ErrorCode != "" ||
		resp.ID != req.ID || resp.Mime != req.Mime || resp.Size != req.Size ||
		resp.ContentHash != req.ContentHash || resp.CustodyKind != req.CustodyKind ||
		resp.CustodyContract != directMediaBlobCustodyContract || resp.ExpiresAtMs <= 0 ||
		resp.StoreStatus != storeStatus || resp.AckStatus != ackStatus {
		t.Fatalf("inexact media custody proof: %#v for request %#v", resp, req)
	}
}

func installDirectMediaCustodyStore(t *testing.T, env *testEnv, media *MediaStore) {
	t.Helper()
	env.media = media
	env.server.SetStreamHandler(MediaProtocol, func(stream network.Stream) {
		HandleMediaStream(stream, media, env.profile)
	})
}

func directMediaCustodyReconcileOwner(dataDir string) *MediaStore {
	owner := &MediaStore{
		index:              make(map[string]*mediaMeta),
		byPeer:             make(map[string][]string),
		dataDir:            dataDir,
		legacyReservations: make(map[string]int),
	}
	owner.loadMetadata()
	return owner
}

func directMediaCustodyCommitLegacyReplacement(store *MediaStore, id, to, mime string, body []byte) error {
	if err := store.reserveLegacyMediaID(id); err != nil {
		return err
	}
	defer store.releaseLegacyMediaID(id)

	path := store.blobPath(to, id)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	tmpPath := store.stagingBlobPath(to, id)
	if err := os.WriteFile(tmpPath, body, 0644); err != nil {
		return err
	}
	meta := &mediaMeta{
		ID:        id,
		To:        to,
		Mime:      mime,
		Size:      int64(len(body)),
		CreatedAt: time.Now().UnixMilli(),
	}
	_, err := store.commitLegacyUpload(tmpPath, path, meta)
	if err != nil {
		_ = os.Remove(tmpPath)
	}
	return err
}

func directMediaCustodyFileCount(t *testing.T, root string) int {
	t.Helper()
	count := 0
	if err := filepath.Walk(root, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			count++
		}
		return nil
	}); err != nil {
		t.Fatalf("walk custody fixture: %v", err)
	}
	return count
}

// Keying-agnostic internal probes: they range over map VALUES so they hold
// under both the historical ID-only maps and the Plan-362 composite
// (recipient, id) maps. Callers probe only quiescent stores, matching the
// direct map peeks the incumbent tests already perform.
func directMediaCustodyFindEntry(store *MediaStore, to, id string) *directMediaBlobCustodyMeta {
	for _, meta := range store.custody.entries {
		if meta.ID == id && meta.To == to {
			return meta
		}
	}
	return nil
}

func directMediaCustodyFindBlocked(store *MediaStore, to, id string) *directMediaBlobCustodyMeta {
	for _, meta := range store.custody.blocked {
		if meta.ID == id && meta.To == to {
			return meta
		}
	}
	return nil
}

// TC-346-01: the raw framed handler recognizes only the additive exact action,
// gates a new store before READY by default, and emits literal typed outcomes.
func TestRelayNotificationClosure_DirectMediaBlobCustodyActionProofAndAdmissionContract(t *testing.T) {
	t.Setenv(mediaCustodyAdmissionEnabledEnv, "")
	env := setupTestEnv(t)
	env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
	body := []byte("strict encrypted media")
	req := directMediaCustodyUploadRequest("action-proof", env.recipient.ID().String(), "application/octet-stream", body)

	disabledBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricDisabled))
	disabled, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
	if ready || disabled.Status != "ERROR" || disabled.ErrorCode != mediaCustodyErrorAdmissionOff ||
		disabled.Error != mediaCustodyErrorAdmissionOff || disabled.StoreStatus != mediaCustodyStoreDisabled {
		t.Fatalf("default-off response = %#v ready=%v", disabled, ready)
	}
	if got := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricDisabled)) - disabledBefore; got != 1 {
		t.Fatalf("disabled metric delta = %v, want 1", got)
	}
	if got := testutil.ToFloat64(mediaCustodyAdmissionEnabledGauge); got != 0 {
		t.Fatalf("default-off admission gauge = %v, want 0", got)
	}

	env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	if got := testutil.ToFloat64(mediaCustodyAdmissionEnabledGauge); got != 1 {
		t.Fatalf("enabled admission gauge = %v, want 1", got)
	}

	ineligibleBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricIneligible))
	invalidRequests := []struct {
		name string
		edit func(*mediaRequest)
	}{
		{name: "kind", edit: func(r *mediaRequest) { r.CustodyKind = "" }},
		{name: "contract", edit: func(r *mediaRequest) { r.CustodyContract = "" }},
		{name: "short hash", edit: func(r *mediaRequest) { r.ContentHash = "abcd" }},
		{name: "uppercase hash", edit: func(r *mediaRequest) { r.ContentHash = strings.ToUpper(r.ContentHash) }},
		{name: "zero size", edit: func(r *mediaRequest) { r.Size = 0 }},
		{name: "oversize", edit: func(r *mediaRequest) { r.Size = maxMediaSize + 1 }},
		{name: "empty MIME", edit: func(r *mediaRequest) { r.Mime = "" }},
		{name: "control MIME", edit: func(r *mediaRequest) { r.Mime = "image/jpeg\x00" }},
		{name: "long MIME", edit: func(r *mediaRequest) { r.Mime = strings.Repeat("m", mediaCustodyMaxMIMEBytes+1) }},
		{name: "group ACL", edit: func(r *mediaRequest) { r.AllowedPeers = []string{env.intruder.ID().String()} }},
		{name: "noncanonical recipient", edit: func(r *mediaRequest) { r.To = "not-a-peer" }},
		{name: "caller expiry", edit: func(r *mediaRequest) { r.ExpiresAtMs = directMediaCustodyTestNow.UnixMilli() }},
	}
	for _, tc := range invalidRequests {
		t.Run("ineligible "+tc.name, func(t *testing.T) {
			invalid := req
			tc.edit(&invalid)
			got, ready := directMediaCustodyUpload(t, env, env.sender, invalid, body)
			if ready || got.Status != "ERROR" || got.ErrorCode != mediaCustodyErrorIneligible || got.StoreStatus != "" {
				t.Fatalf("ineligible response = %#v ready=%v", got, ready)
			}
		})
	}
	if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricIneligible)) - ineligibleBefore; delta != float64(len(invalidRequests)) {
		t.Fatalf("ineligible metric delta = %v, want %d", delta, len(invalidRequests))
	}

	hashMismatch := req
	hashMismatch.ID = "hash-mismatch"
	hashMismatch.ContentHash = strings.Repeat("0", 64)
	hashBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricHashMismatch))
	got, ready := directMediaCustodyUpload(t, env, env.sender, hashMismatch, body)
	if !ready || got.Status != "ERROR" || got.ErrorCode != mediaCustodyErrorHashMismatch {
		t.Fatalf("hash mismatch response = %#v ready=%v", got, ready)
	}
	if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricHashMismatch)) - hashBefore; delta != 1 {
		t.Fatalf("hash mismatch metric delta = %v, want 1", delta)
	}

	storedBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricStored))
	stored, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
	if !ready {
		t.Fatalf("new strict upload did not receive READY: %#v", stored)
	}
	requireDirectMediaCustodyProof(t, stored, req, mediaCustodyStoreStored, "")
	if want := directMediaCustodyTestNow.Add(mediaTTL).UnixMilli(); stored.ExpiresAtMs != want {
		t.Fatalf("stored expiry = %d, want %d", stored.ExpiresAtMs, want)
	}
	if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricStored)) - storedBefore; delta != 1 {
		t.Fatalf("stored metric delta = %v, want 1", delta)
	}
}

// TC-346-02: identity is the complete immutable tuple, strict paths are
// bounded/contained, sender identity is absent at rest, and neither storage
// lane can overwrite the other.
func TestRelayNotificationClosure_DirectMediaBlobCustodyIdentityPathAndCrossLaneIsolation(t *testing.T) {
	env := setupTestEnv(t)
	env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
	body := []byte("identity bytes")
	req := directMediaCustodyUploadRequest("identity", env.recipient.ID().String(), "image/jpeg", body)
	stored, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
	if !ready {
		t.Fatalf("initial strict upload = %#v", stored)
	}
	requireDirectMediaCustodyProof(t, stored, req, mediaCustodyStoreStored, "")

	duplicateBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricDuplicate))
	duplicate, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
	if ready {
		t.Fatal("exact duplicate requested body transfer")
	}
	requireDirectMediaCustodyProof(t, duplicate, req, mediaCustodyStoreDuplicate, "")
	if duplicate.ExpiresAtMs != stored.ExpiresAtMs {
		t.Fatalf("duplicate refreshed expiry: %d -> %d", stored.ExpiresAtMs, duplicate.ExpiresAtMs)
	}
	if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricDuplicate)) - duplicateBefore; delta != 1 {
		t.Fatalf("duplicate metric delta = %v, want 1", delta)
	}

	// 362: identity is per exact (To, ID) target. Tuple drift under the SAME
	// recipient stays refused; a DIFFERENT valid recipient is a sibling
	// custody row of the same canonical blob, not a conflict.
	mutations := []struct {
		name string
		edit func(*mediaRequest)
	}{
		{name: "mime", edit: func(r *mediaRequest) { r.Mime = "image/png" }},
		{name: "size", edit: func(r *mediaRequest) { r.Size++ }},
		{name: "hash", edit: func(r *mediaRequest) { r.ContentHash = strings.Repeat("a", 64) }},
	}
	for _, tc := range mutations {
		t.Run("tuple conflict "+tc.name, func(t *testing.T) {
			mutated := req
			tc.edit(&mutated)
			resp, sawReady := directMediaCustodyUpload(t, env, env.sender, mutated, body)
			if sawReady || resp.Status != "ERROR" || resp.ErrorCode != mediaCustodyErrorIdentityConflict {
				t.Fatalf("mutated tuple accepted: %#v ready=%v", resp, sawReady)
			}
		})
	}
	t.Run("sibling recipient is allowed", func(t *testing.T) {
		sibling := req
		sibling.To = env.intruder.ID().String()
		resp, sawReady := directMediaCustodyUpload(t, env, env.sender, sibling, body)
		if !sawReady {
			t.Fatalf("sibling-recipient upload refused: %#v", resp)
		}
		requireDirectMediaCustodyProof(t, resp, sibling, mediaCustodyStoreStored, "")
		if meta := directMediaCustodyFindEntry(env.media, req.To, req.ID); meta == nil {
			t.Fatal("sibling admission displaced the original recipient row")
		}
		if meta := directMediaCustodyFindEntry(env.media, sibling.To, sibling.ID); meta == nil {
			t.Fatal("sibling admission did not persist its own recipient row")
		}
	})

	filesBefore := directMediaCustodyFileCount(t, env.media.dataDir)
	for _, id := range []string{"..", "../escape", "a/b", `a\b`, "/absolute", strings.Repeat("a", 129)} {
		t.Run("strict path "+fmt.Sprintf("%q", id), func(t *testing.T) {
			bad := directMediaCustodyUploadRequest(id, env.recipient.ID().String(), "image/jpeg", body)
			resp, sawReady := directMediaCustodyUpload(t, env, env.sender, bad, body)
			if sawReady || resp.Status != "ERROR" || resp.ErrorCode != mediaCustodyErrorIneligible {
				t.Fatalf("unsafe strict path response = %#v ready=%v", resp, sawReady)
			}
		})
	}
	if got := directMediaCustodyFileCount(t, env.media.dataDir); got != filesBefore {
		t.Fatalf("invalid strict paths mutated filesystem file count: %d -> %d", filesBefore, got)
	}
	for _, tc := range []struct {
		name string
		req  mediaRequest
	}{
		{name: "legacy parent ID", req: mediaRequest{Action: "upload", ID: "..", To: req.To, Size: 1, Mime: "image/jpeg"}},
		{name: "legacy separator ID", req: mediaRequest{Action: "upload", ID: "a/b", To: req.To, Size: 1, Mime: "image/jpeg"}},
		{name: "legacy absolute ID", req: mediaRequest{Action: "upload", ID: "/absolute", To: req.To, Size: 1, Mime: "image/jpeg"}},
		{name: "legacy reserved recipient", req: mediaRequest{Action: "upload", ID: "legacy-safe", To: mediaCustodyRootName, Size: 1, Mime: "image/jpeg"}},
		{name: "legacy separator recipient", req: mediaRequest{Action: "upload", ID: "legacy-safe", To: "../escape", Size: 1, Mime: "image/jpeg"}},
		{name: "legacy unsafe delete", req: mediaRequest{Action: "delete", ID: "../escape"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resp := directMediaCustodyRequest(t, env, env.sender, tc.req)
			if resp.Status != "ERROR" {
				t.Fatalf("unsafe legacy filesystem action = %#v", resp)
			}
		})
	}
	if got := directMediaCustodyFileCount(t, env.media.dataDir); got != filesBefore {
		t.Fatalf("invalid legacy paths mutated filesystem file count: %d -> %d", filesBefore, got)
	}

	meta := directMediaCustodyFindEntry(env.media, req.To, req.ID)
	if meta == nil {
		t.Fatal("stored identity row missing")
	}
	marker, err := env.media.custody.markerPath(meta)
	if err != nil {
		t.Fatalf("resolve marker: %v", err)
	}
	markerBytes, err := os.ReadFile(marker)
	if err != nil {
		t.Fatalf("read marker: %v", err)
	}
	if bytes.Contains(markerBytes, []byte(env.sender.ID().String())) {
		t.Fatalf("protected marker persisted sender identity: %s", markerBytes)
	}
	var markerJSON map[string]interface{}
	if err := json.Unmarshal(markerBytes, &markerJSON); err != nil {
		t.Fatalf("decode marker: %v", err)
	}
	for _, forbidden := range []string{"from", "sender", "senderPeerId"} {
		if _, ok := markerJSON[forbidden]; ok {
			t.Fatalf("protected marker contains forbidden sender key %q", forbidden)
		}
	}

	legacyConflict := mediaRequest{Action: "upload", ID: req.ID, To: req.To, Size: 1, Mime: "image/jpeg"}
	legacyResp := directMediaCustodyRequest(t, env, env.sender, legacyConflict)
	if legacyResp.Status != "ERROR" {
		t.Fatalf("legacy upload shadowed protected ID: %#v", legacyResp)
	}
	legacyDelete := directMediaCustodyRequest(t, env, env.recipient, mediaRequest{Action: "delete", ID: req.ID})
	if legacyDelete.Status != "OK" {
		t.Fatalf("legacy rollback delete shape = %#v, want compatible OK/no-op", legacyDelete)
	}
	exact := directMediaCustodyExactRequest(stored, "download")
	exact.To = req.To
	if resp, gotBody := directMediaCustodyDownload(t, env, env.recipient, exact); resp.Status != "OK" || !bytes.Equal(gotBody, body) {
		t.Fatalf("protected blob changed after legacy actions: %#v body=%q", resp, gotBody)
	}

	legacyBody := []byte("legacy first")
	env.upload(t, env.sender, "legacy-first", req.To, "image/jpeg", legacyBody)
	strictCollision := directMediaCustodyUploadRequest("legacy-first", req.To, "image/jpeg", legacyBody)
	strictResp, sawReady := directMediaCustodyUpload(t, env, env.sender, strictCollision, legacyBody)
	if sawReady || strictResp.Status != "ERROR" || strictResp.ErrorCode != mediaCustodyErrorIdentityConflict {
		t.Fatalf("strict upload promoted/overwrote legacy ID: %#v ready=%v", strictResp, sawReady)
	}
	if got := downloadMedia(t, env, env.recipient, "legacy-first"); !bytes.Equal(got, legacyBody) {
		t.Fatalf("legacy blob changed after strict collision: %q", got)
	}
}

// TC-346-03: strict capacity rejects distinct authority without evicting any
// pending blob. Duplicate and race decisions are made under the same lock.
func TestRelayNotificationClosure_DirectMediaBlobCustodyRejectsCapacityWithoutEviction(t *testing.T) {
	withMediaLimits(t, 1024, 8, func() {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		env.media.custody.maxCount = 1
		firstBody := []byte("12345678")
		firstReq := directMediaCustodyUploadRequest("capacity-first", env.recipient.ID().String(), "application/octet-stream", firstBody)
		first, ready := directMediaCustodyUpload(t, env, env.sender, firstReq, firstBody)
		if !ready {
			t.Fatalf("first capacity upload = %#v", first)
		}

		duplicate, ready := directMediaCustodyUpload(t, env, env.sender, firstReq, firstBody)
		if ready {
			t.Fatal("exact duplicate lost to capacity check")
		}
		requireDirectMediaCustodyProof(t, duplicate, firstReq, mediaCustodyStoreDuplicate, "")

		fullBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricRejectedFull))
		secondBody := []byte("x")
		secondReq := directMediaCustodyUploadRequest("capacity-second", firstReq.To, "application/octet-stream", secondBody)
		full, ready := directMediaCustodyUpload(t, env, env.sender, secondReq, secondBody)
		if ready || full.Status != "ERROR" || full.ErrorCode != mediaCustodyErrorFull || full.StoreStatus != mediaCustodyStoreRejectedFull {
			t.Fatalf("full capacity response = %#v ready=%v", full, ready)
		}
		if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricRejectedFull)) - fullBefore; delta != 1 {
			t.Fatalf("full metric delta = %v, want 1", delta)
		}
		exact := directMediaCustodyExactRequest(first, "download")
		if resp, got := directMediaCustodyDownload(t, env, env.recipient, exact); resp.Status != "OK" || !bytes.Equal(got, firstBody) {
			t.Fatalf("full admission evicted first blob: %#v body=%q", resp, got)
		}

		ackReq := directMediaCustodyExactRequest(first, mediaCustodyAckAction)
		ack := directMediaCustodyRequest(t, env, env.recipient, ackReq)
		requireDirectMediaCustodyProof(t, ack, firstReq, "", mediaCustodyAckAcked)
		full, ready = directMediaCustodyUpload(t, env, env.sender, secondReq, secondBody)
		if ready || full.ErrorCode != mediaCustodyErrorFull {
			t.Fatalf("ACK tombstone released bounded identity slot: %#v ready=%v", full, ready)
		}
	})

	t.Run("different expired row is normalized before capacity", func(t *testing.T) {
		withMediaLimits(t, 1024, 1024, func() {
			env := setupTestEnv(t)
			env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
			env.media.custody.maxCount = 1
			now := directMediaCustodyTestNow
			env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return now })
			oldBody := []byte("old")
			oldReq := directMediaCustodyUploadRequest("capacity-expired-old", env.recipient.ID().String(), "application/octet-stream", oldBody)
			oldProof, _ := directMediaCustodyUpload(t, env, env.sender, oldReq, oldBody)
			now = time.UnixMilli(oldProof.ExpiresAtMs)
			expiredBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricExpired))
			newBody := []byte("new")
			newReq := directMediaCustodyUploadRequest("capacity-after-expiry", oldReq.To, oldReq.Mime, newBody)
			newProof, ready := directMediaCustodyUpload(t, env, env.sender, newReq, newBody)
			if !ready || newProof.Status != "OK" || newProof.StoreStatus != mediaCustodyStoreStored {
				t.Fatalf("new store after different expired row = %#v ready=%v", newProof, ready)
			}
			if env.media.custody.entries[custodyKeyOf(oldReq.To, oldReq.ID)] != nil || env.media.custody.entries[custodyKeyOf(newReq.To, newReq.ID)] == nil {
				t.Fatalf("capacity normalization entries = %#v", env.media.custody.entries)
			}
			if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricExpired)) - expiredBefore; delta != 1 {
				t.Fatalf("different-row expiry metric delta = %v, want 1", delta)
			}
		})
	})

	t.Run("byte cap rejects without count pressure", func(t *testing.T) {
		withMediaLimits(t, 1024, 8, func() {
			env := setupTestEnv(t)
			env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
			env.media.custody.maxCount = 10
			firstBody := []byte("12345678")
			firstReq := directMediaCustodyUploadRequest("byte-cap-first", env.recipient.ID().String(), "application/octet-stream", firstBody)
			first, _ := directMediaCustodyUpload(t, env, env.sender, firstReq, firstBody)
			secondBody := []byte("x")
			secondReq := directMediaCustodyUploadRequest("byte-cap-second", firstReq.To, firstReq.Mime, secondBody)
			second, ready := directMediaCustodyUpload(t, env, env.sender, secondReq, secondBody)
			if ready || second.ErrorCode != mediaCustodyErrorFull || second.StoreStatus != mediaCustodyStoreRejectedFull {
				t.Fatalf("byte-only capacity response = %#v ready=%v", second, ready)
			}
			if resp, got := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(first, "download")); resp.Status != "OK" || !bytes.Equal(got, firstBody) {
				t.Fatalf("byte-cap rejection evicted first blob: %#v body=%q", resp, got)
			}
		})
	})
}

func TestRelayNotificationClosure_DirectMediaBlobCustodyConcurrentAdmission(t *testing.T) {
	withMediaLimits(t, 1024, 1024, func() {
		t.Run("last slot", func(t *testing.T) {
			env := setupTestEnv(t)
			env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
			env.media.custody.maxCount = 1
			start := make(chan struct{})
			results := make(chan mediaResponse, 2)
			var wg sync.WaitGroup
			for i, from := range []host.Host{env.sender, env.intruder} {
				wg.Add(1)
				go func(i int, from host.Host) {
					defer wg.Done()
					<-start
					body := []byte{byte('a' + i)}
					req := directMediaCustodyUploadRequest(fmt.Sprintf("last-slot-%d", i), env.recipient.ID().String(), "application/octet-stream", body)
					resp, _ := directMediaCustodyUpload(t, env, from, req, body)
					results <- resp
				}(i, from)
			}
			close(start)
			wg.Wait()
			close(results)
			stored, full := 0, 0
			for resp := range results {
				switch {
				case resp.Status == "OK" && resp.StoreStatus == mediaCustodyStoreStored:
					stored++
				case resp.Status == "ERROR" && resp.StoreStatus == mediaCustodyStoreRejectedFull:
					full++
				default:
					t.Fatalf("unexpected last-slot race response: %#v", resp)
				}
			}
			if stored != 1 || full != 1 || len(env.media.custody.entries) != 1 {
				t.Fatalf("last-slot race stored=%d full=%d entries=%d", stored, full, len(env.media.custody.entries))
			}
		})

		t.Run("same ID different tuple", func(t *testing.T) {
			env := setupTestEnv(t)
			env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
			start := make(chan struct{})
			results := make(chan mediaResponse, 2)
			var wg sync.WaitGroup
			for i, from := range []host.Host{env.sender, env.intruder} {
				wg.Add(1)
				go func(i int, from host.Host) {
					defer wg.Done()
					<-start
					body := []byte(fmt.Sprintf("candidate-%d", i))
					req := directMediaCustodyUploadRequest("same-id-race", env.recipient.ID().String(), "application/octet-stream", body)
					resp, _ := directMediaCustodyUpload(t, env, from, req, body)
					results <- resp
				}(i, from)
			}
			close(start)
			wg.Wait()
			close(results)
			stored, conflict := 0, 0
			for resp := range results {
				switch {
				case resp.StoreStatus == mediaCustodyStoreStored:
					stored++
				case resp.ErrorCode == mediaCustodyErrorIdentityConflict:
					conflict++
				default:
					t.Fatalf("unexpected same-ID race response: %#v", resp)
				}
			}
			if stored != 1 || conflict != 1 || len(env.media.custody.entries) != 1 {
				t.Fatalf("same-ID race stored=%d conflict=%d entries=%d", stored, conflict, len(env.media.custody.entries))
			}
		})
	})
}

// TC-346-04: the final marker is the commit point. Pre-marker artifacts are
// cleaned, proof-bearing ambiguous commits reload, and corrupt/impossible
// committed states remain on disk while startup fails closed.
func TestRelayNotificationClosure_DirectMediaBlobCustodyAtomicCommitRecovery(t *testing.T) {
	t.Run("blob before marker is discarded", func(t *testing.T) {
		root := t.TempDir()
		owner, err := NewMediaStore(root)
		if err != nil {
			t.Fatal(err)
		}
		peerID := "12D3KooWA4WHZmYAWGCJbRwU41DwZLtCpoUW6NMWRcmWzEzbnuye"
		dir := filepath.Join(owner.custody.rootDir, peerID)
		if err := os.MkdirAll(dir, 0755); err != nil {
			t.Fatal(err)
		}
		blob := filepath.Join(dir, "orphan.blob")
		temp := filepath.Join(dir, ".orphan.blob-1.tmp")
		if err := os.WriteFile(blob, []byte("orphan"), 0644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(temp, []byte("temp"), 0644); err != nil {
			t.Fatal(err)
		}
		if _, err := NewMediaStore(root); err != nil {
			t.Fatalf("reconcile pre-marker artifacts: %v", err)
		}
		for _, path := range []string{blob, temp} {
			if _, err := os.Stat(path); !os.IsNotExist(err) {
				t.Fatalf("pre-marker artifact survived reconcile %s: %v", path, err)
			}
		}
	})

	t.Run("only generated recipient temp grammar is disposable", func(t *testing.T) {
		root := t.TempDir()
		owner, err := NewMediaStore(root)
		if err != nil {
			t.Fatal(err)
		}
		peerID := "12D3KooWA4WHZmYAWGCJbRwU41DwZLtCpoUW6NMWRcmWzEzbnuye"
		recipientDir := filepath.Join(owner.custody.rootDir, peerID)
		if err := os.MkdirAll(recipientDir, 0755); err != nil {
			t.Fatal(err)
		}
		operatorTemp := filepath.Join(recipientDir, "operator.tmp")
		if err := os.WriteFile(operatorTemp, []byte("operator-owned"), 0644); err != nil {
			t.Fatal(err)
		}
		if _, err := NewMediaStore(root); err == nil {
			t.Fatal("arbitrary operator.tmp was silently accepted/deleted")
		}
		if got, err := os.ReadFile(operatorTemp); err != nil || string(got) != "operator-owned" {
			t.Fatalf("operator temp was not preserved: %q err=%v", got, err)
		}

		if err := os.Remove(operatorTemp); err != nil {
			t.Fatal(err)
		}
		rootGeneratedLooking := filepath.Join(owner.custody.rootDir, ".root.blob-123.tmp")
		if err := os.WriteFile(rootGeneratedLooking, []byte("root-owned"), 0644); err != nil {
			t.Fatal(err)
		}
		if _, err := NewMediaStore(root); err == nil {
			t.Fatal("generated-looking temp at custody root was treated as a disposable upload temp")
		}
		if got, err := os.ReadFile(rootGeneratedLooking); err != nil || string(got) != "root-owned" {
			t.Fatalf("root-level generated-looking temp was not preserved: %q err=%v", got, err)
		}
	})

	t.Run("root-level and nonregular final artifacts fail closed", func(t *testing.T) {
		for _, tc := range []struct {
			name  string
			build func(*testing.T, *MediaStore) string
		}{
			{
				name: "root-level final blob",
				build: func(t *testing.T, store *MediaStore) string {
					path := filepath.Join(store.custody.rootDir, "operator.blob")
					if err := os.WriteFile(path, []byte("operator-owned"), 0644); err != nil {
						t.Fatal(err)
					}
					return path
				},
			},
			{
				name: "nonregular recipient blob",
				build: func(t *testing.T, store *MediaStore) string {
					peerID := "12D3KooWA4WHZmYAWGCJbRwU41DwZLtCpoUW6NMWRcmWzEzbnuye"
					path := filepath.Join(store.custody.rootDir, peerID, "device-like.blob")
					if err := os.MkdirAll(path, 0755); err != nil {
						t.Fatal(err)
					}
					return path
				},
			},
		} {
			t.Run(tc.name, func(t *testing.T) {
				root := t.TempDir()
				store, err := NewMediaStore(root)
				if err != nil {
					t.Fatal(err)
				}
				artifact := tc.build(t, store)
				if _, err := NewMediaStore(root); err == nil {
					t.Fatalf("%s reopened successfully", tc.name)
				}
				if _, err := os.Lstat(artifact); err != nil {
					t.Fatalf("%s was not preserved: %v", tc.name, err)
				}
			})
		}
	})

	t.Run("expiry begins only after complete body acceptance", func(t *testing.T) {
		root := t.TempDir()
		store, err := NewMediaStore(root)
		if err != nil {
			t.Fatal(err)
		}
		store.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		beforeTransfer := directMediaCustodyTestNow
		now := beforeTransfer
		store.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return now })
		body := []byte("slow but complete ciphertext")
		req := directMediaCustodyUploadRequest("slow-acceptance", "12D3KooWA4WHZmYAWGCJbRwU41DwZLtCpoUW6NMWRcmWzEzbnuye", "application/octet-stream", body)
		prepared, failure := store.custody.prepareUpload(&req)
		if failure != nil || prepared == nil || prepared.reservation == nil {
			t.Fatalf("prepare slow upload = (%#v, %v)", prepared, failure)
		}
		now = beforeTransfer.Add(2 * mediaTTL)
		meta, failure := store.custody.commitUpload(prepared.reservation, bytes.NewReader(body))
		if failure != nil || meta == nil {
			t.Fatalf("commit slow upload = (%#v, %v)", meta, failure)
		}
		if meta.CreatedAtMs != now.UnixMilli() || meta.ExpiresAtMs != now.Add(mediaTTL).UnixMilli() {
			t.Fatalf("slow-upload lifetime = created %d expires %d, want %d/%d", meta.CreatedAtMs, meta.ExpiresAtMs, now.UnixMilli(), now.Add(mediaTTL).UnixMilli())
		}
		exact := req
		exact.ExpiresAtMs = meta.ExpiresAtMs
		_, file, failure := store.custody.openDownload(&exact, req.To)
		if failure != nil || file == nil {
			t.Fatalf("fresh proof was dead at acceptance: file=%v failure=%v", file, failure)
		}
		_ = file.Close()
	})

	t.Run("committed proof reloads after final response ambiguity", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		env.media.custody.maxCount = 1
		body := []byte("ambiguous committed bytes")
		req := directMediaCustodyUploadRequest("ambiguous", env.recipient.ID().String(), "application/octet-stream", body)
		realSync := env.media.custody.syncDir
		failedFinalBarrier := false
		markerPath := filepath.Join(env.media.custody.rootDir, req.To, req.ID+".custody")
		env.media.custody.syncDir = func(path string) error {
			if !failedFinalBarrier && fileExists(markerPath) {
				failedFinalBarrier = true
				return errors.New("lost final directory barrier response")
			}
			return realSync(path)
		}
		resp, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
		if !ready || resp.Status != "ERROR" || resp.ErrorCode != mediaCustodyErrorStorage {
			t.Fatalf("ambiguous final-sync response = %#v ready=%v", resp, ready)
		}
		if blocked := env.media.custody.blocked[custodyKeyOf(req.To, req.ID)]; blocked == nil || blocked.To != req.To || blocked.Size != req.Size {
			t.Fatalf("post-marker ambiguity did not retain exact blocked capacity: %#v", blocked)
		}
		if got := testutil.ToFloat64(mediaCustodyBlobsPendingGauge); got != 1 {
			t.Fatalf("blocked pending gauge = %v, want 1", got)
		}
		if got := testutil.ToFloat64(mediaCustodyBytesPendingGauge); got != float64(len(body)) {
			t.Fatalf("blocked byte gauge = %v, want %d", got, len(body))
		}

		env.media.custody.syncDir = realSync
		otherBody := []byte("must not over-admit")
		otherReq := directMediaCustodyUploadRequest("ambiguous-other", req.To, req.Mime, otherBody)
		other, otherReady := directMediaCustodyUpload(t, env, env.sender, otherReq, otherBody)
		if otherReady || other.ErrorCode != mediaCustodyErrorFull || other.StoreStatus != mediaCustodyStoreRejectedFull {
			t.Fatalf("distinct upload over blocked last slot = %#v ready=%v", other, otherReady)
		}
		if env.media.custody.blocked[custodyKeyOf(req.To, req.ID)] != nil || env.media.custody.entries[custodyKeyOf(req.To, req.ID)] == nil {
			t.Fatalf("distinct peer upload did not reconcile blocked commit before capacity: blocked=%#v entries=%#v", env.media.custody.blocked, env.media.custody.entries)
		}
		probe, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
		if ready {
			t.Fatal("reconciled exact probe requested a second body")
		}
		requireDirectMediaCustodyProof(t, probe, req, mediaCustodyStoreDuplicate, "")

		reopened, err := NewMediaStore(env.media.dataDir)
		if err != nil {
			t.Fatalf("reopen proof-bearing ambiguous commit: %v", err)
		}
		reopened.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		installDirectMediaCustodyStore(t, env, reopened)
		probe, ready = directMediaCustodyUpload(t, env, env.sender, req, body)
		if ready {
			t.Fatal("reopened exact probe requested a second body")
		}
		requireDirectMediaCustodyProof(t, probe, req, mediaCustodyStoreDuplicate, "")
		if got, want := probe.ExpiresAtMs, directMediaCustodyTestNow.Add(mediaTTL).UnixMilli(); got != want {
			t.Fatalf("reloaded expiry = %d, want original %d", got, want)
		}
	})

	t.Run("corrupt marker fails closed and is preserved", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		body := []byte("corrupt marker bytes")
		req := directMediaCustodyUploadRequest("corrupt-marker", env.recipient.ID().String(), "application/octet-stream", body)
		proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		marker, _ := env.media.custody.markerPath(env.media.custody.entries[custodyKeyOf(req.To, req.ID)])
		if err := os.WriteFile(marker, []byte("{corrupt"), 0644); err != nil {
			t.Fatal(err)
		}
		if _, err := NewMediaStore(env.media.dataDir); err == nil {
			t.Fatalf("corrupt committed marker reopened successfully; proof was %#v", proof)
		}
		if got, err := os.ReadFile(marker); err != nil || string(got) != "{corrupt" {
			t.Fatalf("corrupt marker was not preserved: %q err=%v", got, err)
		}
	})

	t.Run("pending marker without blob fails closed", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		body := []byte("missing blob")
		req := directMediaCustodyUploadRequest("missing-blob", env.recipient.ID().String(), "application/octet-stream", body)
		_, _ = directMediaCustodyUpload(t, env, env.sender, req, body)
		meta := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]
		blob, _ := env.media.custody.blobPath(meta)
		marker, _ := env.media.custody.markerPath(meta)
		if err := os.Remove(blob); err != nil {
			t.Fatal(err)
		}
		if _, err := NewMediaStore(env.media.dataDir); err == nil {
			t.Fatal("pending marker without blob reopened successfully")
		}
		if _, err := os.Stat(marker); err != nil {
			t.Fatalf("impossible committed marker was not preserved: %v", err)
		}
	})

	t.Run("ACK marker plus leftover blob reconciles on restart", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		body := []byte("restart ACK cleanup")
		req := directMediaCustodyUploadRequest("restart-acked-leftover", env.recipient.ID().String(), "application/octet-stream", body)
		proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		meta := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]
		blobPath, _ := env.media.custody.blobPath(meta)
		realRemove := env.media.custody.remove
		env.media.custody.remove = func(path string) error {
			if path == blobPath {
				return errors.New("leave ACKed bytes for restart")
			}
			return realRemove(path)
		}
		failed := directMediaCustodyRequest(t, env, env.recipient, directMediaCustodyExactRequest(proof, mediaCustodyAckAction))
		if failed.ErrorCode != mediaCustodyErrorCleanupPending {
			t.Fatalf("ACK leftover setup = %#v", failed)
		}
		reopened, err := NewMediaStore(env.media.dataDir)
		if err != nil {
			t.Fatalf("reconcile ACK marker plus leftover: %v", err)
		}
		if got := reopened.custody.entries[custodyKeyOf(req.To, req.ID)]; got == nil || got.State != mediaCustodyStateAcked {
			t.Fatalf("reconstructed ACK tombstone = %#v", got)
		}
		if _, err := os.Stat(blobPath); !os.IsNotExist(err) {
			t.Fatalf("startup did not retire ACK leftover: %v", err)
		}
	})

	t.Run("expired committed pair is removed on restart", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		body := []byte("expired restart bytes")
		req := directMediaCustodyUploadRequest("restart-expired", env.recipient.ID().String(), "application/octet-stream", body)
		_, _ = directMediaCustodyUpload(t, env, env.sender, req, body)
		meta := cloneDirectMediaBlobCustodyMeta(env.media.custody.entries[custodyKeyOf(req.To, req.ID)])
		meta.CreatedAtMs = time.Now().Add(-mediaTTL - time.Hour).UnixMilli()
		meta.ExpiresAtMs = meta.CreatedAtMs + mediaTTL.Milliseconds()
		markerPath, _ := env.media.custody.markerPath(meta)
		blobPath, _ := env.media.custody.blobPath(meta)
		markerJSON, _ := json.Marshal(meta)
		if err := os.WriteFile(markerPath, markerJSON, 0644); err != nil {
			t.Fatal(err)
		}
		reopened, err := NewMediaStore(env.media.dataDir)
		if err != nil {
			t.Fatalf("reconcile expired committed pair: %v", err)
		}
		if reopened.custody.entries[custodyKeyOf(req.To, req.ID)] != nil {
			t.Fatal("expired committed pair remained indexed after restart")
		}
		for _, path := range []string{markerPath, blobPath} {
			if _, err := os.Stat(path); !os.IsNotExist(err) {
				t.Fatalf("expired restart artifact remains %s: %v", path, err)
			}
		}
	})

	t.Run("startup expiry removal failure preserves committed pair", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		body := []byte("expired cleanup must fail closed")
		req := directMediaCustodyUploadRequest("restart-remove-failure", env.recipient.ID().String(), "application/octet-stream", body)
		proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		meta := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]
		blobPath, _ := env.media.custody.blobPath(meta)
		markerPath, _ := env.media.custody.markerPath(meta)

		removeCalls := 0
		owner := directMediaCustodyReconcileOwner(env.media.dataDir)
		opened, err := newDirectMediaBlobCustodyStoreWithConfig(owner, directMediaBlobCustodyStoreConfig{
			now: func() time.Time { return time.UnixMilli(proof.ExpiresAtMs) },
			remove: func(path string) error {
				removeCalls++
				if path == markerPath {
					return errors.New("injected startup removal failure")
				}
				return os.Remove(path)
			},
		})
		if err == nil || opened != nil {
			t.Fatalf("startup removal failure opened protected store: store=%v err=%v", opened, err)
		}
		if removeCalls == 0 {
			t.Fatal("startup reconciliation did not exercise injected remove seam")
		}
		for _, path := range []string{markerPath, blobPath} {
			if _, statErr := os.Stat(path); statErr != nil {
				t.Fatalf("startup removal failure did not preserve %s: %v", path, statErr)
			}
		}
	})

	t.Run("startup ACK cleanup sync failure preserves tombstone and fails closed", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		body := []byte("ACK cleanup barrier ambiguity")
		req := directMediaCustodyUploadRequest("restart-sync-failure", env.recipient.ID().String(), "application/octet-stream", body)
		proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		meta := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]
		blobPath, _ := env.media.custody.blobPath(meta)
		markerPath, _ := env.media.custody.markerPath(meta)
		recipientDir := filepath.Dir(blobPath)
		realRemove := env.media.custody.remove
		env.media.custody.remove = func(path string) error {
			if path == blobPath {
				return errors.New("leave ACKed blob for startup")
			}
			return realRemove(path)
		}
		ack := directMediaCustodyRequest(t, env, env.recipient, directMediaCustodyExactRequest(proof, mediaCustodyAckAction))
		if ack.ErrorCode != mediaCustodyErrorCleanupPending {
			t.Fatalf("ACK-leftover setup = %#v", ack)
		}

		syncCalls := 0
		owner := directMediaCustodyReconcileOwner(env.media.dataDir)
		opened, err := newDirectMediaBlobCustodyStoreWithConfig(owner, directMediaBlobCustodyStoreConfig{
			now: func() time.Time { return directMediaCustodyTestNow },
			syncDir: func(path string) error {
				if path == recipientDir {
					syncCalls++
					return errors.New("injected startup directory sync failure")
				}
				return syncMediaCustodyDirectory(path)
			},
		})
		if err == nil || opened != nil {
			t.Fatalf("startup sync failure opened protected store: store=%v err=%v", opened, err)
		}
		if syncCalls != 1 {
			t.Fatalf("startup cleanup sync calls = %d, want 1", syncCalls)
		}
		if _, statErr := os.Stat(markerPath); statErr != nil {
			t.Fatalf("startup sync ambiguity discarded ACK authority: %v", statErr)
		}
		if _, statErr := os.Stat(blobPath); !os.IsNotExist(statErr) {
			t.Fatalf("startup sync failure did not occur after unlink: %v", statErr)
		}
	})

	for _, tc := range []struct {
		name     string
		wantCode string
		mutate   func(*testing.T, string)
	}{
		{
			name:     "missing pending blob",
			wantCode: mediaCustodyErrorCleanupPending,
			mutate: func(t *testing.T, path string) {
				if err := os.Remove(path); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name:     "corrupt pending blob",
			wantCode: mediaCustodyErrorHashMismatch,
			mutate: func(t *testing.T, path string) {
				if err := os.WriteFile(path, []byte("same-size-bad!"), 0644); err != nil {
					t.Fatal(err)
				}
			},
		},
	} {
		t.Run(tc.name+" cannot prove duplicate", func(t *testing.T) {
			env := setupTestEnv(t)
			env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
			body := []byte("same-size-good")
			req := directMediaCustodyUploadRequest("duplicate-integrity", env.recipient.ID().String(), "application/octet-stream", body)
			_, _ = directMediaCustodyUpload(t, env, env.sender, req, body)
			meta := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]
			blobPath, _ := env.media.custody.blobPath(meta)
			tc.mutate(t, blobPath)
			resp, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
			if ready || resp.Status != "ERROR" || resp.ErrorCode != tc.wantCode || resp.StoreStatus != "" || resp.ExpiresAtMs != 0 {
				t.Fatalf("damaged pending blob yielded custody proof: %#v ready=%v", resp, ready)
			}
		})
	}

	t.Run("both-lane collision fails closed", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		body := []byte("protected collision")
		req := directMediaCustodyUploadRequest("disk-collision", env.recipient.ID().String(), "application/octet-stream", body)
		_, _ = directMediaCustodyUpload(t, env, env.sender, req, body)
		legacyMeta := &mediaMeta{ID: req.ID, To: req.To, Mime: req.Mime, Size: 1, CreatedAt: time.Now().UnixMilli()}
		if err := os.MkdirAll(filepath.Dir(env.media.blobPath(req.To, req.ID)), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(env.media.blobPath(req.To, req.ID), []byte("x"), 0644); err != nil {
			t.Fatal(err)
		}
		legacyJSON, _ := json.Marshal(legacyMeta)
		if err := os.WriteFile(env.media.metaPath(req.To, req.ID), legacyJSON, 0644); err != nil {
			t.Fatal(err)
		}
		if _, err := NewMediaStore(env.media.dataDir); err == nil {
			t.Fatal("both-lane collision reopened successfully")
		}
		for _, path := range []string{env.media.blobPath(req.To, req.ID), env.media.metaPath(req.To, req.ID)} {
			if _, err := os.Stat(path); err != nil {
				t.Fatalf("legacy collision artifact was not preserved %s: %v", path, err)
			}
		}
	})
}

// TC-346-05: strict download requires the exact proof and authenticated
// recipient, remains repeatable before ACK, and never consults legacy state.
func TestRelayNotificationClosure_DirectMediaBlobCustodyStrictDownloadLifecycle(t *testing.T) {
	env := setupTestEnv(t)
	env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	now := directMediaCustodyTestNow
	env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return now })
	body := []byte("repeatable exact ciphertext")
	req := directMediaCustodyUploadRequest("strict-download", env.recipient.ID().String(), "application/octet-stream", body)
	proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
	requireDirectMediaCustodyProof(t, proof, req, mediaCustodyStoreStored, "")

	legacy := directMediaCustodyRequest(t, env, env.recipient, mediaRequest{Action: "download", ID: req.ID})
	if legacy.Status != "ERROR" {
		t.Fatalf("proof-less legacy download exposed protected blob: %#v", legacy)
	}
	exact := directMediaCustodyExactRequest(proof, "download")
	for attempt := 0; attempt < 2; attempt++ {
		resp, got := directMediaCustodyDownload(t, env, env.recipient, exact)
		requireDirectMediaCustodyProof(t, resp, req, "", "")
		if !bytes.Equal(got, body) {
			t.Fatalf("strict download %d = %q, want %q", attempt, got, body)
		}
	}

	intruder := exact
	intruder.To = req.To
	if resp, _ := directMediaCustodyDownload(t, env, env.intruder, intruder); resp.ErrorCode != mediaCustodyErrorNotAuthorized {
		t.Fatalf("intruder strict download = %#v", resp)
	}
	wrong := exact
	wrong.ContentHash = strings.Repeat("b", 64)
	if resp, _ := directMediaCustodyDownload(t, env, env.recipient, wrong); resp.ErrorCode != mediaCustodyErrorIdentityConflict {
		t.Fatalf("wrong-proof strict download = %#v", resp)
	}

	ack := directMediaCustodyRequest(t, env, env.recipient, directMediaCustodyExactRequest(proof, mediaCustodyAckAction))
	requireDirectMediaCustodyProof(t, ack, req, "", mediaCustodyAckAcked)
	if resp, _ := directMediaCustodyDownload(t, env, env.recipient, exact); resp.ErrorCode != mediaCustodyErrorNotFound {
		t.Fatalf("tombstoned strict download = %#v", resp)
	}

	expiringReq := directMediaCustodyUploadRequest("strict-expiry", req.To, req.Mime, body)
	expiring, _ := directMediaCustodyUpload(t, env, env.sender, expiringReq, body)
	now = time.UnixMilli(expiring.ExpiresAtMs)
	if resp, _ := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(expiring, "download")); resp.ErrorCode != mediaCustodyErrorNotFound {
		t.Fatalf("at-expiry strict download = %#v", resp)
	}
}

// TC-346-06: only an exact recipient ACK creates the durable tombstone; it is
// idempotent, blocks upload/download authority, and preserves suppression while
// physical cleanup is retryable.
func TestRelayNotificationClosure_DirectMediaBlobCustodyExactAckOrExpiry(t *testing.T) {
	t.Run("exact idempotent ACK", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		body := []byte("ack exact bytes")
		req := directMediaCustodyUploadRequest("exact-ack", env.recipient.ID().String(), "application/octet-stream", body)
		proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		exactAck := directMediaCustodyExactRequest(proof, mediaCustodyAckAction)
		exactAck.To = req.To

		wrongPeer := directMediaCustodyRequest(t, env, env.intruder, exactAck)
		if wrongPeer.ErrorCode != mediaCustodyErrorNotAuthorized {
			t.Fatalf("wrong-peer ACK = %#v", wrongPeer)
		}
		wrongHash := exactAck
		wrongHash.ContentHash = strings.Repeat("c", 64)
		if resp := directMediaCustodyRequest(t, env, env.recipient, wrongHash); resp.ErrorCode != mediaCustodyErrorIdentityConflict {
			t.Fatalf("wrong-hash ACK = %#v", resp)
		}
		if resp := directMediaCustodyRequest(t, env, env.recipient, mediaRequest{Action: "delete", ID: req.ID}); resp.Status != "OK" {
			t.Fatalf("legacy delete against protected row = %#v", resp)
		}

		ackedBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricAcked))
		acked := directMediaCustodyRequest(t, env, env.recipient, exactAck)
		requireDirectMediaCustodyProof(t, acked, req, "", mediaCustodyAckAcked)
		if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricAcked)) - ackedBefore; delta != 1 {
			t.Fatalf("acked metric delta = %v, want 1", delta)
		}
		repeatedBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricAlreadyAcked))
		repeated := directMediaCustodyRequest(t, env, env.recipient, exactAck)
		requireDirectMediaCustodyProof(t, repeated, req, "", mediaCustodyAckAlreadyAcked)
		if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricAlreadyAcked)) - repeatedBefore; delta != 1 {
			t.Fatalf("already-acked metric delta = %v, want 1", delta)
		}
		reupload, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
		if ready || reupload.ErrorCode != mediaCustodyErrorAlreadyAcked || reupload.StoreStatus != mediaCustodyStoreAlreadyAcked {
			t.Fatalf("upload against tombstone = %#v ready=%v", reupload, ready)
		}
	})

	t.Run("cleanup failure retains tombstone and retries", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		now := directMediaCustodyTestNow
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return now })
		body := []byte("cleanup retry bytes")
		req := directMediaCustodyUploadRequest("cleanup-retry", env.recipient.ID().String(), "application/octet-stream", body)
		proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		meta := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]
		blobPath, _ := env.media.custody.blobPath(meta)
		realRemove := env.media.custody.remove
		env.media.custody.remove = func(path string) error {
			if path == blobPath {
				return errors.New("injected unlink failure")
			}
			return realRemove(path)
		}
		cleanupBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricCleanupPending))
		ackReq := directMediaCustodyExactRequest(proof, mediaCustodyAckAction)
		failed := directMediaCustodyRequest(t, env, env.recipient, ackReq)
		if failed.Status != "ERROR" || failed.ErrorCode != mediaCustodyErrorCleanupPending {
			t.Fatalf("cleanup-pending ACK = %#v", failed)
		}
		if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricCleanupPending)) - cleanupBefore; delta != 1 {
			t.Fatalf("cleanup-pending metric delta = %v, want 1", delta)
		}
		if env.media.custody.entries[custodyKeyOf(req.To, req.ID)].State != mediaCustodyStateAcked {
			t.Fatal("cleanup failure did not retain authoritative tombstone")
		}
		if resp, _ := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(proof, "download")); resp.ErrorCode != mediaCustodyErrorCleanupPending {
			t.Fatalf("cleanup-pending tombstone served bytes: %#v", resp)
		}

		now = time.UnixMilli(proof.ExpiresAtMs)
		pastExpiry := directMediaCustodyRequest(t, env, env.recipient, ackReq)
		if pastExpiry.Status != "ERROR" || pastExpiry.ErrorCode != mediaCustodyErrorCleanupPending {
			t.Fatalf("leftover tombstone was not suppressed past expiry: %#v", pastExpiry)
		}
		if got := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]; got == nil || got.State != mediaCustodyStateAcked {
			t.Fatalf("past-expiry cleanup failure removed tombstone: %#v", got)
		}

		env.media.custody.remove = realRemove
		retried := directMediaCustodyRequest(t, env, env.recipient, ackReq)
		if retried.Status != "ERROR" || retried.ErrorCode != mediaCustodyErrorNotFound {
			t.Fatalf("post-expiry cleanup retry = %#v, want cleaned not-found", retried)
		}
		if _, err := os.Stat(blobPath); !os.IsNotExist(err) {
			t.Fatalf("retry did not retire leftover blob: %v", err)
		}
	})

	t.Run("ACK cleanup uncertainty remains capacity-accounted across reopen", func(t *testing.T) {
		withMediaLimits(t, 1024, 18, func() {
			env := setupTestEnv(t)
			env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
			body := []byte("123456789012345678")
			req := directMediaCustodyUploadRequest("ack-capacity", env.recipient.ID().String(), "application/octet-stream", body)
			proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
			meta := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]
			blobPath, _ := env.media.custody.blobPath(meta)
			recipientDir, _ := env.media.custody.recipientDir(meta)
			realSync := env.media.custody.syncDir
			failSync := true
			env.media.custody.syncDir = func(path string) error {
				if failSync && path == recipientDir {
					return errors.New("injected ACK directory sync failure")
				}
				return realSync(path)
			}
			ackReq := directMediaCustodyExactRequest(proof, mediaCustodyAckAction)
			failed := directMediaCustodyRequest(t, env, env.recipient, ackReq)
			if failed.Status != "ERROR" || failed.ErrorCode != mediaCustodyErrorCleanupPending {
				t.Fatalf("ACK sync uncertainty = %#v", failed)
			}
			if _, err := os.Stat(blobPath); err != nil {
				t.Fatalf("ACK uncertainty lost leftover bytes before durable cleanup: %v", err)
			}
			if got := testutil.ToFloat64(mediaCustodyBytesPendingGauge); got != float64(len(body)) {
				t.Fatalf("ACK uncertainty byte gauge = %v, want %d", got, len(body))
			}

			otherBody := []byte("x")
			otherReq := directMediaCustodyUploadRequest("ack-capacity-other", req.To, req.Mime, otherBody)
			other, ready := directMediaCustodyUpload(t, env, env.sender, otherReq, otherBody)
			if ready || (other.ErrorCode != mediaCustodyErrorCleanupPending && other.ErrorCode != mediaCustodyErrorFull) {
				t.Fatalf("over-admission during ACK cleanup uncertainty = %#v ready=%v", other, ready)
			}

			failSync = false
			retried := directMediaCustodyRequest(t, env, env.recipient, ackReq)
			requireDirectMediaCustodyProof(t, retried, req, "", mediaCustodyAckAlreadyAcked)
			if _, err := os.Stat(blobPath); !os.IsNotExist(err) {
				t.Fatalf("durable ACK retry left bytes behind: %v", err)
			}
			other, ready = directMediaCustodyUpload(t, env, env.sender, otherReq, otherBody)
			if !ready || other.Status != "OK" || other.StoreStatus != mediaCustodyStoreStored {
				t.Fatalf("post-cleanup safe admission = %#v ready=%v", other, ready)
			}
			reopened, err := NewMediaStore(env.media.dataDir)
			if err != nil {
				t.Fatalf("reopen ACK capacity fixture: %v", err)
			}
			if _, err := os.Stat(blobPath); !os.IsNotExist(err) {
				t.Fatalf("reopen reconstructed old pending bytes: %v", err)
			}
			if got := reopened.custody.entries[custodyKeyOf(otherReq.To, otherReq.ID)]; got == nil || got.State != mediaCustodyStatePending {
				t.Fatalf("reopen lost safely admitted replacement: %#v", got)
			}
		})
	})

	t.Run("expiry normalizes synchronously", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		now := directMediaCustodyTestNow
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return now })
		body := []byte("expiry bytes")
		req := directMediaCustodyUploadRequest("exact-expiry", env.recipient.ID().String(), "application/octet-stream", body)
		proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		expiredBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricExpired))
		now = time.UnixMilli(proof.ExpiresAtMs)
		ack := directMediaCustodyRequest(t, env, env.recipient, directMediaCustodyExactRequest(proof, mediaCustodyAckAction))
		if ack.Status != "ERROR" || ack.ErrorCode != mediaCustodyErrorNotFound {
			t.Fatalf("ACK at expiry = %#v", ack)
		}
		if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricExpired)) - expiredBefore; delta != 1 {
			t.Fatalf("expired metric delta = %v, want 1", delta)
		}
		if env.media.custody.entries[custodyKeyOf(req.To, req.ID)] != nil {
			t.Fatal("expired authority remains indexed")
		}
	})

	for _, state := range []string{mediaCustodyStatePending, mediaCustodyStateAcked} {
		t.Run(state+" nonregular blob fails expiry closed", func(t *testing.T) {
			env := setupTestEnv(t)
			env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
			now := directMediaCustodyTestNow
			env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return now })
			body := []byte("lstat failure bytes")
			req := directMediaCustodyUploadRequest("expiry-lstat-"+state, env.recipient.ID().String(), "application/octet-stream", body)
			proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
			ackReq := directMediaCustodyExactRequest(proof, mediaCustodyAckAction)
			if state == mediaCustodyStateAcked {
				acked := directMediaCustodyRequest(t, env, env.recipient, ackReq)
				requireDirectMediaCustodyProof(t, acked, req, "", mediaCustodyAckAcked)
			}
			meta := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]
			blobPath, _ := env.media.custody.blobPath(meta)
			markerPath, _ := env.media.custody.markerPath(meta)
			if err := os.Remove(blobPath); err != nil && !os.IsNotExist(err) {
				t.Fatal(err)
			}
			if err := os.Mkdir(blobPath, 0755); err != nil {
				t.Fatal(err)
			}
			expiredBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricExpired))
			cleanupBefore := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricCleanupPending))
			now = time.UnixMilli(proof.ExpiresAtMs)
			failed := directMediaCustodyRequest(t, env, env.recipient, ackReq)
			if failed.Status != "ERROR" || failed.ErrorCode != mediaCustodyErrorCleanupPending {
				t.Fatalf("nonregular blob expiry response = %#v", failed)
			}
			if got := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]; got == nil || got.State != state {
				t.Fatalf("nonregular blob expiry removed index: %#v", got)
			}
			if _, err := os.Stat(markerPath); err != nil {
				t.Fatalf("nonregular blob expiry removed marker: %v", err)
			}
			if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricExpired)) - expiredBefore; delta != 0 {
				t.Fatalf("nonregular blob reported expired delta %v", delta)
			}
			if delta := testutil.ToFloat64(mediaCustodyOutcomesCounter.WithLabelValues(mediaCustodyMetricCleanupPending)) - cleanupBefore; delta != 1 {
				t.Fatalf("nonregular blob cleanup-pending delta %v, want 1", delta)
			}
		})
	}
}

func TestRelayNotificationClosure_DirectMediaBlobCustodyConcurrentStoreDownloadAckConverges(t *testing.T) {
	env := setupTestEnv(t)
	env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	body := []byte("concurrent convergence")
	req := directMediaCustodyUploadRequest("converge", env.recipient.ID().String(), "application/octet-stream", body)
	proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
	start := make(chan struct{})
	responses := make(chan mediaResponse, 3)
	var wg sync.WaitGroup

	wg.Add(1)
	go func() {
		defer wg.Done()
		<-start
		resp, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		responses <- resp
	}()
	wg.Add(1)
	go func() {
		defer wg.Done()
		<-start
		resp, _ := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(proof, "download"))
		responses <- resp
	}()
	wg.Add(1)
	go func() {
		defer wg.Done()
		<-start
		responses <- directMediaCustodyRequest(t, env, env.recipient, directMediaCustodyExactRequest(proof, mediaCustodyAckAction))
	}()
	close(start)
	wg.Wait()
	close(responses)
	for resp := range responses {
		if resp.Status == "OK" {
			continue
		}
		if resp.ErrorCode != mediaCustodyErrorAlreadyAcked && resp.ErrorCode != mediaCustodyErrorNotFound {
			t.Fatalf("non-convergent concurrent outcome: %#v", resp)
		}
	}

	meta := env.media.custody.entries[custodyKeyOf(req.To, req.ID)]
	if meta == nil || meta.State != mediaCustodyStateAcked {
		t.Fatalf("final convergence state = %#v, want tombstone", meta)
	}
	if resp := directMediaCustodyRequest(t, env, env.recipient, directMediaCustodyExactRequest(proof, mediaCustodyAckAction)); resp.AckStatus != mediaCustodyAckAlreadyAcked {
		t.Fatalf("final repeated ACK = %#v", resp)
	}
	blobPath, _ := env.media.custody.blobPath(meta)
	if _, err := os.Stat(blobPath); !os.IsNotExist(err) {
		t.Fatalf("converged tombstone retained blob: %v", err)
	}
}

// TC-346-07: legacy list/delete/pruning cannot discover or retire the strict
// subtree, and an upgraded admission-off reopen can still drain it.
func TestRelayNotificationClosure_DirectMediaBlobCustodyLegacyRollbackPreservation(t *testing.T) {
	env := setupTestEnv(t)
	env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	body := []byte("rollback protected")
	req := directMediaCustodyUploadRequest("rollback-protected", env.recipient.ID().String(), "application/octet-stream", body)
	proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)

	list := directMediaCustodyRequest(t, env, env.recipient, mediaRequest{Action: "list"})
	if list.Status != "OK" || len(list.Blobs) != 0 {
		t.Fatalf("legacy list exposed protected state: %#v", list)
	}
	if resp := directMediaCustodyRequest(t, env, env.recipient, mediaRequest{Action: "delete", ID: req.ID}); resp.Status != "OK" {
		t.Fatalf("legacy rollback delete response = %#v", resp)
	}

	for i := 0; i < 3; i++ {
		env.upload(t, env.sender, fmt.Sprintf("legacy-prune-%d", i), req.To, "image/jpeg", []byte{byte(i)})
	}
	if resp, got := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(proof, "download")); resp.Status != "OK" || !bytes.Equal(got, body) {
		t.Fatalf("legacy activity changed protected authority: %#v body=%q", resp, got)
	}

	reopened, err := NewMediaStore(env.media.dataDir)
	if err != nil {
		t.Fatalf("upgraded rollback reopen: %v", err)
	}
	reopened.SetDirectMediaBlobCustodyAdmissionEnabled(false)
	installDirectMediaCustodyStore(t, env, reopened)
	duplicate, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
	if ready {
		t.Fatal("admission-off exact drain probe requested body")
	}
	requireDirectMediaCustodyProof(t, duplicate, req, mediaCustodyStoreDuplicate, "")
	ack := directMediaCustodyRequest(t, env, env.recipient, directMediaCustodyExactRequest(duplicate, mediaCustodyAckAction))
	requireDirectMediaCustodyProof(t, ack, req, "", mediaCustodyAckAcked)

	t.Run("legacy replacement commit excludes stale cleanup", func(t *testing.T) {
		raceEnv := setupTestEnv(t)
		peerID := raceEnv.recipient.ID().String()
		oldBody := []byte("old legacy bytes")
		newBody := []byte("new legacy bytes survive")
		raceEnv.upload(t, raceEnv.sender, "legacy-commit-race", peerID, "application/octet-stream", oldBody)
		raceEnv.media.mu.Lock()
		raceEnv.media.index["legacy-commit-race"].CreatedAt = time.Now().Add(-2 * mediaTTL).UnixMilli()
		raceEnv.media.mu.Unlock()

		type hookObservation struct {
			laneHeld       bool
			cleanupCrossed bool
		}
		observed := make(chan hookObservation, 1)
		cleanupDone := make(chan struct{})
		raceEnv.media.legacyAfterBlobRenameForTest = func() {
			laneHeld := !raceEnv.media.laneMu.TryLock()
			if !laneHeld {
				raceEnv.media.laneMu.Unlock()
			}
			go func() {
				raceEnv.media.cleanupExpired()
				close(cleanupDone)
			}()
			cleanupCrossed := false
			select {
			case <-cleanupDone:
				cleanupCrossed = true
			case <-time.After(50 * time.Millisecond):
			}
			observed <- hookObservation{laneHeld: laneHeld, cleanupCrossed: cleanupCrossed}
		}
		raceEnv.upload(t, raceEnv.sender, "legacy-commit-race", peerID, "application/octet-stream", newBody)
		observation := <-observed
		if !observation.laneHeld || observation.cleanupCrossed {
			t.Fatalf("legacy rename-to-metadata critical section observation = %+v", observation)
		}
		select {
		case <-cleanupDone:
		case <-time.After(2 * time.Second):
			t.Fatal("legacy cleanup did not finish after commit released lane lock")
		}
		if got := downloadMedia(t, raceEnv, raceEnv.recipient, "legacy-commit-race"); !bytes.Equal(got, newBody) {
			t.Fatalf("stale cleanup deleted replacement bytes: got %q want %q", got, newBody)
		}
	})

	t.Run("legacy download authorization cannot retarget replacement", func(t *testing.T) {
		raceEnv := setupTestEnv(t)
		id := "legacy-download-replacement-race"
		oldRecipient := raceEnv.recipient.ID().String()
		newRecipient := raceEnv.intruder.ID().String()
		oldBody := []byte("old recipient bytes")
		newBody := []byte("replacement belongs elsewhere")
		raceEnv.upload(t, raceEnv.sender, id, oldRecipient, "application/octet-stream", oldBody)

		authorized := make(chan struct{})
		releaseAuthorization := make(chan struct{})
		raceEnv.media.legacyAfterDownloadAuthorizationForTest = func() {
			raceEnv.media.legacyAfterDownloadAuthorizationForTest = nil
			close(authorized)
			<-releaseAuthorization
		}
		type downloadResult struct {
			meta *mediaMeta
			body []byte
			err  error
		}
		downloaded := make(chan downloadResult, 1)
		go func() {
			meta, f, err := raceEnv.media.openLegacyMediaForDownload(id, oldRecipient)
			if err != nil {
				downloaded <- downloadResult{err: err}
				return
			}
			body, readErr := io.ReadAll(f)
			closeErr := f.Close()
			if readErr == nil {
				readErr = closeErr
			}
			downloaded <- downloadResult{meta: meta, body: body, err: readErr}
		}()
		<-authorized
		if raceEnv.media.laneMu.TryLock() {
			raceEnv.media.laneMu.Unlock()
			close(releaseAuthorization)
			t.Fatal("legacy download authorization hook did not hold identity lane")
		}

		replacementStarted := make(chan struct{})
		replacementDone := make(chan error, 1)
		go func() {
			close(replacementStarted)
			replacementDone <- directMediaCustodyCommitLegacyReplacement(
				raceEnv.media,
				id,
				newRecipient,
				"application/octet-stream",
				newBody,
			)
		}()
		<-replacementStarted
		select {
		case err := <-replacementDone:
			close(releaseAuthorization)
			t.Fatalf("same-ID replacement crossed authorized download decision: %v", err)
		case <-time.After(50 * time.Millisecond):
		}
		close(releaseAuthorization)

		result := <-downloaded
		if result.err != nil || result.meta == nil || result.meta.To != oldRecipient || !bytes.Equal(result.body, oldBody) {
			t.Fatalf("authorized download retargeted replacement: meta=%#v body=%q err=%v", result.meta, result.body, result.err)
		}
		if err := <-replacementDone; err != nil {
			t.Fatalf("commit same-ID replacement after download decision: %v", err)
		}
		if _, f, err := raceEnv.media.openLegacyMediaForDownload(id, oldRecipient); !errors.Is(err, errLegacyMediaNotAuthorized) {
			if f != nil {
				_ = f.Close()
			}
			t.Fatalf("old recipient retained replacement authority: %v", err)
		}
		meta, f, err := raceEnv.media.openLegacyMediaForDownload(id, newRecipient)
		if err != nil {
			t.Fatalf("new recipient cannot open replacement: %v", err)
		}
		got, readErr := io.ReadAll(f)
		_ = f.Close()
		if readErr != nil || meta.To != newRecipient || !bytes.Equal(got, newBody) {
			t.Fatalf("replacement after authorized download = meta %#v body %q err=%v", meta, got, readErr)
		}
	})

	t.Run("legacy delete authorization cannot remove replacement", func(t *testing.T) {
		raceEnv := setupTestEnv(t)
		id := "legacy-delete-replacement-race"
		oldRecipient := raceEnv.recipient.ID().String()
		newRecipient := raceEnv.intruder.ID().String()
		oldBody := []byte("old delete target")
		newBody := []byte("replacement must survive")
		raceEnv.upload(t, raceEnv.sender, id, oldRecipient, "application/octet-stream", oldBody)

		authorized := make(chan struct{})
		releaseAuthorization := make(chan struct{})
		raceEnv.media.legacyAfterDeleteAuthorizationForTest = func() {
			raceEnv.media.legacyAfterDeleteAuthorizationForTest = nil
			close(authorized)
			<-releaseAuthorization
		}
		type deleteResult struct {
			size int64
			err  error
		}
		deleted := make(chan deleteResult, 1)
		go func() {
			size, err := raceEnv.media.deleteLegacyMediaAuthorized(id, oldRecipient)
			deleted <- deleteResult{size: size, err: err}
		}()
		<-authorized
		if raceEnv.media.laneMu.TryLock() {
			raceEnv.media.laneMu.Unlock()
			close(releaseAuthorization)
			t.Fatal("legacy delete authorization hook did not hold identity lane")
		}

		replacementStarted := make(chan struct{})
		replacementDone := make(chan error, 1)
		go func() {
			close(replacementStarted)
			replacementDone <- directMediaCustodyCommitLegacyReplacement(
				raceEnv.media,
				id,
				newRecipient,
				"application/octet-stream",
				newBody,
			)
		}()
		<-replacementStarted
		select {
		case err := <-replacementDone:
			close(releaseAuthorization)
			t.Fatalf("same-ID replacement crossed authorized delete decision: %v", err)
		case <-time.After(50 * time.Millisecond):
		}
		close(releaseAuthorization)

		result := <-deleted
		if result.err != nil || result.size != int64(len(oldBody)) {
			t.Fatalf("authorized old-row delete = %+v", result)
		}
		if err := <-replacementDone; err != nil {
			t.Fatalf("commit same-ID replacement after delete decision: %v", err)
		}
		if _, f, err := raceEnv.media.openLegacyMediaForDownload(id, oldRecipient); !errors.Is(err, errLegacyMediaNotAuthorized) {
			if f != nil {
				_ = f.Close()
			}
			t.Fatalf("old recipient retained replacement authority after delete: %v", err)
		}
		meta, f, err := raceEnv.media.openLegacyMediaForDownload(id, newRecipient)
		if err != nil {
			t.Fatalf("new recipient cannot open replacement after stale delete: %v", err)
		}
		got, readErr := io.ReadAll(f)
		_ = f.Close()
		if readErr != nil || meta.To != newRecipient || !bytes.Equal(got, newBody) {
			t.Fatalf("replacement after stale delete = meta %#v body %q err=%v", meta, got, readErr)
		}
	})
}

// TC-362-01b: one canonical blob ID owns independent exact (recipient, id)
// custody per physical target. Sibling recipients coexist and converge
// independently across ACK, expiry, blocked/ACK-cleanup ambiguity and
// restart; per-recipient quotas and the GLOBAL legacy/protected ID fence are
// unchanged.
func TestRelayNotificationClosure_DirectMediaBlobCustodyRecipientFanoutIsolation(t *testing.T) {
	t.Run("same blob to two recipients coexists and converges independently", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		body := []byte("fanout blob bytes")
		recipientA := env.recipient.ID().String()
		recipientB := env.intruder.ID().String()
		reqA := directMediaCustodyUploadRequest("fanout-blob", recipientA, "application/octet-stream", body)
		reqB := directMediaCustodyUploadRequest("fanout-blob", recipientB, "application/octet-stream", body)

		storedA, ready := directMediaCustodyUpload(t, env, env.sender, reqA, body)
		if !ready {
			t.Fatalf("target A upload = %#v", storedA)
		}
		requireDirectMediaCustodyProof(t, storedA, reqA, mediaCustodyStoreStored, "")
		storedB, ready := directMediaCustodyUpload(t, env, env.sender, reqB, body)
		if !ready {
			t.Fatalf("sibling target B upload = %#v", storedB)
		}
		requireDirectMediaCustodyProof(t, storedB, reqB, mediaCustodyStoreStored, "")
		if got := testutil.ToFloat64(mediaCustodyBlobsPendingGauge); got != 2 {
			t.Fatalf("aggregate pending gauge = %v, want both sibling rows", got)
		}
		if got := testutil.ToFloat64(mediaCustodyBytesPendingGauge); got != float64(2*len(body)) {
			t.Fatalf("aggregate byte gauge = %v, want %d", got, 2*len(body))
		}

		// Exact duplicates stay per-target idempotent.
		dupA, ready := directMediaCustodyUpload(t, env, env.sender, reqA, body)
		if ready {
			t.Fatal("duplicate A requested body transfer")
		}
		requireDirectMediaCustodyProof(t, dupA, reqA, mediaCustodyStoreDuplicate, "")
		dupB, ready := directMediaCustodyUpload(t, env, env.sender, reqB, body)
		if ready {
			t.Fatal("duplicate B requested body transfer")
		}
		requireDirectMediaCustodyProof(t, dupB, reqB, mediaCustodyStoreDuplicate, "")

		// Tuple drift under the SAME (To, ID) remains refused.
		for _, tc := range []struct {
			name string
			edit func(*mediaRequest)
		}{
			{name: "mime", edit: func(r *mediaRequest) { r.Mime = "image/png" }},
			{name: "size", edit: func(r *mediaRequest) { r.Size++ }},
			{name: "hash", edit: func(r *mediaRequest) { r.ContentHash = strings.Repeat("b", 64) }},
		} {
			mutated := reqA
			tc.edit(&mutated)
			resp, sawReady := directMediaCustodyUpload(t, env, env.sender, mutated, body)
			if sawReady || resp.ErrorCode != mediaCustodyErrorIdentityConflict {
				t.Fatalf("same-pair drift %s accepted: %#v ready=%v", tc.name, resp, sawReady)
			}
		}

		// Cross-target access refuses: a stream authenticated as B cannot name
		// A's custody row.
		crossed := directMediaCustodyExactRequest(storedA, "download")
		crossed.To = recipientA
		if resp := directMediaCustodyRequest(t, env, env.intruder, crossed); resp.ErrorCode != mediaCustodyErrorNotAuthorized {
			t.Fatalf("cross-recipient download authorization = %#v", resp)
		}
		crossedAck := directMediaCustodyExactRequest(storedA, mediaCustodyAckAction)
		crossedAck.To = recipientA
		if resp := directMediaCustodyRequest(t, env, env.intruder, crossedAck); resp.ErrorCode != mediaCustodyErrorNotAuthorized {
			t.Fatalf("cross-recipient ACK authorization = %#v", resp)
		}

		// A's ACK releases only A's charged state; B stays downloadable
		// before and after restart.
		ackA := directMediaCustodyExactRequest(storedA, mediaCustodyAckAction)
		acked := directMediaCustodyRequest(t, env, env.recipient, ackA)
		requireDirectMediaCustodyProof(t, acked, ackA, "", mediaCustodyAckAcked)
		if resp, _ := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(storedA, "download")); resp.ErrorCode != mediaCustodyErrorNotFound {
			t.Fatalf("A download after ACK = %#v, want not-found tombstone", resp)
		}
		if resp, gotBody := directMediaCustodyDownload(t, env, env.intruder, directMediaCustodyExactRequest(storedB, "download")); resp.Status != "OK" || !bytes.Equal(gotBody, body) {
			t.Fatalf("B download after A ACK = %#v body=%q", resp, gotBody)
		}
		if got := testutil.ToFloat64(mediaCustodyBytesPendingGauge); got != float64(len(body)) {
			t.Fatalf("A ACK released sibling bytes: gauge = %v, want %d", got, len(body))
		}

		reopened, err := NewMediaStore(env.media.dataDir)
		if err != nil {
			t.Fatalf("restart with sibling custody rows: %v", err)
		}
		reopened.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		reopened.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		installDirectMediaCustodyStore(t, env, reopened)
		if resp, gotBody := directMediaCustodyDownload(t, env, env.intruder, directMediaCustodyExactRequest(storedB, "download")); resp.Status != "OK" || !bytes.Equal(gotBody, body) {
			t.Fatalf("B download after restart = %#v body=%q", resp, gotBody)
		}
		if resp, _ := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(storedA, "download")); resp.ErrorCode != mediaCustodyErrorNotFound {
			t.Fatalf("A tombstone lost across restart: %#v", resp)
		}
	})

	t.Run("per-recipient count quota admits each sibling target once", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		env.media.custody.maxCount = 1
		body := []byte("quota bytes")
		recipientA := env.recipient.ID().String()
		recipientB := env.intruder.ID().String()

		first, ready := directMediaCustodyUpload(t, env, env.sender, directMediaCustodyUploadRequest("quota-blob", recipientA, "application/octet-stream", body), body)
		if !ready || first.StoreStatus != mediaCustodyStoreStored {
			t.Fatalf("A quota admission = %#v", first)
		}
		sibling, ready := directMediaCustodyUpload(t, env, env.sender, directMediaCustodyUploadRequest("quota-blob", recipientB, "application/octet-stream", body), body)
		if !ready || sibling.StoreStatus != mediaCustodyStoreStored {
			t.Fatalf("B sibling admission under A's full quota = %#v", sibling)
		}
		overA, ready := directMediaCustodyUpload(t, env, env.sender, directMediaCustodyUploadRequest("quota-blob-2", recipientA, "application/octet-stream", body), body)
		if ready || overA.ErrorCode != mediaCustodyErrorFull {
			t.Fatalf("A second row over quota = %#v ready=%v", overA, ready)
		}
		overB, ready := directMediaCustodyUpload(t, env, env.sender, directMediaCustodyUploadRequest("quota-blob-2", recipientB, "application/octet-stream", body), body)
		if ready || overB.ErrorCode != mediaCustodyErrorFull {
			t.Fatalf("B second row over quota = %#v ready=%v", overB, ready)
		}
	})

	t.Run("concurrent sibling preparations both commit", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		body := []byte("concurrent sibling bytes")
		recipients := []string{env.recipient.ID().String(), env.intruder.ID().String()}
		responses := make([]mediaResponse, len(recipients))
		readiness := make([]bool, len(recipients))
		var wg sync.WaitGroup
		for index, recipient := range recipients {
			wg.Add(1)
			go func(slot int, to string) {
				defer wg.Done()
				req := directMediaCustodyUploadRequest("concurrent-sibling", to, "application/octet-stream", body)
				responses[slot], readiness[slot] = directMediaCustodyUpload(t, env, env.sender, req, body)
			}(index, recipient)
		}
		wg.Wait()
		for index, recipient := range recipients {
			if !readiness[index] || responses[index].StoreStatus != mediaCustodyStoreStored {
				t.Fatalf("concurrent sibling %s = %#v ready=%v", recipient, responses[index], readiness[index])
			}
			if directMediaCustodyFindEntry(env.media, recipient, "concurrent-sibling") == nil {
				t.Fatalf("concurrent sibling %s missing from entries", recipient)
			}
		}
	})

	t.Run("A blocked ambiguity never blocks or mutates B and both converge", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		body := []byte("blocked isolation bytes")
		recipientA := env.recipient.ID().String()
		recipientB := env.intruder.ID().String()
		reqA := directMediaCustodyUploadRequest("blocked-isolation", recipientA, "application/octet-stream", body)
		reqB := directMediaCustodyUploadRequest("blocked-isolation", recipientB, "application/octet-stream", body)

		realSync := env.media.custody.syncDir
		failedFinalBarrier := false
		markerPath := filepath.Join(env.media.custody.rootDir, recipientA, reqA.ID+".custody")
		env.media.custody.syncDir = func(path string) error {
			if !failedFinalBarrier && fileExists(markerPath) {
				failedFinalBarrier = true
				return errors.New("lost A final directory barrier")
			}
			return realSync(path)
		}
		ambiguous, ready := directMediaCustodyUpload(t, env, env.sender, reqA, body)
		if !ready || ambiguous.ErrorCode != mediaCustodyErrorStorage {
			t.Fatalf("A post-rename ambiguity = %#v ready=%v", ambiguous, ready)
		}
		env.media.custody.syncDir = realSync
		if directMediaCustodyFindBlocked(env.media, recipientA, reqA.ID) == nil {
			t.Fatal("A ambiguity did not retain blocked capacity")
		}

		// While A is blocked, the global legacy fence still owns the ID...
		if resp := directMediaCustodyRequest(t, env, env.sender, mediaRequest{Action: "upload", ID: reqA.ID, To: recipientA, Size: 1, Mime: "image/jpeg"}); resp.Status != "ERROR" {
			t.Fatalf("legacy upload during A blocked = %#v", resp)
		}
		// ...but sibling B's same-ID strict admission proceeds untouched.
		storedB, ready := directMediaCustodyUpload(t, env, env.sender, reqB, body)
		if !ready || storedB.StoreStatus != mediaCustodyStoreStored {
			t.Fatalf("B admission during A blocked = %#v ready=%v", storedB, ready)
		}

		// A's exact retry reconciles its blocked commit into a duplicate
		// proof; B remains byte-identical and downloadable.
		recoveredA, ready := directMediaCustodyUpload(t, env, env.sender, reqA, body)
		if ready {
			t.Fatal("A recovery requested a second body")
		}
		requireDirectMediaCustodyProof(t, recoveredA, reqA, mediaCustodyStoreDuplicate, "")
		if resp, gotBody := directMediaCustodyDownload(t, env, env.intruder, directMediaCustodyExactRequest(storedB, "download")); resp.Status != "OK" || !bytes.Equal(gotBody, body) {
			t.Fatalf("B after A blocked recovery = %#v body=%q", resp, gotBody)
		}
		if resp, gotBody := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(recoveredA, "download")); resp.Status != "OK" || !bytes.Equal(gotBody, body) {
			t.Fatalf("A after blocked recovery = %#v body=%q", resp, gotBody)
		}
	})

	t.Run("A ACK-cleanup ambiguity leaves B independent before and after restart", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		body := []byte("ack cleanup isolation bytes")
		recipientA := env.recipient.ID().String()
		recipientB := env.intruder.ID().String()
		reqA := directMediaCustodyUploadRequest("ack-isolation", recipientA, "application/octet-stream", body)
		reqB := directMediaCustodyUploadRequest("ack-isolation", recipientB, "application/octet-stream", body)
		storedA, _ := directMediaCustodyUpload(t, env, env.sender, reqA, body)
		storedB, _ := directMediaCustodyUpload(t, env, env.sender, reqB, body)

		metaA := directMediaCustodyFindEntry(env.media, recipientA, reqA.ID)
		if metaA == nil {
			t.Fatal("A row missing before ACK ambiguity")
		}
		blobPathA, err := env.media.custody.blobPath(metaA)
		if err != nil {
			t.Fatalf("resolve A blob path: %v", err)
		}
		realRemove := env.media.custody.remove
		env.media.custody.remove = func(path string) error {
			if path == blobPathA {
				return errors.New("injected A unlink failure")
			}
			return realRemove(path)
		}
		ackA := directMediaCustodyExactRequest(storedA, mediaCustodyAckAction)
		failed := directMediaCustodyRequest(t, env, env.recipient, ackA)
		if failed.ErrorCode != mediaCustodyErrorCleanupPending {
			t.Fatalf("A ACK ambiguity = %#v", failed)
		}

		// While A's cleanup is ambiguous the global fence still owns the ID,
		// and B is never blocked, mutated, uncharged or deleted.
		if resp := directMediaCustodyRequest(t, env, env.sender, mediaRequest{Action: "upload", ID: reqA.ID, To: recipientA, Size: 1, Mime: "image/jpeg"}); resp.Status != "ERROR" {
			t.Fatalf("legacy upload during A ACK ambiguity = %#v", resp)
		}
		if resp, gotBody := directMediaCustodyDownload(t, env, env.intruder, directMediaCustodyExactRequest(storedB, "download")); resp.Status != "OK" || !bytes.Equal(gotBody, body) {
			t.Fatalf("B download during A ACK ambiguity = %#v body=%q", resp, gotBody)
		}
		ackB := directMediaCustodyExactRequest(storedB, mediaCustodyAckAction)
		ackedB := directMediaCustodyRequest(t, env, env.intruder, ackB)
		requireDirectMediaCustodyProof(t, ackedB, ackB, "", mediaCustodyAckAcked)

		// A converges independently once its barrier heals.
		env.media.custody.remove = realRemove
		retriedA := directMediaCustodyRequest(t, env, env.recipient, ackA)
		requireDirectMediaCustodyProof(t, retriedA, ackA, "", mediaCustodyAckAlreadyAcked)
		if _, err := os.Stat(blobPathA); !os.IsNotExist(err) {
			t.Fatalf("A cleanup retry left bytes behind: %v", err)
		}

		reopened, err := NewMediaStore(env.media.dataDir)
		if err != nil {
			t.Fatalf("restart after independent sibling convergence: %v", err)
		}
		reopened.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		reopened.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		installDirectMediaCustodyStore(t, env, reopened)
		if resp, _ := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(storedA, "download")); resp.ErrorCode != mediaCustodyErrorNotFound {
			t.Fatalf("A resurrection after restart: %#v", resp)
		}
		if resp, _ := directMediaCustodyDownload(t, env, env.intruder, directMediaCustodyExactRequest(storedB, "download")); resp.ErrorCode != mediaCustodyErrorNotFound {
			t.Fatalf("B resurrection after restart: %#v", resp)
		}
	})

	t.Run("global legacy fence spans reservation and sibling state", func(t *testing.T) {
		env := setupTestEnv(t)
		env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		env.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return directMediaCustodyTestNow })
		body := []byte("fence bytes")
		recipientA := env.recipient.ID().String()
		recipientB := env.intruder.ID().String()

		// Legacy-first: the bare ID blocks strict admission for EVERY
		// recipient, not only the legacy row's own.
		env.upload(t, env.sender, "legacy-owned", recipientA, "image/jpeg", body)
		strictOther := directMediaCustodyUploadRequest("legacy-owned", recipientB, "application/octet-stream", body)
		resp, sawReady := directMediaCustodyUpload(t, env, env.sender, strictOther, body)
		if sawReady || resp.ErrorCode != mediaCustodyErrorIdentityConflict {
			t.Fatalf("strict sibling admitted under legacy-owned ID: %#v ready=%v", resp, sawReady)
		}

		// Strict reservation (pre-publication) already owns the fence.
		reserveReq := directMediaCustodyUploadRequest("reserved-fence", recipientA, "application/octet-stream", body)
		prepared, failure := env.media.custody.prepareUpload(&reserveReq)
		if failure != nil || prepared == nil || prepared.reservation == nil {
			t.Fatalf("hold strict reservation = (%#v, %v)", prepared, failure)
		}
		if err := env.media.reserveLegacyMediaID("reserved-fence"); err == nil {
			env.media.releaseLegacyMediaID("reserved-fence")
			t.Fatal("legacy lane reserved an ID owned by a strict reservation")
		}
		env.media.custody.abortReservation(prepared.reservation)
		if err := env.media.reserveLegacyMediaID("reserved-fence"); err != nil {
			t.Fatalf("aborted strict reservation still fenced the legacy lane: %v", err)
		}
		env.media.releaseLegacyMediaID("reserved-fence")
	})
}
