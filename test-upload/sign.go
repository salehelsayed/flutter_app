package crypto

import (
	"crypto/ed25519"
	"encoding/base64"
	"fmt"
)

// SignPayload signs data with an Ed25519 private key.
// privateKeyBase64: base64-encoded 64-byte Ed25519 private key (seed + public key).
// data: the string data to sign.
// Returns: base64-encoded 64-byte Ed25519 signature.
func SignPayload(privateKeyBase64 string, data string) (string, error) {
	privBytes, err := base64.StdEncoding.DecodeString(privateKeyBase64)
	if err != nil {
		return "", fmt.Errorf("decode private key: %w", err)
	}
	if len(privBytes) != ed25519.PrivateKeySize {
		return "", fmt.Errorf("invalid private key length: got %d, want %d", len(privBytes), ed25519.PrivateKeySize)
	}

	sig := ed25519.Sign(ed25519.PrivateKey(privBytes), []byte(data))
	return base64.StdEncoding.EncodeToString(sig), nil
}

// VerifyPayload verifies an Ed25519 signature.
// publicKeyBase64: base64-encoded 32-byte Ed25519 public key.
// data: the string data that was signed.
// signatureBase64: base64-encoded 64-byte signature.
// Returns: true if the signature is valid.
func VerifyPayload(publicKeyBase64 string, data string, signatureBase64 string) (bool, error) {
	pubBytes, err := base64.StdEncoding.DecodeString(publicKeyBase64)
	if err != nil {
		return false, fmt.Errorf("decode public key: %w", err)
	}
	if len(pubBytes) != ed25519.PublicKeySize {
		return false, fmt.Errorf("invalid public key length: got %d, want %d", len(pubBytes), ed25519.PublicKeySize)
	}

	sigBytes, err := base64.StdEncoding.DecodeString(signatureBase64)
	if err != nil {
		return false, fmt.Errorf("decode signature: %w", err)
	}
	if len(sigBytes) != ed25519.SignatureSize {
		return false, fmt.Errorf("invalid signature length: got %d, want %d", len(sigBytes), ed25519.SignatureSize)
	}

	return ed25519.Verify(ed25519.PublicKey(pubBytes), []byte(data), sigBytes), nil
}
