package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
)

// Test-only, one-shot partial-body hold on the existing disposable relay.
// Unarmed traffic uses the unchanged production handler. No production relay
// flag, app hook, timeout, storage behavior or UI automation is introduced.
type directMediaTransferCheckpoint struct {
	mu        sync.Mutex
	ctx       context.Context
	holdLimit time.Duration
	current   *directMediaTransferCut
}

type directMediaTransferCut struct {
	GateID       string `json:"gateId"`
	Direction    string `json:"direction"`
	PeerID       string `json:"peerId,omitempty"`
	AttachmentID string `json:"attachmentId,omitempty"`
	AfterBytes   int64  `json:"afterBytes"`
	TotalBytes   int64  `json:"totalBytes"`
	transferred  int64
	bound        bool
	held         bool
	released     bool
	timedOut     bool
	release      chan struct{}
}

func newDirectMediaTransferCheckpoint(ctx context.Context, limit time.Duration) *directMediaTransferCheckpoint {
	return &directMediaTransferCheckpoint{ctx: ctx, holdLimit: limit}
}

func (gate *directMediaTransferCheckpoint) arm(cut directMediaTransferCut) error {
	if !validDirectMediaFixtureProbeID(cut.GateID) || !validDirectMediaFixtureProbeID(cut.PeerID) ||
		(cut.AttachmentID != "" && !validDirectMediaFixtureProbeID(cut.AttachmentID)) ||
		(cut.Direction != "upload" && cut.Direction != "download") ||
		cut.AfterBytes <= 0 || (cut.TotalBytes != 0 && cut.TotalBytes <= cut.AfterBytes) {
		return errors.New("exact peer, direction and partial-byte bound required")
	}
	gate.mu.Lock()
	defer gate.mu.Unlock()
	if previous := gate.current; previous != nil && !previous.released && !previous.timedOut {
		return errors.New("previous checkpoint must be released before rearming")
	}
	cut.release = make(chan struct{})
	gate.current = &cut
	return nil
}

func (gate *directMediaTransferCheckpoint) release(id string) error {
	gate.mu.Lock()
	defer gate.mu.Unlock()
	cut := gate.current
	if cut == nil || cut.GateID != id {
		return errors.New("checkpoint identity mismatch")
	}
	if !cut.released {
		cut.released = true
		close(cut.release)
	}
	return nil
}

func (gate *directMediaTransferCheckpoint) snapshot() map[string]any {
	gate.mu.Lock()
	defer gate.mu.Unlock()
	result := map[string]any{"schema": "mknoon.media-transfer-checkpoint.v1", "armed": gate.current != nil}
	if cut := gate.current; cut != nil {
		digest := sha256.Sum256([]byte(cut.AttachmentID))
		result["gateId"] = cut.GateID
		result["direction"] = cut.Direction
		result["attachmentSha256"] = hex.EncodeToString(digest[:])
		result["attachmentId"] = cut.AttachmentID // Private fixture response; never mail this ID.
		result["bound"] = cut.bound
		result["bytesTransferred"] = cut.transferred
		result["totalBytes"] = cut.TotalBytes
		result["held"] = cut.held && !cut.released && !cut.timedOut
		result["released"] = cut.released
		result["timedOut"] = cut.timedOut
	}
	return result
}

// Returns the next permitted body slice, or waits at the one exact boundary.
func (gate *directMediaTransferCheckpoint) allowance(cut *directMediaTransferCut, length int) (int, error) {
	gate.mu.Lock()
	if cut.released {
		gate.mu.Unlock()
		return length, nil
	}
	if cut.timedOut {
		gate.mu.Unlock()
		return 0, context.DeadlineExceeded
	}
	remaining := cut.AfterBytes - cut.transferred
	if remaining > 0 {
		gate.mu.Unlock()
		return min(length, int(remaining)), nil
	}
	gate.mu.Unlock()
	timer := time.NewTimer(gate.holdLimit)
	defer timer.Stop()
	select {
	case <-cut.release:
		return length, nil
	case <-gate.ctx.Done():
		return 0, gate.ctx.Err()
	case <-timer.C:
		gate.mu.Lock()
		cut.timedOut = true
		gate.mu.Unlock()
		return 0, context.DeadlineExceeded
	}
}

func (gate *directMediaTransferCheckpoint) recorded(cut *directMediaTransferCut, length int) {
	gate.mu.Lock()
	defer gate.mu.Unlock()
	cut.transferred += int64(length)
	if cut.transferred == cut.AfterBytes {
		cut.held = true
	}
}

type directMediaCutReader struct {
	reader io.Reader
	gate   *directMediaTransferCheckpoint
	cut    *directMediaTransferCut
}

func (reader *directMediaCutReader) Read(buffer []byte) (int, error) {
	limit, err := reader.gate.allowance(reader.cut, len(buffer))
	if err != nil {
		return 0, err
	}
	n, err := reader.reader.Read(buffer[:limit])
	reader.gate.recorded(reader.cut, n)
	return n, err
}

type directMediaCutWriter struct {
	writer io.Writer
	gate   *directMediaTransferCheckpoint
	cut    *directMediaTransferCut
	// The production download writes one framed JSON metadata response first.
	// Preserve it byte-for-byte and count only the subsequent ciphertext body.
	header           []byte
	frameBytes       int
	metadataComplete bool
	validSize        bool
}

