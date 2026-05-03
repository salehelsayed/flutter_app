package identity

import (
	"encoding/base64"
	"strings"
	"testing"
)

// Test 1: GenerateIdentity returns valid identity with all fields populated.
func TestGenerateIdentity_ReturnsValidIdentityWithAllFields(t *testing.T) {
	id, err := GenerateIdentity()
	if err != nil {
		t.Fatalf("GenerateIdentity() returned error: %v", err)
	}

	if id.PeerId == "" {
		t.Error("PeerId is empty")
	}
	if id.PublicKey == "" {
		t.Error("PublicKey is empty")
	}
	if id.PrivateKey == "" {
		t.Error("PrivateKey is empty")
	}
	if id.Mnemonic12 == "" {
		t.Error("Mnemonic12 is empty")
	}
	if id.CreatedAt == "" {
		t.Error("CreatedAt is empty")
	}
	if id.UpdatedAt == "" {
		t.Error("UpdatedAt is empty")
	}
	if id.CreatedAt != id.UpdatedAt {
		t.Errorf("expected CreatedAt == UpdatedAt on fresh identity, got %q != %q", id.CreatedAt, id.UpdatedAt)
	}

	words := strings.Fields(id.Mnemonic12)
	if len(words) != 12 {
		t.Errorf("expected 12 mnemonic words, got %d: %q", len(words), id.Mnemonic12)
	}
}

// Test 2: GenerateIdentity produces unique PeerIds.
func TestGenerateIdentity_ProducesUniquePeerIds(t *testing.T) {
	id1, err := GenerateIdentity()
	if err != nil {
		t.Fatalf("first GenerateIdentity() returned error: %v", err)
	}

	id2, err := GenerateIdentity()
	if err != nil {
		t.Fatalf("second GenerateIdentity() returned error: %v", err)
	}

	if id1.PeerId == id2.PeerId {
		t.Error("two generated identities have the same PeerId; expected unique")
	}
	if id1.Mnemonic12 == id2.Mnemonic12 {
		t.Error("two generated identities have the same mnemonic; expected unique")
	}
}

func TestSP003GenerateIdentityUsesFreshMnemonicEntropy(t *testing.T) {
	const samples = 16
	seenPeerIds := make(map[string]struct{}, samples)
	seenMnemonics := make(map[string]struct{}, samples)

	for i := 0; i < samples; i++ {
		id, err := GenerateIdentity()
		if err != nil {
			t.Fatalf("GenerateIdentity() #%d returned error: %v", i+1, err)
		}
		if words := strings.Fields(id.Mnemonic12); len(words) != 12 {
			t.Fatalf("identity #%d mnemonic word count = %d, want 12", i+1, len(words))
		}
		if _, exists := seenPeerIds[id.PeerId]; exists {
			t.Fatalf("duplicate peer id at sample %d", i+1)
		}
		if _, exists := seenMnemonics[id.Mnemonic12]; exists {
			t.Fatalf("duplicate mnemonic at sample %d", i+1)
		}
		seenPeerIds[id.PeerId] = struct{}{}
		seenMnemonics[id.Mnemonic12] = struct{}{}
	}
}

// Test 3: RestoreIdentity from same mnemonic produces identical PeerId, PublicKey, PrivateKey.
func TestRestoreIdentity_SameMnemonicProducesIdenticalIdentity(t *testing.T) {
	original, err := GenerateIdentity()
	if err != nil {
		t.Fatalf("GenerateIdentity() returned error: %v", err)
	}

	restored, err := RestoreIdentity(original.Mnemonic12)
	if err != nil {
		t.Fatalf("RestoreIdentity() returned error: %v", err)
	}

	if restored.PeerId != original.PeerId {
		t.Errorf("PeerId mismatch: original=%q, restored=%q", original.PeerId, restored.PeerId)
	}
	if restored.PublicKey != original.PublicKey {
		t.Errorf("PublicKey mismatch: original=%q, restored=%q", original.PublicKey, restored.PublicKey)
	}
	if restored.PrivateKey != original.PrivateKey {
		t.Errorf("PrivateKey mismatch: original=%q, restored=%q", original.PrivateKey, restored.PrivateKey)
	}
}

