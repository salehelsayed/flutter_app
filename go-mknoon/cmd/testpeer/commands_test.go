package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mknoon/go-mknoon/identity"
	"github.com/mknoon/go-mknoon/node"
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

func TestHandleCommandGroupJoinNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("group_join", map[string]interface{}{
		"groupId": "group-1",
	})

	if result["ok"] != false {
		t.Error("expected ok=false without node")
	}
}

func TestHandleCommandGroupJoinMissingParams(t *testing.T) {
	state = &peerState{
		node: node.NewNode(),
	}
	result := handleCommand("group_join", map[string]interface{}{
		"groupId": "group-1",
	})

	if result["ok"] != false {
		t.Error("expected ok=false for missing group config")
	}
}

func TestHandleCommandGroupPublishWithoutIdentity(t *testing.T) {
	state = &peerState{
		node: node.NewNode(),
	}
	result := handleCommand("group_publish", map[string]interface{}{
		"groupId": "group-1",
		"text":    "hello",
	})

	if result["ok"] != false {
		t.Error("expected ok=false without identity")
	}
}

func TestHandleCommandGroupInboxStoreMissingText(t *testing.T) {
	state = &peerState{
		node:     node.NewNode(),
		identity: &identity.Identity{PeerId: "peer-1234"},
	}
	result := handleCommand("group_inbox_store", map[string]interface{}{
		"groupId": "group-1",
	})

	if result["ok"] != false {
		t.Error("expected ok=false for missing text")
	}
}

func TestHandleCommandGroupInboxStoreMissingRecipients(t *testing.T) {
	state = &peerState{
		node:     node.NewNode(),
		identity: &identity.Identity{PeerId: "peer-1234"},
	}
	result := handleCommand("group_inbox_store", map[string]interface{}{
		"groupId": "group-1",
		"text":    "hello",
	})

	if result["ok"] != false {
		t.Error("expected ok=false for missing recipientPeerIds")
	}
	if result["errorMessage"] != "missing recipientPeerIds" {
		t.Fatalf("errorMessage = %v, want missing recipientPeerIds", result["errorMessage"])
	}
}

func TestInboxStoreOutcomeResultExposesDetailedFields(t *testing.T) {
	result := inboxStoreOutcomeResult(node.InboxStoreOutcome{
		StoreStatus: "stored",
		ErrorCode:   "INBOX_FULL",
		ExpiresAtMs: 12345,
		Occupancy:   2,
		Capacity:    100,
	})

	if result["storeStatus"] != "stored" {
		t.Fatalf("storeStatus = %v, want stored", result["storeStatus"])
	}
	if result["errorCode"] != "INBOX_FULL" {
		t.Fatalf("errorCode = %v, want INBOX_FULL", result["errorCode"])
	}
	if result["expiresAtMs"] != int64(12345) ||
		result["occupancy"] != 2 ||
		result["capacity"] != 100 {
		t.Fatalf("metadata = %#v", result)
	}
}

func TestHandleCommandGroupInboxStoreMissingGroupKey(t *testing.T) {
	state = &peerState{
		node:     node.NewNode(),
		identity: &identity.Identity{PeerId: "peer-1234"},
	}
	result := handleCommand("group_inbox_store", map[string]interface{}{
		"groupId":          "group-1",
		"text":             "hello",
		"recipientPeerIds": []interface{}{"peer-2"},
	})

	if result["ok"] != false {
		t.Error("expected ok=false for missing groupKey")
	}
	if result["errorMessage"] != "missing groupKey" {
		t.Fatalf("errorMessage = %v, want missing groupKey", result["errorMessage"])
	}
}

func TestStringSliceParamDedupesJsonLists(t *testing.T) {
	got := stringSliceParam(map[string]interface{}{
		"recipientPeerIds": []interface{}{"peer-2", "", "peer-2", "peer-3", 4},
	}, "recipientPeerIds")

	if len(got) != 2 || got[0] != "peer-2" || got[1] != "peer-3" {
		t.Fatalf("recipientPeerIds = %#v, want [peer-2 peer-3]", got)
	}
}

