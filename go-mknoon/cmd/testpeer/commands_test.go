package main

import (
	"encoding/json"
	"testing"
)

// TestHandleCommandUnknown verifies unknown commands return an error.
func TestHandleCommandUnknown(t *testing.T) {
	result := handleCommand("nonexistent_command", nil)
	if result["ok"] != false {
		t.Errorf("expected ok=false for unknown command")
	}
	msg, _ := result["errorMessage"].(string)
	if msg == "" {
		t.Error("expected errorMessage")
	}
}

// TestHandleCommandGenerateIdentity verifies identity generation.
func TestHandleCommandGenerateIdentity(t *testing.T) {
	// Reset global state.
	state = &peerState{}

	result := handleCommand("generate_identity", nil)
	if result["ok"] != true {
		t.Fatalf("expected ok=true, got errorMessage=%v", result["errorMessage"])
	}

	peerId, _ := result["peerId"].(string)
	if peerId == "" {
		t.Error("expected non-empty peerId")
	}
	if state.identity == nil {
		t.Error("state.identity should be set")
	}
	if state.privateKeyHex == "" {
		t.Error("state.privateKeyHex should be set")
	}
}

// TestHandleCommandRestoreIdentity verifies identity restoration from mnemonic.
func TestHandleCommandRestoreIdentity(t *testing.T) {
	state = &peerState{}

	// First generate to get a valid mnemonic.
	gen := handleCommand("generate_identity", nil)
	mnemonic, _ := gen["mnemonic12"].(string)
	peerId1, _ := gen["peerId"].(string)

	// Reset and restore.
	state = &peerState{}
	result := handleCommand("restore_identity", map[string]interface{}{
		"mnemonic12": mnemonic,
	})

	if result["ok"] != true {
		t.Fatalf("expected ok=true, got errorMessage=%v", result["errorMessage"])
	}

	peerId2, _ := result["peerId"].(string)
	if peerId2 != peerId1 {
		t.Errorf("restored peerId=%s, want %s", peerId2, peerId1)
	}
}

// TestHandleCommandRestoreIdentityMissingMnemonic verifies error on missing input.
func TestHandleCommandRestoreIdentityMissingMnemonic(t *testing.T) {
	state = &peerState{}
	result := handleCommand("restore_identity", nil)
	if result["ok"] != false {
		t.Error("expected ok=false for missing mnemonic")
	}
}

// TestHandleCommandMlKemKeygen verifies ML-KEM key generation.
func TestHandleCommandMlKemKeygen(t *testing.T) {
	state = &peerState{}
	result := handleCommand("mlkem_keygen", nil)

	if result["ok"] != true {
		t.Fatalf("expected ok=true, got errorMessage=%v", result["errorMessage"])
	}

	pk, _ := result["publicKey"].(string)
	sk, _ := result["secretKey"].(string)
	if pk == "" || sk == "" {
		t.Error("expected non-empty publicKey and secretKey")
	}
	if state.mlKemPublicKey == "" || state.mlKemSecretKey == "" {
		t.Error("state ML-KEM keys should be set")
	}
}

// TestHandleCommandStatusNotStarted verifies status when node is not started.
func TestHandleCommandStatusNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("status", nil)

	if result["ok"] != true {
		t.Error("status should always return ok=true")
	}
	if result["isStarted"] != false {
		t.Error("expected isStarted=false")
	}
}

// TestHandleCommandStartWithoutIdentity verifies error when starting without identity.
func TestHandleCommandStartWithoutIdentity(t *testing.T) {
	state = &peerState{}
	result := handleCommand("start", nil)

	if result["ok"] != false {
		t.Error("expected ok=false without identity")
	}
}

// TestHandleCommandGetMessagesEmpty verifies empty message list.
func TestHandleCommandGetMessagesEmpty(t *testing.T) {
	state = &peerState{}
	result := handleCommand("get_messages", nil)

	if result["ok"] != true {
		t.Error("expected ok=true")
	}
	count, _ := result["count"].(int)
	if count != 0 {
		t.Errorf("expected count=0, got %d", count)
	}
}

// TestHandleCommandClearMessages verifies clearing messages.
func TestHandleCommandClearMessages(t *testing.T) {
	state = &peerState{
		collector: newMessageCollector(),
	}
	// Add a fake message.
	state.collector.mu.Lock()
	state.collector.messages = append(state.collector.messages, incomingMessage{
		From: "peer1", Content: "test",
	})
	state.collector.mu.Unlock()

	result := handleCommand("clear_messages", nil)
	if result["ok"] != true {
		t.Error("expected ok=true")
	}

	msgs := state.collector.getMessages()
	if len(msgs) != 0 {
		t.Errorf("expected 0 messages after clear, got %d", len(msgs))
	}
}

// TestHandleCommandReconnectRelaysNotStarted verifies error when node is not started.
func TestHandleCommandReconnectRelaysNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("reconnect_relays", nil)
	if result["ok"] != false {
		t.Error("expected ok=false without node")
	}
}

