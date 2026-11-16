package node

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
)

func b293ClientIdentity(t *testing.T, seed byte) (libp2pcrypto.PrivKey, string, string) {
	t.Helper()
	raw := ed25519.NewKeyFromSeed(bytes.Repeat([]byte{seed}, 32))
	key, err := libp2pcrypto.UnmarshalEd25519PrivateKey(raw)
	if err != nil {
		t.Fatal(err)
	}
	id, err := peer.IDFromPrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return key, id.String(), base64.StdEncoding.EncodeToString(raw)
}

// This literal is independent of the production builder and matches the relay
// fixture's contract. The final component comes from the authenticated stream.
func b293ClientProof(day, account, transport string) []byte {
	return []byte("mknoon/activity-account-proof/v1\x00active_identity_v1\x001\x00" + day + "\x00" + account + "\x00" + transport)
}

func b293ClientAckControl(t *testing.T) {
	t.Helper()
	result, err := parseActiveIdentityResponse([]byte(`{"status":"OK","version":1,"data":{"supported":true,"accepted":true}}`))
	if err != nil || result != activeIdentityAcknowledged {
		t.Fatalf("valid ACK control rejected: result%d error%v", result, err)
	}
}

func TestB293ProtocolBuilderSignsCanonicalAccountAndAuthenticatedTransport(t *testing.T) {
	key, account, privateKey := b293ClientIdentity(t, 41)
	_, first, _ := b293ClientIdentity(t, 42)
	_, second, _ := b293ClientIdentity(t, 43)
	for _, transport := range []string{first, second} {
		raw, err := buildActiveIdentityRequest("2026-03-29", account, transport, privateKey)
		if err != nil {
			t.Fatal(err)
		}
		if len(raw) > 2048 {
			t.Fatal("builder exceeded the bounded request contract")
		}
		var request map[string]json.RawMessage
		if err := json.Unmarshal(raw, &request); err != nil || len(request) != 5 {
			t.Fatalf("builder did not produce exactly five fields: %v", err)
		}
		for _, field := range []string{"action", "version", "day", "accountPeerId", "signature"} {
			if request[field] == nil || bytes.Count(raw, []byte(`"`+field+`"`)) != 1 {
				t.Fatalf("missing or repeated request field %q", field)
			}
		}
		if string(request["action"]) != `"active_identity_v1"` || string(request["version"]) != "1" || string(request["day"]) != `"2026-03-29"` || string(request["accountPeerId"]) != `"`+account+`"` {
			t.Fatal("builder changed the literal relay request contract")
		}
		var signatureText string
		if err := json.Unmarshal(request["signature"], &signatureText); err != nil {
			t.Fatal(err)
		}
		signature, err := base64.StdEncoding.DecodeString(signatureText)
		if err != nil || len(signature) != ed25519.SignatureSize || base64.StdEncoding.EncodeToString(signature) != signatureText {
			t.Fatal("builder emitted a noncanonical Ed25519 signature")
		}
		verified, err := key.GetPublic().Verify(b293ClientProof("2026-03-29", account, transport), signature)
		if err != nil || !verified {
			t.Fatalf("builder proof did not verify against independent wire preimage: %v", err)
		}
		wrongTransport := first
		if transport == first {
			wrongTransport = second
		}
		if verified, err := key.GetPublic().Verify(b293ClientProof("2026-03-29", account, wrongTransport), signature); err != nil || verified {
			t.Fatalf("proof was not bound to the authenticated transport: %v", err)
		}
	}
}

