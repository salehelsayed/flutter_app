package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"io"
	"os"
	"testing"

	"github.com/libp2p/go-libp2p/core/host"
)

// --- Profile test helpers ---

// profileUpload opens a stream, uploads a profile blob for the caller, and waits for OK.
func (env *testEnv) profileUpload(t *testing.T, from host.Host, mime string, data []byte) {
	t.Helper()

	s, err := from.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatalf("open profile upload stream: %v", err)
	}
	defer s.Close()

	sendMediaReq(t, s, mediaRequest{
		Action: "profile_upload",
		Size:   int64(len(data)),
		Mime:   mime,
	})

	resp := recvMediaResp(t, s)
	if resp.Status != "READY" {
		t.Fatalf("profile upload: expected READY, got %s: %s", resp.Status, resp.Error)
	}

	if _, err := s.Write(data); err != nil {
		t.Fatalf("write profile data: %v", err)
	}

	resp = recvMediaResp(t, s)
	if resp.Status != "OK" {
		t.Fatalf("profile upload: expected OK, got %s: %s", resp.Status, resp.Error)
	}
}

// profileDownload opens a stream, downloads a profile blob by owner, and returns the bytes.
func (env *testEnv) profileDownload(t *testing.T, from host.Host, ownerPeerId string) ([]byte, mediaResponse) {
	t.Helper()

	s, err := from.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatalf("open profile download stream: %v", err)
	}
	defer s.Close()

	sendMediaReq(t, s, mediaRequest{
		Action: "profile_download",
		Owner:  ownerPeerId,
	})

	resp := recvMediaResp(t, s)
	if resp.Status != "OK" {
		return nil, resp
	}

	downloaded := make([]byte, resp.Size)
	if _, err := io.ReadFull(s, downloaded); err != nil {
		t.Fatalf("read profile data: %v", err)
	}

	return downloaded, resp
}

// --- Profile tests ---

// TestProfileUploadDownload verifies the happy path:
// sender uploads own profile → recipient downloads → bytes match.
func TestProfileUploadDownload(t *testing.T) {
	env := setupTestEnv(t)

	profileData := make([]byte, 4096)
	rand.Read(profileData)
	senderStr := env.sender.ID().String()

	// Upload
	env.profileUpload(t, env.sender, "image/jpeg", profileData)

	// Verify blob exists on disk
	blobPath := env.profile.blobPath(senderStr)
	if _, err := os.Stat(blobPath); os.IsNotExist(err) {
		t.Fatal("profile file should exist on disk after upload")
	}

	// Download from a different peer
	downloaded, resp := env.profileDownload(t, env.recipient, senderStr)

	if resp.Mime != "image/jpeg" {
		t.Fatalf("mime mismatch: want image/jpeg, got %s", resp.Mime)
	}
	if resp.Size != int64(len(profileData)) {
		t.Fatalf("size mismatch: want %d, got %d", len(profileData), resp.Size)
	}
	if !bytes.Equal(profileData, downloaded) {
		t.Fatal("downloaded profile data does not match uploaded data")
	}

	// Verify blob still exists (no auto-delete)
	if meta := env.profile.lookup(senderStr); meta == nil {
		t.Fatal("profile should still exist after download (no auto-delete)")
	}
}

// TestProfileReplace verifies that uploading a second time replaces the first blob.
func TestProfileReplace(t *testing.T) {
	env := setupTestEnv(t)
	senderStr := env.sender.ID().String()

	// Upload first version
	v1 := make([]byte, 1024)
	rand.Read(v1)
	env.profileUpload(t, env.sender, "image/png", v1)

	// Upload second version
	v2 := make([]byte, 2048)
	rand.Read(v2)
	env.profileUpload(t, env.sender, "image/jpeg", v2)

	// Download should return v2
	downloaded, resp := env.profileDownload(t, env.recipient, senderStr)

	if resp.Mime != "image/jpeg" {
		t.Fatalf("mime should be updated: want image/jpeg, got %s", resp.Mime)
	}
	if resp.Size != int64(len(v2)) {
		t.Fatalf("size should be updated: want %d, got %d", len(v2), resp.Size)
	}
	if !bytes.Equal(v2, downloaded) {
		t.Fatal("downloaded data should match second upload")
	}

	// Only one file on disk
	blobPath := env.profile.blobPath(senderStr)
	info, err := os.Stat(blobPath)
	if err != nil {
		t.Fatalf("profile file should exist: %v", err)
	}
	if info.Size() != int64(len(v2)) {
		t.Fatalf("disk file size should match v2: want %d, got %d", len(v2), info.Size())
	}
}

