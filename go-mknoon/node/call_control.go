package node

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
)

const (
	CallMailboxSchema  = "mknoon.call_mailbox.v1"
	CallEndpointSchema = "mknoon.call_endpoint_set.v1"
	CallControlVersion = 1

	CallTokenKindStandard               = "standard_call"
	CallTokenKindIOSVoIP                = "ios_voip"
	CallIOSVoIPCapabilityVersion uint64 = 1

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

	callMaxEnvelopeBytes = 96 * 1024
	callMaxEvents        = 64
	callMaxBytes         = 256 * 1024
	callMaxTTL           = 45 * time.Second
	callMaxClockSkew     = 5 * time.Minute
	callMaxFieldBytes    = 16 * 1024
	callMaxRecordTTL     = 90 * 24 * time.Hour
)

var (
	ErrCallControlUnsupported     = errors.New("call control unsupported")
	ErrCallControlInvalidRequest  = errors.New("call control request invalid")
	ErrCallControlInvalidResponse = errors.New("call control response invalid")
	ErrCallControlUnavailable     = errors.New("call control unavailable")
)

type CallControlRelayError struct {
	Code string
}

func (e *CallControlRelayError) Error() string {
	if e == nil || e.Code == "" {
		return ErrCallControlUnavailable.Error()
	}
	return "call control unavailable: " + e.Code
}

func (e *CallControlRelayError) Unwrap() error { return ErrCallControlUnavailable }

type CallStoreRequest struct {
	Diagnostics           *CallDiagnosticContext `json:"-"`
	RecipientDevicePeerID string
	CallHandle            string
	MessageID             string
	Envelope              string
	ExpiresAtMs           int64
	WakeHandle            string
}

type CallStoreReceipt struct {
	Schema         string
	Version        int
	StoreStatus    string
	ReceiptAtMs    int64
	ExpiresAtMs    int64
	EventCount     int
	TotalBytes     int
	PendingHandles int
	// Wake is the relay's wake outcome for this event: "dispatched" when the
	// callee's device was alerted, "failed" when the provider refused, empty
	// when nothing was sent (no route, or a callee already on the call).
	Wake string
}

type CallRetrieveRequest struct {
	Diagnostics *CallDiagnosticContext `json:"-"`
	CallHandle  string
	Limit       int
}

type CallMailboxEvent struct {
	CallHandle            string `json:"callHandle"`
	MessageID             string `json:"messageId"`
	SenderPeerID          string `json:"senderPeerId"`
	RecipientDevicePeerID string `json:"recipientDevicePeerId"`
	Envelope              string `json:"envelope"`
	ReceiptAtMs           int64  `json:"receiptAtMs"`
	ExpiresAtMs           int64  `json:"expiresAtMs"`
}

type CallRetrieveResult struct {
	Schema      string
	Version     int
	Events      []CallMailboxEvent
	ReceiptAtMs int64
	ExpiresAtMs int64
	HasMore     bool
}

type CallAckRequest struct {
	Diagnostics *CallDiagnosticContext `json:"-"`
	CallHandle  string
	MessageIDs  []string
}

type CallCancelRequest struct {
	Diagnostics           *CallDiagnosticContext `json:"-"`
	RecipientDevicePeerID string
	CallHandle            string
}

type CallEndpointRecord struct {
	Diagnostics     *CallDiagnosticContext `json:"-"`
	Schema          string                 `json:"schema,omitempty"`
	Version         int                    `json:"version,omitempty"`
	AccountPeerID   string                 `json:"accountPeerId"`
	DevicePeerID    string                 `json:"devicePeerId"`
	Capabilities    []string               `json:"capabilities"`
	Platform        string                 `json:"platform"`
	ExpiresAtMs     int64                  `json:"expiresAtMs"`
	PreferenceEpoch uint64                 `json:"preferenceEpoch"`
	DeviceKeyEpoch  uint64                 `json:"deviceKeyEpoch"`
	RoutingHandle   string                 `json:"routingHandle"`
	Signature       string                 `json:"signature"`
}

type CallEndpointResult struct {
	Found           bool
	Endpoint        *CallEndpointRecord
	CanonicalRecord []byte
}

type CallWakeHandleRecord struct {
	Diagnostics            *CallDiagnosticContext `json:"-"`
	AuthorizedSenderPeerID string
	WakeHandle             string
	ExpiresAtMs            int64
}

