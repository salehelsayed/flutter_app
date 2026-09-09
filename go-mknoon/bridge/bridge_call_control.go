package bridge

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"strings"

	"github.com/mknoon/go-mknoon/node"
)

var (
	callStoreV1Invoke = func(n *node.Node, request node.CallStoreRequest) (node.CallStoreReceipt, error) {
		return n.CallStoreV1(request)
	}
	callRetrieveV1Invoke = func(n *node.Node, request node.CallRetrieveRequest) (node.CallRetrieveResult, error) {
		return n.CallRetrieveV1(request)
	}
	callAckV1Invoke = func(n *node.Node, request node.CallAckRequest) (int, error) {
		return n.CallAckV1(request)
	}
	callCancelV1Invoke = func(n *node.Node, request node.CallCancelRequest) error {
		return n.CallCancelV1(request)
	}
	callEndpointSetV1Invoke = func(n *node.Node, record node.CallEndpointRecord) error {
		return n.CallEndpointSetV1(record)
	}
	callEndpointGetV1Invoke = func(n *node.Node, accountPeerID string) (node.CallEndpointResult, error) {
		return n.CallEndpointGetV1(accountPeerID)
	}
	callEndpointRevokeV1Invoke = func(n *node.Node, accountPeerID string, preferenceEpoch uint64) error {
		return n.CallEndpointRevokeV1(accountPeerID, preferenceEpoch)
	}
	callWakeHandleSetV1Invoke = func(n *node.Node, record node.CallWakeHandleRecord) error {
		return n.CallWakeHandleSetV1(record)
	}
	callWakeHandleRevokeV1Invoke = func(n *node.Node, senderPeerID string) error {
		return n.CallWakeHandleRevokeV1(senderPeerID)
	}
	callTokenSetV1Invoke = func(n *node.Node, record node.CallTokenRecord) (node.CallTokenSetResult, error) {
		return n.CallTokenSetV1(record)
	}
	callTokenRevokeV1Invoke = func(n *node.Node, kind string, expectedRefreshEpoch uint64) (bool, error) {
		return n.CallTokenRevokeV1(kind, expectedRefreshEpoch)
	}
)

func CallStoreV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		ToPeerID    string `json:"toPeerId"`
		CallHandle  string `json:"callHandle"`
		MessageID   string `json:"messageId"`
		Envelope    string `json:"envelope"`
		ExpiresAtMs int64  `json:"expiresAtMs"`
		WakeHandle  string `json:"wakeHandle"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil {
		return callBridgeInvalidInput()
	}
	receipt, err := callStoreV1Invoke(n, node.CallStoreRequest{
		Diagnostics:           diagnostics,
		RecipientDevicePeerID: params.ToPeerID, CallHandle: params.CallHandle,
		MessageID: params.MessageID, Envelope: params.Envelope,
		ExpiresAtMs: params.ExpiresAtMs, WakeHandle: params.WakeHandle,
	})
	if err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{
		"ok": true, "schema": receipt.Schema, "version": receipt.Version,
		"storeStatus": receipt.StoreStatus, "receiptAtMs": receipt.ReceiptAtMs,
		"expiresAtMs": receipt.ExpiresAtMs, "eventCount": receipt.EventCount,
		"totalBytes": receipt.TotalBytes, "pendingHandles": receipt.PendingHandles,
		"wake": receipt.Wake,
	})
}

func CallRetrieveV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		CallHandle string `json:"callHandle"`
		Limit      int    `json:"limit"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil {
		return callBridgeInvalidInput()
	}
	retrieved, err := callRetrieveV1Invoke(n, node.CallRetrieveRequest{
		Diagnostics: diagnostics,
		CallHandle:  params.CallHandle, Limit: params.Limit,
	})
	if err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{
		"ok": true, "schema": retrieved.Schema, "version": retrieved.Version,
		"events": retrieved.Events, "receiptAtMs": retrieved.ReceiptAtMs,
		"expiresAtMs": retrieved.ExpiresAtMs, "hasMore": retrieved.HasMore,
	})
}

func CallAckV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		CallHandle string   `json:"callHandle"`
		MessageIDs []string `json:"messageIds"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil {
		return callBridgeInvalidInput()
	}
	acked, err := callAckV1Invoke(n, node.CallAckRequest{
		Diagnostics: diagnostics,
		CallHandle:  params.CallHandle, MessageIDs: append([]string(nil), params.MessageIDs...),
	})
	if err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{"ok": true, "acked": acked})
}

func CallCancelV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		ToPeerID   string `json:"toPeerId"`
		CallHandle string `json:"callHandle"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil {
		return callBridgeInvalidInput()
	}
	if err := callCancelV1Invoke(n, node.CallCancelRequest{
		Diagnostics:           diagnostics,
		RecipientDevicePeerID: params.ToPeerID, CallHandle: params.CallHandle,
	}); err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{"ok": true, "canceled": true})
}

