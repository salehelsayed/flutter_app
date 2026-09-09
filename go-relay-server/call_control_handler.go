package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
)

const (
	callStoreAction            = "call_store_v1"
	callRetrieveAction         = "call_retrieve_v1"
	callAckAction              = "call_ack_v1"
	callCancelAction           = "call_cancel_v1"
	callEndpointSetAction      = "call_endpoint_set_v1"
	callEndpointGetAction      = "call_endpoint_get_v1"
	callEndpointRevokeAction   = "call_endpoint_revoke_v1"
	callWakeHandleSetAction    = "call_wake_handle_set_v1"
	callWakeHandleRevokeAction = "call_wake_handle_revoke_v1"
	callTokenSetAction         = "call_token_set_v1"
	callTokenRevokeAction      = "call_token_revoke_v1"
)

type callControlWireRequest struct {
	Action      string   `json:"action"`
	To          string   `json:"to,omitempty"`
	CallHandle  string   `json:"callHandle,omitempty"`
	MessageID   string   `json:"messageId,omitempty"`
	MessageIDs  []string `json:"messageIds,omitempty"`
	Envelope    string   `json:"envelope,omitempty"`
	ExpiresAtMs int64    `json:"expiresAtMs,omitempty"`
	WakeHandle  string   `json:"wakeHandle,omitempty"`
	Limit       int      `json:"limit,omitempty"`
	// WakeReceipt asks for the wake outcome on the store receipt. Older
	// clients refuse unknown response fields, so it is only sent when asked.
	WakeReceipt            bool     `json:"wakeReceipt,omitempty"`
	AccountPeerID          string   `json:"accountPeerId,omitempty"`
	DevicePeerID           string   `json:"devicePeerId,omitempty"`
	Capabilities           []string `json:"capabilities,omitempty"`
	Platform               string   `json:"platform,omitempty"`
	PreferenceEpoch        uint64   `json:"preferenceEpoch,omitempty"`
	DeviceKeyEpoch         uint64   `json:"deviceKeyEpoch,omitempty"`
	RoutingHandle          string   `json:"routingHandle,omitempty"`
	Signature              string   `json:"signature,omitempty"`
	AuthorizedSenderPeerID string   `json:"authorizedSenderPeerId,omitempty"`
	TokenKind              string   `json:"tokenKind,omitempty"`
	Token                  string   `json:"token,omitempty"`
	Environment            string   `json:"environment,omitempty"`
	Topic                  string   `json:"topic,omitempty"`
	CapabilityVersion      uint64   `json:"capabilityVersion,omitempty"`
	RefreshEpoch           uint64   `json:"refreshEpoch,omitempty"`
	ExpectedRefreshEpoch   *uint64  `json:"expectedRefreshEpoch,omitempty"`
}

type callControlWireEvent struct {
	CallHandle            string `json:"callHandle"`
	MessageID             string `json:"messageId"`
	SenderPeerID          string `json:"senderPeerId"`
	RecipientDevicePeerID string `json:"recipientDevicePeerId"`
	Envelope              string `json:"envelope"`
	ReceiptAtMs           int64  `json:"receiptAtMs"`
	ExpiresAtMs           int64  `json:"expiresAtMs"`
}

type callControlWireEndpoint struct {
	Schema          string   `json:"schema"`
	Version         int      `json:"version"`
	AccountPeerID   string   `json:"accountPeerId"`
	DevicePeerID    string   `json:"devicePeerId"`
	Capabilities    []string `json:"capabilities"`
	Platform        string   `json:"platform"`
	ExpiresAtMs     int64    `json:"expiresAtMs"`
	PreferenceEpoch uint64   `json:"preferenceEpoch"`
	DeviceKeyEpoch  uint64   `json:"deviceKeyEpoch"`
	RoutingHandle   string   `json:"routingHandle"`
	Signature       string   `json:"signature"`
}

