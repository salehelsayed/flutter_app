package bridge

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/mknoon/go-mknoon/node"
)

func TestVC202CallMailboxBridgeExportsAllTypedActions(t *testing.T) {
	withSingletonNode(t)
	previousStore := callStoreV1Invoke
	previousRetrieve := callRetrieveV1Invoke
	previousAck := callAckV1Invoke
	previousCancel := callCancelV1Invoke
	t.Cleanup(func() {
		callStoreV1Invoke = previousStore
		callRetrieveV1Invoke = previousRetrieve
		callAckV1Invoke = previousAck
		callCancelV1Invoke = previousCancel
	})

	callStoreV1Invoke = func(_ *node.Node, request node.CallStoreRequest) (node.CallStoreReceipt, error) {
		if request.RecipientDevicePeerID != "recipient-fixture" || request.CallHandle != nodeCallBridgeHandle ||
			request.MessageID != nodeCallBridgeMessage || request.Envelope != "encrypted-bridge-envelope" ||
			request.WakeHandle != nodeCallBridgeWake || request.ExpiresAtMs != 1_900_000_045_000 {
			t.Fatal("CallStoreV1 bridge changed request fields")
		}
		return node.CallStoreReceipt{
			Schema: node.CallMailboxSchema, Version: 1, StoreStatus: "stored",
			ReceiptAtMs: 1_900_000_000_000, ExpiresAtMs: 1_900_000_045_000,
			EventCount: 1, TotalBytes: 27, PendingHandles: 1, Wake: "dispatched",
		}, nil
	}
	stored := parseJSON(t, CallStoreV1(`{
		"toPeerId":"recipient-fixture","callHandle":"`+nodeCallBridgeHandle+`",
		"messageId":"`+nodeCallBridgeMessage+`","envelope":"encrypted-bridge-envelope",
		"expiresAtMs":1900000045000,"wakeHandle":"`+nodeCallBridgeWake+`"
	}`))
	if stored["ok"] != true || stored["storeStatus"] != "stored" ||
		stored["receiptAtMs"] != float64(1_900_000_000_000) || stored["wake"] != "dispatched" {
		t.Fatalf("CallStoreV1 response = %#v", stored)
	}

	callRetrieveV1Invoke = func(_ *node.Node, request node.CallRetrieveRequest) (node.CallRetrieveResult, error) {
		if request.CallHandle != nodeCallBridgeHandle || request.Limit != 64 {
			t.Fatal("CallRetrieveV1 bridge changed request fields")
		}
		return node.CallRetrieveResult{
			Schema: node.CallMailboxSchema, Version: 1, ReceiptAtMs: 1_900_000_000_000,
			ExpiresAtMs: 1_900_000_045_000,
			Events: []node.CallMailboxEvent{{
				CallHandle: nodeCallBridgeHandle, MessageID: nodeCallBridgeMessage,
				SenderPeerID: "sender-fixture", RecipientDevicePeerID: "recipient-fixture",
				Envelope: "encrypted-bridge-envelope", ReceiptAtMs: 1_900_000_000_000,
				ExpiresAtMs: 1_900_000_045_000,
			}},
		}, nil
	}
	retrieved := parseJSON(t, CallRetrieveV1(`{"callHandle":"`+nodeCallBridgeHandle+`","limit":64}`))
	if retrieved["ok"] != true || len(retrieved["events"].([]any)) != 1 {
		t.Fatalf("CallRetrieveV1 response = %#v", retrieved)
	}

	callAckV1Invoke = func(_ *node.Node, request node.CallAckRequest) (int, error) {
		if request.CallHandle != nodeCallBridgeHandle || len(request.MessageIDs) != 1 ||
			request.MessageIDs[0] != nodeCallBridgeMessage {
			t.Fatal("CallAckV1 bridge changed request fields")
		}
		return 1, nil
	}
	acked := parseJSON(t, CallAckV1(`{"callHandle":"`+nodeCallBridgeHandle+`","messageIds":["`+nodeCallBridgeMessage+`"]}`))
	if acked["ok"] != true || acked["acked"] != float64(1) {
		t.Fatalf("CallAckV1 response = %#v", acked)
	}

	callCancelV1Invoke = func(_ *node.Node, request node.CallCancelRequest) error {
		if request.RecipientDevicePeerID != "recipient-fixture" || request.CallHandle != nodeCallBridgeHandle {
			t.Fatal("CallCancelV1 bridge changed request fields")
		}
		return nil
	}
	canceled := parseJSON(t, CallCancelV1(`{"toPeerId":"recipient-fixture","callHandle":"`+nodeCallBridgeHandle+`"}`))
	if canceled["ok"] != true || canceled["canceled"] != true {
		t.Fatalf("CallCancelV1 response = %#v", canceled)
	}
}