func TestBuildGroupOfflineReplayEnvelopeSignsEncryptedReplay(t *testing.T) {
	id, err := identity.GenerateIdentity()
	if err != nil {
		t.Fatalf("generate identity: %v", err)
	}
	state = &peerState{identity: id}

	const plaintext = `{"groupId":"group-1","messageId":"m1","text":"secret"}`
	envelope, err := buildGroupOfflineReplayEnvelope(
		"group-1",
		plaintext,
		"m1",
		1,
		"MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=",
		[]string{"peer-2", "peer-3"},
	)
	if err != nil {
		t.Fatalf("build envelope: %v", err)
	}
	if strings.Contains(envelope, "secret") {
		t.Fatalf("envelope leaked plaintext: %s", envelope)
	}

	var decoded map[string]interface{}
	if err := json.Unmarshal([]byte(envelope), &decoded); err != nil {
		t.Fatalf("decode envelope: %v", err)
	}
	if decoded["kind"] != "group_offline_replay" ||
		decoded["payloadType"] != "group_message" ||
		decoded["signatureAlgorithm"] != "ed25519" {
		t.Fatalf("unexpected envelope metadata: %#v", decoded)
	}
	if decoded["signedPayload"] == "" || decoded["signature"] == "" {
		t.Fatalf("expected signedPayload and signature: %#v", decoded)
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

func TestHandleCommandWaitMessageParsesV1Payload(t *testing.T) {
	state = &peerState{
		collector: newMessageCollector(),
	}

	envelope, messageID, err := buildV1Envelope(
		"hello plaintext",
		"peer1",
		"Peer One",
		nil,
	)
	if err != nil {
		t.Fatalf("build v1 envelope: %v", err)
	}
	state.collector.messages = append(state.collector.messages, incomingMessage{
		From:    "peer1",
		To:      "peer2",
		Content: envelope,
	})

	result := handleCommand("wait_message", map[string]interface{}{
		"fromPeerId": "peer1",
		"timeoutSec": 1,
	})
	if result["ok"] != true {
		t.Fatalf("expected ok=true, got errorMessage=%v", result["errorMessage"])
	}
	if result["version"] != "1" || result["decrypted"] != false {
		t.Fatalf("unexpected parsed metadata: %#v", result)
	}
	if result["payloadText"] != "hello plaintext" {
		t.Errorf("payloadText=%v", result["payloadText"])
	}
	if result["messageId"] != messageID {
		t.Errorf("messageId=%v, want %s", result["messageId"], messageID)
	}
}

func TestHandleCommandWaitMessageDecryptsV2Payload(t *testing.T) {
	state = &peerState{
		collector: newMessageCollector(),
	}
	keygen := handleCommand("mlkem_keygen", nil)
	if keygen["ok"] != true {
		t.Fatalf("mlkem_keygen failed: %v", keygen["errorMessage"])
	}

	envelope, messageID, err := buildV2Envelope(
		"hello encrypted",
		"peer1",
		"Peer One",
		state.mlKemPublicKey,
		nil,
	)
	if err != nil {
		t.Fatalf("build v2 envelope: %v", err)
	}
	state.collector.messages = append(state.collector.messages, incomingMessage{
		From:    "peer1",
		To:      "peer2",
		Content: envelope,
	})

	result := handleCommand("wait_message", map[string]interface{}{
		"fromPeerId": "peer1",
		"timeoutSec": 1,
	})
	if result["ok"] != true {
		t.Fatalf("expected ok=true, got errorMessage=%v", result["errorMessage"])
	}
	if result["version"] != "2" || result["decrypted"] != true {
		t.Fatalf("unexpected parsed metadata: %#v", result)
	}
	if result["payloadText"] != "hello encrypted" {
		t.Errorf("payloadText=%v", result["payloadText"])
	}
	if result["messageId"] != messageID {
		t.Errorf("messageId=%v, want %s", result["messageId"], messageID)
	}
	if _, ok := result["parseError"]; ok {
		t.Errorf("unexpected parseError: %v", result["parseError"])
	}
}

func TestHandleCommandGetMessagesEnrichesV2PayloadMedia(t *testing.T) {
	state = &peerState{
		collector: newMessageCollector(),
	}
	keygen := handleCommand("mlkem_keygen", nil)
	if keygen["ok"] != true {
		t.Fatalf("mlkem_keygen failed: %v", keygen["errorMessage"])
	}

	envelope, _, err := buildV2Envelope(
		"message with media",
		"peer1",
		"Peer One",
		state.mlKemPublicKey,
		map[string]interface{}{
			"media": []map[string]interface{}{
				{
					"id":        "blob-1",
					"mime":      "image/png",
					"mediaType": "image",
				},
			},
		},
	)
	if err != nil {
		t.Fatalf("build v2 envelope: %v", err)
	}
	state.collector.messages = append(state.collector.messages, incomingMessage{
		From:    "peer1",
		To:      "peer2",
		Content: envelope,
	})

	result := handleCommand("get_messages", nil)
	if result["ok"] != true {
		t.Fatalf("expected ok=true, got errorMessage=%v", result["errorMessage"])
	}
	messages, ok := result["messages"].([]map[string]interface{})
	if !ok || len(messages) != 1 {
		t.Fatalf("unexpected messages payload: %#v", result["messages"])
	}
	message := messages[0]
	if message["version"] != "2" || message["decrypted"] != true {
		t.Fatalf("unexpected parsed metadata: %#v", message)
	}
	if message["payloadText"] != "message with media" {
		t.Errorf("payloadText=%v", message["payloadText"])
	}
	media, ok := message["payloadMedia"].([]interface{})
	if !ok || len(media) != 1 {
		t.Fatalf("payloadMedia=%#v", message["payloadMedia"])
	}
	attachment, ok := media[0].(map[string]interface{})
	if !ok || attachment["id"] != "blob-1" || attachment["mediaType"] != "image" {
		t.Fatalf("unexpected media attachment: %#v", media[0])
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

func TestHandleCommandUnregisterNotStarted(t *testing.T) {
	state = &peerState{}
	result := handleCommand("unregister", nil)
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

// TestHandleCommandBlobRoundTrip — 112 Phase 5.2 harness pin: ciphertext
// from blob_encrypt is opaque (≠ plaintext) until blob_decrypt is applied,
// and a wrong key fails closed. This is what lets the two-device script
// prove relay-at-rest opacity through real media_upload/media_download.
func TestHandleCommandBlobRoundTrip(t *testing.T) {
	dir := t.TempDir()
	plaintext := []byte("testpeer blob harness round trip")
	srcPath := filepath.Join(dir, "fixture.bin")
	if err := os.WriteFile(srcPath, plaintext, 0o600); err != nil {
		t.Fatal(err)
	}

	keygen := handleCommand("blob_keygen", nil)
	if keygen["ok"] != true {
		t.Fatalf("blob_keygen: %v", keygen)
	}
	key := keygen["keyBase64"].(string)

	enc := handleCommand("blob_encrypt", map[string]interface{}{
		"filePath":  srcPath,
		"keyBase64": key,
	})
	if enc["ok"] != true {
		t.Fatalf("blob_encrypt: %v", enc)
	}
	encryptedPath := enc["encryptedPath"].(string)
	nonce := enc["nonce"].(string)

	ciphertext, err := os.ReadFile(encryptedPath)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Equal(ciphertext, plaintext) {
		t.Fatal("encrypted artifact equals plaintext — cannot prove relay opacity")
	}

	dec := handleCommand("blob_decrypt", map[string]interface{}{
		"filePath":  encryptedPath,
		"keyBase64": key,
		"nonce":     nonce,
	})
	if dec["ok"] != true {
		t.Fatalf("blob_decrypt: %v", dec)
	}
	roundTripped, err := os.ReadFile(dec["decryptedPath"].(string))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(roundTripped, plaintext) {
		t.Fatal("decrypted bytes differ from plaintext")
	}

	wrongKey := handleCommand("blob_keygen", nil)["keyBase64"].(string)
	badDec := handleCommand("blob_decrypt", map[string]interface{}{
		"filePath":  encryptedPath,
		"keyBase64": wrongKey,
		"nonce":     nonce,
	})
	if badDec["ok"] == true {
		t.Fatal("blob_decrypt succeeded with the wrong key")
	}
}