func CallEndpointSetV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var record node.CallEndpointRecord
	if decodeCallBridgeParams(paramsJSON, &record) != nil ||
		(record.Schema != "" && record.Schema != node.CallEndpointSchema) ||
		(record.Version != 0 && record.Version != node.CallControlVersion) {
		return callBridgeInvalidInput()
	}
	record.Diagnostics = diagnostics
	if err := callEndpointSetV1Invoke(n, record); err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{"ok": true})
}

func CallEndpointGetV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		AccountPeerID string `json:"accountPeerId"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil {
		return callBridgeInvalidInput()
	}
	endpoint, err := callEndpointGetDiagnosticInvoke(n, params.AccountPeerID, diagnostics)
	if err != nil {
		return callBridgeError(err)
	}
	response := map[string]any{"ok": true, "found": endpoint.Found}
	if endpoint.Found {
		if endpoint.Endpoint == nil || len(endpoint.CanonicalRecord) == 0 {
			return callBridgeError(node.ErrCallControlInvalidResponse)
		}
		response["endpoint"] = endpoint.Endpoint
		response["canonicalRecord"] = base64.StdEncoding.EncodeToString(endpoint.CanonicalRecord)
	}
	return okJSON(response)
}

func CallEndpointRevokeV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		AccountPeerID   string `json:"accountPeerId"`
		PreferenceEpoch uint64 `json:"preferenceEpoch"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil {
		return callBridgeInvalidInput()
	}
	if err := callEndpointRevokeDiagnosticInvoke(n, params.AccountPeerID, params.PreferenceEpoch, diagnostics); err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{"ok": true, "revoked": true})
}

func CallWakeHandleSetV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		AuthorizedSenderPeerID string `json:"authorizedSenderPeerId"`
		WakeHandle             string `json:"wakeHandle"`
		ExpiresAtMs            int64  `json:"expiresAtMs"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil {
		return callBridgeInvalidInput()
	}
	if err := callWakeHandleSetV1Invoke(n, node.CallWakeHandleRecord{
		Diagnostics:            diagnostics,
		AuthorizedSenderPeerID: params.AuthorizedSenderPeerID,
		WakeHandle:             params.WakeHandle, ExpiresAtMs: params.ExpiresAtMs,
	}); err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{"ok": true})
}

func CallWakeHandleRevokeV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		AuthorizedSenderPeerID string `json:"authorizedSenderPeerId"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil {
		return callBridgeInvalidInput()
	}
	if err := callWakeHandleRevokeDiagnosticInvoke(n, params.AuthorizedSenderPeerID, diagnostics); err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{"ok": true, "revoked": true})
}