// TestHandleCommandDisconnectNotStarted verifies error when node is not started.
func TestHandleCommandDisconnectNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("disconnect", map[string]interface{}{
		"peerId": "12D3KooWTest",
	})
	if result["ok"] != false {
		t.Error("expected ok=false without node")
	}
}

// TestHandleCommandDisconnectMissingPeerId verifies error on missing peerId.
func TestHandleCommandDisconnectMissingPeerId(t *testing.T) {
	state = &peerState{}
	result := handleCommand("disconnect", nil)
	if result["ok"] != false {
		t.Error("expected ok=false for missing peerId")
	}
}

// TestHandleCommandMediaUploadNotStarted verifies error when node is not started.
func TestHandleCommandMediaUploadNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("media_upload", map[string]interface{}{
		"id":       "test-id",
		"toPeerId": "12D3KooWTest",
		"mime":     "image/png",
		"filePath": "/tmp/test.png",
	})
	if result["ok"] != false {
		t.Error("expected ok=false without node")
	}
}

// TestHandleCommandMediaUploadMissingParams verifies error on missing params.
func TestHandleCommandMediaUploadMissingParams(t *testing.T) {
	state = &peerState{}
	result := handleCommand("media_upload", nil)
	if result["ok"] != false {
		t.Error("expected ok=false for missing params")
	}
}

// TestHandleCommandMediaDownloadNotStarted verifies error when node is not started.
func TestHandleCommandMediaDownloadNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("media_download", map[string]interface{}{
		"id":         "test-id",
		"outputPath": "/tmp/test.png",
	})
	if result["ok"] != false {
		t.Error("expected ok=false without node")
	}
}

// TestHandleCommandMediaDownloadMissingParams verifies error on missing params.
func TestHandleCommandMediaDownloadMissingParams(t *testing.T) {
	state = &peerState{}
	result := handleCommand("media_download", nil)
	if result["ok"] != false {
		t.Error("expected ok=false for missing params")
	}
}

// TestHandleCommandMediaDeleteNotStarted verifies error when node is not started.
func TestHandleCommandMediaDeleteNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("media_delete", map[string]interface{}{
		"id": "test-id",
	})
	if result["ok"] != false {
		t.Error("expected ok=false without node")
	}
}

// TestHandleCommandMediaDeleteMissingId verifies error on missing id.
func TestHandleCommandMediaDeleteMissingId(t *testing.T) {
	state = &peerState{}
	result := handleCommand("media_delete", nil)
	if result["ok"] != false {
		t.Error("expected ok=false for missing id")
	}
}

// TestHandleCommandMediaListNotStarted verifies error when node is not started.
func TestHandleCommandMediaListNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("media_list", nil)
	if result["ok"] != false {
		t.Error("expected ok=false without node")
	}
}

// TestHandleCommandProfileUploadNotStarted verifies error when node is not started.
func TestHandleCommandProfileUploadNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("profile_upload", map[string]interface{}{
		"mime":     "image/jpeg",
		"filePath": "/tmp/test.jpg",
	})
	if result["ok"] != false {
		t.Error("expected ok=false without node")
	}
}

// TestHandleCommandProfileUploadMissingParams verifies error on missing params.
func TestHandleCommandProfileUploadMissingParams(t *testing.T) {
	state = &peerState{}
	result := handleCommand("profile_upload", nil)
	if result["ok"] != false {
		t.Error("expected ok=false for missing params")
	}
}

// TestHandleCommandProfileDownloadNotStarted verifies error when node is not started.
func TestHandleCommandProfileDownloadNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("profile_download", map[string]interface{}{
		"ownerPeerId": "12D3KooWTest",
		"outputPath":  "/tmp/test.jpg",
	})
	if result["ok"] != false {
		t.Error("expected ok=false without node")
	}
}

// TestHandleCommandProfileDownloadMissingParams verifies error on missing params.
func TestHandleCommandProfileDownloadMissingParams(t *testing.T) {
	state = &peerState{}
	result := handleCommand("profile_download", nil)
	if result["ok"] != false {
		t.Error("expected ok=false for missing params")
	}
}

// TestCommandResponseFormat verifies responses are valid JSON with expected structure.
func TestCommandResponseFormat(t *testing.T) {
	state = &peerState{}

	tests := []struct {
		cmd    string
		params map[string]interface{}
	}{
		{"generate_identity", nil},
		{"mlkem_keygen", nil},
		{"status", nil},
		{"get_messages", nil},
		{"clear_messages", nil},
	}

	for _, tc := range tests {
		result := handleCommand(tc.cmd, tc.params)

		// Verify the result can be serialized to JSON.
		b, err := json.Marshal(result)
		if err != nil {
			t.Errorf("cmd=%s: marshal error: %v", tc.cmd, err)
			continue
		}

		// Verify it can be parsed back.
		var parsed map[string]interface{}
		if err := json.Unmarshal(b, &parsed); err != nil {
			t.Errorf("cmd=%s: unmarshal error: %v", tc.cmd, err)
			continue
		}

		// Must have "ok" field.
		if _, ok := parsed["ok"]; !ok {
			t.Errorf("cmd=%s: missing ok field", tc.cmd)
		}
	}
}
