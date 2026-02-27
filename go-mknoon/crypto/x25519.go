package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha512"
	"encoding/base64"
	"fmt"
	"io"

	"filippo.io/edwards25519"
	"golang.org/x/crypto/curve25519"
	"golang.org/x/crypto/hkdf"

	"crypto/sha256"
)

const hkdfInfo = "mknoon-contact-request-v1"

// EncryptedContactRequest holds the v2 contact request encrypted fields, all base64-encoded.
type EncryptedContactRequest struct {
	EphemeralPublicKey string // base64-encoded 32-byte X25519 ephemeral public key
	Ciphertext         string // base64-encoded AES-256-GCM ciphertext+tag
	Nonce              string // base64-encoded 12-byte nonce
}

// EdPublicKeyToX25519 converts an Ed25519 public key to an X25519 (Montgomery) public key.
// Uses the birational map: u = (1+y)/(1-y) via filippo.io/edwards25519.
func EdPublicKeyToX25519(edPub []byte) ([]byte, error) {
	if len(edPub) != 32 {
		return nil, fmt.Errorf("ed25519 public key must be 32 bytes, got %d", len(edPub))
	}

	p, err := new(edwards25519.Point).SetBytes(edPub)
	if err != nil {
		return nil, fmt.Errorf("set edwards point: %w", err)
	}

	return p.BytesMontgomery(), nil
}

// EdPrivateKeyToX25519 converts an Ed25519 private key (64 bytes = seed||pub) to
// an X25519 scalar using SHA-512(seed[:32]) with RFC 7748 clamping.
func EdPrivateKeyToX25519(edPriv []byte) ([]byte, error) {
	if len(edPriv) != 64 {
		return nil, fmt.Errorf("ed25519 private key must be 64 bytes, got %d", len(edPriv))
	}

	// SHA-512 of the 32-byte seed
	h := sha512.Sum512(edPriv[:32])
	scalar := h[:32]

	// RFC 7748 clamping
	scalar[0] &= 248  // clear 3 LSB
	scalar[31] &= 127 // clear bit 7
	scalar[31] |= 64  // set bit 6

	return scalar, nil
}

// x25519ECDH performs X25519 Diffie-Hellman and rejects all-zero shared secrets
// (small subgroup attack).
func x25519ECDH(privateKey, publicKey []byte) ([]byte, error) {
	shared, err := curve25519.X25519(privateKey, publicKey)
	if err != nil {
		return nil, fmt.Errorf("x25519: %w", err)
	}

	// Reject all-zero shared secret (small subgroup)
	allZero := true
	for _, b := range shared {
		if b != 0 {
			allZero = false
			break
		}
	}
	if allZero {
		return nil, fmt.Errorf("x25519: all-zero shared secret (small subgroup attack)")
	}

	return shared, nil
}

// deriveAESKey derives a 32-byte AES-256 key from a shared secret using HKDF-SHA256.
// Salt is the ephemeral public key; info is a fixed context string.
func deriveAESKey(sharedSecret, ephemeralPub []byte) ([]byte, error) {
	hkdfReader := hkdf.New(sha256.New, sharedSecret, ephemeralPub, []byte(hkdfInfo))
	key := make([]byte, 32)
	if _, err := io.ReadFull(hkdfReader, key); err != nil {
		return nil, fmt.Errorf("hkdf: %w", err)
	}
	return key, nil
}

// buildAAD builds the Additional Authenticated Data from msgId and ts.
// Format: "msgId|ts" — deterministic, prevents relay from tampering with outer fields.
func buildAAD(msgId, ts string) []byte {
	return []byte(msgId + "|" + ts)
}

