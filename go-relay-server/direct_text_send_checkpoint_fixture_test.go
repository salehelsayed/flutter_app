//go:build integration

package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"sync"
	"time"
)

// DC-004 needs a causal in-flight cut. UI sampling alone cannot prove that
// custody committed while its acknowledgement is still withheld. This adapter
// belongs only to the existing ephemeral relay fixture: it calls the real
// Redis store first, then gates the armed legacy or ACK-custody text response. No app or
// production relay handler changes, broad packet proxy, or audio hook.
type directTextSendCheckpoint struct {
	ctx           context.Context
	mu            sync.Mutex
	armed         bool
	recipientHash string
	messageHash   string
	heldAt        int64
	released      bool
	timedOut      bool
	release       chan struct{}
}

type directTextSendCheckpointStatus struct {
	Schema        string `json:"schema"`
	Armed         bool   `json:"armed"`
	Held          bool   `json:"held"`
	MessageSHA256 string `json:"messageSha256,omitempty"`
	HeldAtUnixMs  int64  `json:"heldAtUnixMs,omitempty"`
	Released      bool   `json:"released"`
	TimedOut      bool   `json:"timedOut"`
}

func newDirectTextSendCheckpoint(ctx context.Context) *directTextSendCheckpoint {
	return &directTextSendCheckpoint{ctx: ctx}
}

func directTextCheckpointHash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func (gate *directTextSendCheckpoint) arm(recipientHash string) error {
	decoded, err := hex.DecodeString(recipientHash)
	if err != nil || len(decoded) != sha256.Size {
		return errors.New("exact recipient digest required")
	}
	gate.mu.Lock()
	defer gate.mu.Unlock()
	if gate.release != nil {
		return errors.New("checkpoint already used")
	}
	gate.armed, gate.released, gate.timedOut = true, false, false
	gate.recipientHash, gate.messageHash, gate.heldAt = hex.EncodeToString(decoded), "", 0
	gate.release = make(chan struct{})
	return nil
}

func (gate *directTextSendCheckpoint) snapshot() directTextSendCheckpointStatus {
	gate.mu.Lock()
	defer gate.mu.Unlock()
	return directTextSendCheckpointStatus{
		Schema:        "mknoon.direct-text-send-checkpoint.v1",
		Armed:         gate.armed,
		Held:          gate.messageHash != "" && !gate.released && !gate.timedOut && gate.ctx.Err() == nil,
		MessageSHA256: gate.messageHash, HeldAtUnixMs: gate.heldAt,
		Released: gate.released, TimedOut: gate.timedOut,
	}
}

func (gate *directTextSendCheckpoint) releaseHeld() {
	gate.mu.Lock()
	defer gate.mu.Unlock()
	if gate.release != nil && !gate.released {
		close(gate.release)
		gate.released = true
	}
}

func (gate *directTextSendCheckpoint) afterCommit(to string, entry inboxMessage, result InboxStoreResult) error {
	var envelope struct {
		Type string `json:"type"`
	}
	if json.Unmarshal([]byte(entry.Message), &envelope) != nil || envelope.Type != "chat_message" {
		return nil
	}
	id := extractMessageId(entry.Message)
	if id == "" {
		return nil
	}
	digest := directTextCheckpointHash(id)
	gate.mu.Lock()
	if !gate.armed || gate.released || gate.timedOut ||
		gate.recipientHash != directTextCheckpointHash(to) ||
		(gate.messageHash == "" && result != InboxStoreResultStored) ||
		(gate.messageHash != "" && gate.messageHash != digest) {
		gate.mu.Unlock()
		return nil
	}
	if gate.messageHash == "" {
		gate.messageHash, gate.heldAt = digest, time.Now().UnixMilli()
	}
	release, started := gate.release, gate.heldAt
	gate.mu.Unlock()
	// Every duplicate of the selected identity shares the same bounded hold;
	// a parallel retry cannot obtain an early successful acknowledgement.
	remaining := 10*time.Second - time.Since(time.UnixMilli(started))
	if remaining < 0 {
		remaining = 0
	}
	timer := time.NewTimer(remaining)
	defer timer.Stop()
	select {
	case <-release:
		return nil
	case <-gate.ctx.Done():
		return gate.ctx.Err()
	case <-timer.C:
		gate.mu.Lock()
		if gate.released {
			gate.mu.Unlock()
			return nil
		}
		gate.timedOut = true
		gate.mu.Unlock()
		return errors.New("fixture checkpoint timed out")
	}
}

// Embed the concrete Redis backend so its optional custody/recovery methods
// retain their method set. Embedding only InboxBackend would hide them.
type directTextCheckpointRedisBackend struct {
	*redisInboxBackend
	gate *directTextSendCheckpoint
}

func (backend *directTextCheckpointRedisBackend) Store(to string, entry inboxMessage) (InboxStoreResult, error) {
	result, err := backend.redisInboxBackend.Store(to, entry)
	if err == nil {
		err = backend.gate.afterCommit(to, entry, result)
	}
	return result, err
}

// Ordinary direct text uses the protected ACK-custody path. Override it too;
// promoting the embedded method would acknowledge around the checkpoint.
func (backend *directTextCheckpointRedisBackend) StoreAckCustody(to string, entry inboxMessage, dedupeKey string) (InboxStoreResult, inboxMessage, error) {
	result, stored, err := backend.redisInboxBackend.StoreAckCustody(to, entry, dedupeKey)
	if err == nil {
		err = backend.gate.afterCommit(to, stored, result)
	}
	return result, stored, err
}

func (gate *directTextSendCheckpoint) serve(writer http.ResponseWriter, request *http.Request) {
	if request.Method == http.MethodGet {
		writer.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(writer).Encode(gate.snapshot())
		return
	}
	if request.Method != http.MethodPost {
		http.Error(writer, "method rejected", http.StatusMethodNotAllowed)
		return
	}
	var command struct {
		Op              string `json:"op"`
		RecipientSHA256 string `json:"recipientSha256"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(writer, request.Body, 1024))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&command) != nil {
		http.Error(writer, "command rejected", http.StatusBadRequest)
		return
	}
	switch command.Op {
	case "arm":
		if gate.arm(command.RecipientSHA256) != nil {
			http.Error(writer, "arm rejected", http.StatusConflict)
			return
		}
	case "release":
		gate.releaseHeld()
	default:
		http.Error(writer, "operation rejected", http.StatusBadRequest)
		return
	}
	writer.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(writer).Encode(gate.snapshot())
}
