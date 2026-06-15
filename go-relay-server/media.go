package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
)

const (
	MediaProtocol        = "/mknoon/media/1.0.0"
	maxMediaPerPeer      = maxMessagesPerPeer
	mediaTTL             = 7 * 24 * time.Hour
	mediaCleanupInterval = 10 * time.Minute
	mediaDataDir         = "/data/media"
)

var (
	maxMediaSize         int64 = 5 * 1024 * 1024 * 1024 // 5 GB
	maxMediaBytesPerPeer int64 = 5 * 1024 * 1024 * 1024 // 5 GB pending bytes per recipient
)

// --- Media metadata ---

// 112 G7b: the sidecar deliberately carries NO sender identity — the
// sender→recipient social graph must not persist at rest for the blob's
// TTL. Download/delete authorization keys on To/AllowedPeers only; the
// live upload log still prints the authenticated peer. Legacy sidecars
// containing `from` still decode (unknown fields are ignored).
type mediaMeta struct {
	ID           string   `json:"id"`
	To           string   `json:"to"`
	Mime         string   `json:"mime"`
	Size         int64    `json:"size"`
	CreatedAt    int64    `json:"created_at"`
	AllowedPeers []string `json:"allowed_peers,omitempty"`
}

// --- Media store ---

type MediaStore struct {
	mu      sync.RWMutex
	index   map[string]*mediaMeta // blob ID → metadata
	byPeer  map[string][]string   // recipient peerId → list of blob IDs
	dataDir string

	cancelCleanup context.CancelFunc
}

func NewMediaStore(dataDir string) *MediaStore {
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Printf("[MEDIA] Warning: could not create data dir %s: %v", dataDir, err)
	}
	ms := &MediaStore{
		index:   make(map[string]*mediaMeta),
		byPeer:  make(map[string][]string),
		dataDir: dataDir,
	}
	ms.loadMetadata()
	return ms
}

func (ms *MediaStore) StartCleanup(ctx context.Context) {
	cleanupCtx, cancel := context.WithCancel(ctx)
	ms.cancelCleanup = cancel
	go func() {
		ticker := time.NewTicker(mediaCleanupInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				ms.cleanupExpired()
			case <-cleanupCtx.Done():
				return
			}
		}
	}()
}

func (ms *MediaStore) StopCleanup() {
	if ms.cancelCleanup != nil {
		ms.cancelCleanup()
	}
}

func (ms *MediaStore) cleanupExpired() {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	now := time.Now().UnixMilli()
	cutoff := now - mediaTTL.Milliseconds()
	var removed int

	for id, meta := range ms.index {
		if meta.CreatedAt < cutoff {
			size := meta.Size
			ms.removeLocked(id)
			removed++
			mediaExpiredCounter.Inc()
			mediaDeletedCounter.WithLabelValues("ttl_cleanup").Inc()
			mediaDeletedBytesCounter.WithLabelValues("ttl_cleanup").Add(float64(size))
		}
	}

	if removed > 0 {
		log.Printf("[MEDIA] Cleanup: removed %d expired blob(s)", removed)
	}
}

func (ms *MediaStore) Stats() (blobCount int, diskMB int64) {
	ms.mu.RLock()
	blobCount = len(ms.index)
	ms.mu.RUnlock()

	var totalBytes int64
	filepath.Walk(ms.dataDir, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() {
			totalBytes += info.Size()
		}
		return nil
	})
	diskMB = totalBytes / (1024 * 1024)
	return
}

func (ms *MediaStore) store(meta *mediaMeta) (int, error) {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	if err := ms.writeMetaAtomic(meta); err != nil {
		return 0, err
	}
	if existing := ms.index[meta.ID]; existing != nil {
		ms.removeIndexEntryLocked(existing)
		if existing.To != meta.To {
			ms.removeFilesLocked(existing)
		}
	}
	ms.index[meta.ID] = meta
	ms.byPeer[meta.To] = append(ms.byPeer[meta.To], meta.ID)

	removed := ms.prunePeerLocked(meta.To)
	if removed > 0 {
		log.Printf("[MEDIA] Pruned %d blob(s) for peer %s", removed, meta.To[:min(20, len(meta.To))])
	}
	return removed, nil
}