type CallTokenRecord struct {
	Diagnostics       *CallDiagnosticContext `json:"-"`
	Kind              string                 `json:"tokenKind"`
	Platform          string                 `json:"platform"`
	Token             string                 `json:"token"`
	ExpiresAtMs       int64                  `json:"expiresAtMs"`
	Environment       string                 `json:"environment,omitempty"`
	Topic             string                 `json:"topic,omitempty"`
	CapabilityVersion uint64                 `json:"capabilityVersion,omitempty"`
	RefreshEpoch      uint64                 `json:"refreshEpoch,omitempty"`
}

type CallTokenSetResult struct {
	RefreshEpoch uint64
	Generation   uint64
}

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
	// WakeReceipt asks the relay for the wake outcome on the store receipt.
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
	ExpectedRefreshEpoch   uint64   `json:"expectedRefreshEpoch,omitempty"`
}

type callControlWireResponse struct {
	Status          string              `json:"status"`
	Error           string              `json:"error,omitempty"`
	ErrorCode       string              `json:"errorCode,omitempty"`
	Schema          string              `json:"schema,omitempty"`
	Version         int                 `json:"version,omitempty"`
	StoreStatus     string              `json:"storeStatus,omitempty"`
	ReceiptAtMs     int64               `json:"receiptAtMs,omitempty"`
	ExpiresAtMs     int64               `json:"expiresAtMs,omitempty"`
	EventCount      int                 `json:"eventCount,omitempty"`
	TotalBytes      int                 `json:"totalBytes,omitempty"`
	PendingHandles  int                 `json:"pendingHandles,omitempty"`
	Wake            string              `json:"wake,omitempty"`
	Events          []CallMailboxEvent  `json:"events,omitempty"`
	HasMore         bool                `json:"hasMore,omitempty"`
	Acked           int                 `json:"acked,omitempty"`
	Canceled        bool                `json:"canceled,omitempty"`
	Revoked         *bool               `json:"revoked,omitempty"`
	Found           bool                `json:"found,omitempty"`
	Endpoint        *CallEndpointRecord `json:"endpoint,omitempty"`
	CanonicalRecord string              `json:"canonicalRecord,omitempty"`
	RefreshEpoch    uint64              `json:"refreshEpoch,omitempty"`
	Generation      uint64              `json:"generation,omitempty"`
}

func (n *Node) CallStoreV1(request CallStoreRequest) (CallStoreReceipt, error) {
	if !validCallPeerID(request.RecipientDevicePeerID) ||
		!validCallRandomID(request.CallHandle) || !validCallRandomID(request.MessageID) ||
		!validCallRandomID(request.WakeHandle) || request.Envelope == "" ||
		!utf8.ValidString(request.Envelope) || len(request.Envelope) > callMaxEnvelopeBytes {
		return CallStoreReceipt{}, ErrCallControlInvalidRequest
	}
	now := time.Now().UTC()
	expiresAt := time.UnixMilli(request.ExpiresAtMs)
	if !expiresAt.After(now) || expiresAt.After(now.Add(callMaxTTL)) {
		return CallStoreReceipt{}, ErrCallControlInvalidRequest
	}
	response, err := n.exchangeCallControl(callControlWireRequest{
		Action: callStoreAction, To: request.RecipientDevicePeerID,
		CallHandle: request.CallHandle, MessageID: request.MessageID,
		Envelope: request.Envelope, ExpiresAtMs: request.ExpiresAtMs,
		WakeHandle: request.WakeHandle, WakeReceipt: true,
	}, request.Diagnostics)
	if err != nil {
		return CallStoreReceipt{}, err
	}
	if response.Schema != CallMailboxSchema || response.Version != CallControlVersion ||
		(response.StoreStatus != "stored" && response.StoreStatus != "duplicate") ||
		response.ReceiptAtMs <= 0 || response.ExpiresAtMs > request.ExpiresAtMs ||
		response.ReceiptAtMs > response.ExpiresAtMs || response.EventCount < 1 ||
		response.EventCount > callMaxEvents || response.TotalBytes < len(request.Envelope) ||
		response.TotalBytes > callMaxBytes || response.PendingHandles < 1 || response.PendingHandles > 2 ||
		!validCallWakeOutcome(response.Wake) ||
		absCallDuration(now.Sub(time.UnixMilli(response.ReceiptAtMs))) > callMaxClockSkew {
		return CallStoreReceipt{}, ErrCallControlInvalidResponse
	}
	return CallStoreReceipt{
		Schema: response.Schema, Version: response.Version, StoreStatus: response.StoreStatus,
		ReceiptAtMs: response.ReceiptAtMs, ExpiresAtMs: response.ExpiresAtMs,
		EventCount: response.EventCount, TotalBytes: response.TotalBytes, Wake: response.Wake,
		PendingHandles: response.PendingHandles,
	}, nil
}

