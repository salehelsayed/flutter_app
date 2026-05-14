package internal

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestMarshalParseGroupEnvelope_RoundTrip(t *testing.T) {
	original := &GroupEnvelope{
		Version:         "3",
		Type:            "group_message",
		GroupId:         "grp-abc-123",
		SenderId:        "peer-id-xyz",
		SenderPublicKey: "c2VuZGVyLXB1YmxpYy1rZXk=",
		Signature:       "c2lnbmF0dXJl",
		KeyEpoch:        2,
		Encrypted: GroupEncryptedPayload{
			Ciphertext: "Y2lwaGVydGV4dA==",
			Nonce:      "bm9uY2U=",
		},
	}

	data, err := MarshalGroupEnvelope(original)
	if err != nil {
		t.Fatalf("MarshalGroupEnvelope() error: %v", err)
	}

	parsed, err := ParseGroupEnvelope(data)
	if err != nil {
		t.Fatalf("ParseGroupEnvelope() error: %v", err)
	}

	if parsed.Version != original.Version {
		t.Errorf("Version = %q, want %q", parsed.Version, original.Version)
	}
	if parsed.Type != original.Type {
		t.Errorf("Type = %q, want %q", parsed.Type, original.Type)
	}
	if parsed.GroupId != original.GroupId {
		t.Errorf("GroupId = %q, want %q", parsed.GroupId, original.GroupId)
	}
	if parsed.SenderId != original.SenderId {
		t.Errorf("SenderId = %q, want %q", parsed.SenderId, original.SenderId)
	}
	if parsed.SenderPublicKey != original.SenderPublicKey {
		t.Errorf("SenderPublicKey = %q, want %q", parsed.SenderPublicKey, original.SenderPublicKey)
	}
	if parsed.Signature != original.Signature {
		t.Errorf("Signature = %q, want %q", parsed.Signature, original.Signature)
	}
	if parsed.KeyEpoch != original.KeyEpoch {
		t.Errorf("KeyEpoch = %d, want %d", parsed.KeyEpoch, original.KeyEpoch)
	}
	if parsed.Encrypted.Ciphertext != original.Encrypted.Ciphertext {
		t.Errorf("Encrypted.Ciphertext = %q, want %q", parsed.Encrypted.Ciphertext, original.Encrypted.Ciphertext)
	}
	if parsed.Encrypted.Nonce != original.Encrypted.Nonce {
		t.Errorf("Encrypted.Nonce = %q, want %q", parsed.Encrypted.Nonce, original.Encrypted.Nonce)
	}
}

func TestParseGroupEnvelope_InvalidJSON(t *testing.T) {
	_, err := ParseGroupEnvelope("not json at all")
	if err == nil {
		t.Error("ParseGroupEnvelope with invalid JSON should fail")
	}
}

func TestParseGroupEnvelope_MissingFields(t *testing.T) {
	// Missing groupId.
	data := `{"version":"3","type":"group_message","senderId":"peer1","senderPublicKey":"abc","signature":"sig","keyEpoch":1,"encrypted":{"ciphertext":"ct","nonce":"n"}}`
	_, err := ParseGroupEnvelope(data)
	if err == nil {
		t.Error("ParseGroupEnvelope with missing groupId should fail")
	}
}

func TestGK010ParseGroupEnvelopeRejectsMissingGroupID(t *testing.T) {
	data := `{"version":"3","type":"group_message","senderId":"peer1","senderPublicKey":"abc","signature":"sig","keyEpoch":1,"encrypted":{"ciphertext":"ct","nonce":"n"}}`

	env, err := ParseGroupEnvelope(data)
	if env != nil {
		t.Fatalf("ParseGroupEnvelope with missing groupId returned envelope %#v, want nil", env)
	}
	if err == nil {
		t.Fatal("ParseGroupEnvelope with missing groupId returned nil error, want rejection")
	}

	errText := err.Error()
	if !strings.Contains(errText, "parse group envelope") {
		t.Fatalf("ParseGroupEnvelope error = %q, want parser context", errText)
	}
	if !strings.Contains(errText, "missing groupId") {
		t.Fatalf("ParseGroupEnvelope error = %q, want missing groupId detail", errText)
	}
}

func TestIsGroupEnvelope_V3GroupMessage(t *testing.T) {
	data := `{"version":"3","type":"group_message","groupId":"g1","senderId":"s1","senderPublicKey":"pk","signature":"sig","keyEpoch":0,"encrypted":{"ciphertext":"ct","nonce":"n"}}`
	if !IsGroupEnvelope(data) {
		t.Error("IsGroupEnvelope should return true for valid v3 group_message")
	}
}

