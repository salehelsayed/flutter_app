package crypto

import (
	"encoding/base64"
	"strings"
	"testing"
)

func migrationTestSession(t *testing.T) (*MigrationSession, *MlKemKeyPair) {
	t.Helper()
	kp, err := MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen() error: %v", err)
	}
	session, err := MigrationSessionEncap(kp.PublicKey, "session-1", "bundle-1", "old_to_new")
	if err != nil {
		t.Fatalf("MigrationSessionEncap() error: %v", err)
	}
	return session, kp
}

func migrationNonce(counter byte) string {
	nonce := make([]byte, 12)
	nonce[11] = counter
	return base64.StdEncoding.EncodeToString(nonce)
}

const migrationTestAAD = `{"bundle_id":"bundle-1","chunk_index":0,"entry_id":"database","is_final":false,"offset":0,"protocol_version":2,"session_id":"session-1"}`

func TestMigrationSessionKeyMatchesAcrossEncapDecap(t *testing.T) {
	session, kp := migrationTestSession(t)

	derived, err := MigrationSessionDecap(kp.SecretKey, session.KemCiphertext, "session-1", "bundle-1", "old_to_new")
	if err != nil {
		t.Fatalf("MigrationSessionDecap() error: %v", err)
	}
	if derived != session.SessionKey {
		t.Fatal("decapsulated session key differs from encapsulated key")
	}

	keyBytes, err := base64.StdEncoding.DecodeString(session.SessionKey)
	if err != nil {
		t.Fatalf("session key is not base64: %v", err)
	}
	if len(keyBytes) != 32 {
		t.Fatalf("session key = %d bytes, want 32", len(keyBytes))
	}
}

func TestMigrationSessionKeyBindsSessionBundleAndDirection(t *testing.T) {
	session, kp := migrationTestSession(t)

	cases := []struct {
		name      string
		sessionId string
		bundleId  string
		direction string
	}{
		{"different session", "session-2", "bundle-1", "old_to_new"},
		{"different bundle", "session-1", "bundle-2", "old_to_new"},
		{"different direction", "session-1", "bundle-1", "new_to_old"},
	}
	for _, tc := range cases {
		derived, err := MigrationSessionDecap(kp.SecretKey, session.KemCiphertext, tc.sessionId, tc.bundleId, tc.direction)
		if err != nil {
			t.Fatalf("%s: MigrationSessionDecap() error: %v", tc.name, err)
		}
		if derived == session.SessionKey {
			t.Fatalf("%s: session key did not change", tc.name)
		}
	}
}

func TestMigrationChunkRoundTripWithRealAAD(t *testing.T) {
	session, _ := migrationTestSession(t)
	plaintext := base64.StdEncoding.EncodeToString([]byte("chunk payload bytes"))

	ciphertext, err := MigrationChunkEncrypt(session.SessionKey, plaintext, migrationTestAAD, migrationNonce(0))
	if err != nil {
		t.Fatalf("MigrationChunkEncrypt() error: %v", err)
	}

	decrypted, err := MigrationChunkDecrypt(session.SessionKey, ciphertext, migrationTestAAD, migrationNonce(0))
	if err != nil {
		t.Fatalf("MigrationChunkDecrypt() error: %v", err)
	}
	if decrypted != plaintext {
		t.Fatal("chunk round-trip plaintext mismatch")
	}
}

func TestMigrationChunkDecryptRejectsTampering(t *testing.T) {
	session, kp := migrationTestSession(t)
	plaintext := base64.StdEncoding.EncodeToString([]byte("chunk payload bytes"))

	ciphertext, err := MigrationChunkEncrypt(session.SessionKey, plaintext, migrationTestAAD, migrationNonce(0))
	if err != nil {
		t.Fatalf("MigrationChunkEncrypt() error: %v", err)
	}

	tamperedBytes, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		t.Fatalf("decode ciphertext: %v", err)
	}
	tamperedBytes[0] ^= 0x01
	tampered := base64.StdEncoding.EncodeToString(tamperedBytes)

	truncated := base64.StdEncoding.EncodeToString(tamperedBytes[:len(tamperedBytes)-1])

	otherSession, err := MigrationSessionEncap(kp.PublicKey, "session-1", "bundle-1", "old_to_new")
	if err != nil {
		t.Fatalf("second MigrationSessionEncap() error: %v", err)
	}

	cases := []struct {
		name       string
		sessionKey string
		ciphertext string
		aad        string
		nonce      string
	}{
		{"tampered ciphertext byte", session.SessionKey, tampered, migrationTestAAD, migrationNonce(0)},
		{"truncated ciphertext", session.SessionKey, truncated, migrationTestAAD, migrationNonce(0)},
		{"wrong aad chunk index", session.SessionKey, ciphertext, strings.Replace(migrationTestAAD, `"chunk_index":0`, `"chunk_index":1`, 1), migrationNonce(0)},
		{"wrong aad is_final flag", session.SessionKey, ciphertext, strings.Replace(migrationTestAAD, `"is_final":false`, `"is_final":true`, 1), migrationNonce(0)},
		{"reordered nonce counter", session.SessionKey, ciphertext, migrationTestAAD, migrationNonce(1)},
		{"different attempt session key", otherSession.SessionKey, ciphertext, migrationTestAAD, migrationNonce(0)},
	}
	for _, tc := range cases {
		if _, err := MigrationChunkDecrypt(tc.sessionKey, tc.ciphertext, tc.aad, tc.nonce); err == nil {
			t.Fatalf("%s: decrypt unexpectedly succeeded", tc.name)
		}
	}
}

func TestMigrationChunkEncryptRejectsBadNonceAndKey(t *testing.T) {
	session, _ := migrationTestSession(t)
	plaintext := base64.StdEncoding.EncodeToString([]byte("chunk payload bytes"))

	if _, err := MigrationChunkEncrypt(session.SessionKey, plaintext, migrationTestAAD, base64.StdEncoding.EncodeToString([]byte("short"))); err == nil {
		t.Fatal("encrypt accepted a non-96-bit nonce")
	}
	shortKey := base64.StdEncoding.EncodeToString([]byte("not enough bytes"))
	if _, err := MigrationChunkEncrypt(shortKey, plaintext, migrationTestAAD, migrationNonce(0)); err == nil {
		t.Fatal("encrypt accepted a session key that is not 32 bytes")
	}
}
