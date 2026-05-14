package crypto

import (
	"bytes"
	"encoding/base64"
	"strings"
	"testing"
)

func TestGenerateGroupKey_Length(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	keyBytes, err := base64.StdEncoding.DecodeString(keyB64)
	if err != nil {
		t.Fatalf("decode group key: %v", err)
	}

	if len(keyBytes) != 32 {
		t.Errorf("group key length = %d, want 32", len(keyBytes))
	}
}

func TestGenerateGroupKey_Unique(t *testing.T) {
	key1, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() #1 error: %v", err)
	}

	key2, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() #2 error: %v", err)
	}

	if key1 == key2 {
		t.Error("two generated group keys should be different")
	}
}

func TestGK001GenerateGroupKeyReturns32ByteBase64AESKey(t *testing.T) {
	const samples = 128
	seen := make(map[string]struct{}, samples)

	for i := 0; i < samples; i++ {
		keyB64, err := GenerateGroupKey()
		if err != nil {
			t.Fatalf("GenerateGroupKey() #%d error: %v", i+1, err)
		}
		keyBytes, err := base64.StdEncoding.Strict().DecodeString(keyB64)
		if err != nil {
			t.Fatalf("GK-001 key #%d is not valid standard base64: %v", i+1, err)
		}
		if len(keyBytes) != 32 {
			t.Fatalf("GK-001 key #%d decoded length = %d, want 32", i+1, len(keyBytes))
		}
		if _, exists := seen[keyB64]; exists {
			t.Fatalf("GK-001 duplicate generated key at sample %d", i+1)
		}
		seen[keyB64] = struct{}{}
	}
}

func TestSP003GroupKeysAndNoncesUseFreshRandomness(t *testing.T) {
	const samples = 64
	seenKeys := make(map[string]struct{}, samples)

	for i := 0; i < samples; i++ {
		keyB64, err := GenerateGroupKey()
		if err != nil {
			t.Fatalf("GenerateGroupKey() #%d error: %v", i+1, err)
		}
		keyBytes, err := base64.StdEncoding.DecodeString(keyB64)
		if err != nil {
			t.Fatalf("decode group key #%d: %v", i+1, err)
		}
		if len(keyBytes) != 32 {
			t.Fatalf("group key #%d length = %d, want 32", i+1, len(keyBytes))
		}
		if _, exists := seenKeys[keyB64]; exists {
			t.Fatalf("duplicate group key at sample %d", i+1)
		}
		seenKeys[keyB64] = struct{}{}
	}

	fixedKeyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() for nonce samples error: %v", err)
	}
	seenNonces := make(map[string]struct{}, samples)
	seenCiphertexts := make(map[string]struct{}, samples)
	for i := 0; i < samples; i++ {
		ctB64, nonceB64, err := EncryptGroupMessage(fixedKeyB64, "SP-003 stable plaintext")
		if err != nil {
			t.Fatalf("EncryptGroupMessage() #%d error: %v", i+1, err)
		}
		nonceBytes, err := base64.StdEncoding.DecodeString(nonceB64)
		if err != nil {
			t.Fatalf("decode nonce #%d: %v", i+1, err)
		}
		if len(nonceBytes) != 12 {
			t.Fatalf("nonce #%d length = %d, want 12", i+1, len(nonceBytes))
		}
		if _, exists := seenNonces[nonceB64]; exists {
			t.Fatalf("duplicate nonce at sample %d", i+1)
		}
		if _, exists := seenCiphertexts[ctB64]; exists {
			t.Fatalf("duplicate ciphertext at sample %d", i+1)
		}
		seenNonces[nonceB64] = struct{}{}
		seenCiphertexts[ctB64] = struct{}{}
	}
}

func TestGroupEncryptDecrypt_RoundTrip(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	original := "Hello, group messaging! This is a secret."

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, original)
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	if ctB64 == "" {
		t.Error("ciphertext is empty")
	}
	if nonceB64 == "" {
		t.Error("nonce is empty")
	}

	decrypted, err := DecryptGroupMessage(keyB64, ctB64, nonceB64)
	if err != nil {
		t.Fatalf("DecryptGroupMessage() error: %v", err)
	}

	if decrypted != original {
		t.Errorf("decrypted = %q, want %q", decrypted, original)
	}
}

