package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// directMediaFixtureFaults is the H2 run-owned fault control for the disposable
// Plan 347 device fixture. It only touches the fixture's own temporary media
// store (legacy lane and custody lane), so a device run can meet real relay
// states without a seven-day wait, a phone clock change, or any production
// relay behaviour change.
type directMediaFixtureFaults struct {
	media *MediaStore

	mu          sync.Mutex
	clockOffset time.Duration
	stash       map[directMediaBlobCustodyKey]directMediaFixtureStash
}

type directMediaFixtureStash struct {
	lane    string
	custody *directMediaBlobCustodyMeta
	legacy  *mediaMeta
	blob    []byte
	marker  []byte
}

const (
	directMediaFixtureLaneLegacy  = "legacy"
	directMediaFixtureLaneCustody = "custody"
)

type directMediaFixtureFault struct {
	Op              string `json:"op"`
	RecipientPeerID string `json:"recipientPeerId,omitempty"`
	AttachmentID    string `json:"attachmentId,omitempty"`
	Lane            string `json:"lane,omitempty"`
}

type directMediaFixtureFaultStatus struct {
	Present     bool   `json:"present"`
	Lane        string `json:"lane,omitempty"`
	State       string `json:"state,omitempty"`
	HashMatches bool   `json:"hashMatches"`
	Snapshotted bool   `json:"snapshotted"`
	ClockOffset string `json:"clockOffset"`
}

func newDirectMediaFixtureFaults(media *MediaStore) *directMediaFixtureFaults {
	faults := &directMediaFixtureFaults{
		media: media,
		stash: map[directMediaBlobCustodyKey]directMediaFixtureStash{},
	}
	media.SetDirectMediaBlobCustodyNowForTest(func() time.Time {
		faults.mu.Lock()
		offset := faults.clockOffset
		faults.mu.Unlock()
		return time.Now().Add(offset)
	})
	return faults
}

func (faults *directMediaFixtureFaults) apply(fault directMediaFixtureFault) error {
	switch fault.Op {
	case "clock_reset":
		faults.setClockOffset(0)
		return nil
	case "expire":
		if fault.RecipientPeerID == "" && fault.AttachmentID == "" {
			faults.setClockOffset(mediaTTL + time.Minute)
			return nil
		}
	case "snapshot", "remove", "restore", "corrupt":
	default:
		return fmt.Errorf("unknown fault op %q", fault.Op)
	}
	if !validDirectMediaFixtureProbeID(fault.RecipientPeerID) ||
		!validDirectMediaFixtureProbeID(fault.AttachmentID) ||
		!validLegacyMediaSegment(fault.RecipientPeerID) ||
		!validLegacyMediaSegment(fault.AttachmentID) {
		return errors.New("fault target rejected")
	}
	key := custodyKeyOf(fault.RecipientPeerID, fault.AttachmentID)
	lane := faults.laneOf(key)
	if fault.Op == "restore" {
		faults.mu.Lock()
		saved, ok := faults.stash[key]
		faults.mu.Unlock()
		if !ok {
			return errors.New("nothing snapshotted for this target")
		}
		if lane != "" {
			return errors.New("target still present")
		}
		lane = saved.lane
	}
	switch lane {
	case directMediaFixtureLaneCustody:
		if fault.Op == "expire" {
			// The custody store reads expiry from its clock seam, so expiry is
			// the real normalize-on-access path, for every custody entry.
			faults.setClockOffset(mediaTTL + time.Minute)
			return nil
		}
		return faults.applyCustody(fault.Op, key)
	case directMediaFixtureLaneLegacy:
		return faults.applyLegacy(fault.Op, key)
	default:
		return errors.New("no pending blob for this target")
	}
}

func (faults *directMediaFixtureFaults) setClockOffset(offset time.Duration) {
	faults.mu.Lock()
	faults.clockOffset = offset
	faults.mu.Unlock()
}

func (faults *directMediaFixtureFaults) laneOf(key directMediaBlobCustodyKey) string {
	if cs := faults.media.custody; cs != nil {
		cs.mu.Lock()
		meta := cs.entries[key]
		cs.mu.Unlock()
		if meta != nil && meta.State == mediaCustodyStatePending {
			return directMediaFixtureLaneCustody
		}
	}
	if meta := faults.media.lookup(key.id); meta != nil && meta.To == key.recipient {
		return directMediaFixtureLaneLegacy
	}
	return ""
}

