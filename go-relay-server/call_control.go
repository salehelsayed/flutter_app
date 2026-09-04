package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
)

const (
	CallMailboxSchema  = "mknoon.call_mailbox.v1"
	CallEndpointSchema = "mknoon.call_endpoint_set.v1"
	CallWakeSchema     = "mknoon.call_wake_handle.v1"
	CallTokenSchema    = "mknoon.call_token.v1"
	CallControlVersion = 1

	CallMaxEnvelopeBytes                         = 96 * 1024
	callWakeBookkeepingTimeout                   = 2 * time.Second
	CallMaxEventsPerCall                         = 64
	CallMaxBytesPerCall                          = 256 * 1024
	CallMaxPendingHandles                        = 2
	CallMaxPreconnectTTL                         = 45 * time.Second
	CallReplayTombstoneTTL                       = 10 * time.Minute
	callMaxTypedRecordTTL                        = 90 * 24 * time.Hour
	callMaxWakeHandlesPerDevice                  = 512
	callMaxTerminalTombstonesPerRecipient        = 512
	callStoreRateWindow                          = time.Minute
	callStoreRateLimit                           = 120
	callMaxTokenBytes                            = 16 * 1024
	callMaxSignatureBytes                        = 16 * 1024
	callMaxCapabilities                          = 16
	callMaxRetrieveLimit                         = CallMaxEventsPerCall
	callWakeDispatchLease                        = 5 * time.Second
	callMaxWakeDispatchAttempts                  = 2
	callIOSVoIPCapabilityVersion          uint64 = 1
	callMaxAPNSTopicBytes                        = 255
)

const (
	CallStoreStatusStored    CallStoreStatus = "stored"
	CallStoreStatusDuplicate CallStoreStatus = "duplicate"

	CallTokenKindStandard CallTokenKind = "standard_call"
	CallTokenKindIOSVoIP  CallTokenKind = "ios_voip"
)

var (
	ErrCallBackendUnavailable = errors.New("call backend unavailable")
	ErrCallInvalidRequest     = errors.New("call request invalid")
	ErrCallUnauthorized       = errors.New("call request unauthorized")
	ErrCallIdentityConflict   = errors.New("call identity conflict")
	ErrCallReplay             = errors.New("call replay rejected")
	ErrCallExpiry             = errors.New("call expiry invalid")
	ErrCallEnvelopeTooLarge   = errors.New("call envelope too large")
	ErrCallRecipientCapacity  = errors.New("call recipient capacity reached")
	ErrCallEventCapacity      = errors.New("call event capacity reached")
	ErrCallByteCapacity       = errors.New("call byte capacity reached")
	ErrCallRateLimited        = errors.New("call rate limited")
	ErrCallStaleEpoch         = errors.New("call endpoint epoch stale")
	ErrCallTokenInvalid       = errors.New("call token invalid")
)

type CallStoreStatus string
type CallTokenKind string

type CallStoreRequest struct {
	RecipientDevicePeerID string
	CallHandle            string
	MessageID             string
	Envelope              []byte
	ExpiresAtMs           int64
	WakeHandle            string
}

type CallStoreReceipt struct {
	Schema         string
	Version        int
	StoreStatus    CallStoreStatus
	ReceiptAtMs    int64
	ExpiresAtMs    int64
	EventCount     int
	TotalBytes     int
	PendingHandles int
}

type CallMailboxEvent struct {
	CallHandle            string `json:"callHandle"`
	MessageID             string `json:"messageId"`
	SenderPeerID          string `json:"senderPeerId"`
	RecipientDevicePeerID string `json:"recipientDevicePeerId"`
	Envelope              []byte `json:"envelope"`
	ReceiptAtMs           int64  `json:"receiptAtMs"`
	ExpiresAtMs           int64  `json:"expiresAtMs"`
}

type CallRetrieveRequest struct {
	CallHandle string
	Limit      int
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
	CallHandle string
	MessageIDs []string
}

type CallCancelRequest struct {
	RecipientDevicePeerID string
	CallHandle            string
}

type CallEndpointRecord struct {
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
	Signature       []byte   `json:"signature"`
}

