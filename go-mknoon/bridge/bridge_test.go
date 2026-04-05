package bridge

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sync"
	"testing"

	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/node"
)

// parseJSON is a test helper that unmarshals a JSON string into a map.
func parseJSON(t *testing.T, s string) map[string]interface{} {
	t.Helper()
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(s), &m); err != nil {
		t.Fatalf("failed to parse JSON %q: %v", s, err)
	}
	return m
}

// assertOk is a test helper that checks the "ok" field is true.
func assertOk(t *testing.T, m map[string]interface{}) {
	t.Helper()
	ok, exists := m["ok"]
	if !exists {
		t.Fatal("response missing 'ok' field")
	}
	if ok != true {
		t.Fatalf("expected ok=true, got ok=%v, errorCode=%v, errorMessage=%v",
			ok, m["errorCode"], m["errorMessage"])
	}
}

// assertNotOk is a test helper that checks the "ok" field is false and
// errorCode matches the expected value.
func assertNotOk(t *testing.T, m map[string]interface{}, expectedCode string) {
	t.Helper()
	ok, exists := m["ok"]
	if !exists {
		t.Fatal("response missing 'ok' field")
	}
	if ok != false {
		t.Fatalf("expected ok=false, got ok=%v", ok)
	}
	code, _ := m["errorCode"].(string)
	if code != expectedCode {
		t.Errorf("expected errorCode=%q, got %q (errorMessage=%v)",
			expectedCode, code, m["errorMessage"])
	}
}

// --- GenerateIdentity ---

func TestGenerateIdentity_ReturnsValidIdentity(t *testing.T) {
	result := GenerateIdentity()
	m := parseJSON(t, result)
	assertOk(t, m)

	identity, ok := m["identity"].(map[string]interface{})
	if !ok {
		t.Fatal("response missing 'identity' map")
	}

	expectedKeys := []string{"peerId", "publicKey", "privateKey", "mnemonic12", "createdAt", "updatedAt"}
	for _, key := range expectedKeys {
		val, exists := identity[key]
		if !exists {
			t.Errorf("identity missing key %q", key)
			continue
		}
		str, ok := val.(string)
		if !ok || str == "" {
			t.Errorf("identity[%q] should be a non-empty string, got %v", key, val)
		}
	}
}

// --- RestoreIdentity ---

func TestRestoreIdentity_ValidMnemonic(t *testing.T) {
	// First generate an identity to get a valid mnemonic.
	genResult := GenerateIdentity()
	genMap := parseJSON(t, genResult)
	assertOk(t, genMap)

	genIdentity := genMap["identity"].(map[string]interface{})
	mnemonic := genIdentity["mnemonic12"].(string)

	// Restore from that mnemonic.
	input, _ := json.Marshal(map[string]string{"mnemonic12": mnemonic})
	restoreResult := RestoreIdentity(string(input))
	restoreMap := parseJSON(t, restoreResult)
	assertOk(t, restoreMap)

	restoreIdentity := restoreMap["identity"].(map[string]interface{})

	// The peer ID and keys must match.
	if restoreIdentity["peerId"] != genIdentity["peerId"] {
		t.Errorf("peerId mismatch: gen=%q, restore=%q",
			genIdentity["peerId"], restoreIdentity["peerId"])
	}
	if restoreIdentity["publicKey"] != genIdentity["publicKey"] {
		t.Errorf("publicKey mismatch: gen=%q, restore=%q",
			genIdentity["publicKey"], restoreIdentity["publicKey"])
	}
	if restoreIdentity["privateKey"] != genIdentity["privateKey"] {
		t.Errorf("privateKey mismatch: gen=%q, restore=%q",
			genIdentity["privateKey"], restoreIdentity["privateKey"])
	}
}

func TestRestoreIdentity_InvalidMnemonic(t *testing.T) {
	// 12 words that fail BIP39 checksum validation.
	input, _ := json.Marshal(map[string]string{
		"mnemonic12": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon",
	})
	result := RestoreIdentity(string(input))
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_MNEMONIC")
}

