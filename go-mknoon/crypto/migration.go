package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"

	"github.com/cloudflare/circl/kem/mlkem/mlkem768"
	"golang.org/x/crypto/hkdf"
)

// Account-move transfer session crypto (protocol v2).
//
// One ML-KEM-768 encapsulation per transfer attempt produces a shared secret;
// the AES-256-GCM session key is derived from it with HKDF-SHA256 whose info
// binds sessionId, bundleId, and direction. Every chunk is then sealed with a
// caller-supplied 96-bit counter nonce and the canonical chunk associated
// data as real GCM AAD, so reordered, replayed, truncated, or re-attributed
// chunks fail authentication instead of decrypting silently.

// MigrationSession holds the derived session key and the KEM ciphertext the
// receiver needs to derive the same key.
type MigrationSession struct {
	SessionKey    string // base64-encoded 32-byte AES-256 key
	KemCiphertext string // base64-encoded ML-KEM-768 ciphertext (1088 bytes raw)
}

const migrationSessionKeyBytes = 32

func migrationSessionInfo(sessionId, bundleId, direction string) []byte {
	return []byte("mknoon/migration/v2|" + sessionId + "|" + bundleId + "|" + direction)
}

func migrationDeriveSessionKey(sharedSecret []byte, sessionId, bundleId, direction string) ([]byte, error) {
	reader := hkdf.New(sha256.New, sharedSecret, nil, migrationSessionInfo(sessionId, bundleId, direction))
	key := make([]byte, migrationSessionKeyBytes)
	if _, err := io.ReadFull(reader, key); err != nil {
		return nil, fmt.Errorf("hkdf derive session key: %w", err)
	}
	return key, nil
}

// MigrationSessionEncap encapsulates to the receiver's ML-KEM-768 public key
// and derives the transfer session key.
func MigrationSessionEncap(recipientPublicKeyBase64, sessionId, bundleId, direction string) (*MigrationSession, error) {
	pkBytes, err := base64.StdEncoding.DecodeString(recipientPublicKeyBase64)
	if err != nil {
		return nil, fmt.Errorf("decode recipient public key: %w", err)
	}

	scheme := mlkem768.Scheme()
	pk, err := scheme.UnmarshalBinaryPublicKey(pkBytes)
	if err != nil {
		return nil, fmt.Errorf("unmarshal recipient public key: %w", err)
	}

	kemCiphertext, sharedSecret, err := scheme.Encapsulate(pk)
	if err != nil {
		return nil, fmt.Errorf("mlkem768 encapsulate: %w", err)
	}

	key, err := migrationDeriveSessionKey(sharedSecret, sessionId, bundleId, direction)
	if err != nil {
		return nil, err
	}

	return &MigrationSession{
		SessionKey:    base64.StdEncoding.EncodeToString(key),
		KemCiphertext: base64.StdEncoding.EncodeToString(kemCiphertext),
	}, nil
}

// MigrationSessionDecap decapsulates the KEM ciphertext with the receiver's
// secret key and derives the same transfer session key as the sender.
func MigrationSessionDecap(secretKeyBase64, kemCiphertextBase64, sessionId, bundleId, direction string) (string, error) {
	skBytes, err := base64.StdEncoding.DecodeString(secretKeyBase64)
	if err != nil {
		return "", fmt.Errorf("decode secret key: %w", err)
	}

	kemCiphertext, err := base64.StdEncoding.DecodeString(kemCiphertextBase64)
	if err != nil {
		return "", fmt.Errorf("decode kem ciphertext: %w", err)
	}

	scheme := mlkem768.Scheme()
	sk, err := scheme.UnmarshalBinaryPrivateKey(skBytes)
	if err != nil {
		return "", fmt.Errorf("unmarshal secret key: %w", err)
	}

	sharedSecret, err := scheme.Decapsulate(sk, kemCiphertext)
	if err != nil {
		return "", fmt.Errorf("mlkem768 decapsulate: %w", err)
	}

	key, err := migrationDeriveSessionKey(sharedSecret, sessionId, bundleId, direction)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(key), nil
}

func migrationChunkGCM(sessionKeyBase64 string) (cipher.AEAD, error) {
	key, err := base64.StdEncoding.DecodeString(sessionKeyBase64)
	if err != nil {
		return nil, fmt.Errorf("decode session key: %w", err)
	}
	if len(key) != migrationSessionKeyBytes {
		return nil, fmt.Errorf("session key must be %d bytes, got %d", migrationSessionKeyBytes, len(key))
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("aes new cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("aes new gcm: %w", err)
	}
	return gcm, nil
}

// MigrationChunkEncrypt seals one chunk with the session key, the
// caller-supplied counter nonce, and the canonical associated-data JSON as
// real GCM AAD.
func MigrationChunkEncrypt(sessionKeyBase64, plaintextBase64, aad, nonceBase64 string) (ciphertextBase64 string, err error) {
	gcm, err := migrationChunkGCM(sessionKeyBase64)
	if err != nil {
		return "", err
	}

	plaintext, err := base64.StdEncoding.DecodeString(plaintextBase64)
	if err != nil {
		return "", fmt.Errorf("decode plaintext: %w", err)
	}

	nonce, err := base64.StdEncoding.DecodeString(nonceBase64)
	if err != nil {
		return "", fmt.Errorf("decode nonce: %w", err)
	}
	if len(nonce) != gcm.NonceSize() {
		return "", fmt.Errorf("nonce must be %d bytes, got %d", gcm.NonceSize(), len(nonce))
	}

	ciphertext := gcm.Seal(nil, nonce, plaintext, []byte(aad))
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

// MigrationChunkDecrypt opens one chunk; any tampering of the ciphertext,
// nonce, or associated data fails authentication.
func MigrationChunkDecrypt(sessionKeyBase64, ciphertextBase64, aad, nonceBase64 string) (plaintextBase64 string, err error) {
	gcm, err := migrationChunkGCM(sessionKeyBase64)
	if err != nil {
		return "", err
	}

	ciphertext, err := base64.StdEncoding.DecodeString(ciphertextBase64)
	if err != nil {
		return "", fmt.Errorf("decode ciphertext: %w", err)
	}

	nonce, err := base64.StdEncoding.DecodeString(nonceBase64)
	if err != nil {
		return "", fmt.Errorf("decode nonce: %w", err)
	}
	if len(nonce) != gcm.NonceSize() {
		return "", fmt.Errorf("nonce must be %d bytes, got %d", gcm.NonceSize(), len(nonce))
	}

	plaintext, err := gcm.Open(nil, nonce, ciphertext, []byte(aad))
	if err != nil {
		return "", fmt.Errorf("aes-gcm chunk decrypt: %w", err)
	}
	return base64.StdEncoding.EncodeToString(plaintext), nil
}
