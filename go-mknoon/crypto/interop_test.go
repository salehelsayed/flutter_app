package crypto

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/tyler-smith/go-bip39"
)

// -----------------------------------------------------------------------
// Shared constants for Go <-> JS interop verification.
// -----------------------------------------------------------------------

// knownMnemonic is a valid BIP39 12-word mnemonic used by both Go and JS tests
// to produce deterministic identity values.
const knownMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

// Expected deterministic values derived from knownMnemonic.
// Both Go and JS must produce exactly these strings.
const (
	expectedPeerId     = "12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj"
	expectedPublicKey  = "xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo="
	expectedPrivateKey = "XrALvdzwaQhIiairkVVWgWX1xFPMuF5wgRqu1vbaX8HFeF4YZbcIk4r/gWHVcwBklmY7GqEINOOW3FZoaaLGag=="
)

// signPayload is the message both Go and JS sign with the known identity.
const signPayload = "interop-test-payload"

// expectedSignature is the Ed25519 signature of signPayload using the known
// identity's private key. Ed25519 is deterministic, so this is a fixed vector.
const expectedSignature = "vA6No9SDLTYKdhYoEl4WGfUUA5DvQkQmtQG1UxYHP+NjwHuSQ0/EmXfOLJPx4lic/HbIvNQc0W9DxA1LRteMCw=="

// encryptPlaintext is the message used for ML-KEM encryption interop tests.
const encryptPlaintext = "Hello from Go!"

// -----------------------------------------------------------------------
// interopVectors is the JSON structure written to testdata/interop_vectors.json
// so the JS test suite can consume it.
// -----------------------------------------------------------------------

type interopVectors struct {
	Identity   identityVectors   `json:"identity"`
	Signature  signatureVectors  `json:"signature"`
	Encryption encryptionVectors `json:"encryption"`
}

type identityVectors struct {
	Mnemonic   string `json:"mnemonic"`
	PeerId     string `json:"peerId"`
	PublicKey  string `json:"publicKey"`
	PrivateKey string `json:"privateKey"`
}

type signatureVectors struct {
	Data      string `json:"data"`
	Signature string `json:"signature"`
}

