package node

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"strings"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

// --- Types (mirror relay server) ---

type mediaRequest struct {
	Action          string   `json:"action"`
	ID              string   `json:"id,omitempty"`
	To              string   `json:"to,omitempty"`
	Owner           string   `json:"owner,omitempty"` // for profile_download
	Size            int64    `json:"size,omitempty"`
	Mime            string   `json:"mime,omitempty"`
	AllowedPeers    []string `json:"allowedPeers,omitempty"`
	CustodyKind     string   `json:"custodyKind,omitempty"`
	CustodyContract string   `json:"custodyContract,omitempty"`
	ContentHash     string   `json:"contentHash,omitempty"`
	ExpiresAtMs     int64    `json:"expiresAtMs,omitempty"`
}

type mediaResponse struct {
	Status          string      `json:"status"`
	Error           string      `json:"error,omitempty"`
	ErrorCode       string      `json:"errorCode,omitempty"`
	StoreStatus     string      `json:"storeStatus,omitempty"`
	AckStatus       string      `json:"ackStatus,omitempty"`
	ID              string      `json:"id,omitempty"`
	Mime            string      `json:"mime,omitempty"`
	Size            int64       `json:"size,omitempty"`
	CustodyKind     string      `json:"custodyKind,omitempty"`
	CustodyContract string      `json:"custodyContract,omitempty"`
	ContentHash     string      `json:"contentHash,omitempty"`
	ExpiresAtMs     int64       `json:"expiresAtMs,omitempty"`
	Blobs           []MediaMeta `json:"blobs,omitempty"`
}

const (
	// CustodyKindDirectMediaBlobV1 is the protected encrypted-byte media lane.
	CustodyKindDirectMediaBlobV1 = "direct_media_blob_v1"
	// CustodyKindGroupMediaBlobV1 reuses the same strict relay action/backend
	// while remaining an exact, non-interchangeable custody identity.
	CustodyKindGroupMediaBlobV1 = "group_media_blob_v1"

	mediaUploadCustodyAction = "upload_custody_v1"
	mediaAckCustodyAction    = "ack_custody_v1"

	MediaCustodyAdmissionDisabledCode   = "MEDIA_CUSTODY_ADMISSION_DISABLED"
	MediaCustodyFullCode                = "MEDIA_CUSTODY_FULL"
	MediaCustodyUnsupportedCode         = "MEDIA_CUSTODY_UNSUPPORTED"
	MediaCustodyIdentityConflictCode    = "MEDIA_CUSTODY_IDENTITY_CONFLICT"
	MediaCustodyIneligibleCode          = "MEDIA_CUSTODY_INELIGIBLE"
	MediaCustodyNotAuthorizedCode       = "MEDIA_CUSTODY_NOT_AUTHORIZED"
	MediaCustodyHashMismatchCode        = "MEDIA_CUSTODY_HASH_MISMATCH"
	MediaCustodyAlreadyAckedCode        = "MEDIA_CUSTODY_ALREADY_ACKED"
	MediaCustodyCleanupPendingCode      = "MEDIA_CUSTODY_CLEANUP_PENDING"
	MediaCustodyStorageErrorCode        = "MEDIA_CUSTODY_STORAGE_ERROR"
	MediaCustodyNotFoundCode            = "MEDIA_CUSTODY_NOT_FOUND"
	MediaCustodyCommitIndeterminateCode = "MEDIA_CUSTODY_COMMIT_INDETERMINATE"
)

var (
	ErrMediaCustodyAdmissionDisabled   = errors.New("media custody admission disabled")
	ErrMediaCustodyFull                = errors.New("media custody full")
	ErrMediaCustodyUnsupported         = errors.New("media custody unsupported")
	ErrMediaCustodyIdentityConflict    = errors.New("media custody identity conflict")
	ErrMediaCustodyIneligible          = errors.New("media custody ineligible")
	ErrMediaCustodyNotAuthorized       = errors.New("media custody not authorized")
	ErrMediaCustodyHashMismatch        = errors.New("media custody hash mismatch")
	ErrMediaCustodyAlreadyAcked        = errors.New("media custody already acked")
	ErrMediaCustodyCleanupPending      = errors.New("media custody cleanup pending")
	ErrMediaCustodyStorage             = errors.New("media custody storage error")
	ErrMediaCustodyNotFound            = errors.New("media custody not found")
	ErrMediaCustodyCommitIndeterminate = errors.New("media custody commit indeterminate")
)

