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
	maxMediaSize         = 100 * 1024 * 1024 // 100 MB
	maxMediaPerPeer      = 50
	mediaTTL             = 7 * 24 * time.Hour
	mediaCleanupInterval = 10 * time.Minute
	mediaDataDir         = "/data/media"
)

// --- Media metadata ---

type mediaMeta struct {
	ID           string   `json:"id"`
	From         string   `json:"from"`
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
	return &MediaStore{
		index:   make(map[string]*mediaMeta),
		byPeer:  make(map[string][]string),
		dataDir: dataDir,
	}
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

func (ms *MediaStore) store(meta *mediaMeta) {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	ms.index[meta.ID] = meta
	ms.byPeer[meta.To] = append(ms.byPeer[meta.To], meta.ID)

	// Prune oldest if over limit
	ids := ms.byPeer[meta.To]
	if len(ids) > maxMediaPerPeer {
		// Sort by creation time so we remove the oldest
		sort.Slice(ids, func(i, j int) bool {
			mi, mj := ms.index[ids[i]], ms.index[ids[j]]
			if mi == nil || mj == nil {
				return false
			}
			return mi.CreatedAt < mj.CreatedAt
		})
		// Remove oldest entries beyond the limit
		toRemove := ids[:len(ids)-maxMediaPerPeer]
		for _, id := range toRemove {
			if m := ms.index[id]; m != nil {
				mediaDeletedCounter.WithLabelValues("peer_cap").Inc()
				mediaDeletedBytesCounter.WithLabelValues("peer_cap").Add(float64(m.Size))
			}
			ms.removeLocked(id)
		}
		log.Printf("[MEDIA] Pruned %d blob(s) for peer %s", len(toRemove), meta.To[:min(20, len(meta.To))])
	}
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

	// Remove from byPeer
	ids := ms.byPeer[meta.To]
	for i, bid := range ids {
		if bid == id {
			ms.byPeer[meta.To] = append(ids[:i], ids[i+1:]...)
			break
		}
	}
	if len(ms.byPeer[meta.To]) == 0 {
		delete(ms.byPeer, meta.To)
	}

	// Remove disk file
	path := ms.blobPath(meta.To, id)
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		log.Printf("[MEDIA] Failed to remove file %s: %v", path, err)
	}

	// Remove from index
	delete(ms.index, id)
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

	// Create file and stream data
	path := media.blobPath(req.To, req.ID)
	f, err := os.Create(path)
	if err != nil {
		log.Printf("[MEDIA] Failed to create file %s: %v", path, err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "server storage error"})
		return
	}

	written, err := io.CopyN(f, s, req.Size)
	f.Close()

	if err != nil || written != req.Size {
		// Clean up partial file
		os.Remove(path)
		log.Printf("[MEDIA] Upload incomplete for %s: wrote %d/%d, err=%v", req.ID, written, req.Size, err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "upload incomplete"})
		return
	}

	meta := &mediaMeta{
		ID:           req.ID,
		From:         remotePeer,
		To:           req.To,
		Mime:         req.Mime,
		Size:         req.Size,
		CreatedAt:    time.Now().UnixMilli(),
		AllowedPeers: req.AllowedPeers,
	}
	media.store(meta)
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

	// Auto-delete after download — but NOT for group blobs (other members still need it)
	if !isGroupMode {
		mediaDeletedCounter.WithLabelValues("auto_download").Inc()
		mediaDeletedBytesCounter.WithLabelValues("auto_download").Add(float64(meta.Size))
		media.remove(req.ID)
		log.Printf("[MEDIA] Auto-deleted blob %s after download", req.ID)
	}
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
