package node

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestGroupReactionReplaySignedRecipientSetPreservedInStoreRequest(t *testing.T) {
	replayRecipients := []string{
		"author-device-1",
		"author-device-2",
		"bystander-device",
	}
	envelopeBytes, err := json.Marshal(map[string]interface{}{
		"kind":             "group_offline_replay",
		"version":          1,
		"groupId":          "group-reaction-node",
		"payloadType":      "group_reaction",
		"recipientPeerIds": replayRecipients,
		"notificationExtension": map[string]interface{}{
			"version":                               1,
			"replayRecipientSetHash":                "signed-replay-set-hash",
			"notificationRecipientTransportPeerIds": []string{"author-device-1", "author-device-2"},
		},
	})
	if err != nil {
		t.Fatalf("encode group reaction envelope: %v", err)
	}

	request := buildGroupInboxStoreRequest(
		"group-reaction-node",
		"reactor-transport",
		string(envelopeBytes),
		replayRecipients,
		"",
		"",
	)
	if request.Message != string(envelopeBytes) {
		t.Fatal("group reaction envelope changed before relay store")
	}
	if !reflect.DeepEqual(request.RecipientPeerIds, replayRecipients) {
		t.Fatalf("store recipients = %#v, want exact signed set %#v", request.RecipientPeerIds, replayRecipients)
	}
}

func TestGroupReactionTwoAuthorDevicesRemainDistinctFromReplayBystander(t *testing.T) {
	replayRecipients := []string{
		"author-device-1",
		"author-device-2",
		"bystander-device",
	}
	request := buildGroupInboxStoreRequest(
		"group-reaction-two-author-devices",
		"reactor-transport",
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_reaction"}`,
		replayRecipients,
		"",
		"",
	)
	if len(request.RecipientPeerIds) != 3 {
		t.Fatalf("replay recipient count = %d, want both author devices plus bystander", len(request.RecipientPeerIds))
	}
	if request.RecipientPeerIds[0] != "author-device-1" ||
		request.RecipientPeerIds[1] != "author-device-2" ||
		request.RecipientPeerIds[2] != "bystander-device" {
		t.Fatalf("transport recipients collapsed or reordered: %#v", request.RecipientPeerIds)
	}
}