// MediaCustodyResult is the exact receipt returned by a strict upload or ACK.
// CustodyRelayPeerId is derived from the authenticated stream target and is
// never accepted from the relay response payload.
type MediaCustodyResult struct {
	ID                 string
	CustodyKind        string
	CustodyContract    string
	ContentHash        string
	Size               int64
	Mime               string
	ExpiresAtMs        int64
	StoreStatus        string
	AckStatus          string
	ErrorCode          string
	ErrorMessage       string
	CustodyRelayPeerId string
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
const mediaSourceRoleRelayMediaStore = "relay_media_store"

type mediaStream struct {
	stream          network.Stream
	cancel          context.CancelFunc
	operation       string
	sourcePeerId    string
	streamTransport string
}

// MediaDownloadResult includes the downloaded blob metadata plus the concrete
// source telemetry needed to distinguish relay-store fetches from peer-phone
// fetches in Flutter logs.
type MediaDownloadResult struct {
	Mime                string
	Size                int64
	SourceRole          string
	SourcePeerId        string
	SourcePeerShort     string
	StreamTransport     string
	ServedByPhone       bool
	RoutedViaRelayStore bool
	CustodyKind         string
	CustodyContract     string
	ContentHash         string
	ExpiresAtMs         int64
	CustodyRelayPeerId  string
	ErrorCode           string
	ErrorMessage        string
}

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

func relayMediaTelemetryFields(operation, sourcePeerId, streamTransport string) map[string]interface{} {
	if streamTransport == "" {
		streamTransport = "unknown"
	}
	return map[string]interface{}{
		"operation":           operation,
		"sourceRole":          mediaSourceRoleRelayMediaStore,
		"sourcePeerId":        sourcePeerId,
		"sourcePeerShort":     shortPeerID(sourcePeerId),
		"streamTransport":     streamTransport,
		"servedByPhone":       false,
		"routedViaRelayStore": true,
	}
}

func (s *mediaStream) telemetryFields() map[string]interface{} {
	if s == nil {
		return map[string]interface{}{
			"operation":           "unknown",
			"sourceRole":          "unknown",
			"sourcePeerId":        "",
			"sourcePeerShort":     "",
			"streamTransport":     "unknown",
			"servedByPhone":       false,
			"routedViaRelayStore": false,
		}
	}
	return relayMediaTelemetryFields(s.operation, s.sourcePeerId, s.streamTransport)
}

func mediaEventDetails(s *mediaStream, details map[string]interface{}) map[string]interface{} {
	merged := s.telemetryFields()
	for key, value := range details {
		merged[key] = value
	}
	return merged
}

func mediaDownloadResultFromStream(s *mediaStream, mime string, size int64) MediaDownloadResult {
	fields := s.telemetryFields()
	return MediaDownloadResult{
		Mime:                mime,
		Size:                size,
		SourceRole:          fields["sourceRole"].(string),
		SourcePeerId:        fields["sourcePeerId"].(string),
		SourcePeerShort:     fields["sourcePeerShort"].(string),
		StreamTransport:     fields["streamTransport"].(string),
		ServedByPhone:       fields["servedByPhone"].(bool),
		RoutedViaRelayStore: fields["routedViaRelayStore"].(bool),
	}
}

func (n *Node) openMediaStreamForRelay(operation string, relay RelayInfo) (*mediaStream, error) {
	return n.openMediaStreamForRelayWithDial(operation, relay, true)
}

// Explicit same-peer protocol retries reuse an authenticated connection. They
// must not restart the entire address race or acquire another dial budget.
func (n *Node) openMediaStreamForRelayWithDial(operation string, relay RelayInfo, allowDial bool) (*mediaStream, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	totalStart := time.Now()
	ctx, cancel := context.WithTimeout(n.ctx, MediaTimeout)

	connectStart := time.Now()
	if allowDial {
		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			cancel()
			n.emitEvent("media:stream_open_timing", mediaEventDetails(&mediaStream{
				operation:       operation,
				sourcePeerId:    relay.ID.String(),
				streamTransport: "unknown",
			}, map[string]interface{}{
				"connectMs": time.Since(connectStart).Milliseconds(),
				"totalMs":   time.Since(totalStart).Milliseconds(),
				"outcome":   "connect_failed",
			}))
			return nil, fmt.Errorf("connect to relay: %w", err)
		}
	} else {
		ctx = network.WithNoDial(ctx, "media-protocol-retry")
	}
	connectMs := time.Since(connectStart).Milliseconds()

	streamStart := time.Now()
	s, err := h.NewStream(ctx, relay.ID, MediaProtocol)
	if err != nil {
		cancel()
		n.emitEvent("media:stream_open_timing", mediaEventDetails(&mediaStream{
			operation:       operation,
			sourcePeerId:    relay.ID.String(),
			streamTransport: "unknown",
		}, map[string]interface{}{
			"connectMs":   connectMs,
			"newStreamMs": time.Since(streamStart).Milliseconds(),
			"totalMs":     time.Since(totalStart).Milliseconds(),
			"outcome":     "stream_failed",
		}))
		return nil, err
	}
	stream := &mediaStream{
		stream:          s,
		cancel:          cancel,
		operation:       operation,
		sourcePeerId:    relay.ID.String(),
		streamTransport: classifyStreamTransport(s),
	}
	n.emitEvent("media:stream_open_timing", mediaEventDetails(stream, map[string]interface{}{
		"connectMs":   connectMs,
		"newStreamMs": time.Since(streamStart).Milliseconds(),
		"totalMs":     time.Since(totalStart).Milliseconds(),
		"outcome":     "success",
	}))
	setStreamDeadline(s, MediaTimeout)
	switch operation {
	case "upload", "upload_custody", "upload_custody_probe", "profile_upload":
		stream.stream = &mediaUploadStream{
			Stream:           s,
			idleTimeout:      MediaIdleTimeout,
			absoluteDeadline: time.Now().Add(MediaTimeout),
		}
	}
	return stream, nil
}