func TestGK002EncryptDecryptRoundTripForTextPayload(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	payload := `{"type":"text","body":"GK-002 exact round trip","meta":{"line":1,"urgent":false}}`
	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, payload)
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	if ctB64 == "" {
		t.Fatal("ciphertext is empty")
	}
	if nonceB64 == "" {
		t.Fatal("nonce is empty")
	}

	strictBase64 := base64.StdEncoding.Strict()
	ctBytes, err := strictBase64.DecodeString(ctB64)
	if err != nil {
		t.Fatalf("ciphertext is not strict standard base64: %v", err)
	}
	if len(ctBytes) == 0 {
		t.Fatal("decoded ciphertext is empty")
	}
	nonceBytes, err := strictBase64.DecodeString(nonceB64)
	if err != nil {
		t.Fatalf("nonce is not strict standard base64: %v", err)
	}
	if len(nonceBytes) != 12 {
		t.Fatalf("decoded nonce length = %d, want 12", len(nonceBytes))
	}

	decrypted, err := DecryptGroupMessage(keyB64, ctB64, nonceB64)
	if err != nil {
		t.Fatalf("DecryptGroupMessage() error: %v", err)
	}
	if !bytes.Equal([]byte(decrypted), []byte(payload)) {
		t.Errorf("decrypted bytes = %q, want %q", decrypted, payload)
	}
}

func TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	const samples = 128
	payload := `{"type":"text","body":"GK-003 stable plaintext","meta":{"sample":true}}`
	strictBase64 := base64.StdEncoding.Strict()
	seenNonces := make(map[string]struct{}, samples)
	seenCiphertexts := make(map[string]struct{}, samples)

	for i := 0; i < samples; i++ {
		ctB64, nonceB64, err := EncryptGroupMessage(keyB64, payload)
		if err != nil {
			t.Fatalf("EncryptGroupMessage() #%d error: %v", i+1, err)
		}
		if ctB64 == "" {
			t.Fatalf("ciphertext #%d is empty", i+1)
		}
		if nonceB64 == "" {
			t.Fatalf("nonce #%d is empty", i+1)
		}

		ctBytes, err := strictBase64.DecodeString(ctB64)
		if err != nil {
			t.Fatalf("ciphertext #%d is not strict standard base64: %v", i+1, err)
		}
		if len(ctBytes) == 0 {
			t.Fatalf("decoded ciphertext #%d is empty", i+1)
		}

		nonceBytes, err := strictBase64.DecodeString(nonceB64)
		if err != nil {
			t.Fatalf("nonce #%d is not strict standard base64: %v", i+1, err)
		}
		if len(nonceBytes) != 12 {
			t.Fatalf("decoded nonce #%d length = %d, want 12", i+1, len(nonceBytes))
		}

		if _, exists := seenNonces[nonceB64]; exists {
			t.Fatalf("duplicate nonce at sample %d", i+1)
		}
		if _, exists := seenCiphertexts[ctB64]; exists {
			t.Fatalf("duplicate ciphertext at sample %d", i+1)
		}
		seenNonces[nonceB64] = struct{}{}
		seenCiphertexts[ctB64] = struct{}{}
	}
}

func TestGroupEncryptDecrypt_WrongKey(t *testing.T) {
	key1, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() #1 error: %v", err)
	}

	key2, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() #2 error: %v", err)
	}

	ctB64, nonceB64, err := EncryptGroupMessage(key1, "secret for key1")
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	_, err = DecryptGroupMessage(key2, ctB64, nonceB64)
	if err == nil {
		t.Error("decryption with wrong key should fail")
	}
}

func TestGroupEncryptDecrypt_TamperedCiphertext(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, "do not tamper")
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	// Tamper with ciphertext by decoding, flipping a byte, and re-encoding.
	ctBytes, _ := base64.StdEncoding.DecodeString(ctB64)
	ctBytes[0] ^= 0xFF
	tamperedCt := base64.StdEncoding.EncodeToString(ctBytes)

	_, err = DecryptGroupMessage(keyB64, tamperedCt, nonceB64)
	if err == nil {
		t.Error("decryption with tampered ciphertext should fail")
	}
}