func (n *Node) CallRetrieveV1(request CallRetrieveRequest) (CallRetrieveResult, error) {
	if (request.CallHandle != "" && !validCallRandomID(request.CallHandle)) ||
		request.Limit < 0 || request.Limit > callMaxEvents {
		return CallRetrieveResult{}, ErrCallControlInvalidRequest
	}
	response, err := n.exchangeCallControl(callControlWireRequest{
		Action: callRetrieveAction, CallHandle: request.CallHandle, Limit: request.Limit,
	}, request.Diagnostics)
	if err != nil {
		return CallRetrieveResult{}, err
	}
	if response.Schema != CallMailboxSchema || response.Version != CallControlVersion ||
		len(response.Events) > callMaxEvents || response.ReceiptAtMs <= 0 ||
		absCallDuration(time.Now().Sub(time.UnixMilli(response.ReceiptAtMs))) > callMaxClockSkew {
		return CallRetrieveResult{}, ErrCallControlInvalidResponse
	}
	for _, event := range response.Events {
		if !validCallRandomID(event.CallHandle) || !validCallRandomID(event.MessageID) ||
			!validCallPeerID(event.SenderPeerID) || event.RecipientDevicePeerID != n.peerId ||
			event.Envelope == "" || len(event.Envelope) > callMaxEnvelopeBytes ||
			event.ReceiptAtMs <= 0 || event.ExpiresAtMs <= response.ReceiptAtMs ||
			(request.CallHandle != "" && event.CallHandle != request.CallHandle) {
			return CallRetrieveResult{}, ErrCallControlInvalidResponse
		}
	}
	return CallRetrieveResult{
		Schema: response.Schema, Version: response.Version,
		Events:      append(make([]CallMailboxEvent, 0, len(response.Events)), response.Events...),
		ReceiptAtMs: response.ReceiptAtMs, ExpiresAtMs: response.ExpiresAtMs,
		HasMore: response.HasMore,
	}, nil
}

func validCallWakeOutcome(value string) bool {
	switch value {
	case "", "dispatched", "failed":
		return true
	}
	return false
}

func (n *Node) CallAckV1(request CallAckRequest) (int, error) {
	if !validCallRandomID(request.CallHandle) || len(request.MessageIDs) == 0 ||
		len(request.MessageIDs) > callMaxEvents {
		return 0, ErrCallControlInvalidRequest
	}
	for _, id := range request.MessageIDs {
		if !validCallRandomID(id) {
			return 0, ErrCallControlInvalidRequest
		}
	}
	response, err := n.exchangeCallControl(callControlWireRequest{
		Action: callAckAction, CallHandle: request.CallHandle,
		MessageIDs: append([]string(nil), request.MessageIDs...),
	}, request.Diagnostics)
	if err != nil {
		return 0, err
	}
	if response.Acked < 0 || response.Acked > len(request.MessageIDs) {
		return 0, ErrCallControlInvalidResponse
	}
	return response.Acked, nil
}

func (n *Node) CallCancelV1(request CallCancelRequest) error {
	if !validCallPeerID(request.RecipientDevicePeerID) || !validCallRandomID(request.CallHandle) {
		return ErrCallControlInvalidRequest
	}
	response, err := n.exchangeCallControl(callControlWireRequest{
		Action: callCancelAction, To: request.RecipientDevicePeerID, CallHandle: request.CallHandle,
	}, request.Diagnostics)
	if err != nil {
		return err
	}
	if !response.Canceled {
		return ErrCallControlInvalidResponse
	}
	return nil
}