func TestVC202CallAuthorityBridgeExportsEndpointWakeAndSeparatedTokens(t *testing.T) {
	withSingletonNode(t)
	previousEndpointSet := callEndpointSetV1Invoke
	previousEndpointGet := callEndpointGetV1Invoke
	previousEndpointRevoke := callEndpointRevokeV1Invoke
	previousWakeSet := callWakeHandleSetV1Invoke
	previousWakeRevoke := callWakeHandleRevokeV1Invoke
	previousTokenSet := callTokenSetV1Invoke
	previousTokenRevoke := callTokenRevokeV1Invoke
	t.Cleanup(func() {
		callEndpointSetV1Invoke = previousEndpointSet
		callEndpointGetV1Invoke = previousEndpointGet
		callEndpointRevokeV1Invoke = previousEndpointRevoke
		callWakeHandleSetV1Invoke = previousWakeSet
		callWakeHandleRevokeV1Invoke = previousWakeRevoke
		callTokenSetV1Invoke = previousTokenSet
		callTokenRevokeV1Invoke = previousTokenRevoke
	})

	signature := base64.StdEncoding.EncodeToString([]byte("endpoint-signature-fixture"))
	canonical := []byte(`{"schema":"mknoon.call_endpoint_set.v1"}`)
	endpoint := node.CallEndpointRecord{
		Schema: node.CallEndpointSchema, Version: 1,
		AccountPeerID: "account-fixture", DevicePeerID: "device-fixture",
		Capabilities: []string{"voice_call_v1"}, Platform: "ios",
		ExpiresAtMs: 1_900_003_600_000, PreferenceEpoch: 7, DeviceKeyEpoch: 11,
		RoutingHandle: nodeCallBridgeHandle, Signature: signature,
	}
	callEndpointSetV1Invoke = func(_ *node.Node, got node.CallEndpointRecord) error {
		if got.Signature != signature || got.PreferenceEpoch != 7 || got.DeviceKeyEpoch != 11 {
			t.Fatal("CallEndpointSetV1 bridge changed signed record")
		}
		return nil
	}
	set := parseJSON(t, CallEndpointSetV1(mustBridgeJSON(t, endpoint)))
	if set["ok"] != true {
		t.Fatalf("CallEndpointSetV1 response = %#v", set)
	}

	callEndpointGetV1Invoke = func(_ *node.Node, account string) (node.CallEndpointResult, error) {
		if account != "account-fixture" {
			t.Fatal("CallEndpointGetV1 changed account")
		}
		return node.CallEndpointResult{Found: true, Endpoint: &endpoint, CanonicalRecord: canonical}, nil
	}
	got := parseJSON(t, CallEndpointGetV1(`{"accountPeerId":"account-fixture"}`))
	if got["ok"] != true || got["found"] != true ||
		got["canonicalRecord"] != base64.StdEncoding.EncodeToString(canonical) {
		t.Fatalf("CallEndpointGetV1 response = %#v", got)
	}

	callEndpointRevokeV1Invoke = func(_ *node.Node, account string, epoch uint64) error {
		if account != "account-fixture" || epoch != 8 {
			t.Fatal("CallEndpointRevokeV1 changed authority fields")
		}
		return nil
	}
	if response := parseJSON(t, CallEndpointRevokeV1(`{"accountPeerId":"account-fixture","preferenceEpoch":8}`)); response["ok"] != true || response["revoked"] != true {
		t.Fatalf("CallEndpointRevokeV1 response = %#v", response)
	}

	callWakeHandleSetV1Invoke = func(_ *node.Node, record node.CallWakeHandleRecord) error {
		if record.AuthorizedSenderPeerID != "sender-fixture" || record.WakeHandle != nodeCallBridgeWake {
			t.Fatal("CallWakeHandleSetV1 changed opaque authority")
		}
		return nil
	}
	if response := parseJSON(t, CallWakeHandleSetV1(`{"authorizedSenderPeerId":"sender-fixture","wakeHandle":"`+nodeCallBridgeWake+`","expiresAtMs":1900003600000}`)); response["ok"] != true {
		t.Fatalf("CallWakeHandleSetV1 response = %#v", response)
	}
	callWakeHandleRevokeV1Invoke = func(_ *node.Node, sender string) error {
		if sender != "sender-fixture" {
			t.Fatal("CallWakeHandleRevokeV1 changed sender")
		}
		return nil
	}
	if response := parseJSON(t, CallWakeHandleRevokeV1(`{"authorizedSenderPeerId":"sender-fixture"}`)); response["revoked"] != true {
		t.Fatalf("CallWakeHandleRevokeV1 response = %#v", response)
	}

	var records []node.CallTokenRecord
	callTokenSetV1Invoke = func(_ *node.Node, record node.CallTokenRecord) (node.CallTokenSetResult, error) {
		records = append(records, record)
		if record.Kind == node.CallTokenKindIOSVoIP {
			return node.CallTokenSetResult{RefreshEpoch: record.RefreshEpoch, Generation: 12}, nil
		}
		return node.CallTokenSetResult{}, nil
	}
	standardSet := parseJSON(t, CallTokenSetV1(
		`{"tokenKind":"standard_call","platform":"android","token":"standard-token","expiresAtMs":1900003600000}`,
	))
	if standardSet["ok"] != true || len(standardSet) != 1 {
		t.Fatalf("standard CallTokenSetV1 response = %#v", standardSet)
	}
	iosSet := parseJSON(t, CallTokenSetV1(
		`{"tokenKind":"ios_voip","platform":"ios","token":"voip-token","expiresAtMs":1900003600000,`+
			`"environment":"sandbox","topic":"com.mknoon.test.voip","capabilityVersion":1,"refreshEpoch":9}`,
	))
	if iosSet["ok"] != true || iosSet["refreshEpoch"] != float64(9) || iosSet["generation"] != float64(12) {
		t.Fatalf("iOS CallTokenSetV1 response = %#v", iosSet)
	}
	if len(records) != 2 || records[0].Kind != node.CallTokenKindStandard ||
		records[0].Environment != "" || records[0].RefreshEpoch != 0 ||
		records[1].Kind != node.CallTokenKindIOSVoIP || records[1].Environment != "sandbox" ||
		records[1].Topic != "com.mknoon.test.voip" || records[1].CapabilityVersion != 1 ||
		records[1].RefreshEpoch != 9 {
		t.Fatalf("token authority fields changed: %#v", records)
	}
	callTokenRevokeV1Invoke = func(_ *node.Node, kind string, expectedRefreshEpoch uint64) (bool, error) {
		if kind == node.CallTokenKindStandard {
			if expectedRefreshEpoch != 0 {
				t.Fatal("standard revoke gained an epoch field")
			}
			return true, nil
		}
		if kind != node.CallTokenKindIOSVoIP || expectedRefreshEpoch != 9 {
			t.Fatal("CallTokenRevokeV1 changed iOS CAS fields")
		}
		return false, nil
	}
	if response := parseJSON(t, CallTokenRevokeV1(`{"tokenKind":"standard_call"}`)); response["revoked"] != true {
		t.Fatalf("standard CallTokenRevokeV1 response = %#v", response)
	}
	if response := parseJSON(t, CallTokenRevokeV1(
		`{"tokenKind":"ios_voip","expectedRefreshEpoch":9}`,
	)); response["revoked"] != false {
		t.Fatalf("iOS stale CallTokenRevokeV1 response = %#v", response)
	}
}

