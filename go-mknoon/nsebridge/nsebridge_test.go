package bridge

import (
	"encoding/json"
	"testing"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

func decodeNSEBridgeResponse(t *testing.T, raw string) map[string]interface{} {
	t.Helper()
	var response map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &response); err != nil {
		t.Fatalf("decode bridge response %q: %v", raw, err)
	}
	return response
}

func TestGroupDecryptMessageMatchesProductionCrypto(t *testing.T) {
	key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	const plaintext = `{"id":"group-message-1","text":"hello from Pixel"}`
	ciphertext, nonce, err := mcrypto.EncryptGroupMessage(key, plaintext)
	if err != nil {
		t.Fatalf("encrypt group message: %v", err)
	}
	request, err := json.Marshal(map[string]string{
		"groupKey":   key,
		"ciphertext": ciphertext,
		"nonce":      nonce,
	})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	response := decodeNSEBridgeResponse(t, GroupDecryptMessage(string(request)))
	if response["ok"] != true || response["plaintext"] != plaintext {
		t.Fatalf("group decrypt response = %#v", response)
	}
}

func TestDecryptMessageMatchesProductionCrypto(t *testing.T) {
	keyPair, err := mcrypto.MlKemKeygen()
	if err != nil {
		t.Fatalf("generate ML-KEM key pair: %v", err)
	}
	const plaintext = `{"id":"direct-message-1","text":"hello securely"}`
	encrypted, err := mcrypto.EncryptMessage(keyPair.PublicKey, plaintext)
	if err != nil {
		t.Fatalf("encrypt direct message: %v", err)
	}
	request, err := json.Marshal(map[string]string{
		"secretKey":  keyPair.SecretKey,
		"kem":        encrypted.Kem,
		"ciphertext": encrypted.Ciphertext,
		"nonce":      encrypted.Nonce,
	})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	response := decodeNSEBridgeResponse(t, DecryptMessage(string(request)))
	if response["ok"] != true || response["plaintext"] != plaintext {
		t.Fatalf("direct decrypt response = %#v", response)
	}
}

func TestNSEInboxRetrievePendingRejectsMalformedInputWithoutPrivateDetails(t *testing.T) {
	response := decodeNSEBridgeResponse(t, NSEInboxRetrievePending(`{"unexpected":true}`))
	if response["ok"] != false || response["errorCode"] != "INVALID_INPUT" ||
		response["errorMessage"] != "invalid NSE inbox request" {
		t.Fatalf("malformed inbox response = %#v", response)
	}
}