func CallTokenSetV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		TokenKind         string `json:"tokenKind"`
		Platform          string `json:"platform"`
		Token             string `json:"token"`
		ExpiresAtMs       int64  `json:"expiresAtMs"`
		Environment       string `json:"environment"`
		Topic             string `json:"topic"`
		CapabilityVersion uint64 `json:"capabilityVersion"`
		RefreshEpoch      uint64 `json:"refreshEpoch"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil {
		return callBridgeInvalidInput()
	}
	record := node.CallTokenRecord{
		Kind: params.TokenKind, Platform: params.Platform,
		Token: params.Token, ExpiresAtMs: params.ExpiresAtMs,
		Environment: params.Environment, Topic: params.Topic,
		CapabilityVersion: params.CapabilityVersion, RefreshEpoch: params.RefreshEpoch,
	}
	if !validCallBridgeTokenShape(record) {
		return callBridgeInvalidInput()
	}
	record.Diagnostics = diagnostics
	setResult, err := callTokenSetV1Invoke(n, record)
	if err != nil {
		return callBridgeError(err)
	}
	response := map[string]any{"ok": true}
	if record.Kind == node.CallTokenKindIOSVoIP {
		if setResult.Generation == 0 || setResult.RefreshEpoch != record.RefreshEpoch {
			return callBridgeError(node.ErrCallControlInvalidResponse)
		}
		response["generation"] = setResult.Generation
		response["refreshEpoch"] = setResult.RefreshEpoch
	} else if setResult.Generation != 0 || setResult.RefreshEpoch != 0 {
		return callBridgeError(node.ErrCallControlInvalidResponse)
	}
	return okJSON(response)
}

func CallTokenRevokeV1(paramsJSON string) (result string) {
	paramsJSON, diagnostics := splitCallBridgeDiagnostics(paramsJSON)
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var params struct {
		TokenKind            string `json:"tokenKind"`
		ExpectedRefreshEpoch uint64 `json:"expectedRefreshEpoch"`
	}
	if decodeCallBridgeParams(paramsJSON, &params) != nil ||
		(params.TokenKind != node.CallTokenKindIOSVoIP && params.TokenKind != node.CallTokenKindStandard) ||
		(params.TokenKind == node.CallTokenKindIOSVoIP && params.ExpectedRefreshEpoch == 0) ||
		(params.TokenKind == node.CallTokenKindStandard && params.ExpectedRefreshEpoch != 0) {
		return callBridgeInvalidInput()
	}
	revoked, err := callTokenRevokeDiagnosticInvoke(n, params.TokenKind, params.ExpectedRefreshEpoch, diagnostics)
	if err != nil {
		return callBridgeError(err)
	}
	if params.TokenKind == node.CallTokenKindStandard && !revoked {
		return callBridgeError(node.ErrCallControlInvalidResponse)
	}
	return okJSON(map[string]any{"ok": true, "revoked": revoked})
}

func validCallBridgeTokenShape(record node.CallTokenRecord) bool {
	if record.Token == "" || record.Token != strings.TrimSpace(record.Token) ||
		strings.ContainsAny(record.Token, "\r\n\t") || record.ExpiresAtMs <= 0 {
		return false
	}
	if record.Kind == node.CallTokenKindStandard {
		return record.Platform == "android" && record.Environment == "" && record.Topic == "" &&
			record.CapabilityVersion == 0 && record.RefreshEpoch == 0
	}
	return record.Kind == node.CallTokenKindIOSVoIP && record.Platform == "ios" &&
		(record.Environment == "sandbox" || record.Environment == "production") &&
		validCallBridgeVoIPTopic(record.Topic) &&
		record.CapabilityVersion == node.CallIOSVoIPCapabilityVersion && record.RefreshEpoch > 0
}

func validCallBridgeVoIPTopic(value string) bool {
	if value == "" || value != strings.TrimSpace(value) || len(value) > 255 ||
		!strings.HasSuffix(value, ".voip") || strings.Contains(value, "..") {
		return false
	}
	for _, char := range value {
		if (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') ||
			(char >= '0' && char <= '9') || char == '.' || char == '-' {
			continue
		}
		return false
	}
	return true
}

func currentCallBridgeNode() *node.Node {
	nodeMu.Lock()
	defer nodeMu.Unlock()
	return singletonNode
}

func decodeCallBridgeParams(raw string, destination any) error {
	if raw == "" {
		raw = "{}"
	}
	decoder := json.NewDecoder(bytes.NewBufferString(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return node.ErrCallControlInvalidRequest
	}
	return nil
}

func callBridgeRecover(result *string) {
	if recover() != nil {
		*result = errJSON("INTERNAL_ERROR", "Call control bridge failure")
	}
}

func callBridgeInvalidInput() string {
	return errJSON("INVALID_INPUT", "Invalid call control request")
}

func callBridgeError(err error) string {
	code := "CALL_CONTROL_UNAVAILABLE"
	var relayErr *node.CallControlRelayError
	switch {
	case errors.As(err, &relayErr) && relayErr != nil && safeCallBridgeRelayErrorCode(relayErr.Code):
		code = relayErr.Code
	case errors.Is(err, node.ErrCallControlUnsupported):
		code = "CALL_CONTROL_UNSUPPORTED"
	case errors.Is(err, node.ErrCallControlInvalidRequest):
		code = "INVALID_INPUT"
	case errors.Is(err, node.ErrCallControlInvalidResponse):
		code = "CALL_CONTROL_INVALID_RESPONSE"
	}
	return errJSON(code, "Call control request failed")
}

func safeCallBridgeRelayErrorCode(code string) bool {
	switch code {
	case "CALL_BACKEND_UNAVAILABLE", "CALL_INVALID_REQUEST", "CALL_UNAUTHORIZED",
		"CALL_IDENTITY_CONFLICT", "CALL_REPLAY", "CALL_EXPIRY_INVALID",
		"CALL_ENVELOPE_TOO_LARGE", "CALL_RECIPIENT_CAPACITY", "CALL_EVENT_CAPACITY",
		"CALL_BYTE_CAPACITY", "CALL_RATE_LIMITED", "CALL_STALE_EPOCH":
		return true
	default:
		return false
	}
}
