// Package bridge exposes the bounded gomobile surface used by the iOS
// notification service extension. It deliberately excludes the app bridge's
// singleton, media, pubsub, and UI command graph.
package bridge

import (
	"encoding/json"
	"fmt"
	"time"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

// DecryptMessage decrypts an ML-KEM-768 + AES-256-GCM notification envelope.
func DecryptMessage(paramsJSON string) (result string) {
	defer func() {
		if recovered := recover(); recovered != nil {
			result = errorJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", recovered))
		}
	}()

	var params struct {
		SecretKey  string `json:"secretKey"`
		Kem        string `json:"kem"`
		Ciphertext string `json:"ciphertext"`
		Nonce      string `json:"nonce"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errorJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.SecretKey == "" || params.Kem == "" ||
		params.Ciphertext == "" || params.Nonce == "" {
		return errorJSON(
			"INVALID_INPUT",
			"missing secretKey, kem, ciphertext, or nonce",
		)
	}

	startedAt := time.Now()
	plaintext, err := mcrypto.DecryptMessage(
		params.SecretKey,
		params.Kem,
		params.Ciphertext,
		params.Nonce,
	)
	if err != nil {
		return errorJSON("DECRYPT_FAILED", err.Error())
	}
	return successJSON(map[string]interface{}{
		"ok":               true,
		"plaintext":        plaintext,
		"decryptMs":        time.Since(startedAt).Milliseconds(),
		"payloadSizeBytes": len(plaintext),
	})
}

// GroupDecryptMessage decrypts an AES-256-GCM group notification envelope.
func GroupDecryptMessage(paramsJSON string) (result string) {
	defer func() {
		if recovered := recover(); recovered != nil {
			result = errorJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", recovered))
		}
	}()

	var params struct {
		GroupKey   string `json:"groupKey"`
		Ciphertext string `json:"ciphertext"`
		Nonce      string `json:"nonce"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errorJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.GroupKey == "" || params.Ciphertext == "" || params.Nonce == "" {
		return errorJSON(
			"INVALID_INPUT",
			"missing groupKey, ciphertext, or nonce",
		)
	}

	plaintext, err := mcrypto.DecryptGroupMessage(
		params.GroupKey,
		params.Ciphertext,
		params.Nonce,
	)
	if err != nil {
		return errorJSON("INTERNAL_ERROR", err.Error())
	}
	return successJSON(map[string]interface{}{
		"ok":        true,
		"plaintext": plaintext,
	})
}

func successJSON(value map[string]interface{}) string {
	encoded, err := json.Marshal(value)
	if err != nil {
		return errorJSON("INTERNAL_ERROR", fmt.Sprintf("json marshal: %v", err))
	}
	return string(encoded)
}

func errorJSON(code, message string) string {
	encoded, _ := json.Marshal(map[string]interface{}{
		"ok":           false,
		"errorCode":    code,
		"errorMessage": message,
	})
	return string(encoded)
}
