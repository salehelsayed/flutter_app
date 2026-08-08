//go:build integration

package integration_test

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/mknoon/go-mknoon/node"
)

const (
	mediaCustodyMatrixOld      = "old"
	mediaCustodyMatrixDisabled = "disabled"
	mediaCustodyMatrixFull     = "full"
	mediaCustodyMatrixConflict = "conflict"
	mediaCustodyMatrixAccept   = "accept"
	mediaCustodyMatrixDropOnce = "drop_once"
)

type mediaCustodyMatrixRequest struct {
	Action          string `json:"action"`
	ID              string `json:"id,omitempty"`
	To              string `json:"to,omitempty"`
	Size            int64  `json:"size,omitempty"`
	Mime            string `json:"mime,omitempty"`
	CustodyKind     string `json:"custodyKind,omitempty"`
	CustodyContract string `json:"custodyContract,omitempty"`
	ContentHash     string `json:"contentHash,omitempty"`
	ExpiresAtMs     int64  `json:"expiresAtMs,omitempty"`
}

type mediaCustodyMatrixResponse struct {
	Status          string `json:"status"`
	Error           string `json:"error,omitempty"`
	ErrorCode       string `json:"errorCode,omitempty"`
	StoreStatus     string `json:"storeStatus,omitempty"`
	AckStatus       string `json:"ackStatus,omitempty"`
	ID              string `json:"id,omitempty"`
	Size            int64  `json:"size,omitempty"`
	Mime            string `json:"mime,omitempty"`
	CustodyKind     string `json:"custodyKind,omitempty"`
	CustodyContract string `json:"custodyContract,omitempty"`
	ContentHash     string `json:"contentHash,omitempty"`
	ExpiresAtMs     int64  `json:"expiresAtMs,omitempty"`
}

type mediaCustodyMatrixState struct {
	mu sync.Mutex

	mode      string
	actions   []string
	committed bool
	acked     bool
	dropped   bool
	request   mediaCustodyMatrixRequest
	payload   []byte
	expiresAt int64
}

func startMediaCustodyMatrixRelay(t *testing.T, mode string) (*localRelayServer, *mediaCustodyMatrixState) {
	t.Helper()
	relay := newLocalRelayServer(t, newLocalRelaySharedState())
	relay.start()
	state := &mediaCustodyMatrixState{mode: mode, expiresAt: 9_000_000_000_000}
	relay.host.SetStreamHandler(node.MediaProtocol, state.handleStream)
	t.Cleanup(func() { relay.stop() })
	return relay, state
}

func (state *mediaCustodyMatrixState) handleStream(stream network.Stream) {
	defer stream.Close()
	raw, err := readLocalRelayFrame(stream)
	if err != nil {
		return
	}
	var request mediaCustodyMatrixRequest
	if json.Unmarshal(raw, &request) != nil {
		return
	}
	state.mu.Lock()
	defer state.mu.Unlock()
	state.actions = append(state.actions, request.Action)

	switch request.Action {
	case "upload_custody_v1":
		state.handleUpload(stream, request)
	case "download":
		state.handleDownload(stream, request)
	case "ack_custody_v1":
		state.handleAck(stream, request)
	default:
		_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{
			Status: "ERROR", Error: "unknown action: " + request.Action,
		})
	}
}

func (state *mediaCustodyMatrixState) handleUpload(stream network.Stream, request mediaCustodyMatrixRequest) {
	switch state.mode {
	case mediaCustodyMatrixOld:
		_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{
			Status: "ERROR", Error: "unknown action: upload_custody_v1",
		})
		return
	case mediaCustodyMatrixDisabled:
		_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{
			Status: "ERROR", ErrorCode: node.MediaCustodyAdmissionDisabledCode,
			StoreStatus: "disabled",
		})
		return
	case mediaCustodyMatrixFull:
		_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{
			Status: "ERROR", ErrorCode: node.MediaCustodyFullCode,
			StoreStatus: "rejected_full",
		})
		return
	case mediaCustodyMatrixConflict:
		_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{
			Status: "ERROR", ErrorCode: node.MediaCustodyIdentityConflictCode,
		})
		return
	}
	if state.committed {
		if state.sameIdentity(request) {
			_ = writeMediaCustodyMatrixResponse(stream, state.proof("duplicate", ""))
			return
		}
		_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{
			Status: "ERROR", ErrorCode: node.MediaCustodyIdentityConflictCode,
		})
		return
	}
	_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{Status: "READY"})
	payload := make([]byte, request.Size)
	if _, err := io.ReadFull(stream, payload); err != nil {
		return
	}
	state.committed = true
	state.request = request
	state.payload = payload
	if state.mode == mediaCustodyMatrixDropOnce && !state.dropped {
		state.dropped = true
		return
	}
	_ = writeMediaCustodyMatrixResponse(stream, state.proof("stored", ""))
}