// Test 4: RestoreIdentity fails for invalid word count.
func TestRestoreIdentity_FailsForInvalidWordCount(t *testing.T) {
	tests := []struct {
		name     string
		mnemonic string
		wantN    int
	}{
		{"too few (3 words)", "abandon ability able", 3},
		{"too many (15 words)", "abandon ability able about above absent absorb abstract absurd abuse access accident acid acoustic across", 15},
		{"empty", "", 0},
		{"single word", "abandon", 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := RestoreIdentity(tt.mnemonic)
			if err == nil {
				t.Fatalf("expected error for %d words, got nil", tt.wantN)
			}
			if !strings.Contains(err.Error(), "expected 12 words") {
				t.Errorf("expected word count error, got: %v", err)
			}
		})
	}
}

// Test 5: RestoreIdentity fails for invalid BIP39 checksum.
func TestRestoreIdentity_FailsForInvalidChecksum(t *testing.T) {
	// 12 real BIP39 words but invalid checksum combination.
	invalid := "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"
	_, err := RestoreIdentity(invalid)
	if err == nil {
		t.Fatal("expected error for invalid mnemonic, got nil")
	}
	if !strings.Contains(err.Error(), "BIP39 checksum") {
		t.Errorf("expected BIP39 checksum error, got: %v", err)
	}
}

// Test 6: RestoreIdentity normalizes input (trim, lowercase).
func TestRestoreIdentity_NormalizesInput(t *testing.T) {
	original, err := GenerateIdentity()
	if err != nil {
		t.Fatalf("GenerateIdentity() returned error: %v", err)
	}

	// Add leading/trailing whitespace, extra spaces between words, and uppercase.
	messyMnemonic := "  " + strings.ToUpper(original.Mnemonic12) + "  "
	messyMnemonic = strings.Replace(messyMnemonic, " ", "   ", 3) // triple some spaces

	restored, err := RestoreIdentity(messyMnemonic)
	if err != nil {
		t.Fatalf("RestoreIdentity() with messy input returned error: %v", err)
	}

	if restored.PeerId != original.PeerId {
		t.Errorf("PeerId mismatch after normalization: original=%q, restored=%q", original.PeerId, restored.PeerId)
	}
	if restored.PublicKey != original.PublicKey {
		t.Errorf("PublicKey mismatch after normalization: original=%q, restored=%q", original.PublicKey, restored.PublicKey)
	}
	if restored.PrivateKey != original.PrivateKey {
		t.Errorf("PrivateKey mismatch after normalization: original=%q, restored=%q", original.PrivateKey, restored.PrivateKey)
	}
}

// Test 7: Public key is 32 bytes when base64-decoded.
func TestGenerateIdentity_PublicKeyIs32Bytes(t *testing.T) {
	id, err := GenerateIdentity()
	if err != nil {
		t.Fatalf("GenerateIdentity() returned error: %v", err)
	}

	pubBytes, err := base64.StdEncoding.DecodeString(id.PublicKey)
	if err != nil {
		t.Fatalf("failed to decode PublicKey base64: %v", err)
	}
	if len(pubBytes) != 32 {
		t.Errorf("expected decoded PublicKey to be 32 bytes, got %d", len(pubBytes))
	}
}

// Test 8: Private key is 64 bytes when base64-decoded.
func TestGenerateIdentity_PrivateKeyIs64Bytes(t *testing.T) {
	id, err := GenerateIdentity()
	if err != nil {
		t.Fatalf("GenerateIdentity() returned error: %v", err)
	}

	privBytes, err := base64.StdEncoding.DecodeString(id.PrivateKey)
	if err != nil {
		t.Fatalf("failed to decode PrivateKey base64: %v", err)
	}
	if len(privBytes) != 64 {
		t.Errorf("expected decoded PrivateKey to be 64 bytes, got %d", len(privBytes))
	}
}

// Test 9: PeerId starts with "12D3KooW".
func TestGenerateIdentity_PeerIdStartsWith12D3KooW(t *testing.T) {
	id, err := GenerateIdentity()
	if err != nil {
		t.Fatalf("GenerateIdentity() returned error: %v", err)
	}

	if !strings.HasPrefix(id.PeerId, "12D3KooW") {
		t.Errorf("expected PeerId to start with '12D3KooW', got %q", id.PeerId)
	}
}