func (writer *directMediaCutWriter) Write(buffer []byte) (int, error) {
	total := 0
	for len(buffer) > 0 {
		if !writer.metadataComplete {
			need := 4 - len(writer.header)
			if len(writer.header) >= 4 {
				need = writer.frameBytes - len(writer.header)
			}
			part := buffer[:min(len(buffer), need)]
			n, err := writer.writer.Write(part)
			writer.header = append(writer.header, part[:n]...)
			total += n
			buffer = buffer[n:]
			if err != nil {
				return total, err
			}
			if n != len(part) {
				return total, io.ErrShortWrite
			}
			if len(writer.header) == 4 {
				size := binary.BigEndian.Uint32(writer.header)
				if size > maxFrameLen {
					return total, errors.New("invalid production response frame")
				}
				writer.frameBytes = 4 + int(size)
			}
			if len(writer.header) == writer.frameBytes {
				var metadata mediaResponse
				if err := json.Unmarshal(writer.header[4:], &metadata); err != nil {
					return total, err
				}
				writer.gate.mu.Lock()
				writer.validSize = metadata.Status == "OK" && metadata.Size > writer.cut.AfterBytes &&
					(writer.cut.TotalBytes == 0 || metadata.Size == writer.cut.TotalBytes)
				if writer.validSize {
					writer.cut.TotalBytes = metadata.Size
				}
				writer.gate.mu.Unlock()
				writer.metadataComplete = true
			}
			continue
		}
		limit := len(buffer)
		if writer.validSize {
			var err error
			limit, err = writer.gate.allowance(writer.cut, limit)
			if err != nil {
				return total, err
			}
		}
		n, err := writer.writer.Write(buffer[:limit])
		if writer.validSize {
			writer.gate.recorded(writer.cut, n)
		}
		total += n
		buffer = buffer[n:]
		if err != nil {
			return total, err
		}
		if n != limit {
			return total, io.ErrShortWrite
		}
	}
	return total, nil
}

type directMediaCheckpointStream struct {
	network.Stream
	reader io.Reader
	writer io.Writer
}

func (stream *directMediaCheckpointStream) Read(body []byte) (int, error) {
	return stream.reader.Read(body)
}
func (stream *directMediaCheckpointStream) Write(body []byte) (int, error) {
	return stream.writer.Write(body)
}

func (gate *directMediaTransferCheckpoint) handle(stream network.Stream, media *MediaStore, profile *ProfileStore) {
	gate.mu.Lock()
	cut := gate.current
	eligible := cut != nil && !cut.bound && !cut.released && !cut.timedOut && cut.PeerID == stream.Conn().RemotePeer().String()
	gate.mu.Unlock()
	if !eligible {
		HandleMediaStream(stream, media, profile)
		return
	}
	requestBytes, err := readFrame(stream)
	if err != nil {
		_ = stream.Reset()
		return
	}
	var request mediaRequest
	if err := json.Unmarshal(requestBytes, &request); err != nil {
		_ = stream.Reset()
		return
	}
	var header bytes.Buffer
	if err := writeFrame(&header, requestBytes); err != nil {
		_ = stream.Reset()
		return
	}
	wrapped := &directMediaCheckpointStream{Stream: stream, reader: io.MultiReader(&header, stream), writer: stream}
	gate.mu.Lock()
	matching := !cut.bound && !cut.released && validDirectMediaFixtureProbeID(request.ID) &&
		(cut.AttachmentID == "" || cut.AttachmentID == request.ID) &&
		(cut.Direction == "upload" && (request.Action == "upload" || request.Action == mediaCustodyUploadAction) && request.Size > cut.AfterBytes && (cut.TotalBytes == 0 || request.Size == cut.TotalBytes) ||
			cut.Direction == "download" && request.Action == "download")
	if matching {
		cut.bound = true
		cut.AttachmentID = request.ID
		if cut.Direction == "upload" {
			cut.TotalBytes = request.Size
		}
	}
	gate.mu.Unlock()
	if matching {
		if cut.Direction == "upload" {
			wrapped.reader = io.MultiReader(&header, &directMediaCutReader{reader: stream, gate: gate, cut: cut})
		} else {
			wrapped.writer = &directMediaCutWriter{writer: stream, gate: gate, cut: cut}
		}
	}
	HandleMediaStream(wrapped, media, profile)
}

func (gate *directMediaTransferCheckpoint) serve(writer http.ResponseWriter, request *http.Request) {
	if request.Method == http.MethodPost {
		var input struct {
			Op string `json:"op"`
			directMediaTransferCut
		}
		if err := json.NewDecoder(http.MaxBytesReader(writer, request.Body, 4096)).Decode(&input); err != nil {
			http.Error(writer, "checkpoint body rejected", http.StatusBadRequest)
			return
		}
		var err error
		switch input.Op {
		case "arm":
			err = gate.arm(input.directMediaTransferCut)
		case "release":
			err = gate.release(input.GateID)
		default:
			err = errors.New("unknown checkpoint operation")
		}
		if err != nil {
			http.Error(writer, err.Error(), http.StatusBadRequest)
			return
		}
	} else if request.Method != http.MethodGet {
		http.Error(writer, "GET or POST required", http.StatusMethodNotAllowed)
		return
	}
	writer.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(writer).Encode(gate.snapshot())
}
