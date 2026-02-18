// Package bridge provides the gomobile-exported API for Flutter integration.
//
// ALL functions take and return JSON strings (gomobile constraint -- no complex
// types across FFI). Each function recovers panics and returns a JSON error
// envelope so the caller never sees an unhandled crash.
//
// JSON protocol:
//
//	Success: { "ok": true, ... }
//	Error:   { "ok": false, "errorCode": "...", "errorMessage": "..." }
package bridge

import (
	"encoding/json"
	"fmt"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/identity"
)

// --- Identity ---

// GenerateIdentity creates a new identity with BIP39 mnemonic + Ed25519 keypair.
// Returns JSON: { "ok": true, "identity": { "peerId", "publicKey", "privateKey", "mnemonic12", "createdAt", "updatedAt" } }
// Or: { "ok": false, "errorCode": "INTERNAL_ERROR", "errorMessage": "..." }
func GenerateIdentity() (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	id, err := identity.GenerateIdentity()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":       true,
		"identity": identityMap(id),
	})
}

// RestoreIdentity restores identity from mnemonic.
// Input JSON: { "mnemonic12": "word1 word2 ... word12" }
// Returns same format as GenerateIdentity.
func RestoreIdentity(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		Mnemonic12 string `json:"mnemonic12"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.Mnemonic12 == "" {
		return errJSON("INVALID_INPUT", "missing mnemonic12")
	}

	id, err := identity.RestoreIdentity(params.Mnemonic12)
	if err != nil {
		return errJSON("INVALID_MNEMONIC", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":       true,
		"identity": identityMap(id),
	})
}

// --- Crypto ---

// MlKemKeygen generates a new ML-KEM-768 key pair.
// Returns JSON: { "ok": true, "publicKey": "<base64>", "secretKey": "<base64>" }
func MlKemKeygen() (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	kp, err := mcrypto.MlKemKeygen()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":        true,
		"publicKey": kp.PublicKey,
		"secretKey": kp.SecretKey,
	})
}

// EncryptMessage encrypts a message with ML-KEM-768 + AES-256-GCM.
// Input JSON: { "recipientPublicKey": "<base64>", "plaintext": "..." }
// Returns JSON: { "ok": true, "kem": "<base64>", "ciphertext": "<base64>", "nonce": "<base64>" }
func EncryptMessage(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		RecipientPublicKey string `json:"recipientPublicKey"`
		Plaintext          string `json:"plaintext"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.RecipientPublicKey == "" || params.Plaintext == "" {
		return errJSON("INVALID_INPUT", "missing recipientPublicKey or plaintext")
	}

	enc, err := mcrypto.EncryptMessage(params.RecipientPublicKey, params.Plaintext)
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":         true,
		"kem":        enc.Kem,
		"ciphertext": enc.Ciphertext,
		"nonce":      enc.Nonce,
	})
}

// DecryptMessage decrypts a message.
// Input JSON: { "secretKey": "<base64>", "kem": "<base64>", "ciphertext": "<base64>", "nonce": "<base64>" }
// Returns JSON: { "ok": true, "plaintext": "..." }
func DecryptMessage(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		SecretKey  string `json:"secretKey"`
		Kem        string `json:"kem"`
		Ciphertext string `json:"ciphertext"`
		Nonce      string `json:"nonce"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.SecretKey == "" || params.Kem == "" || params.Ciphertext == "" || params.Nonce == "" {
		return errJSON("INVALID_INPUT", "missing secretKey, kem, ciphertext, or nonce")
	}

	plaintext, err := mcrypto.DecryptMessage(params.SecretKey, params.Kem, params.Ciphertext, params.Nonce)
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":        true,
		"plaintext": plaintext,
	})
}

// --- Helpers ---

// identityMap converts an identity.Identity to the JSON-compatible map format.
func identityMap(id *identity.Identity) map[string]interface{} {
	return map[string]interface{}{
		"peerId":     id.PeerId,
		"publicKey":  id.PublicKey,
		"privateKey": id.PrivateKey,
		"mnemonic12": id.Mnemonic12,
		"createdAt":  id.CreatedAt,
		"updatedAt":  id.UpdatedAt,
	}
}

// okJSON marshals a success map to a JSON string. If marshalling fails
// (should never happen with basic types), it falls back to an error envelope.
func okJSON(m map[string]interface{}) string {
	b, err := json.Marshal(m)
	if err != nil {
		return errJSON("INTERNAL_ERROR", fmt.Sprintf("json marshal: %v", err))
	}
	return string(b)
}

// errJSON builds a JSON error envelope string.
func errJSON(code, message string) string {
	b, _ := json.Marshal(map[string]interface{}{
		"ok":           false,
		"errorCode":    code,
		"errorMessage": message,
	})
	return string(b)
}