func (ms *MediaStore) prunePeerLocked(peerID string) int {
	ids := append([]string(nil), ms.byPeer[peerID]...)
	if len(ids) == 0 {
		return 0
	}

	totalBytes := ms.pendingBytesForPeerLocked(peerID)
	if len(ids) <= maxMediaPerPeer && totalBytes <= maxMediaBytesPerPeer {
		return 0
	}

	sort.Slice(ids, func(i, j int) bool {
		mi, mj := ms.index[ids[i]], ms.index[ids[j]]
		if mi == nil || mj == nil {
			return false
		}
		return mi.CreatedAt < mj.CreatedAt
	})

	removed := 0
	for removed < len(ids) &&
		((len(ids)-removed) > maxMediaPerPeer || totalBytes > maxMediaBytesPerPeer) {
		id := ids[removed]
		if meta := ms.index[id]; meta != nil {
			totalBytes -= meta.Size
			mediaDeletedCounter.WithLabelValues("peer_cap").Inc()
			mediaDeletedBytesCounter.WithLabelValues("peer_cap").Add(float64(meta.Size))
		}
		ms.removeLocked(id)
		removed++
	}

	return removed
}

func (ms *MediaStore) pendingBytesForPeerLocked(peerID string) int64 {
	var total int64
	for _, id := range ms.byPeer[peerID] {
		if meta := ms.index[id]; meta != nil {
			total += meta.Size
		}
	}
	return total
}

func (ms *MediaStore) lookup(id string) *mediaMeta {
	ms.mu.RLock()
	defer ms.mu.RUnlock()
	return ms.index[id]
}

func (ms *MediaStore) remove(id string) {
	ms.mu.Lock()
	defer ms.mu.Unlock()
	ms.removeLocked(id)
}

// removeLocked deletes a blob from index, byPeer, and disk. Caller must hold mu.
func (ms *MediaStore) removeLocked(id string) {
	meta, ok := ms.index[id]
	if !ok {
		return
	}

	ms.removeIndexEntryLocked(meta)
	ms.removeFilesLocked(meta)

	// Remove from index
	delete(ms.index, id)
}

func (ms *MediaStore) removeIndexEntryLocked(meta *mediaMeta) {
	ids := ms.byPeer[meta.To]
	for i, bid := range ids {
		if bid == meta.ID {
			ms.byPeer[meta.To] = append(ids[:i], ids[i+1:]...)
			break
		}
	}
	if len(ms.byPeer[meta.To]) == 0 {
		delete(ms.byPeer, meta.To)
	}
	delete(ms.index, meta.ID)
}

func (ms *MediaStore) removeFilesLocked(meta *mediaMeta) {
	for _, path := range []string{ms.blobPath(meta.To, meta.ID), ms.metaPath(meta.To, meta.ID)} {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			log.Printf("[MEDIA] Failed to remove file %s: %v", path, err)
		}
	}
}

func (ms *MediaStore) listForPeer(peerId string) []*mediaMeta {
	ms.mu.RLock()
	defer ms.mu.RUnlock()

	ids := ms.byPeer[peerId]
	result := make([]*mediaMeta, 0, len(ids))
	for _, id := range ids {
		if meta, ok := ms.index[id]; ok {
			result = append(result, meta)
		}
	}
	return result
}

func (ms *MediaStore) blobPath(to, id string) string {
	return filepath.Join(ms.dataDir, to, id+".enc")
}

func (ms *MediaStore) metaPath(to, id string) string {
	return ms.blobPath(to, id) + ".json"
}

func (ms *MediaStore) stagingBlobPath(to, id string) string {
	return fmt.Sprintf("%s.%d.tmp", ms.blobPath(to, id), time.Now().UnixNano())
}

func (ms *MediaStore) writeMetaAtomic(meta *mediaMeta) error {
	path := ms.metaPath(meta.To, meta.ID)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return fmt.Errorf("create metadata dir: %w", err)
	}
	data, err := json.Marshal(meta)
	if err != nil {
		return fmt.Errorf("marshal metadata: %w", err)
	}
	tmpPath := fmt.Sprintf("%s.%d.tmp", path, time.Now().UnixNano())
	f, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("create metadata temp: %w", err)
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		os.Remove(tmpPath)
		return fmt.Errorf("write metadata temp: %w", err)
	}
	if err := f.Sync(); err != nil {
		f.Close()
		os.Remove(tmpPath)
		return fmt.Errorf("sync metadata temp: %w", err)
	}
	if err := f.Close(); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("close metadata temp: %w", err)
	}
	if err := os.Rename(tmpPath, path); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("commit metadata: %w", err)
	}
	return nil
}

