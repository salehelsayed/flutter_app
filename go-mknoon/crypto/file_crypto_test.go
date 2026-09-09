package crypto

import (
	"bytes"
	"encoding/base64"
	"errors"
	"os"
	"path/filepath"
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
	if !errors.Is(err, ErrFileAuthentication) {
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
	if !errors.Is(err, ErrFileAuthentication) {
		t.Fatal("tampered bytes must be classified as authentication failure")
	}
}

func TestDecryptFileIOPreservesCauseAndAllowsRetry(t *testing.T) {
	key, err := GenerateSymmetricKey()
	if err != nil {
		t.Fatal(err)
	}
	nonce := base64.StdEncoding.EncodeToString(make([]byte, 12))
	src := filepath.Join(t.TempDir(), "media.bin")
	_, err = DecryptFile(src, key, nonce)
	if !errors.Is(err, ErrFileIO) || !errors.Is(err, os.ErrNotExist) {
		t.Fatal("missing input must retain both I/O classification and filesystem cause")
	}
	plaintext := []byte("valid encrypted bytes remain recoverable")
	if err := os.WriteFile(src, plaintext, 0o600); err != nil {
		t.Fatal(err)
	}
	cipherPath, nonce, err := EncryptFile(src, key)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(cipherPath+".dec", 0o700); err != nil {
		t.Fatal(err)
	}
	path, err := DecryptFile(cipherPath, key, nonce)
	var pathError *os.PathError
	if path != "" || !errors.Is(err, ErrFileIO) || !errors.As(err, &pathError) || errors.Is(err, ErrFileAuthentication) {
		t.Fatal("blocked output must preserve its I/O cause without claiming authentication failure")
	}
	if err := os.Remove(cipherPath + ".dec"); err != nil {
		t.Fatal(err)
	}
	path, err = DecryptFile(cipherPath, key, nonce)
	if err != nil {
		t.Fatal(err)
	}
	recovered, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(recovered, plaintext) {
		t.Fatal("unblocked output did not recover the original authenticated bytes")
	}
}

func TestDecryptFileRejectsMetadataBeforeFileIO(t *testing.T) {
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	nonce := base64.StdEncoding.EncodeToString(make([]byte, 12))
	for _, tc := range []struct{ name, key, nonce string }{
		{"empty_key", "", nonce},
		{"invalid_key_encoding", "!", nonce},
		{"short_key", base64.StdEncoding.EncodeToString(make([]byte, 31)), nonce},
		{"long_key", base64.StdEncoding.EncodeToString(make([]byte, 33)), nonce},
		{"empty_nonce", key, ""},
		{"invalid_nonce_encoding", key, "!"},
		{"short_nonce", key, base64.StdEncoding.EncodeToString(make([]byte, 11))},
		{"long_nonce", key, base64.StdEncoding.EncodeToString(make([]byte, 13))},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path, err := DecryptFile(filepath.Join(t.TempDir(), "missing"), tc.key, tc.nonce)
			if path != "" || !errors.Is(err, ErrFileMetadata) || errors.Is(err, ErrFileIO) || errors.Is(err, ErrFileAuthentication) {
				t.Fatal("invalid metadata must fail closed before reading a file or attempting authentication")
			}
		})
	}
}

func TestLargeFileRoundTrip(t *testing.T) {
	for _, tc := range []struct {
		name string
		size int
	}{
		{"five_mebibytes", 5 * 1024 * 1024},
		{"reported_cipher_size_4634918", 4634918 - 16},
		{"reported_cipher_size_4401190", 4401190 - 16},
	} {
		t.Run(tc.name, func(t *testing.T) {
			plainPath := filepath.Join(t.TempDir(), "large.bin")
			// Synthetic bytes only; the GCM tag accounts for the extra16 bytes.
			data := make([]byte, tc.size)
			for i := range data {
				data[i] = byte(i % 256)
			}
			if err := os.WriteFile(plainPath, data, 0600); err != nil {
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
			cipherInfo, err := os.Stat(encPath)
			if err != nil || cipherInfo.Size() != int64(tc.size+16) {
				t.Fatal("ciphertext size must equal plaintext plus the GCM tag")
			}
			decPath, err := DecryptFile(encPath, key, nonce)
			if err != nil {
				t.Fatalf("DecryptFile: %v", err)
			}
			recovered, err := os.ReadFile(decPath)
			if err != nil || !bytes.Equal(recovered, data) {
				t.Fatal("large file round-trip mismatch")
			}
		})
	}
}
