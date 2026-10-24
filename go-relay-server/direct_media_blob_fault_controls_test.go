package main

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

// H2 (MEDIA-019/038): the run-owned fault controls drive the real custody
// store into the states a recipient can meet, and each state is reported by
// the production download handler exactly as a real relay would report it.
func TestDirectMediaFixtureFaultControlsDriveRealCustodyStates(t *testing.T) {
	env := setupTestEnv(t)
	env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	faults := newDirectMediaFixtureFaults(env.media)
	recipient := env.recipient.ID().String()
	body := []byte("h2 owned ciphertext for fault controls")

	upload := func(id string) mediaResponse {
		req := directMediaCustodyUploadRequest(id, recipient, "application/octet-stream", body)
		proof, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
		requireDirectMediaCustodyProof(t, proof, req, mediaCustodyStoreStored, "")
		return proof
	}
	download := func(proof mediaResponse) (mediaResponse, []byte) {
		return directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(proof, "download"))
	}

	control := upload("h2-control")
	if pending := faults.pending(); len(pending) != 1 || pending[0].AttachmentID != control.ID || pending[0].RecipientPeerID != recipient {
		t.Fatalf("pending = %#v", pending)
	}
	if resp, got := download(control); resp.Status != "OK" || !bytes.Equal(got, body) {
		t.Fatalf("positive control = %#v %q", resp, got)
	}

	removed := upload("h2-remove")
	if err := faults.apply(directMediaFixtureFault{Op: "snapshot", RecipientPeerID: recipient, AttachmentID: removed.ID}); err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	if err := faults.apply(directMediaFixtureFault{Op: "remove", RecipientPeerID: recipient, AttachmentID: removed.ID}); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if resp, _ := download(removed); resp.ErrorCode != mediaCustodyErrorNotFound {
		t.Fatalf("removed download = %#v, want not found", resp)
	}
	if status := faults.status(recipient, removed.ID); status.Present {
		t.Fatalf("removed status = %#v", status)
	}
	if err := faults.apply(directMediaFixtureFault{Op: "restore", RecipientPeerID: recipient, AttachmentID: removed.ID}); err != nil {
		t.Fatalf("restore: %v", err)
	}
	if resp, got := download(removed); resp.Status != "OK" || !bytes.Equal(got, body) {
		t.Fatalf("restored download = %#v %q", resp, got)
	}

	corrupt := upload("h2-corrupt")
	if err := faults.apply(directMediaFixtureFault{Op: "corrupt", RecipientPeerID: recipient, AttachmentID: corrupt.ID}); err != nil {
		t.Fatalf("corrupt: %v", err)
	}
	if status := faults.status(recipient, corrupt.ID); !status.Present || status.HashMatches {
		t.Fatalf("corrupt status = %#v", status)
	}
	if resp, got := download(corrupt); resp.ErrorCode != mediaCustodyErrorHashMismatch || len(got) != 0 {
		t.Fatalf("corrupt download = %#v (%d bytes), want hash mismatch and no bytes", resp, len(got))
	}

	expiring := upload("h2-expire")
	if err := faults.apply(directMediaFixtureFault{Op: "expire"}); err != nil {
		t.Fatalf("expire: %v", err)
	}
	if resp, _ := download(expiring); resp.ErrorCode != mediaCustodyErrorNotFound {
		t.Fatalf("expired download = %#v, want not found", resp)
	}
	blobPath, _ := env.media.custody.blobPath(&directMediaBlobCustodyMeta{To: recipient, ID: expiring.ID})
	if _, err := os.Stat(blobPath); !os.IsNotExist(err) {
		t.Fatalf("expired blob still on disk: %v", err)
	}
	if err := faults.apply(directMediaFixtureFault{Op: "clock_reset"}); err != nil {
		t.Fatalf("clock reset: %v", err)
	}
	after := upload("h2-after-reset")
	if resp, got := download(after); resp.Status != "OK" || !bytes.Equal(got, body) {
		t.Fatalf("post-reset control = %#v %q", resp, got)
	}

	for _, bad := range []directMediaFixtureFault{
		{Op: "remove", RecipientPeerID: recipient},
		{Op: "nuke", RecipientPeerID: recipient, AttachmentID: control.ID},
		{Op: "restore", RecipientPeerID: recipient, AttachmentID: "never-snapshotted"},
		{Op: "corrupt", RecipientPeerID: recipient, AttachmentID: "../escape"},
	} {
		if err := faults.apply(bad); err == nil {
			t.Fatalf("fault %#v accepted", bad)
		}
	}
}