type callControlWireResponse struct {
	Status          string                   `json:"status"`
	ErrorCode       string                   `json:"errorCode,omitempty"`
	Schema          string                   `json:"schema,omitempty"`
	Version         int                      `json:"version,omitempty"`
	StoreStatus     string                   `json:"storeStatus,omitempty"`
	ReceiptAtMs     int64                    `json:"receiptAtMs,omitempty"`
	ExpiresAtMs     int64                    `json:"expiresAtMs,omitempty"`
	EventCount      int                      `json:"eventCount,omitempty"`
	TotalBytes      int                      `json:"totalBytes,omitempty"`
	PendingHandles  int                      `json:"pendingHandles,omitempty"`
	Wake            string                   `json:"wake,omitempty"`
	Events          []callControlWireEvent   `json:"events,omitempty"`
	HasMore         bool                     `json:"hasMore,omitempty"`
	Acked           int                      `json:"acked,omitempty"`
	Canceled        bool                     `json:"canceled,omitempty"`
	Revoked         *bool                    `json:"revoked,omitempty"`
	Found           bool                     `json:"found,omitempty"`
	Endpoint        *callControlWireEndpoint `json:"endpoint,omitempty"`
	CanonicalRecord string                   `json:"canonicalRecord,omitempty"`
	RefreshEpoch    uint64                   `json:"refreshEpoch,omitempty"`
	Generation      uint64                   `json:"generation,omitempty"`
}

func isCallControlAction(action string) bool {
	switch action {
	case callStoreAction, callRetrieveAction, callAckAction, callCancelAction,
		callEndpointSetAction, callEndpointGetAction, callEndpointRevokeAction,
		callWakeHandleSetAction, callWakeHandleRevokeAction,
		callTokenSetAction, callTokenRevokeAction:
		return true
	default:
		return false
	}
}

