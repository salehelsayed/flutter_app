package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDirectMediaFixtureUploadStorageFaultRejectsThenRetriesRealUpload(t *testing.T) {
	env := setupTestEnv(t)
	env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	faults := newDirectMediaFixtureFaults(env.media)
	t.Cleanup(func() {
		if err := faults.restoreUploadStorage(); err != nil {
			t.Errorf("restore fixture storage: %v", err)
		}
	})
	recipient := env.recipient.ID().String()
	body := []byte{0, 1, 2, 3, 4, 5, 6, 7}
	controlReq := directMediaCustodyUploadRequest("owned-control", recipient, "application/octet-stream", body)
	control, _ := directMediaCustodyUpload(t, env, env.sender, controlReq, body)
	requireDirectMediaCustodyProof(t, control, controlReq, mediaCustodyStoreStored, "")
	if err := faults.apply(directMediaFixtureFault{Op: "upload_storage_block"}); err != nil {
		t.Fatal(err)
	}
	retryReq := directMediaCustodyUploadRequest("owned-retry", recipient, "application/octet-stream", body)
	rejected, _ := directMediaCustodyUpload(t, env, env.sender, retryReq, body)
	if rejected.Status != "ERROR" || rejected.ErrorCode != mediaCustodyErrorStorage || rejected.StoreStatus == mediaCustodyStoreStored {
		t.Fatalf("real upload was not a storage rejection: status=%s code=%s", rejected.Status, rejected.ErrorCode)
	}
	if err := faults.apply(directMediaFixtureFault{Op: "upload_storage_restore"}); err != nil {
		t.Fatal(err)
	}
	retried, _ := directMediaCustodyUpload(t, env, env.sender, retryReq, body)
	requireDirectMediaCustodyProof(t, retried, retryReq, mediaCustodyStoreStored, "")
	for _, proof := range []mediaResponse{control, retried} {
		response, got := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(proof, "download"))
		if response.Status != "OK" || !bytes.Equal(got, body) {
			t.Fatal("restored target or unrelated original blob changed")
		}
	}
}

func TestDirectMediaFixtureUploadStorageFaultEndpointRejectsScopeAndBusyUploads(t *testing.T) {
	env := setupTestEnv(t)
	faults := newDirectMediaFixtureFaults(env.media)
	t.Cleanup(func() {
		if err := faults.restoreUploadStorage(); err != nil {
			t.Errorf("restore fixture storage: %v", err)
		}
	})
	post := func(body string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		faults.serve(w, httptest.NewRequest(http.MethodPost, "/cap/fault", strings.NewReader(body)))
		return w
	}
	for _, body := range []string{`{"op":"upload_storage_block","attachmentId":"unexpected"}`, `{"op":"upload_storage_restore","lane":"custody"}`} {
		if response := post(body); response.Code != http.StatusConflict {
			t.Fatalf("target scope not rejected: %d", response.Code)
		}
	}
	env.media.laneMu.Lock()
	env.media.legacyReservations["active"] = 1
	env.media.laneMu.Unlock()
	if response := post(`{"op":"upload_storage_block"}`); response.Code != http.StatusConflict {
		t.Fatalf("active upload not rejected: %d", response.Code)
	}
	env.media.laneMu.Lock()
	delete(env.media.legacyReservations, "active")
	env.media.laneMu.Unlock()
	response := post(`{"op":"upload_storage_block"}`)
	if response.Code != http.StatusOK {
		t.Fatalf("block failed: %d", response.Code)
	}
	var report struct {
		Status struct {
			Blocked bool `json:"uploadStorageBlocked"`
		} `json:"status"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &report); err != nil || !report.Status.Blocked {
		t.Fatal("owned storage-block status not observed")
	}
	if response := post(`{"op":"upload_storage_restore"}`); response.Code != http.StatusOK {
		t.Fatalf("restore failed: %d", response.Code)
	}
	if _, err := os.Stat(env.media.dataDir); err != nil {
		t.Fatal(err)
	}
}

func TestDirectMediaFixtureUploadStorageRestorePreservesUnexpectedReplacement(t *testing.T) {
	env := setupTestEnv(t)
	faults := newDirectMediaFixtureFaults(env.media)
	if err := faults.blockUploadStorage(); err != nil {
		t.Fatal(err)
	}
	root := env.media.dataDir
	t.Cleanup(func() {
		_ = os.WriteFile(root, []byte(directMediaFixtureUploadStorageMarker), 0600)
		if err := faults.restoreUploadStorage(); err != nil {
			t.Errorf("restore fixture storage: %v", err)
		}
	})
	changed := []byte("changed owned test marker")
	if err := os.WriteFile(root, changed, 0600); err != nil {
		t.Fatal(err)
	}
	if err := faults.restoreUploadStorage(); err == nil {
		t.Fatal("changed replacement was removed")
	}
	got, err := os.ReadFile(root)
	if err != nil || !bytes.Equal(got, changed) {
		t.Fatal("unexpected replacement was modified")
	}
	info, err := os.Stat(filepath.Join(faults.uploadStash, "media"))
	if err != nil || !info.IsDir() {
		t.Fatal("original media directory was not retained")
	}
}
