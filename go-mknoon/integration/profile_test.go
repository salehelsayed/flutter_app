//go:build integration

package integration_test

import (
	"bytes"
	"crypto/rand"
	"os"
	"path/filepath"
	"testing"
)

// ---------- Profile integration tests ----------

func TestRelayProfileUploadDownload(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, peerIdA := startNode(t)
	nodeB, _ := startNode(t)

	t.Logf("NodeA=%s", peerIdA)

	// Create a temp file with random 1KB data.
	dir := t.TempDir()
	uploadPath := filepath.Join(dir, "profile_upload.jpg")
	originalData := make([]byte, 1024)
	if _, err := rand.Read(originalData); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	if err := os.WriteFile(uploadPath, originalData, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	// Node A uploads its profile.
	if err := nodeA.ProfileUpload("image/jpeg", uploadPath); err != nil {
		t.Fatalf("ProfileUpload: %v", err)
	}
	t.Log("Node A profile upload succeeded")

	// Node B downloads Node A's profile.
	downloadPath := filepath.Join(dir, "profile_download.jpg")
	mime, size, err := nodeB.ProfileDownload(peerIdA, downloadPath)
	if err != nil {
		t.Fatalf("ProfileDownload: %v", err)
	}
	t.Logf("downloaded profile: mime=%s size=%d", mime, size)

	if mime != "image/jpeg" {
		t.Errorf("mime=%s, want image/jpeg", mime)
	}
	if size != int64(len(originalData)) {
		t.Errorf("size=%d, want %d", size, len(originalData))
	}

	// Verify downloaded bytes match uploaded bytes.
	downloadedData, err := os.ReadFile(downloadPath)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if !bytes.Equal(originalData, downloadedData) {
		t.Error("downloaded data does not match uploaded data")
	}

	t.Log("profile upload/download verified successfully")
}

func TestRelayProfileReplace(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, peerIdA := startNode(t)
	nodeB, _ := startNode(t)

	t.Logf("NodeA=%s", peerIdA)

	dir := t.TempDir()

	// Create first profile with random data.
	data1 := make([]byte, 1024)
	if _, err := rand.Read(data1); err != nil {
		t.Fatalf("rand.Read data1: %v", err)
	}
	path1 := filepath.Join(dir, "profile1.jpg")
	if err := os.WriteFile(path1, data1, 0644); err != nil {
		t.Fatalf("WriteFile data1: %v", err)
	}

	// Upload first profile.
	if err := nodeA.ProfileUpload("image/jpeg", path1); err != nil {
		t.Fatalf("ProfileUpload (first): %v", err)
	}
	t.Log("first profile upload succeeded")

	// Create second profile with different random data.
	data2 := make([]byte, 1024)
	if _, err := rand.Read(data2); err != nil {
		t.Fatalf("rand.Read data2: %v", err)
	}
	path2 := filepath.Join(dir, "profile2.jpg")
	if err := os.WriteFile(path2, data2, 0644); err != nil {
		t.Fatalf("WriteFile data2: %v", err)
	}

	// Upload second profile (replaces first).
	if err := nodeA.ProfileUpload("image/jpeg", path2); err != nil {
		t.Fatalf("ProfileUpload (second): %v", err)
	}
	t.Log("second profile upload succeeded (replace)")

	// Node B downloads — should get data2.
	downloadPath := filepath.Join(dir, "profile_replaced.jpg")
	mime, size, err := nodeB.ProfileDownload(peerIdA, downloadPath)
	if err != nil {
		t.Fatalf("ProfileDownload: %v", err)
	}
	t.Logf("downloaded replaced profile: mime=%s size=%d", mime, size)

	downloadedData, err := os.ReadFile(downloadPath)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}

	if bytes.Equal(downloadedData, data1) {
		t.Error("downloaded data matches data1 (first upload) — replace did not work")
	}
	if !bytes.Equal(downloadedData, data2) {
		t.Error("downloaded data does not match data2 (second upload)")
	}

	t.Log("profile replace verified successfully")
}

func TestRelayProfileDownloadNotFound(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, _ := startNode(t)

	dir := t.TempDir()
	outputPath := filepath.Join(dir, "not_found.jpg")

	// Try to download profile for a non-existent peer.
	_, _, err := nodeA.ProfileDownload("12D3KooWNonExistentPeer", outputPath)
	if err == nil {
		t.Fatal("expected error when downloading profile for non-existent peer, got nil")
	}

	t.Logf("got expected error: %v", err)
}

func TestRelayProfileSizeLimit(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, _ := startNode(t)

	dir := t.TempDir()

	// Create a file larger than 512KB (the server limit).
	oversized := make([]byte, 513*1024)
	if _, err := rand.Read(oversized); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	oversizedPath := filepath.Join(dir, "oversized.jpg")
	if err := os.WriteFile(oversizedPath, oversized, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	// Upload should fail due to size limit.
	err := nodeA.ProfileUpload("image/jpeg", oversizedPath)
	if err == nil {
		t.Fatal("expected error when uploading oversized profile, got nil")
	}

	t.Logf("got expected error: %v", err)
}
