package node

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func b29E1ClientControl(t *testing.T) {
	t.Helper()
	_, account, key := b293ClientIdentity(t, 61)
	_, transport, _ := b293ClientIdentity(t, 62)
	if _, err := buildActiveEngagementRequest("2026-W13", []string{"active", "chat"}, account, transport, key); err != nil {
		t.Fatalf("valid engagement builder control: %v", err)
	}
}

func TestB29E1ProtocolCanonicalWireAndPurposeBoundProof(t *testing.T) {
	key, account, private := b293ClientIdentity(t, 61)
	_, transport, _ := b293ClientIdentity(t, 62)
	for _, kinds := range [][]string{{"active"}, {"active", "chat"}, {"active", "call", "group"}, {"active", "chat", "call", "group"}} {
		raw, err := buildActiveEngagementRequest("2026-W13", kinds, account, transport, private)
		if err != nil {
			t.Fatal(err)
		}
		var wire map[string]json.RawMessage
		if json.Unmarshal(raw, &wire) != nil || len(wire) != 6 || len(raw) > 2048 {
			t.Fatal("engagement request did not obey six-field bounded contract")
		}
		for _, name := range []string{"action", "version", "week", "kinds", "accountPeerId", "signature"} {
			if wire[name] == nil {
				t.Fatalf("missing field %s", name)
			}
		}
		if string(wire["accountPeerId"]) != `"`+account+`"` {
			t.Fatal("builder emitted a different canonical account")
		}
		if string(wire["action"]) != `"engagement_identity_v1"` || string(wire["week"]) != `"2026-W13"` || string(wire["version"]) != "1" {
			t.Fatal("wire action/version/week mismatch")
		}
		wantKinds, _ := json.Marshal(kinds)
		if !bytes.Equal(wantKinds, wire["kinds"]) {
			t.Fatal("canonical kind list changed")
		}
		var encoded string
		if json.Unmarshal(wire["signature"], &encoded) != nil {
			t.Fatal("signature type")
		}
		signature, err := base64.StdEncoding.Strict().DecodeString(encoded)
		if err != nil || base64.StdEncoding.EncodeToString(signature) != encoded {
			t.Fatal("signature encoding")
		}
		// Independent frozen literal, shared with the relay fixture rather than a production helper.
		proof := []byte("mknoon/activity-account-proof/v1\x00engagement_identity_v1\x001\x002026-W13\x00" + strings.Join(kinds, ",") + "\x00" + account + "\x00" + transport)
		if ok, err := key.GetPublic().Verify(proof, signature); err != nil || !ok {
			t.Fatal("independent proof did not verify")
		}
		for _, altered := range []string{strings.Replace(string(proof), "engagement_identity_v1", "active_identity_v1", 1), strings.Replace(string(proof), "2026-W13", "2026-W14", 1), string(proof) + "\x00", strings.Replace(string(proof), transport, account, 1)} {
			if ok, _ := key.GetPublic().Verify([]byte(altered), signature); ok {
				t.Fatal("proof did not bind purpose/week/transport/exact bytes")
			}
		}
	}
}

func TestB29E1ProtocolBuilderRejectsInvalidInputsPrivately(t *testing.T) {
	b29E1ClientControl(t)
	_, account, private := b293ClientIdentity(t, 61)
	_, transport, _ := b293ClientIdentity(t, 62)
	for _, kinds := range [][]string{nil, {}, {"chat"}, {"active", "active"}, {"active", "reciprocal"}, {"active", "pair-digest-private"}, {"chat", "active"}, {"active", "group", "call"}} {
		if raw, err := buildActiveEngagementRequest("2026-W13", kinds, account, transport, private); len(raw) != 0 || !errors.Is(err, errActiveEngagementInvalidRequest) {
			t.Fatalf("invalid kinds accepted or leaked: %v", err)
		}
	}
	for _, tc := range []struct{ week, account, transport, key string }{
		{"2026-W54", account, transport, private}, {"2026-W1", account, transport, private}, {"2026-03-29", account, transport, private},
		{"2026-W13", "private-account", transport, private}, {"2026-W13", account, "private-transport", private}, {"2026-W13", account, transport, private + "\n"},
		{"2026-W13", transport, transport, private}, {"2026-W13", account, transport, "private-key"},
	} {
		raw, err := buildActiveEngagementRequest(tc.week, []string{"active"}, tc.account, tc.transport, tc.key)
		if len(raw) != 0 || !errors.Is(err, errActiveEngagementInvalidRequest) || strings.Contains(err.Error(), "private-") {
			t.Fatal("invalid local proof accepted or echoed")
		}
	}
}

