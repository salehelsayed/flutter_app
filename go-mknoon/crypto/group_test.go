package crypto

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestGenerateGroupKey_Length(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	keyBytes, err := base64.StdEncoding.DecodeString(keyB64)
	if err != nil {
		t.Fatalf("decode group key: %v", err)
	}

	if len(keyBytes) != 32 {
		t.Errorf("group key length = %d, want 32", len(keyBytes))
	}
}

func TestGenerateGroupKey_Unique(t *testing.T) {
	key1, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() #1 error: %v", err)
	}

	key2, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() #2 error: %v", err)
	}

	if key1 == key2 {
		t.Error("two generated group keys should be different")
	}
}

func TestGroupEncryptDecrypt_RoundTrip(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	original := "Hello, group messaging! This is a secret."

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, original)
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	if ctB64 == "" {
		t.Error("ciphertext is empty")
	}
	if nonceB64 == "" {
		t.Error("nonce is empty")
	}

	decrypted, err := DecryptGroupMessage(keyB64, ctB64, nonceB64)
	if err != nil {
		t.Fatalf("DecryptGroupMessage() error: %v", err)
	}

	if decrypted != original {
		t.Errorf("decrypted = %q, want %q", decrypted, original)
	}
}

func TestGroupEncryptDecrypt_WrongKey(t *testing.T) {
	key1, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() #1 error: %v", err)
	}

	key2, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() #2 error: %v", err)
	}

	ctB64, nonceB64, err := EncryptGroupMessage(key1, "secret for key1")
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	_, err = DecryptGroupMessage(key2, ctB64, nonceB64)
	if err == nil {
		t.Error("decryption with wrong key should fail")
	}
}

func TestGroupEncryptDecrypt_TamperedCiphertext(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, "do not tamper")
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	// Tamper with ciphertext by decoding, flipping a byte, and re-encoding.
	ctBytes, _ := base64.StdEncoding.DecodeString(ctB64)
	ctBytes[0] ^= 0xFF
	tamperedCt := base64.StdEncoding.EncodeToString(ctBytes)

	_, err = DecryptGroupMessage(keyB64, tamperedCt, nonceB64)
	if err == nil {
		t.Error("decryption with tampered ciphertext should fail")
	}
}

func TestGroupEncryptDecrypt_TamperedNonce(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, "do not tamper nonce")
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	// Tamper with nonce by decoding, flipping a byte, and re-encoding.
	nonceBytes, _ := base64.StdEncoding.DecodeString(nonceB64)
	nonceBytes[0] ^= 0xFF
	tamperedNonce := base64.StdEncoding.EncodeToString(nonceBytes)

	_, err = DecryptGroupMessage(keyB64, ctB64, tamperedNonce)
	if err == nil {
		t.Error("decryption with tampered nonce should fail")
	}
}

func TestGroupEncryptDecrypt_UniqueNonces(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	plaintext := "same message both times"

	_, nonce1, err := EncryptGroupMessage(keyB64, plaintext)
	if err != nil {
		t.Fatalf("EncryptGroupMessage() #1 error: %v", err)
	}

	_, nonce2, err := EncryptGroupMessage(keyB64, plaintext)
	if err != nil {
		t.Fatalf("EncryptGroupMessage() #2 error: %v", err)
	}

	if nonce1 == nonce2 {
		t.Error("nonces should differ for different encryptions")
	}
}

func TestGroupEncryptDecrypt_EmptyString(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, "")
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	decrypted, err := DecryptGroupMessage(keyB64, ctB64, nonceB64)
	if err != nil {
		t.Fatalf("DecryptGroupMessage() error: %v", err)
	}

	if decrypted != "" {
		t.Errorf("decrypted = %q, want empty string", decrypted)
	}
}

func TestGroupEncryptDecrypt_LargeMessage(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	// 1 MB plaintext.
	original := strings.Repeat("A", 1024*1024)

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, original)
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	decrypted, err := DecryptGroupMessage(keyB64, ctB64, nonceB64)
	if err != nil {
		t.Fatalf("DecryptGroupMessage() error: %v", err)
	}

	if decrypted != original {
		t.Errorf("decrypted length = %d, want %d", len(decrypted), len(original))
	}
}

func TestEncryptGroupMessage_InvalidKey(t *testing.T) {
	_, _, err := EncryptGroupMessage("not-valid-base64!!!", "hello")
	if err == nil {
		t.Error("EncryptGroupMessage with non-base64 key should fail")
	}
}

func TestEncryptGroupMessage_WrongKeyLength(t *testing.T) {
	// 16-byte key (AES-128) instead of required 32-byte (AES-256).
	shortKey := make([]byte, 16)
	shortKeyB64 := base64.StdEncoding.EncodeToString(shortKey)

	_, _, err := EncryptGroupMessage(shortKeyB64, "hello")
	if err == nil {
		t.Error("EncryptGroupMessage with 16-byte key should fail")
	}
}

func TestDecryptGroupMessage_InvalidBase64(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	// Invalid base64 for ciphertext.
	_, err = DecryptGroupMessage(keyB64, "not-valid!!!", "AAAAAAAAAAAAAAAA")
	if err == nil {
		t.Error("DecryptGroupMessage with invalid ciphertext base64 should fail")
	}

	// Invalid base64 for nonce.
	_, err = DecryptGroupMessage(keyB64, "AAAAAAAAAA==", "not-valid!!!")
	if err == nil {
		t.Error("DecryptGroupMessage with invalid nonce base64 should fail")
	}

	// Invalid base64 for key.
	_, err = DecryptGroupMessage("not-valid!!!", "AAAAAAAAAA==", "AAAAAAAAAAAAAAAA")
	if err == nil {
		t.Error("DecryptGroupMessage with invalid key base64 should fail")
	}
}

func TestBuildGroupSignatureData_Format(t *testing.T) {
	result := BuildGroupSignatureData("group-abc-123", 5, "c2VjcmV0")
	expected := "group-abc-123|5|c2VjcmV0"

	if result != expected {
		t.Errorf("BuildGroupSignatureData = %q, want %q", result, expected)
	}
}

func TestBuildGroupSignatureData_Deterministic(t *testing.T) {
	r1 := BuildGroupSignatureData("grp1", 1, "ct1")
	r2 := BuildGroupSignatureData("grp1", 1, "ct1")

	if r1 != r2 {
		t.Errorf("BuildGroupSignatureData not deterministic: %q != %q", r1, r2)
	}
}