// openMediaStream connects to the relay and opens a MediaProtocol stream.
// Tries each configured relay in order until one succeeds.
func (n *Node) openMediaStream(operation string) (*mediaStream, error) {
	rs := n.buildRelaySelector(nil)
	return ForEachWithResult(rs, func(relay RelayInfo) (*mediaStream, error) {
		return n.openMediaStreamForRelay(operation, relay)
	})
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

func copyMediaDownloadToFile(outputPath string, reader io.Reader, expectedSize int64, idleTimeout time.Duration, progressFn func(receivedBytes, totalBytes int64)) (int64, error) {
	f, err := os.Create(outputPath)
	if err != nil {
		return 0, fmt.Errorf("create output file: %w", err)
	}

	src := reader
	if progressFn != nil {
		// Same 256KiB/250ms cadence as the upload reader. Each tick lets the
		// caller re-arm its stream deadline so a slow-but-moving transfer is
		// never killed by a fixed wall clock; stall detection (idleTimeout)
		// stays the failure authority.
		src = &mediaUploadProgressReader{
			reader:         reader,
			totalBytes:     expectedSize,
			lastEmitAt:     time.Now(),
			emitProgressFn: progressFn,
		}
	}
	idleReader := newIdleTimeoutReader(src, idleTimeout)
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
	ms, err := n.openMediaStream("upload")
	if err != nil {
		return err
	}
	s := ms.stream
	defer ms.cancel()
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
	if _, err := io.Copy(s, progressReader); err != nil {
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
	n.emitEvent("media:upload_complete", mediaEventDetails(ms, map[string]interface{}{
		"id":                    id,
		"totalBytes":            fi.Size(),
		"totalMs":               transferMs,
		"throughputBytesPerSec": throughput,
	}))
	log.Printf("[MEDIA] Uploaded blob %s (%d bytes) to %s", id, fi.Size(), toPeerId[:min(20, len(toPeerId))])
	streamOK = true
	return nil
}

// MediaDownload downloads a blob from the relay's media store.
func (n *Node) MediaDownload(id, outputPath string) (MediaDownloadResult, error) {
	rs := n.buildRelaySelector(nil)
	return n.mediaDownloadAcrossRelays(rs, func(relay RelayInfo, allowDial bool) (MediaDownloadResult, bool, error) {
		ms, err := n.openMediaStreamForRelayWithDial("download", relay, allowDial)
		if err != nil {
			return MediaDownloadResult{}, true, err
		}
		return n.mediaDownloadFromStream(ms, id, outputPath)
	})
}

func (n *Node) mediaDownloadAcrossRelays(
	rs *RelaySelector,
	attempt func(RelayInfo, bool) (MediaDownloadResult, bool, error),
) (MediaDownloadResult, error) {
	relays := rs.Relays()
	if len(relays) == 0 {
		return MediaDownloadResult{}, fmt.Errorf("no relays configured")
	}

	var lastErr error
	for i, relay := range relays {
		for j := 0; j < max(1, len(relay.Addrs)); j++ {
			result, retry, err := attempt(relay, j == 0)
			if err == nil {
				return result, nil
			}
			lastErr = err
			if !retry {
				return MediaDownloadResult{}, err
			}
			log.Printf("[MEDIA] Relay %d/%d addr %d/%d (%s) media download failed, trying next eligible relay: %v",
				i+1, len(relays), j+1, max(1, len(relay.Addrs)), relay.ID.String()[:min(20, len(relay.ID.String()))], err)
		}
	}

	return MediaDownloadResult{}, fmt.Errorf("all %d relays failed, last error: %w", len(relays), lastErr)
}

func (n *Node) mediaDownloadFromStream(ms *mediaStream, id, outputPath string) (MediaDownloadResult, bool, error) {
	s := ms.stream
	defer ms.cancel()
	streamOK := false
	defer finishStream(s, &streamOK)

	// Send download request
	resp, sErr := sendMediaRequest(s, &mediaRequest{
		Action: "download",
		ID:     id,
	})
	if sErr != nil {
		err := fmt.Errorf("download request: %w", sErr)
		n.emitEvent("media:download_failed", mediaEventDetails(ms, map[string]interface{}{
			"id":    id,
			"error": err.Error(),
		}))
		return MediaDownloadResult{}, true, err
	}

	if resp.Status != "OK" {
		err := fmt.Errorf("download failed: %s", resp.Error)
		n.emitEvent("media:download_failed", mediaEventDetails(ms, map[string]interface{}{
			"id":    id,
			"error": err.Error(),
		}))
		return MediaDownloadResult{}, resp.Error == "not found", err
	}

	// Read exactly resp.Size bytes. Each progress tick re-arms the stream
	// deadline (rolling), so the transfer only dies on a genuine stall.
	downloadStart := time.Now()
	downloadProgressFn := func(receivedBytes, totalBytes int64) {
		setStreamDeadline(s, MediaTimeout)
		n.emitEvent("media:download_progress", map[string]interface{}{
			"id":            id,
			"receivedBytes": receivedBytes,
			"totalBytes":    totalBytes,
			"fromPeerId":    ms.sourcePeerId,
		})
	}
	if _, sErr := copyMediaDownloadToFile(outputPath, s, resp.Size, MediaIdleTimeout, downloadProgressFn); sErr != nil {
		n.emitEvent("media:download_failed", mediaEventDetails(ms, map[string]interface{}{
			"id":    id,
			"error": sErr.Error(),
		}))
		return MediaDownloadResult{}, !strings.HasPrefix(sErr.Error(), "create output file:"), sErr
	}

	downloadMs := time.Since(downloadStart).Milliseconds()
	dlThroughput := int64(0)
	if downloadMs > 0 {
		dlThroughput = (resp.Size * 1000) / downloadMs
	}
	n.emitEvent("media:download_complete", mediaEventDetails(ms, map[string]interface{}{
		"id":                    id,
		"totalBytes":            resp.Size,
		"totalMs":               downloadMs,
		"throughputBytesPerSec": dlThroughput,
	}))
	log.Printf("[MEDIA] Downloaded blob %s (%d bytes, %s)", id, resp.Size, resp.Mime)
	streamOK = true
	return mediaDownloadResultFromStream(ms, resp.Mime, resp.Size), false, nil
}

// MediaDelete deletes a blob from the relay's media store.
func (n *Node) MediaDelete(id string) error {
	ms, err := n.openMediaStream("delete")
	if err != nil {
		return err
	}
	s := ms.stream
	defer ms.cancel()
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

type mediaCustodyExpectedProof struct {
	ID              string
	CustodyKind     string
	CustodyContract string
	ContentHash     string
	Size            int64
	Mime            string
	ExpiresAtMs     int64
}

type mediaCustodyAttemptDisposition int

const (
	mediaCustodyAttemptTerminal mediaCustodyAttemptDisposition = iota
	mediaCustodyAttemptTrySibling
	mediaCustodyAttemptTryNextPeer
	mediaCustodyAttemptAmbiguous
)

func validateMediaCustodyContract(kind, contract string) error {
	if (kind != CustodyKindDirectMediaBlobV1 && kind != CustodyKindGroupMediaBlobV1) ||
		contract != AckOrExpiryCustodyContract {
		return fmt.Errorf("%w: contract=%q kind=%q", ErrMediaCustodyIneligible, contract, kind)
	}
	return nil
}

func isLowerSHA256(value string) bool {
	if len(value) != sha256.Size*2 {
		return false
	}
	for _, r := range value {
		if (r < '0' || r > '9') && (r < 'a' || r > 'f') {
			return false
		}
	}
	return true
}

func hashAndRewindMediaFile(file *os.File) (string, int64, error) {
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return "", 0, fmt.Errorf("rewind media file: %w", err)
	}
	info, err := file.Stat()
	if err != nil {
		return "", 0, fmt.Errorf("stat media file: %w", err)
	}
	if info.Size() <= 0 {
		return "", 0, fmt.Errorf("media file must be non-empty")
	}
	hasher := sha256.New()
	written, err := io.Copy(hasher, file)
	if err != nil {
		return "", 0, fmt.Errorf("hash media file: %w", err)
	}
	if written != info.Size() {
		return "", 0, fmt.Errorf("hash media file: read %d/%d bytes", written, info.Size())
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return "", 0, fmt.Errorf("rewind hashed media file: %w", err)
	}
	return fmt.Sprintf("%x", hasher.Sum(nil)), info.Size(), nil
}

func mediaCustodyResultFromResponse(resp *mediaResponse, relayPeerID string) MediaCustodyResult {
	if resp == nil {
		return MediaCustodyResult{CustodyRelayPeerId: relayPeerID}
	}
	return MediaCustodyResult{
		ID:                 resp.ID,
		CustodyKind:        resp.CustodyKind,
		CustodyContract:    resp.CustodyContract,
		ContentHash:        resp.ContentHash,
		Size:               resp.Size,
		Mime:               resp.Mime,
		ExpiresAtMs:        resp.ExpiresAtMs,
		StoreStatus:        resp.StoreStatus,
		AckStatus:          resp.AckStatus,
		ErrorCode:          resp.ErrorCode,
		ErrorMessage:       resp.Error,
		CustodyRelayPeerId: relayPeerID,
	}
}

func mediaCustodyFailure(code, message, relayPeerID string) (MediaCustodyResult, error) {
	result := MediaCustodyResult{
		ErrorCode:          code,
		ErrorMessage:       message,
		CustodyRelayPeerId: relayPeerID,
	}
	return result, mediaCustodyError(code, message)
}

func mediaCustodyError(code, message string) error {
	var sentinel error
	switch code {
	case MediaCustodyAdmissionDisabledCode:
		sentinel = ErrMediaCustodyAdmissionDisabled
	case MediaCustodyFullCode:
		sentinel = ErrMediaCustodyFull
	case MediaCustodyUnsupportedCode:
		sentinel = ErrMediaCustodyUnsupported
	case MediaCustodyIdentityConflictCode:
		sentinel = ErrMediaCustodyIdentityConflict
	case MediaCustodyIneligibleCode:
		sentinel = ErrMediaCustodyIneligible
	case MediaCustodyNotAuthorizedCode:
		sentinel = ErrMediaCustodyNotAuthorized
	case MediaCustodyHashMismatchCode:
		sentinel = ErrMediaCustodyHashMismatch
	case MediaCustodyAlreadyAckedCode:
		sentinel = ErrMediaCustodyAlreadyAcked
	case MediaCustodyCleanupPendingCode:
		sentinel = ErrMediaCustodyCleanupPending
	case MediaCustodyStorageErrorCode:
		sentinel = ErrMediaCustodyStorage
	case MediaCustodyNotFoundCode:
		sentinel = ErrMediaCustodyNotFound
	case MediaCustodyCommitIndeterminateCode:
		sentinel = ErrMediaCustodyCommitIndeterminate
	default:
		sentinel = errors.New("media custody operation failed")
	}
	if message == "" {
		message = code
	}
	return fmt.Errorf("%w: %s", sentinel, message)
}

func normalizeMediaCustodyError(resp *mediaResponse) string {
	if resp == nil {
		return MediaCustodyUnsupportedCode
	}
	if resp.ErrorCode != "" {
		return resp.ErrorCode
	}
	message := strings.ToLower(resp.Error)
	switch {
	case strings.Contains(message, "not found"), strings.Contains(message, "expired"):
		return MediaCustodyNotFoundCode
	case strings.Contains(message, "not authorized"), strings.Contains(message, "unauthorized"):
		return MediaCustodyNotAuthorizedCode
	default:
		return MediaCustodyUnsupportedCode
	}
}

func mediaCustodyResponseError(resp *mediaResponse, relayPeerID string) (MediaCustodyResult, error) {
	result := mediaCustodyResultFromResponse(resp, relayPeerID)
	result.ErrorCode = normalizeMediaCustodyError(resp)
	message := result.ErrorMessage
	if message == "" {
		message = result.ErrorCode
	}
	return result, mediaCustodyError(result.ErrorCode, message)
}

func mediaCustodyProofMatches(resp *mediaResponse, expected mediaCustodyExpectedProof, requireExpiry bool) bool {
	if resp == nil || resp.ID != expected.ID || resp.CustodyKind != expected.CustodyKind ||
		resp.CustodyContract != expected.CustodyContract || resp.ContentHash != expected.ContentHash ||
		resp.Size != expected.Size || resp.Mime != expected.Mime {
		return false
	}
	if requireExpiry {
		return expected.ExpiresAtMs > 0 && resp.ExpiresAtMs == expected.ExpiresAtMs
	}
	return resp.ExpiresAtMs > 0
}

func mediaCustodyResponseHasProof(resp *mediaResponse) bool {
	return resp != nil && (resp.CustodyKind != "" || resp.CustodyContract != "" ||
		resp.ContentHash != "" || resp.ExpiresAtMs != 0)
}

func mediaCustodyUploadSuccessMatches(resp *mediaResponse, expected mediaCustodyExpectedProof) bool {
	return resp != nil && resp.Status == "OK" && resp.Error == "" && resp.ErrorCode == "" &&
		resp.AckStatus == "" &&
		(resp.StoreStatus == "stored" || resp.StoreStatus == "duplicate") &&
		mediaCustodyProofMatches(resp, expected, false)
}

func mediaCustodyDownloadSuccessMatches(resp *mediaResponse, expected mediaCustodyExpectedProof) bool {
	return resp != nil && resp.Status == "OK" && resp.Error == "" && resp.ErrorCode == "" &&
		resp.StoreStatus == "" && resp.AckStatus == "" &&
		mediaCustodyProofMatches(resp, expected, true)
}

func mediaCustodyAckSuccessMatches(resp *mediaResponse, expected mediaCustodyExpectedProof) bool {
	return resp != nil && resp.Status == "OK" && resp.Error == "" && resp.ErrorCode == "" &&
		resp.StoreStatus == "" &&
		(resp.AckStatus == "acked" || resp.AckStatus == "already_acked") &&
		mediaCustodyProofMatches(resp, expected, true)
}

func mediaCustodyExplicitPreBodyNonCommit(resp *mediaResponse, code string) bool {
	if resp == nil || resp.Status != "ERROR" || resp.AckStatus != "" ||
		mediaCustodyResponseHasProof(resp) {
		return false
	}
	switch code {
	case MediaCustodyAdmissionDisabledCode:
		return resp.StoreStatus == "disabled"
	case MediaCustodyFullCode:
		return resp.StoreStatus == "rejected_full"
	case MediaCustodyUnsupportedCode:
		return resp.StoreStatus == ""
	default:
		return false
	}
}

func mediaCustodyWrongProof(
	resp *mediaResponse,
	expected mediaCustodyExpectedProof,
	relayPeerID string,
) (MediaCustodyResult, error) {
	code := MediaCustodyIdentityConflictCode
	message := "relay returned a conflicting custody proof"
	if resp != nil && resp.ContentHash != "" && resp.ContentHash != expected.ContentHash {
		code = MediaCustodyHashMismatchCode
		message = "relay returned a mismatched custody content hash"
	}
	result := mediaCustodyResultFromResponse(resp, relayPeerID)
	result.ErrorCode = code
	result.ErrorMessage = message
	return result, mediaCustodyError(code, message)
}

func isMediaCustodyPreBodyRetryCode(code string) bool {
	return code == MediaCustodyAdmissionDisabledCode ||
		code == MediaCustodyFullCode ||
		code == MediaCustodyUnsupportedCode
}

// MediaUploadCustody uploads one exact encrypted artifact to one proof-bearing
// relay. Failover is permitted only before READY/body transfer. An ambiguous
// post-body result is probed once against the same relay peer and never fanned
// out to another relay.
func (n *Node) MediaUploadCustody(
	id, toPeerID, mime, filePath, custodyKind, custodyContract, callerContentHash string,
) (MediaCustodyResult, error) {
	if err := validateMediaCustodyContract(custodyKind, custodyContract); err != nil {
		return mediaCustodyFailure(MediaCustodyIneligibleCode, err.Error(), "")
	}
	file, err := os.Open(filePath)
	if err != nil {
		return mediaCustodyFailure(MediaCustodyIneligibleCode, fmt.Sprintf("open file: %v", err), "")
	}
	defer file.Close()

	contentHash, size, err := hashAndRewindMediaFile(file)
	if err != nil {
		return mediaCustodyFailure(MediaCustodyIneligibleCode, err.Error(), "")
	}
	if !isLowerSHA256(callerContentHash) {
		return mediaCustodyFailure(MediaCustodyIneligibleCode, "caller content hash must be lowercase SHA-256", "")
	}
	if callerContentHash != contentHash {
		return mediaCustodyFailure(MediaCustodyHashMismatchCode, "caller content hash does not match local file", "")
	}
	if id == "" || toPeerID == "" || mime == "" {
		return mediaCustodyFailure(MediaCustodyIneligibleCode, "missing id, recipient, or mime", "")
	}

	expected := mediaCustodyExpectedProof{
		ID:              id,
		CustodyKind:     custodyKind,
		CustodyContract: custodyContract,
		ContentHash:     contentHash,
		Size:            size,
		Mime:            mime,
	}
	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return mediaCustodyFailure(MediaCustodyUnsupportedCode, "no relays configured", "")
	}

	var lastResult MediaCustodyResult
	var lastErr error
	for _, relay := range relays {
		for attempt := 0; attempt < max(1, len(relay.Addrs)); attempt++ {
			result, disposition, attemptErr := n.mediaUploadCustodyToRelay(relay, file, expected, toPeerID, attempt == 0)
			lastResult, lastErr = result, attemptErr
			if attemptErr == nil {
				return result, nil
			}
			switch disposition {
			case mediaCustodyAttemptTrySibling:
				continue
			case mediaCustodyAttemptTryNextPeer:
				break
			case mediaCustodyAttemptAmbiguous:
				currentHash, currentSize, hashErr := hashAndRewindMediaFile(file)
				if hashErr != nil || currentHash != expected.ContentHash || currentSize != expected.Size {
					return mediaCustodyFailure(MediaCustodyHashMismatchCode, "local file changed before custody recovery probe", relay.ID.String())
				}
				recovered, probeErr := n.probeMediaCustodyDuplicate(relay, expected, toPeerID)
				if probeErr == nil {
					return recovered, nil
				}
				if errors.Is(probeErr, ErrMediaCustodyIdentityConflict) ||
					errors.Is(probeErr, ErrMediaCustodyIneligible) ||
					errors.Is(probeErr, ErrMediaCustodyNotAuthorized) ||
					errors.Is(probeErr, ErrMediaCustodyHashMismatch) ||
					errors.Is(probeErr, ErrMediaCustodyAlreadyAcked) {
					return recovered, probeErr
				}
				n.emitEvent("media:custody_flow", map[string]interface{}{
					"operation": "upload",
					"outcome":   "indeterminate_after_body",
				})
				return mediaCustodyFailure(
					MediaCustodyCommitIndeterminateCode,
					"final custody proof was not recoverable from the selected relay",
					relay.ID.String(),
				)
			default:
				return result, attemptErr
			}
			if disposition == mediaCustodyAttemptTryNextPeer {
				break
			}
		}
	}
	if lastErr == nil {
		return mediaCustodyFailure(MediaCustodyUnsupportedCode, "no relay accepted media custody", "")
	}
	return lastResult, fmt.Errorf("all %d relays failed to accept media custody: %w", len(relays), lastErr)
}

func (n *Node) mediaUploadCustodyToRelay(
	relay RelayInfo,
	file *os.File,
	expected mediaCustodyExpectedProof,
	toPeerID string,
	allowDial bool,
) (MediaCustodyResult, mediaCustodyAttemptDisposition, error) {
	ms, err := n.openMediaStreamForRelayWithDial("upload_custody", relay, allowDial)
	if err != nil {
		result, resultErr := mediaCustodyFailure(MediaCustodyUnsupportedCode, err.Error(), relay.ID.String())
		return result, mediaCustodyAttemptTrySibling, resultErr
	}
	s := ms.stream
	defer ms.cancel()
	streamOK := false
	defer finishStream(s, &streamOK)

	resp, err := sendMediaRequest(s, &mediaRequest{
		Action:          mediaUploadCustodyAction,
		ID:              expected.ID,
		To:              toPeerID,
		Size:            expected.Size,
		Mime:            expected.Mime,
		CustodyKind:     expected.CustodyKind,
		CustodyContract: expected.CustodyContract,
		ContentHash:     expected.ContentHash,
	})
	if err != nil {
		result, resultErr := mediaCustodyFailure(MediaCustodyUnsupportedCode, err.Error(), relay.ID.String())
		return result, mediaCustodyAttemptTrySibling, resultErr
	}
	if resp.Status == "OK" {
		if resp.StoreStatus == "duplicate" && mediaCustodyUploadSuccessMatches(resp, expected) {
			streamOK = true
			return mediaCustodyResultFromResponse(resp, relay.ID.String()), mediaCustodyAttemptTerminal, nil
		}
		if mediaCustodyResponseHasProof(resp) || resp.StoreStatus != "" || resp.AckStatus != "" {
			if !mediaCustodyProofMatches(resp, expected, false) {
				result, resultErr := mediaCustodyWrongProof(resp, expected, relay.ID.String())
				return result, mediaCustodyAttemptTerminal, resultErr
			}
			result, resultErr := mediaCustodyFailure(
				MediaCustodyIdentityConflictCode,
				"relay returned a contradictory upload custody proof",
				relay.ID.String(),
			)
			return result, mediaCustodyAttemptTerminal, resultErr
		}
		result, resultErr := mediaCustodyFailure(MediaCustodyUnsupportedCode, "pre-body response missing exact duplicate proof", relay.ID.String())
		return result, mediaCustodyAttemptTryNextPeer, resultErr
	}
	if resp.Status == "ERROR" {
		result, resultErr := mediaCustodyResponseError(resp, relay.ID.String())
		if isMediaCustodyPreBodyRetryCode(result.ErrorCode) &&
			mediaCustodyExplicitPreBodyNonCommit(resp, result.ErrorCode) {
			return result, mediaCustodyAttemptTryNextPeer, resultErr
		}
		return result, mediaCustodyAttemptTerminal, resultErr
	}
	if resp.Status != "READY" || resp.Error != "" || resp.ErrorCode != "" ||
		resp.StoreStatus != "" || resp.AckStatus != "" || mediaCustodyResponseHasProof(resp) {
		result, resultErr := mediaCustodyFailure(MediaCustodyUnsupportedCode, "relay did not authorize strict body transfer", relay.ID.String())
		if mediaCustodyResponseHasProof(resp) || resp.StoreStatus != "" || resp.AckStatus != "" {
			return result, mediaCustodyAttemptTerminal, resultErr
		}
		return result, mediaCustodyAttemptTryNextPeer, resultErr
	}

	if _, err := file.Seek(0, io.SeekStart); err != nil {
		result, resultErr := mediaCustodyFailure(MediaCustodyCommitIndeterminateCode, err.Error(), relay.ID.String())
		return result, mediaCustodyAttemptAmbiguous, resultErr
	}
	progressReader := &mediaUploadProgressReader{
		reader:     file,
		totalBytes: expected.Size,
		lastEmitAt: time.Now(),
		emitProgressFn: func(sentBytes, totalBytes int64) {
			n.emitEvent("media:upload_progress", map[string]interface{}{
				"id":         expected.ID,
				"sentBytes":  sentBytes,
				"totalBytes": totalBytes,
				"toPeerId":   toPeerID,
			})
		},
	}
	progressReader.emitProgressFn(0, expected.Size)
	if _, err := io.CopyN(s, progressReader, expected.Size); err != nil {
		result, resultErr := mediaCustodyFailure(MediaCustodyCommitIndeterminateCode, fmt.Sprintf("stream file data: %v", err), relay.ID.String())
		return result, mediaCustodyAttemptAmbiguous, resultErr
	}
	progressReader.emitProgressFn(expected.Size, expected.Size)

	confirmBytes, err := readFrame(s)
	if err != nil {
		result, resultErr := mediaCustodyFailure(MediaCustodyCommitIndeterminateCode, fmt.Sprintf("read upload confirmation: %v", err), relay.ID.String())
		return result, mediaCustodyAttemptAmbiguous, resultErr
	}
	var confirm mediaResponse
	if err := json.Unmarshal(confirmBytes, &confirm); err != nil {
		result, resultErr := mediaCustodyFailure(MediaCustodyCommitIndeterminateCode, fmt.Sprintf("unmarshal upload confirmation: %v", err), relay.ID.String())
		return result, mediaCustodyAttemptAmbiguous, resultErr
	}
	if confirm.Status == "ERROR" {
		result, resultErr := mediaCustodyResponseError(&confirm, relay.ID.String())
		switch result.ErrorCode {
		case MediaCustodyIdentityConflictCode, MediaCustodyIneligibleCode,
			MediaCustodyNotAuthorizedCode, MediaCustodyHashMismatchCode,
			MediaCustodyAlreadyAckedCode:
			return result, mediaCustodyAttemptTerminal, resultErr
		default:
			return result, mediaCustodyAttemptAmbiguous, resultErr
		}
	}
	if confirm.Status == "OK" && mediaCustodyResponseHasProof(&confirm) {
		if !mediaCustodyProofMatches(&confirm, expected, false) {
			result, resultErr := mediaCustodyWrongProof(&confirm, expected, relay.ID.String())
			return result, mediaCustodyAttemptTerminal, resultErr
		}
		if !mediaCustodyUploadSuccessMatches(&confirm, expected) {
			result, resultErr := mediaCustodyFailure(
				MediaCustodyIdentityConflictCode,
				"relay returned a contradictory final upload proof",
				relay.ID.String(),
			)
			return result, mediaCustodyAttemptTerminal, resultErr
		}
	}
	if !mediaCustodyUploadSuccessMatches(&confirm, expected) {
		result, resultErr := mediaCustodyFailure(MediaCustodyCommitIndeterminateCode, "final response missing exact custody proof", relay.ID.String())
		return result, mediaCustodyAttemptAmbiguous, resultErr
	}
	streamOK = true
	return mediaCustodyResultFromResponse(&confirm, relay.ID.String()), mediaCustodyAttemptTerminal, nil
}

func (n *Node) probeMediaCustodyDuplicate(
	relay RelayInfo,
	expected mediaCustodyExpectedProof,
	toPeerID string,
) (MediaCustodyResult, error) {
	var lastErr error
	for _, candidate := range relayInfoAttemptCandidates(relay) {
		ms, err := n.openMediaStreamForRelay("upload_custody_probe", candidate)
		if err != nil {
			lastErr = err
			continue
		}
		resp, requestErr := sendMediaRequest(ms.stream, &mediaRequest{
			Action:          mediaUploadCustodyAction,
			ID:              expected.ID,
			To:              toPeerID,
			Size:            expected.Size,
			Mime:            expected.Mime,
			CustodyKind:     expected.CustodyKind,
			CustodyContract: expected.CustodyContract,
			ContentHash:     expected.ContentHash,
		})
		ms.cancel()
		_ = ms.stream.Reset()
		if requestErr != nil {
			lastErr = requestErr
			continue
		}
		if resp.Status == "OK" && resp.StoreStatus == "duplicate" &&
			mediaCustodyUploadSuccessMatches(resp, expected) {
			return mediaCustodyResultFromResponse(resp, relay.ID.String()), nil
		}
		if resp.Status == "OK" && (mediaCustodyResponseHasProof(resp) ||
			resp.StoreStatus != "" || resp.AckStatus != "") {
			if !mediaCustodyProofMatches(resp, expected, false) {
				return mediaCustodyWrongProof(resp, expected, relay.ID.String())
			}
			return mediaCustodyFailure(
				MediaCustodyIdentityConflictCode,
				"relay returned a contradictory duplicate proof",
				relay.ID.String(),
			)
		}
		if resp.Status == "ERROR" {
			result, responseErr := mediaCustodyResponseError(resp, relay.ID.String())
			return result, responseErr
		}
		lastErr = ErrMediaCustodyCommitIndeterminate
		break
	}
	if lastErr == nil {
		lastErr = ErrMediaCustodyCommitIndeterminate
	}
	return MediaCustodyResult{CustodyRelayPeerId: relay.ID.String()}, lastErr
}

// MediaDownloadCustody downloads only a response carrying the complete exact
// proof, verifies the streamed ciphertext hash, and records the concrete relay
// peer that must later receive the ACK.
func (n *Node) MediaDownloadCustody(
	id, outputPath, custodyKind, custodyContract, contentHash string,
	size int64,
	mime string,
	expiresAtMs int64,
) (MediaDownloadResult, error) {
	if err := validateMediaCustodyContract(custodyKind, custodyContract); err != nil ||
		id == "" || outputPath == "" || !isLowerSHA256(contentHash) || size <= 0 || mime == "" || expiresAtMs <= 0 {
		if err == nil {
			err = ErrMediaCustodyIneligible
		}
		return MediaDownloadResult{ErrorCode: MediaCustodyIneligibleCode, ErrorMessage: "invalid strict download tuple"},
			fmt.Errorf("%w: invalid strict download tuple", err)
	}
	expected := mediaCustodyExpectedProof{
		ID: id, CustodyKind: custodyKind, CustodyContract: custodyContract,
		ContentHash: contentHash, Size: size, Mime: mime, ExpiresAtMs: expiresAtMs,
	}
	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return MediaDownloadResult{ErrorCode: MediaCustodyUnsupportedCode, ErrorMessage: "no relays configured"},
			fmt.Errorf("%w: no relays configured", ErrMediaCustodyUnsupported)
	}
	var lastResult MediaDownloadResult
	var lastErr error
	for _, relay := range relays {
		for attempt := 0; attempt < max(1, len(relay.Addrs)); attempt++ {
			result, retrySibling, retryPeer, err := n.mediaDownloadCustodyFromRelay(relay, outputPath, expected, attempt == 0)
			if err == nil {
				return result, nil
			}
			lastResult = result
			lastErr = err
			if retrySibling {
				continue
			}
			if retryPeer {
				break
			}
			return result, err
		}
	}
	if lastErr == nil {
		lastErr = ErrMediaCustodyNotFound
	}
	return lastResult, fmt.Errorf("all %d relays failed strict media download: %w", len(relays), lastErr)
}