func TestVC202CallBridgeFailuresDoNotEchoPayloadIdentityOrToken(t *testing.T) {
	withSingletonNode(t)
	previous := callStoreV1Invoke
	callStoreV1Invoke = func(*node.Node, node.CallStoreRequest) (node.CallStoreReceipt, error) {
		return node.CallStoreReceipt{}, errors.New("synthetic backend failure")
	}
	t.Cleanup(func() { callStoreV1Invoke = previous })
	result := CallStoreV1(`{"toPeerId":"secret-peer","callHandle":"` + nodeCallBridgeHandle + `","messageId":"` + nodeCallBridgeMessage + `","envelope":"secret-envelope","expiresAtMs":1900000045000,"wakeHandle":"` + nodeCallBridgeWake + `"}`)
	for _, forbidden := range []string{"secret-peer", "secret-envelope", nodeCallBridgeWake} {
		if bytes.Contains([]byte(result), []byte(forbidden)) {
			t.Fatal("call bridge failure echoed private input")
		}
	}
}

func TestVC205CallBridgePreservesOnlySafeRelayErrorCodes(t *testing.T) {
	for _, code := range []string{
		"CALL_BACKEND_UNAVAILABLE",
		"CALL_INVALID_REQUEST",
		"CALL_UNAUTHORIZED",
		"CALL_IDENTITY_CONFLICT",
		"CALL_REPLAY",
		"CALL_EXPIRY_INVALID",
		"CALL_ENVELOPE_TOO_LARGE",
		"CALL_RECIPIENT_CAPACITY",
		"CALL_EVENT_CAPACITY",
		"CALL_BYTE_CAPACITY",
		"CALL_RATE_LIMITED",
		"CALL_STALE_EPOCH",
	} {
		t.Run(code, func(t *testing.T) {
			response := parseJSON(t, callBridgeError(&node.CallControlRelayError{Code: code}))
			if response["ok"] != false || response["errorCode"] != code ||
				response["errorMessage"] != "Call control request failed" {
				t.Fatalf("relay bridge error response = %#v", response)
			}
		})
	}

	for _, unsafeCode := range []string{
		"",
		"CALL_CONTROL_UNAVAILABLE",
		"SECRET_recipient-device-secret",
		"CALL_BACKEND_UNAVAILABLE\nsecret-token",
	} {
		t.Run("unsafe", func(t *testing.T) {
			result := callBridgeError(&node.CallControlRelayError{Code: unsafeCode})
			response := parseJSON(t, result)
			if response["errorCode"] != "CALL_CONTROL_UNAVAILABLE" {
				t.Fatalf("unsafe relay code was not collapsed: %#v", response)
			}
			for _, forbidden := range []string{"SECRET_", "secret-token"} {
				if strings.Contains(result, forbidden) {
					t.Fatal("unsafe relay code leaked through bridge response")
				}
			}
		})
	}
}