func TestGroupEncryptDecrypt_TamperedNonce(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, "do not tamper nonce")
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	// Tamper with nonce by decoding, flipping a byte, and re-encoding.
	nonceBytes, _ := base64.StdEncoding.DecodeString(nonceB64)
	nonceBytes[0] ^= 0xFF
	tamperedNonce := base64.StdEncoding.EncodeToString(nonceBytes)

	_, err = DecryptGroupMessage(keyB64, ctB64, tamperedNonce)
	if err == nil {
		t.Error("decryption with tampered nonce should fail")
	}
}

func TestGroupEncryptDecrypt_UniqueNonces(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	plaintext := "same message both times"

	_, nonce1, err := EncryptGroupMessage(keyB64, plaintext)
	if err != nil {
		t.Fatalf("EncryptGroupMessage() #1 error: %v", err)
	}

	_, nonce2, err := EncryptGroupMessage(keyB64, plaintext)
	if err != nil {
		t.Fatalf("EncryptGroupMessage() #2 error: %v", err)
	}

	if nonce1 == nonce2 {
		t.Error("nonces should differ for different encryptions")
	}
}

func TestGroupEncryptDecrypt_EmptyString(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, "")
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	decrypted, err := DecryptGroupMessage(keyB64, ctB64, nonceB64)
	if err != nil {
		t.Fatalf("DecryptGroupMessage() error: %v", err)
	}

	if decrypted != "" {
		t.Errorf("decrypted = %q, want empty string", decrypted)
	}
}

func TestGroupEncryptDecrypt_LargeMessage(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	// 1 MB plaintext.
	original := strings.Repeat("A", 1024*1024)

	ctB64, nonceB64, err := EncryptGroupMessage(keyB64, original)
	if err != nil {
		t.Fatalf("EncryptGroupMessage() error: %v", err)
	}

	decrypted, err := DecryptGroupMessage(keyB64, ctB64, nonceB64)
	if err != nil {
		t.Fatalf("DecryptGroupMessage() error: %v", err)
	}

	if decrypted != original {
		t.Errorf("decrypted length = %d, want %d", len(decrypted), len(original))
	}
}

func TestEncryptGroupMessage_InvalidKey(t *testing.T) {
	_, _, err := EncryptGroupMessage("not-valid-base64!!!", "hello")
	if err == nil {
		t.Error("EncryptGroupMessage with non-base64 key should fail")
	}
}

func TestGK004InvalidKeyBase64IsRejected(t *testing.T) {
	malformedKeyB64 := "not-valid-base64!!!"

	ctB64, nonceB64, err := EncryptGroupMessage(malformedKeyB64, "GK-004 plaintext")
	if err == nil {
		t.Fatal("EncryptGroupMessage with malformed group key should fail")
	}
	if !strings.Contains(err.Error(), "decode group key") {
		t.Fatalf("EncryptGroupMessage error = %q, want decode group key", err.Error())
	}
	if ctB64 != "" || nonceB64 != "" {
		t.Fatalf("EncryptGroupMessage returned ciphertext=%q nonce=%q, want empty outputs", ctB64, nonceB64)
	}

	validLookingCiphertextB64 := base64.StdEncoding.EncodeToString([]byte("GK-004 ciphertext placeholder"))
	validLookingNonceB64 := base64.StdEncoding.EncodeToString(make([]byte, 12))
	plaintext, err := DecryptGroupMessage(malformedKeyB64, validLookingCiphertextB64, validLookingNonceB64)
	if err == nil {
		t.Fatal("DecryptGroupMessage with malformed group key should fail")
	}
	if !strings.Contains(err.Error(), "decode group key") {
		t.Fatalf("DecryptGroupMessage error = %q, want decode group key", err.Error())
	}
	if plaintext != "" {
		t.Fatalf("DecryptGroupMessage plaintext = %q, want empty", plaintext)
	}
}