func mediaDownloadResultFromCustodyFailure(result MediaCustodyResult) MediaDownloadResult {
	return MediaDownloadResult{
		Mime:               result.Mime,
		Size:               result.Size,
		CustodyKind:        result.CustodyKind,
		CustodyContract:    result.CustodyContract,
		ContentHash:        result.ContentHash,
		ExpiresAtMs:        result.ExpiresAtMs,
		CustodyRelayPeerId: result.CustodyRelayPeerId,
		ErrorCode:          result.ErrorCode,
		ErrorMessage:       result.ErrorMessage,
	}
}

func (n *Node) mediaDownloadCustodyFromRelay(
	relay RelayInfo,
	outputPath string,
	expected mediaCustodyExpectedProof,
	allowDial bool,
) (MediaDownloadResult, bool, bool, error) {
	ms, err := n.openMediaStreamForRelayWithDial("download_custody", relay, allowDial)
	if err != nil {
		return MediaDownloadResult{
			ErrorCode: MediaCustodyUnsupportedCode, ErrorMessage: err.Error(), CustodyRelayPeerId: relay.ID.String(),
		}, true, false, err
	}
	s := ms.stream
	defer ms.cancel()
	streamOK := false
	defer finishStream(s, &streamOK)
	resp, err := sendMediaRequest(s, &mediaRequest{
		Action:          "download",
		ID:              expected.ID,
		To:              n.peerId,
		Size:            expected.Size,
		Mime:            expected.Mime,
		CustodyKind:     expected.CustodyKind,
		CustodyContract: expected.CustodyContract,
		ContentHash:     expected.ContentHash,
		ExpiresAtMs:     expected.ExpiresAtMs,
	})
	if err != nil {
		return MediaDownloadResult{
			ErrorCode: MediaCustodyUnsupportedCode, ErrorMessage: err.Error(), CustodyRelayPeerId: relay.ID.String(),
		}, true, false, fmt.Errorf("strict download request: %w", err)
	}
	if resp.Status == "ERROR" {
		if mediaCustodyResponseHasProof(resp) || resp.StoreStatus != "" || resp.AckStatus != "" {
			wrong, wrongErr := mediaCustodyFailure(
				MediaCustodyIdentityConflictCode,
				"relay returned custody proof/status fields on a download error",
				relay.ID.String(),
			)
			return mediaDownloadResultFromCustodyFailure(wrong), false, false, wrongErr
		}
		result, responseErr := mediaCustodyResponseError(resp, relay.ID.String())
		if result.ErrorCode == MediaCustodyNotFoundCode || result.ErrorCode == MediaCustodyUnsupportedCode {
			return mediaDownloadResultFromCustodyFailure(result), false, true, responseErr
		}
		return mediaDownloadResultFromCustodyFailure(result), false, false, responseErr
	}
	if resp.Status == "OK" && (mediaCustodyResponseHasProof(resp) ||
		resp.StoreStatus != "" || resp.AckStatus != "") {
		if !mediaCustodyProofMatches(resp, expected, true) {
			wrongProof, proofErr := mediaCustodyWrongProof(resp, expected, relay.ID.String())
			return mediaDownloadResultFromCustodyFailure(wrongProof), false, false, proofErr
		}
		if !mediaCustodyDownloadSuccessMatches(resp, expected) {
			wrong, wrongErr := mediaCustodyFailure(
				MediaCustodyIdentityConflictCode,
				"relay returned a contradictory download proof",
				relay.ID.String(),
			)
			return mediaDownloadResultFromCustodyFailure(wrong), false, false, wrongErr
		}
	}
	if !mediaCustodyDownloadSuccessMatches(resp, expected) {
		return MediaDownloadResult{
				ErrorCode: MediaCustodyUnsupportedCode, ErrorMessage: "strict download response missing exact proof",
				CustodyRelayPeerId: relay.ID.String(),
			}, false, true,
			fmt.Errorf("%w: strict download response missing exact proof", ErrMediaCustodyUnsupported)
	}

	progressFn := func(receivedBytes, totalBytes int64) {
		setStreamDeadline(s, MediaTimeout)
		n.emitEvent("media:download_progress", map[string]interface{}{
			"id":            expected.ID,
			"receivedBytes": receivedBytes,
			"totalBytes":    totalBytes,
			"fromPeerId":    ms.sourcePeerId,
		})
	}
	if _, err := copyMediaCustodyDownloadToFile(
		outputPath, s, expected.Size, expected.ContentHash, MediaIdleTimeout, progressFn,
	); err != nil {
		if errors.Is(err, ErrMediaCustodyHashMismatch) {
			return MediaDownloadResult{
				ErrorCode: MediaCustodyHashMismatchCode, ErrorMessage: err.Error(),
				CustodyRelayPeerId: relay.ID.String(),
			}, false, false, err
		}
		return MediaDownloadResult{
			ErrorCode: MediaCustodyUnsupportedCode, ErrorMessage: err.Error(),
			CustodyRelayPeerId: relay.ID.String(),
		}, true, false, err
	}

	result := mediaDownloadResultFromStream(ms, resp.Mime, resp.Size)
	result.CustodyKind = resp.CustodyKind
	result.CustodyContract = resp.CustodyContract
	result.ContentHash = resp.ContentHash
	result.ExpiresAtMs = resp.ExpiresAtMs
	result.CustodyRelayPeerId = relay.ID.String()
	streamOK = true
	return result, false, false, nil
}

