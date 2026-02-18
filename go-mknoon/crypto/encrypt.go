package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"fmt"

	"github.com/cloudflare/circl/kem/mlkem/mlkem768"
)

// EncryptedMessage holds the v2 envelope encrypted fields, all base64-encoded.
type EncryptedMessage struct {
	Kem        string // base64-encoded KEM ciphertext (1088 bytes raw)
	Ciphertext string // base64-encoded AES-GCM ciphertext (plaintext + 16-byte auth tag)
	Nonce      string // base64-encoded 12-byte nonce
}

// EncryptMessage encrypts plaintext for a recipient using ML-KEM-768 key
// encapsulation followed by AES-256-GCM symmetric encryption.
//
// Uses cloudflare/circl for ML-KEM-768 to stay wire-compatible with the JS
// implementation (@noble/post-quantum), which uses 1184-byte public keys and
// 2400-byte secret keys.
//
// This is wire-compatible with the JS implementation:
//  1. Decode recipient's ML-KEM public key from base64.
//  2. ML-KEM-768 encapsulate to produce a shared secret and KEM ciphertext.
//  3. Generate a random 12-byte nonce.
//  4. AES-256-GCM encrypt the plaintext with the shared secret + nonce.
//     Go's gcm.Seal appends the 16-byte auth tag to the ciphertext,
//     matching @noble/ciphers AES-GCM behavior.
func EncryptMessage(recipientMlKemPublicKeyBase64 string, plaintext string) (*EncryptedMessage, error) {
	// 1. Decode recipient public key.
	pkBytes, err := base64.StdEncoding.DecodeString(recipientMlKemPublicKeyBase64)
	if err != nil {
		return nil, fmt.Errorf("decode recipient public key: %w", err)
	}

	scheme := mlkem768.Scheme()

	pk, err := scheme.UnmarshalBinaryPublicKey(pkBytes)
	if err != nil {
		return nil, fmt.Errorf("unmarshal recipient public key: %w", err)
	}

	// 2. KEM encapsulate -> (kemCiphertext, sharedSecret).
	kemCiphertext, sharedSecret, err := scheme.Encapsulate(pk)
	if err != nil {
		return nil, fmt.Errorf("mlkem768 encapsulate: %w", err)
	}

	// 3. Random 12-byte nonce.
	nonce := make([]byte, 12)
	if _, err := rand.Read(nonce); err != nil {
		return nil, fmt.Errorf("generate nonce: %w", err)
	}

	// 4. AES-256-GCM encrypt.
	block, err := aes.NewCipher(sharedSecret)
	if err != nil {
		return nil, fmt.Errorf("aes new cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("aes new gcm: %w", err)
	}

	// Seal appends ciphertext + 16-byte auth tag to dst (nil).
	aesCiphertext := gcm.Seal(nil, nonce, []byte(plaintext), nil)

	return &EncryptedMessage{
		Kem:        base64.StdEncoding.EncodeToString(kemCiphertext),
		Ciphertext: base64.StdEncoding.EncodeToString(aesCiphertext),
		Nonce:      base64.StdEncoding.EncodeToString(nonce),
	}, nil
}
