package node

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

// --- Types (mirror relay server) ---

type mediaRequest struct {
	Action       string   `json:"action"`
	ID           string   `json:"id,omitempty"`
	To           string   `json:"to,omitempty"`
	Owner        string   `json:"owner,omitempty"` // for profile_download
	Size         int64    `json:"size,omitempty"`
	Mime         string   `json:"mime,omitempty"`
	AllowedPeers []string `json:"allowedPeers,omitempty"`
}

type mediaResponse struct {
	Status string      `json:"status"`
	Error  string      `json:"error,omitempty"`
	ID     string      `json:"id,omitempty"`
	Mime   string      `json:"mime,omitempty"`
	Size   int64       `json:"size,omitempty"`
	Blobs  []MediaMeta `json:"blobs,omitempty"`
}

// MediaMeta is the metadata for a media blob.
type MediaMeta struct {
	ID        string `json:"id"`
	From      string `json:"from"`
	To        string `json:"to"`
	Mime      string `json:"mime"`
	Size      int64  `json:"size"`
	CreatedAt int64  `json:"created_at"`
}

// --- Helper ---

// ErrStallTimeout is returned when a media transfer stalls (no bytes for MediaIdleTimeout).
var ErrStallTimeout = fmt.Errorf("media transfer stalled: no bytes for %v", MediaIdleTimeout)

// idleTimeoutReader wraps an io.Reader and fails if no bytes are read
// within the idle timeout period. The timer resets on every successful
// Read that returns n > 0.
type idleTimeoutReader struct {
	reader      io.Reader
	idleTimeout time.Duration
	timer       *time.Timer
}

func newIdleTimeoutReader(r io.Reader, timeout time.Duration) *idleTimeoutReader {
	return &idleTimeoutReader{
		reader:      r,
		idleTimeout: timeout,
		timer:       time.NewTimer(timeout),
	}
}

func (r *idleTimeoutReader) Read(p []byte) (int, error) {
	type readResult struct {
		n   int
		err error
	}
	ch := make(chan readResult, 1)
	go func() {
		n, err := r.reader.Read(p)
		ch <- readResult{n, err}
	}()

	select {
	case res := <-ch:
		if res.n > 0 {
			r.timer.Reset(r.idleTimeout)
		}
		return res.n, res.err
	case <-r.timer.C:
		return 0, ErrStallTimeout
	}
}

const mediaUploadProgressEmitChunkBytes int64 = 256 * 1024
const mediaUploadProgressEmitInterval = 250 * time.Millisecond

type mediaUploadProgressReader struct {
	reader         io.Reader
	totalBytes     int64
	sentBytes      int64
	lastEmitBytes  int64
	lastEmitAt     time.Time
	emitProgressFn func(sentBytes, totalBytes int64)
}

func (r *mediaUploadProgressReader) Read(p []byte) (int, error) {
	n, err := r.reader.Read(p)
	if n > 0 {
		r.sentBytes += int64(n)
		now := time.Now()
		shouldEmit := r.sentBytes == r.totalBytes ||
			r.sentBytes-r.lastEmitBytes >= mediaUploadProgressEmitChunkBytes ||
			now.Sub(r.lastEmitAt) >= mediaUploadProgressEmitInterval
		if shouldEmit && r.emitProgressFn != nil {
			r.lastEmitBytes = r.sentBytes
			r.lastEmitAt = now
			r.emitProgressFn(r.sentBytes, r.totalBytes)
		}
	}
	return n, err
}

