package node

import (
	"encoding/json"
	"errors"
	"strconv"
	"testing"
	"time"
)

const (
	nodeCallHandle  = "00112233445566778899aabbccddeeff"
	nodeCallMessage = "10112233445566778899aabbccddeeff"
	nodeCallWake    = "20112233445566778899aabbccddeeff"
)

func TestVC202CallMailboxNodeUsesDedicatedVersionedActions(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	relay, requests := startTurnCredentialsRelayFixture(t, `{
		"status":"OK","schema":"mknoon.call_mailbox.v1","version":1,
		"storeStatus":"stored","receiptAtMs":`+formatCallTestInt(now.UnixMilli())+`,
		"expiresAtMs":`+formatCallTestInt(now.Add(30*time.Second).UnixMilli())+`,
		"eventCount":1,"totalBytes":23,"pendingHandles":1
	}`)
	n := turnCredentialsNode(t, relay)
	recipient := relay.ID().String()
	request := CallStoreRequest{
		RecipientDevicePeerID: recipient,
		CallHandle:            nodeCallHandle,
		MessageID:             nodeCallMessage,
		Envelope:              "encrypted-node-envelope",
		ExpiresAtMs:           now.Add(30 * time.Second).UnixMilli(),
		WakeHandle:            nodeCallWake,
	}
	receipt, err := n.CallStoreV1(request)
	if err != nil {
		t.Fatal("CallStoreV1 returned an error")
	}
	if receipt.StoreStatus != "stored" || receipt.ReceiptAtMs != now.UnixMilli() ||
		receipt.ExpiresAtMs != request.ExpiresAtMs {
		t.Fatalf("CallStoreV1 receipt = %#v", receipt)
	}

	select {
	case raw := <-requests:
		var got map[string]any
		if json.Unmarshal([]byte(raw), &got) != nil || got["action"] != "call_store_v1" ||
			got["to"] != recipient || got["callHandle"] != nodeCallHandle ||
			got["messageId"] != nodeCallMessage || got["envelope"] != request.Envelope ||
			got["wakeHandle"] != nodeCallWake {
			t.Fatalf("unexpected call store request: %s", raw)
		}
		for _, forbidden := range []string{"from", "senderPeerId", "accountPeerId", "token"} {
			if _, present := got[forbidden]; present {
				t.Fatalf("call store claimed or exposed %s", forbidden)
			}
		}
	case <-time.After(2 * time.Second):
		t.Fatal("relay did not receive call_store_v1")
	}
}

func TestVC202CallEndpointWakeAndTokenNodeActionsStayTyped(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	tests := []struct {
		name       string
		response   string
		invoke     func(*Node) error
		wantAction string
	}{
		{
			name: "endpoint set", response: `{"status":"OK"}`, wantAction: "call_endpoint_set_v1",
			invoke: func(n *Node) error {
				return n.CallEndpointSetV1(CallEndpointRecord{
					AccountPeerID: n.peerId, DevicePeerID: n.peerId,
					Capabilities: []string{"voice_call_v1"}, Platform: "android",
					ExpiresAtMs: now.Add(time.Hour).UnixMilli(), PreferenceEpoch: 1,
					DeviceKeyEpoch: 1, RoutingHandle: nodeCallHandle, Signature: "c2lnbmVkLWZpeHR1cmU=",
				})
			},
		},
		{
			name: "wake set", response: `{"status":"OK"}`, wantAction: "call_wake_handle_set_v1",
			invoke: func(n *Node) error {
				return n.CallWakeHandleSetV1(CallWakeHandleRecord{
					AuthorizedSenderPeerID: n.peerId, WakeHandle: nodeCallWake,
					ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
				})
			},
		},
		{
			name: "standard call token", response: `{"status":"OK"}`, wantAction: "call_token_set_v1",
			invoke: func(n *Node) error {
				_, err := n.CallTokenSetV1(CallTokenRecord{
					Kind: CallTokenKindStandard, Platform: "android", Token: "standard-call-token",
					ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
				})
				return err
			},
		},
		{
			name: "ios voip token", response: `{"status":"OK","refreshEpoch":7,"generation":11}`, wantAction: "call_token_set_v1",
			invoke: func(n *Node) error {
				_, err := n.CallTokenSetV1(CallTokenRecord{
					Kind: CallTokenKindIOSVoIP, Platform: "ios", Token: "ios-voip-token",
					ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
					Environment: "sandbox", Topic: "com.mknoon.test.voip",
					CapabilityVersion: CallIOSVoIPCapabilityVersion, RefreshEpoch: 7,
				})
				return err
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			relay, requests := startTurnCredentialsRelayFixture(t, tc.response)
			n := turnCredentialsNode(t, relay)
			if err := tc.invoke(n); err != nil {
				t.Fatal("typed call action returned an error")
			}
			select {
			case raw := <-requests:
				var got map[string]any
				if json.Unmarshal([]byte(raw), &got) != nil || got["action"] != tc.wantAction {
					t.Fatalf("request = %s, want action %s", raw, tc.wantAction)
				}
				if _, claimed := got["from"]; claimed {
					t.Fatal("call control action claimed authenticated identity")
				}
			case <-time.After(2 * time.Second):
				t.Fatal("relay did not receive call action")
			}
		})
	}
}