func (faults *directMediaFixtureFaults) applyCustody(op string, key directMediaBlobCustodyKey) error {
	cs := faults.media.custody
	cs.owner.laneMu.Lock()
	defer cs.owner.laneMu.Unlock()
	cs.mu.Lock()
	defer cs.mu.Unlock()
	faults.mu.Lock()
	defer faults.mu.Unlock()

	meta := cs.entries[key]
	switch op {
	case "snapshot":
		if meta == nil || meta.State != mediaCustodyStatePending {
			return errors.New("no pending custody entry to snapshot")
		}
		blobPath, _ := cs.blobPath(meta)
		markerPath, _ := cs.markerPath(meta)
		blob, err := os.ReadFile(blobPath)
		if err != nil {
			return err
		}
		marker, err := os.ReadFile(markerPath)
		if err != nil {
			return err
		}
		faults.stash[key] = directMediaFixtureStash{
			lane:    directMediaFixtureLaneCustody,
			custody: cloneDirectMediaBlobCustodyMeta(meta),
			blob:    blob,
			marker:  marker,
		}
		return nil
	case "remove":
		if meta == nil || meta.State != mediaCustodyStatePending {
			return errors.New("no pending custody entry to remove")
		}
		// The same artifact removal and index drop the TTL sweep performs, so
		// the recipient meets the sweep's exact not-found end state.
		if err := cs.removeExpiredArtifactsLocked(meta, true); err != nil {
			return err
		}
		delete(cs.entries, key)
		cs.refreshGaugesLocked()
		return nil
	case "restore":
		saved := faults.stash[key]
		if meta != nil {
			return errors.New("custody entry still present")
		}
		blobPath, _ := cs.blobPath(saved.custody)
		markerPath, _ := cs.markerPath(saved.custody)
		if err := os.WriteFile(blobPath, saved.blob, 0o600); err != nil {
			return err
		}
		if err := os.WriteFile(markerPath, saved.marker, 0o600); err != nil {
			return err
		}
		cs.entries[key] = cloneDirectMediaBlobCustodyMeta(saved.custody)
		cs.refreshGaugesLocked()
		return nil
	case "corrupt":
		if meta == nil || meta.State != mediaCustodyStatePending {
			return errors.New("no pending custody blob to corrupt")
		}
		blobPath, _ := cs.blobPath(meta)
		return flipMiddleByte(blobPath, meta.Size)
	}
	return nil
}

func (faults *directMediaFixtureFaults) applyLegacy(op string, key directMediaBlobCustodyKey) error {
	ms := faults.media
	switch op {
	case "snapshot":
		meta := ms.lookup(key.id)
		if meta == nil || meta.To != key.recipient {
			return errors.New("no legacy blob to snapshot")
		}
		blob, err := os.ReadFile(ms.blobPath(meta.To, meta.ID))
		if err != nil {
			return err
		}
		saved := *meta
		saved.AllowedPeers = append([]string(nil), meta.AllowedPeers...)
		faults.mu.Lock()
		faults.stash[key] = directMediaFixtureStash{lane: directMediaFixtureLaneLegacy, legacy: &saved, blob: blob}
		faults.mu.Unlock()
		return nil
	case "remove":
		// MediaStore.remove is the same index and file removal the TTL sweep
		// and explicit delete use.
		ms.remove(key.id)
		return nil
	case "restore":
		faults.mu.Lock()
		saved := faults.stash[key]
		faults.mu.Unlock()
		ms.laneMu.Lock()
		defer ms.laneMu.Unlock()
		blobPath := ms.blobPath(saved.legacy.To, saved.legacy.ID)
		if err := os.MkdirAll(filepath.Dir(blobPath), 0o700); err != nil {
			return err
		}
		if err := os.WriteFile(blobPath, saved.blob, 0o600); err != nil {
			return err
		}
		restored := *saved.legacy
		_, err := ms.store(&restored)
		return err
	case "corrupt":
		meta := ms.lookup(key.id)
		if meta == nil {
			return errors.New("no legacy blob to corrupt")
		}
		return flipMiddleByte(ms.blobPath(meta.To, meta.ID), meta.Size)
	case "expire":
		// Backdate this one entry past the TTL, then run the production sweep.
		ms.mu.Lock()
		meta := ms.index[key.id]
		if meta == nil {
			ms.mu.Unlock()
			return errors.New("no legacy blob to expire")
		}
		meta.CreatedAt = time.Now().Add(-mediaTTL - time.Minute).UnixMilli()
		err := ms.writeMetaAtomic(meta)
		ms.mu.Unlock()
		if err != nil {
			return err
		}
		ms.cleanupExpired()
		return nil
	}
	return nil
}

