// Package crypto provides ML-KEM-768 + AES-256-GCM encryption and Ed25519
// signing, wire-compatible with the JS implementation in core_lib_js.
package crypto

import (
	"encoding/base64"
	"fmt"

	"github.com/cloudflare/circl/kem/mlkem/mlkem768"
)

// MlKemKeyPair holds base64-encoded ML-KEM-768 keys.
type MlKemKeyPair struct {
	PublicKey string // base64, 1184 bytes decoded
	SecretKey string // base64, 2400 bytes decoded
}

// MlKemKeygen generates a new ML-KEM-768 key pair and returns
// the keys as standard base64-encoded strings.
//
// Uses cloudflare/circl (not Go stdlib crypto/mlkem) because the JS
// implementation (@noble/post-quantum) serializes the secret key as 2400
// bytes, matching circl's MarshalBinary format. The Go stdlib crypto/mlkem
// uses a 64-byte seed format that is NOT wire-compatible.
func MlKemKeygen() (*MlKemKeyPair, error) {
	scheme := mlkem768.Scheme()

	pk, sk, err := scheme.GenerateKeyPair()
	if err != nil {
		return nil, fmt.Errorf("mlkem768 keygen: %w", err)
	}

	pkBytes, err := pk.MarshalBinary()
	if err != nil {
		return nil, fmt.Errorf("marshal public key: %w", err)
	}

	skBytes, err := sk.MarshalBinary()
	if err != nil {
		return nil, fmt.Errorf("marshal secret key: %w", err)
	}

	return &MlKemKeyPair{
		PublicKey: base64.StdEncoding.EncodeToString(pkBytes),
		SecretKey: base64.StdEncoding.EncodeToString(skBytes),
	}, nil
}