func handleCallControlRequest(
	s network.Stream,
	raw []byte,
	authenticatedPeerID string,
	service *CallControlService,
) {
	response := callControlErrorResponse(ErrCallBackendUnavailable)
	var action string
	var wakeStatus CallWakeStatus
	defer func() { recordCallControlRequest(action, response, wakeStatus) }()
	request, err := decodeCallControlRequest(raw)
	if err == nil {
		action = request.Action
	}
	if service == nil || service.backend == nil {
		writeErr := writeCallControlResponse(s, response)
		callDiagnosticSpanFromStream(s).result(request, response, writeErr)
		return
	}
	if err != nil {
		response = callControlErrorResponse(ErrCallInvalidRequest)
		writeErr := writeCallControlResponse(s, response)
		callDiagnosticSpanFromStream(s).result(request, response, writeErr)
		return
	}
	span := callDiagnosticSpanFromStream(s)
	if span != nil {
		span.authorityKind = diagnosticAuthorityKind(request)
	}
	ctx, cancel := context.WithTimeout(callDiagnosticWithContext(context.Background(), span), 3*time.Second)
	if span != nil && request.Action != callRetrieveAction {
		stage, action := diagnosticAction(request.Action)
		span.emit(stage, action, "started", span.diagnostics.Reason, nil)
	}
	defer cancel()
	response = callControlWireResponse{Status: "OK"}
	switch request.Action {
	case callStoreAction:
		receipt, callErr := service.Store(ctx, authenticatedPeerID, CallStoreRequest{
			RecipientDevicePeerID: request.To, CallHandle: request.CallHandle,
			MessageID: request.MessageID, Envelope: []byte(request.Envelope),
			ExpiresAtMs: request.ExpiresAtMs, WakeHandle: request.WakeHandle,
		})
		// Observe wake delivery even for clients that did not opt in to the
		// additional wire receipt field.
		wakeStatus = receipt.WakeStatus
		if callErr != nil {
			response = callControlErrorResponse(callErr)
			break
		}
		response.Schema = receipt.Schema
		response.Version = receipt.Version
		response.StoreStatus = string(receipt.StoreStatus)
		response.ReceiptAtMs = receipt.ReceiptAtMs
		response.ExpiresAtMs = receipt.ExpiresAtMs
		response.EventCount = receipt.EventCount
		response.TotalBytes = receipt.TotalBytes
		response.PendingHandles = receipt.PendingHandles
		if request.WakeReceipt {
			response.Wake = string(receipt.WakeStatus)
		}
	case callRetrieveAction:
		result, callErr := service.Retrieve(ctx, authenticatedPeerID, CallRetrieveRequest{
			CallHandle: request.CallHandle, Limit: request.Limit,
		})
		if callErr != nil {
			response = callControlErrorResponse(callErr)
			break
		}
		response.Schema, response.Version = result.Schema, result.Version
		response.ReceiptAtMs, response.ExpiresAtMs = result.ReceiptAtMs, result.ExpiresAtMs
		response.HasMore = result.HasMore
		response.Events = make([]callControlWireEvent, 0, len(result.Events))
		for _, event := range result.Events {
			response.Events = append(response.Events, callControlWireEvent{
				CallHandle: event.CallHandle, MessageID: event.MessageID,
				SenderPeerID: event.SenderPeerID, RecipientDevicePeerID: event.RecipientDevicePeerID,
				Envelope: string(event.Envelope), ReceiptAtMs: event.ReceiptAtMs,
				ExpiresAtMs: event.ExpiresAtMs,
			})
		}
		if fitted, ok := fitCallRetrieveResponse(response); ok {
			response = fitted
		} else {
			response = callControlErrorResponse(ErrCallBackendUnavailable)
		}
	case callAckAction:
		acked, callErr := service.Ack(ctx, authenticatedPeerID, CallAckRequest{
			CallHandle: request.CallHandle, MessageIDs: request.MessageIDs,
		})
		if callErr != nil {
			response = callControlErrorResponse(callErr)
		} else {
			response.Acked = acked
		}
	case callCancelAction:
		if callErr := service.Cancel(ctx, authenticatedPeerID, CallCancelRequest{
			RecipientDevicePeerID: request.To, CallHandle: request.CallHandle,
		}); callErr != nil {
			response = callControlErrorResponse(callErr)
		} else {
			response.Canceled = true
		}
	case callEndpointSetAction:
		signature, decodeErr := base64.StdEncoding.DecodeString(request.Signature)
		if decodeErr != nil {
			response = callControlErrorResponse(ErrCallInvalidRequest)
			break
		}
		// The connection authenticates the device; the record signature must
		// come from the account identity named in the record.
		callErr := service.setEndpoint(ctx, authenticatedPeerID, CallEndpointRecord{
			AccountPeerID: request.AccountPeerID, DevicePeerID: request.DevicePeerID,
			Capabilities: request.Capabilities, Platform: request.Platform,
			ExpiresAtMs: request.ExpiresAtMs, PreferenceEpoch: request.PreferenceEpoch,
			DeviceKeyEpoch: request.DeviceKeyEpoch, RoutingHandle: request.RoutingHandle,
			Signature: signature,
		}, connectionCallEndpointSignatureVerifier{
			authenticatedPeerID: authenticatedPeerID,
			publicKey:           s.Conn().RemotePublicKey(),
		})
		if callErr != nil {
			response = callControlErrorResponse(callErr)
		}
	case callEndpointGetAction:
		endpoint, callErr := service.GetEndpoint(ctx, authenticatedPeerID, request.AccountPeerID)
		if callErr != nil {
			response = callControlErrorResponse(callErr)
			break
		}
		response.Found = endpoint != nil
		if endpoint != nil {
			canonical, canonicalErr := canonicalCallEndpointRecord(*endpoint)
			if canonicalErr != nil {
				response = callControlErrorResponse(ErrCallBackendUnavailable)
				break
			}
			response.Endpoint = endpointToWire(*endpoint)
			response.CanonicalRecord = base64.StdEncoding.EncodeToString(canonical)
		}
	case callEndpointRevokeAction:
		callErr := service.RevokeEndpoint(
			ctx, authenticatedPeerID, request.AccountPeerID, request.PreferenceEpoch,
		)
		if callErr != nil {
			response = callControlErrorResponse(callErr)
		} else {
			response.Revoked = callControlBool(true)
		}
	case callWakeHandleSetAction:
		callErr := service.SetWakeHandle(ctx, authenticatedPeerID, CallWakeHandleRecord{
			AuthorizedSenderPeerID: request.AuthorizedSenderPeerID,
			WakeHandle:             request.WakeHandle, ExpiresAtMs: request.ExpiresAtMs,
		})
		if callErr != nil {
			response = callControlErrorResponse(callErr)
		}
	case callWakeHandleRevokeAction:
		callErr := service.RevokeWakeHandle(ctx, authenticatedPeerID, request.AuthorizedSenderPeerID)
		if callErr != nil {
			response = callControlErrorResponse(callErr)
		} else {
			response.Revoked = callControlBool(true)
		}
	case callTokenSetAction:
		stored, callErr := service.SetCallTokenWithResult(ctx, authenticatedPeerID, CallTokenRecord{
			Kind: CallTokenKind(request.TokenKind), Platform: request.Platform,
			Token: request.Token, ExpiresAtMs: request.ExpiresAtMs,
			Environment: request.Environment, Topic: request.Topic,
			CapabilityVersion: request.CapabilityVersion, RefreshEpoch: request.RefreshEpoch,
		})
		if callErr != nil {
			response = callControlErrorResponse(callErr)
		} else if stored != nil {
			response.RefreshEpoch = stored.RefreshEpoch
			response.Generation = stored.Generation
		}
		if callErr == nil {
			if _, v2 := s.(*callDiagnosticStream); !v2 {
				service.diagnostics.invalidateLegacyPushCapability(authenticatedPeerID)
			}
		}
	case callTokenRevokeAction:
		kind := CallTokenKind(request.TokenKind)
		if kind == CallTokenKindIOSVoIP {
			if request.ExpectedRefreshEpoch == nil {
				response = callControlErrorResponse(ErrCallInvalidRequest)
				break
			}
			revoked, callErr := service.RevokeCallTokenRefreshEpoch(
				ctx, authenticatedPeerID, kind, *request.ExpectedRefreshEpoch,
			)
			if callErr != nil {
				response = callControlErrorResponse(callErr)
			} else {
				response.Revoked = callControlBool(revoked)
			}
		} else if request.ExpectedRefreshEpoch != nil {
			response = callControlErrorResponse(ErrCallInvalidRequest)
		} else {
			callErr := service.RevokeCallToken(ctx, authenticatedPeerID, kind)
			if callErr != nil {
				response = callControlErrorResponse(callErr)
			} else {
				response.Revoked = callControlBool(true)
			}
		}
	}
	writeErr := writeCallControlResponse(s, response)
	span.result(request, response, writeErr)
}

