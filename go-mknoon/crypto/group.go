package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"fmt"
)

// GenerateGroupKey generates a random 32-byte AES-256 key for group
// symmetric encryption and returns it as a base64-encoded string.
func GenerateGroupKey() (string, error) {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return "", fmt.Errorf("generate group key: %w", err)
	}
	return base64.StdEncoding.EncodeToString(key), nil
}

// EncryptGroupMessage encrypts plaintext using AES-256-GCM with the given
// base64-encoded group key. Returns base64-encoded ciphertext and nonce.
//
// The key must be exactly 32 bytes (decoded). A random 12-byte nonce is
// generated for each call. The ciphertext includes the 16-byte GCM auth tag.
func EncryptGroupMessage(groupKeyB64, plaintext string) (ctB64, nonceB64 string, err error) {
	// 1. Decode key from base64.
	key, err := base64.StdEncoding.DecodeString(groupKeyB64)
	if err != nil {
		return "", "", fmt.Errorf("decode group key: %w", err)
	}

	if len(key) != 32 {
		return "", "", fmt.Errorf("invalid group key length: got %d, want 32", len(key))
	}

	// 2. Create AES cipher.
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", "", fmt.Errorf("aes new cipher: %w", err)
	}

	// 3. Create GCM.
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", "", fmt.Errorf("aes new gcm: %w", err)
	}

	// 4. Random 12-byte nonce.
	nonce := make([]byte, 12)
	if _, err := rand.Read(nonce); err != nil {
		return "", "", fmt.Errorf("generate nonce: %w", err)
	}

	// 5. Seal: appends ciphertext + 16-byte auth tag to dst (nil).
	ciphertext := gcm.Seal(nil, nonce, []byte(plaintext), nil)

	return base64.StdEncoding.EncodeToString(ciphertext),
		base64.StdEncoding.EncodeToString(nonce),
		nil
}

// DecryptGroupMessage decrypts AES-256-GCM ciphertext using the given
// base64-encoded group key and nonce. Returns the plaintext string.
func DecryptGroupMessage(groupKeyB64, ctB64, nonceB64 string) (string, error) {
	// 1. Decode all inputs from base64.
	key, err := base64.StdEncoding.DecodeString(groupKeyB64)
	if err != nil {
		return "", fmt.Errorf("decode group key: %w", err)
	}

	if len(key) != 32 {
		return "", fmt.Errorf("invalid group key length: got %d, want 32", len(key))
	}

	ciphertext, err := base64.StdEncoding.DecodeString(ctB64)
	if err != nil {
		return "", fmt.Errorf("decode ciphertext: %w", err)
	}

	nonce, err := base64.StdEncoding.DecodeString(nonceB64)
	if err != nil {
		return "", fmt.Errorf("decode nonce: %w", err)
	}

	// 2. Create AES cipher.
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("aes new cipher: %w", err)
	}

	// 3. Create GCM.
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("aes new gcm: %w", err)
	}

	// 4. Open: decrypt and verify auth tag.
	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", fmt.Errorf("aes-gcm decrypt: %w", err)
	}

	return string(plaintext), nil
}

// BuildGroupSignatureData constructs the deterministic string that gets signed
// to authenticate a group message: "groupId|epoch|ciphertext".
func BuildGroupSignatureData(groupId string, keyEpoch int, ctB64 string) string {
	return fmt.Sprintf("%s|%d|%s", groupId, keyEpoch, ctB64)
}
