package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
)

func waitDirectMediaTransferHeld(t *testing.T, gate *directMediaTransferCheckpoint) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if gate.snapshot()["held"] == true {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("partial transfer never held: %#v", gate.snapshot())
}

func TestDirectMediaTransferCheckpointUploadPreservesProductionCustody(t *testing.T) {
	t.Setenv(mediaCustodyAdmissionEnabledEnv, "true")
	env := setupTestEnv(t)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	gate := newDirectMediaTransferCheckpoint(ctx, time.Second)
	env.server.SetStreamHandler(MediaProtocol, func(s network.Stream) { gate.handle(s, env.media, env.profile) })
	body := bytes.Repeat([]byte("real production encrypted bytes"), 16384)
	req := directMediaCustodyUploadRequest("checkpoint-upload", env.recipient.ID().String(), "image/jpeg", body)
	if err := gate.arm(directMediaTransferCut{GateID: "upload-run", Direction: "upload", PeerID: env.sender.ID().String(), AfterBytes: 65536}); err != nil {
		t.Fatal(err)
	}
	stream := directMediaCustodyOpen(t, env, env.sender)
	defer stream.Close()
	sendMediaReq(t, stream, req)
	if ready := recvMediaResp(t, stream); ready.Status != "READY" {
		t.Fatalf("not READY: %#v", ready)
	}
	writeDone := make(chan error, 1)
	go func() { _, err := stream.Write(body); writeDone <- err }()
	waitDirectMediaTransferHeld(t, gate)
	if state := gate.snapshot(); state["bytesTransferred"] != int64(65536) || state["bound"] != true || state["released"] != false {
		t.Fatalf("inexact cut: %#v", state)
	}
	response := make(chan mediaResponse, 1)
	go func() {
		frame, err := readFrame(stream)
		var result mediaResponse
		if err == nil {
			_ = json.Unmarshal(frame, &result)
		}
		response <- result
	}()
	select {
	case result := <-response:
		t.Fatalf("upload completed through the held cut: %#v", result)
	case <-time.After(20 * time.Millisecond):
	}
	if err := gate.release("wrong-run"); err == nil {
		t.Fatal("wrong run released transfer")
	}
	if err := gate.release("upload-run"); err != nil {
		t.Fatal(err)
	}
	select {
	case result := <-response:
		requireDirectMediaCustodyProof(t, result, req, mediaCustodyStoreStored, "")
	case <-time.After(3 * time.Second):
		t.Fatal("released upload did not settle")
	}
	if err := <-writeDone; err != nil {
		t.Fatal(err)
	}
}

func TestDirectMediaTransferCheckpointDownloadCountsOnlyCiphertext(t *testing.T) {
	t.Setenv(mediaCustodyAdmissionEnabledEnv, "true")
	env := setupTestEnv(t)
	body := bytes.Repeat([]byte("encrypted image body"), 16384)
	req := directMediaCustodyUploadRequest("checkpoint-download", env.recipient.ID().String(), "image/jpeg", body)
	stored, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	gate := newDirectMediaTransferCheckpoint(ctx, time.Second)
	if err := gate.arm(directMediaTransferCut{GateID: "download-run", Direction: "download", PeerID: env.recipient.ID().String(), AttachmentID: req.ID, AfterBytes: 65536}); err != nil {
		t.Fatal(err)
	}
	env.server.SetStreamHandler(MediaProtocol, func(s network.Stream) { gate.handle(s, env.media, env.profile) })
	stream := directMediaCustodyOpen(t, env, env.recipient)
	defer stream.Close()
	sendMediaReq(t, stream, directMediaCustodyExactRequest(stored, "download"))
	metadata := recvMediaResp(t, stream)
	if metadata.Status != "OK" || metadata.Size != int64(len(body)) {
		t.Fatalf("metadata changed: %#v", metadata)
	}
	actual := make([]byte, len(body))
	if _, err := io.ReadFull(stream, actual[:65536]); err != nil {
		t.Fatal(err)
	}
	waitDirectMediaTransferHeld(t, gate)
	if got := gate.snapshot()["bytesTransferred"]; got != int64(65536) {
		t.Fatalf("framed metadata counted as ciphertext: %v", got)
	}
	rest := make(chan error, 1)
	go func() { _, err := io.ReadFull(stream, actual[65536:]); rest <- err }()
	select {
	case err := <-rest:
		t.Fatalf("remaining body crossed held checkpoint: %v", err)
	case <-time.After(20 * time.Millisecond):
	}
	if err := gate.release("download-run"); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-rest:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("released download did not finish")
	}
	if !bytes.Equal(body, actual) {
		t.Fatal("production download bytes changed")
	}
}

func TestDirectMediaTransferCheckpointHttpBindingAndUnrelatedPeer(t *testing.T) {
	t.Setenv(mediaCustodyAdmissionEnabledEnv, "true")
	env := setupTestEnv(t)
	gate := newDirectMediaTransferCheckpoint(context.Background(), time.Second)
	request := httptest.NewRequest(http.MethodPost, "/transfer-checkpoint", strings.NewReader(`{"op":"arm","gateId":"unrelated-run","direction":"upload","peerId":"other-peer","afterBytes":1,"totalBytes":100}`))
	recorder := httptest.NewRecorder()
	gate.serve(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("arm refused: %s", recorder.Body.String())
	}
	env.server.SetStreamHandler(MediaProtocol, func(s network.Stream) { gate.handle(s, env.media, env.profile) })
	body := []byte("unrelated production payload")
	req := directMediaCustodyUploadRequest("unrelated-upload", env.recipient.ID().String(), "image/jpeg", body)
	stored, _ := directMediaCustodyUpload(t, env, env.sender, req, body)
	requireDirectMediaCustodyProof(t, stored, req, mediaCustodyStoreStored, "")
	if state := gate.snapshot(); state["bound"] != false || state["bytesTransferred"] != int64(0) {
		t.Fatalf("unrelated peer captured: %#v", state)
	}
	if err := gate.arm(directMediaTransferCut{GateID: "replacement", Direction: "upload", PeerID: "peer", AfterBytes: 1, TotalBytes: 10}); err == nil {
		t.Fatal("unreleased gate was replaced")
	}
	if err := gate.release("unrelated-run"); err != nil {
		t.Fatal(err)
	}
	if err := gate.release("unrelated-run"); err != nil {
		t.Fatal("release is not idempotent")
	}
}

func TestDirectMediaTransferCheckpointTimeoutAndCancellation(t *testing.T) {
	for _, cancelled := range []bool{false, true} {
		t.Run(map[bool]string{false: "timeout", true: "cancellation"}[cancelled], func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			gate := newDirectMediaTransferCheckpoint(ctx, time.Millisecond)
			if err := gate.arm(directMediaTransferCut{GateID: "bounded-run", Direction: "upload", PeerID: "peer", AfterBytes: 2, TotalBytes: 4}); err != nil {
				t.Fatal(err)
			}
			reader := &directMediaCutReader{reader: bytes.NewReader([]byte("1234")), gate: gate, cut: gate.current}
			buffer := make([]byte, 4)
			if n, err := reader.Read(buffer); n != 2 || err != nil {
				t.Fatalf("partial read %d: %v", n, err)
			}
			if cancelled {
				cancel()
			}
			_, err := reader.Read(buffer)
			want := context.DeadlineExceeded
			if cancelled {
				want = context.Canceled
			}
			if !errors.Is(err, want) {
				t.Fatalf("unbounded/incorrect wait: %v", err)
			}
			if !cancelled && gate.snapshot()["timedOut"] != true {
				t.Fatal("timeout not retained")
			}
		})
	}
}
