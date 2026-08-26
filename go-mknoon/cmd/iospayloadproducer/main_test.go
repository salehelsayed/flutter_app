package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

func TestProducePayloadUsesRealV2EncryptionAndOmitsHandoffSecrets(t *testing.T) {
	keys, err := mcrypto.MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen: %v", err)
	}
	const receiverPeer = "12D3KooWLTW8pKJrjG3FQqY8Qp8Fs7yWqjWq6sXg88hn6Qoq9p2A"
	request := providerRequest{
		Schema:              requestSchema,
		ExpectedTitle:       "New private message",
		ExpectedBody:        "Open Mknoon to read it",
		ExpectedMessageText: "exact private SIMS message",
		ReceiverDeviceID:    "00008150-001C3C6A3684401C",
		PeerDeviceID:        receiverPeer,
	}
	handoff := receiverHandoff{
		Schema:                    handoffSchema,
		CaptureNonce:              "capture-nonce-1234",
		ReceiverDeviceID:          request.ReceiverDeviceID,
		PeerDeviceID:              receiverPeer,
		BundleID:                  bundleID,
		APNSEnvironment:           "development",
		APNSDeviceToken:           strings.Repeat("ab", 32),
		MLKemPublicKey:            keys.PublicKey,
		NotificationAuthorization: "authorized",
		NotificationAlertSetting:  "enabled",
		NotificationBadgeSetting:  "enabled",
		CapturedAt:                time.Now().UTC().Format(time.RFC3339Nano),
	}

	encoded, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce")
	if err != nil {
		t.Fatalf("producePayload: %v", err)
	}
	if len(encoded) > 4096 {
		t.Fatalf("payload has %d bytes", len(encoded))
	}
	if strings.Contains(string(encoded), request.ExpectedMessageText) {
		t.Fatal("APNs payload exposed message plaintext")
	}
	if strings.Contains(string(encoded), handoff.APNSDeviceToken) {
		t.Fatal("APNs payload copied the device token")
	}
	if strings.Contains(string(encoded), handoff.MLKemPublicKey) {
		t.Fatal("APNs payload copied the receiver public key")
	}

	var payload apnsPayload
	if err := json.Unmarshal(encoded, &payload); err != nil {
		t.Fatalf("decode APNs payload: %v", err)
	}
	if payload.FixtureSchema != payloadSchema || payload.Type != "new_message" || payload.APS.MutableContent != 1 {
		t.Fatalf("unexpected APNs route: %#v", payload)
	}
	if payload.APS.Alert.Title != request.ExpectedTitle || payload.APS.Alert.Body != request.ExpectedBody {
		t.Fatal("APNs alert does not match provider request")
	}
	if _, err := peer.Decode(payload.SenderID); err != nil {
		t.Fatalf("sender is not a valid libp2p peer ID: %v", err)
	}

	plaintext, err := mcrypto.DecryptMessage(keys.SecretKey, payload.Kem, payload.Ciphertext, payload.Nonce)
	if err != nil {
		t.Fatalf("DecryptMessage: %v", err)
	}
	var inner innerMessage
	if err := json.Unmarshal([]byte(plaintext), &inner); err != nil {
		t.Fatalf("decode inner chat message: %v", err)
	}
	if inner.ID != payload.MessageID || inner.SenderPeerID != payload.SenderID ||
		inner.Text != request.ExpectedMessageText || inner.SenderUsername != request.ExpectedTitle {
		t.Fatalf("inner/outer chat parity mismatch: %#v", inner)
	}
}