func TestB293ProtocolBuilderRefusesInvalidIdentityDayAndPrivateKey(t *testing.T) {
	_, account, privateKey := b293ClientIdentity(t, 41)
	_, transport, _ := b293ClientIdentity(t, 42)
	_, other, otherPrivate := b293ClientIdentity(t, 43)
	if _, err := buildActiveIdentityRequest("2026-03-29", account, transport, privateKey); err != nil {
		t.Fatalf("valid builder control failed: %v", err)
	}
	accountID, err := peer.Decode(account)
	if err != nil {
		t.Fatal(err)
	}
	transportID, err := peer.Decode(transport)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ name, day, account, transport, privateKey string }{
		{"empty-day", "", account, transport, privateKey},
		{"invalid-calendar-date", "2026-02-29", account, transport, privateKey},
		{"noncanonical-day", "2026-3-29", account, transport, privateKey},
		{"timestamp-instead-of-day", "2026-03-29T00:00:00Z", account, transport, privateKey},
		{"empty-account", "2026-03-29", "", transport, privateKey},
		{"invalid-account", "2026-03-29", "private-b293-invalid-account", transport, privateKey},
		{"noncanonical-account", "2026-03-29", peer.ToCid(accountID).String(), transport, privateKey},
		{"empty-transport", "2026-03-29", account, "", privateKey},
		{"invalid-transport", "2026-03-29", account, "private-b293-invalid-transport", privateKey},
		{"noncanonical-transport", "2026-03-29", account, peer.ToCid(transportID).String(), privateKey},
		{"foreign-root-key", "2026-03-29", account, transport, otherPrivate},
		{"different-account", "2026-03-29", other, transport, privateKey},
		{"empty-key", "2026-03-29", account, transport, ""},
		{"key-not-base64", "2026-03-29", account, transport, "private-b293-secret-not-base64"},
		{"key-not-64-bytes", "2026-03-29", account, transport, base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{41}, 32))},
		{"key-newline", "2026-03-29", account, transport, privateKey + "\n"},
		{"key-unpadded", "2026-03-29", account, transport, strings.TrimRight(privateKey, "=")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			raw, err := buildActiveIdentityRequest(tc.day, tc.account, tc.transport, tc.privateKey)
			if !errors.Is(err, errActiveIdentityInvalidRequest) || len(raw) != 0 || err.Error() != errActiveIdentityInvalidRequest.Error() {
				t.Fatalf("invalid local assertion was built: bytes%d error%v", len(raw), err)
			}
			if strings.Contains(err.Error(), "private-b293-") || strings.Contains(err.Error(), tc.privateKey) && tc.privateKey != "" {
				t.Fatal("builder error echoed private input")
			}
		})
	}
}

func TestB293ProtocolResponseDistinguishesAckUnsupportedAndRetry(t *testing.T) {
	for _, tc := range []struct {
		name, raw string
		want      activeIdentityProtocolResult
		wantError error
	}{
		{"ack", `{"status":"OK","version":1,"data":{"supported":true,"accepted":true}}`, activeIdentityAcknowledged, nil},
		{"feature-absent", `{"status":"OK","version":1,"data":{"supported":false,"accepted":false}}`, activeIdentityUnsupported, nil},
		{"supported-refusal", `{"status":"OK","version":1,"data":{"supported":true,"accepted":false}}`, activeIdentityRetryable, nil},
		{"legacy-exact-action", `{"status":"ERROR","error":"Unknown action: active_identity_v1"}`, activeIdentityUnsupported, nil},
		{"legacy-empty-code", `{"status":"ERROR","errorCode":"","error":"Unknown action: active_identity_v1"}`, activeIdentityUnsupported, nil},
		{"storage-failure", `{"status":"ERROR","version":1,"errorCode":"ACTIVE_IDENTITY_STORAGE_UNAVAILABLE"}`, activeIdentityRetryable, errActiveIdentityRelayFailure},
		{"relay-refusal", `{"status":"ERROR","version":1,"errorCode":"ACTIVE_IDENTITY_INVALID_REQUEST"}`, activeIdentityRetryable, errActiveIdentityRelayFailure},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseActiveIdentityResponse([]byte(tc.raw))
			if got != tc.want || !errors.Is(err, tc.wantError) || tc.wantError != nil && err.Error() != tc.wantError.Error() {
				t.Fatalf("typed response result%d error%v, want%d %v", got, err, tc.want, tc.wantError)
			}
		})
	}
}