func TestB29E1ProtocolTypedResponses(t *testing.T) {
	for _, tc := range []struct {
		raw  string
		want activeEngagementProtocolResult
		err  error
	}{
		{`{"status":"OK","version":1,"data":{"supported":true,"accepted":true}}`, activeEngagementAcknowledged, nil},
		{`{"status":"OK","version":1,"data":{"supported":false,"accepted":false}}`, activeEngagementUnsupported, nil},
		{`{"status":"OK","version":1,"data":{"supported":true,"accepted":false}}`, activeEngagementRetryable, nil},
		{`{"status":"ERROR","error":"Unknown action: engagement_identity_v1"}`, activeEngagementUnsupported, nil},
		{`{"status":"ERROR","errorCode":"","error":"Unknown action: engagement_identity_v1"}`, activeEngagementUnsupported, nil},
		{`{"status":"ERROR","version":1,"errorCode":"ACTIVE_ENGAGEMENT_STORAGE_UNAVAILABLE"}`, activeEngagementRetryable, errActiveEngagementRelayFailure},
		{`{"status":"ERROR","version":1,"errorCode":"ACTIVE_ENGAGEMENT_INVALID_REQUEST"}`, activeEngagementRetryable, errActiveEngagementRelayFailure},
	} {
		got, err := parseActiveEngagementResponse([]byte(tc.raw))
		if got != tc.want || !errors.Is(err, tc.err) {
			t.Fatalf("typed outcome: got %d/%v want %d/%v", got, err, tc.want, tc.err)
		}
	}
}

func TestB29E1ProtocolRefusesSmuggledOrMalformedResponses(t *testing.T) {
	ack := `{"status":"OK","version":1,"data":{"supported":true,"accepted":true}}`
	if result, err := parseActiveEngagementResponse([]byte(ack)); err != nil || result != activeEngagementAcknowledged {
		t.Fatal("valid ACK control")
	}
	for _, raw := range []string{"", "null", "[]", ack + "{}", ack + strings.Repeat(" ", 2049),
		`{"status":"OK","version":1,"data":{"supported":false,"accepted":true}}`,
		`{"status":"OK","version":1.0,"data":{"supported":true,"accepted":true}}`,
		`{"status":"OK","version":1,"data":{"supported":true,"accepted":true,"pairDigest":"private"}}`,
		`{"status":"OK","version":1,"data":{"supported":true,"accepted":false,"accepted":true}}`,
		`{"status":"OK","status":"OK","version":1,"data":{"supported":true,"accepted":true}}`,
		`{"Status":"OK","version":1,"data":{"supported":true,"accepted":true}}`,
		`{"status":"ERROR","error":"Unknown action: active_identity_v1"}`,
		`{"status":"ERROR","error":"Unknown action: engagement_identity_v1/private"}`,
		`{"status":"ERROR","version":1,"errorCode":"private-secret"}`,
	} {
		got, err := parseActiveEngagementResponse([]byte(raw))
		if got != activeEngagementRetryable || !errors.Is(err, errActiveEngagementInvalidResponse) || strings.Contains(err.Error(), "private") {
			t.Fatal("malformed reply became ACK/unsupported or leaked")
		}
	}
}