// TestProfileDownloadNotFound verifies that downloading a non-existent profile
// returns a "not found" error.
func TestProfileDownloadNotFound(t *testing.T) {
	env := setupTestEnv(t)

	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{
		Action: "profile_download",
		Owner:  "12D3KooWNonExistentPeer",
	})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "ERROR" || resp.Error != "not found" {
		t.Fatalf("expected 'not found', got status=%s error=%s", resp.Status, resp.Error)
	}
}

// TestProfileDelete verifies that the owner can delete their profile and
// subsequent downloads return "not found".
func TestProfileDelete(t *testing.T) {
	env := setupTestEnv(t)
	senderStr := env.sender.ID().String()

	// Upload
	data := make([]byte, 512)
	rand.Read(data)
	env.profileUpload(t, env.sender, "image/png", data)

	blobPath := env.profile.blobPath(senderStr)
	if _, err := os.Stat(blobPath); os.IsNotExist(err) {
		t.Fatal("profile should exist before delete")
	}

	// Delete
	s, err := env.sender.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "profile_delete"})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "OK" {
		t.Fatalf("delete: expected OK, got %s: %s", resp.Status, resp.Error)
	}

	// Verify gone from disk
	if _, err := os.Stat(blobPath); !os.IsNotExist(err) {
		t.Fatal("profile file should be removed from disk after delete")
	}

	// Verify gone from index
	if meta := env.profile.lookup(senderStr); meta != nil {
		t.Fatal("profile should be removed from index after delete")
	}

	// Download should fail
	s2, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s2, mediaRequest{
		Action: "profile_download",
		Owner:  senderStr,
	})
	resp2 := recvMediaResp(t, s2)
	s2.Close()

	if resp2.Status != "ERROR" || resp2.Error != "not found" {
		t.Fatalf("download after delete: expected 'not found', got status=%s error=%s", resp2.Status, resp2.Error)
	}
}

// TestProfileDeleteIdempotent verifies that deleting a non-existent profile
// returns OK (idempotent).
func TestProfileDeleteIdempotent(t *testing.T) {
	env := setupTestEnv(t)

	s, err := env.sender.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "profile_delete"})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "OK" {
		t.Fatalf("idempotent delete: expected OK, got %s: %s", resp.Status, resp.Error)
	}
}

// TestProfileSizeLimit verifies that uploads exceeding maxProfileSize (512 KB)
// are rejected before any data transfer.
func TestProfileSizeLimit(t *testing.T) {
	env := setupTestEnv(t)

	s, err := env.sender.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{
		Action: "profile_upload",
		Size:   maxProfileSize + 1,
		Mime:   "image/jpeg",
	})

	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "ERROR" {
		t.Fatalf("expected ERROR for oversized profile upload, got %s", resp.Status)
	}
}

// TestProfileAnyPeerCanDownload verifies that any peer (sender, recipient,
// intruder) can download a profile — no authorization on downloads.
func TestProfileAnyPeerCanDownload(t *testing.T) {
	env := setupTestEnv(t)
	senderStr := env.sender.ID().String()

	data := make([]byte, 1024)
	rand.Read(data)
	env.profileUpload(t, env.sender, "image/jpeg", data)

	// All three peers should be able to download
	peers := []struct {
		name string
		host host.Host
	}{
		{"sender (self)", env.sender},
		{"recipient", env.recipient},
		{"intruder", env.intruder},
	}

	for _, p := range peers {
		downloaded, resp := env.profileDownload(t, p.host, senderStr)
		if resp.Status != "OK" {
			t.Fatalf("%s: download failed: %s: %s", p.name, resp.Status, resp.Error)
		}
		if !bytes.Equal(data, downloaded) {
			t.Fatalf("%s: downloaded data does not match", p.name)
		}
	}
}