func TestDirectMediaFixtureFaultEndpointAcceptsOnlyWellFormedFaults(t *testing.T) {
	env := setupTestEnv(t)
	env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	faults := newDirectMediaFixtureFaults(env.media)
	post := func(body string) int {
		recorder := httptest.NewRecorder()
		faults.serve(recorder, httptest.NewRequest(http.MethodPost, "/cap/fault", strings.NewReader(body)))
		return recorder.Code
	}
	if code := post(`{"op":"expire"}`); code != http.StatusOK {
		t.Fatalf("expire = %d", code)
	}
	if code := post(`{"op":"clock_reset"}`); code != http.StatusOK {
		t.Fatalf("clock_reset = %d", code)
	}
	if code := post(`{"op":"expire","extra":1}`); code != http.StatusBadRequest {
		t.Fatalf("unknown field = %d", code)
	}
	if code := post(`{"op":"remove","recipientPeerId":"peer","attachmentId":"absent"}`); code != http.StatusConflict {
		t.Fatalf("remove absent = %d", code)
	}
	recorder := httptest.NewRecorder()
	faults.serve(recorder, httptest.NewRequest(http.MethodDelete, "/cap/fault", nil))
	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("delete = %d", recorder.Code)
	}
}

// Shipping builds leave the custody client flag off, so production 1:1 media
// rides the legacy lane. The same controls must reach that lane, where the
// relay serves stored bytes without a hash check of its own.
func TestDirectMediaFixtureFaultControlsDriveRealLegacyStates(t *testing.T) {
	env := setupTestEnv(t)
	faults := newDirectMediaFixtureFaults(env.media)
	recipient := env.recipient.ID().String()
	body := []byte("h2 owned legacy ciphertext for fault controls")
	download := func(id string) (mediaResponse, []byte) {
		t.Helper()
		s, err := env.recipient.NewStream(context.Background(), env.server.ID(), MediaProtocol)
		if err != nil {
			t.Fatal(err)
		}
		defer s.Close()
		sendMediaReq(t, s, mediaRequest{Action: "download", ID: id})
		resp := recvMediaResp(t, s)
		if resp.Status != "OK" {
			return resp, nil
		}
		got := make([]byte, resp.Size)
		if _, err := io.ReadFull(s, got); err != nil {
			t.Fatal(err)
		}
		return resp, got
	}
	target := func(op, id string) directMediaFixtureFault {
		return directMediaFixtureFault{Op: op, RecipientPeerID: recipient, AttachmentID: id}
	}

	env.upload(t, env.sender, "legacy-control", recipient, "application/octet-stream", body)
	if pending := faults.pending(); len(pending) != 1 || pending[0].Lane != "legacy" || pending[0].AttachmentID != "legacy-control" {
		t.Fatalf("pending = %#v", pending)
	}
	if resp, got := download("legacy-control"); resp.Status != "OK" || !bytes.Equal(got, body) {
		t.Fatalf("legacy control = %#v %q", resp, got)
	}

	env.upload(t, env.sender, "legacy-remove", recipient, "application/octet-stream", body)
	for _, op := range []string{"snapshot", "remove"} {
		if err := faults.apply(target(op, "legacy-remove")); err != nil {
			t.Fatalf("%s: %v", op, err)
		}
	}
	if resp, _ := download("legacy-remove"); resp.Error != "not found" {
		t.Fatalf("removed legacy download = %#v", resp)
	}
	if err := faults.apply(target("restore", "legacy-remove")); err != nil {
		t.Fatalf("restore: %v", err)
	}
	if resp, got := download("legacy-remove"); resp.Status != "OK" || !bytes.Equal(got, body) {
		t.Fatalf("restored legacy download = %#v %q", resp, got)
	}

	env.upload(t, env.sender, "legacy-corrupt", recipient, "application/octet-stream", body)
	if err := faults.apply(target("corrupt", "legacy-corrupt")); err != nil {
		t.Fatalf("corrupt: %v", err)
	}
	resp, got := download("legacy-corrupt")
	if resp.Status != "OK" || len(got) != len(body) || bytes.Equal(got, body) {
		t.Fatalf("corrupt legacy download = %#v, want same-size altered bytes served", resp)
	}

	env.upload(t, env.sender, "legacy-expire", recipient, "application/octet-stream", body)
	if err := faults.apply(target("expire", "legacy-expire")); err != nil {
		t.Fatalf("expire: %v", err)
	}
	if resp, _ := download("legacy-expire"); resp.Error != "not found" {
		t.Fatalf("expired legacy download = %#v", resp)
	}
	if _, err := os.Stat(env.media.blobPath(recipient, "legacy-expire")); !os.IsNotExist(err) {
		t.Fatalf("expired legacy blob still on disk: %v", err)
	}
	if resp, got := download("legacy-control"); resp.Status != "OK" || !bytes.Equal(got, body) {
		t.Fatalf("legacy control after sweep = %#v %q", resp, got)
	}
}
