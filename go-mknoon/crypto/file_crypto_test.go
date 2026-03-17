package crypto

import (
	"bytes"
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGenerateSymmetricKey(t *testing.T) {
	key, err := GenerateSymmetricKey()
	if err != nil {
		t.Fatalf("GenerateSymmetricKey: %v", err)
	}
	decoded, err := base64.StdEncoding.DecodeString(key)
	if err != nil {
		t.Fatalf("decode key: %v", err)
	}
	if len(decoded) != 32 {
		t.Fatalf("expected 32-byte key, got %d", len(decoded))
	}
}

func TestEncryptDecryptFileRoundTrip(t *testing.T) {
	dir := t.TempDir()
	plainPath := filepath.Join(dir, "test.bin")
	original := []byte("hello world — repost media test content")
	if err := os.WriteFile(plainPath, original, 0600); err != nil {
		t.Fatal(err)
	}

	key, err := GenerateSymmetricKey()
	if err != nil {
		t.Fatal(err)
	}

	encPath, nonce, err := EncryptFile(plainPath, key)
	if err != nil {
		t.Fatalf("EncryptFile: %v", err)
	}

	// Ciphertext must differ from plaintext.
	ct, _ := os.ReadFile(encPath)
	if bytes.Equal(ct, original) {
		t.Fatal("ciphertext equals plaintext")
	}

	decPath, err := DecryptFile(encPath, key, nonce)
	if err != nil {
		t.Fatalf("DecryptFile: %v", err)
	}
	recovered, _ := os.ReadFile(decPath)
	if !bytes.Equal(recovered, original) {
		t.Fatal("decrypted content does not match original")
	}
}

func TestDecryptWithWrongKeyFails(t *testing.T) {
	dir := t.TempDir()
	plainPath := filepath.Join(dir, "test.bin")
	if err := os.WriteFile(plainPath, []byte("secret data"), 0600); err != nil {
		t.Fatal(err)
	}

	key1, _ := GenerateSymmetricKey()
	key2, _ := GenerateSymmetricKey()

	encPath, nonce, err := EncryptFile(plainPath, key1)
	if err != nil {
		t.Fatal(err)
	}

	_, err = DecryptFile(encPath, key2, nonce)
	if err == nil {
		t.Fatal("expected error decrypting with wrong key")
	}
	if !strings.Contains(err.Error(), "aes-gcm decrypt") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDecryptCorruptedCiphertextFails(t *testing.T) {
	dir := t.TempDir()
	plainPath := filepath.Join(dir, "test.bin")
	if err := os.WriteFile(plainPath, []byte("data to corrupt"), 0600); err != nil {
		t.Fatal(err)
	}

	key, _ := GenerateSymmetricKey()
	encPath, nonce, err := EncryptFile(plainPath, key)
	if err != nil {
		t.Fatal(err)
	}

	// Corrupt one byte.
	ct, _ := os.ReadFile(encPath)
	ct[0] ^= 0xFF
	os.WriteFile(encPath, ct, 0600)

	_, err = DecryptFile(encPath, key, nonce)
	if err == nil {
		t.Fatal("expected GCM authentication error")
	}
}

func TestLargeFileRoundTrip(t *testing.T) {
	dir := t.TempDir()
	plainPath := filepath.Join(dir, "large.bin")

	// 5 MB file.
	data := make([]byte, 5*1024*1024)
	for i := range data {
		data[i] = byte(i % 256)
	}
	if err := os.WriteFile(plainPath, data, 0600); err != nil {
		t.Fatal(err)
	}

	key, _ := GenerateSymmetricKey()
	encPath, nonce, err := EncryptFile(plainPath, key)
	if err != nil {
		t.Fatalf("EncryptFile 5MB: %v", err)
	}

	decPath, err := DecryptFile(encPath, key, nonce)
	if err != nil {
		t.Fatalf("DecryptFile 5MB: %v", err)
	}
	recovered, _ := os.ReadFile(decPath)
	if !bytes.Equal(recovered, data) {
		t.Fatal("large file round-trip mismatch")
	}
}
