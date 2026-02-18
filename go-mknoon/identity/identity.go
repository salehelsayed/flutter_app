// Package identity provides generation and restoration of mknoon identities.
//
// An identity consists of a BIP39 mnemonic, an Ed25519 keypair derived from
// that mnemonic, and a libp2p peer ID derived from the public key. The same
// mnemonic always produces the same keypair and peer ID (deterministic).
//
// Derivation path (matches the JS implementation exactly):
//
//	bip39.NewSeed(mnemonic, "") -> 64-byte seed
//	ed25519.NewKeyFromSeed(seed[:32]) -> keypair
//	peer.IDFromPublicKey(libp2pPubKey) -> Peer ID
package identity

import (
	"crypto/ed25519"
	"encoding/base64"
	"fmt"
	"strings"
	"time"

	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/tyler-smith/go-bip39"
)

// Identity holds the complete cryptographic identity for a mknoon user.
type Identity struct {
	PeerId     string // libp2p peer ID, e.g. "12D3KooW..."
	PublicKey  string // base64-encoded 32-byte Ed25519 public key
	PrivateKey string // base64-encoded 64-byte Ed25519 private key
	Mnemonic12 string // 12 BIP39 words separated by spaces
	CreatedAt  string // ISO-8601 UTC timestamp
	UpdatedAt  string // ISO-8601 UTC timestamp
}

// GenerateIdentity creates a new identity with a fresh 12-word BIP39 mnemonic
// and deterministically derived Ed25519 keypair and libp2p peer ID.
//
//  1. Generate 128-bit entropy -> 12-word BIP39 mnemonic
//  2. Derive 64-byte seed from mnemonic (no password)
//  3. Ed25519 keypair from seed[:32]
//  4. Derive libp2p Peer ID
//  5. Base64 encode keys
//  6. Set timestamps
func GenerateIdentity() (*Identity, error) {
	// 1. Generate 12-word BIP39 mnemonic (128 bits entropy = 12 words).
	entropy, err := bip39.NewEntropy(128)
	if err != nil {
		return nil, fmt.Errorf("generate entropy: %w", err)
	}
	mnemonic, err := bip39.NewMnemonic(entropy)
	if err != nil {
		return nil, fmt.Errorf("generate mnemonic: %w", err)
	}

	return identityFromMnemonic(mnemonic)
}

// RestoreIdentity deterministically recreates an identity from a 12-word BIP39
// mnemonic. The same mnemonic always produces the same peer ID and keys.
//
// The mnemonic is normalized (trimmed, lowercased) before validation.
// Returns an error if the word count is not 12 or the BIP39 checksum is invalid.
//
//  1. Normalize (trim, lowercase)
//  2. Validate word count == 12
//  3. Validate BIP39 checksum
//  4. Same derivation as GenerateIdentity
func RestoreIdentity(mnemonic12 string) (*Identity, error) {
	// Normalize: trim whitespace, lowercase.
	normalized := strings.ToLower(strings.TrimSpace(mnemonic12))

	// Validate word count == 12.
	words := strings.Fields(normalized)
	if len(words) != 12 {
		return nil, fmt.Errorf("invalid mnemonic: expected 12 words, got %d", len(words))
	}

	// Re-join with single spaces (handles irregular spacing in input).
	normalized = strings.Join(words, " ")

	// Validate BIP39 checksum.
	if !bip39.IsMnemonicValid(normalized) {
		return nil, fmt.Errorf("invalid mnemonic: BIP39 checksum validation failed")
	}

	return identityFromMnemonic(normalized)
}

// ToJSON returns a map matching the JS bridge response format:
//
//	{ "ok": true, "identity": { "peerId": "...", ... } }
func (id *Identity) ToJSON() map[string]interface{} {
	return map[string]interface{}{
		"ok": true,
		"identity": map[string]interface{}{
			"peerId":     id.PeerId,
			"publicKey":  id.PublicKey,
			"privateKey": id.PrivateKey,
			"mnemonic12": id.Mnemonic12,
			"createdAt":  id.CreatedAt,
			"updatedAt":  id.UpdatedAt,
		},
	}
}

// identityFromMnemonic is the shared implementation for GenerateIdentity and
// RestoreIdentity. It derives the seed, keypair, peer ID, and timestamps from
// a validated mnemonic.
func identityFromMnemonic(mnemonic string) (*Identity, error) {
	// 2. Derive seed from mnemonic (64 bytes, empty passphrase to match JS).
	seed := bip39.NewSeed(mnemonic, "")

	// 3. Use first 32 bytes of seed as Ed25519 seed.
	// This matches the JS: bip39.mnemonicToSeed(mnemonic) -> seed[:32] ->
	// ed25519.NewKeyFromSeed(seed[:32])
	edPrivKey := ed25519.NewKeyFromSeed(seed[:32])
	edPubKey := edPrivKey.Public().(ed25519.PublicKey)

	// 4. Wrap in libp2p crypto types for peer ID derivation.
	// UnmarshalEd25519PrivateKey expects 64 bytes (32-byte seed + 32-byte public).
	libp2pPrivKey, err := crypto.UnmarshalEd25519PrivateKey(edPrivKey)
	if err != nil {
		return nil, fmt.Errorf("unmarshal ed25519 private key: %w", err)
	}

	// 5. Derive libp2p peer ID from public key.
	peerID, err := peer.IDFromPublicKey(libp2pPrivKey.GetPublic())
	if err != nil {
		return nil, fmt.Errorf("derive peer ID: %w", err)
	}

	// 6. Base64-encode keys (standard encoding, matching JS Buffer.toString('base64')).
	publicKeyB64 := base64.StdEncoding.EncodeToString([]byte(edPubKey))
	privateKeyB64 := base64.StdEncoding.EncodeToString([]byte(edPrivKey))

	// 7. Timestamps in ISO-8601 UTC.
	now := time.Now().UTC().Format(time.RFC3339Nano)

	return &Identity{
		PeerId:     peerID.String(),
		PublicKey:  publicKeyB64,
		PrivateKey: privateKeyB64,
		Mnemonic12: mnemonic,
		CreatedAt:  now,
		UpdatedAt:  now,
	}, nil
}