func (state *mediaCustodyMatrixState) handleDownload(stream network.Stream, request mediaCustodyMatrixRequest) {
	if state.mode == mediaCustodyMatrixOld {
		// An old relay may ignore additive fields and return a broad legacy OK;
		// the strict client must not accept it as custody proof.
		_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{
			Status: "OK", ID: request.ID, Size: request.Size, Mime: request.Mime,
		})
		return
	}
	if !state.committed || state.acked || !state.sameIdentity(request) ||
		stream.Conn().RemotePeer().String() != state.request.To {
		_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{
			Status: "ERROR", ErrorCode: node.MediaCustodyNotFoundCode,
		})
		return
	}
	_ = writeMediaCustodyMatrixResponse(stream, state.proof("", ""))
	_, _ = stream.Write(state.payload)
}

func (state *mediaCustodyMatrixState) handleAck(stream network.Stream, request mediaCustodyMatrixRequest) {
	if !state.committed || !state.sameIdentity(request) ||
		stream.Conn().RemotePeer().String() != state.request.To {
		_ = writeMediaCustodyMatrixResponse(stream, mediaCustodyMatrixResponse{
			Status: "ERROR", ErrorCode: node.MediaCustodyNotFoundCode,
		})
		return
	}
	status := "acked"
	if state.acked {
		status = "already_acked"
	}
	state.acked = true
	state.payload = nil
	_ = writeMediaCustodyMatrixResponse(stream, state.proof("", status))
}

func (state *mediaCustodyMatrixState) sameIdentity(request mediaCustodyMatrixRequest) bool {
	return request.ID == state.request.ID &&
		request.Size == state.request.Size && request.Mime == state.request.Mime &&
		request.CustodyKind == state.request.CustodyKind &&
		request.CustodyContract == state.request.CustodyContract &&
		request.ContentHash == state.request.ContentHash &&
		(request.ExpiresAtMs == 0 || request.ExpiresAtMs == state.expiresAt)
}

func (state *mediaCustodyMatrixState) proof(storeStatus, ackStatus string) mediaCustodyMatrixResponse {
	return mediaCustodyMatrixResponse{
		Status:          "OK",
		StoreStatus:     storeStatus,
		AckStatus:       ackStatus,
		ID:              state.request.ID,
		Size:            state.request.Size,
		Mime:            state.request.Mime,
		CustodyKind:     state.request.CustodyKind,
		CustodyContract: state.request.CustodyContract,
		ContentHash:     state.request.ContentHash,
		ExpiresAtMs:     state.expiresAt,
	}
}

func (state *mediaCustodyMatrixState) actionCount(action string) int {
	state.mu.Lock()
	defer state.mu.Unlock()
	count := 0
	for _, candidate := range state.actions {
		if candidate == action {
			count++
		}
	}
	return count
}

func writeMediaCustodyMatrixResponse(stream network.Stream, response mediaCustodyMatrixResponse) error {
	raw, err := json.Marshal(response)
	if err != nil {
		return err
	}
	return writeLocalRelayFrame(stream, raw)
}

func mediaCustodyMatrixHash(payload []byte) string {
	digest := sha256.Sum256(payload)
	return fmt.Sprintf("%x", digest[:])
}

