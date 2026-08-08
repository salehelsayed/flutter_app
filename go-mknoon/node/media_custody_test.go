package node

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

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	ma "github.com/multiformats/go-multiaddr"
)

type mediaCustodyTestRelay struct {
	host host.Host

	mu       sync.Mutex
	requests []mediaRequest
	handler  func(network.Stream, mediaRequest)
}

func startMediaCustodyTestRelay(
	t *testing.T,
	handler func(network.Stream, mediaRequest),
) *mediaCustodyTestRelay {
	t.Helper()
	h, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("libp2p.New: %v", err)
	}
	relay := &mediaCustodyTestRelay{host: h, handler: handler}
	h.SetStreamHandler(MediaProtocol, func(stream network.Stream) {
		defer stream.Close()
		raw, err := readFrame(stream)
		if err != nil {
			return
		}
		var request mediaRequest
		if json.Unmarshal(raw, &request) != nil {
			return
		}
		relay.mu.Lock()
		relay.requests = append(relay.requests, request)
		relay.mu.Unlock()
		handler(stream, request)
	})
	t.Cleanup(func() {
		if err := h.Close(); err != nil {
			t.Errorf("relay close: %v", err)
		}
	})
	return relay
}

func (relay *mediaCustodyTestRelay) addr(t *testing.T) string {
	t.Helper()
	peerComponent, err := ma.NewMultiaddr(fmt.Sprintf("/p2p/%s", relay.host.ID()))
	if err != nil {
		t.Fatalf("peer multiaddr: %v", err)
	}
	return relay.host.Addrs()[0].Encapsulate(peerComponent).String()
}

func (relay *mediaCustodyTestRelay) requestCount() int {
	relay.mu.Lock()
	defer relay.mu.Unlock()
	return len(relay.requests)
}

func configureMediaCustodyTestRelays(t *testing.T, n *Node, addresses ...string) {
	t.Helper()
	n.mu.Lock()
	n.relayAddresses = append([]string(nil), addresses...)
	n.mu.Unlock()
}

func writeMediaCustodyTestResponse(t *testing.T, stream network.Stream, response mediaResponse) {
	t.Helper()
	raw, err := json.Marshal(response)
	if err != nil {
		t.Errorf("marshal response: %v", err)
		return
	}
	if err := writeFrame(stream, raw); err != nil {
		t.Errorf("write response: %v", err)
	}
}

func mediaCustodyTestHash(payload []byte) string {
	digest := sha256.Sum256(payload)
	return fmt.Sprintf("%x", digest[:])
}

func exactMediaCustodyTestResponse(
	request mediaRequest,
	storeStatus string,
	ackStatus string,
	expiresAtMs int64,
) mediaResponse {
	return mediaResponse{
		Status:          "OK",
		StoreStatus:     storeStatus,
		AckStatus:       ackStatus,
		ID:              request.ID,
		Mime:            request.Mime,
		Size:            request.Size,
		CustodyKind:     request.CustodyKind,
		CustodyContract: request.CustodyContract,
		ContentHash:     request.ContentHash,
		ExpiresAtMs:     expiresAtMs,
	}
}

