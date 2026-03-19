package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
)

const (
	maxProfileSize = 512 * 1024 // 512 KB
	profileDataDir = "/data/profiles"
)

// --- Profile metadata ---

type profileMeta struct {
	Owner     string `json:"owner"`
	Mime      string `json:"mime"`
	Size      int64  `json:"size"`
	UpdatedAt int64  `json:"updated_at"`
}

// --- Profile store ---

type ProfileStore struct {
	mu      sync.RWMutex
	index   map[string]*profileMeta // ownerPeerId → meta
	dataDir string
}

func NewProfileStore(dataDir string) *ProfileStore {
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Printf("[PROFILE] Warning: could not create data dir %s: %v", dataDir, err)
	}
	ps := &ProfileStore{
		index:   make(map[string]*profileMeta),
		dataDir: dataDir,
	}
	ps.loadExisting()
	return ps
}

// loadExisting scans the data directory for existing profile files
// and populates the in-memory index so relay_profile_count is
// accurate immediately after startup.
func (ps *ProfileStore) loadExisting() {
	entries, err := os.ReadDir(ps.dataDir)
	if err != nil {
		log.Printf("[PROFILE] Could not scan existing profiles: %v", err)
		return
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !strings.HasSuffix(name, ".blob") {
			continue
		}
		ownerPeerId := strings.TrimSuffix(name, ".blob")
		info, err := entry.Info()
		if err != nil {
			continue
		}
		if info.Size() == 0 {
			continue // tombstone from deleted profile
		}
		ps.index[ownerPeerId] = &profileMeta{
			Owner:     ownerPeerId,
			Size:      info.Size(),
			UpdatedAt: info.ModTime().UnixMilli(),
		}
	}
	if len(ps.index) > 0 {
		log.Printf("[PROFILE] Loaded %d existing profile(s) from disk", len(ps.index))
	}
}

func (ps *ProfileStore) store(meta *profileMeta) {
	ps.mu.Lock()
	defer ps.mu.Unlock()
	ps.index[meta.Owner] = meta
}

func (ps *ProfileStore) lookup(ownerPeerId string) *profileMeta {
	ps.mu.RLock()
	defer ps.mu.RUnlock()
	return ps.index[ownerPeerId]
}

func (ps *ProfileStore) remove(ownerPeerId string) {
	ps.mu.Lock()
	defer ps.mu.Unlock()

	if _, ok := ps.index[ownerPeerId]; !ok {
		return
	}

	path := ps.blobPath(ownerPeerId)
	// Truncate to zero bytes instead of deleting — leaves a tombstone
	// so re-uploads are not miscounted as new signups.
	if err := os.Truncate(path, 0); err != nil && !os.IsNotExist(err) {
		log.Printf("[PROFILE] Failed to truncate file %s: %v", path, err)
	}

	delete(ps.index, ownerPeerId)
}

func (ps *ProfileStore) blobPath(ownerPeerId string) string {
	return filepath.Join(ps.dataDir, ownerPeerId+".blob")
}

func (ps *ProfileStore) Stats() (count int, diskMB int64) {
	ps.mu.RLock()
	count = len(ps.index)
	ps.mu.RUnlock()

	var totalBytes int64
	filepath.Walk(ps.dataDir, func(_ string, info os.FileInfo, err error) error {
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

// --- Handler functions ---

func handleProfileUpload(s network.Stream, profile *ProfileStore, remotePeer string, req *mediaRequest) {
	if req.Size <= 0 {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "missing required field: size"})
		return
	}
	if req.Size > maxProfileSize {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: fmt.Sprintf("size %d exceeds max %d", req.Size, maxProfileSize)})
		return
	}

	// Signal client we're ready for data
	writeMediaResponse(s, mediaResponse{Status: "READY"})

	// Check if profile already exists — detect new signups
	path := profile.blobPath(remotePeer)
	isNewProfile := false
	if _, err := os.Stat(path); os.IsNotExist(err) {
		isNewProfile = true
	}

	// Create file and stream data
	f, err := os.Create(path)
	if err != nil {
		log.Printf("[PROFILE] Failed to create file %s: %v", path, err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "server storage error"})
		return
	}

	written, err := io.CopyN(f, s, req.Size)
	f.Close()

	if err != nil || written != req.Size {
		os.Remove(path)
		log.Printf("[PROFILE] Upload incomplete for %s: wrote %d/%d, err=%v", remotePeer[:min(20, len(remotePeer))], written, req.Size, err)
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "upload incomplete"})
		return
	}

	meta := &profileMeta{
		Owner:     remotePeer,
		Mime:      req.Mime,
		Size:      req.Size,
		UpdatedAt: time.Now().UnixMilli(),
	}
	profile.store(meta)
	profileUploadedCounter.Inc()
	if isNewProfile {
		newSignupsCounter.Inc()
	}

	writeMediaResponse(s, mediaResponse{Status: "OK"})
	log.Printf("[PROFILE] Uploaded profile for %s (%d bytes, %s)",
		remotePeer[:min(20, len(remotePeer))], req.Size, req.Mime)
}

func handleProfileDownload(s network.Stream, profile *ProfileStore, req *mediaRequest) {
	if req.Owner == "" {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "missing required field: owner"})
		return
	}

	meta := profile.lookup(req.Owner)
	if meta == nil {
		writeMediaResponse(s, mediaResponse{Status: "ERROR", Error: "not found"})
		return
	}

	// Send metadata response first
	writeMediaResponse(s, mediaResponse{
		Status: "OK",
		Mime:   meta.Mime,
		Size:   meta.Size,
	})

	// Stream file data
	path := profile.blobPath(meta.Owner)
	f, err := os.Open(path)
	if err != nil {
		log.Printf("[PROFILE] Failed to open file %s: %v", path, err)
		return
	}
	defer f.Close()

	written, err := io.Copy(s, f)
	if err != nil {
		log.Printf("[PROFILE] Download stream error for %s: %v", req.Owner[:min(20, len(req.Owner))], err)
		return
	}
	profileDownloadedCounter.Inc()
	log.Printf("[PROFILE] Downloaded profile for %s (%d bytes)", req.Owner[:min(20, len(req.Owner))], written)
}

func handleProfileDelete(s network.Stream, profile *ProfileStore, remotePeer string) {
	profile.remove(remotePeer)
	profileDeletedCounter.Inc()
	writeMediaResponse(s, mediaResponse{Status: "OK"})
	log.Printf("[PROFILE] Deleted profile for %s", remotePeer[:min(20, len(remotePeer))])
}
