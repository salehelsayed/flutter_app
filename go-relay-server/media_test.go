package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
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
	profile   *ProfileStore
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
	profile := NewProfileStore(filepath.Join(dataDir, "profiles"))

	server.SetStreamHandler(MediaProtocol, func(s network.Stream) {
		HandleMediaStream(s, media, profile)
	})

	t.Cleanup(func() {
		server.Close()
		sender.Close()
		recipient.Close()
		intruder.Close()
	})

	return &testEnv{server, sender, recipient, intruder, media, profile}
}

func withMediaLimits(t *testing.T, sizeLimit, peerByteCap int64, fn func()) {
	t.Helper()

	prevSizeLimit := maxMediaSize
	prevPeerByteCap := maxMediaBytesPerPeer
	maxMediaSize = sizeLimit
	maxMediaBytesPerPeer = peerByteCap
	t.Cleanup(func() {
		maxMediaSize = prevSizeLimit
		maxMediaBytesPerPeer = prevPeerByteCap
	})

	fn()
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

// uploadWithAllowedPeers opens a stream, uploads a blob with allowedPeers, and waits for OK.
func (env *testEnv) uploadWithAllowedPeers(t *testing.T, from host.Host, blobID, toStr, mime string, data []byte, allowedPeers []string) {
	t.Helper()

	s, err := from.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatalf("open upload stream: %v", err)
	}
	defer s.Close()

	sendMediaReq(t, s, mediaRequest{
		Action:       "upload",
		ID:           blobID,
		To:           toStr,
		Size:         int64(len(data)),
		Mime:         mime,
		AllowedPeers: allowedPeers,
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

// TestSizeLimitExceeded verifies uploads above the configured max are rejected
// at the protocol level (before any data transfer).
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

func TestUploadAtConfiguredMaxSize(t *testing.T) {
	withMediaLimits(t, 1024, 8*1024, func() {
		env := setupTestEnv(t)
		recipientStr := env.recipient.ID().String()

		data := make([]byte, int(maxMediaSize))
		rand.Read(data)

		env.upload(t, env.sender, "max-size", recipientStr, "video/mp4", data)

		meta := env.media.lookup("max-size")
		if meta == nil {
			t.Fatal("expected blob metadata to be stored")
		}
		if meta.Size != maxMediaSize {
			t.Fatalf("expected stored size %d, got %d", maxMediaSize, meta.Size)
		}
	})
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

func TestPeerByteCapPruning(t *testing.T) {
	withMediaLimits(t, 1024, 8, func() {
		env := setupTestEnv(t)
		recipientStr := env.recipient.ID().String()

		for i := 0; i < 3; i++ {
			data := []byte{byte(i), byte(i + 1), byte(i + 2)}
			env.upload(t, env.sender, fmt.Sprintf("bytes-%03d", i), recipientStr, "image/jpeg", data)
			time.Sleep(2 * time.Millisecond)
		}

		if meta := env.media.lookup("bytes-000"); meta != nil {
			t.Fatal("oldest blob should have been pruned to satisfy peer byte cap")
		}
		if meta := env.media.lookup("bytes-001"); meta == nil {
			t.Fatal("second blob should remain after byte-cap pruning")
		}
		if meta := env.media.lookup("bytes-002"); meta == nil {
			t.Fatal("newest blob should remain after byte-cap pruning")
		}

		env.media.mu.RLock()
		totalBytes := env.media.pendingBytesForPeerLocked(recipientStr)
		env.media.mu.RUnlock()
		if totalBytes > maxMediaBytesPerPeer {
			t.Fatalf("expected pending bytes <= %d, got %d", maxMediaBytesPerPeer, totalBytes)
		}
	})
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

// --- Group media tests (AllowedPeers) ---

// TestGroupMediaUploadDownload verifies that uploading with allowedPeers
// allows listed peers to download and rejects unlisted peers.
func TestGroupMediaUploadDownload(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()
	intruderStr := env.intruder.ID().String()

	// Upload with allowedPeers containing recipient and sender (but not intruder)
	data := make([]byte, 1024)
	rand.Read(data)

	allowedPeers := []string{recipientStr, env.sender.ID().String()}
	env.uploadWithAllowedPeers(t, env.sender, "group-blob-1", "group-id-1", "image/jpeg", data, allowedPeers)

	// Recipient can download
	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, s, mediaRequest{Action: "download", ID: "group-blob-1"})
	resp := recvMediaResp(t, s)
	if resp.Status != "OK" {
		t.Fatalf("recipient download: expected OK, got %s: %s", resp.Status, resp.Error)
	}
	downloaded := make([]byte, resp.Size)
	io.ReadFull(s, downloaded)
	s.Close()

	if !bytes.Equal(data, downloaded) {
		t.Fatal("downloaded data does not match uploaded data")
	}

	// Intruder cannot download
	s2, err := env.intruder.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, s2, mediaRequest{Action: "download", ID: "group-blob-1"})
	resp2 := recvMediaResp(t, s2)
	s2.Close()

	if resp2.Status != "ERROR" || resp2.Error != "not authorized" {
		t.Fatalf("intruder download: expected 'not authorized', got status=%s error=%s", resp2.Status, resp2.Error)
	}

	_ = intruderStr // suppress unused
}

// TestGroupMediaNoAutoDelete verifies that group blobs (with AllowedPeers)
// are NOT auto-deleted after the first download.
func TestGroupMediaNoAutoDelete(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()
	senderStr := env.sender.ID().String()

	data := make([]byte, 512)
	rand.Read(data)

	allowedPeers := []string{recipientStr, senderStr}
	env.uploadWithAllowedPeers(t, env.sender, "group-persist", "group-id-2", "audio/aac", data, allowedPeers)

	// First download by recipient
	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, s, mediaRequest{Action: "download", ID: "group-persist"})
	resp := recvMediaResp(t, s)
	if resp.Status != "OK" {
		t.Fatalf("first download: expected OK, got %s: %s", resp.Status, resp.Error)
	}
	buf := make([]byte, resp.Size)
	io.ReadFull(s, buf)
	s.Close()

	// Blob should still exist (no auto-delete for group)
	time.Sleep(200 * time.Millisecond)
	if meta := env.media.lookup("group-persist"); meta == nil {
		t.Fatal("group blob should NOT be auto-deleted after download")
	}

	// Second download by sender — should still succeed
	s2, err := env.sender.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, s2, mediaRequest{Action: "download", ID: "group-persist"})
	resp2 := recvMediaResp(t, s2)
	if resp2.Status != "OK" {
		t.Fatalf("second download: expected OK, got %s: %s", resp2.Status, resp2.Error)
	}
	buf2 := make([]byte, resp2.Size)
	io.ReadFull(s2, buf2)
	s2.Close()

	if !bytes.Equal(data, buf2) {
		t.Fatal("second download data does not match")
	}
}

// TestGroupMediaUnauthorizedPeer verifies that a peer NOT in allowedPeers
// cannot download a group blob.
func TestGroupMediaUnauthorizedPeer(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	data := make([]byte, 256)
	rand.Read(data)

	// Only recipient is allowed — intruder is NOT
	allowedPeers := []string{recipientStr}
	env.uploadWithAllowedPeers(t, env.sender, "group-secret", "group-id-3", "image/png", data, allowedPeers)

	// Intruder tries to download
	s, err := env.intruder.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, s, mediaRequest{Action: "download", ID: "group-secret"})
	resp := recvMediaResp(t, s)
	s.Close()

	if resp.Status != "ERROR" || resp.Error != "not authorized" {
		t.Fatalf("expected 'not authorized', got status=%s error=%s", resp.Status, resp.Error)
	}

	// Blob should still exist for authorized recipient
	if meta := env.media.lookup("group-secret"); meta == nil {
		t.Fatal("blob should still exist after unauthorized download attempt")
	}
}