func TestGK014IsGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction(t *testing.T) {
	cases := []struct {
		name string
		data string
		want bool
	}{
		{
			name: "v3 group message",
			data: `{"version":"3","type":"group_message","groupId":"g1","senderId":"s1","senderPublicKey":"pk","signature":"sig","keyEpoch":0,"encrypted":{"ciphertext":"ct","nonce":"n"}}`,
			want: true,
		},
		{
			name: "v3 group reaction",
			data: `{"version":"3","type":"group_reaction","groupId":"g1","senderId":"s1","senderPublicKey":"pk","signature":"sig","keyEpoch":0,"encrypted":{"ciphertext":"ct","nonce":"n"}}`,
			want: true,
		},
		{
			name: "v2 group message",
			data: `{"version":"2","type":"group_message","groupId":"g1"}`,
		},
		{
			name: "v4 group message",
			data: `{"version":"4","type":"group_message","groupId":"g1"}`,
		},
		{
			name: "v3 unsupported type",
			data: `{"version":"3","type":"group_membership","groupId":"g1"}`,
		},
		{
			name: "missing version",
			data: `{"type":"group_message","groupId":"g1"}`,
		},
		{
			name: "missing type",
			data: `{"version":"3","groupId":"g1"}`,
		},
		{
			name: "numeric version",
			data: `{"version":3,"type":"group_message","groupId":"g1"}`,
		},
		{
			name: "malformed json",
			data: `{"version":"3","type":"group_message"`,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsGroupEnvelope(tc.data); got != tc.want {
				t.Fatalf("IsGroupEnvelope() = %t, want %t for %s", got, tc.want, tc.data)
			}
		})
	}
}

func TestIsGroupEnvelope_V1Message(t *testing.T) {
	data := `{"version":"1","type":"chat_message","payload":{"text":"hello"}}`
	if IsGroupEnvelope(data) {
		t.Error("IsGroupEnvelope should return false for v1 message")
	}
}

func TestIsGroupEnvelope_V2Message(t *testing.T) {
	data := `{"version":"2","encrypted":{"kem":"k","ciphertext":"ct","nonce":"n"}}`
	if IsGroupEnvelope(data) {
		t.Error("IsGroupEnvelope should return false for v2 message")
	}
}

func TestIsGroupEnvelope_InvalidJSON(t *testing.T) {
	if IsGroupEnvelope("not json") {
		t.Error("IsGroupEnvelope should return false for invalid JSON")
	}
}

func TestMarshalParseGroupPayload_RoundTrip(t *testing.T) {
	original := &GroupMessagePayload{
		Text:      "Hello group!",
		Timestamp: "2026-03-02T12:00:00Z",
		Username:  "alice",
	}

	data, err := MarshalGroupPayload(original)
	if err != nil {
		t.Fatalf("MarshalGroupPayload() error: %v", err)
	}

	parsed, err := ParseGroupPayload(data)
	if err != nil {
		t.Fatalf("ParseGroupPayload() error: %v", err)
	}

	if parsed.Text != original.Text {
		t.Errorf("Text = %q, want %q", parsed.Text, original.Text)
	}
	if parsed.Timestamp != original.Timestamp {
		t.Errorf("Timestamp = %q, want %q", parsed.Timestamp, original.Timestamp)
	}
	if parsed.Username != original.Username {
		t.Errorf("Username = %q, want %q", parsed.Username, original.Username)
	}
}

func TestGK029ParseGroupPayloadRejectsWrongSchema(t *testing.T) {
	cases := []struct {
		name      string
		payload   string
		wantError string
	}{
		{name: "non json", payload: "not-json", wantError: "parse group payload"},
		{name: "non object", payload: `["not","an","object"]`, wantError: "parse group payload"},
		{name: "missing text", payload: `{"timestamp":"2026-05-12T20:30:00Z"}`, wantError: "missing text"},
		{name: "null text", payload: `{"text":null,"timestamp":"2026-05-12T20:30:00Z"}`, wantError: "invalid text"},
		{name: "numeric text", payload: `{"text":123,"timestamp":"2026-05-12T20:30:00Z"}`, wantError: "invalid text"},
		{name: "missing timestamp", payload: `{"text":"hello"}`, wantError: "missing timestamp"},
		{name: "blank timestamp", payload: `{"text":"hello","timestamp":"   "}`, wantError: "missing timestamp"},
		{name: "numeric timestamp", payload: `{"text":"hello","timestamp":123}`, wantError: "invalid timestamp"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			parsed, err := ParseGroupPayload(tc.payload)
			if err == nil {
				t.Fatalf("ParseGroupPayload() err = nil, parsed=%#v, want %q", parsed, tc.wantError)
			}
			if !strings.Contains(err.Error(), tc.wantError) {
				t.Fatalf("ParseGroupPayload() err = %q, want containing %q", err.Error(), tc.wantError)
			}
		})
	}
}

func TestGK029ParseGroupPayloadAcceptsPresentEmptyTextWithTimestamp(t *testing.T) {
	parsed, err := ParseGroupPayload(`{"text":"","timestamp":"2026-05-12T20:30:00Z","extra":{"media":[]}}`)
	if err != nil {
		t.Fatalf("ParseGroupPayload() error: %v", err)
	}
	if parsed.Text != "" {
		t.Fatalf("Text = %q, want empty", parsed.Text)
	}
	if parsed.Timestamp != "2026-05-12T20:30:00Z" {
		t.Fatalf("Timestamp = %q, want fixture timestamp", parsed.Timestamp)
	}
	if parsed.Extra == nil {
		t.Fatal("Extra is nil after parsing valid empty-text payload")
	}
	if _, ok := parsed.Extra["media"]; !ok {
		t.Fatal("Extra missing media key after parsing valid empty-text payload")
	}
}