type CallWakeHandleRecord struct {
	AuthorizedSenderPeerID string
	WakeHandle             string
	ExpiresAtMs            int64
}

type CallTokenRecord struct {
	Schema            string        `json:"schema"`
	Version           int           `json:"version"`
	Kind              CallTokenKind `json:"kind"`
	Platform          string        `json:"platform"`
	Token             string        `json:"token"`
	ExpiresAtMs       int64         `json:"expiresAtMs"`
	Environment       string        `json:"environment,omitempty"`
	Topic             string        `json:"topic,omitempty"`
	CapabilityVersion uint64        `json:"capabilityVersion,omitempty"`
	RefreshEpoch      uint64        `json:"refreshEpoch,omitempty"`
	Generation        uint64        `json:"generation,omitempty"`
}

// CallWakeRoute holds provider material only between the durable call-token
// authority and the provider adapter. It is never logged or returned on wire.
type CallWakeRoute struct {
	Kind              CallTokenKind
	Platform          string
	Token             string
	Environment       string
	Topic             string
	CapabilityVersion uint64
	RefreshEpoch      uint64
	Generation        uint64
}

// CallWakePayload contains only recipient-generated opaque values and relay
// time. It cannot carry an account/device identity or encrypted envelope.
type CallWakePayload struct {
	CallHandle  string
	WakeHandle  string
	ExpiresAtMs int64
}

// CallWakeDispatcher must honor context cancellation and its deadline before
// entering and while waiting on the provider. The deadline is the call's hard
// expiry, after which Redis may remove every active-owner barrier.
type CallWakeDispatcher interface {
	DispatchCallWake(context.Context, CallWakeRoute, CallWakePayload) error
}

// CallEndpointSignatureVerifier proves that the ACCOUNT named by an endpoint
// record signed it. The device is proven separately by the authenticated
// connection. Verifying against the connection key alone let any peer publish
// an endpoint for any account and lock the owner out until the tombstone
// high-water expired.
type CallEndpointSignatureVerifier interface {
	VerifyCallEndpoint(accountPeerID string, canonicalRecord, signature []byte) bool
}

type libp2pCallEndpointSignatureVerifier struct{}

// connectionCallEndpointSignatureVerifier verifies with the authenticated
// connection key only when the record names the connected peer as its own
// account (the secure channel already proved that key belongs to that peer
// ID). A record for any other account must verify under that account's key.
type connectionCallEndpointSignatureVerifier struct {
	authenticatedPeerID string
	publicKey           libp2pcrypto.PubKey
}

func (v connectionCallEndpointSignatureVerifier) VerifyCallEndpoint(
	accountPeerID string,
	canonicalRecord, signature []byte,
) bool {
	if accountPeerID != v.authenticatedPeerID || v.publicKey == nil {
		return libp2pCallEndpointSignatureVerifier{}.VerifyCallEndpoint(
			accountPeerID, canonicalRecord, signature,
		)
	}
	verified, err := v.publicKey.Verify(canonicalRecord, signature)
	return err == nil && verified
}

func (libp2pCallEndpointSignatureVerifier) VerifyCallEndpoint(
	accountPeerID string,
	canonicalRecord, signature []byte,
) bool {
	id, err := peer.Decode(accountPeerID)
	if err != nil {
		return false
	}
	publicKey, err := id.ExtractPublicKey()
	if err != nil || publicKey == nil {
		return false
	}
	verified, err := publicKey.Verify(canonicalRecord, signature)
	return err == nil && verified
}

type CallControlService struct {
	backend                     *redisCallControlStore
	dispatcher                  CallWakeDispatcher
	now                         func() time.Time
	endpointVerifier            CallEndpointSignatureVerifier
	beforeWakeClaim             func()
	beforeWakeCurrent           func()
	beforeWakeDispatch          func()
	afterWakeDispatchOwned      func()
	afterWakeDispatchAuthorized func()
}

func NewCallControlService(
	backend *redisCallControlStore,
	dispatcher CallWakeDispatcher,
	now func() time.Time,
) *CallControlService {
	if now == nil {
		now = time.Now
	}
	return &CallControlService{
		backend: backend, dispatcher: dispatcher, now: now,
		endpointVerifier: libp2pCallEndpointSignatureVerifier{},
	}
}