func decodeCallControlRequest(raw []byte) (callControlWireRequest, error) {
	if err := validateCallControlFieldSet(raw); err != nil {
		return callControlWireRequest{}, err
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	var request callControlWireRequest
	if err := decoder.Decode(&request); err != nil || !isCallControlAction(request.Action) {
		return callControlWireRequest{}, ErrCallInvalidRequest
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return callControlWireRequest{}, ErrCallInvalidRequest
	}
	return request, nil
}

func validateCallControlFieldSet(raw []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	opening, err := decoder.Token()
	if err != nil || opening != json.Delim('{') {
		return ErrCallInvalidRequest
	}
	seen := make(map[string]struct{})
	var action string
	keys := make([]string, 0, 12)
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return ErrCallInvalidRequest
		}
		key, ok := token.(string)
		if !ok {
			return ErrCallInvalidRequest
		}
		if _, duplicate := seen[key]; duplicate {
			return ErrCallInvalidRequest
		}
		seen[key] = struct{}{}
		keys = append(keys, key)
		var value json.RawMessage
		if err := decoder.Decode(&value); err != nil {
			return ErrCallInvalidRequest
		}
		if key == "action" && json.Unmarshal(value, &action) != nil {
			return ErrCallInvalidRequest
		}
	}
	if closing, err := decoder.Token(); err != nil || closing != json.Delim('}') {
		return ErrCallInvalidRequest
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return ErrCallInvalidRequest
	}
	allowed := callControlAllowedFields(action)
	if allowed == nil {
		return ErrCallInvalidRequest
	}
	for _, key := range keys {
		if _, ok := allowed[key]; !ok {
			return ErrCallInvalidRequest
		}
	}
	return nil
}

