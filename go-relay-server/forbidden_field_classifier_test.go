package main

import (
	"encoding/json"
	"os"
	"reflect"
	"strings"
	"testing"

	"firebase.google.com/go/v4/messaging"
)

func TestForbiddenFieldClassifier_MessagePushesDoNotExposePreviewCanaries(t *testing.T) {
	canaries := []string{
		"Alice",
		"Team Chat",
		"Hello secret",
		"Alice: hello",
		"Photo",
		"Voice message",
		"Video",
		"File",
		"Media",
		"GIF",
		"👍",
		"Original target text",
	}

	cases := []struct {
		name string
		msg  *messagingMessageForScan
	}{
		{
			name: "chat",
			msg: scanPushMessage(buildPushMessage(
				"fcm-token",
				"peer-alice",
				`{"type":"chat_message","version":"2","id":"fixture-chat-1","senderPeerId":"peer-alice","senderUsername":"Alice","encrypted":{"kem":"fixture-kem","ciphertext":"fixture-ciphertext","nonce":"fixture-nonce"}}`,
			)),
		},
		{
			name: "group",
			msg: scanPushMessage(buildGroupPushMessage(
				"fcm-token",
				"group-team",
				"peer-alice-transport",
				"fixture-group-1",
				`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"fixture-group-1","ciphertext":"fixture-ciphertext","nonce":"fixture-nonce"}`,
			)),
		},
		{
			name: "direct reaction",
			msg: scanPushMessage(buildReactionPushMessage(
				"fcm-token",
				"peer-alice",
				`{"type":"message_reaction","version":"2","senderPeerId":"peer-alice","eventId":"reaction-privacy-1","action":"add","targetMessageId":"target-privacy-1","encrypted":{"kem":"fixture-kem","ciphertext":"fixture-ciphertext","nonce":"fixture-nonce"}}`,
			)),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			encoded, err := json.Marshal(tc.msg)
			if err != nil {
				t.Fatalf("marshal push surface: %v", err)
			}
			surface := string(encoded)
			for _, canary := range canaries {
				if strings.Contains(surface, canary) {
					t.Fatalf("push surface leaked forbidden canary %q: %s", canary, surface)
				}
			}
		})
	}
}

func TestForbiddenFieldClassifier_CommittedReactionFixtureMatchesRelayPush(t *testing.T) {
	raw, err := os.ReadFile("../test_fixtures/one_to_one_reaction_add.json")
	if err != nil {
		t.Fatalf("read shared reaction fixture: %v", err)
	}
	var fixture struct {
		RouteData         map[string]string      `json:"routeData"`
		EncryptedEnvelope map[string]interface{} `json:"encryptedEnvelope"`
		Plaintext         map[string]interface{} `json:"plaintext"`
	}
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatalf("decode shared reaction fixture: %v", err)
	}
	envelope, err := json.Marshal(fixture.EncryptedEnvelope)
	if err != nil {
		t.Fatalf("encode fixture envelope: %v", err)
	}
	msg := buildReactionPushMessage(
		"fixture-token",
		fixture.RouteData["sender_id"],
		string(envelope),
	)
	if msg == nil {
		t.Fatal("fixture did not produce an eligible reaction push")
	}
	if !reflect.DeepEqual(msg.Data, fixture.RouteData) {
		t.Fatalf("relay data diverged from shared fixture\n got: %#v\nwant: %#v", msg.Data, fixture.RouteData)
	}

	encoded, err := json.Marshal(scanPushMessage(msg))
	if err != nil {
		t.Fatalf("marshal reaction push surface: %v", err)
	}
	surface := string(encoded)
	for _, field := range []string{"emoji", "actorUsername", "targetText"} {
		value, _ := fixture.Plaintext[field].(string)
		if value != "" && strings.Contains(surface, value) {
			t.Fatalf("reaction push surface leaked plaintext %s %q: %s", field, value, surface)
		}
	}
}

type messagingMessageForScan struct {
	Notification interface{}       `json:"notification,omitempty"`
	Data         map[string]string `json:"data,omitempty"`
	Android      interface{}       `json:"android,omitempty"`
	APNS         interface{}       `json:"apns,omitempty"`
}

func scanPushMessage(msg *messaging.Message) *messagingMessageForScan {
	raw, _ := json.Marshal(msg)
	var out messagingMessageForScan
	_ = json.Unmarshal(raw, &out)
	return &out
}