func TestMediaCustodyUploadPhaseAwareRelaySelection(t *testing.T) {
	t.Run("unsupported pre-body relay advances to an exact accepting relay", func(t *testing.T) {
		payload := []byte("strict upload bytes")
		hash := mediaCustodyTestHash(payload)
		path := filepath.Join(t.TempDir(), "upload.enc")
		if err := os.WriteFile(path, payload, 0o600); err != nil {
			t.Fatalf("write upload: %v", err)
		}
		oldRelay := startMediaCustodyTestRelay(t, func(stream network.Stream, _ mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "ERROR", Error: "unknown action: upload_custody_v1"})
		})
		acceptingRelay := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
			body := make([]byte, request.Size)
			if _, err := io.ReadFull(stream, body); err != nil {
				t.Errorf("read upload body: %v", err)
				return
			}
			if !bytes.Equal(body, payload) {
				t.Errorf("body=%q, want %q", body, payload)
			}
			writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "stored", "", 111111))
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, n, oldRelay.addr(t), acceptingRelay.addr(t))

		result, err := n.MediaUploadCustody(
			"blob-phase", "recipient", "application/octet-stream", path,
			CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract, hash,
		)
		if err != nil {
			t.Fatalf("MediaUploadCustody: %v", err)
		}
		if result.StoreStatus != "stored" || result.ContentHash != hash ||
			result.CustodyRelayPeerId != acceptingRelay.host.ID().String() {
			t.Fatalf("result=%#v", result)
		}
	})

	t.Run("dropped final proof probes only the same relay peer", func(t *testing.T) {
		payload := []byte("ambiguous upload bytes")
		hash := mediaCustodyTestHash(payload)
		path := filepath.Join(t.TempDir(), "ambiguous.enc")
		if err := os.WriteFile(path, payload, 0o600); err != nil {
			t.Fatalf("write upload: %v", err)
		}
		var selectedMu sync.Mutex
		selectedAttempts := 0
		selected := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			selectedMu.Lock()
			selectedAttempts++
			attempt := selectedAttempts
			selectedMu.Unlock()
			if attempt == 1 {
				writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
				_, _ = io.CopyN(io.Discard, stream, request.Size)
				return // committed, but deliberately drop the final proof
			}
			writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "duplicate", "", 222222))
		})
		shouldNotReceive := startMediaCustodyTestRelay(t, func(stream network.Stream, _ mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, n, selected.addr(t), shouldNotReceive.addr(t))

		result, err := n.MediaUploadCustody(
			"blob-ambiguous", "recipient", "application/octet-stream", path,
			CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract, hash,
		)
		if err != nil {
			t.Fatalf("MediaUploadCustody recovery: %v", err)
		}
		if result.StoreStatus != "duplicate" || result.ExpiresAtMs != 222222 {
			t.Fatalf("recovered result=%#v", result)
		}
		if selected.requestCount() != 2 || shouldNotReceive.requestCount() != 0 {
			t.Fatalf("selected requests=%d fallback requests=%d",
				selected.requestCount(), shouldNotReceive.requestCount())
		}
	})

	t.Run("contradictory pre-body error proof is terminal", func(t *testing.T) {
		payload := []byte("contradictory pre-body proof")
		hash := mediaCustodyTestHash(payload)
		path := filepath.Join(t.TempDir(), "contradictory.enc")
		if err := os.WriteFile(path, payload, 0o600); err != nil {
			t.Fatalf("write upload: %v", err)
		}
		contradictory := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			response := exactMediaCustodyTestResponse(request, "stored", "", 232323)
			response.Status = "ERROR"
			response.ErrorCode = MediaCustodyAdmissionDisabledCode
			response.Error = "admission disabled"
			writeMediaCustodyTestResponse(t, stream, response)
		})
		shouldNotReceive := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
			_, _ = io.CopyN(io.Discard, stream, request.Size)
			writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "stored", "", 242424))
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, n, contradictory.addr(t), shouldNotReceive.addr(t))

		_, err := n.MediaUploadCustody(
			"blob-contradictory", "recipient", "application/octet-stream", path,
			CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract, hash,
		)
		if err == nil {
			t.Fatal("contradictory ERROR proof was accepted")
		}
		if contradictory.requestCount() != 1 || shouldNotReceive.requestCount() != 0 {
			t.Fatalf("contradictory requests=%d fallback requests=%d",
				contradictory.requestCount(), shouldNotReceive.requestCount())
		}
	})

	t.Run("upload rejects cross-operation ack status", func(t *testing.T) {
		payload := []byte("cross-operation upload proof")
		hash := mediaCustodyTestHash(payload)
		path := filepath.Join(t.TempDir(), "cross-operation.enc")
		if err := os.WriteFile(path, payload, 0o600); err != nil {
			t.Fatalf("write upload: %v", err)
		}
		crossOperation := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			response := exactMediaCustodyTestResponse(request, "duplicate", "acked", 252525)
			writeMediaCustodyTestResponse(t, stream, response)
		})
		shouldNotReceive := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
			_, _ = io.CopyN(io.Discard, stream, request.Size)
			writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "stored", "", 262626))
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, n, crossOperation.addr(t), shouldNotReceive.addr(t))

		_, err := n.MediaUploadCustody(
			"blob-cross-operation", "recipient", "application/octet-stream", path,
			CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract, hash,
		)
		if err == nil {
			t.Fatal("upload accepted an ACK status as custody proof")
		}
		if crossOperation.requestCount() != 1 || shouldNotReceive.requestCount() != 0 {
			t.Fatalf("cross-operation requests=%d fallback requests=%d",
				crossOperation.requestCount(), shouldNotReceive.requestCount())
		}
	})

	t.Run("local hash mismatch fails before relay selection", func(t *testing.T) {
		payload := []byte("local upload hash mismatch")
		path := filepath.Join(t.TempDir(), "local-mismatch.enc")
		if err := os.WriteFile(path, payload, 0o600); err != nil {
			t.Fatalf("write upload: %v", err)
		}
		relay := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, n, relay.addr(t))

		result, err := n.MediaUploadCustody(
			"blob-local-mismatch", "recipient", "application/octet-stream", path,
			CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract,
			mediaCustodyTestHash([]byte("different ciphertext")),
		)
		if !errors.Is(err, ErrMediaCustodyHashMismatch) || result.ErrorCode != MediaCustodyHashMismatchCode {
			t.Fatalf("result=%#v error=%v, want local hash mismatch", result, err)
		}
		if relay.requestCount() != 0 {
			t.Fatalf("local mismatch reached relay %d time(s)", relay.requestCount())
		}
	})

	t.Run("unrecoverable post-body probe is indeterminate without cross-peer advance", func(t *testing.T) {
		payload := []byte("unrecoverable ambiguous upload")
		hash := mediaCustodyTestHash(payload)
		path := filepath.Join(t.TempDir(), "unrecoverable.enc")
		if err := os.WriteFile(path, payload, 0o600); err != nil {
			t.Fatalf("write upload: %v", err)
		}
		var selectedMu sync.Mutex
		selectedAttempts := 0
		selected := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			selectedMu.Lock()
			selectedAttempts++
			attempt := selectedAttempts
			selectedMu.Unlock()
			if attempt == 1 {
				writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
				_, _ = io.CopyN(io.Discard, stream, request.Size)
				return
			}
			writeMediaCustodyTestResponse(t, stream, mediaResponse{
				Status: "ERROR", ErrorCode: MediaCustodyUnsupportedCode,
				Error: "duplicate probe unavailable",
			})
		})
		shouldNotReceive := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "READY"})
			_, _ = io.CopyN(io.Discard, stream, request.Size)
			writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "stored", "", 272727))
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, n, selected.addr(t), shouldNotReceive.addr(t))

		result, err := n.MediaUploadCustody(
			"blob-unrecoverable", "recipient", "application/octet-stream", path,
			CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract, hash,
		)
		if !errors.Is(err, ErrMediaCustodyCommitIndeterminate) ||
			result.ErrorCode != MediaCustodyCommitIndeterminateCode ||
			result.CustodyRelayPeerId != selected.host.ID().String() {
			t.Fatalf("result=%#v error=%v, want source-pinned indeterminate", result, err)
		}
		if selected.requestCount() != 2 || shouldNotReceive.requestCount() != 0 {
			t.Fatalf("selected requests=%d fallback requests=%d",
				selected.requestCount(), shouldNotReceive.requestCount())
		}
	})
}

