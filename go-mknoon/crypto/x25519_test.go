package crypto

import (
	"crypto/ed25519"
	"encoding/base64"
	"testing"

	"github.com/tyler-smith/go-bip39"
)

// --- Helpers ---

// testEd25519Keys generates an Ed25519 keypair from the "abandon...about" mnemonic.
func testEd25519Keys() (ed25519.PublicKey, ed25519.PrivateKey) {
	mnemonic := "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
	seed := bip39.NewSeed(mnemonic, "")
	priv := ed25519.NewKeyFromSeed(seed[:32])
	pub := priv.Public().(ed25519.PublicKey)
	return pub, priv
}

// testEd25519Keys2 generates a second keypair from a different mnemonic.
func testEd25519Keys2() (ed25519.PublicKey, ed25519.PrivateKey) {
	mnemonic := "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"
	seed := bip39.NewSeed(mnemonic, "")
	priv := ed25519.NewKeyFromSeed(seed[:32])
	pub := priv.Public().(ed25519.PublicKey)
	return pub, priv
}

// --- EdPublicKeyToX25519 ---

func TestEdPublicKeyToX25519_KnownVector(t *testing.T) {
	pub, _ := testEd25519Keys()
	x25519Pub, err := EdPublicKeyToX25519(pub)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(x25519Pub) != 32 {
		t.Fatalf("expected 32 bytes, got %d", len(x25519Pub))
	}
	// Should be deterministic
	x25519Pub2, _ := EdPublicKeyToX25519(pub)
	if !bytesEqual(x25519Pub, x25519Pub2) {
		t.Fatal("not deterministic")
	}
}

func TestEdPublicKeyToX25519_WrongLength(t *testing.T) {
	for _, size := range []int{0, 31, 33} {
		_, err := EdPublicKeyToX25519(make([]byte, size))
		if err == nil {
			t.Fatalf("expected error for %d bytes", size)
		}
	}
}

func TestEdPublicKeyToX25519_DifferentKeys(t *testing.T) {
	pub1, _ := testEd25519Keys()
	pub2, _ := testEd25519Keys2()
	x1, _ := EdPublicKeyToX25519(pub1)
	x2, _ := EdPublicKeyToX25519(pub2)
	if bytesEqual(x1, x2) {
		t.Fatal("different Ed keys should produce different X25519 keys")
	}
}

// --- EdPrivateKeyToX25519 ---

func TestEdPrivateKeyToX25519_ValidLength(t *testing.T) {
	_, priv := testEd25519Keys()
	x25519Priv, err := EdPrivateKeyToX25519(priv)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(x25519Priv) != 32 {
		t.Fatalf("expected 32 bytes, got %d", len(x25519Priv))
	}
}

func TestEdPrivateKeyToX25519_WrongLength(t *testing.T) {
	for _, size := range []int{0, 32, 63, 65} {
		_, err := EdPrivateKeyToX25519(make([]byte, size))
		if err == nil {
			t.Fatalf("expected error for %d bytes", size)
		}
	}
}

func TestEdPrivateKeyToX25519_ClampingApplied(t *testing.T) {
	_, priv := testEd25519Keys()
	x, _ := EdPrivateKeyToX25519(priv)
	// RFC 7748 clamping: clear 3 LSB of byte 0, clear bit 7 of byte 31, set bit 6 of byte 31
	if x[0]&7 != 0 {
		t.Fatalf("clamping: byte[0]&7 should be 0, got %d", x[0]&7)
	}
	if x[31]&0x80 != 0 {
		t.Fatalf("clamping: byte[31]&0x80 should be 0, got %d", x[31]&0x80)
	}
	if x[31]&0x40 != 0x40 {
		t.Fatalf("clamping: byte[31]&0x40 should be 0x40, got %d", x[31]&0x40)
	}
}

func TestEdPrivateKeyToX25519_Deterministic(t *testing.T) {
	_, priv := testEd25519Keys()
	x1, _ := EdPrivateKeyToX25519(priv)
	x2, _ := EdPrivateKeyToX25519(priv)
	if !bytesEqual(x1, x2) {
		t.Fatal("not deterministic")
	}
}

// --- ECDH ---