func TestVC202CallNodeRejectsMalformedOrIdentityBearingRelayResponses(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	responses := []string{
		`{"status":"OK","schema":"mknoon.call_mailbox.v1","version":1,"storeStatus":"stored","receiptAtMs":1,"expiresAtMs":2,"eventCount":1,"totalBytes":1,"pendingHandles":1,"token":"must-not-be-here"}`,
		`{"status":"OK","schema":"wrong","version":1,"storeStatus":"stored","receiptAtMs":1,"expiresAtMs":2,"eventCount":1,"totalBytes":1,"pendingHandles":1}`,
	}
	for _, response := range responses {
		relay, _ := startTurnCredentialsRelayFixture(t, response)
		n := turnCredentialsNode(t, relay)
		_, err := n.CallStoreV1(CallStoreRequest{
			RecipientDevicePeerID: relay.ID().String(), CallHandle: nodeCallHandle,
			MessageID: nodeCallMessage, Envelope: "e", ExpiresAtMs: now.Add(time.Second).UnixMilli(),
			WakeHandle: nodeCallWake,
		})
		if err == nil {
			t.Fatal("invalid relay response was accepted")
		}
	}
}

func TestVC202CallNodeRetrieveAckCancelAndAuthorityRevocationsUseExactActions(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	tests := []struct {
		name       string
		response   string
		invoke     func(*Node, string) error
		wantAction string
		wantFields map[string]any
	}{
		{
			name: "retrieve", response: `{"status":"OK","schema":"mknoon.call_mailbox.v1","version":1,"receiptAtMs":` + formatCallTestInt(now.UnixMilli()) + `,"events":[]}`,
			wantAction: "call_retrieve_v1", wantFields: map[string]any{"callHandle": nodeCallHandle, "limit": float64(64)},
			invoke: func(n *Node, _ string) error {
				_, err := n.CallRetrieveV1(CallRetrieveRequest{CallHandle: nodeCallHandle, Limit: 64})
				return err
			},
		},
		{
			name: "ack", response: `{"status":"OK","acked":1}`,
			wantAction: "call_ack_v1", wantFields: map[string]any{"callHandle": nodeCallHandle},
			invoke: func(n *Node, _ string) error {
				_, err := n.CallAckV1(CallAckRequest{CallHandle: nodeCallHandle, MessageIDs: []string{nodeCallMessage}})
				return err
			},
		},
		{
			name: "cancel", response: `{"status":"OK","canceled":true}`,
			wantAction: "call_cancel_v1", wantFields: map[string]any{"callHandle": nodeCallHandle},
			invoke: func(n *Node, relayID string) error {
				return n.CallCancelV1(CallCancelRequest{RecipientDevicePeerID: relayID, CallHandle: nodeCallHandle})
			},
		},
		{
			name: "endpoint get missing", response: `{"status":"OK","found":false}`,
			wantAction: "call_endpoint_get_v1", wantFields: map[string]any{},
			invoke: func(n *Node, relayID string) error {
				result, err := n.CallEndpointGetV1(relayID)
				if err == nil && result.Found {
					return errors.New("missing endpoint returned found")
				}
				return err
			},
		},
		{
			name: "endpoint revoke", response: `{"status":"OK","revoked":true}`,
			wantAction: "call_endpoint_revoke_v1", wantFields: map[string]any{"preferenceEpoch": float64(7)},
			invoke: func(n *Node, relayID string) error { return n.CallEndpointRevokeV1(relayID, 7) },
		},
		{
			name: "wake revoke", response: `{"status":"OK","revoked":true}`,
			wantAction: "call_wake_handle_revoke_v1", wantFields: map[string]any{},
			invoke: func(n *Node, relayID string) error { return n.CallWakeHandleRevokeV1(relayID) },
		},
		{
			name: "token revoke", response: `{"status":"OK","revoked":true}`,
			wantAction: "call_token_revoke_v1", wantFields: map[string]any{
				"tokenKind": CallTokenKindIOSVoIP, "expectedRefreshEpoch": float64(7),
			},
			invoke: func(n *Node, _ string) error {
				_, err := n.CallTokenRevokeV1(CallTokenKindIOSVoIP, 7)
				return err
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			relay, requests := startTurnCredentialsRelayFixture(t, tc.response)
			n := turnCredentialsNode(t, relay)
			if err := tc.invoke(n, relay.ID().String()); err != nil {
				t.Fatalf("action returned error: %v", err)
			}
			select {
			case raw := <-requests:
				var request map[string]any
				if json.Unmarshal([]byte(raw), &request) != nil || request["action"] != tc.wantAction {
					t.Fatalf("request = %s, want action %s", raw, tc.wantAction)
				}
				for key, want := range tc.wantFields {
					if request[key] != want {
						t.Fatalf("request[%s] = %#v, want %#v", key, request[key], want)
					}
				}
				if _, claimed := request["from"]; claimed {
					t.Fatal("call action claimed authenticated identity")
				}
			case <-time.After(2 * time.Second):
				t.Fatal("relay did not receive action")
			}
		})
	}
}

