package crypto

import (
	"crypto/ed25519"
	"encoding/base64"
	"testing"
)

func TestSignVerify_RoundTrip(t *testing.T) {
	pubB64, privB64 := generateTestKeyPair(t)

	data := "Hello, Ed25519 signing!"

	sig, err := SignPayload(privB64, data)
	if err != nil {
		t.Fatalf("SignPayload() error: %v", err)
	}

	if sig == "" {
		t.Fatal("SignPayload() returned empty signature")
	}

	// Verify the signature is 64 bytes when decoded.
	sigBytes, err := base64.StdEncoding.DecodeString(sig)
	if err != nil {
		t.Fatalf("decode signature: %v", err)
	}
	if len(sigBytes) != ed25519.SignatureSize {
		t.Errorf("signature length = %d, want %d", len(sigBytes), ed25519.SignatureSize)
	}

	valid, err := VerifyPayload(pubB64, data, sig)
	if err != nil {
		t.Fatalf("VerifyPayload() error: %v", err)
	}

	if !valid {
		t.Error("VerifyPayload() = false, want true")
	}
}

func TestVerify_WrongPublicKey(t *testing.T) {
	_, privB64 := generateTestKeyPair(t)
	otherPubB64, _ := generateTestKeyPair(t)

	data := "message signed by first key"

	sig, err := SignPayload(privB64, data)
	if err != nil {
		t.Fatalf("SignPayload() error: %v", err)
	}

	valid, err := VerifyPayload(otherPubB64, data, sig)
	if err != nil {
		t.Fatalf("VerifyPayload() error: %v", err)
	}

	if valid {
		t.Error("VerifyPayload() with wrong public key = true, want false")
	}
}

func TestVerify_TamperedData(t *testing.T) {
	pubB64, privB64 := generateTestKeyPair(t)

	originalData := "original message"

	sig, err := SignPayload(privB64, originalData)
	if err != nil {
		t.Fatalf("SignPayload() error: %v", err)
	}

	tamperedData := "tampered message"

	valid, err := VerifyPayload(pubB64, tamperedData, sig)
	if err != nil {
		t.Fatalf("VerifyPayload() error: %v", err)
	}

	if valid {
		t.Error("VerifyPayload() with tampered data = true, want false")
	}
}

func TestVerify_TamperedSignature(t *testing.T) {
	pubB64, privB64 := generateTestKeyPair(t)

	data := "important data"

	sig, err := SignPayload(privB64, data)
	if err != nil {
		t.Fatalf("SignPayload() error: %v", err)
	}

	// Corrupt the signature by flipping a byte.
	sigBytes, err := base64.StdEncoding.DecodeString(sig)
	if err != nil {
		t.Fatalf("decode signature: %v", err)
	}
	sigBytes[0] ^= 0xFF
	tamperedSig := base64.StdEncoding.EncodeToString(sigBytes)

	valid, err := VerifyPayload(pubB64, data, tamperedSig)
	if err != nil {
		t.Fatalf("VerifyPayload() error: %v", err)
	}

	if valid {
		t.Error("VerifyPayload() with tampered signature = true, want false")
	}
}

func TestSign_InvalidPrivateKeyLength(t *testing.T) {
	shortKey := base64.StdEncoding.EncodeToString([]byte("too short"))

	_, err := SignPayload(shortKey, "data")
	if err == nil {
		t.Error("SignPayload() with invalid key length should return error")
	}
}

func TestVerify_InvalidPublicKeyLength(t *testing.T) {
	shortKey := base64.StdEncoding.EncodeToString([]byte("short"))
	dummySig := base64.StdEncoding.EncodeToString(make([]byte, 64))

	_, err := VerifyPayload(shortKey, "data", dummySig)
	if err == nil {
		t.Error("VerifyPayload() with invalid public key length should return error")
	}
}

func TestVerify_InvalidSignatureLength(t *testing.T) {
	pubB64, _ := generateTestKeyPair(t)
	shortSig := base64.StdEncoding.EncodeToString([]byte("short"))

	_, err := VerifyPayload(pubB64, "data", shortSig)
	if err == nil {
		t.Error("VerifyPayload() with invalid signature length should return error")
	}
}