func TestB293ProtocolResponseRejectsMalformedContradictoryAndSmuggledAcks(t *testing.T) {
	b293ClientAckControl(t)
	valid := `{"status":"OK","version":1,"data":{"supported":true,"accepted":true}}`
	padded := valid + strings.Repeat(" ", 2048-len(valid))
	if result, err := parseActiveIdentityResponse([]byte(padded)); err != nil || result != activeIdentityAcknowledged {
		t.Fatalf("bounded valid ACK was rejected: result%d error%v", result, err)
	}
	for name, raw := range map[string]string{
		"empty": "", "null": "null", "array": "[]", "malformed": `{"status":`,
		"trailing-json": valid + `{}`, "oversized": padded + " ",
		"missing-status":           `{"version":1,"data":{"supported":true,"accepted":true}}`,
		"null-status":              `{"status":null,"version":1,"data":{"supported":true,"accepted":true}}`,
		"unknown-status":           `{"status":"MAYBE","version":1,"data":{"supported":true,"accepted":true}}`,
		"boolean-status":           `{"status":true,"version":1,"data":{"supported":true,"accepted":true}}`,
		"missing-version":          `{"status":"OK","data":{"supported":true,"accepted":true}}`,
		"null-version":             `{"status":"OK","version":null,"data":{"supported":true,"accepted":true}}`,
		"wrong-version":            `{"status":"OK","version":2,"data":{"supported":true,"accepted":true}}`,
		"string-version":           `{"status":"OK","version":"1","data":{"supported":true,"accepted":true}}`,
		"decimal-version":          `{"status":"OK","version":1.0,"data":{"supported":true,"accepted":true}}`,
		"boolean-version":          `{"status":"OK","version":true,"data":{"supported":true,"accepted":true}}`,
		"missing-data":             `{"status":"OK","version":1}`,
		"null-data":                `{"status":"OK","version":1,"data":null}`,
		"array-data":               `{"status":"OK","version":1,"data":[]}`,
		"missing-supported":        `{"status":"OK","version":1,"data":{"accepted":true}}`,
		"missing-accepted":         `{"status":"OK","version":1,"data":{"supported":true}}`,
		"null-supported":           `{"status":"OK","version":1,"data":{"supported":null,"accepted":true}}`,
		"null-accepted":            `{"status":"OK","version":1,"data":{"supported":true,"accepted":null}}`,
		"number-supported":         `{"status":"OK","version":1,"data":{"supported":1,"accepted":true}}`,
		"string-accepted":          `{"status":"OK","version":1,"data":{"supported":true,"accepted":"true"}}`,
		"contradictory-ack":        `{"status":"OK","version":1,"data":{"supported":false,"accepted":true}}`,
		"unknown-top-field":        `{"status":"OK","version":1,"accountPeerId":"private-b293-response-account","data":{"supported":true,"accepted":true}}`,
		"unknown-data-field":       `{"status":"OK","version":1,"data":{"supported":true,"accepted":true,"signature":"private-b293-response-signature"}}`,
		"duplicate-status":         `{"status":"OK","status":"OK","version":1,"data":{"supported":true,"accepted":true}}`,
		"duplicate-data":           `{"status":"OK","version":1,"data":{"supported":true,"accepted":true},"data":{"supported":true,"accepted":true}}`,
		"duplicate-supported":      `{"status":"OK","version":1,"data":{"supported":true,"supported":true,"accepted":true}}`,
		"duplicate-accepted":       `{"status":"OK","version":1,"data":{"supported":true,"accepted":false,"accepted":true}}`,
		"case-alias-status":        `{"Status":"OK","version":1,"data":{"supported":true,"accepted":true}}`,
		"case-duplicate-status":    `{"status":"OK","Status":"OK","version":1,"data":{"supported":true,"accepted":true}}`,
		"case-alias-supported":     `{"status":"OK","version":1,"data":{"Supported":true,"accepted":true}}`,
		"case-duplicate-accepted":  `{"status":"OK","version":1,"data":{"supported":true,"accepted":true,"Accepted":true}}`,
		"ok-with-error":            `{"status":"OK","version":1,"error":"private-b293-response-error","data":{"supported":true,"accepted":true}}`,
		"ok-with-error-code":       `{"status":"OK","version":1,"errorCode":"ACTIVE_IDENTITY_INVALID_REQUEST","data":{"supported":true,"accepted":true}}`,
		"error-with-ack":           `{"status":"ERROR","version":1,"errorCode":"ACTIVE_IDENTITY_STORAGE_UNAVAILABLE","data":{"supported":true,"accepted":true}}`,
		"legacy-with-ack":          `{"status":"ERROR","error":"Unknown action: active_identity_v1","data":{"supported":true,"accepted":true}}`,
		"legacy-with-foreign-code": `{"status":"ERROR","errorCode":"PRIVATE_FAILURE","error":"Unknown action: active_identity_v1"}`,
		"legacy-other-action":      `{"status":"ERROR","error":"Unknown action: app_diagnostics_v1"}`,
		"legacy-prefix":            `{"status":"ERROR","error":"private-b293-prefix Unknown action: active_identity_v1"}`,
		"legacy-suffix":            `{"status":"ERROR","error":"Unknown action: active_identity_v1/private-b293-suffix"}`,
		"arbitrary-error":          `{"status":"ERROR","error":"private-b293-account-transport-signature"}`,
	} {
		t.Run(name, func(t *testing.T) {
			result, err := parseActiveIdentityResponse([]byte(raw))
			if result != activeIdentityRetryable || !errors.Is(err, errActiveIdentityInvalidResponse) || err.Error() != errActiveIdentityInvalidResponse.Error() {
				t.Fatalf("malformed/unrelated reply became ACK or unsupported: result%d error%v", result, err)
			}
			if strings.Contains(err.Error(), "private-b293-") || raw != "" && strings.Contains(err.Error(), raw) {
				t.Fatal("codec error echoed the untrusted relay reply")
			}
		})
	}
}