func TestVC205CallTokenBridgeCarriesIOSCASAndRejectsShapeFailures(t *testing.T) {
	withSingletonNode(t)
	previousSet := callTokenSetV1Invoke
	previousRevoke := callTokenRevokeV1Invoke
	t.Cleanup(func() {
		callTokenSetV1Invoke = previousSet
		callTokenRevokeV1Invoke = previousRevoke
	})

	var captured []node.CallTokenRecord
	invalidSetResult := false
	callTokenSetV1Invoke = func(_ *node.Node, record node.CallTokenRecord) (node.CallTokenSetResult, error) {
		captured = append(captured, record)
		if record.Kind == node.CallTokenKindStandard {
			return node.CallTokenSetResult{}, nil
		}
		if invalidSetResult {
			return node.CallTokenSetResult{RefreshEpoch: record.RefreshEpoch}, nil
		}
		return node.CallTokenSetResult{RefreshEpoch: record.RefreshEpoch, Generation: 17}, nil
	}
	standard := parseJSON(t, CallTokenSetV1(
		`{"tokenKind":"standard_call","platform":"android","token":"standard-token","expiresAtMs":1900003600000}`,
	))
	if standard["ok"] != true || len(standard) != 1 {
		t.Fatalf("standard bridge response changed = %#v", standard)
	}
	ios := parseJSON(t, CallTokenSetV1(
		`{"tokenKind":"ios_voip","platform":"ios","token":"pushkit-token","expiresAtMs":1900003600000,`+
			`"environment":"production","topic":"com.mknoon.test.voip","capabilityVersion":1,"refreshEpoch":33}`,
	))
	if ios["ok"] != true || ios["generation"] != float64(17) || ios["refreshEpoch"] != float64(33) {
		t.Fatalf("iOS bridge response = %#v", ios)
	}
	if len(captured) != 2 || captured[0].Environment != "" || captured[0].RefreshEpoch != 0 ||
		captured[1].Environment != "production" || captured[1].Topic != "com.mknoon.test.voip" ||
		captured[1].CapabilityVersion != node.CallIOSVoIPCapabilityVersion || captured[1].RefreshEpoch != 33 {
		t.Fatalf("bridge set records = %#v", captured)
	}
	setCalls := len(captured)
	for _, invalid := range []string{
		`{"tokenKind":"ios_voip","platform":"ios","token":"pushkit-token","expiresAtMs":1900003600000,"topic":"com.mknoon.test.voip","capabilityVersion":1,"refreshEpoch":33}`,
		`{"tokenKind":"ios_voip","platform":"ios","token":"pushkit-token","expiresAtMs":1900003600000,"environment":"development","topic":"com.mknoon.test.voip","capabilityVersion":1,"refreshEpoch":33}`,
		`{"tokenKind":"standard_call","platform":"android","token":"standard-token","expiresAtMs":1900003600000,"refreshEpoch":1}`,
	} {
		if response := CallTokenSetV1(invalid); !strings.Contains(response, "INVALID_INPUT") {
			t.Fatalf("invalid set shape response = %s", response)
		}
	}
	if len(captured) != setCalls {
		t.Fatalf("invalid set shape reached node: %d -> %d", setCalls, len(captured))
	}
	invalidSetResult = true
	if response := CallTokenSetV1(
		`{"tokenKind":"ios_voip","platform":"ios","token":"pushkit-token","expiresAtMs":1900003600000,` +
			`"environment":"sandbox","topic":"com.mknoon.test.voip","capabilityVersion":1,"refreshEpoch":34}`,
	); !strings.Contains(response, "CALL_CONTROL_INVALID_RESPONSE") {
		t.Fatalf("invalid node set result response = %s", response)
	}

	type revokeCall struct {
		kind  string
		epoch uint64
	}
	var revokes []revokeCall
	callTokenRevokeV1Invoke = func(_ *node.Node, kind string, epoch uint64) (bool, error) {
		revokes = append(revokes, revokeCall{kind: kind, epoch: epoch})
		return kind == node.CallTokenKindStandard, nil
	}
	standardRevoke := parseJSON(t, CallTokenRevokeV1(`{"tokenKind":"standard_call"}`))
	iosRevoke := parseJSON(t, CallTokenRevokeV1(
		`{"tokenKind":"ios_voip","expectedRefreshEpoch":33}`,
	))
	if standardRevoke["revoked"] != true || iosRevoke["revoked"] != false || len(revokes) != 2 ||
		revokes[0] != (revokeCall{kind: node.CallTokenKindStandard}) ||
		revokes[1] != (revokeCall{kind: node.CallTokenKindIOSVoIP, epoch: 33}) {
		t.Fatalf("bridge revoke contract = (%#v, %#v, %#v)", standardRevoke, iosRevoke, revokes)
	}
	revokeCalls := len(revokes)
	for _, invalid := range []string{
		`{"tokenKind":"ios_voip"}`,
		`{"tokenKind":"standard_call","expectedRefreshEpoch":1}`,
		`{"tokenKind":"unknown"}`,
	} {
		if response := CallTokenRevokeV1(invalid); !strings.Contains(response, "INVALID_INPUT") {
			t.Fatalf("invalid revoke shape response = %s", response)
		}
	}
	if len(revokes) != revokeCalls {
		t.Fatalf("invalid revoke shape reached node: %d -> %d", revokeCalls, len(revokes))
	}
}

const (
	nodeCallBridgeHandle  = "00112233445566778899aabbccddeeff"
	nodeCallBridgeMessage = "10112233445566778899aabbccddeeff"
	nodeCallBridgeWake    = "20112233445566778899aabbccddeeff"
)

func mustBridgeJSON(t *testing.T, value any) string {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal("marshal bridge fixture")
	}
	return string(raw)
}