func callControlAllowedFields(action string) map[string]struct{} {
	fields := []string{"action"}
	switch action {
	case callStoreAction:
		fields = append(fields, "to", "callHandle", "messageId", "envelope", "expiresAtMs", "wakeHandle", "wakeReceipt")
	case callRetrieveAction:
		fields = append(fields, "callHandle", "limit")
	case callAckAction:
		fields = append(fields, "callHandle", "messageIds")
	case callCancelAction:
		fields = append(fields, "to", "callHandle")
	case callEndpointSetAction:
		fields = append(fields, "accountPeerId", "devicePeerId", "capabilities", "platform",
			"expiresAtMs", "preferenceEpoch", "deviceKeyEpoch", "routingHandle", "signature")
	case callEndpointGetAction:
		fields = append(fields, "accountPeerId")
	case callEndpointRevokeAction:
		fields = append(fields, "accountPeerId", "preferenceEpoch")
	case callWakeHandleSetAction:
		fields = append(fields, "authorizedSenderPeerId", "wakeHandle", "expiresAtMs")
	case callWakeHandleRevokeAction:
		fields = append(fields, "authorizedSenderPeerId")
	case callTokenSetAction:
		fields = append(fields, "tokenKind", "platform", "token", "expiresAtMs",
			"environment", "topic", "capabilityVersion", "refreshEpoch")
	case callTokenRevokeAction:
		fields = append(fields, "tokenKind", "expectedRefreshEpoch")
	default:
		return nil
	}
	allowed := make(map[string]struct{}, len(fields))
	for _, field := range fields {
		allowed[field] = struct{}{}
	}
	return allowed
}

func endpointToWire(endpoint CallEndpointRecord) *callControlWireEndpoint {
	return &callControlWireEndpoint{
		Schema: endpoint.Schema, Version: endpoint.Version,
		AccountPeerID: endpoint.AccountPeerID, DevicePeerID: endpoint.DevicePeerID,
		Capabilities: append([]string(nil), endpoint.Capabilities...), Platform: endpoint.Platform,
		ExpiresAtMs: endpoint.ExpiresAtMs, PreferenceEpoch: endpoint.PreferenceEpoch,
		DeviceKeyEpoch: endpoint.DeviceKeyEpoch, RoutingHandle: endpoint.RoutingHandle,
		Signature: base64.StdEncoding.EncodeToString(endpoint.Signature),
	}
}

func fitCallRetrieveResponse(response callControlWireResponse) (callControlWireResponse, bool) {
	for {
		raw, err := json.Marshal(response)
		if err == nil && len(raw) <= maxFrameLen {
			return response, true
		}
		if len(response.Events) == 0 {
			return callControlWireResponse{}, false
		}
		response.Events = response.Events[:len(response.Events)-1]
		response.HasMore = true
	}
}

func callControlErrorResponse(err error) callControlWireResponse {
	code := "CALL_BACKEND_UNAVAILABLE"
	switch {
	case errors.Is(err, ErrCallInvalidRequest):
		code = "CALL_INVALID_REQUEST"
	case errors.Is(err, ErrCallUnauthorized):
		code = "CALL_UNAUTHORIZED"
	case errors.Is(err, ErrCallIdentityConflict):
		code = "CALL_IDENTITY_CONFLICT"
	case errors.Is(err, ErrCallReplay):
		code = "CALL_REPLAY"
	case errors.Is(err, ErrCallExpiry):
		code = "CALL_EXPIRY_INVALID"
	case errors.Is(err, ErrCallEnvelopeTooLarge):
		code = "CALL_ENVELOPE_TOO_LARGE"
	case errors.Is(err, ErrCallRecipientCapacity):
		code = "CALL_RECIPIENT_CAPACITY"
	case errors.Is(err, ErrCallEventCapacity):
		code = "CALL_EVENT_CAPACITY"
	case errors.Is(err, ErrCallByteCapacity):
		code = "CALL_BYTE_CAPACITY"
	case errors.Is(err, ErrCallRateLimited):
		code = "CALL_RATE_LIMITED"
	case errors.Is(err, ErrCallStaleEpoch):
		code = "CALL_STALE_EPOCH"
	}
	return callControlWireResponse{Status: "ERROR", ErrorCode: code}
}

func writeCallControlResponse(s network.Stream, response callControlWireResponse) error {
	raw, err := json.Marshal(response)
	if err != nil {
		raw = []byte(`{"status":"ERROR","errorCode":"CALL_BACKEND_UNAVAILABLE"}`)
	}
	return writeFrame(s, raw)
}

func callControlBool(value bool) *bool {
	return &value
}