func TestECDH_SharedSecretConsistency(t *testing.T) {
	pub1, priv1 := testEd25519Keys()
	pub2, priv2 := testEd25519Keys2()

	x25519Pub1, _ := EdPublicKeyToX25519(pub1)
	x25519Priv1, _ := EdPrivateKeyToX25519(priv1)
	x25519Pub2, _ := EdPublicKeyToX25519(pub2)
	x25519Priv2, _ := EdPrivateKeyToX25519(priv2)

	// DH commutativity: sender→recipient == recipient→sender
	ss1, err := x25519ECDH(x25519Priv1, x25519Pub2)
	if err != nil {
		t.Fatalf("ECDH 1→2 error: %v", err)
	}
	ss2, err := x25519ECDH(x25519Priv2, x25519Pub1)
	if err != nil {
		t.Fatalf("ECDH 2→1 error: %v", err)
	}
	if !bytesEqual(ss1, ss2) {
		t.Fatal("shared secrets should be equal (DH commutativity)")
	}
}

func TestECDH_RejectAllZeroSharedSecret(t *testing.T) {
	// Small-subgroup point: all zeros public key (order 1)
	zeroPoint := make([]byte, 32)
	_, priv := testEd25519Keys()
	x25519Priv, _ := EdPrivateKeyToX25519(priv)

	_, err := x25519ECDH(x25519Priv, zeroPoint)
	if err == nil {
		t.Fatal("should reject all-zero shared secret")
	}
}

// --- HKDF ---

func TestHKDF_Deterministic(t *testing.T) {
	secret := make([]byte, 32)
	secret[0] = 1
	salt := make([]byte, 32)
	salt[0] = 2

	key1, _ := deriveAESKey(secret, salt)
	key2, _ := deriveAESKey(secret, salt)
	if !bytesEqual(key1, key2) {
		t.Fatal("HKDF not deterministic")
	}
}

func TestHKDF_DifferentEphemerals_DifferentKeys(t *testing.T) {
	secret := make([]byte, 32)
	secret[0] = 1
	salt1 := make([]byte, 32)
	salt1[0] = 2
	salt2 := make([]byte, 32)
	salt2[0] = 3

	key1, _ := deriveAESKey(secret, salt1)
	key2, _ := deriveAESKey(secret, salt2)
	if bytesEqual(key1, key2) {
		t.Fatal("different salts should produce different keys")
	}
}

func TestHKDF_OutputIs32Bytes(t *testing.T) {
	secret := make([]byte, 32)
	salt := make([]byte, 32)
	key, err := deriveAESKey(secret, salt)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(key) != 32 {
		t.Fatalf("expected 32 bytes, got %d", len(key))
	}
}

// --- EncryptContactRequest / DecryptContactRequest ---

func TestEncryptDecrypt_RoundTrip(t *testing.T) {
	pub, priv := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)
	ownPrivB64 := base64.StdEncoding.EncodeToString(priv)

	plaintext := `{"ns":"12D3KooW...","pk":"abc","sig":"xyz"}`
	msgId := "550e8400-e29b-41d4-a716-446655440000"
	ts := "2024-01-01T00:00:00Z"

	enc, err := EncryptContactRequest(recipientPubB64, plaintext, msgId, ts)
	if err != nil {
		t.Fatalf("encrypt error: %v", err)
	}

	decrypted, err := DecryptContactRequest(ownPrivB64, enc.EphemeralPublicKey, enc.Ciphertext, enc.Nonce, msgId, ts)
	if err != nil {
		t.Fatalf("decrypt error: %v", err)
	}

	if decrypted != plaintext {
		t.Fatalf("expected %q, got %q", plaintext, decrypted)
	}
}

func TestEncrypt_EphemeralKeyIs32Bytes(t *testing.T) {
	pub, _ := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)

	enc, err := EncryptContactRequest(recipientPubB64, "hello", "msg1", "2024-01-01T00:00:00Z")
	if err != nil {
		t.Fatalf("encrypt error: %v", err)
	}

	ephBytes, err := base64.StdEncoding.DecodeString(enc.EphemeralPublicKey)
	if err != nil {
		t.Fatalf("decode ephemeral key: %v", err)
	}
	if len(ephBytes) != 32 {
		t.Fatalf("expected 32 bytes, got %d", len(ephBytes))
	}
}