func TestVC202CallNodeRejectsActionIrrelevantAndDuplicateResponseFields(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	responses := []string{
		`{"status":"OK","schema":"mknoon.call_mailbox.v1","version":1,"storeStatus":"stored","receiptAtMs":` + formatCallTestInt(now.UnixMilli()) + `,"expiresAtMs":` + formatCallTestInt(now.Add(time.Second).UnixMilli()) + `,"eventCount":1,"totalBytes":1,"pendingHandles":1,"revoked":true}`,
		`{"status":"OK","status":"OK","schema":"mknoon.call_mailbox.v1","version":1,"storeStatus":"stored","receiptAtMs":1,"expiresAtMs":2,"eventCount":1,"totalBytes":1,"pendingHandles":1}`,
	}
	for _, response := range responses {
		relay, _ := startTurnCredentialsRelayFixture(t, response)
		n := turnCredentialsNode(t, relay)
		_, err := n.CallStoreV1(CallStoreRequest{
			RecipientDevicePeerID: relay.ID().String(), CallHandle: nodeCallHandle,
			MessageID: nodeCallMessage, Envelope: "e", ExpiresAtMs: now.Add(time.Second).UnixMilli(),
			WakeHandle: nodeCallWake,
		})
		if !errors.Is(err, ErrCallControlInvalidResponse) {
			t.Fatalf("strict response error = %v", err)
		}
	}
}

