package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	mocknet "github.com/libp2p/go-libp2p/p2p/net/mock"
)

// --- Test helpers ---

func sendMediaReq(t *testing.T, s io.Writer, req mediaRequest) {
	t.Helper()
	data, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}
	if err := writeFrame(s, data); err != nil {
		t.Fatalf("write frame: %v", err)
	}
}

func recvMediaResp(t *testing.T, s io.Reader) mediaResponse {
	t.Helper()
	data, err := readFrame(s)
	if err != nil {
		t.Fatalf("read frame: %v", err)
	}
	var resp mediaResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	return resp
}

// waitFor polls a condition with timeout instead of a fixed sleep.
func waitFor(t *testing.T, timeout time.Duration, condition func() bool, msg string) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal(msg)
}

type testEnv struct {
	server    host.Host
	sender    host.Host
	recipient host.Host
	intruder  host.Host
	media     *MediaStore
}

func setupTestEnv(t *testing.T) *testEnv {
	t.Helper()

	mn := mocknet.New()
	server, err := mn.GenPeer()
	if err != nil {
		t.Fatal(err)
	}
	sender, err := mn.GenPeer()
	if err != nil {
		t.Fatal(err)
	}
	recipient, err := mn.GenPeer()
	if err != nil {
		t.Fatal(err)
	}
	intruder, err := mn.GenPeer()
	if err != nil {
		t.Fatal(err)
	}

	if err := mn.LinkAll(); err != nil {
		t.Fatal(err)
	}
	if err := mn.ConnectAllButSelf(); err != nil {
		t.Fatal(err)
	}

	dataDir := t.TempDir()
	media := NewMediaStore(dataDir)

	server.SetStreamHandler(MediaProtocol, func(s network.Stream) {
		HandleMediaStream(s, media)
	})

	t.Cleanup(func() {
		server.Close()
		sender.Close()
		recipient.Close()
		intruder.Close()
	})

	return &testEnv{server, sender, recipient, intruder, media}
}

// upload opens a stream, uploads a blob, and waits for OK.
func (env *testEnv) upload(t *testing.T, from host.Host, blobID, toStr, mime string, data []byte) {
	t.Helper()

	s, err := from.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatalf("open upload stream: %v", err)
	}
	defer s.Close()

	sendMediaReq(t, s, mediaRequest{
		Action: "upload",
		ID:     blobID,
		To:     toStr,
		Size:   int64(len(data)),
		Mime:   mime,
	})

	resp := recvMediaResp(t, s)
	if resp.Status != "READY" {
		t.Fatalf("upload %s: expected READY, got %s: %s", blobID, resp.Status, resp.Error)
	}

	if _, err := s.Write(data); err != nil {
		t.Fatalf("write blob data: %v", err)
	}

	resp = recvMediaResp(t, s)
	if resp.Status != "OK" {
		t.Fatalf("upload %s: expected OK, got %s: %s", blobID, resp.Status, resp.Error)
	}
}

// --- Smoke tests ---

// TestUploadDownloadAutoDelete verifies the core happy path:
// sender uploads → recipient downloads → data matches → blob auto-deleted from server.
func TestUploadDownloadAutoDelete(t *testing.T) {
	env := setupTestEnv(t)

	blobID := "blob-001"
	blobData := make([]byte, 4096)
	rand.Read(blobData)
	recipientStr := env.recipient.ID().String()

	// Upload
	env.upload(t, env.sender, blobID, recipientStr, "image/jpeg", blobData)

	// Verify blob exists on disk
	blobPath := env.media.blobPath(recipientStr, blobID)
	if _, err := os.Stat(blobPath); os.IsNotExist(err) {
		t.Fatal("blob file should exist on disk after upload")
	}

	// Download
	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "download", ID: blobID})
	resp := recvMediaResp(t, s)

	if resp.Status != "OK" {
		t.Fatalf("download: expected OK, got %s: %s", resp.Status, resp.Error)
	}
	if resp.Size != int64(len(blobData)) {
		t.Fatalf("size mismatch: want %d, got %d", len(blobData), resp.Size)
	}
	if resp.Mime != "image/jpeg" {
		t.Fatalf("mime mismatch: want image/jpeg, got %s", resp.Mime)
	}

	downloaded := make([]byte, resp.Size)
	if _, err := io.ReadFull(s, downloaded); err != nil {
		t.Fatalf("read blob data: %v", err)
	}
	s.Close()

	if !bytes.Equal(blobData, downloaded) {
		t.Fatal("downloaded data does not match uploaded data")
	}

	// Verify auto-deleted from disk + index
	waitFor(t, 2*time.Second, func() bool {
		_, err := os.Stat(blobPath)
		return os.IsNotExist(err)
	}, "blob should be auto-deleted from disk after download")

	waitFor(t, 2*time.Second, func() bool {
		return env.media.lookup(blobID) == nil
	}, "blob should be removed from index after download")
}

