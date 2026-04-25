package main

import (
	"encoding/json"
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
				"fixture-group-1",
				`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"fixture-group-1","ciphertext":"fixture-ciphertext","nonce":"fixture-nonce"}`,
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