// openMediaStream connects to the relay and opens a MediaProtocol stream.
// Tries each configured relay in order until one succeeds.
func (n *Node) openMediaStream() (network.Stream, context.CancelFunc, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, nil, fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	type streamResult struct {
		stream network.Stream
		cancel context.CancelFunc
	}

	result, err := ForEachWithResult(rs, func(relay RelayInfo) (*streamResult, error) {
		totalStart := time.Now()
		ctx, cancel := context.WithTimeout(n.ctx, MediaTimeout)

		connectStart := time.Now()
		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			cancel()
			n.emitEvent("media:stream_open_timing", map[string]interface{}{
				"connectMs": time.Since(connectStart).Milliseconds(),
				"totalMs":   time.Since(totalStart).Milliseconds(),
				"outcome":   "connect_failed",
			})
			return nil, fmt.Errorf("connect to relay: %w", err)
		}
		connectMs := time.Since(connectStart).Milliseconds()

		streamStart := time.Now()
		s, err := h.NewStream(ctx, relay.ID, MediaProtocol)
		if err != nil {
			cancel()
			n.emitEvent("media:stream_open_timing", map[string]interface{}{
				"connectMs":   connectMs,
				"newStreamMs": time.Since(streamStart).Milliseconds(),
				"totalMs":     time.Since(totalStart).Milliseconds(),
				"outcome":     "stream_failed",
			})
			return nil, fmt.Errorf("open media stream: %w", err)
		}
		n.emitEvent("media:stream_open_timing", map[string]interface{}{
			"connectMs":   connectMs,
			"newStreamMs": time.Since(streamStart).Milliseconds(),
			"totalMs":     time.Since(totalStart).Milliseconds(),
			"outcome":     "success",
		})
		setStreamDeadline(s, MediaTimeout)

		return &streamResult{stream: s, cancel: cancel}, nil
	})

	if err != nil {
		return nil, nil, err
	}

	return result.stream, result.cancel, nil
}

// sendMediaRequest sends a framed JSON request and reads the framed JSON response.
func sendMediaRequest(s network.Stream, req *mediaRequest) (*mediaResponse, error) {
	reqBytes, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	if err := writeFrame(s, reqBytes); err != nil {
		return nil, fmt.Errorf("write request: %w", err)
	}

	respBytes, err := readFrame(s)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	var resp mediaResponse
	if err := json.Unmarshal(respBytes, &resp); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}

	return &resp, nil
}

func copyMediaDownloadToFile(outputPath string, reader io.Reader, expectedSize int64, idleTimeout time.Duration) (int64, error) {
	f, err := os.Create(outputPath)
	if err != nil {
		return 0, fmt.Errorf("create output file: %w", err)
	}

	idleReader := newIdleTimeoutReader(reader, idleTimeout)
	written, copyErr := io.CopyN(f, idleReader, expectedSize)
	closeErr := f.Close()
	if copyErr == nil {
		copyErr = closeErr
	}

	if copyErr != nil || written != expectedSize {
		os.Remove(outputPath)
		return written, fmt.Errorf("download incomplete: wrote %d/%d, err=%v", written, expectedSize, copyErr)
	}

	return written, nil
}

// --- Public methods ---