func TestGK005WrongKeyLengthIsRejected(t *testing.T) {
	wrongLengthKeyB64 := base64.StdEncoding.EncodeToString(make([]byte, 16))

	ctB64, nonceB64, err := EncryptGroupMessage(wrongLengthKeyB64, "GK-005 plaintext")
	if err == nil {
		t.Fatal("EncryptGroupMessage with 16-byte group key should fail")
	}
	if !strings.Contains(err.Error(), "invalid group key length") {
		t.Fatalf("EncryptGroupMessage error = %q, want invalid group key length", err.Error())
	}
	if !strings.Contains(err.Error(), "got 16, want 32") {
		t.Fatalf("EncryptGroupMessage error = %q, want got 16, want 32", err.Error())
	}
	if ctB64 != "" || nonceB64 != "" {
		t.Fatalf("EncryptGroupMessage returned ciphertext=%q nonce=%q, want empty outputs", ctB64, nonceB64)
	}

	validLookingCiphertextB64 := base64.StdEncoding.EncodeToString([]byte("GK-005 ciphertext placeholder"))
	validLookingNonceB64 := base64.StdEncoding.EncodeToString(make([]byte, 12))
	plaintext, err := DecryptGroupMessage(wrongLengthKeyB64, validLookingCiphertextB64, validLookingNonceB64)
	if err == nil {
		t.Fatal("DecryptGroupMessage with 16-byte group key should fail")
	}
	if !strings.Contains(err.Error(), "invalid group key length") {
		t.Fatalf("DecryptGroupMessage error = %q, want invalid group key length", err.Error())
	}
	if !strings.Contains(err.Error(), "got 16, want 32") {
		t.Fatalf("DecryptGroupMessage error = %q, want got 16, want 32", err.Error())
	}
	if plaintext != "" {
		t.Fatalf("DecryptGroupMessage plaintext = %q, want empty", plaintext)
	}
}

func TestEncryptGroupMessage_WrongKeyLength(t *testing.T) {
	// 16-byte key (AES-128) instead of required 32-byte (AES-256).
	shortKey := make([]byte, 16)
	shortKeyB64 := base64.StdEncoding.EncodeToString(shortKey)

	_, _, err := EncryptGroupMessage(shortKeyB64, "hello")
	if err == nil {
		t.Error("EncryptGroupMessage with 16-byte key should fail")
	}
}

func TestDecryptGroupMessage_InvalidBase64(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	// Invalid base64 for ciphertext.
	_, err = DecryptGroupMessage(keyB64, "not-valid!!!", "AAAAAAAAAAAAAAAA")
	if err == nil {
		t.Error("DecryptGroupMessage with invalid ciphertext base64 should fail")
	}

	// Invalid base64 for nonce.
	_, err = DecryptGroupMessage(keyB64, "AAAAAAAAAA==", "not-valid!!!")
	if err == nil {
		t.Error("DecryptGroupMessage with invalid nonce base64 should fail")
	}

	// Invalid base64 for key.
	_, err = DecryptGroupMessage("not-valid!!!", "AAAAAAAAAA==", "AAAAAAAAAAAAAAAA")
	if err == nil {
		t.Error("DecryptGroupMessage with invalid key base64 should fail")
	}
}