func TestMediaCustodyStrictDownloadSelectsExactProof(t *testing.T) {
	payload := []byte("strict downloaded ciphertext")
	hash := mediaCustodyTestHash(payload)
	const expiresAtMs = int64(333333)
	proofless := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
		writeMediaCustodyTestResponse(t, stream, mediaResponse{
			Status: "OK", ID: request.ID, Mime: request.Mime, Size: request.Size,
		})
		_, _ = stream.Write(payload)
	})
	exact := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
		writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "", "", expiresAtMs))
		_, _ = stream.Write(payload)
	})
	n := startLocalNodeForMultiRelayTest(t)
	configureMediaCustodyTestRelays(t, n, proofless.addr(t), exact.addr(t))
	outputPath := filepath.Join(t.TempDir(), "download.enc")

	result, err := n.MediaDownloadCustody(
		"blob-download", outputPath,
		CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract, hash,
		int64(len(payload)), "application/octet-stream", expiresAtMs,
	)
	if err != nil {
		t.Fatalf("MediaDownloadCustody: %v", err)
	}
	got, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("read output: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("output=%q, want %q", got, payload)
	}
	if result.ContentHash != hash || result.CustodyRelayPeerId != exact.host.ID().String() {
		t.Fatalf("result=%#v", result)
	}
	if proofless.requestCount() != 1 || exact.requestCount() != 1 {
		t.Fatalf("proofless=%d exact=%d", proofless.requestCount(), exact.requestCount())
	}

	t.Run("mutated proof is terminal", func(t *testing.T) {
		mutated := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			response := exactMediaCustodyTestResponse(request, "", "", expiresAtMs)
			response.ContentHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
			writeMediaCustodyTestResponse(t, stream, response)
		})
		shouldNotRun := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "", "", expiresAtMs))
			_, _ = stream.Write(payload)
		})
		terminalNode := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, terminalNode, mutated.addr(t), shouldNotRun.addr(t))
		_, err := terminalNode.MediaDownloadCustody(
			"blob-mutated", filepath.Join(t.TempDir(), "mutated.enc"),
			CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract, hash,
			int64(len(payload)), "application/octet-stream", expiresAtMs,
		)
		if !errors.Is(err, ErrMediaCustodyHashMismatch) {
			t.Fatalf("error=%v, want hash mismatch", err)
		}
		if shouldNotRun.requestCount() != 0 {
			t.Fatal("mutated proof advanced to another relay")
		}
	})

	t.Run("exact proof with corrupt streamed bytes removes partial file", func(t *testing.T) {
		corruptPayload := append([]byte(nil), payload...)
		corruptPayload[0] ^= 0xff
		corrupt := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "", "", expiresAtMs))
			_, _ = stream.Write(corruptPayload)
		})
		shouldNotRun := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "", "", expiresAtMs))
			_, _ = stream.Write(payload)
		})
		corruptNode := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, corruptNode, corrupt.addr(t), shouldNotRun.addr(t))
		corruptPath := filepath.Join(t.TempDir(), "corrupt.enc")

		result, err := corruptNode.MediaDownloadCustody(
			"blob-corrupt", corruptPath,
			CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract, hash,
			int64(len(payload)), "application/octet-stream", expiresAtMs,
		)
		if !errors.Is(err, ErrMediaCustodyHashMismatch) || result.ErrorCode != MediaCustodyHashMismatchCode {
			t.Fatalf("result=%#v error=%v, want streamed hash mismatch", result, err)
		}
		if _, statErr := os.Stat(corruptPath); !errors.Is(statErr, os.ErrNotExist) {
			t.Fatalf("partial output survived hash mismatch: %v", statErr)
		}
		if shouldNotRun.requestCount() != 0 {
			t.Fatal("streamed hash mismatch advanced to another relay")
		}
	})
}