func (ms *MediaStore) loadMetadata() {
	if err := filepath.Walk(ms.dataDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info == nil || info.IsDir() || filepath.Ext(path) != ".json" {
			return nil
		}
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			log.Printf("[MEDIA] Ignoring unreadable metadata sidecar %s: %v", path, readErr)
			return nil
		}
		var meta mediaMeta
		if err := json.Unmarshal(data, &meta); err != nil {
			log.Printf("[MEDIA] Ignoring corrupt metadata sidecar %s: %v", path, err)
			return nil
		}
		if meta.ID == "" || meta.To == "" {
			log.Printf("[MEDIA] Ignoring incomplete metadata sidecar %s", path)
			return nil
		}
		if _, err := os.Stat(ms.blobPath(meta.To, meta.ID)); err != nil {
			log.Printf("[MEDIA] Ignoring metadata sidecar %s without blob: %v", path, err)
			return nil
		}
		ms.index[meta.ID] = &meta
		ms.byPeer[meta.To] = append(ms.byPeer[meta.To], meta.ID)
		return nil
	}); err != nil {
		log.Printf("[MEDIA] Warning: could not load metadata sidecars from %s: %v", ms.dataDir, err)
	}
	for peerID, ids := range ms.byPeer {
		sort.Slice(ids, func(i, j int) bool {
			mi, mj := ms.index[ids[i]], ms.index[ids[j]]
			if mi == nil || mj == nil {
				return false
			}
			return mi.CreatedAt < mj.CreatedAt
		})
		ms.byPeer[peerID] = ids
	}
}

// --- Request/response types ---

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
	Status string       `json:"status"`
	Error  string       `json:"error,omitempty"`
	ID     string       `json:"id,omitempty"`
	Mime   string       `json:"mime,omitempty"`
	Size   int64        `json:"size,omitempty"`
	Blobs  []*mediaMeta `json:"blobs,omitempty"`
}

// --- Stream handler ---

func HandleMediaStream(s network.Stream, media *MediaStore, profile *ProfileStore) {
	start := time.Now()
	activeStreams.WithLabelValues("media").Inc()
	streamResult := "ok"
	defer func() {
		activeStreams.WithLabelValues("media").Dec()
		streamDuration.WithLabelValues("media", streamResult).Observe(time.Since(start).Seconds())
		log.Printf("[MEDIA] stream handled in %s", time.Since(start))
	}()
	defer s.Close()

	remotePeer := s.Conn().RemotePeer().String()
	log.Printf("[MEDIA] Incoming stream from %s", remotePeer[:min(20, len(remotePeer))])

	requestBytes, err := readFrame(s)
	if err != nil {
		streamResult = "error"
		streamErrorsCounter.WithLabelValues("media", "read").Inc()
		log.Printf("[MEDIA] Read error from %s: %v", remotePeer[:min(20, len(remotePeer))], err)
		return
	}

	var req mediaRequest
	if err := json.Unmarshal(requestBytes, &req); err != nil {
		streamResult = "error"
		streamErrorsCounter.WithLabelValues("media", "decode").Inc()
		log.Printf("[MEDIA] JSON decode error: %v", err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "invalid JSON"})
		return
	}

	log.Printf("[MEDIA] action=%s from %s", req.Action, remotePeer[:min(20, len(remotePeer))])

	switch req.Action {
	case "upload":
		handleMediaUpload(s, media, remotePeer, &req)
	case "download":
		handleMediaDownload(s, media, remotePeer, &req)
	case "delete":
		handleMediaDelete(s, media, remotePeer, &req)
	case "list":
		handleMediaList(s, media, remotePeer)
	case "profile_upload":
		handleProfileUpload(s, profile, remotePeer, &req)
	case "profile_download":
		handleProfileDownload(s, profile, &req)
	case "profile_delete":
		handleProfileDelete(s, profile, remotePeer)
	default:
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: fmt.Sprintf("unknown action: %s", req.Action)})
	}

	log.Printf("[MEDIA] Stream closed for %s", remotePeer[:min(20, len(remotePeer))])
}

func handleMediaUpload(s network.Stream, media *MediaStore, remotePeer string, req *mediaRequest) {
	if req.ID == "" || req.To == "" || req.Size <= 0 {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "missing required fields: id, to, size"})
		return
	}
	if req.Size > maxMediaSize {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: fmt.Sprintf("size %d exceeds max %d", req.Size, maxMediaSize)})
		return
	}

	// Ensure recipient directory exists
	dir := filepath.Join(media.dataDir, req.To)
	if err := os.MkdirAll(dir, 0755); err != nil {
		log.Printf("[MEDIA] Failed to create dir %s: %v", dir, err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "server storage error"})
		return
	}

	// Signal client we're ready for data
	writeMediaResponse(s, mediaResponse{Status: "READY"})

	path := media.blobPath(req.To, req.ID)
	tmpPath := media.stagingBlobPath(req.To, req.ID)
	f, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		log.Printf("[MEDIA] Failed to create file %s: %v", tmpPath, err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "server storage error"})
		return
	}

	written, err := io.CopyN(f, s, req.Size)
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}

	if err != nil || written != req.Size {
		os.Remove(tmpPath)
		log.Printf("[MEDIA] Upload incomplete for %s: wrote %d/%d, err=%v", req.ID, written, req.Size, err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "upload incomplete"})
		return
	}

	if err := os.Rename(tmpPath, path); err != nil {
		os.Remove(tmpPath)
		log.Printf("[MEDIA] Failed to commit upload %s: %v", req.ID, err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "server storage error"})
		return
	}

	meta := &mediaMeta{
		ID:           req.ID,
		To:           req.To,
		Mime:         req.Mime,
		Size:         req.Size,
		CreatedAt:    time.Now().UnixMilli(),
		AllowedPeers: req.AllowedPeers,
	}
	if _, err := media.store(meta); err != nil {
		log.Printf("[MEDIA] Failed to persist metadata for %s: %v", req.ID, err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "server storage error"})
		return
	}
	mediaUploadedCounter.Inc()
	mediaUploadedBytesCounter.Add(float64(written))
	if biz != nil {
		biz.RecordMediaUploaded()
	}

	writeMediaResponse(s, mediaResponse{Status: "OK", ID: req.ID})
	log.Printf("[MEDIA] Uploaded blob %s (%d bytes) from %s to %s",
		req.ID, req.Size, remotePeer[:min(20, len(remotePeer))], req.To[:min(20, len(req.To))])
}