func (n *Node) CallEndpointSetV1(record CallEndpointRecord) error {
	if record.Schema == "" {
		record.Schema = CallEndpointSchema
	}
	if record.Version == 0 {
		record.Version = CallControlVersion
	}
	if err := validateNodeCallEndpoint(record); err != nil {
		return err
	}
	if record.DevicePeerID != n.peerId {
		return ErrCallControlInvalidRequest
	}
	_, err := n.exchangeCallControl(callControlWireRequest{
		Action: callEndpointSetAction, AccountPeerID: record.AccountPeerID,
		DevicePeerID: record.DevicePeerID, Capabilities: append([]string(nil), record.Capabilities...),
		Platform: record.Platform, ExpiresAtMs: record.ExpiresAtMs,
		PreferenceEpoch: record.PreferenceEpoch, DeviceKeyEpoch: record.DeviceKeyEpoch,
		RoutingHandle: record.RoutingHandle, Signature: record.Signature,
	}, record.Diagnostics)
	return err
}

func (n *Node) CallEndpointGetV1(accountPeerID string, diagnostics ...*CallDiagnosticContext) (CallEndpointResult, error) {
	if !validCallPeerID(accountPeerID) {
		return CallEndpointResult{}, ErrCallControlInvalidRequest
	}
	response, err := n.exchangeCallControl(callControlWireRequest{
		Action: callEndpointGetAction, AccountPeerID: accountPeerID,
	}, diagnosticContext(diagnostics))
	if err != nil {
		return CallEndpointResult{}, err
	}
	if !response.Found {
		if response.Endpoint != nil || response.CanonicalRecord != "" {
			return CallEndpointResult{}, ErrCallControlInvalidResponse
		}
		return CallEndpointResult{}, nil
	}
	if response.Endpoint == nil || response.Endpoint.AccountPeerID != accountPeerID ||
		validateNodeCallEndpoint(*response.Endpoint) != nil {
		return CallEndpointResult{}, ErrCallControlInvalidResponse
	}
	canonical, err := base64.StdEncoding.DecodeString(response.CanonicalRecord)
	if err != nil || len(canonical) == 0 {
		return CallEndpointResult{}, ErrCallControlInvalidResponse
	}
	wantCanonical, err := canonicalNodeCallEndpoint(*response.Endpoint)
	if err != nil || !bytes.Equal(canonical, wantCanonical) {
		return CallEndpointResult{}, ErrCallControlInvalidResponse
	}
	copy := *response.Endpoint
	copy.Capabilities = append([]string(nil), response.Endpoint.Capabilities...)
	return CallEndpointResult{Found: true, Endpoint: &copy, CanonicalRecord: canonical}, nil
}

func (n *Node) CallEndpointRevokeV1(accountPeerID string, preferenceEpoch uint64, diagnostics ...*CallDiagnosticContext) error {
	if !validCallPeerID(accountPeerID) || preferenceEpoch == 0 {
		return ErrCallControlInvalidRequest
	}
	response, err := n.exchangeCallControl(callControlWireRequest{
		Action: callEndpointRevokeAction, AccountPeerID: accountPeerID,
		PreferenceEpoch: preferenceEpoch,
	}, diagnosticContext(diagnostics))
	if err != nil {
		return err
	}
	if response.Revoked == nil || !*response.Revoked {
		return ErrCallControlInvalidResponse
	}
	return nil
}

func (n *Node) CallWakeHandleSetV1(record CallWakeHandleRecord) error {
	now := time.Now()
	if !validCallPeerID(record.AuthorizedSenderPeerID) || !validCallRandomID(record.WakeHandle) ||
		record.ExpiresAtMs <= now.UnixMilli() ||
		time.UnixMilli(record.ExpiresAtMs).After(now.Add(callMaxRecordTTL)) {
		return ErrCallControlInvalidRequest
	}
	_, err := n.exchangeCallControl(callControlWireRequest{
		Action: callWakeHandleSetAction, AuthorizedSenderPeerID: record.AuthorizedSenderPeerID,
		WakeHandle: record.WakeHandle, ExpiresAtMs: record.ExpiresAtMs,
	}, record.Diagnostics)
	return err
}

func (n *Node) CallWakeHandleRevokeV1(authorizedSenderPeerID string, diagnostics ...*CallDiagnosticContext) error {
	if !validCallPeerID(authorizedSenderPeerID) {
		return ErrCallControlInvalidRequest
	}
	response, err := n.exchangeCallControl(callControlWireRequest{
		Action: callWakeHandleRevokeAction, AuthorizedSenderPeerID: authorizedSenderPeerID,
	}, diagnosticContext(diagnostics))
	if err != nil {
		return err
	}
	if response.Revoked == nil || !*response.Revoked {
		return ErrCallControlInvalidResponse
	}
	return nil
}