func NewCallControlServiceWithVerifier(
	backend *redisCallControlStore,
	dispatcher CallWakeDispatcher,
	now func() time.Time,
	verifier CallEndpointSignatureVerifier,
) *CallControlService {
	service := NewCallControlService(backend, dispatcher, now)
	if verifier != nil {
		service.endpointVerifier = verifier
	}
	return service
}

func (s *CallControlService) Store(
	ctx context.Context,
	authenticatedSender string,
	request CallStoreRequest,
) (CallStoreReceipt, error) {
	now := s.nowTime()
	if s == nil || s.backend == nil {
		return CallStoreReceipt{}, ErrCallBackendUnavailable
	}
	// Phone clocks commonly run a few seconds ahead of the relay. A request
	// whose expiry merely overshoots the hard pre-connect bound is clamped to
	// it instead of rejected; the receipt echoes the clamped value.
	if maxExpiresAtMs := now.Add(CallMaxPreconnectTTL).UnixMilli(); request.ExpiresAtMs > maxExpiresAtMs {
		request.ExpiresAtMs = maxExpiresAtMs
	}
	if err := validateCallStoreRequest(authenticatedSender, request, now); err != nil {
		return CallStoreReceipt{}, err
	}
	receipt, err := s.backend.Store(ctx, authenticatedSender, request, now)
	if err != nil {
		return CallStoreReceipt{}, err
	}
	if (receipt.StoreStatus != CallStoreStatusStored && receipt.StoreStatus != CallStoreStatusDuplicate) ||
		s.dispatcher == nil {
		return receipt, nil
	}
	if s.beforeWakeClaim != nil {
		s.beforeWakeClaim()
	}
	wakeOwner := uuid.NewString()
	wakeNow := s.nowTime()
	route, allowed, err := s.backend.ClaimWake(ctx, authenticatedSender, request, wakeNow)
	if err != nil {
		return receipt, err
	}
	if !allowed || route == nil {
		return receipt, nil
	}
	if s.beforeWakeCurrent != nil {
		s.beforeWakeCurrent()
	}
	current, err := s.backend.WakeCurrent(ctx, authenticatedSender, request, *route, wakeOwner, wakeNow)
	if err != nil {
		return receipt, err
	}
	if !current {
		return receipt, nil
	}
	if s.beforeWakeDispatch != nil {
		s.beforeWakeDispatch()
	}
	current, err = s.backend.WakeDispatchOwned(
		ctx, authenticatedSender, request, wakeOwner, s.nowTime(),
	)
	if err != nil {
		return receipt, err
	}
	if !current {
		return receipt, nil
	}
	if s.afterWakeDispatchOwned != nil {
		s.afterWakeDispatchOwned()
	}
	// Authorization adds this owner to the bounded active set. Unlike a final
	// ownership check, that durable registration remains a terminalization
	// barrier across lease takeover until this provider invocation returns.
	dispatchDeadline := time.UnixMilli(receipt.ExpiresAtMs)
	authorizationNow := s.nowTime()
	dispatchCtx, cancelDispatch := context.WithDeadline(ctx, dispatchDeadline)
	defer cancelDispatch()
	// The handler's request context can expire while the push provider is
	// slow. Claim bookkeeping after the provider returns must still run, or
	// the claim stays owned until the call expires and every later ack or
	// cancel for it fails.
	bookkeepingCtx, cancelBookkeeping := context.WithTimeout(
		context.WithoutCancel(ctx), callWakeBookkeepingTimeout,
	)
	defer cancelBookkeeping()
	current, err = s.backend.AuthorizeWakeDispatch(
		ctx, authenticatedSender, request, wakeOwner, authorizationNow,
	)
	if err != nil {
		// An ambiguous authorization may have installed the active barrier,
		// but this invocation will not enter the provider after returning the
		// error. Release once; an unavailable Redis keeps the barrier fail-closed.
		_ = s.backend.ReleaseWakeDispatchAuthorization(
			bookkeepingCtx, authenticatedSender, request, wakeOwner,
		)
		return receipt, err
	}
	if !current {
		return receipt, nil
	}
	if s.afterWakeDispatchAuthorized != nil {
		s.afterWakeDispatchAuthorized()
	}
	dispatchErr := dispatchCtx.Err()
	if !s.nowTime().Before(dispatchDeadline) {
		dispatchErr = context.DeadlineExceeded
	}
	if dispatchErr == nil {
		dispatchErr = s.dispatcher.DispatchCallWake(dispatchCtx, *route, CallWakePayload{
			CallHandle: request.CallHandle, WakeHandle: request.WakeHandle,
			ExpiresAtMs: receipt.ExpiresAtMs,
		})
	}
	if err := s.backend.CompleteWake(bookkeepingCtx, authenticatedSender, request, wakeOwner); err != nil {
		// The provider has returned, so this owner can no longer enter it even
		// when the completion transaction's outcome was ambiguous. A separate
		// best-effort release preserves recovery without dropping the barrier
		// before provider return; failure leaves it fail-closed until hard TTL.
		_ = s.backend.ReleaseWakeDispatchAuthorization(
			bookkeepingCtx, authenticatedSender, request, wakeOwner,
		)
		return receipt, err
	}
	if errors.Is(dispatchErr, ErrCallTokenInvalid) {
		if cleanupErr := s.backend.RevokeCallTokenIfMatch(
			bookkeepingCtx, request.RecipientDevicePeerID, *route,
		); cleanupErr != nil {
			return receipt, cleanupErr
		}
	}
	return receipt, nil
}

