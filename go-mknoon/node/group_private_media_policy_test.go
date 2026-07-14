package node

import (
	"testing"
	"time"
)

func TestGPL12PrivatePolicyUsesExistingEncryptedExtras(t *testing.T) {
	const groupID = "gpl12-private-policy-extras"
	harness := setupLP013TwoNodeGroup(t, groupID)

	privateOpts := map[string]interface{}{
		"media": []map[string]interface{}{
			{"id": "gpl12-blob", "mime": "image/png", "size": 42},
		},
		"mediaPolicyVersion":   1,
		"mediaLifecycle":       "viewOnce",
		"mediaDurationSeconds": nil,
		"mediaProtected":       true,
	}
	baseline := len(harness.nodeBCapture.snapshot())
	messageID, peerCount, err := harness.nodeA.PublishGroupMessage(
		groupID,
		harness.privB64,
		harness.nodeA.PeerId(),
		harness.pubB64,
		"Alice",
		"",
		"gpl12-private",
		privateOpts,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage private policy: %v", err)
	}
	if messageID != "gpl12-private" {
		t.Fatalf("messageID = %q, want gpl12-private", messageID)
	}
	if peerCount < 1 {
		t.Fatalf("topic peer count = %d, want at least one", peerCount)
	}

	event := waitForCollectedEventAfter(
		t,
		harness.nodeBCapture,
		baseline,
		"group_message:received",
		5*time.Second,
	)
	if got := event["mediaPolicyVersion"]; got != float64(1) {
		t.Fatalf("mediaPolicyVersion = %#v, want numeric 1", got)
	}
	if got := event["mediaLifecycle"]; got != "viewOnce" {
		t.Fatalf("mediaLifecycle = %#v, want viewOnce", got)
	}
	if got, present := event["mediaDurationSeconds"]; !present || got != nil {
		t.Fatalf("mediaDurationSeconds = %#v present=%v, want explicit null", got, present)
	}
	if got := event["mediaProtected"]; got != true {
		t.Fatalf("mediaProtected = %#v, want true", got)
	}
	if _, present := privateOpts["publishedAtNano"]; present {
		t.Fatal("PublishGroupMessage mutated caller extras")
	}

	legacyBaseline := len(harness.nodeBCapture.snapshot())
	_, _, err = harness.nodeA.PublishGroupMessage(
		groupID,
		harness.privB64,
		harness.nodeA.PeerId(),
		harness.pubB64,
		"Alice",
		"",
		"gpl12-legacy",
		map[string]interface{}{
			"media": []map[string]interface{}{
				{"id": "gpl12-legacy-blob", "mime": "image/png", "size": 42},
			},
		},
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage legacy control: %v", err)
	}
	legacyEvent := waitForCollectedEventAfter(
		t,
		harness.nodeBCapture,
		legacyBaseline,
		"group_message:received",
		5*time.Second,
	)
	for _, key := range []string{
		"mediaPolicyVersion",
		"mediaLifecycle",
		"mediaDurationSeconds",
		"mediaProtected",
	} {
		if value, present := legacyEvent[key]; present {
			t.Fatalf("legacy event unexpectedly contains %s=%#v", key, value)
		}
	}
}