func TestMediaCustodyAckPinsSourceRelayAndRequiresExactProof(t *testing.T) {
	const expiresAtMs = int64(444444)
	hash := mediaCustodyTestHash([]byte("acked ciphertext"))
	wrongRelay := startMediaCustodyTestRelay(t, func(stream network.Stream, _ mediaRequest) {
		writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "OK", AckStatus: "acked"})
	})
	var sourceMu sync.Mutex
	sourceAttempts := 0
	sourceRelay := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
		sourceMu.Lock()
		sourceAttempts++
		attempt := sourceAttempts
		sourceMu.Unlock()
		if attempt == 1 {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{
				Status: "ERROR", ErrorCode: MediaCustodyCleanupPendingCode,
				Error: "cleanup pending",
			})
			return
		}
		writeMediaCustodyTestResponse(t, stream, exactMediaCustodyTestResponse(request, "", "already_acked", expiresAtMs))
	})
	n := startLocalNodeForMultiRelayTest(t)
	// Duplicate the source address to prove cleanup-pending retry remains within
	// that peer's sibling-address set and never reaches the other configured peer.
	configureMediaCustodyTestRelays(
		t, n, wrongRelay.addr(t), sourceRelay.addr(t), sourceRelay.addr(t),
	)

	result, err := n.MediaAckCustody(
		"blob-ack", CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract,
		hash, int64(len("acked ciphertext")), "application/octet-stream",
		expiresAtMs, sourceRelay.host.ID().String(),
	)
	if err != nil {
		t.Fatalf("MediaAckCustody: %v", err)
	}
	if result.AckStatus != "already_acked" || result.CustodyRelayPeerId != sourceRelay.host.ID().String() {
		t.Fatalf("result=%#v", result)
	}
	if wrongRelay.requestCount() != 0 || sourceRelay.requestCount() != 2 {
		t.Fatalf("wrong relay requests=%d source requests=%d",
			wrongRelay.requestCount(), sourceRelay.requestCount())
	}

	t.Run("generic proof is terminal", func(t *testing.T) {
		other := startMediaCustodyTestRelay(t, func(stream network.Stream, _ mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "OK", AckStatus: "acked"})
		})
		source := startMediaCustodyTestRelay(t, func(stream network.Stream, _ mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "OK", AckStatus: "acked"})
		})
		ackNode := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, ackNode, other.addr(t), source.addr(t))

		_, err := ackNode.MediaAckCustody(
			"blob-generic-ack", CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract,
			hash, int64(len("acked ciphertext")), "application/octet-stream",
			expiresAtMs, source.host.ID().String(),
		)
		if !errors.Is(err, ErrMediaCustodyUnsupported) {
			t.Fatalf("error=%v, want unsupported generic proof", err)
		}
		if source.requestCount() != 1 || other.requestCount() != 0 {
			t.Fatalf("source requests=%d other requests=%d", source.requestCount(), other.requestCount())
		}
	})

	t.Run("mutated proof is terminal", func(t *testing.T) {
		other := startMediaCustodyTestRelay(t, func(stream network.Stream, _ mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "OK", AckStatus: "acked"})
		})
		source := startMediaCustodyTestRelay(t, func(stream network.Stream, request mediaRequest) {
			response := exactMediaCustodyTestResponse(request, "", "acked", expiresAtMs)
			response.ContentHash = mediaCustodyTestHash([]byte("mutated ACK proof"))
			writeMediaCustodyTestResponse(t, stream, response)
		})
		ackNode := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, ackNode, other.addr(t), source.addr(t))

		_, err := ackNode.MediaAckCustody(
			"blob-mutated-ack", CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract,
			hash, int64(len("acked ciphertext")), "application/octet-stream",
			expiresAtMs, source.host.ID().String(),
		)
		if !errors.Is(err, ErrMediaCustodyHashMismatch) {
			t.Fatalf("error=%v, want mutated ACK proof mismatch", err)
		}
		if source.requestCount() != 1 || other.requestCount() != 0 {
			t.Fatalf("source requests=%d other requests=%d", source.requestCount(), other.requestCount())
		}
	})

	t.Run("exhausted source siblings never advance to another peer", func(t *testing.T) {
		other := startMediaCustodyTestRelay(t, func(stream network.Stream, _ mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{Status: "OK", AckStatus: "acked"})
		})
		source := startMediaCustodyTestRelay(t, func(stream network.Stream, _ mediaRequest) {
			writeMediaCustodyTestResponse(t, stream, mediaResponse{
				Status: "ERROR", ErrorCode: MediaCustodyCleanupPendingCode,
				Error: "cleanup pending",
			})
		})
		ackNode := startLocalNodeForMultiRelayTest(t)
		configureMediaCustodyTestRelays(t, ackNode, other.addr(t), source.addr(t), source.addr(t))

		result, err := ackNode.MediaAckCustody(
			"blob-exhausted-ack", CustodyKindDirectMediaBlobV1, AckOrExpiryCustodyContract,
			hash, int64(len("acked ciphertext")), "application/octet-stream",
			expiresAtMs, source.host.ID().String(),
		)
		if !errors.Is(err, ErrMediaCustodyCleanupPending) || result.ErrorCode != MediaCustodyCleanupPendingCode {
			t.Fatalf("result=%#v error=%v, want cleanup pending", result, err)
		}
		if source.requestCount() != 2 || other.requestCount() != 0 {
			t.Fatalf("source requests=%d other requests=%d", source.requestCount(), other.requestCount())
		}
	})
}