// MediaUpload uploads a file to the relay's media store.
func (n *Node) MediaUpload(id, toPeerId, mime, filePath string, allowedPeers []string) error {
	s, cancel, err := n.openMediaStream()
	if err != nil {
		return err
	}
	defer cancel()
	streamOK := false
	defer finishStream(s, &streamOK)

	// Open and stat the local file
	f, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return fmt.Errorf("stat file: %w", err)
	}

	// Send upload request
	resp, err := sendMediaRequest(s, &mediaRequest{
		Action:       "upload",
		ID:           id,
		To:           toPeerId,
		Size:         fi.Size(),
		Mime:         mime,
		AllowedPeers: allowedPeers,
	})
	if err != nil {
		return fmt.Errorf("upload request: %w", err)
	}

	if resp.Status != "READY" {
		return fmt.Errorf("upload not ready: %s", resp.Error)
	}

	// Stream raw bytes
	progressReader := &mediaUploadProgressReader{
		reader:     f,
		totalBytes: fi.Size(),
		lastEmitAt: time.Now(),
		emitProgressFn: func(sentBytes, totalBytes int64) {
			n.emitEvent("media:upload_progress", map[string]interface{}{
				"id":         id,
				"sentBytes":  sentBytes,
				"totalBytes": totalBytes,
				"toPeerId":   toPeerId,
			})
		},
	}
	progressReader.emitProgressFn(0, fi.Size())
	transferStart := time.Now()
	idleReader := newIdleTimeoutReader(progressReader, MediaIdleTimeout)
	if _, err := io.Copy(s, idleReader); err != nil {
		return fmt.Errorf("stream file data: %w", err)
	}
	progressReader.emitProgressFn(fi.Size(), fi.Size())

	// Read final confirmation
	confirmBytes, err := readFrame(s)
	if err != nil {
		return fmt.Errorf("read upload confirmation: %w", err)
	}

	var confirm mediaResponse
	if err := json.Unmarshal(confirmBytes, &confirm); err != nil {
		return fmt.Errorf("unmarshal confirmation: %w", err)
	}

	if confirm.Status != "OK" {
		return fmt.Errorf("upload failed: %s", confirm.Error)
	}

	transferMs := time.Since(transferStart).Milliseconds()
	throughput := int64(0)
	if transferMs > 0 {
		throughput = (fi.Size() * 1000) / transferMs
	}
	n.emitEvent("media:upload_complete", map[string]interface{}{
		"id":                    id,
		"totalBytes":            fi.Size(),
		"totalMs":               transferMs,
		"throughputBytesPerSec": throughput,
	})
	log.Printf("[MEDIA] Uploaded blob %s (%d bytes) to %s", id, fi.Size(), toPeerId[:min(20, len(toPeerId))])
	streamOK = true
	return nil
}

// MediaDownload downloads a blob from the relay's media store.
func (n *Node) MediaDownload(id, outputPath string) (mime string, size int64, err error) {
	s, cancel, sErr := n.openMediaStream()
	if sErr != nil {
		return "", 0, sErr
	}
	defer cancel()
	streamOK := false
	defer finishStream(s, &streamOK)

	// Send download request
	resp, sErr := sendMediaRequest(s, &mediaRequest{
		Action: "download",
		ID:     id,
	})
	if sErr != nil {
		return "", 0, fmt.Errorf("download request: %w", sErr)
	}

	if resp.Status != "OK" {
		return "", 0, fmt.Errorf("download failed: %s", resp.Error)
	}

	// Read exactly resp.Size bytes
	downloadStart := time.Now()
	if _, sErr := copyMediaDownloadToFile(outputPath, s, resp.Size, MediaIdleTimeout); sErr != nil {
		return "", 0, sErr
	}

	downloadMs := time.Since(downloadStart).Milliseconds()
	dlThroughput := int64(0)
	if downloadMs > 0 {
		dlThroughput = (resp.Size * 1000) / downloadMs
	}
	n.emitEvent("media:download_complete", map[string]interface{}{
		"id":                    id,
		"totalBytes":            resp.Size,
		"totalMs":               downloadMs,
		"throughputBytesPerSec": dlThroughput,
	})
	log.Printf("[MEDIA] Downloaded blob %s (%d bytes, %s)", id, resp.Size, resp.Mime)
	streamOK = true
	return resp.Mime, resp.Size, nil
}

// MediaDelete deletes a blob from the relay's media store.
func (n *Node) MediaDelete(id string) error {
	s, cancel, err := n.openMediaStream()
	if err != nil {
		return err
	}
	defer cancel()
	streamOK := false
	defer finishStream(s, &streamOK)

	resp, err := sendMediaRequest(s, &mediaRequest{
		Action: "delete",
		ID:     id,
	})
	if err != nil {
		return fmt.Errorf("delete request: %w", err)
	}

	if resp.Status != "OK" {
		return fmt.Errorf("delete failed: %s", resp.Error)
	}

	log.Printf("[MEDIA] Deleted blob %s", id)
	streamOK = true
	return nil
}