func copyMediaCustodyDownloadToFile(
	outputPath string,
	reader io.Reader,
	expectedSize int64,
	expectedHash string,
	idleTimeout time.Duration,
	progressFn func(receivedBytes, totalBytes int64),
) (int64, error) {
	file, err := os.Create(outputPath)
	if err != nil {
		return 0, fmt.Errorf("create output file: %w", err)
	}
	hasher := sha256.New()
	source := reader
	if progressFn != nil {
		source = &mediaUploadProgressReader{
			reader: reader, totalBytes: expectedSize, lastEmitAt: time.Now(), emitProgressFn: progressFn,
		}
	}
	written, copyErr := io.CopyN(io.MultiWriter(file, hasher), newIdleTimeoutReader(source, idleTimeout), expectedSize)
	closeErr := file.Close()
	if copyErr == nil {
		copyErr = closeErr
	}
	if copyErr != nil || written != expectedSize {
		_ = os.Remove(outputPath)
		return written, fmt.Errorf("download incomplete: wrote %d/%d, err=%v", written, expectedSize, copyErr)
	}
	actualHash := fmt.Sprintf("%x", hasher.Sum(nil))
	if actualHash != expectedHash {
		_ = os.Remove(outputPath)
		return written, fmt.Errorf("%w: expected %s got %s", ErrMediaCustodyHashMismatch, expectedHash, actualHash)
	}
	return written, nil
}