// TestMultipleMediaTypes verifies that different MIME types are stored and
// returned correctly via the list action.
func TestMultipleMediaTypes(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	types := []struct {
		id   string
		mime string
		size int
	}{
		{"img-001", "image/jpeg", 1024},
		{"vid-001", "video/mp4", 2048},
		{"aud-001", "audio/aac", 512},
		{"doc-001", "application/pdf", 768},
	}

	for _, mt := range types {
		data := make([]byte, mt.size)
		rand.Read(data)
		env.upload(t, env.sender, mt.id, recipientStr, mt.mime, data)
	}

	// List
	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "list"})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "OK" {
		t.Fatalf("list: expected OK, got %s: %s", resp.Status, resp.Error)
	}
	if len(resp.Blobs) != 4 {
		t.Fatalf("expected 4 blobs, got %d", len(resp.Blobs))
	}

	mimeSet := make(map[string]bool)
	for _, b := range resp.Blobs {
		mimeSet[b.Mime] = true
	}
	for _, mt := range types {
		if !mimeSet[mt.mime] {
			t.Errorf("missing mime type in list: %s", mt.mime)
		}
	}
}

// TestE2EBlobOpacity verifies the server stores opaque encrypted blobs
// without interpreting them — random bytes round-trip correctly.
func TestE2EBlobOpacity(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	// Simulate an encrypted payload (random bytes, not valid media)
	encrypted := make([]byte, 8192)
	rand.Read(encrypted)

	env.upload(t, env.sender, "encrypted-msg", recipientStr, "application/octet-stream", encrypted)

	// Download and verify bytes are identical
	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "download", ID: "encrypted-msg"})
	resp := recvMediaResp(t, s)
	if resp.Status != "OK" {
		t.Fatalf("download: %s: %s", resp.Status, resp.Error)
	}

	downloaded := make([]byte, resp.Size)
	io.ReadFull(s, downloaded)
	s.Close()

	if !bytes.Equal(encrypted, downloaded) {
		t.Fatal("encrypted blob was corrupted in transit — server must not modify data")
	}
}

// TestUnauthorizedDownload verifies that only the intended recipient can
// download a blob.
func TestUnauthorizedDownload(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	data := make([]byte, 256)
	rand.Read(data)
	env.upload(t, env.sender, "secret-blob", recipientStr, "image/png", data)

	// Intruder tries to download
	s, err := env.intruder.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "download", ID: "secret-blob"})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "ERROR" || resp.Error != "not authorized" {
		t.Fatalf("expected 'not authorized', got status=%s error=%s", resp.Status, resp.Error)
	}

	// Blob should still exist for the real recipient
	if meta := env.media.lookup("secret-blob"); meta == nil {
		t.Fatal("blob should still exist after unauthorized download attempt")
	}
}

// TestUnauthorizedDelete verifies that only the intended recipient can
// delete a blob.
func TestUnauthorizedDelete(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	data := make([]byte, 256)
	rand.Read(data)
	env.upload(t, env.sender, "keep-blob", recipientStr, "image/png", data)

	// Intruder tries to delete
	s, err := env.intruder.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "delete", ID: "keep-blob"})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "ERROR" || resp.Error != "not authorized" {
		t.Fatalf("expected 'not authorized', got status=%s error=%s", resp.Status, resp.Error)
	}

	if meta := env.media.lookup("keep-blob"); meta == nil {
		t.Fatal("blob should survive unauthorized delete attempt")
	}
}

// TestDownloadNotFound verifies the server returns a clear error for
// non-existent blob IDs.
func TestDownloadNotFound(t *testing.T) {
	env := setupTestEnv(t)

	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "download", ID: "does-not-exist"})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "ERROR" || resp.Error != "not found" {
		t.Fatalf("expected 'not found', got status=%s error=%s", resp.Status, resp.Error)
	}
}

