package crypto

import (
	"encoding/base64"
	"testing"
)

// TestMlKemKeygen generates a key pair and verifies the raw byte sizes
// match ML-KEM-768: public key 1184 bytes, secret key 2400 bytes.
func TestMlKemKeygen(t *testing.T) {
	kp, err := MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen() error: %v", err)
	}

	if kp.PublicKey == "" {
		t.Fatal("PublicKey is empty")
	}
	if kp.SecretKey == "" {
		t.Fatal("SecretKey is empty")
	}

	pkBytes, err := base64.StdEncoding.DecodeString(kp.PublicKey)
	if err != nil {
		t.Fatalf("decode public key: %v", err)
	}
	if len(pkBytes) != 1184 {
		t.Errorf("public key length = %d, want 1184", len(pkBytes))
	}

	skBytes, err := base64.StdEncoding.DecodeString(kp.SecretKey)
	if err != nil {
		t.Fatalf("decode secret key: %v", err)
	}
	if len(skBytes) != 2400 {
		t.Errorf("secret key length = %d, want 2400", len(skBytes))
	}
}

// TestEncryptDecryptRoundTrip generates a key pair, encrypts a message,
// then decrypts it and verifies the plaintext matches.
func TestEncryptDecryptRoundTrip(t *testing.T) {
	kp, err := MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen() error: %v", err)
	}

	original := "Hello, post-quantum world! This is a secret message."

	encrypted, err := EncryptMessage(kp.PublicKey, original)
	if err != nil {
		t.Fatalf("EncryptMessage() error: %v", err)
	}

	// Verify encrypted fields are non-empty base64.
	if encrypted.Kem == "" {
		t.Error("encrypted.Kem is empty")
	}
	if encrypted.Ciphertext == "" {
		t.Error("encrypted.Ciphertext is empty")
	}
	if encrypted.Nonce == "" {
		t.Error("encrypted.Nonce is empty")
	}

	// Verify KEM ciphertext is 1088 bytes.
	kemBytes, err := base64.StdEncoding.DecodeString(encrypted.Kem)
	if err != nil {
		t.Fatalf("decode kem: %v", err)
	}
	if len(kemBytes) != 1088 {
		t.Errorf("kem ciphertext length = %d, want 1088", len(kemBytes))
	}

	// Verify nonce is 12 bytes.
	nonceBytes, err := base64.StdEncoding.DecodeString(encrypted.Nonce)
	if err != nil {
		t.Fatalf("decode nonce: %v", err)
	}
	if len(nonceBytes) != 12 {
		t.Errorf("nonce length = %d, want 12", len(nonceBytes))
	}

	// Decrypt and verify.
	decrypted, err := DecryptMessage(kp.SecretKey, encrypted.Kem, encrypted.Ciphertext, encrypted.Nonce)
	if err != nil {
		t.Fatalf("DecryptMessage() error: %v", err)
	}

	if decrypted != original {
		t.Errorf("decrypted = %q, want %q", decrypted, original)
	}
}

// TestEncryptDifferentMessages verifies that encrypting different plaintexts
// with the same public key produces different ciphertexts (due to randomized
// KEM encapsulation and random AES-GCM nonces).
func TestEncryptDifferentMessages(t *testing.T) {
	kp, err := MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen() error: %v", err)
	}

	enc1, err := EncryptMessage(kp.PublicKey, "message one")
	if err != nil {
		t.Fatalf("EncryptMessage(#1) error: %v", err)
	}

	enc2, err := EncryptMessage(kp.PublicKey, "message two")
	if err != nil {
		t.Fatalf("EncryptMessage(#2) error: %v", err)
	}

	// KEM ciphertexts must differ (different random encapsulation seeds).
	if enc1.Kem == enc2.Kem {
		t.Error("KEM ciphertexts should differ for different encryptions")
	}

	// AES ciphertexts must differ (different plaintext and nonce).
	if enc1.Ciphertext == enc2.Ciphertext {
		t.Error("AES ciphertexts should differ for different plaintexts")
	}

	// Nonces must differ (randomly generated).
	if enc1.Nonce == enc2.Nonce {
		t.Error("nonces should differ for different encryptions")
	}
}

// TestDecryptWrongKey encrypts with one key pair and attempts to decrypt
// with a different secret key. This should fail because the wrong key
// produces a different shared secret, causing AES-GCM auth tag verification
// to fail (or ML-KEM implicit rejection produces garbage shared secret).
func TestDecryptWrongKey(t *testing.T) {
	// Generate two independent key pairs.
	kp1, err := MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen() #1 error: %v", err)
	}

	kp2, err := MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen() #2 error: %v", err)
	}

	// Encrypt with kp1's public key.
	encrypted, err := EncryptMessage(kp1.PublicKey, "secret for kp1")
	if err != nil {
		t.Fatalf("EncryptMessage() error: %v", err)
	}

	// Attempt to decrypt with kp2's secret key. This should either error or
	// return garbage (ML-KEM implicit rejection). We check that the plaintext
	// does NOT match the original.
	decrypted, err := DecryptMessage(kp2.SecretKey, encrypted.Kem, encrypted.Ciphertext, encrypted.Nonce)
	if err == nil && decrypted == "secret for kp1" {
		t.Error("decryption with wrong key should not produce the original plaintext")
	}
	// If err != nil, that's the expected outcome (AES-GCM auth tag mismatch).
}
