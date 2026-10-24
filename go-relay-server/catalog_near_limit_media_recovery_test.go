package main

import (
	"bytes"
	"io"
	"testing"
	"time"
)

// DC-018 transport leg: real framed handler and filesystem, including the
// 16-byte encryption tag above the application's 25 MiB minus one PNG size.
// App-side per-type rejection is a separate Dart policy/presentation proof.
func TestCatalogDC018NearLimitStorageAndPartialTransferRecovery(t *testing.T) {
	env := setupTestEnv(t)
	env.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	faults := newDirectMediaFixtureFaults(env.media)
	t.Cleanup(func() {
		if err := faults.restoreUploadStorage(); err != nil {
			t.Error(err)
		}
	})
	body := make([]byte, 25*1024*1024-1+16)
	for i := range body {
		body[i] = byte(i % 251)
	}
	req := directMediaCustodyUploadRequest("catalog-near-limit", env.recipient.ID().String(), "application/octet-stream", body)
	if err := faults.apply(directMediaFixtureFault{Op: "upload_storage_block"}); err != nil {
		t.Fatal(err)
	}
	rejected, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
	if ready || rejected.ErrorCode != mediaCustodyErrorStorage {
		t.Fatal("owned filesystem fault did not reject before accepting the body")
	}
	if err := faults.apply(directMediaFixtureFault{Op: "upload_storage_restore"}); err != nil {
		t.Fatal(err)
	}
	baseline := directMediaCustodyFileCount(t, env.media.dataDir)
	stream := directMediaCustodyOpen(t, env, env.sender)
	sendMediaReq(t, stream, req)
	if recvMediaResp(t, stream).Status != "READY" {
		t.Fatal("partial upload did not reach body transfer")
	}
	if _, err := stream.Write(body[:1024]); err != nil {
		t.Fatal(err)
	}
	if err := stream.CloseWrite(); err != nil {
		t.Fatal(err)
	}
	partial := recvMediaResp(t, stream)
	_ = stream.Close()
	if partial.Status != "ERROR" || partial.StoreStatus == mediaCustodyStoreStored {
		t.Fatal("partial body was certified as stored")
	}
	waitFor(t, 5*time.Second, func() bool {
		return directMediaCustodyFileCount(t, env.media.dataDir) == baseline
	}, "partial artifact cleanup")
	proof, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
	if !ready {
		t.Fatal("same upload did not recover")
	}
	requireDirectMediaCustodyProof(t, proof, req, mediaCustodyStoreStored, "")
	storedFiles := directMediaCustodyFileCount(t, env.media.dataDir)
	duplicate, ready := directMediaCustodyUpload(t, env, env.sender, req, body)
	if ready {
		t.Fatal("duplicate requested another body")
	}
	requireDirectMediaCustodyProof(t, duplicate, req, mediaCustodyStoreDuplicate, "")
	interrupted := directMediaCustodyOpen(t, env, env.recipient)
	sendMediaReq(t, interrupted, directMediaCustodyExactRequest(proof, "download"))
	if recvMediaResp(t, interrupted).Status != "OK" {
		t.Fatal("download did not start")
	}
	if _, err := io.ReadFull(interrupted, make([]byte, 1024)); err != nil {
		t.Fatal(err)
	}
	_ = interrupted.Reset()
	response, got := directMediaCustodyDownload(t, env, env.recipient, directMediaCustodyExactRequest(proof, "download"))
	if response.Status != "OK" || !bytes.Equal(got, body) {
		t.Fatal("recovered near-limit bytes changed")
	}
	if directMediaCustodyFileCount(t, env.media.dataDir) != storedFiles {
		t.Fatal("retry duplicated or removed an artifact")
	}
	crossed := directMediaCustodyExactRequest(proof, "download")
	crossed.To = req.To
	denied := directMediaCustodyRequest(t, env, env.intruder, crossed)
	if denied.ErrorCode != mediaCustodyErrorNotAuthorized {
		t.Fatal("cross-recipient request missed authenticated-target rejection")
	}
}
