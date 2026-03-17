package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"os"
)

// GenerateSymmetricKey generates a random 32-byte AES-256 key and returns
// it as a base64-encoded string.
func GenerateSymmetricKey() (string, error) {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return "", fmt.Errorf("generate symmetric key: %w", err)
	}
	return base64.StdEncoding.EncodeToString(key), nil
}

// EncryptFile encrypts the file at filePath using AES-256-GCM with the
// provided base64-encoded 32-byte key. A random 12-byte nonce is generated.
// The ciphertext is written to filePath + ".enc".
// Returns (encryptedFilePath, base64Nonce, error).
func EncryptFile(filePath string, keyBase64 string) (string, string, error) {
	key, err := base64.StdEncoding.DecodeString(keyBase64)
	if err != nil {
		return "", "", fmt.Errorf("decode key: %w", err)
	}
	if len(key) != 32 {
		return "", "", fmt.Errorf("invalid key length: got %d, want 32", len(key))
	}

	plaintext, err := os.ReadFile(filePath)
	if err != nil {
		return "", "", fmt.Errorf("read file: %w", err)
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", "", fmt.Errorf("aes new cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", "", fmt.Errorf("aes new gcm: %w", err)
	}

	nonce := make([]byte, 12)
	if _, err := rand.Read(nonce); err != nil {
		return "", "", fmt.Errorf("generate nonce: %w", err)
	}

	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)

	encryptedPath := filePath + ".enc"
	if err := os.WriteFile(encryptedPath, ciphertext, 0600); err != nil {
		return "", "", fmt.Errorf("write encrypted file: %w", err)
	}

	return encryptedPath, base64.StdEncoding.EncodeToString(nonce), nil
}

// DecryptFile decrypts the file at filePath using AES-256-GCM with the
// provided base64-encoded key and nonce. The plaintext is written to
// filePath + ".dec".
// Returns (decryptedFilePath, error).
func DecryptFile(filePath string, keyBase64 string, nonceBase64 string) (string, error) {
	key, err := base64.StdEncoding.DecodeString(keyBase64)
	if err != nil {
		return "", fmt.Errorf("decode key: %w", err)
	}
	if len(key) != 32 {
		return "", fmt.Errorf("invalid key length: got %d, want 32", len(key))
	}

	nonce, err := base64.StdEncoding.DecodeString(nonceBase64)
	if err != nil {
		return "", fmt.Errorf("decode nonce: %w", err)
	}

	ciphertext, err := os.ReadFile(filePath)
	if err != nil {
		return "", fmt.Errorf("read file: %w", err)
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("aes new cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("aes new gcm: %w", err)
	}

	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", fmt.Errorf("aes-gcm decrypt: %w", err)
	}

	decryptedPath := filePath + ".dec"
	if err := os.WriteFile(decryptedPath, plaintext, 0600); err != nil {
		return "", fmt.Errorf("write decrypted file: %w", err)
	}

	return decryptedPath, nil
}