func flipMiddleByte(path string, size int64) error {
	if size <= 0 {
		return errors.New("empty blob")
	}
	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return err
	}
	defer file.Close()
	one := make([]byte, 1)
	if _, err := file.ReadAt(one, size/2); err != nil {
		return err
	}
	one[0] ^= 0xff
	_, err = file.WriteAt(one, size/2)
	return err
}

func (faults *directMediaFixtureFaults) status(recipientPeerID, attachmentID string) directMediaFixtureFaultStatus {
	key := custodyKeyOf(recipientPeerID, attachmentID)
	faults.mu.Lock()
	_, snapshotted := faults.stash[key]
	offset := faults.clockOffset
	faults.mu.Unlock()
	status := directMediaFixtureFaultStatus{Snapshotted: snapshotted, ClockOffset: offset.String()}
	if cs := faults.media.custody; cs != nil {
		cs.mu.Lock()
		meta := cloneDirectMediaBlobCustodyMeta(cs.entries[key])
		cs.mu.Unlock()
		if meta != nil {
			status.Present = true
			status.Lane = directMediaFixtureLaneCustody
			status.State = meta.State
			if blobPath, err := cs.blobPath(meta); err == nil {
				status.HashMatches = verifyMediaCustodyBlob(blobPath, meta.Size, meta.ContentHash) == nil
			}
			return status
		}
	}
	if meta := faults.media.lookup(attachmentID); meta != nil && meta.To == recipientPeerID {
		status.Present = true
		status.Lane = directMediaFixtureLaneLegacy
	}
	return status
}

// pending lists this run's pending blobs on both lanes, oldest first, so a
// device driver can address the blob it just sent without reading app logs.
func (faults *directMediaFixtureFaults) pending() []directMediaFixtureFault {
	type entry struct {
		target    directMediaFixtureFault
		createdAt int64
	}
	var entries []entry
	if cs := faults.media.custody; cs != nil {
		cs.mu.Lock()
		for _, meta := range cs.entries {
			if meta.State == mediaCustodyStatePending {
				entries = append(entries, entry{
					target:    directMediaFixtureFault{RecipientPeerID: meta.To, AttachmentID: meta.ID, Lane: directMediaFixtureLaneCustody},
					createdAt: meta.CreatedAtMs,
				})
			}
		}
		cs.mu.Unlock()
	}
	faults.media.mu.RLock()
	for _, meta := range faults.media.index {
		entries = append(entries, entry{
			target:    directMediaFixtureFault{RecipientPeerID: meta.To, AttachmentID: meta.ID, Lane: directMediaFixtureLaneLegacy},
			createdAt: meta.CreatedAt,
		})
	}
	faults.media.mu.RUnlock()
	sort.SliceStable(entries, func(i, j int) bool { return entries[i].createdAt < entries[j].createdAt })
	targets := make([]directMediaFixtureFault, 0, len(entries))
	for _, e := range entries {
		targets = append(targets, e.target)
	}
	return targets
}

// serve answers POST {probe}/fault with a JSON fault, GET {probe}/fault?list=pending
// with this run's pending blobs, and GET {probe}/fault?recipientPeerId=&attachmentId=
// with one target's status.
func (faults *directMediaFixtureFaults) serve(writer http.ResponseWriter, request *http.Request) {
	writer.Header().Set("Content-Type", "application/json")
	switch request.Method {
	case http.MethodPost:
		var fault directMediaFixtureFault
		decoder := json.NewDecoder(http.MaxBytesReader(writer, request.Body, 4096))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&fault); err != nil {
			http.Error(writer, "fault body rejected", http.StatusBadRequest)
			return
		}
		if err := faults.apply(fault); err != nil {
			http.Error(writer, err.Error(), http.StatusConflict)
			return
		}
		_ = json.NewEncoder(writer).Encode(map[string]any{
			"schema": "mknoon.h2.direct-media-fault.v1",
			"op":     fault.Op,
			"status": faults.status(fault.RecipientPeerID, fault.AttachmentID),
		})
	case http.MethodGet:
		query := request.URL.Query()
		if query.Get("list") == "pending" {
			_ = json.NewEncoder(writer).Encode(map[string]any{
				"schema":  "mknoon.h2.direct-media-fault.v1",
				"pending": faults.pending(),
			})
			return
		}
		_ = json.NewEncoder(writer).Encode(map[string]any{
			"schema": "mknoon.h2.direct-media-fault.v1",
			"status": faults.status(query.Get("recipientPeerId"), query.Get("attachmentId")),
		})
	default:
		http.Error(writer, "method rejected", http.StatusMethodNotAllowed)
	}
}