func TestEncrypt_NonceIs12Bytes(t *testing.T) {
	pub, _ := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)

	enc, err := EncryptContactRequest(recipientPubB64, "hello", "msg1", "2024-01-01T00:00:00Z")
	if err != nil {
		t.Fatalf("encrypt error: %v", err)
	}

	nonceBytes, err := base64.StdEncoding.DecodeString(enc.Nonce)
	if err != nil {
		t.Fatalf("decode nonce: %v", err)
	}
	if len(nonceBytes) != 12 {
		t.Fatalf("expected 12 bytes, got %d", len(nonceBytes))
	}
}

func TestEncrypt_DifferentEncryptionsDiffer(t *testing.T) {
	pub, _ := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)

	enc1, _ := EncryptContactRequest(recipientPubB64, "hello", "msg1", "2024-01-01T00:00:00Z")
	enc2, _ := EncryptContactRequest(recipientPubB64, "hello", "msg1", "2024-01-01T00:00:00Z")

	if enc1.EphemeralPublicKey == enc2.EphemeralPublicKey {
		t.Fatal("ephemeral keys should differ (fresh random each time)")
	}
	if enc1.Ciphertext == enc2.Ciphertext {
		t.Fatal("ciphertexts should differ")
	}
}

func TestDecrypt_WrongPrivateKey(t *testing.T) {
	pub, _ := testEd25519Keys()
	_, priv2 := testEd25519Keys2()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)
	wrongPrivB64 := base64.StdEncoding.EncodeToString(priv2)

	enc, _ := EncryptContactRequest(recipientPubB64, "secret", "msg1", "2024-01-01T00:00:00Z")

	_, err := DecryptContactRequest(wrongPrivB64, enc.EphemeralPublicKey, enc.Ciphertext, enc.Nonce, "msg1", "2024-01-01T00:00:00Z")
	if err == nil {
		t.Fatal("should fail with wrong private key")
	}
}

func TestDecrypt_TamperedCiphertext(t *testing.T) {
	pub, priv := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)
	ownPrivB64 := base64.StdEncoding.EncodeToString(priv)

	enc, _ := EncryptContactRequest(recipientPubB64, "secret", "msg1", "2024-01-01T00:00:00Z")

	// Tamper with ciphertext
	ctBytes, _ := base64.StdEncoding.DecodeString(enc.Ciphertext)
	ctBytes[0] ^= 0xFF
	tampered := base64.StdEncoding.EncodeToString(ctBytes)

	_, err := DecryptContactRequest(ownPrivB64, enc.EphemeralPublicKey, tampered, enc.Nonce, "msg1", "2024-01-01T00:00:00Z")
	if err == nil {
		t.Fatal("should fail with tampered ciphertext")
	}
}

func TestDecrypt_TamperedEphemeralKey(t *testing.T) {
	pub, priv := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)
	ownPrivB64 := base64.StdEncoding.EncodeToString(priv)

	enc, _ := EncryptContactRequest(recipientPubB64, "secret", "msg1", "2024-01-01T00:00:00Z")

	// Tamper with ephemeral key
	ephBytes, _ := base64.StdEncoding.DecodeString(enc.EphemeralPublicKey)
	ephBytes[0] ^= 0xFF
	tampered := base64.StdEncoding.EncodeToString(ephBytes)

	_, err := DecryptContactRequest(ownPrivB64, tampered, enc.Ciphertext, enc.Nonce, "msg1", "2024-01-01T00:00:00Z")
	if err == nil {
		t.Fatal("should fail with tampered ephemeral key")
	}
}

func TestEncrypt_InvalidRecipientKey(t *testing.T) {
	// Bad base64
	_, err := EncryptContactRequest("not-base64!!!", "hello", "msg1", "2024-01-01T00:00:00Z")
	if err == nil {
		t.Fatal("should fail with bad base64")
	}

	// Wrong length
	short := base64.StdEncoding.EncodeToString(make([]byte, 16))
	_, err = EncryptContactRequest(short, "hello", "msg1", "2024-01-01T00:00:00Z")
	if err == nil {
		t.Fatal("should fail with wrong length")
	}
}