func TestTC396ProductionShapedBackgroundPayload(t *testing.T) {
	keys, err := mcrypto.MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen: %v", err)
	}
	const receiverPeer = "12D3KooWLTW8pKJrjG3FQqY8Qp8Fs7yWqjWq6sXg88hn6Qoq9p2A"
	request := providerRequest{
		Schema:              requestSchema,
		ExpectedTitle:       "New private message",
		ExpectedBody:        "Open Mknoon to read it",
		ExpectedMessageText: "TC-396 encrypted private message",
		ReceiverDeviceID:    "00008150-001C3C6A3684401C",
		PeerDeviceID:        receiverPeer,
	}
	handoff := receiverHandoff{
		Schema:                    handoffSchema,
		CaptureNonce:              "tc396-capture-nonce",
		ReceiverDeviceID:          request.ReceiverDeviceID,
		PeerDeviceID:              receiverPeer,
		BundleID:                  bundleID,
		APNSEnvironment:           "development",
		APNSDeviceToken:           strings.Repeat("cd", 32),
		MLKemPublicKey:            keys.PublicKey,
		NotificationAuthorization: "authorized",
		NotificationAlertSetting:  "enabled",
		NotificationBadgeSetting:  "enabled",
		CapturedAt:                time.Now().UTC().Format(time.RFC3339Nano),
	}

	encoded, err := producePayload(
		request,
		handoff,
		"tc396-production-shaped-run",
		"tc396-production-shaped-nonce",
	)
	if err != nil {
		t.Fatalf("producePayload: %v", err)
	}
	if len(encoded) > 4096 {
		t.Fatalf("production-shaped payload has %d bytes, want <= 4096", len(encoded))
	}
	gcmMessageIDOccurrences := strings.Count(string(encoded), `"gcm.message_id"`)
	for label, secret := range map[string]string{
		"message plaintext":       request.ExpectedMessageText,
		"APNs device token":       handoff.APNSDeviceToken,
		"receiver public key":     handoff.MLKemPublicKey,
		"receiver capture nonce":  handoff.CaptureNonce,
		"producer run identifier": "tc396-production-shaped-run",
		"producer nonce":          "tc396-production-shaped-nonce",
	} {
		if strings.Contains(string(encoded), secret) {
			t.Fatalf("production-shaped payload exposed %s", label)
		}
	}

	var shape map[string]any
	if err := json.Unmarshal(encoded, &shape); err != nil {
		t.Fatalf("decode APNs shape: %v", err)
	}
	aps, ok := shape["aps"].(map[string]any)
	if !ok {
		t.Fatalf("aps = %#v, want object", shape["aps"])
	}
	if got := aps["mutable-content"]; got != float64(1) {
		t.Fatalf("aps.mutable-content = %#v, want 1", got)
	}
	if got := aps["content-available"]; got != float64(1) {
		t.Errorf("aps.content-available = %#v, want 1", got)
	}
	alert, ok := aps["alert"].(map[string]any)
	if !ok || alert["title"] != request.ExpectedTitle || alert["body"] != request.ExpectedBody {
		t.Fatalf("aps.alert = %#v, want exact bounded provider alert", aps["alert"])
	}
	gcmMessageID, ok := shape["gcm.message_id"].(string)
	if gcmMessageIDOccurrences != 1 || !ok || strings.TrimSpace(gcmMessageID) != gcmMessageID ||
		len([]byte(gcmMessageID)) == 0 || len([]byte(gcmMessageID)) > 64 {
		t.Errorf(
			"gcm.message_id occurrences=%d value=%#v, want exactly one nonempty trimmed <=64-byte synthetic ID",
			gcmMessageIDOccurrences,
			shape["gcm.message_id"],
		)
	}

	var payload apnsPayload
	if err := json.Unmarshal(encoded, &payload); err != nil {
		t.Fatalf("decode typed APNs payload: %v", err)
	}
	if payload.FixtureSchema != payloadSchema || payload.Type != "new_message" ||
		payload.MessageID == "" || payload.SenderID == "" || payload.Kem == "" ||
		payload.Ciphertext == "" || payload.Nonce == "" {
		t.Fatalf("production-shaped fixture lost encrypted rich route: %#v", payload)
	}
	plaintext, err := mcrypto.DecryptMessage(
		keys.SecretKey,
		payload.Kem,
		payload.Ciphertext,
		payload.Nonce,
	)
	if err != nil {
		t.Fatalf("DecryptMessage: %v", err)
	}
	var inner innerMessage
	if err := json.Unmarshal([]byte(plaintext), &inner); err != nil {
		t.Fatalf("decode inner chat message: %v", err)
	}
	if inner.ID != payload.MessageID || inner.SenderPeerID != payload.SenderID ||
		inner.Text != request.ExpectedMessageText || inner.SenderUsername != request.ExpectedTitle {
		t.Fatalf("production-shaped inner/outer parity mismatch: %#v", inner)
	}
}

