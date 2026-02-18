package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/base64"
	"fmt"

	"github.com/cloudflare/circl/kem/mlkem/mlkem768"
)

// DecryptMessage decrypts a v2 envelope message using the recipient's own
// ML-KEM-768 secret key. It performs KEM decapsulation to recover the shared
// secret and then AES-256-GCM decrypts the ciphertext.
//
// Uses cloudflare/circl for ML-KEM-768 to stay wire-compatible with the JS
// implementation (@noble/post-quantum), which uses 2400-byte secret keys.
//
// This is wire-compatible with the JS implementation:
//  1. Decode all inputs from base64.
//  2. ML-KEM-768 decapsulate with secret key -> shared secret.
//  3. AES-256-GCM decrypt with shared secret + nonce.
//  4. Return plaintext string.
func DecryptMessage(ownMlKemSecretKeyBase64, kemCiphertextBase64, aesCiphertextBase64, nonceBase64 string) (string, error) {
	// 1. Decode all inputs from base64.
	skBytes, err := base64.StdEncoding.DecodeString(ownMlKemSecretKeyBase64)
	if err != nil {
		return "", fmt.Errorf("decode secret key: %w", err)
	}

	kemCiphertext, err := base64.StdEncoding.DecodeString(kemCiphertextBase64)
	if err != nil {
		return "", fmt.Errorf("decode kem ciphertext: %w", err)
	}

	aesCiphertext, err := base64.StdEncoding.DecodeString(aesCiphertextBase64)
	if err != nil {
		return "", fmt.Errorf("decode aes ciphertext: %w", err)
	}

	nonce, err := base64.StdEncoding.DecodeString(nonceBase64)
	if err != nil {
		return "", fmt.Errorf("decode nonce: %w", err)
	}

	// 2. KEM decapsulate -> sharedSecret.
	scheme := mlkem768.Scheme()

	sk, err := scheme.UnmarshalBinaryPrivateKey(skBytes)
	if err != nil {
		return "", fmt.Errorf("unmarshal secret key: %w", err)
	}

	sharedSecret, err := scheme.Decapsulate(sk, kemCiphertext)
	if err != nil {
		return "", fmt.Errorf("mlkem768 decapsulate: %w", err)
	}

	// 3. AES-256-GCM decrypt.
	block, err := aes.NewCipher(sharedSecret)
	if err != nil {
		return "", fmt.Errorf("aes new cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("aes new gcm: %w", err)
	}

	plaintext, err := gcm.Open(nil, nonce, aesCiphertext, nil)
	if err != nil {
		return "", fmt.Errorf("aes-gcm decrypt: %w", err)
	}

	// 4. Return plaintext string.
	return string(plaintext), nil
}