// EncryptContactRequest encrypts a signed payload for a recipient using their
// Ed25519 public key via ephemeral X25519 ECDH + HKDF-SHA256 + AES-256-GCM.
//
//  1. Generate ephemeral X25519 keypair
//  2. Convert recipient's Ed25519 public key → X25519
//  3. X25519 ECDH → shared secret
//  4. HKDF-SHA256 → AES key
//  5. AES-256-GCM encrypt with AAD = "msgId|ts"
func EncryptContactRequest(recipientEdPubKeyB64, plaintext, msgId, ts string) (*EncryptedContactRequest, error) {
	// 1. Decode recipient Ed25519 public key
	recipientEdPub, err := base64.StdEncoding.DecodeString(recipientEdPubKeyB64)
	if err != nil {
		return nil, fmt.Errorf("decode recipient public key: %w", err)
	}
	if len(recipientEdPub) != 32 {
		return nil, fmt.Errorf("recipient public key must be 32 bytes, got %d", len(recipientEdPub))
	}

	// 2. Convert recipient Ed25519 pub → X25519
	recipientX25519Pub, err := EdPublicKeyToX25519(recipientEdPub)
	if err != nil {
		return nil, fmt.Errorf("convert recipient key: %w", err)
	}

	// 3. Generate ephemeral X25519 keypair (fresh random)
	ephPriv := make([]byte, 32)
	if _, err := rand.Read(ephPriv); err != nil {
		return nil, fmt.Errorf("generate ephemeral key: %w", err)
	}
	ephPub, err := curve25519.X25519(ephPriv, curve25519.Basepoint)
	if err != nil {
		return nil, fmt.Errorf("compute ephemeral public key: %w", err)
	}

	// 4. ECDH → shared secret
	sharedSecret, err := x25519ECDH(ephPriv, recipientX25519Pub)
	if err != nil {
		return nil, fmt.Errorf("ecdh: %w", err)
	}

	// 5. HKDF → AES key
	aesKey, err := deriveAESKey(sharedSecret, ephPub)
	if err != nil {
		return nil, fmt.Errorf("derive key: %w", err)
	}

	// 6. AES-256-GCM encrypt
	block, err := aes.NewCipher(aesKey)
	if err != nil {
		return nil, fmt.Errorf("aes new cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("aes new gcm: %w", err)
	}

	nonce := make([]byte, 12)
	if _, err := rand.Read(nonce); err != nil {
		return nil, fmt.Errorf("generate nonce: %w", err)
	}

	aad := buildAAD(msgId, ts)
	ciphertext := gcm.Seal(nil, nonce, []byte(plaintext), aad)

	return &EncryptedContactRequest{
		EphemeralPublicKey: base64.StdEncoding.EncodeToString(ephPub),
		Ciphertext:         base64.StdEncoding.EncodeToString(ciphertext),
		Nonce:              base64.StdEncoding.EncodeToString(nonce),
	}, nil
}

// DecryptContactRequest decrypts a v2 contact request using the recipient's
// own Ed25519 private key.
//
//  1. Convert own Ed25519 private key → X25519 scalar
//  2. X25519 ECDH with ephemeral public key → shared secret
//  3. HKDF-SHA256 → AES key
//  4. AES-256-GCM decrypt with AAD = "msgId|ts"
func DecryptContactRequest(ownEdPrivKeyB64, ephPubB64, ciphertextB64, nonceB64, msgId, ts string) (string, error) {
	// 1. Decode inputs
	ownEdPriv, err := base64.StdEncoding.DecodeString(ownEdPrivKeyB64)
	if err != nil {
		return "", fmt.Errorf("decode private key: %w", err)
	}

	ephPub, err := base64.StdEncoding.DecodeString(ephPubB64)
	if err != nil {
		return "", fmt.Errorf("decode ephemeral public key: %w", err)
	}

	ciphertext, err := base64.StdEncoding.DecodeString(ciphertextB64)
	if err != nil {
		return "", fmt.Errorf("decode ciphertext: %w", err)
	}

	nonce, err := base64.StdEncoding.DecodeString(nonceB64)
	if err != nil {
		return "", fmt.Errorf("decode nonce: %w", err)
	}

	// 2. Convert Ed25519 priv → X25519 scalar
	x25519Priv, err := EdPrivateKeyToX25519(ownEdPriv)
	if err != nil {
		return "", fmt.Errorf("convert private key: %w", err)
	}

	// 3. ECDH with ephemeral pub → shared secret
	sharedSecret, err := x25519ECDH(x25519Priv, ephPub)
	if err != nil {
		return "", fmt.Errorf("ecdh: %w", err)
	}

	// 4. HKDF → AES key
	aesKey, err := deriveAESKey(sharedSecret, ephPub)
	if err != nil {
		return "", fmt.Errorf("derive key: %w", err)
	}

	// 5. AES-256-GCM decrypt
	block, err := aes.NewCipher(aesKey)
	if err != nil {
		return "", fmt.Errorf("aes new cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("aes new gcm: %w", err)
	}

	aad := buildAAD(msgId, ts)
	plaintext, err := gcm.Open(nil, nonce, ciphertext, aad)
	if err != nil {
		return "", fmt.Errorf("aes-gcm decrypt: %w", err)
	}

	return string(plaintext), nil
}