func TestProducePayloadRequiresExactly32DecodedAPNSTokenBytes(t *testing.T) {
	keys, err := mcrypto.MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen: %v", err)
	}
	const receiverPeer = "12D3KooWLTW8pKJrjG3FQqY8Qp8Fs7yWqjWq6sXg88hn6Qoq9p2A"
	request := providerRequest{
		Schema:              requestSchema,
		ExpectedTitle:       "Title",
		ExpectedBody:        "Body",
		ExpectedMessageText: "private text",
		ReceiverDeviceID:    "00008150-001C3C6A3684401C",
		PeerDeviceID:        receiverPeer,
	}
	handoff := receiverHandoff{
		Schema:                    handoffSchema,
		CaptureNonce:              "capture-nonce-1234",
		ReceiverDeviceID:          request.ReceiverDeviceID,
		PeerDeviceID:              receiverPeer,
		BundleID:                  bundleID,
		APNSEnvironment:           "development",
		MLKemPublicKey:            keys.PublicKey,
		NotificationAuthorization: "authorized",
		NotificationAlertSetting:  "enabled",
		NotificationBadgeSetting:  "enabled",
		CapturedAt:                time.Now().UTC().Format(time.RFC3339Nano),
	}
	for name, token := range map[string]string{
		"31 decoded bytes": strings.Repeat("ab", 31),
		"33 decoded bytes": strings.Repeat("ab", 33),
		"non-hex 64 chars": strings.Repeat("zz", 32),
	} {
		t.Run(name, func(t *testing.T) {
			handoff.APNSDeviceToken = token
			if _, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce"); err == nil {
				t.Fatal("invalid APNs token length/encoding was accepted")
			}
		})
	}
	handoff.APNSDeviceToken = strings.Repeat("ab", 32)
	handoff.NotificationAuthorization = "denied"
	if _, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce"); err == nil {
		t.Fatal("denied notification authorization was accepted")
	}
	handoff.NotificationAuthorization = "authorized"
	handoff.NotificationAlertSetting = "disabled"
	if _, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce"); err == nil {
		t.Fatal("disabled notification alerts were accepted")
	}
	handoff.NotificationAlertSetting = "enabled"
	handoff.NotificationBadgeSetting = "disabled"
	if _, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce"); err == nil {
		t.Fatal("disabled notification badges were accepted")
	}
}

func TestProducePayloadRejectsTitleOutsideContactUsernameBound(t *testing.T) {
	keys, err := mcrypto.MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen: %v", err)
	}
	const receiverPeer = "12D3KooWLTW8pKJrjG3FQqY8Qp8Fs7yWqjWq6sXg88hn6Qoq9p2A"
	request := providerRequest{
		Schema:              requestSchema,
		ExpectedTitle:       strings.Repeat("a", 31),
		ExpectedBody:        "Body",
		ExpectedMessageText: "private text",
		ReceiverDeviceID:    "00008150-001C3C6A3684401C",
		PeerDeviceID:        receiverPeer,
	}
	handoff := receiverHandoff{
		Schema:                    handoffSchema,
		CaptureNonce:              "capture-nonce-1234",
		ReceiverDeviceID:          request.ReceiverDeviceID,
		PeerDeviceID:              receiverPeer,
		BundleID:                  bundleID,
		APNSEnvironment:           "development",
		APNSDeviceToken:           strings.Repeat("ab", 32),
		MLKemPublicKey:            keys.PublicKey,
		NotificationAuthorization: "authorized",
		NotificationAlertSetting:  "enabled",
		NotificationBadgeSetting:  "enabled",
		CapturedAt:                time.Now().UTC().Format(time.RFC3339Nano),
	}

	if _, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce"); err == nil {
		t.Fatal("title outside the contact username bound was accepted")
	}

	request.ExpectedTitle = "Title"
	request.ExpectedMessageText = strings.Repeat("m", 141)
	if _, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce"); err == nil {
		t.Fatal("message beyond the NSE preview bound was accepted")
	}

	request.ExpectedMessageText = " private text"
	if _, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce"); err == nil {
		t.Fatal("non-canonical fixture whitespace was accepted")
	}

	request.ExpectedMessageText = "private text"
	request.ExpectedBody = "café"
	if _, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce"); err == nil {
		t.Fatal("cross-language non-ASCII fixture text was accepted")
	}

	request.ExpectedBody = "fallback exposes private text"
	if _, err := producePayload(request, handoff, "major-ios-run", "major-ios-nonce"); err == nil {
		t.Fatal("alert exposing the decrypted message fixture was accepted")
	}
}

