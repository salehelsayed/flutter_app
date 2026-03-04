//go:build integration

package integration_test

import (
	"bytes"
	"crypto/rand"
	"os"
	"path/filepath"
	"testing"
)

// ---------- 1:1 Media integration tests ----------

// TestRelayMediaUploadDownload verifies the 1:1 media happy path through the
// real relay: upload from Node A → download on Node B → data matches →
// auto-deleted after download.
func TestRelayMediaUploadDownload(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, _ := startNode(t)
	nodeB, peerIdB := startNode(t)

	dir := t.TempDir()

	// Create a 4KB file with random data.
	originalData := make([]byte, 4096)
	if _, err := rand.Read(originalData); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	uploadPath := filepath.Join(dir, "media_upload.jpg")
	if err := os.WriteFile(uploadPath, originalData, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	blobID := "smoke-1to1-blob"

	// Node A uploads to Node B (1:1 mode — no allowedPeers).
	if err := nodeA.MediaUpload(blobID, peerIdB, "image/jpeg", uploadPath, nil); err != nil {
		t.Fatalf("MediaUpload: %v", err)
	}
	t.Log("1:1 media upload succeeded")

	// Node B downloads.
	downloadPath := filepath.Join(dir, "media_download.jpg")
	mime, size, err := nodeB.MediaDownload(blobID, downloadPath)
	if err != nil {
		t.Fatalf("MediaDownload: %v", err)
	}
	t.Logf("downloaded: mime=%s size=%d", mime, size)

	if mime != "image/jpeg" {
		t.Errorf("mime=%s, want image/jpeg", mime)
	}
	if size != int64(len(originalData)) {
		t.Errorf("size=%d, want %d", size, len(originalData))
	}

	downloadedData, err := os.ReadFile(downloadPath)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if !bytes.Equal(originalData, downloadedData) {
		t.Error("downloaded data does not match uploaded data")
	}

	// Verify auto-deleted (second download should fail).
	downloadPath2 := filepath.Join(dir, "media_download2.jpg")
	_, _, err = nodeB.MediaDownload(blobID, downloadPath2)
	if err == nil {
		t.Error("expected error on second download (blob should be auto-deleted)")
	} else {
		t.Logf("second download correctly failed: %v", err)
	}

	t.Log("1:1 media upload/download verified successfully")
}

// ---------- Group Media integration tests (AllowedPeers) ----------

// TestRelayGroupMediaUploadDownload verifies the group media flow:
// upload with allowedPeers → all allowed members can download → blob
// persists after download (no auto-delete) → unauthorized peer rejected.
func TestRelayGroupMediaUploadDownload(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, peerIdA := startNode(t) // sender / member 1
	nodeB, peerIdB := startNode(t) // member 2
	nodeC, _ := startNode(t)       // outsider (NOT in allowedPeers)

	t.Logf("NodeA (sender) = %s", peerIdA)
	t.Logf("NodeB (member) = %s", peerIdB)

	dir := t.TempDir()

	// Create a 4KB file with random data (simulates an encrypted image).
	originalData := make([]byte, 4096)
	if _, err := rand.Read(originalData); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	uploadPath := filepath.Join(dir, "group_media.enc")
	if err := os.WriteFile(uploadPath, originalData, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	blobID := "smoke-group-blob"
	groupID := "group-uuid-test"
	allowedPeers := []string{peerIdA, peerIdB} // both members, NOT nodeC

	// --- Upload with AllowedPeers ---
	if err := nodeA.MediaUpload(blobID, groupID, "image/jpeg", uploadPath, allowedPeers); err != nil {
		t.Fatalf("MediaUpload (group): %v", err)
	}
	t.Log("group media upload succeeded")

	// --- Member B downloads ---
	downloadPathB := filepath.Join(dir, "download_b.enc")
	mime, size, err := nodeB.MediaDownload(blobID, downloadPathB)
	if err != nil {
		t.Fatalf("MediaDownload (member B): %v", err)
	}
	t.Logf("member B download: mime=%s size=%d", mime, size)

	downloadedB, err := os.ReadFile(downloadPathB)
	if err != nil {
		t.Fatalf("ReadFile B: %v", err)
	}
	if !bytes.Equal(originalData, downloadedB) {
		t.Error("member B: downloaded data does not match uploaded data")
	}
	t.Log("member B download verified — data matches")

	// --- Blob should NOT be auto-deleted (group mode) ---
	// Member A downloads the same blob — should still exist.
	downloadPathA := filepath.Join(dir, "download_a.enc")
	mime2, size2, err := nodeA.MediaDownload(blobID, downloadPathA)
	if err != nil {
		t.Fatalf("MediaDownload (member A, second download): %v — blob was auto-deleted but shouldn't be in group mode", err)
	}
	t.Logf("member A download: mime=%s size=%d", mime2, size2)

	downloadedA, err := os.ReadFile(downloadPathA)
	if err != nil {
		t.Fatalf("ReadFile A: %v", err)
	}
	if !bytes.Equal(originalData, downloadedA) {
		t.Error("member A: downloaded data does not match uploaded data")
	}
	t.Log("group blob persisted after first download — no auto-delete confirmed")

	// --- Outsider C should be rejected ---
	downloadPathC := filepath.Join(dir, "download_c.enc")
	_, _, err = nodeC.MediaDownload(blobID, downloadPathC)
	if err == nil {
		t.Error("outsider download should have been rejected (not in allowedPeers)")
	} else {
		t.Logf("outsider correctly rejected: %v", err)
	}

	t.Log("group media upload/download verified successfully")
}

// TestRelayGroupMediaVoiceNote verifies that a small audio blob (simulating
// a voice note) round-trips correctly in group mode.
func TestRelayGroupMediaVoiceNote(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, peerIdA := startNode(t)
	nodeB, peerIdB := startNode(t)

	dir := t.TempDir()

	// Small audio-sized payload (8KB).
	audioData := make([]byte, 8192)
	if _, err := rand.Read(audioData); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	uploadPath := filepath.Join(dir, "voice.m4a")
	if err := os.WriteFile(uploadPath, audioData, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	blobID := "smoke-voice-blob"
	allowedPeers := []string{peerIdA, peerIdB}

	// Upload as audio/mp4
	if err := nodeA.MediaUpload(blobID, "group-voice-test", "audio/mp4", uploadPath, allowedPeers); err != nil {
		t.Fatalf("MediaUpload (voice): %v", err)
	}
	t.Log("voice note upload succeeded")

	// Download and verify
	downloadPath := filepath.Join(dir, "voice_download.m4a")
	mime, size, err := nodeB.MediaDownload(blobID, downloadPath)
	if err != nil {
		t.Fatalf("MediaDownload (voice): %v", err)
	}

	if mime != "audio/mp4" {
		t.Errorf("mime=%s, want audio/mp4", mime)
	}
	if size != int64(len(audioData)) {
		t.Errorf("size=%d, want %d", size, len(audioData))
	}

	downloaded, err := os.ReadFile(downloadPath)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if !bytes.Equal(audioData, downloaded) {
		t.Error("voice note data does not match")
	}

	t.Log("voice note round-trip verified successfully")
}