// TestPL006RemovedPeerCannotDownloadPostRemovalGroupMedia proves that a peer
// removed before a group media upload cannot directly download the new blob.
func TestPL006RemovedPeerCannotDownloadPostRemovalGroupMedia(t *testing.T) {
	env := setupTestEnv(t)
	senderStr := env.sender.ID().String()
	recipientStr := env.recipient.ID().String()

	data := make([]byte, 512)
	rand.Read(data)

	// Alice uploads after Charlie removal, so only active Alice and Bob remain
	// in the relay ACL. The intruder peer represents removed Charlie.
	allowedPeers := []string{senderStr, recipientStr}
	env.uploadWithAllowedPeers(t, env.sender, "pl006-post-removal", "group-pl006", "image/png", data, allowedPeers)

	removed, err := env.intruder.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, removed, mediaRequest{Action: "download", ID: "pl006-post-removal"})
	removedResp := recvMediaResp(t, removed)
	removed.Close()

	if removedResp.Status != "ERROR" || removedResp.Error != "not authorized" {
		t.Fatalf("removed peer download: expected not authorized, got status=%s error=%s", removedResp.Status, removedResp.Error)
	}
	if meta := env.media.lookup("pl006-post-removal"); meta == nil {
		t.Fatal("blob should remain available to active peers after removed peer denial")
	}

	active, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, active, mediaRequest{Action: "download", ID: "pl006-post-removal"})
	activeResp := recvMediaResp(t, active)
	if activeResp.Status != "OK" {
		t.Fatalf("active peer download: expected OK, got %s: %s", activeResp.Status, activeResp.Error)
	}
	downloaded := make([]byte, activeResp.Size)
	io.ReadFull(active, downloaded)
	active.Close()

	if !bytes.Equal(data, downloaded) {
		t.Fatal("active peer downloaded data does not match uploaded data")
	}
}

// TestBackwardCompat verifies that uploads WITHOUT allowedPeers still
// behave the same (1:1 mode with auto-delete).
func TestBackwardCompat(t *testing.T) {
	env := setupTestEnv(t)
	recipientStr := env.recipient.ID().String()

	data := make([]byte, 256)
	rand.Read(data)

	// Upload without allowedPeers (1:1 mode)
	env.upload(t, env.sender, "compat-blob", recipientStr, "image/jpeg", data)

	// Download — should succeed
	s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, s, mediaRequest{Action: "download", ID: "compat-blob"})
	resp := recvMediaResp(t, s)
	if resp.Status != "OK" {
		t.Fatalf("download: expected OK, got %s: %s", resp.Status, resp.Error)
	}
	buf := make([]byte, resp.Size)
	io.ReadFull(s, buf)
	s.Close()

	// Should auto-delete (1:1 mode)
	waitFor(t, 2*time.Second, func() bool {
		return env.media.lookup("compat-blob") == nil
	}, "blob should be auto-deleted after 1:1 download")

	// Second download should fail
	s2, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
	if err != nil {
		t.Fatal(err)
	}
	sendMediaReq(t, s2, mediaRequest{Action: "download", ID: "compat-blob"})
	resp2 := recvMediaResp(t, s2)
	s2.Close()

	if resp2.Status != "ERROR" || resp2.Error != "not found" {
		t.Fatalf("expected 'not found' after auto-delete, got status=%s error=%s", resp2.Status, resp2.Error)
	}
}