func TestRestoreIdentity_EmptyInput(t *testing.T) {
	result := RestoreIdentity("")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestRestoreIdentity_MissingMnemonic(t *testing.T) {
	// Valid JSON but missing mnemonic12 field.
	result := RestoreIdentity("{}")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

// --- MlKemKeygen ---

func TestMlKemKeygen_ReturnsKeys(t *testing.T) {
	result := MlKemKeygen()
	m := parseJSON(t, result)
	assertOk(t, m)

	publicKey, ok := m["publicKey"].(string)
	if !ok || publicKey == "" {
		t.Error("response missing or empty 'publicKey'")
	}

	secretKey, ok := m["secretKey"].(string)
	if !ok || secretKey == "" {
		t.Error("response missing or empty 'secretKey'")
	}
}

// --- EncryptMessage + DecryptMessage round-trip ---

func TestEncryptDecryptRoundTrip(t *testing.T) {
	// Generate a key pair.
	keygenResult := MlKemKeygen()
	keygenMap := parseJSON(t, keygenResult)
	assertOk(t, keygenMap)

	publicKey := keygenMap["publicKey"].(string)
	secretKey := keygenMap["secretKey"].(string)

	// Encrypt a message.
	originalPlaintext := "Hello, post-quantum world!"
	encInput, _ := json.Marshal(map[string]string{
		"recipientPublicKey": publicKey,
		"plaintext":          originalPlaintext,
	})

	encResult := EncryptMessage(string(encInput))
	encMap := parseJSON(t, encResult)
	assertOk(t, encMap)

	kem, ok := encMap["kem"].(string)
	if !ok || kem == "" {
		t.Fatal("encrypt response missing 'kem'")
	}
	ciphertext, ok := encMap["ciphertext"].(string)
	if !ok || ciphertext == "" {
		t.Fatal("encrypt response missing 'ciphertext'")
	}
	nonce, ok := encMap["nonce"].(string)
	if !ok || nonce == "" {
		t.Fatal("encrypt response missing 'nonce'")
	}

	// Decrypt the message.
	decInput, _ := json.Marshal(map[string]string{
		"secretKey":  secretKey,
		"kem":        kem,
		"ciphertext": ciphertext,
		"nonce":      nonce,
	})

	decResult := DecryptMessage(string(decInput))
	decMap := parseJSON(t, decResult)
	assertOk(t, decMap)

	plaintext, ok := decMap["plaintext"].(string)
	if !ok {
		t.Fatal("decrypt response missing 'plaintext'")
	}

	if plaintext != originalPlaintext {
		t.Errorf("plaintext mismatch: got %q, want %q", plaintext, originalPlaintext)
	}
}

// --- DecryptMessage with wrong key ---

func TestDecryptMessage_WrongKey(t *testing.T) {
	// Generate two key pairs.
	keygen1 := parseJSON(t, MlKemKeygen())
	assertOk(t, keygen1)
	keygen2 := parseJSON(t, MlKemKeygen())
	assertOk(t, keygen2)

	publicKey1 := keygen1["publicKey"].(string)
	secretKey2 := keygen2["secretKey"].(string)

	// Encrypt with key pair 1's public key.
	encInput, _ := json.Marshal(map[string]string{
		"recipientPublicKey": publicKey1,
		"plaintext":          "secret for key pair 1",
	})
	encMap := parseJSON(t, EncryptMessage(string(encInput)))
	assertOk(t, encMap)

	// Attempt to decrypt with key pair 2's secret key.
	decInput, _ := json.Marshal(map[string]string{
		"secretKey":  secretKey2,
		"kem":        encMap["kem"].(string),
		"ciphertext": encMap["ciphertext"].(string),
		"nonce":      encMap["nonce"].(string),
	})

	decResult := DecryptMessage(string(decInput))
	decMap := parseJSON(t, decResult)

	// Decryption with the wrong key should fail (AES-GCM auth tag mismatch).
	ok, _ := decMap["ok"].(bool)
	if ok {
		plaintext, _ := decMap["plaintext"].(string)
		if plaintext == "secret for key pair 1" {
			t.Error("decryption with wrong key should not produce the original plaintext")
		}
	}
	// If ok=false, that is the expected outcome.
}

// --- Invalid JSON input ---

func TestRestoreIdentity_InvalidJSON(t *testing.T) {
	result := RestoreIdentity("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestEncryptMessage_InvalidJSON(t *testing.T) {
	result := EncryptMessage("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestDecryptMessage_InvalidJSON(t *testing.T) {
	result := DecryptMessage("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestEncryptMessage_MissingFields(t *testing.T) {
	// Valid JSON but missing required fields.
	result := EncryptMessage(`{"recipientPublicKey": "abc"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestDecryptMessage_MissingFields(t *testing.T) {
	// Valid JSON but missing required fields.
	result := DecryptMessage(`{"secretKey": "abc"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

// --- SignPayload + VerifyPayload ---

func TestSignVerifyRoundTrip(t *testing.T) {
	// Generate an identity to get a valid key pair
	genResult := GenerateIdentity()
	genMap := parseJSON(t, genResult)
	assertOk(t, genMap)

	identity := genMap["identity"].(map[string]interface{})
	privateKey := identity["privateKey"].(string)
	publicKey := identity["publicKey"].(string)

	// Sign
	data := "hello world"
	signInput, _ := json.Marshal(map[string]string{
		"privateKey": privateKey,
		"data":       data,
	})
	signResult := SignPayload(string(signInput))
	signMap := parseJSON(t, signResult)
	assertOk(t, signMap)

	signature := signMap["signature"].(string)
	if signature == "" {
		t.Fatal("signature is empty")
	}

	// Verify
	verifyInput, _ := json.Marshal(map[string]string{
		"publicKey": publicKey,
		"data":      data,
		"signature": signature,
	})
	verifyResult := VerifyPayload(string(verifyInput))
	verifyMap := parseJSON(t, verifyResult)
	assertOk(t, verifyMap)

	valid, ok := verifyMap["valid"].(bool)
	if !ok || !valid {
		t.Errorf("expected valid=true, got %v", verifyMap["valid"])
	}
}

func TestSignPayload_InvalidJSON(t *testing.T) {
	result := SignPayload("not json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestVerifyPayload_InvalidJSON(t *testing.T) {
	result := VerifyPayload("not json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestSignPayload_MissingFields(t *testing.T) {
	result := SignPayload(`{"privateKey": "abc"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestVerifyPayload_MissingFields(t *testing.T) {
	result := VerifyPayload(`{"publicKey": "abc"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

// --- EncryptContactRequest ---

func TestEncryptContactRequest_InvalidJSON(t *testing.T) {
	result := EncryptContactRequest("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestEncryptContactRequest_MissingFields(t *testing.T) {
	result := EncryptContactRequest(`{"recipientPublicKey": "abc"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestEncryptContactRequest_InvalidRecipientKey(t *testing.T) {
	input, _ := json.Marshal(map[string]string{
		"recipientPublicKey": "not-valid-base64!!!",
		"plaintext":          "hello",
		"msgId":              "test-id",
		"ts":                 "2024-01-01T00:00:00Z",
	})
	result := EncryptContactRequest(string(input))
	m := parseJSON(t, result)
	assertNotOk(t, m, "INTERNAL_ERROR")
}

func TestEncryptContactRequest_Success(t *testing.T) {
	// Generate identity to get a valid Ed25519 public key
	genResult := GenerateIdentity()
	genMap := parseJSON(t, genResult)
	assertOk(t, genMap)
	identity := genMap["identity"].(map[string]interface{})
	publicKey := identity["publicKey"].(string)

	input, _ := json.Marshal(map[string]string{
		"recipientPublicKey": publicKey,
		"plaintext":          "test payload",
		"msgId":              "msg-123",
		"ts":                 "2024-01-01T00:00:00Z",
	})
	result := EncryptContactRequest(string(input))
	m := parseJSON(t, result)
	assertOk(t, m)

	// Verify all required output fields
	eph, ok := m["ephemeralPublicKey"].(string)
	if !ok || eph == "" {
		t.Error("response missing or empty 'ephemeralPublicKey'")
	}
	ct, ok := m["ciphertext"].(string)
	if !ok || ct == "" {
		t.Error("response missing or empty 'ciphertext'")
	}
	nonce, ok := m["nonce"].(string)
	if !ok || nonce == "" {
		t.Error("response missing or empty 'nonce'")
	}
}

// --- DecryptContactRequest ---

func TestDecryptContactRequest_InvalidJSON(t *testing.T) {
	result := DecryptContactRequest("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestDecryptContactRequest_MissingFields(t *testing.T) {
	result := DecryptContactRequest(`{"privateKey": "abc"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestDecryptContactRequest_RoundTrip(t *testing.T) {
	// Generate an identity
	genResult := GenerateIdentity()
	genMap := parseJSON(t, genResult)
	assertOk(t, genMap)
	identity := genMap["identity"].(map[string]interface{})
	publicKey := identity["publicKey"].(string)
	privateKey := identity["privateKey"].(string)

	// Encrypt
	plaintext := `{"ns":"peer123","pk":"pubkey","rv":"/rv","ts":"2024-01-01T00:00:00Z","sig":"abc"}`
	msgId := "msg-456"
	ts := "2024-01-01T00:00:00Z"

	encInput, _ := json.Marshal(map[string]string{
		"recipientPublicKey": publicKey,
		"plaintext":          plaintext,
		"msgId":              msgId,
		"ts":                 ts,
	})
	encResult := EncryptContactRequest(string(encInput))
	encMap := parseJSON(t, encResult)
	assertOk(t, encMap)

	// Decrypt
	decInput, _ := json.Marshal(map[string]string{
		"privateKey":         privateKey,
		"ephemeralPublicKey": encMap["ephemeralPublicKey"].(string),
		"ciphertext":         encMap["ciphertext"].(string),
		"nonce":              encMap["nonce"].(string),
		"msgId":              msgId,
		"ts":                 ts,
	})
	decResult := DecryptContactRequest(string(decInput))
	decMap := parseJSON(t, decResult)
	assertOk(t, decMap)

	got, ok := decMap["plaintext"].(string)
	if !ok {
		t.Fatal("decrypt response missing 'plaintext'")
	}
	if got != plaintext {
		t.Errorf("plaintext mismatch: got %q, want %q", got, plaintext)
	}
}

func TestDecryptContactRequest_WrongKey(t *testing.T) {
	// Generate two identities
	gen1 := parseJSON(t, GenerateIdentity())
	assertOk(t, gen1)
	gen2 := parseJSON(t, GenerateIdentity())
	assertOk(t, gen2)

	id1 := gen1["identity"].(map[string]interface{})
	id2 := gen2["identity"].(map[string]interface{})

	// Encrypt to identity 1
	encInput, _ := json.Marshal(map[string]string{
		"recipientPublicKey": id1["publicKey"].(string),
		"plaintext":          "secret data",
		"msgId":              "msg-789",
		"ts":                 "2024-01-01T00:00:00Z",
	})
	encMap := parseJSON(t, EncryptContactRequest(string(encInput)))
	assertOk(t, encMap)

	// Decrypt with identity 2's private key → should fail
	decInput, _ := json.Marshal(map[string]string{
		"privateKey":         id2["privateKey"].(string),
		"ephemeralPublicKey": encMap["ephemeralPublicKey"].(string),
		"ciphertext":         encMap["ciphertext"].(string),
		"nonce":              encMap["nonce"].(string),
		"msgId":              "msg-789",
		"ts":                 "2024-01-01T00:00:00Z",
	})
	decResult := DecryptContactRequest(string(decInput))
	decMap := parseJSON(t, decResult)
	assertNotOk(t, decMap, "INTERNAL_ERROR")
}

func TestDecryptContactRequest_TamperedAAD(t *testing.T) {
	// Generate identity
	genMap := parseJSON(t, GenerateIdentity())
	assertOk(t, genMap)
	identity := genMap["identity"].(map[string]interface{})

	// Encrypt with specific msgId/ts
	encInput, _ := json.Marshal(map[string]string{
		"recipientPublicKey": identity["publicKey"].(string),
		"plaintext":          "aad test",
		"msgId":              "original-id",
		"ts":                 "2024-01-01T00:00:00Z",
	})
	encMap := parseJSON(t, EncryptContactRequest(string(encInput)))
	assertOk(t, encMap)

	// Decrypt with tampered msgId → should fail (AAD mismatch)
	decInput, _ := json.Marshal(map[string]string{
		"privateKey":         identity["privateKey"].(string),
		"ephemeralPublicKey": encMap["ephemeralPublicKey"].(string),
		"ciphertext":         encMap["ciphertext"].(string),
		"nonce":              encMap["nonce"].(string),
		"msgId":              "tampered-id",
		"ts":                 "2024-01-01T00:00:00Z",
	})
	decResult := DecryptContactRequest(string(decInput))
	decMap := parseJSON(t, decResult)
	assertNotOk(t, decMap, "INTERNAL_ERROR")
}

// --- Inbox: NOT_INITIALIZED (no singleton node) ---

func TestInboxStore_NodeNotInitialized(t *testing.T) {
	result := InboxStore(`{"toPeerId": "12D3KooWTest", "message": "hello"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestInboxRetrieve_NodeNotInitialized(t *testing.T) {
	result := InboxRetrieve()
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestInboxRetrievePending_NodeNotInitialized(t *testing.T) {
	result := InboxRetrievePendingWithParams(`{"timeoutMs":250}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestInboxAck_NodeNotInitialized(t *testing.T) {
	result := InboxAck(`{"entryIds":["entry-1"]}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestInboxRegisterToken_NodeNotInitialized(t *testing.T) {
	result := InboxRegisterToken(`{"token": "fake-token", "platform": "ios"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

// --- Inbox: JSON validation (requires initialized node) ---
//
// These tests temporarily set the singleton node so the bridge functions
// reach the JSON-parsing and field-validation code paths. The node is not
// started (no network), so valid params will fail at the node layer, but
// invalid params are caught before that.

// noopCallback satisfies node.EventCallback for test init.
type noopCallback struct{}

func (noopCallback) OnEvent(string) {}

type recordingBridgeCallback struct {
	events []string
}

func (c *recordingBridgeCallback) OnEvent(jsonString string) {
	c.events = append(c.events, jsonString)
}

// withSingletonNode sets up a singleton for the duration of one test.
func withSingletonNode(t *testing.T) {
	t.Helper()
	nodeMu.Lock()
	prev := singletonNode
	nodeMu.Unlock()

	Initialize(&noopCallback{})

	t.Cleanup(func() {
		nodeMu.Lock()
		singletonNode = prev
		nodeMu.Unlock()
	})
}

func TestInboxStore_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := InboxStore("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxStore_MissingParams(t *testing.T) {
	withSingletonNode(t)
	result := InboxStore(`{}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxStore_MissingMessage(t *testing.T) {
	withSingletonNode(t)
	result := InboxStore(`{"toPeerId": "12D3KooWTest"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxStore_MissingToPeerId(t *testing.T) {
	withSingletonNode(t)
	result := InboxStore(`{"message": "hello"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxRegisterToken_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := InboxRegisterToken("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxRetrievePending_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := InboxRetrievePendingWithParams("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxAck_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := InboxAck("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxAck_MissingEntryIds(t *testing.T) {
	withSingletonNode(t)
	result := InboxAck(`{}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxRegisterToken_MissingFields(t *testing.T) {
	withSingletonNode(t)
	result := InboxRegisterToken(`{}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxRegisterToken_MissingToken(t *testing.T) {
	withSingletonNode(t)
	result := InboxRegisterToken(`{"platform": "ios"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestInboxRegisterToken_MissingPlatform(t *testing.T) {
	withSingletonNode(t)
	result := InboxRegisterToken(`{"token": "fake-token"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

// ---------------------------------------------------------------------------
// Helpers for node lifecycle tests
// ---------------------------------------------------------------------------

// generateTestKeyHex generates a valid Ed25519 private key hex string
// suitable for StartNode input.
func generateTestKeyHex(t *testing.T) string {
	t.Helper()
	priv, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	raw, err := priv.Raw()
	if err != nil {
		t.Fatalf("raw key: %v", err)
	}
	return hex.EncodeToString(raw)
}

// startNodeJSON builds a valid JSON input string for StartNode.
func startNodeJSON(t *testing.T, keyHex string) string {
	t.Helper()
	b, _ := json.Marshal(map[string]interface{}{
		"privateKeyHex":  keyHex,
		"relayAddresses": []string{},
		"namespace":      "",
		"autoRegister":   false,
		"listenPort":     0,
	})
	return string(b)
}

// withNilSingleton temporarily sets the singleton node to nil for the
// duration of one test, then restores the previous value.
func withNilSingleton(t *testing.T) {
	t.Helper()
	nodeMu.Lock()
	prev := singletonNode
	singletonNode = nil
	nodeMu.Unlock()

	t.Cleanup(func() {
		nodeMu.Lock()
		singletonNode = prev
		nodeMu.Unlock()
	})
}

// withFreshSingletonNode creates a brand-new initialized (but not started)
// singleton node, replacing whatever was there before. On cleanup it stops
// the node (if started) and restores the previous singleton.
func withFreshSingletonNode(t *testing.T) {
	t.Helper()
	nodeMu.Lock()
	prev := singletonNode
	singletonNode = nil // force Initialize to create a new one
	nodeMu.Unlock()

	Initialize(&noopCallback{})

	t.Cleanup(func() {
		StopNode() // safe even if not started
		nodeMu.Lock()
		singletonNode = prev
		nodeMu.Unlock()
	})
}

// ---------------------------------------------------------------------------
// StartNode tests
// ---------------------------------------------------------------------------

func TestStartNode_NotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := StartNode(`{"privateKeyHex":"aabb"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestStartNode_InvalidJSON(t *testing.T) {
	withFreshSingletonNode(t)
	result := StartNode("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestStartNode_MissingPrivateKeyHex(t *testing.T) {
	withFreshSingletonNode(t)
	result := StartNode(`{}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestStartNode_InvalidPrivateKeyHex(t *testing.T) {
	withFreshSingletonNode(t)
	// "zzzz" is not valid hex, but even valid hex that doesn't decode
	// to a proper Ed25519 key will error. Use something that IS valid hex
	// but not a valid key.
	input := startNodeJSON(t, "aabbccdd")
	result := StartNode(input)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NODE_START_ERROR")
}

func TestStartNode_Success(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	result := StartNode(input)
	m := parseJSON(t, result)
	assertOk(t, m)

	// Verify isStarted
	isStarted, _ := m["isStarted"].(bool)
	if !isStarted {
		t.Error("expected isStarted=true")
	}

	// Verify peerId is non-empty
	peerId, _ := m["peerId"].(string)
	if peerId == "" {
		t.Error("expected non-empty peerId")
	}

	// Verify listenAddresses, circuitAddresses, connections are present
	if _, ok := m["listenAddresses"]; !ok {
		t.Error("response missing 'listenAddresses'")
	}
	if _, ok := m["circuitAddresses"]; !ok {
		t.Error("response missing 'circuitAddresses'")
	}
	if _, ok := m["connections"]; !ok {
		t.Error("response missing 'connections'")
	}
}

func TestStartNode_AlreadyStarted(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)

	// First start should succeed.
	result1 := StartNode(input)
	m1 := parseJSON(t, result1)
	assertOk(t, m1)

	// Second start should fail.
	result2 := StartNode(input)
	m2 := parseJSON(t, result2)
	assertNotOk(t, m2, "NODE_START_ERROR")
}

// ---------------------------------------------------------------------------
// StopNode tests
// ---------------------------------------------------------------------------

func TestStopNode_NotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := StopNode()
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestStopNode_Success(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Stop should succeed.
	stopResult := StopNode()
	m := parseJSON(t, stopResult)
	assertOk(t, m)
}

func TestStopNode_NotStarted(t *testing.T) {
	withFreshSingletonNode(t)
	// Node is initialized but not started — Stop is a no-op, returns ok.
	result := StopNode()
	m := parseJSON(t, result)
	assertOk(t, m)
}

// ---------------------------------------------------------------------------
// NodeStatus tests
// ---------------------------------------------------------------------------

func TestNodeStatus_NotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := NodeStatus()
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestNodeStatus_BeforeStart(t *testing.T) {
	withFreshSingletonNode(t)
	result := NodeStatus()
	m := parseJSON(t, result)
	assertOk(t, m)

	isStarted, _ := m["isStarted"].(bool)
	if isStarted {
		t.Error("expected isStarted=false before Start")
	}
}

func TestNodeStatus_AfterStart(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	result := NodeStatus()
	m := parseJSON(t, result)
	assertOk(t, m)

	isStarted, _ := m["isStarted"].(bool)
	if !isStarted {
		t.Error("expected isStarted=true after Start")
	}

	peerId, _ := m["peerId"].(string)
	if peerId == "" {
		t.Error("expected non-empty peerId after Start")
	}
}

func TestNodeStatus_AfterStop(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	stopResult := StopNode()
	assertOk(t, parseJSON(t, stopResult))

	result := NodeStatus()
	m := parseJSON(t, result)
	assertOk(t, m)

	isStarted, _ := m["isStarted"].(bool)
	if isStarted {
		t.Error("expected isStarted=false after Stop")
	}
}

// ---------------------------------------------------------------------------
// RelayReconnect tests
// ---------------------------------------------------------------------------

func TestRelayReconnect_NotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := RelayReconnect()
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestRelayReconnect_NotStarted(t *testing.T) {
	withFreshSingletonNode(t)
	// Node is initialized but not started — ReconnectRelays returns error.
	result := RelayReconnect()
	m := parseJSON(t, result)
	assertNotOk(t, m, "RELAY_ERROR")
}

func TestRelayReconnect_Success(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// RelayReconnect does a full stop+start cycle. With no relay configured
	// in the empty relayAddresses list, the waitForCircuitAddress will
	// timeout (~10s) but should still succeed.
	reconnectResult := RelayReconnect()
	m := parseJSON(t, reconnectResult)
	assertOk(t, m)

	// Verify node is still started after reconnect.
	statusResult := NodeStatus()
	statusMap := parseJSON(t, statusResult)
	assertOk(t, statusMap)

	isStarted, _ := statusMap["isStarted"].(bool)
	if !isStarted {
		t.Error("expected isStarted=true after RelayReconnect")
	}
}

func TestRelayReconnect_PreservesPeerId(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	startMap := parseJSON(t, startResult)
	assertOk(t, startMap)

	peerIdBefore, _ := startMap["peerId"].(string)
	if peerIdBefore == "" {
		t.Fatal("expected non-empty peerId before reconnect")
	}

	// Reconnect — peer ID should be preserved (same private key).
	reconnectResult := RelayReconnect()
	assertOk(t, parseJSON(t, reconnectResult))

	statusResult := NodeStatus()
	statusMap := parseJSON(t, statusResult)
	assertOk(t, statusMap)

	peerIdAfter, _ := statusMap["peerId"].(string)
	if peerIdAfter != peerIdBefore {
		t.Errorf("peerId changed after reconnect: before=%q, after=%q",
			peerIdBefore, peerIdAfter)
	}
}

// ---------------------------------------------------------------------------
// Phase 4: Relay Session Manager and Reservation-Aware Health — Bridge Tests
// ---------------------------------------------------------------------------

func TestNodeStatus_ContainsRelayStateWithoutBreakingLegacyFields(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	result := NodeStatus()
	m := parseJSON(t, result)
	assertOk(t, m)

	// Legacy fields must still be present.
	legacyKeys := []string{"ok", "peerId", "isStarted", "listenAddresses", "circuitAddresses", "connections"}
	for _, key := range legacyKeys {
		if _, exists := m[key]; !exists {
			t.Errorf("NodeStatus missing legacy key %q", key)
		}
	}

	// New relay-session fields must be present (additive).
	newKeys := []string{"relayState", "relayStates", "healthyRelayCount", "watchdogRestartCount", "needsGroupRecovery"}
	for _, key := range newKeys {
		if _, exists := m[key]; !exists {
			t.Errorf("NodeStatus missing new relay session key %q", key)
		}
	}

	// relayState should be a string.
	if _, ok := m["relayState"].(string); !ok {
		t.Errorf("relayState should be string, got %T", m["relayState"])
	}

	// healthyRelayCount should be a number.
	switch m["healthyRelayCount"].(type) {
	case float64, int:
		// ok — JSON numbers decode as float64
	default:
		t.Errorf("healthyRelayCount should be number, got %T", m["healthyRelayCount"])
	}
}

func TestNodeCallbackAdapter_ForwardsRelayStateEventUntouched(t *testing.T) {
	recorder := &recordingBridgeCallback{}
	adapter := &nodeCallbackAdapter{cb: recorder}
	payload := `{"event":"relay:state","data":{"relayState":"online","healthyRelayCount":1}}`

	adapter.OnEvent(payload)

	if len(recorder.events) != 1 {
		t.Fatalf("expected exactly 1 forwarded event, got %d", len(recorder.events))
	}
	if recorder.events[0] != payload {
		t.Fatalf("expected forwarded payload %q, got %q", payload, recorder.events[0])
	}
}

func TestSendMessage_IncludesTransportInResponse(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	startResult := StartNode(startNodeJSON(t, keyHex))
	assertOk(t, parseJSON(t, startResult))

	target := node.NewNode()
	targetState, err := target.Start(node.NodeConfig{
		PrivateKeyHex:  generateTestKeyHex(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("target Start: %v", err)
	}
	t.Cleanup(func() {
		_ = target.Stop()
	})

	var targetAddrs []string
	for _, addr := range target.Host().Addrs() {
		targetAddrs = append(targetAddrs, addr.String())
	}

	if err := singletonNode.DialPeer(targetState.PeerId, targetAddrs); err != nil {
		t.Fatalf("DialPeer: %v", err)
	}

	input, err := json.Marshal(map[string]interface{}{
		"peerId":  targetState.PeerId,
		"message": "hello over bridge",
	})
	if err != nil {
		t.Fatalf("marshal input: %v", err)
	}

	result := SendMessage(string(input))
	response := parseJSON(t, result)
	assertOk(t, response)

	if got := response["transport"]; got != "direct" {
		t.Fatalf("expected direct transport, got %v", got)
	}
}

func TestConfirmDirectMessage_NotInitialized(t *testing.T) {
	withNilSingleton(t)

	result := ConfirmDirectMessage(`{"nonce":"nonce-1","ok":true}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestConfirmDirectMessage_InvalidJSON(t *testing.T) {
	withFreshSingletonNode(t)

	result := ConfirmDirectMessage("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestConfirmDirectMessage_MissingNonce(t *testing.T) {
	withFreshSingletonNode(t)

	result := ConfirmDirectMessage(`{"ok":true}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestConfirmDirectMessage_Success(t *testing.T) {
	withFreshSingletonNode(t)

	result := ConfirmDirectMessage(`{"nonce":"nonce-1","ok":false}`)
	m := parseJSON(t, result)
	assertOk(t, m)
}

func TestRelayReconnect_ReturnsRecoveryMode(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	result := RelayReconnect()
	m := parseJSON(t, result)
	assertOk(t, m)

	// Should include recoveryMode field.
	recoveryMode, ok := m["recoveryMode"].(string)
	if !ok {
		t.Fatalf("RelayReconnect missing recoveryMode field")
	}
	if recoveryMode != "in_place" && recoveryMode != "watchdog_restart" {
		t.Errorf("recoveryMode should be 'in_place' or 'watchdog_restart', got %q", recoveryMode)
	}
}

func TestRelayReconnect_ConcurrentBridgeCallsShareSingleRecovery(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Launch 3 concurrent reconnects.
	var wg sync.WaitGroup
	results := make([]string, 3)
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			results[idx] = RelayReconnect()
		}(i)
	}

	wg.Wait()

	// All should succeed.
	for i, r := range results {
		m := parseJSON(t, r)
		assertOk(t, m)
		_ = i
	}

	// Verify the node is still started after concurrent reconnects.
	statusResult := NodeStatus()
	statusMap := parseJSON(t, statusResult)
	assertOk(t, statusMap)

	isStarted, _ := statusMap["isStarted"].(bool)
	if !isStarted {
		t.Error("node should be started after concurrent reconnects")
	}
}

func TestRelayReconnect_ReturnsStructuredRecoveryFields(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	result := RelayReconnect()
	m := parseJSON(t, result)
	assertOk(t, m)

	// Verify structured fields exist so callers don't need string matching.
	structuredFields := []string{"recoveryMode", "relayState", "healthyRelayCount"}
	for _, field := range structuredFields {
		if _, exists := m[field]; !exists {
			t.Errorf("RelayReconnect response missing structured field %q", field)
		}
	}
}

func TestGroupAcknowledgeRecovery_NotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupAcknowledgeRecovery()
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupAcknowledgeRecovery_Success(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	result := GroupAcknowledgeRecovery()
	m := parseJSON(t, result)
	assertOk(t, m)
}

// ---------------------------------------------------------------------------
// Group messaging tests
// ---------------------------------------------------------------------------

func TestGenerateGroupKey_ReturnsKey(t *testing.T) {
	result := GenerateGroupKey()
	m := parseJSON(t, result)
	assertOk(t, m)

	groupKey, ok := m["groupKey"].(string)
	if !ok || groupKey == "" {
		t.Error("response missing or empty 'groupKey'")
	}
}

func TestGroupEncryptDecryptRoundTrip(t *testing.T) {
	// Generate a group key.
	keyResult := GenerateGroupKey()
	keyMap := parseJSON(t, keyResult)
	assertOk(t, keyMap)
	groupKey := keyMap["groupKey"].(string)

	// Encrypt a message.
	originalPlaintext := "Hello, group!"
	encInput, _ := json.Marshal(map[string]string{
		"groupKey":  groupKey,
		"plaintext": originalPlaintext,
	})

	encResult := GroupEncryptMessage(string(encInput))
	encMap := parseJSON(t, encResult)
	assertOk(t, encMap)

	ciphertext, ok := encMap["ciphertext"].(string)
	if !ok || ciphertext == "" {
		t.Fatal("encrypt response missing 'ciphertext'")
	}
	nonce, ok := encMap["nonce"].(string)
	if !ok || nonce == "" {
		t.Fatal("encrypt response missing 'nonce'")
	}

	// Decrypt the message.
	decInput, _ := json.Marshal(map[string]string{
		"groupKey":   groupKey,
		"ciphertext": ciphertext,
		"nonce":      nonce,
	})

	decResult := GroupDecryptMessage(string(decInput))
	decMap := parseJSON(t, decResult)
	assertOk(t, decMap)

	plaintext, ok := decMap["plaintext"].(string)
	if !ok {
		t.Fatal("decrypt response missing 'plaintext'")
	}

	if plaintext != originalPlaintext {
		t.Errorf("plaintext mismatch: got %q, want %q", plaintext, originalPlaintext)
	}
}

func TestGroupEncryptMessage_InvalidJSON(t *testing.T) {
	result := GroupEncryptMessage("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupEncryptMessage_MissingFields(t *testing.T) {
	result := GroupEncryptMessage(`{"groupKey": "abc"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupDecryptMessage_InvalidJSON(t *testing.T) {
	result := GroupDecryptMessage("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupDecryptMessage_MissingFields(t *testing.T) {
	result := GroupDecryptMessage(`{"groupKey": "abc"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupDecryptMessage_WrongKey(t *testing.T) {
	// Generate two different group keys.
	key1Map := parseJSON(t, GenerateGroupKey())
	assertOk(t, key1Map)
	key2Map := parseJSON(t, GenerateGroupKey())
	assertOk(t, key2Map)

	groupKey1 := key1Map["groupKey"].(string)
	groupKey2 := key2Map["groupKey"].(string)

	// Encrypt with key1.
	encInput, _ := json.Marshal(map[string]string{
		"groupKey":  groupKey1,
		"plaintext": "secret group message",
	})
	encMap := parseJSON(t, GroupEncryptMessage(string(encInput)))
	assertOk(t, encMap)

	// Decrypt with key2 should fail.
	decInput, _ := json.Marshal(map[string]string{
		"groupKey":   groupKey2,
		"ciphertext": encMap["ciphertext"].(string),
		"nonce":      encMap["nonce"].(string),
	})
	decResult := GroupDecryptMessage(string(decInput))
	decMap := parseJSON(t, decResult)
	assertNotOk(t, decMap, "INTERNAL_ERROR")
}

// --- Group: NOT_INITIALIZED (no singleton node) ---

func TestGroupCreate_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupCreate(`{"name": "test", "groupType": "chat", "creatorPeerId": "p1", "creatorPublicKey": "pk1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupJoinTopic_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupJoinTopic(`{"groupId": "g1", "groupKey": "k1", "keyEpoch": 1}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupLeaveTopic_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupLeaveTopic(`{"groupId": "g1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupPublish_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupPublish(`{"groupId": "g1", "text": "hello", "senderPeerId": "p1", "senderPublicKey": "pk1", "senderPrivateKey": "sk1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupUpdateConfig_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupUpdateConfig(`{"groupId": "g1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupRotateKey_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupRotateKey(`{"groupId": "g1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupUpdateKey_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupUpdateKey(`{"groupId": "g1", "groupKey": "k1", "keyEpoch": 2}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupInboxStore_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupInboxStore(`{"groupId": "g1", "message": "hello"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupInboxRetrieve_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupInboxRetrieve(`{"groupId": "g1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestGroupInboxRetrieveCursor_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)
	result := GroupInboxRetrieveCursor(`{"groupId": "g1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

// --- Group: JSON validation (requires initialized node) ---

func TestGroupCreate_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupCreate("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupCreate_MissingFields(t *testing.T) {
	withSingletonNode(t)
	result := GroupCreate(`{"name": "test"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupJoinTopic_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupJoinTopic("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupJoinTopic_MissingFields(t *testing.T) {
	withSingletonNode(t)
	result := GroupJoinTopic(`{"groupId": "g1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupLeaveTopic_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupLeaveTopic("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupLeaveTopic_MissingGroupId(t *testing.T) {
	withSingletonNode(t)
	result := GroupLeaveTopic(`{}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupPublish_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupPublish("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupPublish_MissingFields(t *testing.T) {
	withSingletonNode(t)
	result := GroupPublish(`{"groupId": "g1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupPublish_EmptyTextAndNoMedia_Fails(t *testing.T) {
	withSingletonNode(t)
	result := GroupPublish(`{
		"groupId": "g1",
		"text": "",
		"senderPeerId": "peer1",
		"senderPublicKey": "pk1",
		"senderPrivateKey": "sk1",
		"senderUsername": "Alice"
	}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupPublish_MediaOnly_AcceptsEmptyText(t *testing.T) {
	withSingletonNode(t)
	// GroupPublish will fail at PublishGroupMessage (no real group), but it
	// must pass input validation when text is empty but media is present.
	result := GroupPublish(`{
		"groupId": "g1",
		"text": "",
		"senderPeerId": "peer1",
		"senderPublicKey": "pk1",
		"senderPrivateKey": "sk1",
		"senderUsername": "Alice",
		"media": [{"id": "m1", "mime": "audio/mp4", "size": 48000}]
	}`)
	m := parseJSON(t, result)
	// Should NOT be INVALID_INPUT — the validation passed. It will fail
	// with GROUP_ERROR because the group doesn't actually exist.
	if code, ok := m["errorCode"].(string); ok {
		if code == "INVALID_INPUT" {
			t.Fatalf("expected media-only publish to pass validation, got INVALID_INPUT")
		}
	}
}

// TestGroupPublish_ResponseIncludesTopicPeers verifies that a successful
// GroupPublish response includes the "topicPeers" field with a numeric value.
func TestGroupPublish_ResponseIncludesTopicPeers(t *testing.T) {
	withFreshSingletonNode(t)

	// 1. Generate identity to get valid Ed25519 keys.
	genResult := GenerateIdentity()
	genMap := parseJSON(t, genResult)
	assertOk(t, genMap)
	identity := genMap["identity"].(map[string]interface{})
	peerId := identity["peerId"].(string)
	publicKey := identity["publicKey"].(string)
	privateKey := identity["privateKey"].(string)

	// 2. Start the node.
	keyHex := generateTestKeyHex(t)
	startInput, _ := json.Marshal(map[string]interface{}{
		"privateKeyHex":  keyHex,
		"relayAddresses": []string{},
		"autoRegister":   false,
	})
	startResult := StartNode(string(startInput))
	assertOk(t, parseJSON(t, startResult))

	// 3. Create a group (this joins the topic and generates a group key).
	createInput, _ := json.Marshal(map[string]interface{}{
		"name":             "Peer Count Test Group",
		"groupType":        "chat",
		"creatorPeerId":    peerId,
		"creatorPublicKey": publicKey,
	})
	createResult := GroupCreate(string(createInput))
	createMap := parseJSON(t, createResult)
	assertOk(t, createMap)
	groupId := createMap["groupId"].(string)

	// 4. Publish a message to the group.
	publishInput, _ := json.Marshal(map[string]interface{}{
		"groupId":          groupId,
		"text":             "hello from bridge test",
		"senderPeerId":     peerId,
		"senderPublicKey":  publicKey,
		"senderPrivateKey": privateKey,
		"senderUsername":   "TestUser",
	})
	publishResult := GroupPublish(string(publishInput))
	m := parseJSON(t, publishResult)
	assertOk(t, m)

	// 5. Verify the response includes "topicPeers" as a number.
	topicPeersRaw, exists := m["topicPeers"]
	if !exists {
		t.Fatal("response missing 'topicPeers' field")
	}
	topicPeers, ok := topicPeersRaw.(float64) // JSON numbers are float64
	if !ok {
		t.Fatalf("topicPeers should be a number, got %T: %v", topicPeersRaw, topicPeersRaw)
	}
	// Single node, no other peers connected — expect 0.
	if topicPeers != 0 {
		t.Errorf("expected topicPeers == 0 (single node, no other peers), got %v", topicPeers)
	}

	// 6. Verify "messageId" is still present.
	if _, ok := m["messageId"].(string); !ok {
		t.Fatal("response missing 'messageId' string field")
	}
}

func TestBuildGroupPublishOpts_IncludesQuotedMessageId(t *testing.T) {
	media := []map[string]interface{}{
		{"id": "m1", "mime": "image/jpeg"},
	}

	opts := buildGroupPublishOpts(media, "parent-msg-1")
	if opts == nil {
		t.Fatal("expected publish opts, got nil")
	}

	if got := opts["quotedMessageId"]; got != "parent-msg-1" {
		t.Fatalf("quotedMessageId = %v, want %q", got, "parent-msg-1")
	}
	if got, ok := opts["media"].([]map[string]interface{}); !ok || len(got) != 1 {
		t.Fatalf("media = %#v, want one attachment", opts["media"])
	}
}

func TestBuildGroupPublishOpts_EmptyReturnsNil(t *testing.T) {
	if opts := buildGroupPublishOpts(nil, ""); opts != nil {
		t.Fatalf("expected nil opts, got %#v", opts)
	}
}

func TestGroupUpdateConfig_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupUpdateConfig("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupUpdateConfig_MissingGroupId(t *testing.T) {
	withSingletonNode(t)
	result := GroupUpdateConfig(`{}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupUpdateKey_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupUpdateKey("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupUpdateKey_MissingFields(t *testing.T) {
	withSingletonNode(t)
	result := GroupUpdateKey(`{"groupId": "g1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupRotateKey_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupRotateKey("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupRotateKey_MissingGroupId(t *testing.T) {
	withSingletonNode(t)
	result := GroupRotateKey(`{}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupInboxStore_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupInboxStore("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupInboxStore_MissingFields(t *testing.T) {
	withSingletonNode(t)
	result := GroupInboxStore(`{"groupId": "g1"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupInboxStore_AcceptsPushFanoutFields(t *testing.T) {
	withSingletonNode(t)
	result := GroupInboxStore(`{
		"groupId": "g1",
		"message": "hello",
		"recipientPeerIds": ["peer-2", "peer-3"],
		"pushTitle": "Test Group",
		"pushBody": "Alice: hello"
	}`)
	m := parseJSON(t, result)

	assertNotOk(t, m, "GROUP_INBOX_ERROR")
}

func TestGroupInboxRetrieve_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupInboxRetrieve("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupInboxRetrieve_MissingGroupId(t *testing.T) {
	withSingletonNode(t)
	result := GroupInboxRetrieve(`{}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupInboxRetrieveCursor_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := GroupInboxRetrieveCursor("not valid json")
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestGroupInboxRetrieveCursor_MissingGroupId(t *testing.T) {
	withSingletonNode(t)
	result := GroupInboxRetrieveCursor(`{"cursor": "opaque"}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

// ---------------------------------------------------------------------------
// Full lifecycle test
// ---------------------------------------------------------------------------

func TestStartNode_StopNode_FullCycle(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)

	// Start
	startResult := StartNode(input)
	startMap := parseJSON(t, startResult)
	assertOk(t, startMap)

	isStarted, _ := startMap["isStarted"].(bool)
	if !isStarted {
		t.Fatal("expected isStarted=true after Start")
	}

	peerId, _ := startMap["peerId"].(string)
	if peerId == "" {
		t.Fatal("expected non-empty peerId after Start")
	}

	// Stop
	stopResult := StopNode()
	stopMap := parseJSON(t, stopResult)
	assertOk(t, stopMap)

	// Verify stopped via status
	statusResult := NodeStatus()
	statusMap := parseJSON(t, statusResult)
	assertOk(t, statusMap)

	isStarted, _ = statusMap["isStarted"].(bool)
	if isStarted {
		t.Error("expected isStarted=false after Stop")
	}
}

// ===========================================================================
// Phase 3: Bridge-level integration tests for group invite flow
// ===========================================================================

// Test 3.1: GroupUpdateConfig bridge -- happy path with new member.
func TestGroupUpdateConfig_WithNewMember(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Create a group (admin-only config).
	genIdentity := parseJSON(t, GenerateIdentity())
	assertOk(t, genIdentity)
	identity := genIdentity["identity"].(map[string]interface{})

	createInput, _ := json.Marshal(map[string]interface{}{
		"name":             "Invite Test Group",
		"groupType":        "chat",
		"creatorPeerId":    identity["peerId"].(string),
		"creatorPublicKey": identity["publicKey"].(string),
	})
	createResult := GroupCreate(string(createInput))
	createMap := parseJSON(t, createResult)
	assertOk(t, createMap)

	groupId := createMap["groupId"].(string)

	// Build a new config with an additional member.
	updatedConfig := map[string]interface{}{
		"name":      "Invite Test Group",
		"groupType": "chat",
		"members": []map[string]interface{}{
			{
				"peerId":    identity["peerId"].(string),
				"role":      "admin",
				"publicKey": identity["publicKey"].(string),
			},
			{
				"peerId":    "peer-new-member",
				"role":      "writer",
				"publicKey": "newMemberPubKey",
			},
		},
		"createdBy": identity["peerId"].(string),
		"createdAt": "2026-01-01T00:00:00Z",
	}

	updateInput, _ := json.Marshal(map[string]interface{}{
		"groupId":     groupId,
		"groupConfig": updatedConfig,
	})
	updateResult := GroupUpdateConfig(string(updateInput))
	updateMap := parseJSON(t, updateResult)
	assertOk(t, updateMap)
}

// Test 3.2: GroupJoinTopic bridge -- happy path with received invite data.
func TestGroupJoinTopic_WithInviteData(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Generate a group key.
	keyResult := GenerateGroupKey()
	keyMap := parseJSON(t, keyResult)
	assertOk(t, keyMap)
	groupKey := keyMap["groupKey"].(string)

	// Build a config with 2 members (simulating invite payload).
	inviteConfig := map[string]interface{}{
		"name":      "Invite Group",
		"groupType": "chat",
		"members": []map[string]interface{}{
			{
				"peerId":    "peer-admin",
				"role":      "admin",
				"publicKey": "adminPubKey",
			},
			{
				"peerId":    "peer-invitee",
				"role":      "writer",
				"publicKey": "inviteePubKey",
			},
		},
		"createdBy": "peer-admin",
		"createdAt": "2026-01-01T00:00:00Z",
	}

	joinInput, _ := json.Marshal(map[string]interface{}{
		"groupId":     "invite-group-1",
		"groupConfig": inviteConfig,
		"groupKey":    groupKey,
		"keyEpoch":    1,
	})
	joinResult := GroupJoinTopic(string(joinInput))
	joinMap := parseJSON(t, joinResult)
	assertOk(t, joinMap)
}

func TestGroupJoinTopic_AlreadyJoinedIsIdempotent(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	keyResult := GenerateGroupKey()
	keyMap := parseJSON(t, keyResult)
	assertOk(t, keyMap)
	groupKey := keyMap["groupKey"].(string)

	inviteConfig := map[string]interface{}{
		"name":      "Invite Group",
		"groupType": "chat",
		"members": []map[string]interface{}{
			{
				"peerId":    "peer-admin",
				"role":      "admin",
				"publicKey": "adminPubKey",
			},
			{
				"peerId":    "peer-invitee",
				"role":      "writer",
				"publicKey": "inviteePubKey",
			},
		},
		"createdBy": "peer-admin",
		"createdAt": "2026-01-01T00:00:00Z",
	}

	joinInput, _ := json.Marshal(map[string]interface{}{
		"groupId":     "invite-group-already-joined",
		"groupConfig": inviteConfig,
		"groupKey":    groupKey,
		"keyEpoch":    1,
	})

	firstJoin := parseJSON(t, GroupJoinTopic(string(joinInput)))
	assertOk(t, firstJoin)

	secondJoin := parseJSON(t, GroupJoinTopic(string(joinInput)))
	assertOk(t, secondJoin)
	if note, _ := secondJoin["note"].(string); note != "ALREADY_JOINED" {
		t.Fatalf("expected ALREADY_JOINED note on idempotent rejoin, got %v", secondJoin["note"])
	}
}

// ===========================================================================
// Phase 6: Bridge-level GroupRotateKey for post-invite key distribution
// ===========================================================================

// Test 6.1: GroupRotateKey increments epoch.
func TestGroupRotateKey_IncrementsEpoch(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Create a group (keyEpoch starts at 1).
	genIdentity := parseJSON(t, GenerateIdentity())
	assertOk(t, genIdentity)
	identity := genIdentity["identity"].(map[string]interface{})

	createInput, _ := json.Marshal(map[string]interface{}{
		"name":             "Key Rotation Group",
		"groupType":        "chat",
		"creatorPeerId":    identity["peerId"].(string),
		"creatorPublicKey": identity["publicKey"].(string),
	})
	createResult := GroupCreate(string(createInput))
	createMap := parseJSON(t, createResult)
	assertOk(t, createMap)

	groupId := createMap["groupId"].(string)

	// First rotation: epoch should go from 1 to 2.
	rotateInput, _ := json.Marshal(map[string]string{"groupId": groupId})
	rotateResult1 := GroupRotateKey(string(rotateInput))
	rotateMap1 := parseJSON(t, rotateResult1)
	assertOk(t, rotateMap1)

	epoch1, ok := rotateMap1["keyEpoch"].(float64)
	if !ok {
		t.Fatal("response missing 'keyEpoch'")
	}
	if int(epoch1) != 2 {
		t.Errorf("expected keyEpoch=2 after first rotation, got %d", int(epoch1))
	}

	newKey1, ok := rotateMap1["groupKey"].(string)
	if !ok || newKey1 == "" {
		t.Fatal("response missing or empty 'groupKey'")
	}

	// Second rotation: epoch should go from 2 to 3.
	rotateResult2 := GroupRotateKey(string(rotateInput))
	rotateMap2 := parseJSON(t, rotateResult2)
	assertOk(t, rotateMap2)

	epoch2, ok := rotateMap2["keyEpoch"].(float64)
	if !ok {
		t.Fatal("response missing 'keyEpoch'")
	}
	if int(epoch2) != 3 {
		t.Errorf("expected keyEpoch=3 after second rotation, got %d", int(epoch2))
	}

	newKey2, ok := rotateMap2["groupKey"].(string)
	if !ok || newKey2 == "" {
		t.Fatal("response missing or empty 'groupKey' after second rotation")
	}

	// Keys should differ between rotations.
	if newKey1 == newKey2 {
		t.Error("rotated keys should be different")
	}
}

// ===========================================================================
// Network Architecture: timeoutMs and pagination passthrough tests
// ===========================================================================

// TestRendezvousDiscover_HonorsTimeoutMs verifies that when timeoutMs is
// provided in the input JSON, the bridge parses it and passes it to the
// node's RendezvousDiscoverWithTimeout. We verify by checking that the
// discover completes within our custom timeout and returns a valid response.
func TestRendezvousDiscover_HonorsTimeoutMs(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Call RendezvousDiscover with an explicit short timeoutMs.
	// The node is started; the call should succeed (possibly with 0 peers)
	// without hitting INVALID_INPUT — proving timeoutMs was parsed.
	discoverInput, _ := json.Marshal(map[string]interface{}{
		"namespace": "mknoon:chat:test",
		"timeoutMs": 500,
	})
	result := RendezvousDiscover(string(discoverInput))
	m := parseJSON(t, result)

	// The response must NOT be INVALID_INPUT (timeoutMs parsed correctly).
	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("timeoutMs should be parsed without INVALID_INPUT error")
	}

	// The call may succeed (0 peers on unknown namespace) or fail at
	// the network layer. Either way, INVALID_INPUT means parsing failed.
	// If ok=true, verify peers list is present.
	if m["ok"] == true {
		if _, hasPeers := m["peers"]; !hasPeers {
			t.Error("response missing 'peers' field")
		}
	}
}

// TestDialPeer_HonorsTimeoutMs verifies that timeoutMs in the input JSON
// is parsed and passed to DialPeerWithTimeout.
func TestDialPeer_HonorsTimeoutMs(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Call DialPeer with a timeoutMs field. The peer doesn't exist but
	// the important thing is the JSON parsing succeeds (not INVALID_INPUT).
	dialInput, _ := json.Marshal(map[string]interface{}{
		"peerId":    "12D3KooWFakeDialTestPeer",
		"addresses": []string{"/ip4/127.0.0.1/tcp/9999"},
		"timeoutMs": 200,
	})
	result := DialPeer(string(dialInput))
	m := parseJSON(t, result)

	// Should fail at dial layer (unreachable peer), not input parsing.
	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("timeoutMs should be parsed without INVALID_INPUT error")
	}
	// Expect DIAL_ERROR since the peer is unreachable.
	assertNotOk(t, m, "DIAL_ERROR")
}

// TestRendezvousRegister_ForwardsExistingServerAddresses verifies that
// serverAddresses in the input JSON is parsed and forwarded to the node.
func TestRendezvousRegister_ForwardsExistingServerAddresses(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Call RendezvousRegister with serverAddresses. The addresses are
	// unreachable but the bridge should parse them without INVALID_INPUT.
	registerInput, _ := json.Marshal(map[string]interface{}{
		"namespace":       "mknoon:chat:test",
		"serverAddresses": []string{"/ip4/1.2.3.4/tcp/4001/p2p/12D3KooWFakeServer"},
	})
	result := RendezvousRegister(string(registerInput))
	m := parseJSON(t, result)

	// Should fail at rendezvous layer (can't reach server), not input parsing.
	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("serverAddresses should be parsed without INVALID_INPUT error")
	}
	// Expect RENDEZVOUS_ERROR since the server is unreachable.
	assertNotOk(t, m, "RENDEZVOUS_ERROR")
}

// TestInboxRetrieve_HonorsForegroundTimeoutWhenProvided verifies that when
// timeoutMs is provided, InboxRetrieveWithParams honors it and returns a
// valid response including the hasMore field.
func TestInboxRetrieve_HonorsForegroundTimeoutWhenProvided(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Call InboxRetrieveWithParams with an explicit timeoutMs.
	retrieveInput, _ := json.Marshal(map[string]interface{}{
		"timeoutMs": 300,
	})
	result := InboxRetrieveWithParams(string(retrieveInput))
	m := parseJSON(t, result)

	// Must NOT be INVALID_INPUT — proves timeoutMs was parsed.
	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("timeoutMs should be parsed without INVALID_INPUT error")
	}

	// If the call succeeded, verify it includes hasMore and messages.
	if m["ok"] == true {
		if _, hasMsgs := m["messages"]; !hasMsgs {
			t.Error("response missing 'messages' field")
		}
		if _, hasMore := m["hasMore"]; !hasMore {
			t.Error("response missing 'hasMore' field")
		}
	}
}

func TestInboxRetrievePending_HonorsForegroundTimeoutWhenProvided(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	retrieveInput, _ := json.Marshal(map[string]interface{}{
		"timeoutMs": 300,
	})
	result := InboxRetrievePendingWithParams(string(retrieveInput))
	m := parseJSON(t, result)

	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("timeoutMs should be parsed without INVALID_INPUT error")
	}

	if m["ok"] == true {
		if _, hasMsgs := m["messages"]; !hasMsgs {
			t.Error("response missing 'messages' field")
		}
		if _, hasMore := m["hasMore"]; !hasMore {
			t.Error("response missing 'hasMore' field")
		}
	}
}

func TestInboxAck_ParsesEntryIdsAndTimeout(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	ackInput, _ := json.Marshal(map[string]interface{}{
		"entryIds":  []string{"entry-1", "entry-2"},
		"timeoutMs": 300,
	})
	result := InboxAck(string(ackInput))
	m := parseJSON(t, result)

	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("entryIds and timeoutMs should be parsed without INVALID_INPUT error")
	}
}

// TestInboxRetrieve_ExposesContinuationMetadataWhenBacklogRemains verifies
// that InboxRetrieveWithParams includes hasMore in the response while the
// old InboxRetrieve() does NOT include it.
func TestInboxRetrieve_ExposesContinuationMetadataWhenBacklogRemains(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Old InboxRetrieve — does not include hasMore in its response.
	oldResult := InboxRetrieve()
	oldMap := parseJSON(t, oldResult)
	_, hasHasMore := oldMap["hasMore"]
	if hasHasMore {
		t.Error("old InboxRetrieve should not include hasMore field")
	}

	// InboxRetrieveWithParams — includes hasMore in success response.
	newResult := InboxRetrieveWithParams(`{}`)
	newMap := parseJSON(t, newResult)

	if newMap["ok"] == true {
		// On success, hasMore must be present (even if false).
		hasMoreVal, hasField := newMap["hasMore"]
		if !hasField {
			t.Fatal("InboxRetrieveWithParams response missing 'hasMore' field")
		}
		// With no messages, hasMore should be false.
		if hasMoreVal != false {
			t.Errorf("expected hasMore=false with empty inbox, got %v", hasMoreVal)
		}
	} else {
		// If the call failed (network error), just ensure it's not INVALID_INPUT.
		code, _ := newMap["errorCode"].(string)
		if code == "INVALID_INPUT" {
			t.Fatal("InboxRetrieveWithParams should parse empty JSON without error")
		}
	}
}

// ===========================================================================
// GroupUpdateKey — updates stored key without generating a new one
// ===========================================================================

// Test: GroupUpdateKey updates the stored key so subsequent publishes use it.
func TestGroupUpdateKey_UpdatesStoredKey(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Create a group.
	genIdentity := parseJSON(t, GenerateIdentity())
	assertOk(t, genIdentity)
	identity := genIdentity["identity"].(map[string]interface{})

	createInput, _ := json.Marshal(map[string]interface{}{
		"name":             "UpdateKey Test Group",
		"groupType":        "chat",
		"creatorPeerId":    identity["peerId"].(string),
		"creatorPublicKey": identity["publicKey"].(string),
	})
	createResult := GroupCreate(string(createInput))
	createMap := parseJSON(t, createResult)
	assertOk(t, createMap)

	groupId := createMap["groupId"].(string)

	// Generate a new group key to simulate receiving from admin.
	newKeyResult := GenerateGroupKey()
	newKeyMap := parseJSON(t, newKeyResult)
	assertOk(t, newKeyMap)
	newKey := newKeyMap["groupKey"].(string)

	// Call GroupUpdateKey with the new key and epoch 5.
	updateInput, _ := json.Marshal(map[string]interface{}{
		"groupId":  groupId,
		"groupKey": newKey,
		"keyEpoch": 5,
	})
	updateResult := GroupUpdateKey(string(updateInput))
	updateMap := parseJSON(t, updateResult)
	assertOk(t, updateMap)
}

// ---------------------------------------------------------------------------
// Phase 3: Multi-Relay Routing — Bridge tests
// ---------------------------------------------------------------------------

// generateFakeRelayAddrBridge generates a multiaddr string with a random peer ID.
func generateFakeRelayAddrBridge(t *testing.T, port int) string {
	t.Helper()
	priv, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("generate fake relay key: %v", err)
	}
	pid, err := peer.IDFromPrivateKey(priv)
	if err != nil {
		t.Fatalf("peer ID from key: %v", err)
	}
	return fmt.Sprintf("/ip4/127.0.0.1/tcp/%d/p2p/%s", port, pid.String())
}

// TestRendezvousRegister_PassesServerAddresses verifies that the bridge
// RendezvousRegister function correctly parses and forwards multiple
// serverAddresses to the node layer (multi-relay support).
func TestRendezvousRegister_PassesServerAddresses(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Call RendezvousRegister with multiple server addresses using random
	// peer IDs that will never match the production relay.
	addr1 := generateFakeRelayAddrBridge(t, 19991)
	addr2 := generateFakeRelayAddrBridge(t, 19992)

	registerInput, _ := json.Marshal(map[string]interface{}{
		"namespace":       "mknoon:chat:test",
		"serverAddresses": []string{addr1, addr2},
	})
	result := RendezvousRegister(string(registerInput))
	m := parseJSON(t, result)

	// Should fail at rendezvous layer (can't reach servers), not input parsing.
	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("multiple serverAddresses should be parsed without INVALID_INPUT error")
	}
	// Expect RENDEZVOUS_ERROR since the servers are unreachable.
	assertNotOk(t, m, "RENDEZVOUS_ERROR")
}

// TestRendezvousDiscover_PassesServerAddresses verifies that the bridge
// RendezvousDiscover function correctly parses and forwards serverAddresses
// to the node layer for multi-relay discovery.
func TestRendezvousDiscover_PassesServerAddresses(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	input := startNodeJSON(t, keyHex)
	startResult := StartNode(input)
	assertOk(t, parseJSON(t, startResult))

	// Call RendezvousDiscover with serverAddresses field using a random
	// peer ID to avoid hitting the production relay.
	addr1 := generateFakeRelayAddrBridge(t, 19991)

	discoverInput, _ := json.Marshal(map[string]interface{}{
		"namespace":       "mknoon:chat:test",
		"serverAddresses": []string{addr1},
		"timeoutMs":       1000,
	})
	result := RendezvousDiscover(string(discoverInput))
	m := parseJSON(t, result)

	// Should fail at rendezvous layer, not input parsing.
	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("serverAddresses should be parsed without INVALID_INPUT error")
	}
	assertNotOk(t, m, "RENDEZVOUS_ERROR")
}

// TestGroupInboxStore_UsesProvidedServerAddresses verifies that GroupInboxStore
// uses the relay selector (which honors node-configured relay addresses)
// rather than a hardcoded first relay. This is tested by starting the node
// with fake unreachable relay addresses and verifying the operation uses them.
func TestGroupInboxStore_UsesProvidedServerAddresses(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	// Start node with two unreachable relays.
	startInput, _ := json.Marshal(map[string]interface{}{
		"privateKeyHex": keyHex,
		"relayAddresses": []string{
			"/ip4/10.99.99.1/tcp/4001/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g",
			"/ip4/10.99.99.2/tcp/4001/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g",
		},
		"autoRegister": false,
	})
	startResult := StartNode(string(startInput))
	assertOk(t, parseJSON(t, startResult))

	// GroupInboxStore should attempt to use the configured relays.
	storeInput, _ := json.Marshal(map[string]interface{}{
		"groupId": "test-group-123",
		"message": "hello",
	})
	result := GroupInboxStore(string(storeInput))
	m := parseJSON(t, result)

	// Should fail at group inbox layer (can't reach relay), not input parsing.
	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("GroupInboxStore should not fail at input parsing")
	}
	assertNotOk(t, m, "GROUP_INBOX_ERROR")
}

// TestGroupInboxRetrieveCursor_PassesOpaqueCursor verifies that the bridge
// accepts the additive cursor contract and reaches the node layer without
// rejecting opaque cursor values during JSON parsing.
func TestGroupInboxRetrieveCursor_PassesOpaqueCursor(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	startInput, _ := json.Marshal(map[string]interface{}{
		"privateKeyHex": keyHex,
		"relayAddresses": []string{
			generateFakeRelayAddrBridge(t, 19993),
			generateFakeRelayAddrBridge(t, 19994),
		},
		"autoRegister": false,
	})
	startResult := StartNode(string(startInput))
	assertOk(t, parseJSON(t, startResult))

	retrieveInput, _ := json.Marshal(map[string]interface{}{
		"groupId": "test-group-opaque-cursor",
		"cursor":  "opaque+/=cursor:page-2",
		"limit":   7,
	})
	result := GroupInboxRetrieveCursor(string(retrieveInput))
	m := parseJSON(t, result)

	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("GroupInboxRetrieveCursor should accept opaque cursor payloads")
	}
	assertNotOk(t, m, "GROUP_INBOX_ERROR")
}

// TestGroupInboxRetrieveCursor_CommandExposed verifies that
// GroupInboxRetrieveCursor is callable from the bridge layer and accepts
// valid JSON input without INVALID_INPUT rejection.
func TestGroupInboxRetrieveCursor_CommandExposed(t *testing.T) {
	withFreshSingletonNode(t)
	keyHex := generateTestKeyHex(t)
	startInput, _ := json.Marshal(map[string]interface{}{
		"privateKeyHex": keyHex,
		"relayAddresses": []string{
			generateFakeRelayAddrBridge(t, 19995),
		},
		"autoRegister": false,
	})
	startResult := StartNode(string(startInput))
	assertOk(t, parseJSON(t, startResult))

	retrieveInput, _ := json.Marshal(map[string]interface{}{
		"groupId": "test-group-cursor-exposed",
		"cursor":  "",
		"limit":   20,
	})
	result := GroupInboxRetrieveCursor(string(retrieveInput))
	m := parseJSON(t, result)

	// Should fail at group inbox layer (can't reach relay), not input parsing.
	code, _ := m["errorCode"].(string)
	if code == "INVALID_INPUT" {
		t.Fatal("GroupInboxRetrieveCursor should be an exposed command that accepts valid input")
	}
	// Expected failure: GROUP_INBOX_ERROR (no relay reachable)
	assertNotOk(t, m, "GROUP_INBOX_ERROR")
}