type encryptionVectors struct {
	PublicKey  string `json:"publicKey"`
	SecretKey string `json:"secretKey"`
	Plaintext string `json:"plaintext"`
	Kem        string `json:"kem"`
	Ciphertext string `json:"ciphertext"`
	Nonce      string `json:"nonce"`
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

// TestInterop_IdentityFromKnownMnemonic verifies that restoring an identity
// from the known mnemonic produces the expected peerId, publicKey, and
// privateKey. These are the reference vectors that the JS test must also produce.
func TestInterop_IdentityFromKnownMnemonic(t *testing.T) {
	// Derive identity from the known mnemonic (same path as identity package).
	seed := bip39.NewSeed(knownMnemonic, "")
	edPrivKey := ed25519.NewKeyFromSeed(seed[:32])
	edPubKey := edPrivKey.Public().(ed25519.PublicKey)

	libp2pPrivKey, err := crypto.UnmarshalEd25519PrivateKey(edPrivKey)
	if err != nil {
		t.Fatalf("unmarshal ed25519 private key: %v", err)
	}

	peerID, err := peer.IDFromPublicKey(libp2pPrivKey.GetPublic())
	if err != nil {
		t.Fatalf("derive peer ID: %v", err)
	}

	publicKeyB64 := base64.StdEncoding.EncodeToString([]byte(edPubKey))
	privateKeyB64 := base64.StdEncoding.EncodeToString([]byte(edPrivKey))

	// Verify against hardcoded expected values.
	if peerID.String() != expectedPeerId {
		t.Errorf("peerId = %q, want %q", peerID.String(), expectedPeerId)
	}
	if publicKeyB64 != expectedPublicKey {
		t.Errorf("publicKey = %q, want %q", publicKeyB64, expectedPublicKey)
	}
	if privateKeyB64 != expectedPrivateKey {
		t.Errorf("privateKey = %q, want %q", privateKeyB64, expectedPrivateKey)
	}

	t.Logf("PeerId:     %s", peerID.String())
	t.Logf("PublicKey:  %s", publicKeyB64)
	t.Logf("PrivateKey: %s", privateKeyB64)
}

// TestInterop_SignVerify_FixedVectors signs the known payload with the known
// identity's private key and verifies the signature matches the expected
// deterministic value. Ed25519 signing is deterministic, so this is a true
// fixed vector that the JS test must also produce.
func TestInterop_SignVerify_FixedVectors(t *testing.T) {
	// Sign with our crypto.SignPayload function.
	sig, err := SignPayload(expectedPrivateKey, signPayload)
	if err != nil {
		t.Fatalf("SignPayload() error: %v", err)
	}

	if sig != expectedSignature {
		t.Errorf("signature = %q, want %q", sig, expectedSignature)
	}

	// Verify the signature with VerifyPayload.
	valid, err := VerifyPayload(expectedPublicKey, signPayload, sig)
	if err != nil {
		t.Fatalf("VerifyPayload() error: %v", err)
	}
	if !valid {
		t.Error("VerifyPayload() = false, want true")
	}

	t.Logf("Signature: %s", sig)
}

// TestInterop_GoEncrypt_RoundTrip generates an ML-KEM keypair, encrypts the
// known plaintext, decrypts it, and verifies the round-trip. It also writes
// the vectors to testdata/interop_vectors.json so the JS test can decrypt
// the Go-encrypted message.
func TestInterop_GoEncrypt_RoundTrip(t *testing.T) {
	// Generate ML-KEM keypair.
	kp, err := MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen() error: %v", err)
	}

	// Encrypt the known plaintext.
	encrypted, err := EncryptMessage(kp.PublicKey, encryptPlaintext)
	if err != nil {
		t.Fatalf("EncryptMessage() error: %v", err)
	}

	// Round-trip: Go encrypts, Go decrypts.
	decrypted, err := DecryptMessage(kp.SecretKey, encrypted.Kem, encrypted.Ciphertext, encrypted.Nonce)
	if err != nil {
		t.Fatalf("DecryptMessage() error: %v", err)
	}
	if decrypted != encryptPlaintext {
		t.Errorf("decrypted = %q, want %q", decrypted, encryptPlaintext)
	}

	// Verify wire sizes.
	kemBytes, _ := base64.StdEncoding.DecodeString(encrypted.Kem)
	if len(kemBytes) != 1088 {
		t.Errorf("KEM ciphertext = %d bytes, want 1088", len(kemBytes))
	}
	nonceBytes, _ := base64.StdEncoding.DecodeString(encrypted.Nonce)
	if len(nonceBytes) != 12 {
		t.Errorf("nonce = %d bytes, want 12", len(nonceBytes))
	}

	t.Logf("ML-KEM PublicKey length:  %d base64 chars", len(kp.PublicKey))
	t.Logf("ML-KEM SecretKey length:  %d base64 chars", len(kp.SecretKey))
	t.Logf("KEM ciphertext:          %d bytes", len(kemBytes))
	t.Logf("Nonce:                   %d bytes", len(nonceBytes))
}

// TestInterop_GoDecryptsOwnVector is a self-consistency check: Go generates
// a keypair, encrypts a message, and decrypts it. This ensures the encrypt
// and decrypt paths are compatible before cross-platform testing.
func TestInterop_GoDecryptsOwnVector(t *testing.T) {
	kp, err := MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen() error: %v", err)
	}

	messages := []string{
		"Hello from Go!",
		"",
		"Unicode test: \u0645\u0631\u062d\u0628\u0627 \u3053\u3093\u306b\u3061\u306f",
		"A longer message that tests AES-GCM with more data blocks to process.",
	}

	for _, msg := range messages {
		encrypted, err := EncryptMessage(kp.PublicKey, msg)
		if err != nil {
			t.Fatalf("EncryptMessage(%q) error: %v", msg, err)
		}

		decrypted, err := DecryptMessage(kp.SecretKey, encrypted.Kem, encrypted.Ciphertext, encrypted.Nonce)
		if err != nil {
			t.Fatalf("DecryptMessage(%q) error: %v", msg, err)
		}

		if decrypted != msg {
			t.Errorf("roundtrip mismatch: got %q, want %q", decrypted, msg)
		}
	}
}