func (n *Node) CallTokenSetV1(record CallTokenRecord) (CallTokenSetResult, error) {
	if !validNodeCallToken(record) {
		return CallTokenSetResult{}, ErrCallControlInvalidRequest
	}
	response, err := n.exchangeCallControl(callControlWireRequest{
		Action: callTokenSetAction, TokenKind: record.Kind, Platform: record.Platform,
		Token: record.Token, ExpiresAtMs: record.ExpiresAtMs,
		Environment: record.Environment, Topic: record.Topic,
		CapabilityVersion: record.CapabilityVersion, RefreshEpoch: record.RefreshEpoch,
	}, record.Diagnostics)
	if err != nil {
		return CallTokenSetResult{}, err
	}
	if record.Kind == CallTokenKindStandard {
		if response.Generation != 0 || response.RefreshEpoch != 0 {
			return CallTokenSetResult{}, ErrCallControlInvalidResponse
		}
		return CallTokenSetResult{}, nil
	}
	if response.Generation == 0 || response.RefreshEpoch != record.RefreshEpoch {
		return CallTokenSetResult{}, ErrCallControlInvalidResponse
	}
	return CallTokenSetResult{
		RefreshEpoch: response.RefreshEpoch, Generation: response.Generation,
	}, nil
}

func (n *Node) CallTokenRevokeV1(kind string, expectedRefreshEpoch uint64, diagnostics ...*CallDiagnosticContext) (bool, error) {
	if !validNodeCallTokenKind(kind) ||
		(kind == CallTokenKindIOSVoIP && expectedRefreshEpoch == 0) ||
		(kind == CallTokenKindStandard && expectedRefreshEpoch != 0) {
		return false, ErrCallControlInvalidRequest
	}
	response, err := n.exchangeCallControl(callControlWireRequest{
		Action: callTokenRevokeAction, TokenKind: kind,
		ExpectedRefreshEpoch: expectedRefreshEpoch,
	}, diagnosticContext(diagnostics))
	if err != nil {
		return false, err
	}
	if response.Revoked == nil {
		return false, ErrCallControlInvalidResponse
	}
	if kind == CallTokenKindStandard && !*response.Revoked {
		return false, ErrCallControlInvalidResponse
	}
	return *response.Revoked, nil
}

func (n *Node) exchangeCallControl(request callControlWireRequest, diagnostics ...*CallDiagnosticContext) (callControlWireResponse, error) {
	n.mu.RLock()
	h := n.host
	ctx := n.ctx
	n.mu.RUnlock()
	if h == nil || ctx == nil {
		return callControlWireResponse{}, ErrCallControlUnavailable
	}
	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return callControlWireResponse{}, ErrCallControlUnavailable
	}
	var lastErr error
	for _, relay := range relays {
		for _, candidate := range relayInfoAttemptCandidates(relay) {
			diagnostic := n.diagnosticForRelay(candidate.ID, diagnostics)
			raw, err := exchangeCallControlRelay(ctx, h, candidate, request, diagnostic)
			if err == nil && diagnostic != nil && diagnosticUnsupported(raw) {
				n.setDiagnosticRelay(candidate.ID, false)
				raw, err = exchangeCallControlRelay(ctx, h, candidate, request)
			}
			if err != nil {
				lastErr = err
				continue
			}
			response, err := parseCallControlResponse(raw, request.Action)
			if err == nil {
				return response, nil
			}
			lastErr = err
			var relayErr *CallControlRelayError
			if errors.As(err, &relayErr) && relayErr.Code != "CALL_BACKEND_UNAVAILABLE" {
				return callControlWireResponse{}, err
			}
			if !errors.Is(err, ErrCallControlUnavailable) && !errors.Is(err, ErrCallControlUnsupported) {
				return callControlWireResponse{}, err
			}
			break
		}
	}
	if lastErr == nil {
		lastErr = ErrCallControlUnavailable
	}
	return callControlWireResponse{}, lastErr
}