func TestVC205CallTokenNodeCarriesGenerationSafeIOSContractAndPreservesStandard(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	standardRelay, standardRequests := startTurnCredentialsRelayFixture(t, `{"status":"OK"}`)
	standardNode := turnCredentialsNode(t, standardRelay)
	standardResult, err := standardNode.CallTokenSetV1(CallTokenRecord{
		Kind: CallTokenKindStandard, Platform: "android", Token: "standard-call-token",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
	})
	if err != nil || standardResult != (CallTokenSetResult{}) {
		t.Fatalf("standard token result = (%#v, %v)", standardResult, err)
	}
	select {
	case raw := <-standardRequests:
		var request map[string]any
		if json.Unmarshal([]byte(raw), &request) != nil || len(request) != 5 ||
			request["action"] != callTokenSetAction || request["tokenKind"] != CallTokenKindStandard ||
			request["platform"] != "android" || request["token"] != "standard-call-token" {
			t.Fatalf("standard token wire shape = %s", raw)
		}
		for _, forbidden := range []string{"environment", "topic", "capabilityVersion", "refreshEpoch", "generation"} {
			if _, present := request[forbidden]; present {
				t.Fatalf("standard token wire gained %q: %s", forbidden, raw)
			}
		}
	case <-time.After(2 * time.Second):
		t.Fatal("relay did not receive standard token set")
	}

	iosRelay, iosRequests := startTurnCredentialsRelayFixture(t,
		`{"status":"OK","refreshEpoch":41,"generation":7}`,
	)
	iosNode := turnCredentialsNode(t, iosRelay)
	iosRecord := CallTokenRecord{
		Kind: CallTokenKindIOSVoIP, Platform: "ios", Token: "pushkit-token",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(), Environment: "production",
		Topic: "com.mknoon.test.voip", CapabilityVersion: CallIOSVoIPCapabilityVersion,
		RefreshEpoch: 41,
	}
	iosResult, err := iosNode.CallTokenSetV1(iosRecord)
	if err != nil || iosResult.RefreshEpoch != 41 || iosResult.Generation != 7 {
		t.Fatalf("iOS token result = (%#v, %v)", iosResult, err)
	}
	select {
	case raw := <-iosRequests:
		var request map[string]any
		if json.Unmarshal([]byte(raw), &request) != nil || len(request) != 9 ||
			request["action"] != callTokenSetAction || request["tokenKind"] != CallTokenKindIOSVoIP ||
			request["environment"] != "production" || request["topic"] != "com.mknoon.test.voip" ||
			request["capabilityVersion"] != float64(CallIOSVoIPCapabilityVersion) ||
			request["refreshEpoch"] != float64(41) {
			t.Fatalf("iOS token wire shape = %s", raw)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("relay did not receive iOS token set")
	}

	standardRevokeRelay, standardRevokeRequests := startTurnCredentialsRelayFixture(t,
		`{"status":"OK","revoked":true}`,
	)
	standardRevokeNode := turnCredentialsNode(t, standardRevokeRelay)
	if revoked, err := standardRevokeNode.CallTokenRevokeV1(CallTokenKindStandard, 0); err != nil || !revoked {
		t.Fatalf("standard revoke = (%v, %v)", revoked, err)
	}
	select {
	case raw := <-standardRevokeRequests:
		var request map[string]any
		if json.Unmarshal([]byte(raw), &request) != nil || len(request) != 2 ||
			request["action"] != callTokenRevokeAction || request["tokenKind"] != CallTokenKindStandard {
			t.Fatalf("standard revoke wire shape = %s", raw)
		}
		if _, present := request["expectedRefreshEpoch"]; present {
			t.Fatalf("standard revoke gained CAS field: %s", raw)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("relay did not receive standard token revoke")
	}

	iosRevokeRelay, iosRevokeRequests := startTurnCredentialsRelayFixture(t,
		`{"status":"OK","revoked":false}`,
	)
	iosRevokeNode := turnCredentialsNode(t, iosRevokeRelay)
	if revoked, err := iosRevokeNode.CallTokenRevokeV1(CallTokenKindIOSVoIP, 41); err != nil || revoked {
		t.Fatalf("stale iOS revoke = (%v, %v)", revoked, err)
	}
	select {
	case raw := <-iosRevokeRequests:
		var request map[string]any
		if json.Unmarshal([]byte(raw), &request) != nil || len(request) != 3 ||
			request["action"] != callTokenRevokeAction || request["tokenKind"] != CallTokenKindIOSVoIP ||
			request["expectedRefreshEpoch"] != float64(41) {
			t.Fatalf("iOS revoke wire shape = %s", raw)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("relay did not receive iOS token revoke")
	}
}

func TestVC205CallTokenNodeRejectsMetadataAndResponseFailures(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	validIOS := CallTokenRecord{
		Kind: CallTokenKindIOSVoIP, Platform: "ios", Token: "pushkit-token",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(), Environment: "sandbox",
		Topic: "com.mknoon.test.voip", CapabilityVersion: CallIOSVoIPCapabilityVersion,
		RefreshEpoch: 9,
	}
	for name, mutate := range map[string]func(*CallTokenRecord){
		"missing environment":   func(record *CallTokenRecord) { record.Environment = "" },
		"native development":    func(record *CallTokenRecord) { record.Environment = "development" },
		"missing topic":         func(record *CallTokenRecord) { record.Topic = "" },
		"ordinary topic":        func(record *CallTokenRecord) { record.Topic = "com.mknoon.test" },
		"missing capability":    func(record *CallTokenRecord) { record.CapabilityVersion = 0 },
		"missing refresh epoch": func(record *CallTokenRecord) { record.RefreshEpoch = 0 },
	} {
		t.Run(name, func(t *testing.T) {
			record := validIOS
			mutate(&record)
			if _, err := new(Node).CallTokenSetV1(record); !errors.Is(err, ErrCallControlInvalidRequest) {
				t.Fatalf("invalid iOS metadata error = %v", err)
			}
		})
	}
	standardWithMetadata := CallTokenRecord{
		Kind: CallTokenKindStandard, Platform: "android", Token: "standard-token",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(), RefreshEpoch: 1,
	}
	if _, err := new(Node).CallTokenSetV1(standardWithMetadata); !errors.Is(err, ErrCallControlInvalidRequest) {
		t.Fatalf("standard token accepted iOS metadata: %v", err)
	}
	if _, err := new(Node).CallTokenRevokeV1(CallTokenKindIOSVoIP, 0); !errors.Is(err, ErrCallControlInvalidRequest) {
		t.Fatalf("iOS revoke accepted missing CAS epoch: %v", err)
	}
	if _, err := new(Node).CallTokenRevokeV1(CallTokenKindStandard, 1); !errors.Is(err, ErrCallControlInvalidRequest) {
		t.Fatalf("standard revoke accepted iOS CAS epoch: %v", err)
	}

	for name, response := range map[string]string{
		"missing set result": `{"status":"OK"}`,
		"zero generation":    `{"status":"OK","refreshEpoch":9}`,
		"wrong echoed epoch": `{"status":"OK","refreshEpoch":8,"generation":1}`,
	} {
		t.Run(name, func(t *testing.T) {
			relay, _ := startTurnCredentialsRelayFixture(t, response)
			n := turnCredentialsNode(t, relay)
			if _, err := n.CallTokenSetV1(validIOS); !errors.Is(err, ErrCallControlInvalidResponse) {
				t.Fatalf("invalid set response error = %v", err)
			}
		})
	}
	standardRelay, _ := startTurnCredentialsRelayFixture(t,
		`{"status":"OK","refreshEpoch":1,"generation":1}`,
	)
	if _, err := turnCredentialsNode(t, standardRelay).CallTokenSetV1(CallTokenRecord{
		Kind: CallTokenKindStandard, Platform: "android", Token: "standard-token",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
	}); !errors.Is(err, ErrCallControlInvalidResponse) {
		t.Fatalf("standard set accepted iOS response metadata: %v", err)
	}
	for name, test := range map[string]struct {
		kind     string
		epoch    uint64
		response string
	}{
		"missing revoked": {kind: CallTokenKindIOSVoIP, epoch: 9, response: `{"status":"OK"}`},
		"standard false":  {kind: CallTokenKindStandard, response: `{"status":"OK","revoked":false}`},
	} {
		t.Run(name, func(t *testing.T) {
			relay, _ := startTurnCredentialsRelayFixture(t, test.response)
			n := turnCredentialsNode(t, relay)
			if _, err := n.CallTokenRevokeV1(test.kind, test.epoch); !errors.Is(err, ErrCallControlInvalidResponse) {
				t.Fatalf("invalid revoke response error = %v", err)
			}
		})
	}
}

func formatCallTestInt(value int64) string {
	return strconv.FormatInt(value, 10)
}