func (s *CallControlService) Retrieve(
	ctx context.Context,
	authenticatedRecipient string,
	request CallRetrieveRequest,
) (CallRetrieveResult, error) {
	now := s.nowTime()
	if s == nil || s.backend == nil {
		return CallRetrieveResult{}, ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedRecipient) ||
		(request.CallHandle != "" && !validCallRandomID(request.CallHandle)) ||
		request.Limit < 0 {
		return CallRetrieveResult{}, ErrCallInvalidRequest
	}
	limit := request.Limit
	if limit == 0 || limit > callMaxRetrieveLimit {
		limit = callMaxRetrieveLimit
	}
	return s.backend.Retrieve(ctx, authenticatedRecipient, request.CallHandle, limit, now)
}

func (s *CallControlService) Ack(
	ctx context.Context,
	authenticatedRecipient string,
	request CallAckRequest,
) (int, error) {
	if s == nil || s.backend == nil {
		return 0, ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedRecipient) || !validCallRandomID(request.CallHandle) ||
		len(request.MessageIDs) == 0 || len(request.MessageIDs) > CallMaxEventsPerCall {
		return 0, ErrCallInvalidRequest
	}
	seen := make(map[string]struct{}, len(request.MessageIDs))
	for _, messageID := range request.MessageIDs {
		if !validCallRandomID(messageID) {
			return 0, ErrCallInvalidRequest
		}
		seen[messageID] = struct{}{}
	}
	return s.backend.Ack(ctx, authenticatedRecipient, request.CallHandle, seen, s.nowTime())
}

func (s *CallControlService) Cancel(
	ctx context.Context,
	authenticatedSender string,
	request CallCancelRequest,
) error {
	if s == nil || s.backend == nil {
		return ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedSender) || !validPeerID(request.RecipientDevicePeerID) ||
		!validCallRandomID(request.CallHandle) {
		return ErrCallInvalidRequest
	}
	return s.backend.Cancel(ctx, authenticatedSender, request, s.nowTime())
}

func (s *CallControlService) SetEndpoint(
	ctx context.Context,
	authenticatedDevice string,
	record CallEndpointRecord,
) error {
	return s.setEndpoint(ctx, authenticatedDevice, record, s.endpointVerifier)
}

func (s *CallControlService) setEndpoint(
	ctx context.Context,
	authenticatedDevice string,
	record CallEndpointRecord,
	verifier CallEndpointSignatureVerifier,
) error {
	if s == nil || s.backend == nil {
		return ErrCallBackendUnavailable
	}
	now := s.nowTime()
	if err := validateCallEndpoint(authenticatedDevice, record, now); err != nil {
		return err
	}
	record.Schema = CallEndpointSchema
	record.Version = CallControlVersion
	record.Capabilities = append([]string(nil), record.Capabilities...)
	slices.Sort(record.Capabilities)
	canonical, err := canonicalCallEndpointRecord(record)
	if err != nil || verifier == nil ||
		!verifier.VerifyCallEndpoint(record.AccountPeerID, canonical, record.Signature) {
		return ErrCallUnauthorized
	}
	return s.backend.SetEndpoint(ctx, record, now)
}