func handleMediaDownload(s network.Stream, media *MediaStore, remotePeer string, req *mediaRequest) {
	if req.ID == "" {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "missing required field: id"})
		return
	}

	meta := media.lookup(req.ID)
	if meta == nil {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "not found"})
		return
	}

	// Authorization check: group mode (AllowedPeers) vs 1:1 mode (To)
	isGroupMode := len(meta.AllowedPeers) > 0
	if isGroupMode {
		if !containsPeer(meta.AllowedPeers, remotePeer) {
			writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "not authorized"})
			return
		}
	} else {
		if meta.To != remotePeer {
			writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "not authorized"})
			return
		}
	}

	// Send metadata response first
	writeMediaResponse(s, mediaResponse{
		Status: "OK",
		ID:     meta.ID,
		Mime:   meta.Mime,
		Size:   meta.Size,
	})

	// Stream file data
	path := media.blobPath(meta.To, meta.ID)
	f, err := os.Open(path)
	if err != nil {
		log.Printf("[MEDIA] Failed to open file %s: %v", path, err)
		return
	}
	defer f.Close()

	written, err := io.Copy(s, f)
	if err != nil {
		log.Printf("[MEDIA] Download stream error for %s: %v", req.ID, err)
		return
	}
	mediaDownloadedCounter.Inc()
	mediaDownloadedBytesCounter.Add(float64(written))
	log.Printf("[MEDIA] Downloaded blob %s (%d bytes) to %s", req.ID, written, remotePeer[:min(20, len(remotePeer))])

	// Deletion is acknowledgement-based: a completed download stream is not
	// proof of receipt, so the receiver issues an explicit delete after its
	// durable commit (INV-1). Receivers that never ack are bounded by the
	// TTL sweep and per-peer caps.
}

func handleMediaDelete(s network.Stream, media *MediaStore, remotePeer string, req *mediaRequest) {
	if req.ID == "" {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "missing required field: id"})
		return
	}

	meta := media.lookup(req.ID)
	if meta == nil {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "not found"})
		return
	}

	if len(meta.AllowedPeers) > 0 {
		if !containsPeer(meta.AllowedPeers, remotePeer) {
			writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "not authorized"})
			return
		}
	} else {
		if meta.To != remotePeer {
			writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "not authorized"})
			return
		}
	}

	mediaDeletedCounter.WithLabelValues("explicit").Inc()
	mediaDeletedBytesCounter.WithLabelValues("explicit").Add(float64(meta.Size))
	media.remove(req.ID)
	writeMediaResponse(s, mediaResponse{Status: "OK"})
	log.Printf("[MEDIA] Deleted blob %s for %s", req.ID, remotePeer[:min(20, len(remotePeer))])
}

func handleMediaList(s network.Stream, media *MediaStore, remotePeer string) {
	blobs := media.listForPeer(remotePeer)
	writeMediaResponse(s, mediaResponse{Status: "OK", Blobs: blobs})
	log.Printf("[MEDIA] Listed %d blob(s) for %s", len(blobs), remotePeer[:min(20, len(remotePeer))])
}

func containsPeer(peers []string, target string) bool {
	for _, p := range peers {
		if p == target {
			return true
		}
	}
	return false
}

func writeMediaResponse(s network.Stream, resp mediaResponse) {
	data, err := json.Marshal(resp)
	if err != nil {
		streamErrorsCounter.WithLabelValues("media", "write").Inc()
		log.Printf("[MEDIA] JSON encode error: %v", err)
		return
	}
	if err := writeFrame(s, data); err != nil {
		streamErrorsCounter.WithLabelValues("media", "write").Inc()
		log.Printf("[MEDIA] Write error: %v", err)
	}
}