// TestInterop_WriteVectorsJSON generates a complete set of interop test vectors
// and writes them to testdata/interop_vectors.json. The JS test reads this file
// to verify it can decrypt Go-encrypted messages and produce the same identity
// and signature from the known mnemonic.
//
// Run with: go test -run TestInterop_WriteVectorsJSON -v ./crypto/
// Then run the JS test to verify cross-platform compatibility.
func TestInterop_WriteVectorsJSON(t *testing.T) {
	// 1. Identity vectors (deterministic).
	idVec := identityVectors{
		Mnemonic:   knownMnemonic,
		PeerId:     expectedPeerId,
		PublicKey:  expectedPublicKey,
		PrivateKey: expectedPrivateKey,
	}

	// 2. Signature vectors (deterministic).
	sig, err := SignPayload(expectedPrivateKey, signPayload)
	if err != nil {
		t.Fatalf("SignPayload() error: %v", err)
	}
	sigVec := signatureVectors{
		Data:      signPayload,
		Signature: sig,
	}

	// 3. Encryption vectors (ML-KEM keypair + encrypted message).
	// These are NOT deterministic (randomized KEM + nonce), but the JS test
	// can use the secretKey to decrypt and verify the plaintext matches.
	kp, err := MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen() error: %v", err)
	}

	encrypted, err := EncryptMessage(kp.PublicKey, encryptPlaintext)
	if err != nil {
		t.Fatalf("EncryptMessage() error: %v", err)
	}

	// Verify the Go side can decrypt before exporting.
	decrypted, err := DecryptMessage(kp.SecretKey, encrypted.Kem, encrypted.Ciphertext, encrypted.Nonce)
	if err != nil {
		t.Fatalf("DecryptMessage() self-check error: %v", err)
	}
	if decrypted != encryptPlaintext {
		t.Fatalf("self-check decryption mismatch: got %q, want %q", decrypted, encryptPlaintext)
	}

	encVec := encryptionVectors{
		PublicKey:  kp.PublicKey,
		SecretKey:  kp.SecretKey,
		Plaintext:  encryptPlaintext,
		Kem:        encrypted.Kem,
		Ciphertext: encrypted.Ciphertext,
		Nonce:      encrypted.Nonce,
	}

	// 4. Assemble and write JSON.
	vectors := interopVectors{
		Identity:   idVec,
		Signature:  sigVec,
		Encryption: encVec,
	}

	jsonData, err := json.MarshalIndent(vectors, "", "  ")
	if err != nil {
		t.Fatalf("json.MarshalIndent() error: %v", err)
	}

	// Determine the testdata directory relative to this test file.
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	testdataDir := filepath.Join(filepath.Dir(thisFile), "..", "testdata")
	if err := os.MkdirAll(testdataDir, 0o755); err != nil {
		t.Fatalf("mkdir testdata: %v", err)
	}

	outPath := filepath.Join(testdataDir, "interop_vectors.json")
	if err := os.WriteFile(outPath, jsonData, 0o644); err != nil {
		t.Fatalf("write interop_vectors.json: %v", err)
	}

	t.Logf("Wrote interop vectors to %s", outPath)
	t.Logf("Identity peerId: %s", vectors.Identity.PeerId)
	t.Logf("Signature:       %s", vectors.Signature.Signature)
	t.Logf("Encryption KEM length: %d base64 chars", len(vectors.Encryption.Kem))
}