func (s *CallControlService) GetEndpoint(
	ctx context.Context,
	authenticatedRequester string,
	accountPeerID string,
) (*CallEndpointRecord, error) {
	if s == nil || s.backend == nil {
		return nil, ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedRequester) || !validPeerID(accountPeerID) {
		return nil, ErrCallInvalidRequest
	}
	return s.backend.GetEndpoint(ctx, accountPeerID, s.nowTime())
}

func (s *CallControlService) RevokeEndpoint(
	ctx context.Context,
	authenticatedDevice string,
	accountPeerID string,
	preferenceEpoch uint64,
) error {
	if s == nil || s.backend == nil {
		return ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedDevice) || !validPeerID(accountPeerID) || preferenceEpoch == 0 {
		return ErrCallInvalidRequest
	}
	return s.backend.RevokeEndpoint(ctx, authenticatedDevice, accountPeerID, preferenceEpoch)
}

func (s *CallControlService) SetWakeHandle(
	ctx context.Context,
	authenticatedRecipient string,
	record CallWakeHandleRecord,
) error {
	if s == nil || s.backend == nil {
		return ErrCallBackendUnavailable
	}
	now := s.nowTime()
	if !validPeerID(authenticatedRecipient) || !validPeerID(record.AuthorizedSenderPeerID) ||
		authenticatedRecipient == record.AuthorizedSenderPeerID ||
		!validCallRandomID(record.WakeHandle) ||
		!validTypedRecordExpiry(record.ExpiresAtMs, now) {
		return ErrCallInvalidRequest
	}
	return s.backend.SetWakeHandle(ctx, authenticatedRecipient, record, now)
}

func (s *CallControlService) RevokeWakeHandle(
	ctx context.Context,
	authenticatedRecipient string,
	authorizedSenderPeerID string,
) error {
	if s == nil || s.backend == nil {
		return ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedRecipient) || !validPeerID(authorizedSenderPeerID) {
		return ErrCallInvalidRequest
	}
	return s.backend.RevokeWakeHandle(ctx, authenticatedRecipient, authorizedSenderPeerID)
}

func (s *CallControlService) SetCallToken(
	ctx context.Context,
	authenticatedDevice string,
	record CallTokenRecord,
) error {
	_, err := s.SetCallTokenWithResult(ctx, authenticatedDevice, record)
	return err
}

func (s *CallControlService) SetCallTokenWithResult(
	ctx context.Context,
	authenticatedDevice string,
	record CallTokenRecord,
) (*CallTokenRecord, error) {
	if s == nil || s.backend == nil {
		return nil, ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedDevice) || !validCallTokenRegistration(record, s.nowTime()) {
		return nil, ErrCallInvalidRequest
	}
	record.Schema = CallTokenSchema
	record.Version = CallControlVersion
	return s.backend.SetCallToken(ctx, authenticatedDevice, record)
}

func (s *CallControlService) GetCallToken(
	ctx context.Context,
	authenticatedDevice string,
	kind CallTokenKind,
) (*CallTokenRecord, error) {
	if s == nil || s.backend == nil {
		return nil, ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedDevice) || !validCallTokenKind(kind) {
		return nil, ErrCallInvalidRequest
	}
	return s.backend.GetCallToken(ctx, authenticatedDevice, kind, s.nowTime())
}

func (s *CallControlService) RevokeCallToken(
	ctx context.Context,
	authenticatedDevice string,
	kind CallTokenKind,
) error {
	if s == nil || s.backend == nil {
		return ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedDevice) || !validCallTokenKind(kind) {
		return ErrCallInvalidRequest
	}
	return s.backend.RevokeCallToken(ctx, authenticatedDevice, kind)
}