func TestMarshalParseGroupPayload_WithExtra(t *testing.T) {
	original := &GroupMessagePayload{
		Text:      "With extras",
		Timestamp: "2026-03-02T12:00:00Z",
		Extra: map[string]interface{}{
			"replyTo":  "msg-123",
			"priority": float64(1),
		},
	}

	data, err := MarshalGroupPayload(original)
	if err != nil {
		t.Fatalf("MarshalGroupPayload() error: %v", err)
	}

	parsed, err := ParseGroupPayload(data)
	if err != nil {
		t.Fatalf("ParseGroupPayload() error: %v", err)
	}

	if parsed.Extra == nil {
		t.Fatal("Extra is nil after round-trip")
	}

	// Verify extra fields are preserved.
	replyTo, ok := parsed.Extra["replyTo"]
	if !ok {
		t.Error("Extra missing 'replyTo' key")
	} else if replyTo != "msg-123" {
		t.Errorf("Extra['replyTo'] = %v, want %q", replyTo, "msg-123")
	}

	priority, ok := parsed.Extra["priority"]
	if !ok {
		t.Error("Extra missing 'priority' key")
	} else {
		// JSON numbers decode as float64.
		if pf, ok := priority.(float64); !ok || pf != 1 {
			t.Errorf("Extra['priority'] = %v, want 1", priority)
		}
	}

	// Verify no unexpected extra fields.
	if len(parsed.Extra) != 2 {
		// Print all extra keys for debugging.
		keys := make([]string, 0, len(parsed.Extra))
		for k := range parsed.Extra {
			keys = append(keys, k)
		}
		t.Errorf("Extra has %d keys %v, want 2", len(parsed.Extra), keys)
	}

	// Also verify it's valid JSON by re-parsing.
	var raw map[string]interface{}
	if err := json.Unmarshal([]byte(data), &raw); err != nil {
		t.Fatalf("MarshalGroupPayload output is not valid JSON: %v", err)
	}
}

func TestGroupMessagePayloadWithMediaExtra(t *testing.T) {
	media := []interface{}{
		map[string]interface{}{
			"id":   "blob-1",
			"mime": "image/jpeg",
			"size": float64(12345),
		},
		map[string]interface{}{
			"id":         "blob-2",
			"mime":       "audio/mp4",
			"durationMs": float64(5000),
		},
	}

	original := &GroupMessagePayload{
		Text:      "Check this out",
		Timestamp: "2026-03-03T10:00:00Z",
		Username:  "alice",
		Extra: map[string]interface{}{
			"media": media,
		},
	}

	data, err := MarshalGroupPayload(original)
	if err != nil {
		t.Fatalf("MarshalGroupPayload() error: %v", err)
	}

	parsed, err := ParseGroupPayload(data)
	if err != nil {
		t.Fatalf("ParseGroupPayload() error: %v", err)
	}

	if parsed.Extra == nil {
		t.Fatal("Extra is nil after round-trip")
	}

	mediaRaw, ok := parsed.Extra["media"]
	if !ok {
		t.Fatal("Extra missing 'media' key")
	}

	mediaList, ok := mediaRaw.([]interface{})
	if !ok {
		t.Fatalf("Extra['media'] is %T, want []interface{}", mediaRaw)
	}

	if len(mediaList) != 2 {
		t.Fatalf("media list has %d items, want 2", len(mediaList))
	}

	first, ok := mediaList[0].(map[string]interface{})
	if !ok {
		t.Fatalf("media[0] is %T, want map[string]interface{}", mediaList[0])
	}
	if first["id"] != "blob-1" {
		t.Errorf("media[0].id = %v, want blob-1", first["id"])
	}
	if first["mime"] != "image/jpeg" {
		t.Errorf("media[0].mime = %v, want image/jpeg", first["mime"])
	}
}

func TestGroupMessagePayloadWithQuotedMessageIdExtra(t *testing.T) {
	original := &GroupMessagePayload{
		Text:      "Reply body",
		Timestamp: "2026-03-11T10:00:00Z",
		Username:  "alice",
		Extra: map[string]interface{}{
			"quotedMessageId": "parent-msg-1",
			"messageId":       "msg-1",
		},
	}

	data, err := MarshalGroupPayload(original)
	if err != nil {
		t.Fatalf("MarshalGroupPayload() error: %v", err)
	}

	parsed, err := ParseGroupPayload(data)
	if err != nil {
		t.Fatalf("ParseGroupPayload() error: %v", err)
	}

	if parsed.Extra == nil {
		t.Fatal("Extra is nil after round-trip")
	}
	if got := parsed.Extra["quotedMessageId"]; got != "parent-msg-1" {
		t.Fatalf("quotedMessageId = %v, want %q", got, "parent-msg-1")
	}
	if got := parsed.Extra["messageId"]; got != "msg-1" {
		t.Fatalf("messageId = %v, want %q", got, "msg-1")
	}
}
