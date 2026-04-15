package node

import (
	"os"
	"path/filepath"
	"testing"
)

func TestBenchmark_MediaUpload_RequiresConnection(t *testing.T) {
	hexKey := generateTestKey(t)

	collector := &testEventCollector{}
	n := New(collector)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Create a small test file
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test_media.bin")
	if err := os.WriteFile(testFile, make([]byte, 1024), 0644); err != nil {
		t.Fatalf("create test file: %v", err)
	}

	// MediaUpload to unreachable peer should fail
	err = n.MediaUpload("test-id-1", "12D3KooWUnreachablePeer", "application/octet-stream", testFile, nil)
	if err != nil {
		t.Logf("MediaUpload to unreachable peer returned error (expected): %v", err)
	}

	// Check for media events
	streamEvents := collector.collectEvents("media:stream_open_timing")
	t.Logf("BENCHMARK: %d media:stream_open_timing events", len(streamEvents))

	uploadEvents := collector.collectEvents("media:upload_complete")
	t.Logf("BENCHMARK: %d media:upload_complete events", len(uploadEvents))
}

func TestBenchmark_MediaUpload_ProgressEvents(t *testing.T) {
	hexKey := generateTestKey(t)

	collector := &testEventCollector{}
	n := New(collector)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Check that media:upload_progress event type is recognized
	// (actual upload requires two connected peers)
	progressEvents := collector.collectEvents("media:upload_progress")
	t.Logf("BENCHMARK: %d media:upload_progress events (0 expected without transfer)", len(progressEvents))
}