// MediaAckCustody sends an exact ACK only to the configured relay peer that
// supplied the strict download proof. Sibling addresses for that peer may be
// retried, but no other relay peer is eligible.
func (n *Node) MediaAckCustody(
	id, custodyKind, custodyContract, contentHash string,
	size int64,
	mime string,
	expiresAtMs int64,
	custodyRelayPeerID string,
) (MediaCustodyResult, error) {
	if err := validateMediaCustodyContract(custodyKind, custodyContract); err != nil ||
		id == "" || !isLowerSHA256(contentHash) || size <= 0 || mime == "" || expiresAtMs <= 0 || custodyRelayPeerID == "" {
		if err == nil {
			err = ErrMediaCustodyIneligible
		}
		return mediaCustodyFailure(MediaCustodyIneligibleCode, "invalid strict ACK tuple", custodyRelayPeerID)
	}
	targetID, err := peer.Decode(custodyRelayPeerID)
	if err != nil || targetID.String() != custodyRelayPeerID {
		return mediaCustodyFailure(MediaCustodyIneligibleCode, "invalid custody relay peer ID", custodyRelayPeerID)
	}
	var target *RelayInfo
	for _, relay := range n.buildRelaySelector(nil).Relays() {
		if relay.ID == targetID {
			copyRelay := relay
			target = &copyRelay
			break
		}
	}
	if target == nil {
		return mediaCustodyFailure(MediaCustodyIneligibleCode, "custody relay peer is not configured", custodyRelayPeerID)
	}
	expected := mediaCustodyExpectedProof{
		ID: id, CustodyKind: custodyKind, CustodyContract: custodyContract,
		ContentHash: contentHash, Size: size, Mime: mime, ExpiresAtMs: expiresAtMs,
	}
	var lastErr error
	var lastResult MediaCustodyResult
	// Preserve the strict same-peer retry bound for cleanup-pending responses.
	// Every attempt carries all addresses; only the first may dial.
	for attempt := 0; attempt < max(1, len(target.Addrs)); attempt++ {
		ms, openErr := n.openMediaStreamForRelayWithDial("ack_custody", *target, attempt == 0)
		if openErr != nil {
			lastResult, lastErr = mediaCustodyFailure(MediaCustodyUnsupportedCode, openErr.Error(), custodyRelayPeerID)
			continue
		}
		resp, requestErr := sendMediaRequest(ms.stream, &mediaRequest{
			Action:          mediaAckCustodyAction,
			ID:              expected.ID,
			To:              n.peerId,
			Size:            expected.Size,
			Mime:            expected.Mime,
			CustodyKind:     expected.CustodyKind,
			CustodyContract: expected.CustodyContract,
			ContentHash:     expected.ContentHash,
			ExpiresAtMs:     expected.ExpiresAtMs,
		})
		ms.cancel()
		_ = ms.stream.Close()
		if requestErr != nil {
			lastResult, lastErr = mediaCustodyFailure(MediaCustodyUnsupportedCode, requestErr.Error(), custodyRelayPeerID)
			continue
		}
		if mediaCustodyAckSuccessMatches(resp, expected) {
			return mediaCustodyResultFromResponse(resp, custodyRelayPeerID), nil
		}
		if resp.Status == "OK" && mediaCustodyResponseHasProof(resp) {
			if !mediaCustodyProofMatches(resp, expected, true) {
				return mediaCustodyWrongProof(resp, expected, custodyRelayPeerID)
			}
			return mediaCustodyFailure(
				MediaCustodyIdentityConflictCode,
				"relay returned a contradictory ACK proof",
				custodyRelayPeerID,
			)
		}
		if resp.Status == "ERROR" {
			if mediaCustodyResponseHasProof(resp) || resp.StoreStatus != "" || resp.AckStatus != "" {
				return mediaCustodyFailure(
					MediaCustodyIdentityConflictCode,
					"relay returned custody proof/status fields on an ACK error",
					custodyRelayPeerID,
				)
			}
			result, responseErr := mediaCustodyResponseError(resp, custodyRelayPeerID)
			if result.ErrorCode == MediaCustodyCleanupPendingCode {
				lastResult, lastErr = result, responseErr
				continue
			}
			return result, responseErr
		}
		return mediaCustodyFailure(MediaCustodyUnsupportedCode, "ACK response missing exact proof", custodyRelayPeerID)
	}
	if lastErr == nil {
		return mediaCustodyFailure(MediaCustodyUnsupportedCode, "custody relay has no usable addresses", custodyRelayPeerID)
	}
	return lastResult, lastErr
}

// MediaList lists blobs available for this peer on the relay.
func (n *Node) MediaList() ([]MediaMeta, error) {
	ms, err := n.openMediaStream("list")
	if err != nil {
		return nil, err
	}
	s := ms.stream
	defer ms.cancel()
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
	ms, err := n.openMediaStream("profile_upload")
	if err != nil {
		return err
	}
	s := ms.stream
	defer ms.cancel()
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
	if _, err := io.Copy(s, progressReader); err != nil {
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
	ms, sErr := n.openMediaStream("profile_download")
	if sErr != nil {
		return "", 0, sErr
	}
	s := ms.stream
	defer ms.cancel()
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