func exchangeCallControlRelay(
	parent context.Context,
	h host.Host,
	relay RelayInfo,
	request callControlWireRequest,
	diagnostics ...*CallDiagnosticContext,
) ([]byte, error) {
	ctx, cancel := context.WithTimeout(parent, InboxTimeout)
	defer cancel()
	if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
		return nil, ErrCallControlUnavailable
	}
	stream, err := h.NewStream(ctx, relay.ID, InboxProtocol)
	if err != nil {
		return nil, ErrCallControlUnavailable
	}
	streamOK := false
	defer finishStream(stream, &streamOK)
	setStreamDeadline(stream, InboxTimeout)
	raw, err := json.Marshal(request)
	raw = diagnosticWrapRequest(raw, diagnosticContext(diagnostics))
	if err != nil || writeFrame(stream, raw) != nil {
		return nil, ErrCallControlUnavailable
	}
	response, err := readFrame(stream)
	if err != nil {
		return nil, ErrCallControlUnavailable
	}
	streamOK = true
	return response, nil
}

func parseCallControlResponse(raw []byte, action string) (callControlWireResponse, error) {
	if err := validateCallControlResponseFieldSet(raw, action); err != nil {
		return callControlWireResponse{}, err
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	var response callControlWireResponse
	if err := decoder.Decode(&response); err != nil {
		return callControlWireResponse{}, ErrCallControlInvalidResponse
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return callControlWireResponse{}, ErrCallControlInvalidResponse
	}
	if response.Status == "ERROR" {
		if response.Error == "Unknown action: "+action && response.ErrorCode == "" {
			return callControlWireResponse{}, ErrCallControlUnsupported
		}
		if response.Error != "" || !safeCallErrorCode(response.ErrorCode) {
			return callControlWireResponse{}, ErrCallControlInvalidResponse
		}
		return callControlWireResponse{}, &CallControlRelayError{Code: response.ErrorCode}
	}
	if response.Status != "OK" || response.Error != "" || response.ErrorCode != "" {
		return callControlWireResponse{}, ErrCallControlInvalidResponse
	}
	return response, nil
}

func validateCallControlResponseFieldSet(raw []byte, action string) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	opening, err := decoder.Token()
	if err != nil || opening != json.Delim('{') {
		return ErrCallControlInvalidResponse
	}
	seen := map[string]struct{}{}
	keys := make([]string, 0, 12)
	status := ""
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return ErrCallControlInvalidResponse
		}
		key, ok := token.(string)
		if !ok {
			return ErrCallControlInvalidResponse
		}
		if _, duplicate := seen[key]; duplicate {
			return ErrCallControlInvalidResponse
		}
		seen[key] = struct{}{}
		keys = append(keys, key)
		var value json.RawMessage
		if err := decoder.Decode(&value); err != nil {
			return ErrCallControlInvalidResponse
		}
		if key == "status" && json.Unmarshal(value, &status) != nil {
			return ErrCallControlInvalidResponse
		}
	}
	if closing, err := decoder.Token(); err != nil || closing != json.Delim('}') {
		return ErrCallControlInvalidResponse
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return ErrCallControlInvalidResponse
	}
	allowed := map[string]struct{}{"status": {}}
	if status == "ERROR" {
		allowed["error"] = struct{}{}
		allowed["errorCode"] = struct{}{}
	} else if status == "OK" {
		var fields []string
		switch action {
		case callStoreAction:
			fields = []string{"schema", "version", "storeStatus", "receiptAtMs", "expiresAtMs", "eventCount", "totalBytes", "pendingHandles", "wake"}
		case callRetrieveAction:
			fields = []string{"schema", "version", "events", "receiptAtMs", "expiresAtMs", "hasMore"}
		case callAckAction:
			fields = []string{"acked"}
		case callCancelAction:
			fields = []string{"canceled"}
		case callEndpointSetAction, callWakeHandleSetAction:
			fields = nil
		case callTokenSetAction:
			fields = []string{"refreshEpoch", "generation"}
		case callEndpointGetAction:
			fields = []string{"found", "endpoint", "canonicalRecord"}
		case callEndpointRevokeAction, callWakeHandleRevokeAction, callTokenRevokeAction:
			fields = []string{"revoked"}
		default:
			return ErrCallControlInvalidResponse
		}
		for _, field := range fields {
			allowed[field] = struct{}{}
		}
	} else {
		return ErrCallControlInvalidResponse
	}
	for _, key := range keys {
		if _, ok := allowed[key]; !ok {
			return ErrCallControlInvalidResponse
		}
	}
	return nil
}

