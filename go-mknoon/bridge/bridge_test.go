package bridge

import (
	"encoding/json"
	"testing"
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