// MediaList lists blobs available for this peer on the relay.
func (n *Node) MediaList() ([]MediaMeta, error) {
	s, cancel, err := n.openMediaStream()
	if err != nil {
		return nil, err
	}
	defer cancel()
	streamOK := false
	defer finishStream(s, &streamOK)

	resp, err := sendMediaRequest(s, &mediaRequest{
		Action: "list",
	})
	if err != nil {
		return nil, fmt.Errorf("list request: %w", err)
	}

	if resp.Status != "OK" {
		return nil, fmt.Errorf("list failed: %s", resp.Error)
	}

	log.Printf("[MEDIA] Listed %d blob(s)", len(resp.Blobs))
	streamOK = true
	return resp.Blobs, nil
}

// --- Profile methods ---

// ProfileUpload uploads the user's profile picture to the relay.
func (n *Node) ProfileUpload(mime, filePath string) error {
	s, cancel, err := n.openMediaStream()
	if err != nil {
		return err
	}
	defer cancel()
	streamOK := false
	defer finishStream(s, &streamOK)

	f, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return fmt.Errorf("stat file: %w", err)
	}

	resp, err := sendMediaRequest(s, &mediaRequest{
		Action: "profile_upload",
		Size:   fi.Size(),
		Mime:   mime,
	})
	if err != nil {
		return fmt.Errorf("profile upload request: %w", err)
	}

	if resp.Status != "READY" {
		return fmt.Errorf("profile upload not ready: %s", resp.Error)
	}

	progressReader := &mediaUploadProgressReader{
		reader:     f,
		totalBytes: fi.Size(),
		lastEmitAt: time.Now(),
		emitProgressFn: func(sentBytes, totalBytes int64) {
			n.emitEvent("profile:upload_progress", map[string]interface{}{
				"sentBytes":  sentBytes,
				"totalBytes": totalBytes,
			})
		},
	}
	progressReader.emitProgressFn(0, fi.Size())
	idleReader := newIdleTimeoutReader(progressReader, MediaIdleTimeout)
	if _, err := io.Copy(s, idleReader); err != nil {
		return fmt.Errorf("stream profile data: %w", err)
	}
	progressReader.emitProgressFn(fi.Size(), fi.Size())

	confirmBytes, err := readFrame(s)
	if err != nil {
		return fmt.Errorf("read profile upload confirmation: %w", err)
	}

	var confirm mediaResponse
	if err := json.Unmarshal(confirmBytes, &confirm); err != nil {
		return fmt.Errorf("unmarshal confirmation: %w", err)
	}

	if confirm.Status != "OK" {
		return fmt.Errorf("profile upload failed: %s", confirm.Error)
	}

	log.Printf("[PROFILE] Uploaded profile (%d bytes, %s)", fi.Size(), mime)
	streamOK = true
	return nil
}

// ProfileDownload downloads a peer's profile picture from the relay.
func (n *Node) ProfileDownload(ownerPeerId, outputPath string) (mime string, size int64, err error) {
	s, cancel, sErr := n.openMediaStream()
	if sErr != nil {
		return "", 0, sErr
	}
	defer cancel()
	streamOK := false
	defer finishStream(s, &streamOK)

	resp, sErr := sendMediaRequest(s, &mediaRequest{
		Action: "profile_download",
		Owner:  ownerPeerId,
	})
	if sErr != nil {
		return "", 0, fmt.Errorf("profile download request: %w", sErr)
	}

	if resp.Status != "OK" {
		return "", 0, fmt.Errorf("profile download failed: %s", resp.Error)
	}

	f, sErr := os.Create(outputPath)
	if sErr != nil {
		return "", 0, fmt.Errorf("create output file: %w", sErr)
	}

	idleReader := newIdleTimeoutReader(s, MediaIdleTimeout)
	written, sErr := io.CopyN(f, idleReader, resp.Size)
	f.Close()

	if sErr != nil || written != resp.Size {
		os.Remove(outputPath)
		return "", 0, fmt.Errorf("profile download incomplete: wrote %d/%d, err=%v", written, resp.Size, sErr)
	}

	log.Printf("[PROFILE] Downloaded profile for %s (%d bytes, %s)", ownerPeerId[:min(20, len(ownerPeerId))], resp.Size, resp.Mime)
	streamOK = true
	return resp.Mime, resp.Size, nil
}