func TestEncryptDecrypt_RealPayload(t *testing.T) {
	pub, priv := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)
	ownPrivB64 := base64.StdEncoding.EncodeToString(priv)

	// Full signed contact request JSON
	plaintext := `{"mlkem":"longMlKemKeyBase64...","ns":"12D3KooWTestPeerId","pk":"edPubKeyBase64","rv":"/dns4/relay.example.com/tcp/4001/wss/p2p/relay","sig":"signatureBase64","ts":"2024-06-15T12:00:00Z","un":"Alice"}`
	msgId := "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
	ts := "2024-06-15T12:00:00Z"

	enc, err := EncryptContactRequest(recipientPubB64, plaintext, msgId, ts)
	if err != nil {
		t.Fatalf("encrypt error: %v", err)
	}

	decrypted, err := DecryptContactRequest(ownPrivB64, enc.EphemeralPublicKey, enc.Ciphertext, enc.Nonce, msgId, ts)
	if err != nil {
		t.Fatalf("decrypt error: %v", err)
	}

	if decrypted != plaintext {
		t.Fatalf("expected %q, got %q", plaintext, decrypted)
	}
}

func TestEncryptDecrypt_Unicode(t *testing.T) {
	pub, priv := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)
	ownPrivB64 := base64.StdEncoding.EncodeToString(priv)

	plaintext := `{"un":"مرحبا","ns":"テスト","emoji":"🔐🌍"}`
	msgId := "unicode-test-id"
	ts := "2024-01-01T00:00:00Z"

	enc, err := EncryptContactRequest(recipientPubB64, plaintext, msgId, ts)
	if err != nil {
		t.Fatalf("encrypt error: %v", err)
	}

	decrypted, err := DecryptContactRequest(ownPrivB64, enc.EphemeralPublicKey, enc.Ciphertext, enc.Nonce, msgId, ts)
	if err != nil {
		t.Fatalf("decrypt error: %v", err)
	}

	if decrypted != plaintext {
		t.Fatalf("expected %q, got %q", plaintext, decrypted)
	}
}

func TestEncryptDecrypt_AAD_Binding(t *testing.T) {
	pub, priv := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)
	ownPrivB64 := base64.StdEncoding.EncodeToString(priv)

	msgId := "test-msg-id"
	ts := "2024-01-01T00:00:00Z"

	enc, _ := EncryptContactRequest(recipientPubB64, "hello", msgId, ts)

	// Same ciphertext + wrong msgId → auth tag failure
	_, err := DecryptContactRequest(ownPrivB64, enc.EphemeralPublicKey, enc.Ciphertext, enc.Nonce, "wrong-msg-id", ts)
	if err == nil {
		t.Fatal("should fail with wrong msgId (AAD mismatch)")
	}
}

func TestEncryptDecrypt_AAD_TamperedTs(t *testing.T) {
	pub, priv := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)
	ownPrivB64 := base64.StdEncoding.EncodeToString(priv)

	msgId := "test-msg-id"
	ts := "2024-01-01T00:00:00Z"

	enc, _ := EncryptContactRequest(recipientPubB64, "hello", msgId, ts)

	// Same ciphertext + wrong ts → auth tag failure
	_, err := DecryptContactRequest(ownPrivB64, enc.EphemeralPublicKey, enc.Ciphertext, enc.Nonce, msgId, "2024-12-31T23:59:59Z")
	if err == nil {
		t.Fatal("should fail with wrong ts (AAD mismatch)")
	}
}

func TestEncryptDecrypt_AAD_Deterministic(t *testing.T) {
	pub, priv := testEd25519Keys()
	recipientPubB64 := base64.StdEncoding.EncodeToString(pub)
	ownPrivB64 := base64.StdEncoding.EncodeToString(priv)

	msgId := "test-msg-id"
	ts := "2024-01-01T00:00:00Z"

	enc, _ := EncryptContactRequest(recipientPubB64, "hello", msgId, ts)

	// Same AAD on encrypt/decrypt → success
	decrypted, err := DecryptContactRequest(ownPrivB64, enc.EphemeralPublicKey, enc.Ciphertext, enc.Nonce, msgId, ts)
	if err != nil {
		t.Fatalf("decrypt error: %v", err)
	}
	if decrypted != "hello" {
		t.Fatalf("expected %q, got %q", "hello", decrypted)
	}
}

// --- Helpers ---

func bytesEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