func (s *CallControlService) RevokeCallTokenRefreshEpoch(
	ctx context.Context,
	authenticatedDevice string,
	kind CallTokenKind,
	refreshEpoch uint64,
) (bool, error) {
	if s == nil || s.backend == nil {
		return false, ErrCallBackendUnavailable
	}
	if !validPeerID(authenticatedDevice) || kind != CallTokenKindIOSVoIP || refreshEpoch == 0 {
		return false, ErrCallInvalidRequest
	}
	return s.backend.RevokeCallTokenRefreshEpochIfMatch(ctx, authenticatedDevice, kind, refreshEpoch)
}

func (s *CallControlService) nowTime() time.Time {
	if s != nil && s.now != nil {
		return s.now().UTC()
	}
	return time.Now().UTC()
}

func validateCallStoreRequest(sender string, request CallStoreRequest, now time.Time) error {
	if !validPeerID(sender) || !validPeerID(request.RecipientDevicePeerID) ||
		sender == request.RecipientDevicePeerID || !validCallRandomID(request.CallHandle) ||
		!validCallRandomID(request.MessageID) || !validCallRandomID(request.WakeHandle) ||
		len(request.Envelope) == 0 || !utf8.Valid(request.Envelope) {
		return ErrCallInvalidRequest
	}
	if len(request.Envelope) > CallMaxEnvelopeBytes {
		return ErrCallEnvelopeTooLarge
	}
	expiresAt := time.UnixMilli(request.ExpiresAtMs)
	if !expiresAt.After(now) || expiresAt.After(now.Add(CallMaxPreconnectTTL)) {
		return ErrCallExpiry
	}
	return nil
}

func validateCallEndpoint(authenticatedDevice string, record CallEndpointRecord, now time.Time) error {
	if !validPeerID(authenticatedDevice) || !validPeerID(record.AccountPeerID) ||
		!validPeerID(record.DevicePeerID) || authenticatedDevice != record.DevicePeerID ||
		(record.Platform != "android" && record.Platform != "ios") ||
		!validTypedRecordExpiry(record.ExpiresAtMs, now) || record.PreferenceEpoch == 0 ||
		record.DeviceKeyEpoch == 0 || !validCallRandomID(record.RoutingHandle) ||
		len(record.Signature) == 0 || len(record.Signature) > callMaxSignatureBytes ||
		len(record.Capabilities) == 0 || len(record.Capabilities) > callMaxCapabilities {
		return ErrCallInvalidRequest
	}
	seen := make(map[string]struct{}, len(record.Capabilities))
	hasVoice := false
	for _, capability := range record.Capabilities {
		if capability == "" || capability != strings.TrimSpace(capability) || len(capability) > 64 {
			return ErrCallInvalidRequest
		}
		if _, duplicate := seen[capability]; duplicate {
			return ErrCallInvalidRequest
		}
		seen[capability] = struct{}{}
		hasVoice = hasVoice || capability == "voice_call_v1"
	}
	if !hasVoice {
		return ErrCallInvalidRequest
	}
	return nil
}

func validCallTokenRegistration(record CallTokenRecord, now time.Time) bool {
	if record.Schema != "" || record.Version != 0 || record.Generation != 0 {
		return false
	}
	return validCallTokenFields(record, now, false)
}

func validStoredCallToken(record CallTokenRecord, now time.Time) bool {
	return validStoredCallTokenShape(record) && validTypedRecordExpiry(record.ExpiresAtMs, now)
}

func validStoredCallTokenShape(record CallTokenRecord) bool {
	if record.Schema != CallTokenSchema || record.Version != CallControlVersion ||
		record.ExpiresAtMs <= 0 {
		return false
	}
	return validCallTokenFields(record, time.UnixMilli(record.ExpiresAtMs).Add(-time.Millisecond), true)
}

func validCallTokenFields(record CallTokenRecord, now time.Time, stored bool) bool {
	if !validCallTokenKind(record.Kind) || record.Token == "" ||
		record.Token != strings.TrimSpace(record.Token) || len(record.Token) > callMaxTokenBytes ||
		strings.ContainsAny(record.Token, "\r\n\t") || !validTypedRecordExpiry(record.ExpiresAtMs, now) {
		return false
	}
	if record.Kind == CallTokenKindStandard {
		return record.Platform == "android" && record.Environment == "" && record.Topic == "" &&
			record.CapabilityVersion == 0 && record.RefreshEpoch == 0 && record.Generation == 0
	}
	if record.Platform != "ios" || !validAPNSVoIPEnvironment(record.Environment) ||
		!validAPNSVoIPTopic(record.Topic) ||
		record.CapabilityVersion != callIOSVoIPCapabilityVersion || record.RefreshEpoch == 0 {
		return false
	}
	if stored {
		return record.Generation > 0
	}
	return record.Generation == 0
}

