//go:build integration

package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"testing"
	"time"
)

const (
	mediaCustodyProcessHelperMode = "MKNOON_MEDIA_CUSTODY_PROCESS_HELPER"
	mediaCustodyProcessRoot       = "MKNOON_MEDIA_CUSTODY_PROCESS_ROOT"
	mediaCustodyProcessNowEnv     = "MKNOON_MEDIA_CUSTODY_PROCESS_NOW_MS"
	mediaCustodyProcessRecipient  = "12D3KooWA4WHZmYAWGCJbRwU41DwZLtCpoUW6NMWRcmWzEzbnuye"
)

var mediaCustodyProcessBody = []byte("committed ciphertext survives a real relay process handoff")

// TC-346-04: two independently initialized test-binary processes sequentially
// own the same real directory. The second process must reconstruct the exact
// proof and bytes from the final marker, then durably ACK them. This does not
// exercise or authorize concurrent writers on one volume.
func TestDirectMediaBlobCustodySurvivesRelayProcessHandoff(t *testing.T) {
	if mode := os.Getenv(mediaCustodyProcessHelperMode); mode != "" {
		runMediaCustodyProcessHelper(t, mode, os.Getenv(mediaCustodyProcessRoot))
		return
	}

	root := t.TempDir()
	processNow := time.Now().UTC().Truncate(time.Millisecond)
	for _, mode := range []string{"store", "reopen-download-ack"} {
		cmd := exec.Command(os.Args[0], "-test.run=^TestDirectMediaBlobCustodySurvivesRelayProcessHandoff$", "-test.v")
		cmd.Env = append(os.Environ(),
			mediaCustodyProcessHelperMode+"="+mode,
			mediaCustodyProcessRoot+"="+root,
			mediaCustodyProcessNowEnv+"="+strconv.FormatInt(processNow.UnixMilli(), 10),
		)
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("helper process %q failed: %v\n%s", mode, err, output)
		}
	}

	reopened, err := NewMediaStore(root)
	if err != nil {
		t.Fatalf("final reopen: %v", err)
	}
	reopened.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return processNow })
	meta := reopened.custody.entries[custodyKeyOf(mediaCustodyProcessRecipient, "process-handoff")]
	if meta == nil || meta.State != mediaCustodyStateAcked {
		t.Fatalf("final reconstructed state = %#v, want ACK tombstone", meta)
	}
	blobPath, err := reopened.custody.blobPath(meta)
	if err != nil {
		t.Fatalf("resolve final blob path: %v", err)
	}
	if _, err := os.Stat(blobPath); !os.IsNotExist(err) {
		t.Fatalf("ACKed blob still exists after process handoff: %v", err)
	}
	markerPath, err := reopened.custody.markerPath(meta)
	if err != nil {
		t.Fatalf("resolve final marker path: %v", err)
	}
	if _, err := os.Stat(markerPath); err != nil {
		t.Fatalf("durable ACK tombstone missing after process handoff: %v", err)
	}
	if filepath.Dir(markerPath) == root {
		t.Fatalf("protected marker escaped isolated subtree: %s", markerPath)
	}
}

func runMediaCustodyProcessHelper(t *testing.T, mode, root string) {
	t.Helper()
	if root == "" {
		t.Fatal("helper process root is empty")
	}
	store, err := NewMediaStore(root)
	if err != nil {
		t.Fatalf("helper %s reopen: %v", mode, err)
	}
	processNow := mediaCustodyProcessTime(t)
	store.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return processNow })
	req := mediaCustodyProcessRequest(processNow, mode != "store")

	switch mode {
	case "store":
		store.SetDirectMediaBlobCustodyAdmissionEnabled(true)
		prepared, failure := store.custody.prepareUpload(&req)
		if failure != nil || prepared == nil || prepared.reservation == nil {
			t.Fatalf("prepare process upload = (%#v, %v)", prepared, failure)
		}
		meta, failure := store.custody.commitUpload(prepared.reservation, bytes.NewReader(mediaCustodyProcessBody))
		if failure != nil || meta == nil || meta.State != mediaCustodyStatePending {
			t.Fatalf("commit process upload = (%#v, %v)", meta, failure)
		}
		if want := processNow.Add(mediaTTL).UnixMilli(); meta.ExpiresAtMs != want {
			t.Fatalf("committed expiry = %d, want %d", meta.ExpiresAtMs, want)
		}
	case "reopen-download-ack":
		if store.DirectMediaBlobCustodyAdmissionEnabled() {
			t.Fatal("reopen unexpectedly enabled admission")
		}
		for attempt := 0; attempt < 2; attempt++ {
			meta, file, failure := store.custody.openDownload(&req, req.To)
			if failure != nil || meta == nil || file == nil {
				t.Fatalf("reopened download %d = (%#v, %v, %v)", attempt, meta, file, failure)
			}
			got, readErr := io.ReadAll(file)
			closeErr := file.Close()
			if readErr != nil || closeErr != nil || !bytes.Equal(got, mediaCustodyProcessBody) {
				t.Fatalf("reopened download %d bytes = %q, read=%v close=%v", attempt, got, readErr, closeErr)
			}
		}
		meta, ackStatus, failure := store.custody.ack(&req, req.To)
		if failure != nil || meta == nil || ackStatus != mediaCustodyAckAcked {
			t.Fatalf("first reopened ACK = (%#v, %q, %v)", meta, ackStatus, failure)
		}
		meta, ackStatus, failure = store.custody.ack(&req, req.To)
		if failure != nil || meta == nil || ackStatus != mediaCustodyAckAlreadyAcked {
			t.Fatalf("repeated reopened ACK = (%#v, %q, %v)", meta, ackStatus, failure)
		}
	default:
		t.Fatalf("unknown helper mode %q", mode)
	}
}

func mediaCustodyProcessRequest(processNow time.Time, exact bool) mediaRequest {
	sum := sha256.Sum256(mediaCustodyProcessBody)
	req := mediaRequest{
		Action:          mediaCustodyUploadAction,
		ID:              "process-handoff",
		To:              mediaCustodyProcessRecipient,
		Size:            int64(len(mediaCustodyProcessBody)),
		Mime:            "application/octet-stream",
		ContentHash:     hex.EncodeToString(sum[:]),
		CustodyKind:     directMediaBlobCustodyKind,
		CustodyContract: directMediaBlobCustodyContract,
	}
	if exact {
		req.ExpiresAtMs = processNow.Add(mediaTTL).UnixMilli()
	}
	return req
}

func mediaCustodyProcessTime(t *testing.T) time.Time {
	t.Helper()
	raw := os.Getenv(mediaCustodyProcessNowEnv)
	millis, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || millis <= 0 {
		t.Fatalf("invalid %s=%q: %v", mediaCustodyProcessNowEnv, raw, err)
	}
	return time.UnixMilli(millis)
}