func TestExecuteWritesOwnerOnlyPayloadAndRejectsLooseHandoff(t *testing.T) {
	keys, err := mcrypto.MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen: %v", err)
	}
	const receiverPeer = "12D3KooWLTW8pKJrjG3FQqY8Qp8Fs7yWqjWq6sXg88hn6Qoq9p2A"
	directory := t.TempDir()
	requestPath := filepath.Join(directory, "request.json")
	handoffPath := filepath.Join(directory, "handoff.json")
	outputPath := filepath.Join(directory, "private", "payload.json")
	request := providerRequest{
		Schema:              requestSchema,
		ExpectedTitle:       "Title",
		ExpectedBody:        "Body",
		ExpectedMessageText: "private text",
		ReceiverDeviceID:    "00008150-001C3C6A3684401C",
		PeerDeviceID:        receiverPeer,
	}
	handoff := receiverHandoff{
		Schema:                    handoffSchema,
		CaptureNonce:              "capture-nonce-1234",
		ReceiverDeviceID:          request.ReceiverDeviceID,
		PeerDeviceID:              receiverPeer,
		BundleID:                  bundleID,
		APNSEnvironment:           "development",
		APNSDeviceToken:           strings.Repeat("cd", 32),
		MLKemPublicKey:            keys.PublicKey,
		NotificationAuthorization: "authorized",
		NotificationAlertSetting:  "enabled",
		NotificationBadgeSetting:  "enabled",
		CapturedAt:                time.Now().UTC().Format(time.RFC3339Nano),
	}
	writeJSON := func(path string, value any, mode os.FileMode) {
		t.Helper()
		encoded, marshalErr := json.Marshal(value)
		if marshalErr != nil {
			t.Fatalf("marshal: %v", marshalErr)
		}
		if writeErr := os.WriteFile(path, encoded, mode); writeErr != nil {
			t.Fatalf("write: %v", writeErr)
		}
		if chmodErr := os.Chmod(path, mode); chmodErr != nil {
			t.Fatalf("chmod: %v", chmodErr)
		}
	}
	writeJSON(requestPath, request, 0o600)
	writeJSON(handoffPath, handoff, 0o600)
	args := []string{
		"--provider-request", requestPath,
		"--receiver-handoff", handoffPath,
		"--run-id", "major-ios-run",
		"--nonce", "major-ios-nonce",
		"--output", outputPath,
	}
	if err := execute(args); err != nil {
		t.Fatalf("execute: %v", err)
	}
	info, err := os.Stat(outputPath)
	if err != nil {
		t.Fatalf("stat output: %v", err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Fatalf("output mode = %04o, want 0600", got)
	}

	if err := os.Chmod(handoffPath, 0o644); err != nil {
		t.Fatalf("loosen handoff: %v", err)
	}
	if err := execute(args); err == nil || !strings.Contains(err.Error(), "private regular file") {
		t.Fatalf("loose handoff error = %v", err)
	}
}

func TestDecodeExactJSONRejectsDuplicateTopLevelContractFields(t *testing.T) {
	t.Run("provider request schema", func(t *testing.T) {
		var request providerRequest
		err := decodeExactJSON(
			[]byte(`{"schema":"first","schema":"second"}`),
			&request,
		)
		if err == nil {
			t.Fatal("duplicate provider request field was accepted")
		}
	})

	t.Run("receiver handoff capture nonce", func(t *testing.T) {
		var handoff receiverHandoff
		err := decodeExactJSON(
			[]byte(`{"captureNonce":"first","captureNonce":"second"}`),
			&handoff,
		)
		if err == nil {
			t.Fatal("duplicate receiver handoff field was accepted")
		}
	})
}
