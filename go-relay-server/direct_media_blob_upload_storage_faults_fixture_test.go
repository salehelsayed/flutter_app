package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

const directMediaFixtureUploadStorageMarker = "mknoon-owned-upload-storage-blocker-v1"

// Only an explicit fault on this fixture's own temporary media path can enter
// here. Native handlers then meet a real filesystem error, without app/SQL
// status injection or a production relay behavior switch.
func (faults *directMediaFixtureFaults) uploadStorageQuiescentLocked() bool {
	if len(faults.media.legacyReservations) != 0 {
		return false
	}
	if cs := faults.media.custody; cs != nil {
		cs.mu.Lock()
		busy := len(cs.reservations) != 0
		cs.mu.Unlock()
		if busy {
			return false
		}
	}
	return true
}

func (faults *directMediaFixtureFaults) blockUploadStorage() error {
	faults.media.laneMu.Lock()
	defer faults.media.laneMu.Unlock()
	if !faults.uploadStorageQuiescentLocked() {
		return errors.New("active upload reservations; fault not armed")
	}
	faults.mu.Lock()
	defer faults.mu.Unlock()
	if faults.uploadStash != "" {
		return errors.New("upload storage already blocked")
	}
	root := faults.media.dataDir
	if !filepath.IsAbs(root) || filepath.Clean(root) != root {
		return errors.New("fixture media path is not canonical")
	}
	info, err := os.Lstat(root)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return errors.New("fixture media path is not an owned real directory")
	}
	stash, err := os.MkdirTemp(filepath.Dir(root), ".mknoon-upload-storage-")
	if err != nil {
		return fmt.Errorf("create owned upload stash: %w", err)
	}
	saved := filepath.Join(stash, "media")
	if err := os.Rename(root, saved); err != nil {
		_ = os.Remove(stash)
		return fmt.Errorf("stash owned upload storage: %w", err)
	}
	faults.uploadStash = stash
	// O_EXCL preserves an unexpected replacement instead of overwriting it.
	file, err := os.OpenFile(root, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		// A conflicting path is preserved. Only a still-vacant original path
		// permits rolling the original directory back into place.
		var rollback error
		if _, inspectErr := os.Lstat(root); os.IsNotExist(inspectErr) {
			rollback = os.Rename(saved, root)
			if rollback == nil {
				faults.uploadStash = ""
				_ = os.Remove(stash)
			}
		} else {
			rollback = errors.New("original path no longer vacant; saved directory retained")
		}
		return errors.Join(fmt.Errorf("create owned upload blocker: %w", err), rollback)
	}
	markerInfo, statErr := file.Stat()
	_, writeErr := file.Write([]byte(directMediaFixtureUploadStorageMarker))
	closeErr := file.Close()
	faults.uploadMarker = markerInfo
	if err := errors.Join(statErr, writeErr, closeErr); err != nil {
		// Retain ownership/evidence for teardown. Never remove an unverified
		// replacement or recursively delete the saved original directory.
		return fmt.Errorf("write owned upload blocker: %w", err)
	}
	return nil
}

func (faults *directMediaFixtureFaults) restoreUploadStorage() error {
	faults.media.laneMu.Lock()
	defer faults.media.laneMu.Unlock()
	// Default fixture teardown is unchanged when this explicit fault was
	// never armed. Do not take the custody lock while holding faults.mu.
	faults.mu.Lock()
	armed := faults.uploadStash != ""
	faults.mu.Unlock()
	if !armed {
		return nil
	}
	if !faults.uploadStorageQuiescentLocked() {
		return errors.New("active upload reservations; storage not restored")
	}
	faults.mu.Lock()
	defer faults.mu.Unlock()
	if faults.uploadStash == "" {
		return nil
	}
	root := faults.media.dataDir
	saved := filepath.Join(faults.uploadStash, "media")
	original, err := os.Lstat(saved)
	if err != nil || !original.IsDir() || original.Mode()&os.ModeSymlink != 0 {
		return errors.New("saved owned media directory unavailable")
	}
	marker, err := os.Lstat(root)
	if err == nil {
		if !marker.Mode().IsRegular() || faults.uploadMarker == nil || !os.SameFile(marker, faults.uploadMarker) {
			return errors.New("upload blocker was replaced; preserve current path")
		}
		body, readErr := os.ReadFile(root)
		if readErr != nil || !bytes.Equal(body, []byte(directMediaFixtureUploadStorageMarker)) {
			return errors.New("upload blocker contents changed; preserve current path")
		}
		if err := os.Remove(root); err != nil {
			return fmt.Errorf("remove owned upload blocker: %w", err)
		}
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("inspect owned upload blocker: %w", err)
	}
	if err := os.Rename(saved, root); err != nil {
		return fmt.Errorf("restore original owned media directory: %w", err)
	}
	stash := faults.uploadStash
	faults.uploadStash = ""
	faults.uploadMarker = nil
	return os.Remove(stash)
}