// TestSizeLimitExceeded verifies uploads above 100 MB are rejected at
// the protocol level (before any data transfer).
func TestSizeLimitExceeded(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	s, err := env.sender.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{
		Action: "upload",
		ID:     "too-big",
		To:     recipientStr,
		Size:   maxMediaSize + 1,
		Mime:   "video/mp4",
	})

	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "ERROR" {
		t.Fatalf("expected ERROR for oversized upload, got %s", resp.Status)
	}
}

// TestPeerPruning verifies that when a recipient exceeds maxMediaPerPeer,
// the oldest blobs are automatically pruned.
func TestPeerPruning(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	// Upload maxMediaPerPeer + 1 blobs
	for i := 0; i <= maxMediaPerPeer; i++ {
		data := make([]byte, 64)
		rand.Read(data)
		env.upload(t, env.sender, fmt.Sprintf("prune-%03d", i), recipientStr, "image/jpeg", data)
	}

	// List should return exactly maxMediaPerPeer
	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "list"})
	resp := recvMediaResp(t, s)
	s.Close()

	if len(resp.Blobs) != maxMediaPerPeer {
		t.Fatalf("expected %d blobs after pruning, got %d", maxMediaPerPeer, len(resp.Blobs))
	}

	// The first blob (oldest) should have been pruned
	if meta := env.media.lookup("prune-000"); meta != nil {
		t.Fatal("oldest blob (prune-000) should have been pruned")
	}

	// The newest blob should still exist
	newest := fmt.Sprintf("prune-%03d", maxMediaPerPeer)
	if meta := env.media.lookup(newest); meta == nil {
		t.Fatalf("newest blob (%s) should still exist", newest)
	}
}

// TestListEmpty verifies list returns OK with zero blobs for a peer
// with no uploads.
func TestListEmpty(t *testing.T) {
	env := setupTestEnv(t)

	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "list"})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "OK" {
		t.Fatalf("expected OK, got %s: %s", resp.Status, resp.Error)
	}
	if len(resp.Blobs) != 0 {
		t.Fatalf("expected 0 blobs, got %d", len(resp.Blobs))
	}
}

// TestExplicitDelete verifies the delete action removes a blob from both
// disk and index when called by the authorized recipient.
func TestExplicitDelete(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	data := make([]byte, 512)
	rand.Read(data)
	env.upload(t, env.sender, "del-me", recipientStr, "audio/aac", data)

	blobPath := env.media.blobPath(recipientStr, "del-me")
	if _, err := os.Stat(blobPath); os.IsNotExist(err) {
		t.Fatal("blob should exist on disk before delete")
	}

	// Recipient deletes
	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}

	sendMediaReq(t, s, mediaRequest{Action: "delete", ID: "del-me"})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "OK" {
		t.Fatalf("delete: expected OK, got %s: %s", resp.Status, resp.Error)
	}

	// Verify gone from disk
	waitFor(t, 2*time.Second, func() bool {
		_, err := os.Stat(blobPath)
		return os.IsNotExist(err)
	}, "blob should be removed from disk after delete")

	// Verify gone from index
	if meta := env.media.lookup("del-me"); meta != nil {
		t.Fatal("blob should be removed from index after delete")
	}
}

// TestDownloadAfterAutoDeleteReturnsNotFound verifies that a second
// download attempt after auto-delete returns "not found".
func TestDownloadAfterAutoDeleteReturnsNotFound(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	data := make([]byte, 256)
	rand.Read(data)
	env.upload(t, env.sender, "once-only", recipientStr, "image/png", data)

	// First download — should succeed
	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, s, mediaRequest{Action: "download", ID: "once-only"})
	resp := recvMediaResp(t, s)
	if resp.Status != "OK" {
		t.Fatalf("first download: expected OK, got %s: %s", resp.Status, resp.Error)
	}
	buf := make([]byte, resp.Size)
	io.ReadFull(s, buf)
	s.Close()

	// Wait for auto-delete to complete
	waitFor(t, 2*time.Second, func() bool {
		return env.media.lookup("once-only") == nil
	}, "blob should be auto-deleted after first download")

	// Second download — should fail
	s2, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, s2, mediaRequest{Action: "download", ID: "once-only"})
	resp2 := recvMediaResp(t, s2)
	s2.Close()

	if resp2.Status != "ERROR" || resp2.Error != "not found" {
		t.Fatalf("second download: expected 'not found', got status=%s error=%s", resp2.Status, resp2.Error)
	}
}
