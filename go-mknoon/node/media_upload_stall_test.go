package node

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
)

// Exercise the actual upload over local libp2p streams: a local file remains
// readable while the relay stops consuming bytes or answering. The native
// transfer must settle before the much longer Dart watchdog and permit retry.
func TestMediaUploadStallReleasesStreamForRetry(t *testing.T) {
	for _, phase := range []string{"ready", "body", "confirmation"} {
		t.Run(phase, func(t *testing.T) {
			t.Parallel()
			payload := bytes.Repeat([]byte{0x71}, 670610)
			if phase == "body" {
				// Exceed the stream receive window so Write itself blocks.
				payload = bytes.Repeat([]byte{0x71}, 8*1024*1024)
			}
			path := filepath.Join(t.TempDir(), "voice.enc")
			if err := os.WriteFile(path, payload, 0o600); err != nil {
				t.Fatal(err)
			}
			var attempts atomic.Int32
			release := make(chan struct{})
			received := make(chan []byte, 1)
			relay := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
				first := attempts.Add(1) == 1
				if first && phase == "ready" {
					<-release
					return
				}
				writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
				if first && phase == "body" {
					<-release
					return
				}
				body := make([]byte, request.Size)
				if _, err := io.ReadFull(stream, body); err != nil {
					t.Errorf("read body: %v", err)
					return
				}
				if first && phase == "confirmation" {
					<-release
					return
				}
				if request.ID != "stalled-voice" {
					t.Errorf("retry changed blob identity: %s", request.ID)
				}
				received <- body
				writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "OK"})
			})
			n := startLocalNodeForMultiRelayTest(t)
			configureMediaCustodyTestRelays(t, n, relay.addr(t))
			t.Cleanup(func() {
				close(release)
				_ = n.Host().Network().ClosePeer(relay.host.ID())
			})
			done := make(chan error, 1)
			go func() {
				done <- n.MediaUpload("stalled-voice", "recipient", "audio/mp4", path, nil)
			}()
			select {
			case err := <-done:
				if !errors.Is(err, ErrStallTimeout) {
					t.Fatalf("stalled %s returned %v, want ErrStallTimeout", phase, err)
				}
			case <-time.After(MediaIdleTimeout + 3*time.Second):
				t.Fatalf("stalled %s still owns the upload after the native idle budget", phase)
			}
			if err := n.MediaUpload("stalled-voice", "recipient", "audio/mp4", path, nil); err != nil {
				t.Fatalf("retry: %v", err)
			}
			if got := <-received; !bytes.Equal(got, payload) {
				t.Fatal("retry did not deliver the original complete ciphertext")
			}
			if attempts.Load() != 2 {
				t.Fatalf("requests=%d, want one failed attempt and one retry", attempts.Load())
			}
		})
	}
}

func TestMediaCustodyUploadStalledConfirmationProbesSameRelay(t *testing.T) {
	t.Parallel()
	payload := []byte("voice ciphertext whose commit reply never arrives")
	path := filepath.Join(t.TempDir(), "voice.enc")
	if err := os.WriteFile(path, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	var attempts atomic.Int32
	release := make(chan struct{})
	selected := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
		if attempts.Add(1) == 1 {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
			if _, err := io.CopyN(io.Discard, stream, request.Size); err != nil {
				t.Errorf("read body: %v", err)
				return
			}
			<-release // Commit succeeded, but the final reply stalls.
			return
		}
		writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "duplicate", "", 222222))
	})
	sibling := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
		t.Error("ambiguous commit advanced to a different relay")
	})
	n := startLocalNodeForMultiRelayTest(t)
	configureMediaCustodyTestRelays(t, n, selected.addr(t), sibling.addr(t))
	t.Cleanup(func() {
		close(release)
		_ = n.Host().Network().ClosePeer(selected.host.ID())
	})
	type outcome struct {
		result MediaCustodyResult
		err    error
	}
	done := make(chan outcome, 1)
	go func() {
		result, err := n.MediaUploadCustody("stalled-strict-voice", "recipient", "audio/mp4", path,
			CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract, mediaCustodyTestHash(payload))
		done <- outcome{result, err}
	}()
	select {
	case got := <-done:
		if got.err != nil || got.result.StoreStatus != "duplicate" ||
			got.result.CustodyRelayPeerId != selected.host.ID().String() {
			t.Fatalf("recovery=%#v, error=%v", got.result, got.err)
		}
	case <-time.After(MediaIdleTimeout + 3*time.Second):
		t.Fatal("stalled final proof did not reach same-relay recovery within the native idle budget")
	}
	if selected.requestCount() != 2 || sibling.requestCount() != 0 {
		t.Fatalf("selected requests=%d sibling requests=%d", selected.requestCount(), sibling.requestCount())
	}
}
