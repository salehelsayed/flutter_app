package crypto

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"testing"
)

// helper generates a fresh Ed25519 key pair and returns base64-encoded strings.
func generateTestKeyPair(t *testing.T) (publicKeyBase64, privateKeyBase64 string) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	return base64.StdEncoding.EncodeToString(pub), base64.StdEncoding.EncodeToString(priv)
}

func TestSignAndVerify(t *testing.T) {
	pubB64, privB64 := generateTestKeyPair(t)
	data := "hello, mknoon"

	sig, err := SignPayload(privB64, data)
	if err != nil {
		t.Fatalf("SignPayload: %v", err)
	}

	ok, err := VerifyPayload(pubB64, data, sig)
	if err != nil {
		t.Fatalf("VerifyPayload: %v", err)
	}
	if !ok {
		t.Fatal("expected signature to be valid")
	}
}

func TestVerifyWrongData(t *testing.T) {
	pubB64, privB64 := generateTestKeyPair(t)

	sig, err := SignPayload(privB64, "original data")
	if err != nil {
		t.Fatalf("SignPayload: %v", err)
	}

	ok, err := VerifyPayload(pubB64, "tampered data", sig)
	if err != nil {
		t.Fatalf("VerifyPayload: %v", err)
	}
	if ok {
		t.Fatal("expected signature verification to fail for wrong data")
	}
}

func TestVerifyWrongKey(t *testing.T) {
	_, privB64 := generateTestKeyPair(t)
	otherPubB64, _ := generateTestKeyPair(t)

	sig, err := SignPayload(privB64, "some data")
	if err != nil {
		t.Fatalf("SignPayload: %v", err)
	}

	ok, err := VerifyPayload(otherPubB64, "some data", sig)
	if err != nil {
		t.Fatalf("VerifyPayload: %v", err)
	}
	if ok {
		t.Fatal("expected signature verification to fail for wrong key")
	}
}

func TestSignPayloadFormat(t *testing.T) {
	_, privB64 := generateTestKeyPair(t)

	sig, err := SignPayload(privB64, "format check")
	if err != nil {
		t.Fatalf("SignPayload: %v", err)
	}

	sigBytes, err := base64.StdEncoding.DecodeString(sig)
	if err != nil {
		t.Fatalf("signature is not valid base64: %v", err)
	}

	if len(sigBytes) != ed25519.SignatureSize {
		t.Fatalf("signature length: got %d, want %d", len(sigBytes), ed25519.SignatureSize)
	}
}