func safeCallErrorCode(code string) bool {
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

func validateNodeCallEndpoint(record CallEndpointRecord) error {
	now := time.Now()
	if record.Schema != CallEndpointSchema || record.Version != CallControlVersion ||
		!validCallPeerID(record.AccountPeerID) || !validCallPeerID(record.DevicePeerID) ||
		(record.Platform != "android" && record.Platform != "ios") ||
		record.ExpiresAtMs <= now.UnixMilli() ||
		time.UnixMilli(record.ExpiresAtMs).After(now.Add(callMaxRecordTTL)) || record.PreferenceEpoch == 0 ||
		record.DeviceKeyEpoch == 0 || !validCallRandomID(record.RoutingHandle) ||
		record.Signature == "" || len(record.Signature) > callMaxFieldBytes ||
		len(record.Capabilities) == 0 || len(record.Capabilities) > 16 {
		return ErrCallControlInvalidRequest
	}
	if _, err := base64.StdEncoding.DecodeString(record.Signature); err != nil {
		return ErrCallControlInvalidRequest
	}
	hasVoice := false
	seen := map[string]struct{}{}
	for _, capability := range record.Capabilities {
		if capability == "" || capability != strings.TrimSpace(capability) {
			return ErrCallControlInvalidRequest
		}
		if _, duplicate := seen[capability]; duplicate {
			return ErrCallControlInvalidRequest
		}
		seen[capability] = struct{}{}
		hasVoice = hasVoice || capability == "voice_call_v1"
	}
	if !hasVoice {
		return ErrCallControlInvalidRequest
	}
	return nil
}

func validNodeCallToken(record CallTokenRecord) bool {
	now := time.Now()
	if !validNodeCallTokenKind(record.Kind) || record.Token == "" ||
		record.Token != strings.TrimSpace(record.Token) || len(record.Token) > callMaxFieldBytes ||
		strings.ContainsAny(record.Token, "\r\n\t") || record.ExpiresAtMs <= now.UnixMilli() ||
		time.UnixMilli(record.ExpiresAtMs).After(now.Add(callMaxRecordTTL)) {
		return false
	}
	if record.Kind == CallTokenKindStandard {
		return record.Platform == "android" && record.Environment == "" && record.Topic == "" &&
			record.CapabilityVersion == 0 && record.RefreshEpoch == 0
	}
	return record.Platform == "ios" &&
		(record.Environment == "sandbox" || record.Environment == "production") &&
		validNodeAPNSVoIPTopic(record.Topic) &&
		record.CapabilityVersion == CallIOSVoIPCapabilityVersion && record.RefreshEpoch > 0
}

func validNodeAPNSVoIPTopic(value string) bool {
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

func validNodeCallTokenKind(kind string) bool {
	return kind == CallTokenKindStandard || kind == CallTokenKindIOSVoIP
}

func validCallPeerID(value string) bool {
	if value == "" || value != strings.TrimSpace(value) {
		return false
	}
	_, err := peer.Decode(value)
	return err == nil
}

func validCallRandomID(value string) bool {
	if value == "" || value != strings.TrimSpace(value) || value != strings.ToLower(value) {
		return false
	}
	if len(value) == 32 {
		decoded, err := hex.DecodeString(value)
		return err == nil && len(decoded) == 16
	}
	parsed, err := uuid.Parse(value)
	return err == nil && parsed.Version() == 4 && parsed.String() == value
}

func canonicalNodeCallEndpoint(record CallEndpointRecord) ([]byte, error) {
	capabilities := append([]string(nil), record.Capabilities...)
	slices.Sort(capabilities)
	return json.Marshal(struct {
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
	}{
		Schema: CallEndpointSchema, Version: CallControlVersion,
		AccountPeerID: record.AccountPeerID, DevicePeerID: record.DevicePeerID,
		Capabilities: capabilities, Platform: record.Platform,
		ExpiresAtMs: record.ExpiresAtMs, PreferenceEpoch: record.PreferenceEpoch,
		DeviceKeyEpoch: record.DeviceKeyEpoch, RoutingHandle: record.RoutingHandle,
	})
}

func absCallDuration(value time.Duration) time.Duration {
	if value < 0 {
		return -value
	}
	return value
}