func TestGK013DecryptGroupMessageRejectsMissingCiphertextOrNonceWithoutPanic(t *testing.T) {
	keyB64, err := GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey() error: %v", err)
	}

	validNonceB64 := base64.StdEncoding.EncodeToString(make([]byte, 12))
	validLookingCiphertextB64 := base64.StdEncoding.EncodeToString([]byte("GK-013 valid-looking ciphertext"))
	shortNonceB64 := base64.StdEncoding.EncodeToString([]byte{1, 2, 3})

	cases := []struct {
		name      string
		ctB64     string
		nonceB64  string
		wantError string
	}{
		{
			name:      "missing ciphertext",
			ctB64:     "",
			nonceB64:  validNonceB64,
			wantError: "missing ciphertext",
		},
		{
			name:      "missing nonce",
			ctB64:     validLookingCiphertextB64,
			nonceB64:  "",
			wantError: "missing nonce",
		},
		{
			name:      "wrong decoded nonce length",
			ctB64:     validLookingCiphertextB64,
			nonceB64:  shortNonceB64,
			wantError: "invalid nonce length",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var plaintext string
			var decryptErr error
			var panicValue interface{}
			func() {
				defer func() {
					panicValue = recover()
				}()
				plaintext, decryptErr = DecryptGroupMessage(keyB64, tc.ctB64, tc.nonceB64)
			}()
			if panicValue != nil {
				t.Fatalf("DecryptGroupMessage panicked for %s: %v", tc.name, panicValue)
			}
			if decryptErr == nil {
				t.Fatalf("DecryptGroupMessage error = nil, want %q", tc.wantError)
			}
			if !strings.Contains(decryptErr.Error(), tc.wantError) {
				t.Fatalf("DecryptGroupMessage error = %q, want %q", decryptErr.Error(), tc.wantError)
			}
			if plaintext != "" {
				t.Fatalf("DecryptGroupMessage plaintext = %q, want empty", plaintext)
			}
		})
	}
}

func TestBuildGroupSignatureData_Format(t *testing.T) {
	result := BuildGroupSignatureData("group-abc-123", 5, "c2VjcmV0")
	expected := "group-abc-123|5|c2VjcmV0"

	if result != expected {
		t.Errorf("BuildGroupSignatureData = %q, want %q", result, expected)
	}
}

func TestBuildGroupSignatureData_Deterministic(t *testing.T) {
	r1 := BuildGroupSignatureData("grp1", 1, "ct1")
	r2 := BuildGroupSignatureData("grp1", 1, "ct1")

	if r1 != r2 {
		t.Errorf("BuildGroupSignatureData not deterministic: %q != %q", r1, r2)
	}
}

func TestGK009SignatureDataIsDeterministicAndEpochBound(t *testing.T) {
	const (
		groupID    = "group-gk-009"
		epoch      = 7
		ciphertext = "Y2lwaGVydGV4dC1nazAwOQ=="
		expected   = "group-gk-009|7|Y2lwaGVydGV4dC1nazAwOQ=="
	)

	baseData := BuildGroupSignatureData(groupID, epoch, ciphertext)
	repeatedData := BuildGroupSignatureData(groupID, epoch, ciphertext)

	if baseData != repeatedData {
		t.Fatalf("BuildGroupSignatureData not deterministic: %q != %q", baseData, repeatedData)
	}
	if baseData != expected {
		t.Fatalf("BuildGroupSignatureData = %q, want %q", baseData, expected)
	}

	publicKeyB64, privateKeyB64 := generateTestKeyPair(t)
	signature, err := SignPayload(privateKeyB64, baseData)
	if err != nil {
		t.Fatalf("SignPayload: %v", err)
	}

	valid, err := VerifyPayload(publicKeyB64, baseData, signature)
	if err != nil {
		t.Fatalf("VerifyPayload base data: %v", err)
	}
	if !valid {
		t.Fatal("VerifyPayload base data = false, want true")
	}

	changedCases := []struct {
		name string
		data string
	}{
		{
			name: "changed epoch",
			data: BuildGroupSignatureData(groupID, epoch+1, ciphertext),
		},
		{
			name: "changed group id",
			data: BuildGroupSignatureData(groupID+"-other", epoch, ciphertext),
		},
		{
			name: "changed ciphertext",
			data: BuildGroupSignatureData(groupID, epoch, "Y2lwaGVydGV4dC1nazAwOS10YW1wZXJlZA=="),
		},
	}

	for _, tc := range changedCases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.data == baseData {
				t.Fatalf("changed data equals base data: %q", tc.data)
			}

			valid, err := VerifyPayload(publicKeyB64, tc.data, signature)
			if err != nil {
				t.Fatalf("VerifyPayload changed data: %v", err)
			}
			if valid {
				t.Fatal("VerifyPayload changed data = true, want false")
			}
		})
	}
}