func validAPNSVoIPEnvironment(value string) bool {
	return value == "sandbox" || value == "production"
}

func validAPNSVoIPTopic(value string) bool {
	if value == "" || value != strings.TrimSpace(value) || len(value) > callMaxAPNSTopicBytes ||
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

func validStoredIOSVoIPTokenBinding(record CallTokenRecord) bool {
	return record.Schema == CallTokenSchema && record.Version == CallControlVersion &&
		record.Kind == CallTokenKindIOSVoIP && record.Platform == "ios" &&
		record.Token != "" && record.Token == strings.TrimSpace(record.Token) &&
		len(record.Token) <= callMaxTokenBytes && !strings.ContainsAny(record.Token, "\r\n\t") &&
		validAPNSVoIPEnvironment(record.Environment) && validAPNSVoIPTopic(record.Topic) &&
		record.CapabilityVersion == callIOSVoIPCapabilityVersion &&
		record.RefreshEpoch > 0 && record.Generation > 0
}

func sameCallTokenRegistration(existing, incoming CallTokenRecord) bool {
	existing.Generation = 0
	incoming.Generation = 0
	return existing == incoming
}

func sameCallTokenRefreshIdentity(existing, incoming CallTokenRecord) bool {
	existing.Generation = 0
	incoming.Generation = 0
	existing.ExpiresAtMs = 0
	incoming.ExpiresAtMs = 0
	return existing == incoming
}

func callWakeRouteFromToken(record CallTokenRecord) CallWakeRoute {
	return CallWakeRoute{
		Kind: record.Kind, Platform: record.Platform, Token: record.Token,
		Environment: record.Environment, Topic: record.Topic,
		CapabilityVersion: record.CapabilityVersion,
		RefreshEpoch:      record.RefreshEpoch, Generation: record.Generation,
	}
}

func callWakeRouteMatchesToken(route CallWakeRoute, record CallTokenRecord) bool {
	return route.Kind == record.Kind && route.Platform == record.Platform &&
		route.Token == record.Token && route.Environment == record.Environment &&
		route.Topic == record.Topic && route.CapabilityVersion == record.CapabilityVersion &&
		route.RefreshEpoch == record.RefreshEpoch && route.Generation == record.Generation
}

func validCallTokenKind(kind CallTokenKind) bool {
	return kind == CallTokenKindStandard || kind == CallTokenKindIOSVoIP
}

func validTypedRecordExpiry(expiresAtMs int64, now time.Time) bool {
	expiresAt := time.UnixMilli(expiresAtMs)
	return expiresAt.After(now) && !expiresAt.After(now.Add(callMaxTypedRecordTTL))
}

func validPeerID(value string) bool {
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

func callEventDigest(sender string, request CallStoreRequest) string {
	h := sha256.New()
	for _, value := range []string{
		"mknoon.call-event.v1", sender, request.RecipientDevicePeerID,
		request.CallHandle, request.MessageID, fmt.Sprintf("%d", request.ExpiresAtMs),
	} {
		_, _ = h.Write([]byte(value))
		_, _ = h.Write([]byte{0})
	}
	_, _ = h.Write(request.Envelope)
	return hex.EncodeToString(h.Sum(nil))
}

func callOpaqueDigest(domain, value string) string {
	digest := sha256.Sum256([]byte(domain + "\x00" + value))
	return hex.EncodeToString(digest[:])
}

func marshalCallRecord(value any) ([]byte, error) {
	data, err := json.Marshal(value)
	if err != nil {
		return nil, fmt.Errorf("%w: encode record", ErrCallBackendUnavailable)
	}
	return data, nil
}

func canonicalCallEndpointRecord(record CallEndpointRecord) ([]byte, error) {
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