func TestMediaCustodyMixedRelayMatrix(t *testing.T) {
	t.Run("old disabled and full relays advance to one proof-bearing owner", func(t *testing.T) {
		oldRelay, oldState := startMediaCustodyMatrixRelay(t, mediaCustodyMatrixOld)
		disabledRelay, disabledState := startMediaCustodyMatrixRelay(t, mediaCustodyMatrixDisabled)
		fullRelay, fullState := startMediaCustodyMatrixRelay(t, mediaCustodyMatrixFull)
		acceptingRelay, acceptingState := startMediaCustodyMatrixRelay(t, mediaCustodyMatrixAccept)
		addresses := []string{oldRelay.addr(), disabledRelay.addr(), fullRelay.addr(), acceptingRelay.addr()}
		recipient, recipientID := startNodeWithRelays(t, addresses, nil, nil)
		sender, _ := startNodeWithRelays(t, addresses, nil, nil)

		payload := []byte("mixed relay strict ciphertext")
		hash := mediaCustodyMatrixHash(payload)
		uploadPath := filepath.Join(t.TempDir(), "upload.enc")
		if err := os.WriteFile(uploadPath, payload, 0o600); err != nil {
			t.Fatalf("write upload: %v", err)
		}
		upload, err := sender.MediaUploadCustody(
			"matrix-blob", recipientID, "application/octet-stream", uploadPath,
			node.CustodyKindDirectMediaBlobV1, node.AckOrExpiryCustodyContract, hash,
		)
		if err != nil {
			t.Fatalf("MediaUploadCustody: %v", err)
		}
		if upload.StoreStatus != "stored" || upload.CustodyRelayPeerId != acceptingRelay.peerID.String() {
			t.Fatalf("upload=%#v", upload)
		}

		downloadPath := filepath.Join(t.TempDir(), "download.enc")
		download, err := recipient.MediaDownloadCustody(
			upload.ID, downloadPath, upload.CustodyKind, upload.CustodyContract,
			upload.ContentHash, upload.Size, upload.Mime, upload.ExpiresAtMs,
		)
		if err != nil {
			t.Fatalf("MediaDownloadCustody: %v", err)
		}
		got, err := os.ReadFile(downloadPath)
		if err != nil || !bytes.Equal(got, payload) {
			t.Fatalf("download=%q err=%v", got, err)
		}
		if download.CustodyRelayPeerId != acceptingRelay.peerID.String() {
			t.Fatalf("download source=%s", download.CustodyRelayPeerId)
		}

		ack, err := recipient.MediaAckCustody(
			upload.ID, upload.CustodyKind, upload.CustodyContract, upload.ContentHash,
			upload.Size, upload.Mime, upload.ExpiresAtMs, download.CustodyRelayPeerId,
		)
		if err != nil || ack.AckStatus != "acked" {
			t.Fatalf("MediaAckCustody=%#v err=%v", ack, err)
		}
		if oldState.actionCount("ack_custody_v1") != 0 ||
			disabledState.actionCount("ack_custody_v1") != 0 ||
			fullState.actionCount("ack_custody_v1") != 0 ||
			acceptingState.actionCount("ack_custody_v1") != 1 {
			t.Fatalf("ACK was not pinned to accepting source")
		}
	})

	t.Run("identity conflict is terminal", func(t *testing.T) {
		conflictRelay, _ := startMediaCustodyMatrixRelay(t, mediaCustodyMatrixConflict)
		acceptingRelay, acceptingState := startMediaCustodyMatrixRelay(t, mediaCustodyMatrixAccept)
		sender, _ := startNodeWithRelays(t, []string{conflictRelay.addr(), acceptingRelay.addr()}, nil, nil)
		payload := []byte("conflicting bytes")
		path := filepath.Join(t.TempDir(), "conflict.enc")
		if err := os.WriteFile(path, payload, 0o600); err != nil {
			t.Fatalf("write upload: %v", err)
		}
		_, err := sender.MediaUploadCustody(
			"matrix-conflict", "recipient", "application/octet-stream", path,
			node.CustodyKindDirectMediaBlobV1, node.AckOrExpiryCustodyContract,
			mediaCustodyMatrixHash(payload),
		)
		if !errors.Is(err, node.ErrMediaCustodyIdentityConflict) {
			t.Fatalf("error=%v, want identity conflict", err)
		}
		if acceptingState.actionCount("upload_custody_v1") != 0 {
			t.Fatal("terminal conflict advanced to another relay")
		}
	})

	t.Run("ambiguous commit probes same peer without replication", func(t *testing.T) {
		dropRelay, dropState := startMediaCustodyMatrixRelay(t, mediaCustodyMatrixDropOnce)
		fallbackRelay, fallbackState := startMediaCustodyMatrixRelay(t, mediaCustodyMatrixAccept)
		sender, _ := startNodeWithRelays(t, []string{dropRelay.addr(), fallbackRelay.addr()}, nil, nil)
		payload := []byte("commit then drop proof")
		path := filepath.Join(t.TempDir(), "drop.enc")
		if err := os.WriteFile(path, payload, 0o600); err != nil {
			t.Fatalf("write upload: %v", err)
		}
		result, err := sender.MediaUploadCustody(
			"matrix-drop", "recipient", "application/octet-stream", path,
			node.CustodyKindDirectMediaBlobV1, node.AckOrExpiryCustodyContract,
			mediaCustodyMatrixHash(payload),
		)
		if err != nil || result.StoreStatus != "duplicate" {
			t.Fatalf("recovered result=%#v err=%v", result, err)
		}
		if dropState.actionCount("upload_custody_v1") != 2 ||
			fallbackState.actionCount("upload_custody_v1") != 0 {
			t.Fatalf("drop attempts=%d fallback attempts=%d",
				dropState.actionCount("upload_custody_v1"),
				fallbackState.actionCount("upload_custody_v1"))
		}
	})
}
