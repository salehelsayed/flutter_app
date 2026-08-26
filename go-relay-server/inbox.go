package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"

	"github.com/google/uuid"
)

const (
	InboxProtocol      = "/mknoon/inbox/1.0.0"
	maxFrameLen        = 128 * 1024 // 128 KB
	maxMessagesPerPeer = 100
	maxMessageAge      = 7 * 24 * time.Hour

	// Group inbox constants.
	maxMessagesPerGroup = 500
	groupMessageTTL     = 7 * 24 * time.Hour

	pushNotificationTitle       = "New Message"
	pushNotificationBody        = "You have a new message"
	pushNotificationChannelID   = "mknoon_messages"
	pushNotificationSound       = "default"
	contactRequestPushTitle     = "New Contact Request"
	contactRequestPushBody      = "Open Mknoon to respond"
	groupInvitePushTitle        = "Group Invite"
	groupInvitePushBody         = "Open Mknoon to review"
	groupInviteAndroidTagPrefix = "mknoon_group_invite_"
	introPushNotificationTitle  = "New Introduction"
	introPushNotificationBody   = "Open Mknoon to review"
	// 252: role-neutral acceptance copy. Applied only when the canonical
	// envelope message ID validates as an `accept` (and, for v1 plaintext,
	// agrees with the cleartext payload action). No responder identity is
	// exposed; the client resolves the exact context locally on tap.
	introAcceptPushNotificationTitle = "Introduction accepted"
	introAcceptPushNotificationBody  = "Someone accepted an introduction involving you."

	// maxPushDataBytes caps the assembled FCM `data` payload. FCM's 4096-byte
	// "Message is too large" enforcement is SERVER-side (the Admin SDK performs
	// no client-side size validation) and spans a quantity that includes BOTH
	// platform copies of a dual-copy request — live sends whose data map AND
	// marshalled per-platform legs each passed these budgets were still
	// rejected (2026-07-31) until the send sites began projecting a single
	// platform copy per registered token (projectPushMessageForPlatform).
	// Per-leg budgets therefore remain necessary but NOT sufficient. When the
	// assembled data would exceed this budget we drop the encrypted fields and
	// emit a visible generic fallback instead.
	maxPushDataBytes = 4000
	// Measure the complete platform payloads, not only the raw data values.
	// Keeping a 296-byte margin below the provider's 4096-byte ceiling absorbs
	// encoding differences between the Admin SDK request and the final platform
	// payload without sacrificing ordinary encrypted previews.
	maxProviderPayloadBytes = 3800
)

func defaultPushRetryDelays() []time.Duration {
	return []time.Duration{
		250 * time.Millisecond,
		1 * time.Second,
	}
}

// --- Push service ---

type PushService struct {
	client                             *messaging.Client
	tokenBackend                       PushTokenBackend
	sender                             func(context.Context, *messaging.Message) (string, error)
	retryDelays                        []time.Duration
	now                                func() time.Time
	newGroupMessageDispatchID          groupMessageDispatchIDGenerator
	journalGroupMessageProviderAttempt groupMessageProviderAttemptJournal
	groupMessageDispatchAdmission      groupMessageDispatchAdmissionBackend
}

type pushMessageFactory func() *messaging.Message

type resolvedPushMessageFactory func(platform string) (*messaging.Message, error)

type pushMessageProjector func(
	message *messaging.Message,
	platform string,
) *messaging.Message

// pushDeliveryResult is the deliberately coarse provider boundary shared by
// immediate Plan-368 sends and the bounded wake-outcome coordinator. It never
// carries provider, route, peer, or event material.
type pushDeliveryResult string

const (
	pushDeliveryAccepted   pushDeliveryResult = "accepted"
	pushDeliveryPermanent  pushDeliveryResult = "permanent"
	pushDeliveryRetryable  pushDeliveryResult = "retryable"
	pushDeliverySuppressed pushDeliveryResult = "suppressed"
)

type groupMessageDispatchSource string

type groupMessageDispatchIDGenerator func() (string, error)

type groupMessageProviderAttemptJournal func(groupMessageProviderAttemptJournalRecord)

type groupMessageDispatchProjection struct {
	Source groupMessageDispatchSource
	ID     string
}

type groupMessageProviderAttemptJournalRecord struct {
	Schema                          string `json:"schema"`
	Source                          string `json:"source"`
	Provenance                      string `json:"provenance"`
	DispatchCorrelationSha256       string `json:"dispatchCorrelationSha256,omitempty"`
	ClaimedCollapseIdentifierSha256 string `json:"claimedCollapseIdentifierSha256,omitempty"`
	ProviderAttempt                 int    `json:"providerAttempt"`
	AttemptKind                     string `json:"attemptKind"`
	Outcome                         string `json:"outcome"`
	FirebaseResponseNameSha256      string `json:"firebaseResponseNameSha256,omitempty"`
	ProviderMessageIDSha256         string `json:"providerMessageIdSha256,omitempty"`
}

const (
	groupMessageDispatchSourceInbox   groupMessageDispatchSource = "group_inbox"
	groupMessageDispatchSourceContent groupMessageDispatchSource = "group_content"

	groupMessageDispatchClaimKey     = "mknoon_group_message_dispatch_source"
	groupMessageDispatchIDKey        = "mknoon_group_message_dispatch_id"
	groupMessageCollapseClaimKey     = "mknoon_group_message_collapse_id"
	groupMessageDispatchClaimInbox   = "group_inbox_v1"
	groupMessageDispatchClaimContent = "group_content_v1"

	groupMessageProviderAttemptJournalSchema   = "mknoon.relay.group-message-provider-attempt.v1"
	groupMessageProviderProvenanceComplete     = "complete"
	groupMessageProviderProvenanceUnavailable  = "unavailable"
	groupMessageProviderAttemptPrimary         = "primary"
	groupMessageProviderAttemptStrictFallback  = "strict_fallback"
	groupMessageProviderOutcomeAccepted        = "accepted"
	groupMessageProviderOutcomePayloadTooLarge = "payload_too_large"
	groupMessageProviderOutcomePermanent       = "permanent"
	groupMessageProviderOutcomeRetryable       = "retryable"
)

func (source groupMessageDispatchSource) claim() string {
	switch source {
	case groupMessageDispatchSourceInbox:
		return groupMessageDispatchClaimInbox
	case groupMessageDispatchSourceContent:
		return groupMessageDispatchClaimContent
	default:
		return ""
	}
}

func groupMessageDispatchSourceFromClaim(claim string) (groupMessageDispatchSource, bool) {
	switch claim {
	case groupMessageDispatchClaimInbox:
		return groupMessageDispatchSourceInbox, true
	case groupMessageDispatchClaimContent:
		return groupMessageDispatchSourceContent, true
	default:
		return "", false
	}
}

func defaultGroupMessageDispatchIDGenerator() (string, error) {
	value, err := uuid.NewRandom()
	if err != nil {
		return "", err
	}
	return value.String(), nil
}

func canonicalGroupMessageDispatchID(value string) bool {
	if value == "" || value != strings.TrimSpace(value) || value != strings.ToLower(value) {
		return false
	}
	parsed, err := uuid.Parse(value)
	return err == nil && parsed.Version() == 4 && parsed.String() == value
}

func canonicalGroupMessageCollapseClaim(value string) bool {
	return value != "" && value == strings.TrimSpace(value) && len([]byte(value)) <= 64
}

func normalizedFirebaseProviderMessageID(value string) string {
	if value == "" || value != strings.TrimSpace(value) {
		return ""
	}
	segments := strings.Split(value, "/")
	if len(segments) != 4 || segments[0] != "projects" || segments[1] == "" ||
		segments[2] != "messages" || segments[3] == "" {
		return ""
	}
	return segments[3]
}

func defaultGroupMessageProviderAttemptJournal(record groupMessageProviderAttemptJournalRecord) {
	payload, err := json.Marshal(record)
	if err != nil {
		log.Printf("[GROUP_MESSAGE_PROVIDER_ATTEMPT] outcome=journal_encoding_failed")
		return
	}
	log.Printf("[GROUP_MESSAGE_PROVIDER_ATTEMPT] %s", payload)
}

func (ps *PushService) groupMessageDispatchProjection(source groupMessageDispatchSource) groupMessageDispatchProjection {
	projection := groupMessageDispatchProjection{Source: source}
	generator := defaultGroupMessageDispatchIDGenerator
	if ps != nil && ps.newGroupMessageDispatchID != nil {
		generator = ps.newGroupMessageDispatchID
	}
	value, err := generator()
	if err == nil && canonicalGroupMessageDispatchID(value) {
		projection.ID = value
	}
	return projection
}

func groupMessageProviderAttemptBase(
	message *messaging.Message,
) (groupMessageProviderAttemptJournalRecord, bool) {
	if message == nil || message.APNS == nil || message.APNS.Payload == nil {
		return groupMessageProviderAttemptJournalRecord{}, false
	}
	claim, _ := message.APNS.Payload.CustomData[groupMessageDispatchClaimKey].(string)
	source, ok := groupMessageDispatchSourceFromClaim(claim)
	if !ok {
		return groupMessageProviderAttemptJournalRecord{}, false
	}
	record := groupMessageProviderAttemptJournalRecord{
		Schema:     groupMessageProviderAttemptJournalSchema,
		Source:     string(source),
		Provenance: groupMessageProviderProvenanceUnavailable,
	}
	dispatchID, _ := message.APNS.Payload.CustomData[groupMessageDispatchIDKey].(string)
	claimedCollapse, _ := message.APNS.Payload.CustomData[groupMessageCollapseClaimKey].(string)
	headerCollapse := message.APNS.Headers["apns-collapse-id"]
	if canonicalGroupMessageDispatchID(dispatchID) &&
		canonicalGroupMessageCollapseClaim(claimedCollapse) &&
		headerCollapse == claimedCollapse {
		record.Provenance = groupMessageProviderProvenanceComplete
		record.DispatchCorrelationSha256 = sha256Hex(dispatchID)
		record.ClaimedCollapseIdentifierSha256 = sha256Hex(claimedCollapse)
	}
	return record, true
}

func groupMessageProviderOutcome(err error) string {
	if err == nil {
		return groupMessageProviderOutcomeAccepted
	}
	if isPayloadTooLargeError(err) {
		return groupMessageProviderOutcomePayloadTooLarge
	}
	if permanentPushErrorReason(err) != "" {
		return groupMessageProviderOutcomePermanent
	}
	return groupMessageProviderOutcomeRetryable
}

func (ps *PushService) recordGroupMessageProviderAttempt(
	message *messaging.Message,
	providerResponseName string,
	providerErr error,
	providerAttempt int,
	attemptKind string,
) {
	record, ok := groupMessageProviderAttemptBase(message)
	if !ok {
		return
	}
	record.ProviderAttempt = providerAttempt
	record.AttemptKind = attemptKind
	record.Outcome = groupMessageProviderOutcome(providerErr)
	if providerErr == nil && providerResponseName != "" {
		record.FirebaseResponseNameSha256 = sha256Hex(providerResponseName)
		if providerID := normalizedFirebaseProviderMessageID(providerResponseName); providerID != "" {
			record.ProviderMessageIDSha256 = sha256Hex(providerID)
		}
	}
	journal := defaultGroupMessageProviderAttemptJournal
	if ps != nil && ps.journalGroupMessageProviderAttempt != nil {
		journal = ps.journalGroupMessageProviderAttempt
	}
	journal(record)
}

func recordGroupMessageDispatch(source groupMessageDispatchSource, result pushDeliveryResult) {
	if source.claim() == "" {
		return
	}
	terminal := "failed"
	switch result {
	case pushDeliveryAccepted:
		terminal = "accepted"
	case pushDeliverySuppressed:
		terminal = "suppressed"
	}
	groupMessageDispatchCounter.WithLabelValues(string(source), terminal).Inc()
}

// The resolver gateway already returns errors for route selection/build
// failures. These private sentinels let that same error channel carry the
// coarse provider disposition without changing mailboxDirty's Plan-368 API.
// sendSelectedPushThroughGateway consumes them before its ordinary route-error
// accounting, so the incumbent logs and metrics remain unchanged.
var (
	errPushDeliveryPermanent  = errors.New("push delivery permanently rejected")
	errPushDeliveryRetryable  = errors.New("push delivery retryable")
	errPushDeliverySuppressed = errors.New("duplicate group-message provider dispatch suppressed")
)

func pushDeliveryResultError(result pushDeliveryResult) error {
	switch result {
	case pushDeliveryAccepted:
		return nil
	case pushDeliveryPermanent:
		return errPushDeliveryPermanent
	case pushDeliverySuppressed:
		return errPushDeliverySuppressed
	default:
		return errPushDeliveryRetryable
	}
}

type tokenEntry struct {
	Token        string
	Platform     string
	Capabilities []string `json:"Capabilities,omitempty"`
	UpdatedAt    time.Time
}

func NewPushService(ctx context.Context, serviceAccountPath string) *PushService {
	return newPushServiceWithTokenBackend(ctx, serviceAccountPath, newMemoryPushTokenStore())
}

func newPushServiceWithTokenBackend(
	ctx context.Context,
	serviceAccountPath string,
	tokenBackend PushTokenBackend,
) *PushService {
	ps := &PushService{
		tokenBackend:                       tokenBackend,
		retryDelays:                        defaultPushRetryDelays(),
		now:                                time.Now,
		newGroupMessageDispatchID:          defaultGroupMessageDispatchIDGenerator,
		journalGroupMessageProviderAttempt: defaultGroupMessageProviderAttemptJournal,
		groupMessageDispatchAdmission: newMemoryGroupMessageDispatchAdmissionBackend(
			groupMessageDispatchAdmissionTTL,
		),
	}

	opt := option.WithCredentialsFile(serviceAccountPath)
	app, err := firebase.NewApp(ctx, nil, opt)
	if err != nil {
		log.Printf("[PUSH] outcome=provider_init_failed stage=firebase_app")
		return ps
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		log.Printf("[PUSH] outcome=provider_init_failed stage=messaging_client")
		return ps
	}

	ps.client = client
	log.Println("[PUSH] outcome=provider_initialized")
	return ps
}

// NewPushServiceWithBackend creates a PushService with a custom token backend.
func NewPushServiceWithBackend(tokenBackend PushTokenBackend) *PushService {
	return &PushService{
		tokenBackend:                       tokenBackend,
		retryDelays:                        defaultPushRetryDelays(),
		now:                                time.Now,
		newGroupMessageDispatchID:          defaultGroupMessageDispatchIDGenerator,
		journalGroupMessageProviderAttempt: defaultGroupMessageProviderAttemptJournal,
		groupMessageDispatchAdmission: newMemoryGroupMessageDispatchAdmissionBackend(
			groupMessageDispatchAdmissionTTL,
		),
	}
}

func (ps *PushService) Status() string {
	if ps.client != nil {
		return "enabled"
	}
	return "disabled (no service account)"
}

func (ps *PushService) RegisterToken(
	peerId,
	token,
	platform string,
	capabilities ...string,
) error {
	if err := ps.tokenBackend.RegisterToken(peerId, token, platform, capabilities...); err != nil {
		return fmt.Errorf("persist push token: %w", err)
	}
	log.Printf("[PUSH] outcome=registered")
	return nil
}

func (ps *PushService) UnregisterToken(peerId string) error {
	if err := ps.tokenBackend.UnregisterToken(peerId); err != nil {
		return fmt.Errorf("delete push route: %w", err)
	}
	log.Printf("[PUSH] outcome=unregistered")
	return nil
}

func (ps *PushService) selectPushRoute(peerID, requiredCapability string) (*pushRouteLease, error) {
	if ps == nil || ps.tokenBackend == nil {
		return nil, errors.New("push route backend unavailable")
	}
	route, err := ps.tokenBackend.LookupRoute(peerID)
	if err != nil || route == nil {
		return route, err
	}
	if requiredCapability != "" && !route.hasCapability(requiredCapability) {
		return nil, nil
	}
	copy := copyPushRouteLease(*route)
	return &copy, nil
}

// sendPushRouteThroughGateway is the sole production resolver of provider
// material. Both rich compatibility sends and fixed mailbox-dirty sends enter
// with an immutable opaque lease; provider token/platform values exist only
// inside this function and its message factory.
func (ps *PushService) sendPushRouteThroughGateway(
	ctx context.Context,
	route pushRouteLease,
	buildMessage resolvedPushMessageFactory,
	allowStrictFallback bool,
	admissionIdentities ...*groupMessageDispatchAdmissionIdentity,
) error {
	var admissionIdentity *groupMessageDispatchAdmissionIdentity
	if len(admissionIdentities) > 0 {
		admissionIdentity = admissionIdentities[0]
	}
	if ps == nil || ps.tokenBackend == nil {
		return errors.New("push route backend unavailable")
	}
	target, err := ps.tokenBackend.ResolveRoute(route)
	if err != nil {
		return err
	}
	if target == nil {
		return errors.New("push route resolved without a provider target")
	}
	draft, err := buildMessage(target.Platform)
	if err != nil {
		return err
	}
	if draft == nil {
		return pushDeliveryResultError(
			ps.sendWithRetry(ctx, nil, target.Route, allowStrictFallback),
		)
	}
	providerMessage := *draft
	providerMessage.Token = target.Token

	// Provider-unavailable is definitively pre-attempt and must not strand an
	// admission claim. Preserve sendWithRetry's incumbent metrics/logging while
	// keeping the exact key available for a later healthy logical adapter.
	if ps.sender == nil && ps.client == nil {
		return pushDeliveryResultError(
			ps.sendWithRetry(ctx, &providerMessage, target.Route, allowStrictFallback),
		)
	}

	var admissionLease *groupMessageDispatchAdmissionLease
	if admissionIdentity != nil && strings.EqualFold(strings.TrimSpace(target.Platform), "ios") {
		if ps.groupMessageDispatchAdmission == nil {
			groupMessageDispatchAdmissionCounter.WithLabelValues("error").Inc()
			log.Printf("[GROUP_MESSAGE_DISPATCH_ADMISSION] outcome=backend_unavailable")
			return errPushDeliverySuppressed
		}
		lease, acquired, acquireErr := ps.groupMessageDispatchAdmission.TryAcquire(
			ctx,
			*admissionIdentity,
		)
		if acquireErr != nil {
			groupMessageDispatchAdmissionCounter.WithLabelValues("error").Inc()
			log.Printf("[GROUP_MESSAGE_DISPATCH_ADMISSION] outcome=claim_failed")
			return errPushDeliverySuppressed
		}
		if !acquired {
			groupMessageDispatchAdmissionCounter.WithLabelValues("suppressed").Inc()
			log.Printf("[GROUP_MESSAGE_DISPATCH_ADMISSION] outcome=duplicate_suppressed")
			return errPushDeliverySuppressed
		}
		groupMessageDispatchAdmissionCounter.WithLabelValues("acquired").Inc()
		admissionLease = &lease
	}

	result := ps.sendWithRetry(ctx, &providerMessage, target.Route, allowStrictFallback)
	if admissionLease != nil && result == pushDeliveryPermanent {
		if err := ps.groupMessageDispatchAdmission.Release(ctx, *admissionLease); err != nil {
			groupMessageDispatchAdmissionCounter.WithLabelValues("release_failed").Inc()
			log.Printf("[GROUP_MESSAGE_DISPATCH_ADMISSION] outcome=release_failed")
		} else {
			groupMessageDispatchAdmissionCounter.WithLabelValues("released").Inc()
			log.Printf("[GROUP_MESSAGE_DISPATCH_ADMISSION] outcome=released_definitive_rejection")
		}
	}
	return pushDeliveryResultError(result)
}

func (ps *PushService) sendRichPushThroughGateway(
	ctx context.Context,
	route pushRouteLease,
	buildMessage pushMessageFactory,
	projectMessage ...pushMessageProjector,
) error {
	return ps.sendPushRouteThroughGateway(
		ctx,
		route,
		func(platform string) (*messaging.Message, error) {
			var draft *messaging.Message
			if buildMessage != nil {
				draft = buildMessage()
			}
			if draft == nil {
				return nil, nil
			}
			if len(projectMessage) > 0 && projectMessage[0] != nil {
				return projectMessage[0](draft, platform), nil
			}
			return projectPushMessageForPlatform(draft, platform), nil
		},
		true,
	)
}

func (ps *PushService) sendRichPushThroughGatewayWithAdmission(
	ctx context.Context,
	route pushRouteLease,
	buildMessage pushMessageFactory,
	admissionIdentity *groupMessageDispatchAdmissionIdentity,
	projectMessage ...pushMessageProjector,
) error {
	return ps.sendPushRouteThroughGateway(
		ctx,
		route,
		func(platform string) (*messaging.Message, error) {
			var draft *messaging.Message
			if buildMessage != nil {
				draft = buildMessage()
			}
			if draft == nil {
				return nil, nil
			}
			if len(projectMessage) > 0 && projectMessage[0] != nil {
				return projectMessage[0](draft, platform), nil
			}
			return projectPushMessageForPlatform(draft, platform), nil
		},
		true,
		admissionIdentity,
	)
}

func classifySelectedPushRoute(route pushRouteLease, requiredCapability string) (opaque bool, eligible bool) {
	if requiredCapability != "" && !route.hasCapability(requiredCapability) {
		return false, false
	}
	if route.hasCapability(opaqueWakeCapability) {
		return true, route.Handle != ""
	}
	return false, true
}

// sendSelectedPushThroughGateway owns the single bounded stale
// re-lookup/re-selection shared by all four adapters. Once an attempt selects
// opaque wake it may remain opaque or stop; it can never downgrade to rich.
func (ps *PushService) sendSelectedPushThroughGateway(
	ctx context.Context,
	peerID string,
	initialRoute pushRouteLease,
	requiredCapability string,
	buildRichMessage pushMessageFactory,
	projectRichMessage ...pushMessageProjector,
) pushDeliveryResult {
	return ps.sendSelectedPushThroughGatewayWithAdmission(
		ctx,
		peerID,
		initialRoute,
		requiredCapability,
		buildRichMessage,
		nil,
		projectRichMessage...,
	)
}

func (ps *PushService) sendSelectedGroupPushThroughGateway(
	ctx context.Context,
	peerID string,
	groupID string,
	messageID string,
	initialRoute pushRouteLease,
	requiredCapability string,
	buildRichMessage pushMessageFactory,
	projectRichMessage ...pushMessageProjector,
) pushDeliveryResult {
	identity, valid := newGroupMessageDispatchAdmissionIdentity(peerID, groupID, messageID)
	if !valid {
		return ps.sendSelectedPushThroughGateway(
			ctx,
			peerID,
			initialRoute,
			requiredCapability,
			buildRichMessage,
			projectRichMessage...,
		)
	}
	return ps.sendSelectedPushThroughGatewayWithAdmission(
		ctx,
		peerID,
		initialRoute,
		requiredCapability,
		buildRichMessage,
		&identity,
		projectRichMessage...,
	)
}

func (ps *PushService) sendSelectedPushThroughGatewayWithAdmission(
	ctx context.Context,
	peerID string,
	initialRoute pushRouteLease,
	requiredCapability string,
	buildRichMessage pushMessageFactory,
	admissionIdentity *groupMessageDispatchAdmissionIdentity,
	projectRichMessage ...pushMessageProjector,
) pushDeliveryResult {
	route := copyPushRouteLease(initialRoute)
	initialOpaque, eligible := classifySelectedPushRoute(route, requiredCapability)
	if !eligible {
		pushSentCounter.WithLabelValues("route_refresh_ineligible").Inc()
		if initialOpaque {
			log.Printf("[PUSH] outcome=opaque_route_invalid")
		}
		return pushDeliveryRetryable
	}
	opaqueLocked := initialOpaque

	for selectionAttempt := 0; selectionAttempt < 2; selectionAttempt++ {
		selectedOpaque, selectedEligible := classifySelectedPushRoute(route, requiredCapability)
		if !selectedEligible || (opaqueLocked && !selectedOpaque) {
			pushSentCounter.WithLabelValues("route_refresh_ineligible").Inc()
			return pushDeliveryRetryable
		}
		if selectedOpaque {
			selectedPushRouteCounter.WithLabelValues("opaque").Inc()
		} else {
			selectedPushRouteCounter.WithLabelValues("rich").Inc()
		}

		var err error
		if selectedOpaque {
			err = ps.mailboxDirtyWithAdmission(ctx, route, admissionIdentity)
		} else {
			err = ps.sendRichPushThroughGatewayWithAdmission(
				ctx,
				route,
				buildRichMessage,
				admissionIdentity,
				projectRichMessage...,
			)
		}
		if errors.Is(err, ErrPushRouteStale) {
			if selectionAttempt == 1 {
				pushSentCounter.WithLabelValues("route_stale").Inc()
				return pushDeliveryRetryable
			}
			refreshed, lookupErr := ps.selectPushRoute(peerID, requiredCapability)
			if lookupErr != nil {
				pushSentCounter.WithLabelValues("route_lookup_failed").Inc()
				return pushDeliveryRetryable
			}
			if refreshed == nil {
				pushSentCounter.WithLabelValues("route_refresh_ineligible").Inc()
				return pushDeliveryRetryable
			}
			route = copyPushRouteLease(*refreshed)
			continue
		}
		if errors.Is(err, errOpaqueWakeUnsupportedPlatform) {
			pushSentCounter.WithLabelValues("unsupported_platform").Inc()
			log.Printf("[PUSH] outcome=unsupported_platform")
			return pushDeliveryRetryable
		}
		if errors.Is(err, errPushDeliveryPermanent) {
			return pushDeliveryPermanent
		}
		if errors.Is(err, errPushDeliverySuppressed) {
			return pushDeliverySuppressed
		}
		if errors.Is(err, errPushDeliveryRetryable) {
			return pushDeliveryRetryable
		}
		if err != nil {
			pushSentCounter.WithLabelValues("route_resolution_failed").Inc()
			return pushDeliveryRetryable
		}
		return pushDeliveryAccepted
	}

	return pushDeliveryRetryable
}

// sendWakeOutcomeThroughGateway is the coordinator's only provider entrypoint.
// A delayed obligation always re-selects a fresh route and requires the
// incumbent producer capability plus Plan-368's fixed opaque classifier. The
// admission capability itself is intentionally not required here: removing
// wake_outcome_v1 releases an already-due fixed wake instead of stranding it.
func (ps *PushService) sendWakeOutcomeThroughGateway(
	ctx context.Context,
	recipientPeerID string,
	policy wakeOutcomeRoutePolicy,
) pushDeliveryResult {
	requiredCapability, validPolicy := wakeOutcomeRequiredCapability(policy)
	if !validPolicy {
		return pushDeliveryRetryable
	}

	route, err := ps.selectPushRoute(recipientPeerID, requiredCapability)
	if err != nil || route == nil {
		return pushDeliveryRetryable
	}
	return ps.sendOpaqueWakeThroughGateway(ctx, recipientPeerID, *route, policy)
}

func (ps *PushService) sendGroupWakeOutcomeThroughGateway(
	ctx context.Context,
	recipientPeerID string,
	policy wakeOutcomeRoutePolicy,
	groupMessageDispatchAdmissionKey string,
) pushDeliveryResult {
	identity, validIdentity := groupMessageDispatchAdmissionIdentityFromStorageKey(
		groupMessageDispatchAdmissionKey,
	)
	if !validIdentity {
		return pushDeliveryRetryable
	}
	requiredCapability, validPolicy := wakeOutcomeRequiredCapability(policy)
	if !validPolicy {
		return pushDeliveryRetryable
	}
	route, err := ps.selectPushRoute(recipientPeerID, requiredCapability)
	if err != nil || route == nil {
		return pushDeliveryRetryable
	}
	opaque, eligible := classifySelectedPushRoute(*route, requiredCapability)
	if !eligible || !opaque {
		return pushDeliveryRetryable
	}
	result := ps.sendSelectedPushThroughGatewayWithAdmission(
		ctx,
		recipientPeerID,
		*route,
		requiredCapability,
		nil,
		&identity,
	)
	recordGroupMessageDispatch(groupMessageDispatchSourceInbox, result)
	return result
}

// sendOpaqueWakeThroughGateway is the one additional Plan-370 caller of the
// Plan-368 selected gateway. It is shared by due coordinator sends and
// capacity fallbacks that retain their exact CAS-valid route.
func (ps *PushService) sendOpaqueWakeThroughGateway(
	ctx context.Context,
	recipientPeerID string,
	route pushRouteLease,
	policy wakeOutcomeRoutePolicy,
) pushDeliveryResult {
	requiredCapability, validPolicy := wakeOutcomeRequiredCapability(policy)
	if !validPolicy {
		return pushDeliveryRetryable
	}
	opaque, eligible := classifySelectedPushRoute(route, requiredCapability)
	if !eligible || !opaque {
		return pushDeliveryRetryable
	}

	return ps.sendSelectedPushThroughGateway(
		ctx,
		recipientPeerID,
		route,
		requiredCapability,
		nil,
	)
}

// sendGroupOpaqueWakeThroughGateway retains the exact group event identity
// across the preflight path that already selected a fixed opaque wake. Without
// this wrapper, the generic mailbox card would discard group/message identity
// before the shared provider admission boundary.
func (ps *PushService) sendGroupOpaqueWakeThroughGateway(
	ctx context.Context,
	recipientPeerID string,
	groupID string,
	messageID string,
	route pushRouteLease,
	policy wakeOutcomeRoutePolicy,
) pushDeliveryResult {
	requiredCapability, validPolicy := wakeOutcomeRequiredCapability(policy)
	if !validPolicy {
		return pushDeliveryRetryable
	}
	opaque, eligible := classifySelectedPushRoute(route, requiredCapability)
	if !eligible || !opaque {
		return pushDeliveryRetryable
	}

	result := ps.sendSelectedGroupPushThroughGateway(
		ctx,
		recipientPeerID,
		groupID,
		messageID,
		route,
		requiredCapability,
		nil,
	)
	recordGroupMessageDispatch(groupMessageDispatchSourceInbox, result)
	return result
}

func wakeOutcomeRequiredCapability(policy wakeOutcomeRoutePolicy) (string, bool) {
	switch policy {
	case wakeOutcomePolicyNone:
		return "", true
	case wakeOutcomePolicyDirectReaction:
		return directReactionCapability, true
	case wakeOutcomePolicyGroupReaction:
		return groupReactionCapability, true
	default:
		return "", false
	}
}

func recordDirectMissingPushRoute() {
	pushSentCounter.WithLabelValues("missing_token").Inc()
	log.Printf("[PUSH] outcome=missing_route")
}

func recordGroupMissingPushRoute() {
	pushSentCounter.WithLabelValues("missing_token").Inc()
	log.Printf("[PUSH] outcome=missing_route")
}

func (ps *PushService) SendNotification(
	ctx context.Context,
	toPeerId string,
	fromPeerId string,
	message string,
	selectedRoute ...pushRouteLease,
) {
	ps.sendRichNotification(ctx, toPeerId, fromPeerId, message, "", selectedRoute...)
}

func (ps *PushService) sendStoredNotification(
	ctx context.Context,
	toPeerID string,
	fromPeerID string,
	message string,
	custodyID string,
	selectedRoute ...pushRouteLease,
) {
	ps.sendRichNotification(
		ctx,
		toPeerID,
		fromPeerID,
		message,
		custodyID,
		selectedRoute...,
	)
}

func (ps *PushService) sendRichNotification(
	ctx context.Context,
	toPeerID string,
	fromPeerID string,
	message string,
	custodyID string,
	selectedRoute ...pushRouteLease,
) {
	var route *pushRouteLease
	if len(selectedRoute) > 0 {
		copy := copyPushRouteLease(selectedRoute[0])
		route = &copy
	} else {
		var err error
		route, err = ps.selectPushRoute(toPeerID, "")
		if err != nil {
			pushSentCounter.WithLabelValues("route_lookup_failed").Inc()
			return
		}
		if route == nil {
			recordDirectMissingPushRoute()
			return
		}
	}

	var projectMessage []pushMessageProjector
	if custodyID != "" {
		projectMessage = []pushMessageProjector{
			func(message *messaging.Message, platform string) *messaging.Message {
				return projectStoredDirectPushMessageForPlatform(message, platform, custodyID)
			},
		}
	}
	ps.sendSelectedPushThroughGateway(
		ctx,
		toPeerID,
		*route,
		"",
		func() *messaging.Message { return buildPushMessage("", fromPeerID, message) },
		projectMessage...,
	)
}

func (ps *PushService) SendReactionNotification(
	ctx context.Context,
	toPeerID string,
	authenticatedFromPeerID string,
	message string,
) {
	route, err := ps.selectPushRoute(toPeerID, directReactionCapability)
	if err != nil {
		pushSentCounter.WithLabelValues("reaction_route_error").Inc()
		return
	}
	if route == nil {
		pushSentCounter.WithLabelValues("reaction_incapable").Inc()
		return
	}
	ps.sendReactionNotificationForRoute(ctx, toPeerID, *route, authenticatedFromPeerID, message)
}

func (ps *PushService) sendReactionNotificationForRoute(
	ctx context.Context,
	toPeerID string,
	route pushRouteLease,
	authenticatedFromPeerID string,
	message string,
) {
	ps.sendSelectedPushThroughGateway(
		ctx,
		toPeerID,
		route,
		directReactionCapability,
		func() *messaging.Message {
			msg := buildReactionPushMessage("", authenticatedFromPeerID, message)
			if msg == nil {
				pushSentCounter.WithLabelValues("reaction_invalid").Inc()
			}
			return msg
		},
	)
}

func (ps *PushService) SendGroupReactionNotification(
	ctx context.Context,
	toPeerID string,
	groupID string,
	message string,
	metadata groupReactionPushMetadata,
) {
	route, err := ps.selectPushRoute(toPeerID, groupReactionCapability)
	if err != nil {
		pushSentCounter.WithLabelValues("group_reaction_route_error").Inc()
		return
	}
	if route == nil {
		pushSentCounter.WithLabelValues("group_reaction_incapable").Inc()
		return
	}
	ps.sendGroupReactionNotificationForRoute(ctx, toPeerID, *route, groupID, message, metadata)
}

func (ps *PushService) sendGroupReactionNotificationForRoute(
	ctx context.Context,
	toPeerID string,
	route pushRouteLease,
	groupID string,
	message string,
	metadata groupReactionPushMetadata,
) {
	ps.sendSelectedPushThroughGateway(
		ctx,
		toPeerID,
		route,
		groupReactionCapability,
		func() *messaging.Message {
			msg := buildGroupReactionPushMessage("", groupID, message, metadata)
			if msg == nil {
				pushSentCounter.WithLabelValues("group_reaction_invalid").Inc()
			}
			return msg
		},
	)
}

func (ps *PushService) SendGroupNotification(
	ctx context.Context,
	toPeerId string,
	groupId string,
	senderTransportPeerID string,
	messageID string,
	message string,
	selectedRoute ...pushRouteLease,
) {
	var route *pushRouteLease
	if len(selectedRoute) > 0 {
		copy := copyPushRouteLease(selectedRoute[0])
		route = &copy
	} else {
		var err error
		route, err = ps.selectPushRoute(toPeerId, "")
		if err != nil {
			pushSentCounter.WithLabelValues("route_lookup_failed").Inc()
			return
		}
		if route == nil {
			recordGroupMissingPushRoute()
			return
		}
	}

	dispatch := ps.groupMessageDispatchProjection(groupMessageDispatchSourceInbox)
	result := ps.sendSelectedGroupPushThroughGateway(
		ctx,
		toPeerId,
		groupId,
		messageID,
		*route,
		"",
		func() *messaging.Message {
			return buildGroupPushMessage(
				"",
				groupId,
				senderTransportPeerID,
				messageID,
				message,
			)
		},
		func(message *messaging.Message, platform string) *messaging.Message {
			return projectGroupPushMessageForPlatform(
				message,
				platform,
				messageID,
				dispatch,
			)
		},
	)
	recordGroupMessageDispatch(groupMessageDispatchSourceInbox, result)
}

// send returns the provider error VERBATIM. Do not wrap it: messaging.Is* uses
// a bare type assertion on *internal.FirebaseError and does not Unwrap, so a
// fmt.Errorf("...: %w", err) here would silently disable the typed arm of
// permanentPushErrorReason (plan 320).
func (ps *PushService) send(ctx context.Context, msg *messaging.Message) (string, error) {
	if ps.sender != nil {
		return ps.sender(ctx, msg)
	}
	if ps.client == nil {
		return "", nil
	}
	return ps.client.Send(ctx, msg)
}

func (ps *PushService) sendWithRetry(
	ctx context.Context,
	msg *messaging.Message,
	route pushRouteLease,
	allowStrictFallback bool,
) pushDeliveryResult {
	if ps.sender == nil && ps.client == nil {
		pushSentCounter.WithLabelValues("provider_unavailable").Inc()
		log.Printf("[PUSH] provider unavailable outcome=provider_unavailable")
		return pushDeliveryRetryable
	}
	if msg == nil {
		pushSentCounter.WithLabelValues("invalid_payload").Inc()
		log.Printf("[PUSH] outcome=invalid_payload")
		return pushDeliveryRetryable
	}
	totalAttempts := len(ps.retryDelays) + 1
	providerAttempt := 0

	for attempt := 1; attempt <= totalAttempts; attempt++ {
		providerAttempt++
		providerResponseName, err := ps.send(ctx, msg)
		ps.recordGroupMessageProviderAttempt(
			msg,
			providerResponseName,
			err,
			providerAttempt,
			groupMessageProviderAttemptPrimary,
		)
		if err == nil {
			pushSentCounter.WithLabelValues("success").Inc()
			log.Printf("[PUSH] outcome=success attempt=%d total_attempts=%d", attempt, totalAttempts)
			return pushDeliveryAccepted
		}

		if reason := permanentPushErrorReason(err); reason != "" {
			revoked, revokeErr := ps.tokenBackend.RevokeIfCurrent(route)
			pushSentCounter.WithLabelValues("invalid_token").Inc()
			if revokeErr != nil {
				log.Printf("[PUSH] outcome=revoke_failed reason=%s", reason)
			}
			log.Printf("[PUSH] outcome=invalid_token reason=%s", reason)
			if revokeErr != nil || !revoked {
				return pushDeliveryRetryable
			}
			return pushDeliveryPermanent
		}

		if isPayloadTooLargeError(err) {
			if !allowStrictFallback {
				pushSentCounter.WithLabelValues("payload_too_large").Inc()
				log.Printf("[PUSH] outcome=payload_too_large fallback=disabled")
				return pushDeliveryRetryable
			}
			// A provider size rejection is permanent for this exact object. Rebuild
			// once from authenticated routing fields only, then make exactly one
			// final send attempt; never burn the transient retry budget resending the
			// same invalid payload.
			strict := buildStrictMinimalFallbackPushMessage(msg)
			if strict == nil {
				pushSentCounter.WithLabelValues("payload_too_large").Inc()
				log.Printf("[PUSH] outcome=payload_too_large fallback=unavailable")
				return pushDeliveryRetryable
			}

			providerAttempt++
			fallbackProviderResponseName, fallbackErr := ps.send(ctx, strict)
			ps.recordGroupMessageProviderAttempt(
				strict,
				fallbackProviderResponseName,
				fallbackErr,
				providerAttempt,
				groupMessageProviderAttemptStrictFallback,
			)
			if fallbackErr == nil {
				pushSentCounter.WithLabelValues("success").Inc()
				pushSentCounter.WithLabelValues("payload_too_large_fallback").Inc()
				log.Printf("[PUSH] outcome=success fallback=strict")
				return pushDeliveryAccepted
			}
			fallbackResult := pushDeliveryRetryable
			if reason := permanentPushErrorReason(fallbackErr); reason != "" {
				revoked, revokeErr := ps.tokenBackend.RevokeIfCurrent(route)
				pushSentCounter.WithLabelValues("invalid_token").Inc()
				if revokeErr != nil {
					log.Printf("[PUSH] outcome=revoke_failed reason=%s", reason)
				}
				log.Printf("[PUSH] outcome=invalid_token reason=%s fallback=strict", reason)
				if revokeErr == nil && revoked {
					fallbackResult = pushDeliveryPermanent
				}
			} else {
				pushSentCounter.WithLabelValues("failed").Inc()
			}
			log.Printf("[PUSH] outcome=fallback_failed fallback=strict")
			return fallbackResult
		}

		if attempt == totalAttempts {
			pushSentCounter.WithLabelValues("failed").Inc()
			log.Printf("[PUSH] outcome=failed attempts=%d", attempt)
			return pushDeliveryRetryable
		}

		delay := ps.retryDelays[attempt-1]
		log.Printf("[PUSH] outcome=retrying attempt=%d total_attempts=%d", attempt, totalAttempts)

		if !waitForRetryDelay(ctx, delay) {
			pushSentCounter.WithLabelValues("failed").Inc()
			log.Printf("[PUSH] outcome=context_canceled")
			return pushDeliveryRetryable
		}
	}

	return pushDeliveryRetryable
}

func waitForRetryDelay(ctx context.Context, delay time.Duration) bool {
	if delay <= 0 {
		select {
		case <-ctx.Done():
			return false
		default:
			return true
		}
	}

	timer := time.NewTimer(delay)
	defer timer.Stop()

	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

func buildPushMessage(token, fromPeerId, message string) *messaging.Message {
	metadata := extractChatPushMetadata(message)
	if metadata.RouteType == "new_message" {
		data := map[string]string{
			"type":      "new_message",
			"sender_id": fromPeerId,
		}
		if metadata.MessageID != "" {
			data["message_id"] = metadata.MessageID
		}
		if !addChatEncryptedPushData(data, message) {
			fallback := map[string]string{
				"type":                "new_message",
				"sender_id":           fromPeerId,
				"preview_unavailable": "1",
			}
			if metadata.MessageID != "" {
				fallback["message_id"] = metadata.MessageID
			}
			return buildUnusableEnvelopeFallbackPushMessage(token, fallback, fromPeerId)
		}
		message := buildCiphertextOnlyPushMessage(token, data, fromPeerId)
		if pushDataSize(data) > maxPushDataBytes || !messageFitsProviderBudgets(message) {
			// Oversized media envelope: FCM would reject the silent ciphertext-only
			// push (>4 KB). Drop the encrypted payload and keep only routing. Android
			// renders locally after policy checks; APNS retains a generic alert.
			fallback := map[string]string{
				"type":                "new_message",
				"sender_id":           fromPeerId,
				"preview_unavailable": "1",
			}
			if metadata.MessageID != "" {
				fallback["message_id"] = metadata.MessageID
			}
			return buildOversizedFallbackPushMessage(token, fallback, fromPeerId)
		}
		return message
	}

	resolvedTitle := metadata.SenderUsername
	switch metadata.RouteType {
	case "intros":
		if metadata.IntroAction == "accept" {
			resolvedTitle = introAcceptPushNotificationTitle
		} else {
			resolvedTitle = introPushNotificationTitle
		}
	case "contact_request":
		resolvedTitle = contactRequestPushTitle
	case "group_invite":
		if metadata.GroupName != "" {
			resolvedTitle = metadata.GroupName
		} else {
			resolvedTitle = groupInvitePushTitle
		}
	case "new_message":
		if resolvedTitle == "" {
			resolvedTitle = pushNotificationTitle
		}
	default:
		resolvedTitle = pushNotificationTitle
	}
	resolvedBody := metadata.Body
	if resolvedBody == "" {
		switch metadata.RouteType {
		case "intros":
			resolvedBody = introPushNotificationBody
		case "contact_request":
			resolvedBody = contactRequestPushBody
		case "group_invite":
			resolvedBody = groupInvitePushBody
		default:
			resolvedBody = pushNotificationBody
		}
	}

	data := map[string]string{
		"type":  metadata.RouteType,
		"title": resolvedTitle,
		"body":  resolvedBody,
	}
	if metadata.RouteType == "new_message" || metadata.RouteType == "contact_request" {
		data["sender_id"] = fromPeerId
	}
	if metadata.RouteType == "group_invite" && metadata.GroupID != "" {
		data["groupId"] = metadata.GroupID
	}
	if metadata.MessageID != "" {
		data["message_id"] = metadata.MessageID
	}
	if metadata.SenderUsername != "" {
		data["sender_username"] = metadata.SenderUsername
		data["senderUsername"] = metadata.SenderUsername
	}

	androidNotification := &messaging.AndroidNotification{
		Title:     resolvedTitle,
		Body:      resolvedBody,
		ChannelID: pushNotificationChannelID,
	}
	if metadata.RouteType == "group_invite" {
		androidNotification.Tag = groupInviteAndroidNotificationTag(
			metadata.GroupID,
			metadata.MessageID,
		)
	}

	return &messaging.Message{
		Token: token,
		Notification: &messaging.Notification{
			Title: resolvedTitle,
			Body:  resolvedBody,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority:     "high",
			Notification: androidNotification,
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority":  "10",
				"apns-push-type": "alert",
			},
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					ContentAvailable: true,
					Sound:            pushNotificationSound,
					Alert: &messaging.ApsAlert{
						Title: resolvedTitle,
						Body:  resolvedBody,
					},
				},
			},
		},
	}
}

// groupInviteAndroidNotificationTag returns the privacy-safe native identity
// shared with the Android app's local group-invite publisher. Exact redelivery
// of one invite therefore updates one OS card, while distinct invites remain
// independently visible. Missing canonical routing identities deliberately
// leave the notification untagged instead of collapsing unrelated invites.
func groupInviteAndroidNotificationTag(groupID, inviteID string) string {
	groupID = strings.TrimSpace(groupID)
	inviteID = strings.TrimSpace(inviteID)
	if groupID == "" || inviteID == "" {
		return ""
	}

	digest := sha256.Sum256([]byte("group_invite\x00" + groupID + "\x00" + inviteID))
	return fmt.Sprintf("%s%x", groupInviteAndroidTagPrefix, digest[:16])
}

func buildGroupPushMessage(
	token,
	groupId,
	senderTransportPeerID,
	messageID,
	message string,
) *messaging.Message {
	data := map[string]string{
		"type":                     "group_message",
		"groupId":                  groupId,
		"sender_transport_peer_id": senderTransportPeerID,
	}
	if messageID != "" {
		data["message_id"] = messageID
	}
	if !addGroupEncryptedPushData(data, message) {
		fallback := map[string]string{
			"type":                     "group_message",
			"groupId":                  groupId,
			"sender_transport_peer_id": senderTransportPeerID,
			"preview_unavailable":      "1",
		}
		if messageID != "" {
			fallback["message_id"] = messageID
		}
		return buildUnusableEnvelopeFallbackPushMessage(token, fallback, groupId)
	}
	pushMessage := buildCiphertextOnlyPushMessage(token, data, groupId)
	if pushDataSize(data) > maxPushDataBytes || !messageFitsProviderBudgets(pushMessage) {
		// Oversized group media envelope: same as the 1:1 path — drop the encrypted
		// payload and keep only routing. Android renders locally after policy checks;
		// APNS retains a generic alert.
		fallback := map[string]string{
			"type":                     "group_message",
			"groupId":                  groupId,
			"sender_transport_peer_id": senderTransportPeerID,
			"preview_unavailable":      "1",
		}
		if data["message_id"] != "" {
			fallback["message_id"] = data["message_id"]
		}
		return buildOversizedFallbackPushMessage(token, fallback, groupId)
	}

	return pushMessage
}

func buildCiphertextOnlyPushMessage(token string, data map[string]string, threadID string) *messaging.Message {
	aps := &messaging.Aps{
		ContentAvailable: true,
		MutableContent:   true,
		Sound:            pushNotificationSound,
		Alert: &messaging.ApsAlert{
			Title: pushNotificationTitle,
			Body:  pushNotificationBody,
		},
	}
	if threadID != "" {
		aps.ThreadID = threadID
	}

	return &messaging.Message{
		Token: token,
		Data:  data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority":  "10",
				"apns-push-type": "alert",
			},
			Payload: &messaging.APNSPayload{
				Aps:        aps,
				CustomData: apnsCustomDataFromPushData(data),
			},
		},
	}
}

// pushDataSize returns the byte size of the assembled FCM `data` map, counting
// both keys and values. FCM measures the whole data payload against its 4096
// byte limit, so the budget check must include keys, not just values.
func pushDataSize(data map[string]string) int {
	total := 0
	for key, value := range data {
		total += len(key) + len(value)
	}
	return total
}

type providerPayloadSize struct {
	FCM  int
	APNS int
}

// providerEquivalentPayloadSize measures the two complete platform payloads
// FCM materializes for this cross-platform message. The Android/FCM leg
// includes data, notification, and Android configuration; the APNS leg uses
// APNSPayload.MarshalJSON, which merges `aps` and every custom routing key.
// Token and APNS headers route the request but are not part of either delivered
// provider payload.
func providerEquivalentPayloadSize(msg *messaging.Message) (providerPayloadSize, error) {
	if msg == nil {
		return providerPayloadSize{}, fmt.Errorf("nil push message")
	}
	androidPayload := struct {
		Data         map[string]string        `json:"data,omitempty"`
		Notification *messaging.Notification  `json:"notification,omitempty"`
		Android      *messaging.AndroidConfig `json:"android,omitempty"`
	}{
		Data:         msg.Data,
		Notification: msg.Notification,
		Android:      msg.Android,
	}
	fcmBytes, err := json.Marshal(androidPayload)
	if err != nil {
		return providerPayloadSize{}, err
	}

	apnsSize := 0
	if msg.APNS != nil && msg.APNS.Payload != nil {
		apnsBytes, marshalErr := json.Marshal(msg.APNS.Payload)
		if marshalErr != nil {
			return providerPayloadSize{}, marshalErr
		}
		apnsSize = len(apnsBytes)
	}
	return providerPayloadSize{FCM: len(fcmBytes), APNS: apnsSize}, nil
}

func messageFitsProviderBudgets(msg *messaging.Message) bool {
	sizes, err := providerEquivalentPayloadSize(msg)
	return err == nil &&
		sizes.FCM <= maxProviderPayloadBytes &&
		sizes.APNS <= maxProviderPayloadBytes
}

// buildOversizedFallbackPushMessage builds an under-budget fallback for a push
// whose encrypted payload would exceed maxPushDataBytes (e.g. a media envelope).
// The caller has already trimmed `data` down to minimal routing keys
// (+ preview_unavailable="1"). Android must remain routing-only so the background
// handler owns display eligibility, dedupe, mute, and local notification copy;
// including either FCM's top-level Notification or Android.Notification would let
// the provider auto-display a second, policy-bypassing notification. APNS retains
// a generic visible alert because its notification service extension needs an
// alert-class delivery. MutableContent remains on even though the oversized
// ciphertext was removed: the NSE still owns recipient policy, dedupe, tone,
// and trusted routing-copy selection for this routing-only fallback.
func buildOversizedFallbackPushMessage(token string, data map[string]string, threadID string) *messaging.Message {
	return buildRoutingFallbackPushMessage(token, data, threadID, "oversized_fallback")
}

func buildUnusableEnvelopeFallbackPushMessage(token string, data map[string]string, threadID string) *messaging.Message {
	return buildRoutingFallbackPushMessage(token, data, threadID, "unusable_envelope_fallback")
}

func buildRoutingFallbackPushMessage(
	token string,
	data map[string]string,
	threadID string,
	fallbackReason string,
) *messaging.Message {
	routing := cloneStringMap(data)
	if !hasRequiredFallbackRouting(routing) {
		return nil
	}

	// message_id and APNS thread-id are useful but optional. Remove them one at a
	// time and remeasure the complete platform payloads after each reduction.
	// Required routing is never dropped; if it cannot fit, refuse the send.
	for {
		msg := newOversizedFallbackPushMessage(token, routing, threadID)
		if messageFitsProviderBudgets(msg) {
			pushFallbackCounter.WithLabelValues(fallbackReason).Inc()
			return msg
		}
		if _, ok := routing["message_id"]; ok {
			delete(routing, "message_id")
			continue
		}
		if threadID != "" {
			threadID = ""
			continue
		}
		return nil
	}
}

func newOversizedFallbackPushMessage(token string, data map[string]string, threadID string) *messaging.Message {

	aps := &messaging.Aps{
		ContentAvailable: true,
		MutableContent:   true,
		Sound:            pushNotificationSound,
		Alert: &messaging.ApsAlert{
			Title: pushNotificationTitle,
			Body:  pushNotificationBody,
		},
	}
	if threadID != "" {
		aps.ThreadID = threadID
	}

	return &messaging.Message{
		Token: token,
		Data:  data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority":  "10",
				"apns-push-type": "alert",
			},
			Payload: &messaging.APNSPayload{
				Aps:        aps,
				CustomData: apnsCustomDataFromPushData(data),
			},
		},
	}
}

func cloneStringMap(source map[string]string) map[string]string {
	cloned := make(map[string]string, len(source))
	for key, value := range source {
		cloned[key] = value
	}
	return cloned
}

func hasRequiredFallbackRouting(data map[string]string) bool {
	if data["preview_unavailable"] != "1" {
		return false
	}
	switch data["type"] {
	case "new_message":
		return strings.TrimSpace(data["sender_id"]) != ""
	case "group_message":
		return strings.TrimSpace(data["groupId"]) != "" &&
			strings.TrimSpace(data["sender_transport_peer_id"]) != ""
	default:
		return false
	}
}

func buildStrictMinimalFallbackPushMessage(msg *messaging.Message) *messaging.Message {
	if msg == nil {
		return nil
	}
	// ios-projected messages carry their routing exclusively in the APNs
	// CustomData copy (the top-level data map was dropped by the platform
	// projection), so the rescue must read routing keys from either source.
	routingValue := func(key string) string {
		if value, ok := msg.Data[key]; ok {
			return value
		}
		if msg.APNS != nil && msg.APNS.Payload != nil {
			if value, ok := msg.APNS.Payload.CustomData[key].(string); ok {
				return value
			}
		}
		return ""
	}
	data := map[string]string{
		"type":                routingValue("type"),
		"preview_unavailable": "1",
	}
	switch data["type"] {
	case "new_message":
		data["sender_id"] = routingValue("sender_id")
	case "group_message":
		data["groupId"] = routingValue("groupId")
		data["sender_transport_peer_id"] = routingValue("sender_transport_peer_id")
	default:
		return nil
	}
	if !hasRequiredFallbackRouting(data) {
		return nil
	}
	if msg.Data["preview_unavailable"] == "1" &&
		len(msg.Data) == len(data) &&
		msg.APNS != nil && msg.APNS.Payload != nil && msg.APNS.Payload.Aps != nil &&
		msg.APNS.Payload.Aps.ThreadID == "" {
		return nil
	}
	strict := buildOversizedFallbackPushMessage(msg.Token, data, "")
	if data["type"] != "group_message" ||
		strict == nil || strict.APNS == nil || strict.APNS.Payload == nil ||
		msg.APNS == nil || msg.APNS.Payload == nil {
		return strict
	}

	// The provider-size fallback is still the same iOS logical dispatch. Keep
	// its independently derived collapse identity and closed adapter claim,
	// while leaving the top-level FCM Data projection untouched.
	claim, _ := msg.APNS.Payload.CustomData[groupMessageDispatchClaimKey].(string)
	if claim != groupMessageDispatchClaimInbox && claim != groupMessageDispatchClaimContent {
		return strict
	}
	apns := *strict.APNS
	headers := make(map[string]string, len(strict.APNS.Headers)+1)
	for key, value := range strict.APNS.Headers {
		headers[key] = value
	}
	if collapseID := strings.TrimSpace(msg.APNS.Headers["apns-collapse-id"]); collapseID != "" {
		headers["apns-collapse-id"] = collapseID
	}
	apns.Headers = headers
	payload := *strict.APNS.Payload
	customData := make(map[string]interface{}, len(strict.APNS.Payload.CustomData)+3)
	for key, value := range strict.APNS.Payload.CustomData {
		customData[key] = value
	}
	customData[groupMessageDispatchClaimKey] = claim
	dispatchID, _ := msg.APNS.Payload.CustomData[groupMessageDispatchIDKey].(string)
	claimedCollapse, _ := msg.APNS.Payload.CustomData[groupMessageCollapseClaimKey].(string)
	if canonicalGroupMessageDispatchID(dispatchID) &&
		canonicalGroupMessageCollapseClaim(claimedCollapse) &&
		msg.APNS.Headers["apns-collapse-id"] == claimedCollapse {
		customData[groupMessageDispatchIDKey] = dispatchID
		customData[groupMessageCollapseClaimKey] = claimedCollapse
	}
	payload.CustomData = customData
	apns.Payload = &payload
	strict.APNS = &apns
	return strict
}

func isPayloadTooLargeError(err error) bool {
	if err == nil {
		return false
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "message is too large") ||
		strings.Contains(message, "message too large") ||
		strings.Contains(message, "message too big") ||
		strings.Contains(message, "messagetoobig") ||
		strings.Contains(message, "payload too large") ||
		strings.Contains(message, "payloadtoolarge") ||
		strings.Contains(message, "payload-size-limit-exceeded") ||
		strings.Contains(message, "maximum is 4k") ||
		strings.Contains(message, "maximum is 4096") ||
		strings.Contains(message, "request entity too large")
}

// projectPushMessageForPlatform removes the platform copy the registered token
// can never consume, mirroring the group-reaction lane's projection: FCM's
// server-side 4096-byte enforcement spans a quantity that includes BOTH the
// top-level data map and the APNs CustomData duplicate, so a dual-copy
// mid-band envelope passes the per-leg pre-check yet is rejected at send time.
// android tokens drop the APNS config; ios tokens drop the Android config and,
// ONLY when an APNs CustomData copy exists, the duplicate top-level data map.
// Visible-copy routes carry their tap-routing keys exclusively in the data map
// (no CustomData), which FCM merges into the APNs payload — stripping data
// there would break iOS notification-open routing, so it is kept. Unknown
// platform strings fail open to today's dual-copy shape (production cannot
// register an empty platform; see the register_token handler).
func projectPushMessageForPlatform(
	message *messaging.Message,
	platform string,
) *messaging.Message {
	if message == nil {
		return nil
	}
	projected := *message
	switch strings.ToLower(strings.TrimSpace(platform)) {
	case "android":
		projected.APNS = nil
	case "ios":
		projected.Android = nil
		if message.APNS != nil && message.APNS.Payload != nil &&
			len(message.APNS.Payload.CustomData) > 0 {
			projected.Data = nil
		}
	}
	return &projected
}

// boundedGroupMessageIdentity converts the canonical message ID into a stable
// 62-byte maximum APNs collapse identity (`group-message:` plus 48 SHA-256 hex
// characters). Blank IDs remain non-collapsible instead of merging unrelated
// messages.
func boundedGroupMessageIdentity(messageID string) string {
	messageID = strings.TrimSpace(messageID)
	if messageID == "" {
		return ""
	}
	digest := sha256.Sum256([]byte(messageID))
	return fmt.Sprintf("group-message:%x", digest[:24])
}

// projectGroupPushMessageForPlatform adds the per-message retry identity only
// to the iOS group-message copy. It delegates all platform stripping to the
// shared projector and clones APNS/header ownership before mutation.
func projectGroupPushMessageForPlatform(
	message *messaging.Message,
	platform string,
	messageID string,
	dispatch groupMessageDispatchProjection,
) *messaging.Message {
	projected := projectPushMessageForPlatform(message, platform)
	identity := boundedGroupMessageIdentity(messageID)
	if projected == nil ||
		strings.ToLower(strings.TrimSpace(platform)) != "ios" ||
		identity == "" ||
		projected.APNS == nil {
		return projected
	}

	apns := *projected.APNS
	headers := make(map[string]string, len(projected.APNS.Headers)+1)
	for key, value := range projected.APNS.Headers {
		headers[key] = value
	}
	headers["apns-collapse-id"] = identity
	apns.Headers = headers
	if claim := dispatch.Source.claim(); claim != "" && apns.Payload != nil {
		payload := *apns.Payload
		customData := make(map[string]interface{}, len(apns.Payload.CustomData)+3)
		for key, value := range apns.Payload.CustomData {
			customData[key] = value
		}
		customData[groupMessageDispatchClaimKey] = claim
		if canonicalGroupMessageDispatchID(dispatch.ID) && canonicalGroupMessageCollapseClaim(identity) {
			customData[groupMessageDispatchIDKey] = dispatch.ID
			customData[groupMessageCollapseClaimKey] = identity
		}
		payload.CustomData = customData
		apns.Payload = &payload
	}
	projected.APNS = &apns
	return projected
}

// projectStoredDirectPushMessageForPlatform adds a collapse identity only at
// the stored-rich iOS group-invite and direct-message boundary. The relay
// custody UUID is stable across provider retries, while a separately stored row
// receives a new UUID. Unknown platforms retain the incumbent fail-open
// dual-copy projection and never inherit an iOS-only collapse header.
func projectStoredDirectPushMessageForPlatform(
	message *messaging.Message,
	platform string,
	custodyID string,
) *messaging.Message {
	projected := projectPushMessageForPlatform(message, platform)
	messageType := ""
	if message != nil {
		messageType = message.Data["type"]
	}
	if projected == nil ||
		strings.ToLower(strings.TrimSpace(platform)) != "ios" ||
		(messageType != "group_invite" && messageType != "new_message") ||
		projected.APNS == nil {
		return projected
	}

	collapseID := strings.TrimSpace(custodyID)
	if byteLength := len([]byte(collapseID)); byteLength == 0 || byteLength > 64 {
		return projected
	}

	apns := *projected.APNS
	headers := make(map[string]string, len(projected.APNS.Headers)+1)
	for key, value := range projected.APNS.Headers {
		headers[key] = value
	}
	headers["apns-collapse-id"] = collapseID
	apns.Headers = headers
	projected.APNS = &apns
	return projected
}

func apnsCustomDataFromPushData(data map[string]string) map[string]interface{} {
	customData := make(map[string]interface{}, len(data))
	for key, value := range data {
		customData[key] = value
	}
	return customData
}

func addChatEncryptedPushData(data map[string]string, message string) bool {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return false
	}

	if version := trimmedString(envelope["version"]); version != "" {
		data["envelope_version"] = version
	}
	encrypted, ok := envelope["encrypted"].(map[string]interface{})
	if !ok {
		return false
	}

	addTrimmedData(data, "kem", encrypted["kem"])
	addTrimmedData(data, "ciphertext", encrypted["ciphertext"])
	addTrimmedData(data, "nonce", encrypted["nonce"])
	return data["kem"] != "" && data["ciphertext"] != "" && data["nonce"] != ""
}

func addGroupEncryptedPushData(data map[string]string, message string) bool {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return false
	}

	addTrimmedData(data, "kind", envelope["kind"])
	addJSONScalarData(data, "envelope_version", envelope["version"])
	addTrimmedData(data, "payloadType", envelope["payloadType"])
	if data["payloadType"] == "" {
		addTrimmedData(data, "payloadType", envelope["type"])
	}
	addJSONScalarData(data, "keyEpoch", envelope["keyEpoch"])
	if !isCanonicalPositiveInteger(data["keyEpoch"]) {
		return false
	}
	if encrypted, ok := envelope["encrypted"].(map[string]interface{}); ok {
		addTrimmedData(data, "ciphertext", encrypted["ciphertext"])
		addTrimmedData(data, "nonce", encrypted["nonce"])
	}
	if data["ciphertext"] == "" {
		addTrimmedData(data, "ciphertext", envelope["ciphertext"])
	}
	if data["nonce"] == "" {
		addTrimmedData(data, "nonce", envelope["nonce"])
	}
	if data["message_id"] == "" {
		addTrimmedData(data, "message_id", envelope["messageId"])
	}
	if data["groupId"] == "" {
		addTrimmedData(data, "groupId", envelope["groupId"])
	}
	return data["keyEpoch"] != "" &&
		data["ciphertext"] != "" &&
		data["nonce"] != ""
}

func isCanonicalPositiveInteger(value string) bool {
	parsed, err := strconv.ParseInt(value, 10, 64)
	return err == nil && parsed > 0 && strconv.FormatInt(parsed, 10) == value
}

func addTrimmedData(data map[string]string, key string, raw interface{}) {
	if value := trimmedString(raw); value != "" {
		data[key] = value
	}
}

func addJSONScalarData(data map[string]string, key string, raw interface{}) {
	switch value := raw.(type) {
	case string:
		if strings.TrimSpace(value) != "" {
			data[key] = strings.TrimSpace(value)
		}
	case float64:
		if value == float64(int64(value)) {
			data[key] = fmt.Sprintf("%d", int64(value))
		} else {
			data[key] = fmt.Sprintf("%g", value)
		}
	case int:
		data[key] = fmt.Sprintf("%d", value)
	case int64:
		data[key] = fmt.Sprintf("%d", value)
	case json.Number:
		data[key] = value.String()
	}
}

type chatPushMetadata struct {
	ShouldNotify   bool
	RouteType      string
	MessageID      string
	SenderUsername string
	GroupID        string
	GroupName      string
	Body           string
	// IntroAction is the VALIDATED canonical introduction action ("send",
	// "accept", "pass"). Empty when the envelope's canonical message ID is
	// absent, malformed, or (for v1) conflicts with the cleartext payload
	// action — those fail closed to generic introduction copy.
	IntroAction string
	// Plan 256 additive direct-reaction notification metadata. These remain
	// empty for legacy v2 envelopes, which are still stored/replayed silently.
	ReactionEventID         string
	ReactionAction          string
	ReactionTargetMessageID string
}

// introductionEnvelopeIdentity is the validated identity carried by a
// canonical introduction envelope message ID
// (`<introductionId>::<action>::<senderPeerId>`).
type introductionEnvelopeIdentity struct {
	CanonicalID    string
	IntroductionID string
	Action         string
	SenderPeerID   string
}

// parseIntroductionEnvelopeIdentity parses a canonical introduction envelope
// message ID. Introduction IDs may themselves contain "::", so the action and
// sender segments are consumed from the RIGHT. Only send/accept/pass are
// recognized; malformed shapes (missing segments, empty parts, unsupported
// actions) return ok=false so push construction fails closed to generic copy.
func parseIntroductionEnvelopeIdentity(messageID string) (introductionEnvelopeIdentity, bool) {
	trimmed := strings.TrimSpace(messageID)
	senderSep := strings.LastIndex(trimmed, "::")
	if senderSep <= 0 {
		return introductionEnvelopeIdentity{}, false
	}
	senderPeerID := trimmed[senderSep+2:]

	rest := trimmed[:senderSep]
	actionSep := strings.LastIndex(rest, "::")
	if actionSep <= 0 {
		return introductionEnvelopeIdentity{}, false
	}
	action := rest[actionSep+2:]
	introductionID := rest[:actionSep]

	if introductionID == "" || senderPeerID == "" {
		return introductionEnvelopeIdentity{}, false
	}
	switch action {
	case "send", "accept", "pass":
	default:
		return introductionEnvelopeIdentity{}, false
	}

	return introductionEnvelopeIdentity{
		CanonicalID:    trimmed,
		IntroductionID: introductionID,
		Action:         action,
		SenderPeerID:   senderPeerID,
	}, true
}

func extractChatPushMetadata(message string) chatPushMetadata {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return chatPushMetadata{}
	}

	switch trimmedString(envelope["type"]) {
	case "message_reaction":
		reaction, _, eligible := extractDirectReactionPushMetadata(message)
		return chatPushMetadata{
			ShouldNotify:            eligible,
			RouteType:               "message_reaction",
			MessageID:               reaction.EventID,
			ReactionEventID:         reaction.EventID,
			ReactionAction:          reaction.Action,
			ReactionTargetMessageID: reaction.TargetMessageID,
		}
	case "introduction":
		metadata := chatPushMetadata{
			ShouldNotify: true,
			RouteType:    "intros",
			MessageID:    extractMessageId(message),
			Body:         introPushNotificationBody,
		}
		// 252: introduction metadata prefers a VALIDATED canonical top-level
		// messageId over any coexisting legacy id, and that one selected
		// value drives both the action decision and the forwarded push
		// message_id. When no canonical messageId validates, the generic
		// extractMessageId routing identity and generic copy are preserved
		// unchanged (global ID precedence is untouched).
		identity, ok := parseIntroductionEnvelopeIdentity(trimmedString(envelope["messageId"]))
		if !ok {
			return metadata
		}
		// v1 plaintext envelopes carry a cleartext action; it must AGREE with
		// the validated canonical ID before that action is trusted. v2 opaque
		// envelopes derive the action only from the canonical ID.
		if payload, isV1 := envelope["payload"].(map[string]interface{}); isV1 {
			if trimmedString(payload["action"]) != identity.Action {
				return metadata
			}
		}
		metadata.MessageID = identity.CanonicalID
		metadata.IntroAction = identity.Action
		if identity.Action == "accept" {
			metadata.Body = introAcceptPushNotificationBody
		}
		return metadata
	case "chat_message":
		return chatPushMetadata{
			ShouldNotify: true,
			RouteType:    "new_message",
			MessageID:    extractMessageId(message),
		}
	case "contact_request":
		intent := trimmedString(envelope["intent"])
		metadata := chatPushMetadata{
			ShouldNotify:   intent != "key_exchange_retry",
			RouteType:      "contact_request",
			MessageID:      extractMessageId(message),
			SenderUsername: trimmedString(envelope["senderUsername"]),
		}
		if payload, ok := envelope["payload"].(map[string]interface{}); ok {
			if metadata.SenderUsername == "" {
				metadata.SenderUsername = trimmedString(payload["senderUsername"])
			}
			if metadata.SenderUsername == "" {
				metadata.SenderUsername = trimmedString(payload["un"])
			}
		}
		if metadata.SenderUsername != "" {
			metadata.Body = fmt.Sprintf("%s wants to connect", metadata.SenderUsername)
		} else {
			metadata.Body = contactRequestPushBody
		}
		return metadata
	case "group_invite":
		metadata := chatPushMetadata{
			ShouldNotify:   true,
			RouteType:      "group_invite",
			MessageID:      extractMessageId(message),
			SenderUsername: trimmedString(envelope["senderUsername"]),
			GroupID:        trimmedString(envelope["groupId"]),
			GroupName:      trimmedString(envelope["groupName"]),
		}
		if payload, ok := envelope["payload"].(map[string]interface{}); ok {
			if metadata.SenderUsername == "" {
				metadata.SenderUsername = trimmedString(payload["senderUsername"])
			}
			if metadata.GroupID == "" {
				metadata.GroupID = trimmedString(payload["groupId"])
			}
			if metadata.GroupName == "" {
				if groupConfig, ok := payload["groupConfig"].(map[string]interface{}); ok {
					metadata.GroupName = trimmedString(groupConfig["name"])
				}
			}
		}
		switch {
		case metadata.SenderUsername != "" && metadata.GroupName != "":
			metadata.Body = fmt.Sprintf("%s invited you to %s", metadata.SenderUsername, metadata.GroupName)
		case metadata.SenderUsername != "":
			metadata.Body = fmt.Sprintf("%s sent you a group invite", metadata.SenderUsername)
		default:
			metadata.Body = groupInvitePushBody
		}
		return metadata
	default:
		return chatPushMetadata{}
	}
}

func (ps *PushService) TokenCount() int {
	return ps.tokenBackend.TokenCount()
}

func (ps *PushService) PlatformCounts() map[string]int {
	return ps.tokenBackend.PlatformCounts()
}

// permanentPushErrorReason classifies a push error as permanently unroutable
// (the token is dead — retrying can never succeed) and names the arm that
// decided, so post-deploy evidence is attributable. Empty string = transient.
//
// Two arms, deliberately:
//
//   - TYPED (authoritative): messaging.IsUnregistered / IsSenderIDMismatch read
//     the SDK's structured errorCode (Ext["messagingErrorCode"] == UNREGISTERED
//     / SENDER_ID_MISMATCH). These only fire when FCM returns the FcmError
//     detail.
//   - LITERAL (belt-and-braces, and the arm that actually catches today's
//     production traffic): FCM's error *message* text. The live journal shows
//     "NotRegistered", and the SAME dead peer logged "Requested entity was not
//     found." at another time — neither is the errorCode, and neither matches
//     the legacy hyphenated literals. Without this arm the fix would be inert.
//
// Deliberately NOT permanent: messaging.IsInvalidArgument — FCM also returns
// INVALID_ARGUMENT for oversized payloads, and this check runs BEFORE the
// payload-too-large branch, so including it would swallow the strict-minimal
// rescue (plan 316) and evict live tokens.
func permanentPushErrorReason(err error) string {
	if err == nil {
		return ""
	}
	if messaging.IsUnregistered(err) {
		return "typed_unregistered"
	}
	if messaging.IsSenderIDMismatch(err) {
		return "typed_sender_mismatch"
	}
	errStr := err.Error()
	for _, candidate := range []struct {
		needle string
		reason string
	}{
		{"registration-token-not-registered", "literal_legacy_not_registered"},
		{"invalid-registration-token", "literal_legacy_invalid_token"},
		{"notregistered", "literal_notregistered"},
		{"requested entity was not found", "literal_entity_not_found"},
		{"senderid mismatch", "literal_sender_mismatch"},
		{"mismatched sender", "literal_sender_mismatch"},
	} {
		if containsFold(errStr, candidate.needle) {
			return candidate.reason
		}
	}
	return ""
}

// containsFold is an ASCII case-insensitive substring test. FCM's message text
// is not case-stable ("NotRegistered" vs "NOT_REGISTERED" vs lowercase codes).
func containsFold(s, substr string) bool {
	return contains(toLowerASCII(s), toLowerASCII(substr))
}

func toLowerASCII(s string) string {
	out := []byte(s)
	for i := 0; i < len(out); i++ {
		if out[i] >= 'A' && out[i] <= 'Z' {
			out[i] += 'a' - 'A'
		}
	}
	return string(out)
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsImpl(s, substr))
}

func containsImpl(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// extractMessageId attempts to extract a message ID from the JSON payload
// for deduplication. Supports chat IDs, introduction IDs, and v2 contact
// request `msgId` values.
// Returns "" if the payload is malformed or has no extractable ID.
func extractMessageId(message string) string {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		return ""
	}

	// V2 encrypted: top-level "id" field
	if id, ok := envelope["id"].(string); ok && id != "" {
		return id
	}

	// Plan 256: direct-reaction v2 uses its immutable event identity as the
	// relay dedupe key. targetMessageId is deliberately not an event identity:
	// distinct reactions to the same authored message must remain distinct.
	if envelope["type"] == "message_reaction" {
		if eventID := exactString(envelope["eventId"]); eventID != "" {
			return eventID
		}
	}

	// Plan 257: a cryptographically valid group-reaction notification extension
	// supplies the immutable transition identity used by both memory and Redis
	// custody. Legacy or invalid extensions retain the base v1 messageId fallback.
	if reaction, recognized, valid := extractGroupReactionPushMetadata(message, "", "", nil); recognized && valid {
		return reaction.TransitionID
	}

	if id, ok := envelope["messageId"].(string); ok && id != "" {
		return id
	}

	if id, ok := envelope["msgId"].(string); ok && id != "" {
		return id
	}

	// V1 plaintext: payload.id
	if payload, ok := envelope["payload"].(map[string]interface{}); ok {
		if id, ok := payload["id"].(string); ok {
			return id
		}
		if introID, ok := payload["introductionId"].(string); ok {
			return introID
		}
	}

	return ""
}

const (
	directInboxTargetIDDedupePrefix        = "target-id:"
	directInboxEditEventIDDedupePrefix     = "edit-event-id:"
	directInboxDeletionEventIDDedupePrefix = "deletion-event-id:"
	directInboxReactionEventIDDedupePrefix = "reaction-event-id:"
)

func extractDirectDeletionCustodyDedupeKey(message string) string {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil ||
		!hasExactJSONKeys(
			envelope,
			"type",
			"version",
			"eventId",
			"senderPeerId",
			"encrypted",
		) ||
		exactString(envelope["type"]) != "message_deletion" ||
		exactString(envelope["version"]) != "2" ||
		exactString(envelope["senderPeerId"]) == "" {
		return ""
	}
	eventID := exactString(envelope["eventId"])
	encrypted, ok := envelope["encrypted"].(map[string]interface{})
	if eventID == "" || !ok ||
		!hasExactJSONKeys(encrypted, "kem", "ciphertext", "nonce") ||
		exactString(encrypted["kem"]) == "" ||
		exactString(encrypted["ciphertext"]) == "" ||
		exactString(encrypted["nonce"]) == "" {
		return ""
	}
	return directInboxDeletionEventIDDedupePrefix + eventID
}

// extractDirectReactionCustodyDedupeKey returns a namespaced custody identity
// only for a complete, exact v2 direct reaction. Custody accepts both ADD and
// REMOVE transitions. This is intentionally independent of
// extractDirectReactionPushMetadata, whose eligibility remains ADD-only.
//
// Legacy, partial, malformed, whitespace-mutated, and unsupported-action
// envelopes return an empty key so extractDirectInboxDedupeKey can preserve
// their historical target-key (or no-key) behavior.
func extractDirectReactionCustodyDedupeKey(message string) string {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil ||
		exactString(envelope["type"]) != "message_reaction" ||
		exactString(envelope["version"]) != "2" {
		return ""
	}

	eventID := exactString(envelope["eventId"])
	action := exactString(envelope["action"])
	if eventID == "" ||
		(action != "add" && action != "remove") ||
		exactString(envelope["targetMessageId"]) == "" ||
		exactString(envelope["senderPeerId"]) == "" {
		return ""
	}

	encrypted, ok := envelope["encrypted"].(map[string]interface{})
	if !ok ||
		exactString(encrypted["kem"]) == "" ||
		exactString(encrypted["ciphertext"]) == "" ||
		exactString(encrypted["nonce"]) == "" {
		return ""
	}

	return directInboxReactionEventIDDedupePrefix + eventID
}

// extractDirectInboxDedupeKey returns the relay-custody identity for a direct
// inbox envelope. It is deliberately separate from extractMessageId: push
// routing must continue to expose the authored chat target ID as message_id,
// while distinct edits of that target need distinct custody entries.
//
// New chat edits advertise an additive, authenticated eventId at the opaque
// envelope boundary. A nonblank eventId is namespaced away from target IDs so
// even equal raw strings cannot collide across the two identity kinds. Legacy
// edits have no eventId and retain the historical target-ID dedupe semantics.
func extractDirectInboxDedupeKey(message string) string {
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err == nil &&
		envelope["type"] == "chat_message" {
		if eventID, ok := envelope["eventId"].(string); ok && strings.TrimSpace(eventID) != "" {
			return directInboxEditEventIDDedupePrefix + eventID
		}
	}
	if deletionKey := extractDirectDeletionCustodyDedupeKey(message); deletionKey != "" {
		return deletionKey
	}
	if reactionKey := extractDirectReactionCustodyDedupeKey(message); reactionKey != "" {
		return reactionKey
	}

	if messageID := extractMessageId(message); messageID != "" {
		return directInboxTargetIDDedupePrefix + messageID
	}
	return ""
}

func trimmedString(raw interface{}) string {
	value, ok := raw.(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(value)
}

// --- Inbox store ---

type inboxMessage struct {
	ID          string                 `json:"id,omitempty"`
	From        string                 `json:"from"`
	Message     string                 `json:"message"`
	Timestamp   int64                  `json:"timestamp"`
	ExpiresAtMs int64                  `json:"expiresAtMs,omitempty"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
	// FDC-09 §12: the opaque wake-token the sender presented (TRANSIENT — json:"-",
	// never persisted or returned in a retrieve). Read once at store time for the
	// access-token wake gate; the durable message shape is unchanged.
	WakeToken string `json:"-"`
}

func ensureInboxMessageID(entry inboxMessage) inboxMessage {
	if entry.ID == "" {
		entry.ID = uuid.New().String()
	}
	return entry
}

// InboxStore wraps an InboxBackend and a PushService.
type InboxStore struct {
	backend  InboxBackend
	push     *PushService
	capacity int
	// now is injectable only for deterministic ACK-custody expiry tests. Every
	// production constructor installs time.Now and nil falls back to time.Now.
	now func() time.Time
	// Plan 344: default-off admission applies only to new protected writes.
	// Retrieve/ACK continue to drain a Redis lane while this kill switch is off.
	ackCustodyAdmissionEnabled bool
	// FDC-09 §12 access-token wake gate (always non-nil; fail-open until a
	// recipient registers a set).
	wakeTokens *memoryWakeTokenStore
	// Plan 256: typed direct-reaction wake is separately default-off. Ordinary
	// inbox custody and ordinary push eligibility are unchanged by this flag.
	directReactionPushEnabled bool
	// Plan 370: the paired durable wake-outcome admission is default-off and is
	// enabled by bootstrap only for the Redis authority.
	wakeOutcomeAdmissionEnabled bool
	// G26: strict-authority group content wake, default-off like every sibling
	// push flag. Custody admission and delivery are unchanged by this flag —
	// only whether a stored group message also wakes the recipient.
	groupContentPushEnabled bool
	// G27: strict-authority group reactions share direct-inbox custody but keep
	// the signed author-only audience and typed group_reaction capability.
	groupReactionPushEnabled bool
}

func (is *InboxStore) SetDirectReactionPushEnabled(enabled bool) {
	is.directReactionPushEnabled = enabled
}

func (is *InboxStore) SetGroupContentPushEnabled(enabled bool) {
	if is != nil {
		is.groupContentPushEnabled = enabled
	}
}

func (is *InboxStore) SetGroupReactionPushEnabled(enabled bool) {
	if is != nil {
		is.groupReactionPushEnabled = enabled
	}
}

func (is *InboxStore) SetWakeOutcomeAdmissionEnabled(enabled bool) {
	if is != nil {
		is.wakeOutcomeAdmissionEnabled = enabled
	}
}

func (is *InboxStore) WakeOutcomeAdmissionEnabled() bool {
	return is != nil && is.wakeOutcomeAdmissionEnabled
}

// NewInboxStore creates an InboxStore with an in-memory backend.
func NewInboxStore(push *PushService) *InboxStore {
	return &InboxStore{
		backend:                    newMemoryInboxBackend(),
		push:                       push,
		capacity:                   maxMessagesPerPeer,
		now:                        time.Now,
		ackCustodyAdmissionEnabled: loadAckCustodyAdmissionEnabledFromEnv(),
		wakeTokens:                 newMemoryWakeTokenStore(),
	}
}

// NewInboxStoreWithBackend creates an InboxStore with a custom backend.
func NewInboxStoreWithBackend(backend InboxBackend, push *PushService) *InboxStore {
	return NewInboxStoreWithBackendAndCapacity(backend, push, maxMessagesPerPeer)
}

func NewInboxStoreWithBackendAndCapacity(
	backend InboxBackend,
	push *PushService,
	capacity int,
) *InboxStore {
	if capacity <= 0 {
		capacity = maxMessagesPerPeer
	}
	return &InboxStore{
		backend:                    backend,
		push:                       push,
		capacity:                   capacity,
		now:                        time.Now,
		ackCustodyAdmissionEnabled: loadAckCustodyAdmissionEnabledFromEnv(),
		wakeTokens:                 newMemoryWakeTokenStore(),
	}
}

// RegisterWakeTokens registers the recipient's authorized opaque wake-token set
// (FDC-09 §12). The subject is the AUTHENTICATED stream peer (the dispatch arm
// passes remotePeer) — a peer registers only ITS OWN authorized set.
func (is *InboxStore) RegisterWakeTokens(peerId string, tokens []string) {
	if is.wakeTokens == nil {
		return
	}
	is.wakeTokens.RegisterWakeTokens(peerId, tokens)
}

// ClearWakeTokens drops a recipient's authorized wake-token set (e.g. on
// unregister_token — no orphaned wake authorization).
func (is *InboxStore) ClearWakeTokens(peerId string) {
	if is.wakeTokens == nil {
		return
	}
	is.wakeTokens.ClearWakeTokens(peerId)
}

type wakeOutcomePreflightFallbackKind uint8

const (
	wakeOutcomePreflightNotAttempted wakeOutcomePreflightFallbackKind = iota
	wakeOutcomePreflightLookupFailed
	wakeOutcomePreflightNoRoute
	wakeOutcomePreflightSelectedRoute
)

// wakeOutcomePreflightFallback carries the one incumbent route decision made
// before a Redis admission attempt. It is consumed only after a genuinely new
// event store. Lookup errors and nil routes stay no-provider; a selected but
// non-admitted lease feeds the existing route-bearing gateway without another
// directory read.
type wakeOutcomePreflightFallback struct {
	kind     wakeOutcomePreflightFallbackKind
	producer wakeOutcomeProducerKind
	route    pushRouteLease
}

func (is *InboxStore) Store(toPeerId string, entry inboxMessage) (InboxStoreResult, error) {
	entry = ensureInboxMessageID(entry)
	result, admissionStatus, admission, preflightFallback, handled, err := is.storeWithWakeOutcome(
		toPeerId,
		entry,
	)
	if handled {
		if err != nil {
			log.Printf("[INBOX] Store failed for %s from %s: wake outcome transaction failed",
				toPeerId[:min(20, len(toPeerId))],
				entry.From[:min(20, len(entry.From))])
			return "", err
		}
		switch result {
		case InboxStoreResultDuplicate:
			log.Printf("[INBOX] Duplicate message for %s from %s — skipped",
				toPeerId[:min(20, len(toPeerId))],
				entry.From[:min(20, len(entry.From))])
			inboxStoredCounter.Inc()
			return InboxStoreResultDuplicate, nil
		case InboxStoreResultRejectedFull:
			inboxRejectedFullCounter.Inc()
			inboxCappedCounter.Inc()
			log.Printf("[INBOX] Rejected store for %s from %s: inbox full",
				toPeerId[:min(20, len(toPeerId))],
				entry.From[:min(20, len(entry.From))])
			return InboxStoreResultRejectedFull, nil
		case InboxStoreResultStored:
			is.recordStoredWithoutPush(toPeerId, entry)
			switch admissionStatus {
			case wakeOutcomeAdmissionDelayed, wakeOutcomeAdmissionSuppressed:
				// Delayed obligations and completed/existing authority suppress the
				// incumbent immediate provider call.
			case wakeOutcomeAdmissionCapacityFallback, wakeOutcomeAdmissionImmediateFallback:
				is.launchDirectPushForWakeAdmission(toPeerId, entry, admission)
			default:
				// Unknown backend dispositions must fail toward delivery, never toward
				// silently losing the wake.
				is.launchDirectPushForWakeAdmission(toPeerId, entry, admission)
			}
			return InboxStoreResultStored, nil
		default:
			return "", fmt.Errorf("unexpected inbox store result %q", result)
		}
	}

	result, err = is.backend.Store(toPeerId, entry)
	if err != nil {
		log.Printf("[INBOX] Store failed for %s from %s: %v",
			toPeerId[:min(20, len(toPeerId))],
			entry.From[:min(20, len(entry.From))],
			err)
		return "", err
	}
	if result == InboxStoreResultDuplicate {
		// Duplicate — do not fire push notification.
		log.Printf("[INBOX] Duplicate message for %s from %s — skipped",
			toPeerId[:min(20, len(toPeerId))],
			entry.From[:min(20, len(entry.From))])
		inboxStoredCounter.Inc() // still count for metrics visibility
		return InboxStoreResultDuplicate, nil
	}
	if result == InboxStoreResultRejectedFull {
		inboxRejectedFullCounter.Inc()
		inboxCappedCounter.Inc()
		log.Printf("[INBOX] Rejected store for %s from %s: inbox full",
			toPeerId[:min(20, len(toPeerId))],
			entry.From[:min(20, len(entry.From))])
		return InboxStoreResultRejectedFull, nil
	}
	is.recordStoredWithoutPush(toPeerId, entry)
	is.launchStoredDirectPushAfterPreflight(toPeerId, entry, preflightFallback)
	return InboxStoreResultStored, nil
}

// storeWithWakeOutcome attempts the optional durable Redis admission path. A
// memory/legacy backend, an ineligible producer, or any preflight failure falls
// back to the incumbent store path without delaying delivery. Route-CAS
// conflicts are retried with one fresh lease; a second conflict also falls back
// because neither transaction committed an event or obligation.
func (is *InboxStore) storeWithWakeOutcome(
	toPeerID string,
	entry inboxMessage,
) (
	InboxStoreResult,
	wakeOutcomeAdmissionStatus,
	wakeOutcomeAdmission,
	wakeOutcomePreflightFallback,
	bool,
	error,
) {
	var zeroStatus wakeOutcomeAdmissionStatus
	if !is.WakeOutcomeAdmissionEnabled() {
		return "", zeroStatus, wakeOutcomeAdmission{}, wakeOutcomePreflightFallback{}, false, nil
	}
	backend, ok := is.backend.(interface {
		StoreWithWakeOutcome(
			toPeerID string,
			entry inboxMessage,
			admission wakeOutcomeAdmission,
		) (InboxStoreResult, wakeOutcomeAdmissionStatus, error)
	})
	if !ok {
		return "", zeroStatus, wakeOutcomeAdmission{}, wakeOutcomePreflightFallback{}, false, nil
	}

	producer, requiredCapability, verifiedEventKey, eligible := is.directWakeOutcomeProducer(toPeerID, entry)
	if !eligible {
		return "", zeroStatus, wakeOutcomeAdmission{}, wakeOutcomePreflightFallback{}, false, nil
	}

	for routeAttempt := 0; routeAttempt < 2; routeAttempt++ {
		fallback, admission, admitted := is.preflightDirectWakeOutcome(
			toPeerID,
			entry,
			producer,
			requiredCapability,
			verifiedEventKey,
		)
		if !admitted {
			return "", zeroStatus, wakeOutcomeAdmission{}, fallback, false, nil
		}

		result, status, err := backend.StoreWithWakeOutcome(toPeerID, entry, admission)
		if errors.Is(err, errWakeOutcomeRouteChanged) {
			if routeAttempt == 1 {
				return "", zeroStatus, wakeOutcomeAdmission{}, fallback, false, nil
			}
			continue
		}
		return result, status, admission, wakeOutcomePreflightFallback{}, true, err
	}

	return "", zeroStatus, wakeOutcomeAdmission{}, wakeOutcomePreflightFallback{}, false, nil
}

func (is *InboxStore) preflightDirectWakeOutcome(
	toPeerID string,
	entry inboxMessage,
	producer wakeOutcomeProducerKind,
	requiredCapability string,
	verifiedEventKey string,
) (wakeOutcomePreflightFallback, wakeOutcomeAdmission, bool) {
	fallback := wakeOutcomePreflightFallback{producer: producer}
	route, err := is.push.selectPushRoute(toPeerID, requiredCapability)
	if err != nil {
		fallback.kind = wakeOutcomePreflightLookupFailed
		return fallback, wakeOutcomeAdmission{}, false
	}
	if route == nil {
		fallback.kind = wakeOutcomePreflightNoRoute
		return fallback, wakeOutcomeAdmission{}, false
	}
	fallback.kind = wakeOutcomePreflightSelectedRoute
	fallback.route = copyPushRouteLease(*route)
	if verifiedEventKey != "" {
		admission, admitted := newWakeOutcomeAdmissionForEvent(
			toPeerID,
			producer,
			verifiedEventKey,
			*route,
			entry.Timestamp,
			directWakeOutcomeExpiryMs(entry),
		)
		return fallback, admission, admitted
	}
	admission, admitted := newWakeOutcomeAdmission(
		toPeerID,
		entry.Message,
		producer,
		*route,
		entry.Timestamp,
		directWakeOutcomeExpiryMs(entry),
	)
	return fallback, admission, admitted
}

func (is *InboxStore) directWakeOutcomeProducer(
	toPeerID string,
	entry inboxMessage,
) (wakeOutcomeProducerKind, string, string, bool) {
	if is == nil || is.push == nil {
		return 0, "", "", false
	}
	if reaction, recognized, eligible := extractDirectReactionPushMetadata(entry.Message); recognized {
		if !eligible || reaction.EnvelopeSender != entry.From || !is.directReactionPushEnabled {
			return 0, "", "", false
		}
		authorized := is.wakeTokens != nil &&
			is.wakeTokens.HasRegisteredSet(toPeerID) &&
			is.wakeTokens.IsAuthorized(toPeerID, entry.WakeToken)
		if !authorized {
			return 0, "", "", false
		}
		return wakeOutcomeProducerDirectReaction, directReactionCapability, reaction.EventID, true
	}

	metadata := extractChatPushMetadata(entry.Message)
	if !metadata.ShouldNotify || (is.wakeTokens != nil && wakeTokenGateEnforced &&
		!is.wakeTokens.IsAuthorized(toPeerID, entry.WakeToken)) {
		return 0, "", "", false
	}
	return wakeOutcomeProducerDirectMessage, "", "", true
}

func directWakeOutcomeExpiryMs(entry inboxMessage) int64 {
	if entry.ExpiresAtMs > 0 {
		return entry.ExpiresAtMs
	}
	return entry.Timestamp + maxMessageAge.Milliseconds()
}

// recordStoredAndLaunchPush is shared by legacy Store and the protected
// store-after-atomic-commit path. Callers must invoke it only for a genuinely
// new durable row; duplicates and failed/ambiguous commits never refanout.
func (is *InboxStore) recordStoredAndLaunchPush(toPeerId string, entry inboxMessage) {
	is.recordStoredWithoutPush(toPeerId, entry)
	is.launchStoredDirectPush(toPeerId, entry)
}

func (is *InboxStore) recordStoredWithoutPush(toPeerId string, entry inboxMessage) {
	inboxStoredCounter.Inc()
	if biz != nil {
		biz.RecordMessageStored()
	}

	log.Printf("[INBOX] Stored message for %s from %s",
		toPeerId[:min(20, len(toPeerId))],
		entry.From[:min(20, len(entry.From))])
}

func (is *InboxStore) launchStoredDirectPush(toPeerId string, entry inboxMessage) {
	// Fire push only for supported user-visible envelope types (the existing
	// ShouldNotify type filter) AND only when the sender is authorized to wake the
	// recipient (FDC-09 §12 access-token gate — LAYERED ON TOP of ShouldNotify,
	// never replacing or widening it). The gate is presence-INDEPENDENT: the
	// store->push seam never consults the presence store, so a wrong presence value
	// can never suppress (or trigger) a wake (PRESENCE_NEVER_LOAD_BEARING). It is
	// FAIL-OPEN when the recipient has registered no wake-token set, so existing
	// push delivery for already-paired contacts is unchanged. The message is
	// already STORED above either way — only the wake is gated (delivery preserved).
	if reaction, recognizedReaction, eligibleReaction := extractDirectReactionPushMetadata(entry.Message); recognizedReaction {
		if !eligibleReaction || reaction.EnvelopeSender != entry.From || !is.directReactionPushEnabled {
			return
		}
		// Unlike the global ordinary-message wake gate, direct reactions NEVER
		// fail open. The recipient must have explicitly registered a set and the
		// presented opaque token must be a member of it.
		authorized := is.wakeTokens != nil &&
			is.wakeTokens.HasRegisteredSet(toPeerId) &&
			is.wakeTokens.IsAuthorized(toPeerId, entry.WakeToken)
		if !authorized {
			pushSentCounter.WithLabelValues("reaction_unauthorized").Inc()
			return
		}
		if is.push == nil {
			pushSentCounter.WithLabelValues("reaction_incapable").Inc()
			return
		}
		route, err := is.push.selectPushRoute(toPeerId, directReactionCapability)
		if err != nil {
			pushSentCounter.WithLabelValues("reaction_route_error").Inc()
			return
		}
		if route == nil {
			pushSentCounter.WithLabelValues("reaction_incapable").Inc()
			return
		}
		go is.push.sendReactionNotificationForRoute(
			context.Background(),
			toPeerId,
			*route,
			entry.From,
			entry.Message,
		)
		return
	}

	// G26: strict-authority group content. Placed BEFORE the chat-metadata
	// switch because a replay envelope has no `type` field and would otherwise
	// fall to that switch's default and be silently dropped. Recognized-but-
	// ineligible shapes return here rather than falling through, so a reaction
	// can never be routed onto the group-message audience.
	if metadata, recognizedContent, eligibleContent := extractGroupContentPushMetadata(entry.Message); recognizedContent {
		if metadata.PayloadType == groupContentPayloadTypeReaction {
			reaction, recognizedReaction, validReaction := extractGroupReactionPushMetadata(
				entry.Message,
				metadata.GroupID,
				entry.From,
				nil,
			)
			if !recognizedReaction || !validReaction || reaction.Action != "add" ||
				!is.groupReactionPushEnabled {
				groupReactionWakeCounter.WithLabelValues("invalid_or_disabled").Inc()
				log.Printf("[GROUP_REACTION_WAKE] outcome=invalid_or_disabled")
				return
			}
			if !containsExactString(reaction.NotificationRecipientTransportPeerIDs, toPeerId) {
				groupReactionWakeCounter.WithLabelValues("no_wake_recipients").Inc()
				log.Printf("[GROUP_REACTION_WAKE] outcome=no_wake_recipients")
				return
			}
			// Strict custody is already per recipient. The absent-set behavior stays
			// rollout-safe/fail-open, while an explicitly registered set is
			// authoritative regardless of the legacy global enforcement switch.
			if is.wakeTokens != nil && is.wakeTokens.HasRegisteredSet(toPeerId) &&
				!is.wakeTokens.IsAuthorized(toPeerId, entry.WakeToken) {
				groupReactionWakeCounter.WithLabelValues("unauthorized_wake").Inc()
				log.Printf("[GROUP_REACTION_WAKE] outcome=unauthorized_wake")
				return
			}
			if is.push == nil {
				groupReactionWakeCounter.WithLabelValues("push_unavailable").Inc()
				log.Printf("[GROUP_REACTION_WAKE] outcome=push_unavailable")
				return
			}
			route, err := is.push.selectPushRoute(toPeerId, groupReactionCapability)
			if err != nil {
				groupReactionWakeCounter.WithLabelValues("route_error").Inc()
				return
			}
			if route == nil {
				recordGroupReactionIncapableSkipped()
				return
			}
			groupReactionWakeCounter.WithLabelValues("attempted").Inc()
			log.Printf("[GROUP_REACTION_WAKE] outcome=dispatched")
			go is.push.sendGroupReactionNotificationForRoute(
				context.Background(),
				toPeerId,
				*route,
				metadata.GroupID,
				entry.Message,
				reaction,
			)
			return
		}
		if !eligibleContent || !is.groupContentPushEnabled {
			groupContentWakeCounter.WithLabelValues("invalid_or_disabled").Inc()
			return
		}
		// Same fail-open wake-token gate as an ordinary direct message, and for
		// the same reason: this envelope IS the group's ordinary message
		// traffic, only carried per recipient instead of over the topic.
		if is.wakeTokens != nil && wakeTokenGateEnforced &&
			!is.wakeTokens.IsAuthorized(toPeerId, entry.WakeToken) {
			pushSentCounter.WithLabelValues("unauthorized_wake").Inc()
			groupContentWakeCounter.WithLabelValues("unauthorized_wake").Inc()
			log.Printf("[GROUP_CONTENT_WAKE] outcome=unauthorized_wake")
			return
		}
		if is.push == nil {
			groupContentWakeCounter.WithLabelValues("push_unavailable").Inc()
			return
		}
		route, err := is.push.selectPushRoute(toPeerId, "")
		if err != nil {
			groupContentWakeCounter.WithLabelValues("route_error").Inc()
			return
		}
		if route == nil {
			groupContentWakeCounter.WithLabelValues("incapable_skipped").Inc()
			return
		}
		groupContentWakeCounter.WithLabelValues("attempted").Inc()
		log.Printf("[GROUP_CONTENT_WAKE] outcome=attempted")
		go is.push.sendGroupContentNotificationForRoute(
			context.Background(),
			toPeerId,
			*route,
			metadata,
			entry.Message,
		)
		return
	}

	if metadata := extractChatPushMetadata(entry.Message); metadata.ShouldNotify && is.push != nil {
		if is.wakeTokens == nil || !wakeTokenGateEnforced ||
			is.wakeTokens.IsAuthorized(toPeerId, entry.WakeToken) {
			go is.push.sendStoredNotification(
				context.Background(),
				toPeerId,
				entry.From,
				entry.Message,
				entry.ID,
			)
		} else {
			pushSentCounter.WithLabelValues("unauthorized_wake").Inc()
			log.Printf("[INBOX] Suppressed unauthorized wake for %s (no valid wake-token; message still stored)",
				toPeerId[:min(20, len(toPeerId))])
		}
	}
}

func (is *InboxStore) launchStoredDirectPushAfterPreflight(
	toPeerID string,
	entry inboxMessage,
	fallback wakeOutcomePreflightFallback,
) {
	if fallback.kind == wakeOutcomePreflightNotAttempted {
		is.launchStoredDirectPush(toPeerID, entry)
		return
	}

	// Re-run the incumbent authorization/type decision after persistence. This
	// preserves wake-token and reaction-flag changes without repeating the route
	// lookup that the admission preflight already consumed.
	producer, _, _, eligible := is.directWakeOutcomeProducer(toPeerID, entry)
	if !eligible || producer != fallback.producer {
		is.launchStoredDirectPush(toPeerID, entry)
		return
	}

	switch fallback.kind {
	case wakeOutcomePreflightLookupFailed:
		if producer == wakeOutcomeProducerDirectReaction {
			pushSentCounter.WithLabelValues("reaction_route_error").Inc()
		} else {
			pushSentCounter.WithLabelValues("route_lookup_failed").Inc()
		}
	case wakeOutcomePreflightNoRoute:
		if producer == wakeOutcomeProducerDirectReaction {
			pushSentCounter.WithLabelValues("reaction_incapable").Inc()
		} else {
			recordDirectMissingPushRoute()
		}
	case wakeOutcomePreflightSelectedRoute:
		route := copyPushRouteLease(fallback.route)
		if producer == wakeOutcomeProducerDirectReaction {
			go is.push.sendReactionNotificationForRoute(
				context.Background(),
				toPeerID,
				route,
				entry.From,
				entry.Message,
			)
		} else {
			go is.push.sendStoredNotification(
				context.Background(),
				toPeerID,
				entry.From,
				entry.Message,
				entry.ID,
				route,
			)
		}
	}
}

func (is *InboxStore) launchDirectPushForWakeAdmission(
	toPeerID string,
	_ inboxMessage,
	admission wakeOutcomeAdmission,
) {
	if is == nil || is.push == nil {
		return
	}
	route := admission.Route()
	go is.push.sendOpaqueWakeThroughGateway(
		context.Background(),
		toPeerID,
		route,
		admission.policy,
	)
}

func (is *InboxStore) Capacity() int {
	if is.capacity <= 0 {
		return maxMessagesPerPeer
	}
	return is.capacity
}

func (is *InboxStore) Retrieve(peerId string, limit int) []inboxMessage {
	messages, hasMore := is.backend.Retrieve(peerId, limit)

	if len(messages) == 0 {
		log.Printf("[INBOX] No messages for %s", peerId[:min(20, len(peerId))])
		return nil
	}

	inboxRetrievedCounter.Add(float64(len(messages)))

	remaining := 0
	if hasMore {
		remaining = is.backend.Count(peerId)
	}
	log.Printf("[INBOX] Retrieved %d message(s) for %s — deleted from memory (%d remaining)",
		len(messages), peerId[:min(20, len(peerId))], remaining)
	return messages
}

// RetrieveWithMeta retrieves messages and returns pagination metadata.
func (is *InboxStore) RetrieveWithMeta(peerId string, limit int) ([]inboxMessage, bool) {
	messages, hasMore := is.backend.Retrieve(peerId, limit)

	if len(messages) > 0 {
		inboxRetrievedCounter.Add(float64(len(messages)))
	}

	return messages, hasMore
}

// RetrievePendingWithMeta retrieves messages without deleting them and returns
// pagination metadata.
func (is *InboxStore) RetrievePendingWithMeta(peerId string, limit int) ([]inboxMessage, bool) {
	return is.backend.RetrievePending(peerId, limit)
}

// Ack deletes only the inbox entries whose stable relay entry IDs match the
// provided list.
func (is *InboxStore) Ack(peerId string, entryIDs []string) (int, error) {
	removed, err := is.backend.Ack(peerId, entryIDs)
	if err != nil {
		return 0, err
	}

	if removed > 0 {
		log.Printf("[INBOX] Acked %d message(s) for %s",
			removed, peerId[:min(20, len(peerId))])
	}

	return removed, nil
}

func (is *InboxStore) Count(peerId string) int {
	return is.backend.Count(peerId)
}

func (is *InboxStore) Stats() (totalPeers, totalMessages int) {
	return is.backend.Stats()
}

// --- Group Inbox store ---

type groupInboxMessage struct {
	From             string   `json:"from"`
	Message          string   `json:"message"`
	Timestamp        int64    `json:"timestamp"`
	ID               string   `json:"id,omitempty"`
	RecipientPeerIds []string `json:"-"`
}

type groupInboxHistoryGap struct {
	GroupId                string   `json:"groupId"`
	GapId                  string   `json:"gapId"`
	MissingAfterMessageId  string   `json:"missingAfterMessageId"`
	MissingBeforeMessageId string   `json:"missingBeforeMessageId"`
	ExpectedRangeHash      string   `json:"expectedRangeHash"`
	ExpectedHeadMessageId  string   `json:"expectedHeadMessageId"`
	CandidateSourcePeerIds []string `json:"candidateSourcePeerIds"`
}

// GroupInboxStore wraps a GroupInboxBackend.
type GroupInboxStore struct {
	backend                     GroupInboxBackend
	push                        *PushService
	groupReactionPushEnabled    bool
	wakeOutcomeAdmissionEnabled bool
}

// NewGroupInboxStore creates a store with an in-memory backend.
func NewGroupInboxStore(maxPerGroup int, ttl time.Duration) *GroupInboxStore {
	return &GroupInboxStore{
		backend: newMemoryGroupInboxBackend(maxPerGroup, ttl),
	}
}

// NewGroupInboxStoreWithBackend creates a store with a custom backend.
func NewGroupInboxStoreWithBackend(backend GroupInboxBackend) *GroupInboxStore {
	return &GroupInboxStore{
		backend: backend,
	}
}

func (s *GroupInboxStore) SetPush(push *PushService) {
	s.push = push
}

func (s *GroupInboxStore) SetGroupReactionPushEnabled(enabled bool) {
	s.groupReactionPushEnabled = enabled
}

func (s *GroupInboxStore) SetWakeOutcomeAdmissionEnabled(enabled bool) {
	if s != nil {
		s.wakeOutcomeAdmissionEnabled = enabled
	}
}

func (s *GroupInboxStore) WakeOutcomeAdmissionEnabled() bool {
	return s != nil && s.wakeOutcomeAdmissionEnabled
}

func (s *GroupInboxStore) Store(groupId, from, message string) error {
	_, err := s.store(groupId, from, message, []string{from})
	return err
}

func (s *GroupInboxStore) store(
	groupId string,
	from string,
	message string,
	recipientPeerIds []string,
) (GroupInboxStoreResult, error) {
	normalizedRecipients := normalizePeerIds(recipientPeerIds)
	if len(normalizedRecipients) == 0 {
		return "", fmt.Errorf("recipientPeerIds required")
	}

	result, err := s.backend.StoreWithRecipients(
		groupId,
		from,
		message,
		normalizedRecipients,
	)
	if err != nil {
		return "", err
	}
	if result == GroupInboxStoreResultDuplicate {
		log.Printf("[GROUP_INBOX] Duplicate message for group %s from %s skipped",
			groupId[:min(20, len(groupId))],
			from[:min(20, len(from))])
		return GroupInboxStoreResultDuplicate, nil
	}
	if result == GroupInboxStoreResultStored {
		s.recordGroupStored(groupId, from)
	}
	return result, nil
}

func (s *GroupInboxStore) recordGroupStored(groupID, from string) {
	groupInboxStoredCounter.Inc()
	log.Printf("[GROUP_INBOX] Stored message for group %s from %s",
		groupID[:min(20, len(groupID))],
		from[:min(20, len(from))])
}

type groupWakeOutcomeDispatch struct {
	preflight    wakeOutcomePreflightFallback
	admission    wakeOutcomeAdmission
	hasAdmission bool
	status       wakeOutcomeAdmissionStatus
	hasResult    bool
}

func (s *GroupInboxStore) StoreWithPushRecipients(
	groupId string,
	from string,
	message string,
	recipientPeerIds []string,
) error {
	normalizedRecipients := normalizePeerIds(recipientPeerIds)
	reaction, recognizedReaction, validReaction := extractGroupReactionPushMetadata(
		message,
		groupId,
		from,
		normalizedRecipients,
	)
	if recognizedReaction && validReaction {
		// Persist the exact canonical replay set that was signed. Notification
		// recipients remain a distinct verified subset and never narrow custody.
		normalizedRecipients = append(
			[]string(nil),
			reaction.ReplayRecipientTransportPeerIDs...,
		)
	}
	result, wakeDispatches, handled, err := s.storeWithWakeOutcomes(
		groupId,
		from,
		message,
		normalizedRecipients,
		reaction,
		recognizedReaction,
		validReaction,
	)
	if !handled {
		result, err = s.store(groupId, from, message, normalizedRecipients)
	} else if err == nil && result == GroupInboxStoreResultStored {
		s.recordGroupStored(groupId, from)
	}
	if err != nil {
		return err
	}
	if result == GroupInboxStoreResultDuplicate {
		if recognizedReaction && validReaction {
			groupReactionWakeCounter.WithLabelValues("duplicate_suppressed").Inc()
			log.Printf("[GROUP_REACTION_WAKE] outcome=duplicate_suppressed")
		}
		return nil
	}
	if recognizedReaction {
		// Legacy, malformed, REMOVE, incapable, and flag-off reactions are silent
		// custody. Crucially, none can fall through to group_message fanout.
		if !validReaction || reaction.Action != "add" || !s.groupReactionPushEnabled {
			// Plan 320 P3: this decline used to be entirely silent, so a wake lost
			// here was invisible to every counter and journal line.
			groupReactionWakeCounter.WithLabelValues("invalid_or_disabled").Inc()
			log.Printf("[GROUP_REACTION_WAKE] outcome=invalid_or_disabled")
			return nil
		}
		s.fanOutGroupReactionPush(
			groupId,
			from,
			message,
			reaction,
			wakeDispatches,
		)
		return nil
	}

	if !s.shouldFanoutPush(groupId, message) {
		return nil
	}

	s.fanOutPush(
		groupId,
		from,
		normalizedRecipients,
		message,
		wakeDispatches,
	)
	return nil
}

// storeWithWakeOutcomes admits all qualifying recipients alongside the group
// event in one optional Redis transaction. A route-CAS conflict rebuilds the
// complete recipient set once; a second conflict returns to the incumbent
// immediate path, and no split event/obligation commit is possible.
func (s *GroupInboxStore) storeWithWakeOutcomes(
	groupID string,
	from string,
	message string,
	recipientPeerIDs []string,
	reaction groupReactionPushMetadata,
	recognizedReaction bool,
	validReaction bool,
) (
	GroupInboxStoreResult,
	map[string]groupWakeOutcomeDispatch,
	bool,
	error,
) {
	if !s.WakeOutcomeAdmissionEnabled() {
		return "", nil, false, nil
	}
	backend, ok := s.backend.(interface {
		StoreWithRecipientsAndWakeOutcomes(
			groupID string,
			from string,
			message string,
			recipientPeerIDs []string,
			admissions []wakeOutcomeAdmission,
		) (GroupInboxStoreResult, []wakeOutcomeAdmissionResult, error)
	})
	if !ok || s.push == nil {
		return "", nil, false, nil
	}

	producer := wakeOutcomeProducerGroupMessage
	requiredCapability := ""
	verifiedEventKey := ""
	wakeRecipients := recipientPeerIDs
	if recognizedReaction {
		if !validReaction || reaction.Action != "add" || !s.groupReactionPushEnabled {
			return "", nil, false, nil
		}
		producer = wakeOutcomeProducerGroupReaction
		requiredCapability = groupReactionCapability
		verifiedEventKey = reaction.TransitionID
		wakeRecipients = reaction.NotificationRecipientTransportPeerIDs
	}

	storedAt := time.Now()
	eventTTL := groupMessageTTL
	if redisBackend, ok := s.backend.(*redisGroupInboxBackend); ok {
		if redisBackend.wakeOutcomes != nil {
			storedAt = redisBackend.wakeOutcomes.nowTime()
		}
		if redisBackend.ttl > 0 && redisBackend.ttl < eventTTL {
			eventTTL = redisBackend.ttl
		}
	}
	storedAtMs := storedAt.UnixMilli()
	eventExpiresAtMs := storedAtMs + eventTTL.Milliseconds()
	for routeAttempt := 0; routeAttempt < 2; routeAttempt++ {
		admissions, dispatches := s.groupWakeOutcomeAdmissions(
			groupID,
			from,
			message,
			wakeRecipients,
			producer,
			requiredCapability,
			verifiedEventKey,
			storedAtMs,
			eventExpiresAtMs,
		)
		if len(admissions) == 0 {
			return "", groupWakeOutcomeFallbackDispatches(dispatches), false, nil
		}

		result, admissionResults, err := backend.StoreWithRecipientsAndWakeOutcomes(
			groupID,
			from,
			message,
			recipientPeerIDs,
			admissions,
		)
		if errors.Is(err, errWakeOutcomeRouteChanged) {
			if routeAttempt == 1 {
				return "", groupWakeOutcomeFallbackDispatches(dispatches), false, nil
			}
			continue
		}
		if err != nil {
			return "", nil, true, err
		}
		return result, correlateGroupWakeOutcomeDispatches(
			admissions,
			admissionResults,
			dispatches,
		), true, nil
	}

	return "", nil, false, nil
}

func (s *GroupInboxStore) groupWakeOutcomeAdmissions(
	groupID string,
	from string,
	message string,
	recipientPeerIDs []string,
	producer wakeOutcomeProducerKind,
	requiredCapability string,
	verifiedEventKey string,
	storedAtMs int64,
	eventExpiresAtMs int64,
) ([]wakeOutcomeAdmission, map[string]groupWakeOutcomeDispatch) {
	normalizedRecipients := normalizePeerIds(recipientPeerIDs)
	admissions := make([]wakeOutcomeAdmission, 0, len(normalizedRecipients))
	dispatches := make(map[string]groupWakeOutcomeDispatch, len(normalizedRecipients))
	for _, recipientPeerID := range normalizedRecipients {
		if recipientPeerID == "" || recipientPeerID == from {
			continue
		}
		fallback := wakeOutcomePreflightFallback{producer: producer}
		route, err := s.push.selectPushRoute(recipientPeerID, requiredCapability)
		if err != nil {
			fallback.kind = wakeOutcomePreflightLookupFailed
			dispatches[recipientPeerID] = groupWakeOutcomeDispatch{preflight: fallback}
			continue
		}
		if route == nil {
			fallback.kind = wakeOutcomePreflightNoRoute
			dispatches[recipientPeerID] = groupWakeOutcomeDispatch{preflight: fallback}
			continue
		}
		fallback.kind = wakeOutcomePreflightSelectedRoute
		fallback.route = copyPushRouteLease(*route)
		var admission wakeOutcomeAdmission
		var admitted bool
		if verifiedEventKey != "" {
			admission, admitted = newWakeOutcomeAdmissionForEvent(
				recipientPeerID,
				producer,
				verifiedEventKey,
				*route,
				storedAtMs,
				eventExpiresAtMs,
			)
		} else {
			admission, admitted = newWakeOutcomeAdmission(
				recipientPeerID,
				message,
				producer,
				*route,
				storedAtMs,
				eventExpiresAtMs,
			)
		}
		if admitted && producer == wakeOutcomeProducerGroupMessage {
			identity, validIdentity := newGroupMessageDispatchAdmissionIdentity(
				recipientPeerID,
				groupID,
				extractMessageId(message),
			)
			if validIdentity {
				admission.groupMessageDispatchAdmissionKey = identity.storageKey()
			}
		}
		dispatch := groupWakeOutcomeDispatch{preflight: fallback}
		if admitted {
			admissions = append(admissions, admission)
			dispatch.admission = admission
			dispatch.hasAdmission = true
		}
		dispatches[recipientPeerID] = dispatch
	}
	return admissions, dispatches
}

func correlateGroupWakeOutcomeDispatches(
	admissions []wakeOutcomeAdmission,
	results []wakeOutcomeAdmissionResult,
	dispatches map[string]groupWakeOutcomeDispatch,
) map[string]groupWakeOutcomeDispatch {
	if dispatches == nil {
		dispatches = make(map[string]groupWakeOutcomeDispatch, len(admissions))
	}
	for _, admission := range admissions {
		dispatch := dispatches[admission.RecipientPeerID()]
		dispatch.admission = admission
		dispatch.hasAdmission = true
		dispatches[admission.RecipientPeerID()] = dispatch
	}
	for _, result := range results {
		dispatch, ok := dispatches[result.recipientPeerID]
		if !ok || dispatch.admission.Correlation() != result.correlation {
			continue
		}
		dispatch.status = result.status
		dispatch.hasResult = true
		dispatches[result.recipientPeerID] = dispatch
	}
	return dispatches
}

func groupWakeOutcomeFallbackDispatches(
	dispatches map[string]groupWakeOutcomeDispatch,
) map[string]groupWakeOutcomeDispatch {
	for recipientPeerID, dispatch := range dispatches {
		dispatch.admission = wakeOutcomeAdmission{}
		dispatch.hasAdmission = false
		dispatch.status = ""
		dispatch.hasResult = false
		dispatches[recipientPeerID] = dispatch
	}
	return dispatches
}

func suppressImmediateWake(dispatch groupWakeOutcomeDispatch) bool {
	return dispatch.hasResult &&
		(dispatch.status == wakeOutcomeAdmissionDelayed ||
			dispatch.status == wakeOutcomeAdmissionSuppressed)
}

func recordGroupReactionIncapableSkipped() {
	groupReactionWakeCounter.WithLabelValues("incapable_skipped").Inc()
	log.Printf("[GROUP_REACTION_WAKE] outcome=incapable_skipped")
}

func (s *GroupInboxStore) fanOutGroupReactionPush(
	groupID string,
	from string,
	message string,
	metadata groupReactionPushMetadata,
	wakeDispatches map[string]groupWakeOutcomeDispatch,
) {
	if s.push == nil {
		// Plan 320 P3: previously a silent return.
		groupReactionWakeCounter.WithLabelValues("push_unavailable").Inc()
		log.Printf("[GROUP_REACTION_WAKE] outcome=push_unavailable")
		return
	}
	if len(metadata.NotificationRecipientTransportPeerIDs) == 0 {
		groupReactionWakeCounter.WithLabelValues("no_wake_recipients").Inc()
		log.Printf("[GROUP_REACTION_WAKE] outcome=no_wake_recipients")
		return
	}
	for _, peerID := range metadata.NotificationRecipientTransportPeerIDs {
		if peerID == "" || peerID == from {
			// Plan 320 P3: the third silent decline. Counting it is what makes the
			// per-transition accounting identity hold (emitted outcomes ==
			// len(NotificationRecipientTransportPeerIDs)).
			groupReactionWakeCounter.WithLabelValues("self_or_empty_skipped").Inc()
			continue
		}
		dispatch, preflighted := wakeDispatches[peerID]
		var route pushRouteLease
		if dispatch.hasAdmission {
			// The exact route and producer eligibility were CAS-valid with the
			// group event. Count the same synchronous attempted disposition as the
			// incumbent path even when the provider call is delayed/suppressed.
			route = dispatch.admission.Route()
		} else if preflighted {
			switch dispatch.preflight.kind {
			case wakeOutcomePreflightLookupFailed:
				groupReactionWakeCounter.WithLabelValues("route_error").Inc()
				continue
			case wakeOutcomePreflightNoRoute:
				recordGroupReactionIncapableSkipped()
				continue
			case wakeOutcomePreflightSelectedRoute:
				route = copyPushRouteLease(dispatch.preflight.route)
			default:
				preflighted = false
			}
		}
		if !dispatch.hasAdmission && !preflighted {
			selected, err := s.push.selectPushRoute(peerID, groupReactionCapability)
			if err != nil {
				groupReactionWakeCounter.WithLabelValues("route_error").Inc()
				continue
			}
			if selected == nil {
				recordGroupReactionIncapableSkipped()
				continue
			}
			route = *selected
		}
		groupReactionWakeCounter.WithLabelValues("attempted").Inc()
		log.Printf("[GROUP_REACTION_WAKE] outcome=dispatched")
		if dispatch.hasAdmission {
			if suppressImmediateWake(dispatch) {
				continue
			}
			go s.push.sendOpaqueWakeThroughGateway(
				context.Background(),
				peerID,
				route,
				dispatch.admission.policy,
			)
			continue
		}
		go s.push.sendGroupReactionNotificationForRoute(
			context.Background(),
			peerID,
			route,
			groupID,
			message,
			metadata,
		)
	}
}

func (s *GroupInboxStore) shouldFanoutPush(groupId, message string) bool {
	if s.push == nil {
		return false
	}
	if len(s.backend.RetrieveSince(groupId, 0)) == 0 {
		return false
	}

	messageID := extractMessageId(message)
	if messageID == "" {
		return true
	}

	seen := 0
	for _, stored := range s.backend.RetrieveSince(groupId, 0) {
		if extractMessageId(stored.Message) == messageID {
			seen++
			if seen > 1 {
				return false
			}
		}
	}
	return seen == 1
}

func (s *GroupInboxStore) fanOutPush(
	groupId string,
	from string,
	recipientPeerIds []string,
	message string,
	wakeDispatches map[string]groupWakeOutcomeDispatch,
) {
	if s.push == nil || len(recipientPeerIds) == 0 {
		return
	}

	messageID := extractMessageId(message)
	seen := make(map[string]struct{}, len(recipientPeerIds))
	for _, peerID := range recipientPeerIds {
		if peerID == "" || peerID == from {
			continue
		}
		if _, ok := seen[peerID]; ok {
			continue
		}
		seen[peerID] = struct{}{}
		if dispatch, preflighted := wakeDispatches[peerID]; preflighted {
			if dispatch.hasAdmission {
				if suppressImmediateWake(dispatch) {
					continue
				}
				go s.push.sendGroupOpaqueWakeThroughGateway(
					context.Background(),
					peerID,
					groupId,
					messageID,
					dispatch.admission.Route(),
					dispatch.admission.policy,
				)
				continue
			}
			switch dispatch.preflight.kind {
			case wakeOutcomePreflightLookupFailed:
				pushSentCounter.WithLabelValues("route_lookup_failed").Inc()
				continue
			case wakeOutcomePreflightNoRoute:
				recordGroupMissingPushRoute()
				continue
			case wakeOutcomePreflightSelectedRoute:
				go s.push.SendGroupNotification(
					context.Background(),
					peerID,
					groupId,
					from,
					messageID,
					message,
					dispatch.preflight.route,
				)
				continue
			}
		}
		go s.push.SendGroupNotification(
			context.Background(),
			peerID,
			groupId,
			from,
			messageID,
			message,
		)
	}
}

func (s *GroupInboxStore) Retrieve(groupId string, sinceTimestamp int64) []groupInboxMessage {
	result := s.backend.RetrieveSince(groupId, sinceTimestamp)
	groupInboxRetrievedCounter.Add(float64(len(result)))

	log.Printf("[GROUP_INBOX] Retrieved %d message(s) for group %s (since=%d)",
		len(result), groupId[:min(20, len(groupId))], sinceTimestamp)
	return result
}

func (s *GroupInboxStore) RetrieveAuthorized(
	groupId string,
	sinceTimestamp int64,
	requesterPeerId string,
) []groupInboxMessage {
	messages := s.backend.RetrieveSince(groupId, sinceTimestamp)
	result := filterGroupInboxMessagesForPeer(messages, requesterPeerId)
	groupInboxRetrievedCounter.Add(float64(len(result)))

	log.Printf("[GROUP_INBOX] Retrieved %d authorized message(s) for group %s peer %s (since=%d)",
		len(result),
		groupId[:min(20, len(groupId))],
		requesterPeerId[:min(20, len(requesterPeerId))],
		sinceTimestamp)
	return result
}

// RetrieveWithCursor retrieves messages using cursor-based pagination.
func (s *GroupInboxStore) RetrieveWithCursor(groupId string, cursor string, limit int) ([]groupInboxMessage, string, []groupInboxHistoryGap) {
	messages, nextCursor, historyGaps := s.backend.RetrieveCursor(groupId, cursor, limit)
	groupInboxRetrievedCounter.Add(float64(len(messages)))
	return messages, nextCursor, historyGaps
}

func (s *GroupInboxStore) RetrieveWithCursorAuthorized(
	groupId string,
	cursor string,
	limit int,
	requesterPeerId string,
) ([]groupInboxMessage, string, []groupInboxHistoryGap) {
	if limit <= 0 {
		return nil, "", nil
	}

	allMessages := s.backend.RetrieveSince(groupId, 0)
	cursorFound := cursor == ""
	startIdx := 0
	if cursor != "" {
		for i, message := range allMessages {
			if message.ID == cursor {
				startIdx = i + 1
				cursorFound = true
				break
			}
		}
	}

	result := make([]groupInboxMessage, 0, min(limit, len(allMessages)))
	lastReturnedIndex := -1

	for i := startIdx; i < len(allMessages); i++ {
		message := allMessages[i]
		if !groupInboxMessageAuthorizedForPeer(message, requesterPeerId) {
			continue
		}
		result = append(result, message)
		lastReturnedIndex = i
		if len(result) == limit {
			break
		}
	}

	if len(result) == 0 {
		return nil, "", nil
	}

	nextCursor := ""
	for i := lastReturnedIndex + 1; i < len(allMessages); i++ {
		if groupInboxMessageAuthorizedForPeer(allMessages[i], requesterPeerId) {
			nextCursor = result[len(result)-1].ID
			break
		}
	}

	groupInboxRetrievedCounter.Add(float64(len(result)))
	return result, nextCursor, buildGroupInboxHistoryGaps(groupId, cursor, cursorFound, result)
}

func (s *GroupInboxStore) RetrieveHistoryRepairRangeAuthorized(
	groupId string,
	missingAfterMessageId string,
	missingBeforeMessageId string,
	limit int,
	requesterPeerId string,
) ([]groupInboxMessage, string, string) {
	if limit <= 0 {
		limit = 50
	}

	allMessages := s.backend.RetrieveSince(groupId, 0)
	startIdx := 0
	if missingAfterMessageId != "" {
		for i, message := range allMessages {
			if message.ID == missingAfterMessageId {
				startIdx = i + 1
				break
			}
		}
	}

	result := make([]groupInboxMessage, 0, min(limit, len(allMessages)))
	for i := startIdx; i < len(allMessages) && len(result) < limit; i++ {
		message := allMessages[i]
		if !groupInboxMessageAuthorizedForPeer(message, requesterPeerId) {
			continue
		}
		result = append(result, message)
		if message.ID == missingBeforeMessageId {
			break
		}
	}

	if len(result) == 0 {
		return nil, "", ""
	}
	return result, computeGroupHistoryRangeHash(result), result[len(result)-1].ID
}

func buildGroupInboxHistoryGaps(
	groupId string,
	cursor string,
	cursorFound bool,
	repairMessages []groupInboxMessage,
) []groupInboxHistoryGap {
	if cursor == "" || cursorFound || len(repairMessages) == 0 {
		return nil
	}

	headMessageID := repairMessages[len(repairMessages)-1].ID
	rangeHash := computeGroupHistoryRangeHash(repairMessages)
	gapSeed := fmt.Sprintf("%s|%s|%s|%s", groupId, cursor, headMessageID, rangeHash)
	gapHash := sha256.Sum256([]byte(gapSeed))
	return []groupInboxHistoryGap{{
		GroupId:                groupId,
		GapId:                  fmt.Sprintf("relay-gap-%x", gapHash[:8]),
		MissingAfterMessageId:  cursor,
		MissingBeforeMessageId: headMessageID,
		ExpectedRangeHash:      rangeHash,
		ExpectedHeadMessageId:  headMessageID,
		CandidateSourcePeerIds: groupInboxCandidateSourcePeerIds(repairMessages),
	}}
}

func groupInboxCandidateSourcePeerIds(messages []groupInboxMessage) []string {
	seen := make(map[string]struct{})
	result := make([]string, 0)
	add := func(peerId string) {
		peerId = strings.TrimSpace(peerId)
		if peerId == "" {
			return
		}
		if _, ok := seen[peerId]; ok {
			return
		}
		seen[peerId] = struct{}{}
		result = append(result, peerId)
	}

	for _, message := range messages {
		add(message.From)
		for _, peerId := range message.RecipientPeerIds {
			add(peerId)
		}
	}
	return result
}

func computeGroupHistoryRangeHash(messages []groupInboxMessage) string {
	parts := make([]string, 0, len(messages))
	for _, message := range messages {
		payload := map[string]interface{}{
			"from":      message.From,
			"message":   message.Message,
			"timestamp": message.Timestamp,
		}
		// SetEscapeHTML(false): the Dart client's jsonEncode does NOT escape
		// < > &, so the relay must not either or the two range hashes diverge
		// (finding 06 Phase 1C). json.Encoder.Encode appends a trailing
		// newline, trimmed here before joining with the inter-message "\n".
		//
		// Caveat: encoding/json still escapes U+2028/U+2029 even with HTML
		// escaping off, while Dart's jsonEncode emits them raw — a message with
		// those code points would hash differently across languages. Unreachable
		// for real group messages (the hashed `message` is the base64/ASCII
		// encrypted offline-replay envelope); see the Dart twin's doc comment.
		var buf bytes.Buffer
		enc := json.NewEncoder(&buf)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(payload); err != nil {
			continue
		}
		parts = append(parts, strings.TrimRight(buf.String(), "\n"))
	}
	sum := sha256.Sum256([]byte(strings.Join(parts, "\n")))
	return fmt.Sprintf("%x", sum[:])
}

func normalizePeerIds(peerIds []string) []string {
	if len(peerIds) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(peerIds))
	result := make([]string, 0, len(peerIds))
	for _, peerId := range peerIds {
		if peerId == "" {
			continue
		}
		if _, ok := seen[peerId]; ok {
			continue
		}
		seen[peerId] = struct{}{}
		result = append(result, peerId)
	}
	return result
}

// isCanonicalGroupID accepts the exact UUIDv4 representation emitted by the
// production group creator: lowercase, hyphenated, and fixed at 36 bytes.
// Relay ingress rejects every other form before durable storage or push
// construction, bounding the required group routing field by contract.
func isCanonicalGroupID(groupID string) bool {
	if len(groupID) != 36 || strings.TrimSpace(groupID) != groupID {
		return false
	}
	parsed, err := uuid.Parse(groupID)
	return err == nil && parsed != uuid.Nil &&
		parsed.Version() == uuid.Version(4) && parsed.String() == groupID
}

func mergePeerIds(existing []string, incoming []string) []string {
	merged := normalizePeerIds(existing)
	if len(incoming) == 0 {
		return merged
	}
	seen := make(map[string]struct{}, len(merged)+len(incoming))
	for _, peerId := range merged {
		seen[peerId] = struct{}{}
	}
	for _, peerId := range incoming {
		if peerId == "" {
			continue
		}
		if _, ok := seen[peerId]; ok {
			continue
		}
		seen[peerId] = struct{}{}
		merged = append(merged, peerId)
	}
	return merged
}

func stringSlicesEqual(a []string, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func groupInboxMessageAuthorizedForPeer(message groupInboxMessage, peerId string) bool {
	if peerId == "" {
		return false
	}
	return message.From == peerId || containsPeer(message.RecipientPeerIds, peerId)
}

func filterGroupInboxMessagesForPeer(messages []groupInboxMessage, peerId string) []groupInboxMessage {
	if len(messages) == 0 {
		return nil
	}
	result := make([]groupInboxMessage, 0, len(messages))
	for _, message := range messages {
		if groupInboxMessageAuthorizedForPeer(message, peerId) {
			result = append(result, message)
		}
	}
	return result
}

// Prune removes expired messages across all groups. Called periodically.
func (s *GroupInboxStore) Prune() {
	s.backend.Prune()
}

func (s *GroupInboxStore) Stats() (groups int, totalMessages int) {
	return s.backend.Stats()
}

// --- 4-byte BE framing (matches JS inbox protocol) ---

func readFrame(r io.Reader) ([]byte, error) {
	var lenBuf [4]byte
	if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
		return nil, fmt.Errorf("read length: %w", err)
	}
	length := binary.BigEndian.Uint32(lenBuf[:])
	if length > maxFrameLen {
		return nil, fmt.Errorf("frame too large: %d", length)
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(r, data); err != nil {
		return nil, fmt.Errorf("read payload: %w", err)
	}
	return data, nil
}

func writeFrame(w io.Writer, data []byte) error {
	if len(data) > maxFrameLen {
		return fmt.Errorf("frame too large: %d", len(data))
	}
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(data)))
	if _, err := w.Write(lenBuf[:]); err != nil {
		return fmt.Errorf("write length: %w", err)
	}
	if _, err := w.Write(data); err != nil {
		return fmt.Errorf("write payload: %w", err)
	}
	return nil
}

// --- Inbox stream handler ---

type wakeOutcomeRequest struct {
	action          string
	correlation     string
	wakeNotRequired bool
}

var errInvalidWakeOutcomeRequest = errors.New("invalid wake outcome request")

// decodeWakeOutcomeRequest is intentionally action-local. The inherited inbox
// decoder is permissive for compatibility, whereas this authenticated outcome
// arm has exactly three fields and rejects duplicate keys as well as unknown
// ones. Keeping the correlation out of inboxRequest also prevents it from
// becoming an accidental recipient/routing alias for any legacy action.
func decodeWakeOutcomeRequest(raw []byte) (wakeOutcomeRequest, error) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	opening, err := decoder.Token()
	if err != nil || opening != json.Delim('{') {
		return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
	}

	var request wakeOutcomeRequest
	seen := make(map[string]struct{}, 3)
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
		}
		key, ok := keyToken.(string)
		if !ok {
			return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
		}
		if _, duplicate := seen[key]; duplicate {
			return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
		}
		seen[key] = struct{}{}

		switch key {
		case "action":
			if err := decoder.Decode(&request.action); err != nil {
				return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
			}
		case "correlation":
			if err := decoder.Decode(&request.correlation); err != nil {
				return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
			}
		case "wakeNotRequired":
			if err := decoder.Decode(&request.wakeNotRequired); err != nil {
				return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
			}
		default:
			return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
		}
	}

	closing, err := decoder.Token()
	if err != nil || closing != json.Delim('}') {
		return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
	}
	if len(seen) != 3 || request.action != wakeOutcomeAction ||
		!request.wakeNotRequired || !isCanonicalWakeOutcomeCorrelation(request.correlation) {
		return wakeOutcomeRequest{}, errInvalidWakeOutcomeRequest
	}
	return request, nil
}

func isCanonicalWakeOutcomeCorrelation(value string) bool {
	if len(value) != sha256.Size*2 {
		return false
	}
	for _, candidate := range []byte(value) {
		if (candidate < '0' || candidate > '9') &&
			(candidate < 'a' || candidate > 'f') {
			return false
		}
	}
	return true
}

type inboxRequest struct {
	Action   string                 `json:"action"`
	To       string                 `json:"to,omitempty"`
	From     string                 `json:"from,omitempty"`
	Message  string                 `json:"message,omitempty"`
	Metadata map[string]interface{} `json:"metadata,omitempty"`
	Limit    int                    `json:"limit,omitempty"`
	EntryIds []string               `json:"entryIds,omitempty"`
	Token    string                 `json:"token,omitempty"`
	Platform string                 `json:"platform,omitempty"`
	// Plan 256: recipient-advertised push capabilities are stored with the
	// authenticated peer's platform token. Legacy registrations omit this field.
	Capabilities []string `json:"capabilities,omitempty"`
	// FDC-09 §12 access-token wake gate (additive). WakeToken is the opaque token a
	// SENDER presents on `store` to authorize waking the recipient; WakeTokens is
	// the SET a RECIPIENT registers via `register_wake_tokens`. omitempty keeps
	// every other action's frame byte-identical (NET-REL-07).
	WakeToken  string   `json:"wakeToken,omitempty"`
	WakeTokens []string `json:"wakeTokens,omitempty"`
	// Plan 344 additive selectors. Legacy actions ignore these fields, and old
	// decoders ignore them under the existing lenient JSON contract.
	CustodyKind     string `json:"custodyKind,omitempty"`
	CustodyContract string `json:"custodyContract,omitempty"`
	// Plan 347: present only on a strict direct-media v108 store. A pointer is
	// required so an explicitly supplied zero is rejected instead of being
	// confused with omission by Go's JSON zero value.
	CustodyExpiresAtOrBeforeMs *int64 `json:"custodyExpiresAtOrBeforeMs,omitempty"`
	// Group inbox fields.
	GroupId                string   `json:"groupId,omitempty"`
	RecipientPeerIds       []string `json:"recipientPeerIds,omitempty"`
	SinceTimestamp         int64    `json:"sinceTimestamp,omitempty"`
	Cursor                 string   `json:"cursor,omitempty"`
	GapId                  string   `json:"gapId,omitempty"`
	SourcePeerId           string   `json:"sourcePeerId,omitempty"`
	MissingAfterMessageId  string   `json:"missingAfterMessageId,omitempty"`
	MissingBeforeMessageId string   `json:"missingBeforeMessageId,omitempty"`
	ExpectedRangeHash      string   `json:"expectedRangeHash,omitempty"`
	ExpectedHeadMessageId  string   `json:"expectedHeadMessageId,omitempty"`
}

type inboxResponse struct {
	Status          string                 `json:"status"`
	Error           string                 `json:"error,omitempty"`
	ErrorCode       string                 `json:"errorCode,omitempty"`
	StoreStatus     string                 `json:"storeStatus,omitempty"`
	CustodyContract string                 `json:"custodyContract,omitempty"`
	ExpiresAtMs     int64                  `json:"expiresAtMs,omitempty"`
	Occupancy       int                    `json:"occupancy,omitempty"`
	Capacity        int                    `json:"capacity,omitempty"`
	Messages        []inboxMessage         `json:"messages,omitempty"`
	HasMore         bool                   `json:"hasMore,omitempty"`
	Acked           int                    `json:"acked,omitempty"`
	GroupMessages   []groupInboxMessage    `json:"groupMessages,omitempty"`
	NextCursor      string                 `json:"nextCursor,omitempty"`
	HistoryGaps     []groupInboxHistoryGap `json:"historyGaps,omitempty"`
	GroupId         string                 `json:"groupId,omitempty"`
	GapId           string                 `json:"gapId,omitempty"`
	SourcePeerId    string                 `json:"sourcePeerId,omitempty"`
	RangeHash       string                 `json:"rangeHash,omitempty"`
	HeadMessageId   string                 `json:"headMessageId,omitempty"`
	// FDC-08 presence_get response fields (additive — `omitempty` keeps every
	// other action's response byte-identical for NET-REL-07). Presence is
	// "online-ish", never a foreground/background claim. AgeMs is a pointer so a
	// legitimate `ageMs:0` on a presence response is still emitted, while every
	// non-presence response omits the key entirely.
	Presence string `json:"presence,omitempty"`
	AgeMs    *int64 `json:"ageMs,omitempty"`
}

func fitRetrievePendingResponse(
	messages []inboxMessage,
	hasMore bool,
) ([]inboxMessage, bool, error) {
	return fitRetrievePendingResponseForContract(messages, hasMore, "")
}

func fitRetrievePendingResponseForContract(
	messages []inboxMessage,
	hasMore bool,
	custodyContract string,
) ([]inboxMessage, bool, error) {
	if len(messages) == 0 {
		return nil, hasMore, nil
	}

	trimmed := append([]inboxMessage(nil), messages...)
	trimmedHasMore := hasMore
	for len(trimmed) > 0 {
		data, err := json.Marshal(inboxResponse{
			Status:          "OK",
			Messages:        trimmed,
			HasMore:         trimmedHasMore,
			CustodyContract: custodyContract,
		})
		if err == nil && len(data) <= maxFrameLen {
			if len(trimmed) != len(messages) {
				log.Printf("[INBOX] retrieve_pending trimmed response from %d to %d message(s) to fit %d-byte frame",
					len(messages), len(trimmed), maxFrameLen)
			}
			return trimmed, trimmedHasMore, nil
		}
		trimmed = trimmed[:len(trimmed)-1]
		trimmedHasMore = true
	}

	return nil, true, fmt.Errorf("single retrieve_pending entry exceeds %d-byte frame limit", maxFrameLen)
}

// HandleInboxStream dispatches a single inbox request over a libp2p stream. Its
// gocyclo is pre-existing (the 11-case action dispatch); FDC-08 adds one
// delegating `presence_get` arm (-> handlePresenceGet) and does not refactor the
// inherited switch (out of scope — see FDC-08 Scope Guard / named-handler rule).
//
//nolint:gocyclo,funlen // pre-existing dispatch size/complexity; FDC-08 adds one delegating case
func HandleInboxStream(s network.Stream, inbox *InboxStore, groupInbox *GroupInboxStore, h host.Host, presence *PresenceStore) {
	start := time.Now()
	activeStreams.WithLabelValues("inbox").Inc()
	streamResult := "ok"
	defer func() {
		activeStreams.WithLabelValues("inbox").Dec()
		streamDuration.WithLabelValues("inbox", streamResult).Observe(time.Since(start).Seconds())
		log.Printf("[INBOX] stream handled in %s", time.Since(start))
	}()
	defer s.Close()

	remotePeer := s.Conn().RemotePeer().String()
	log.Printf("[INBOX] Incoming stream from %s", remotePeer[:min(20, len(remotePeer))])

	requestBytes, err := readFrame(s)
	if err != nil {
		streamResult = "error"
		streamErrorsCounter.WithLabelValues("inbox", "read").Inc()
		log.Printf("[INBOX] Read error from %s: %v", remotePeer[:min(20, len(remotePeer))], err)
		return
	}

	var req inboxRequest
	if err := json.Unmarshal(requestBytes, &req); err != nil {
		streamResult = "error"
		streamErrorsCounter.WithLabelValues("inbox", "decode").Inc()
		log.Printf("[INBOX] JSON decode error: %v", err)
		writeResponse(s, inboxResponse{Status: "ERROR", Error: "invalid JSON"})
		return
	}

	var resp inboxResponse

	switch req.Action {
	case "store":
		if req.To == "" || req.Message == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required fields: to, message"}
		} else {
			entry := inboxMessage{
				// Direct inbox attribution is always the authenticated libp2p peer.
				// A caller-supplied `from` is legacy input only and cannot forge push
				// routing or durable sender custody.
				From:      remotePeer,
				Message:   req.Message,
				Timestamp: time.Now().UnixMilli(),
				Metadata:  req.Metadata,
				WakeToken: req.WakeToken, // FDC-09 §12: presented opaque wake-token (transient)
			}
			result, err := inbox.Store(req.To, entry)
			if err != nil {
				resp = inboxResponse{Status: "ERROR", Error: fmt.Sprintf("store failed: %v", err)}
			} else if result == InboxStoreResultRejectedFull {
				resp = inboxResponse{
					Status:      "ERROR",
					Error:       "INBOX_FULL",
					StoreStatus: string(result),
					Occupancy:   inbox.Count(req.To),
					Capacity:    inbox.Capacity(),
				}
			} else {
				resp = inboxResponse{
					Status:      "OK",
					StoreStatus: string(result),
					Occupancy:   inbox.Count(req.To),
					Capacity:    inbox.Capacity(),
				}
				if result == InboxStoreResultStored {
					resp.ExpiresAtMs = entry.Timestamp + maxMessageAge.Milliseconds()
				}
			}
			// Push notification is now fired inside InboxStore.Store
			// (only for genuinely new messages, skipped for duplicates).
		}

	case ackCustodyStoreAction:
		storeNow := inbox.ackCustodyNow()
		if req.To == "" || req.Message == "" || req.CustodyKind == "" ||
			req.CustodyContract != ackCustodyContract ||
			!validAckCustodyExpiryCeiling(
				req.CustodyKind,
				req.CustodyExpiresAtOrBeforeMs,
				storeNow,
				req.Message,
				remotePeer,
				req.To,
			) {
			recordAckCustodyStoreResult(ackCustodyStoreMetricIneligible)
			resp = inboxResponse{
				Status:    "ERROR",
				Error:     ackCustodyErrorIneligible,
				ErrorCode: ackCustodyErrorIneligible,
			}
		} else {
			entry := inboxMessage{
				From:      remotePeer,
				Message:   req.Message,
				Timestamp: storeNow.UnixMilli(),
				Metadata:  req.Metadata,
				WakeToken: req.WakeToken,
			}
			if req.CustodyExpiresAtOrBeforeMs != nil {
				entry.ExpiresAtMs = *req.CustodyExpiresAtOrBeforeMs
			}
			result, storedEntry, err := inbox.StoreAckCustody(req.To, entry, req.CustodyKind)
			if err != nil {
				switch {
				case errors.Is(err, errAckCustodyAdmissionDisabled):
					resp = inboxResponse{
						Status:    "ERROR",
						Error:     ackCustodyErrorAdmissionDisabled,
						ErrorCode: ackCustodyErrorAdmissionDisabled,
					}
				case errors.Is(err, errAckCustodyIdentityConflict):
					resp = inboxResponse{
						Status:    "ERROR",
						Error:     ackCustodyErrorIdentityConflict,
						ErrorCode: ackCustodyErrorIdentityConflict,
					}
				case errors.Is(err, errAckCustodyIneligible):
					resp = inboxResponse{
						Status:    "ERROR",
						Error:     ackCustodyErrorIneligible,
						ErrorCode: ackCustodyErrorIneligible,
					}
				case errors.Is(err, errAckCustodyBackendUnavailable):
					resp = inboxResponse{
						Status:    "ERROR",
						Error:     ackCustodyErrorBackendUnavailable,
						ErrorCode: ackCustodyErrorBackendUnavailable,
					}
				default:
					resp = inboxResponse{Status: "ERROR", Error: fmt.Sprintf("store custody failed: %v", err)}
				}
			} else if result == InboxStoreResultRejectedFull {
				resp = inboxResponse{
					Status:      "ERROR",
					Error:       ackCustodyErrorInboxFull,
					ErrorCode:   ackCustodyErrorInboxFull,
					StoreStatus: string(result),
					Occupancy:   inbox.CountAckCustody(req.To),
					Capacity:    inbox.Capacity(),
				}
			} else {
				resp = inboxResponse{
					Status:          "OK",
					StoreStatus:     string(result),
					CustodyContract: ackCustodyContract,
					ExpiresAtMs:     ackCustodyEntryExpiresAtMs(storedEntry),
					Occupancy:       inbox.CountAckCustody(req.To),
					Capacity:        inbox.Capacity(),
				}
			}
		}

	case "retrieve":
		limit := req.Limit
		if limit <= 0 {
			limit = 50
		}
		messages, hasMore := inbox.RetrieveWithMeta(remotePeer, limit)
		if len(messages) > 0 {
			resp = inboxResponse{Status: "OK", Messages: messages, HasMore: hasMore}
		} else {
			resp = inboxResponse{Status: "NO_MESSAGES"}
		}

	case "retrieve_pending":
		limit := req.Limit
		if limit <= 0 {
			limit = 50
		}
		messages, hasMore := inbox.RetrievePendingWithMeta(remotePeer, limit)
		if len(messages) > 0 {
			fittedMessages, fittedHasMore, err := fitRetrievePendingResponse(messages, hasMore)
			if err != nil {
				resp = inboxResponse{Status: "ERROR", Error: err.Error()}
			} else {
				resp = inboxResponse{
					Status:   "OK",
					Messages: fittedMessages,
					HasMore:  fittedHasMore,
				}
			}
		} else {
			resp = inboxResponse{Status: "NO_MESSAGES"}
		}

	case ackCustodyRetrievePendingAction:
		if req.CustodyContract != ackCustodyContract {
			resp = inboxResponse{
				Status:    "ERROR",
				Error:     ackCustodyErrorIneligible,
				ErrorCode: ackCustodyErrorIneligible,
			}
		} else {
			limit := req.Limit
			if limit <= 0 {
				limit = 50
			}
			messages, hasMore, err := inbox.RetrieveAckCustodyPending(remotePeer, limit)
			if err != nil {
				resp = inboxResponse{Status: "ERROR", Error: err.Error()}
			} else if len(messages) == 0 {
				resp = inboxResponse{Status: "NO_MESSAGES", CustodyContract: ackCustodyContract}
			} else {
				fittedMessages, fittedHasMore, err := fitRetrievePendingResponseForContract(
					messages,
					hasMore,
					ackCustodyContract,
				)
				if err != nil {
					resp = inboxResponse{Status: "ERROR", Error: err.Error()}
				} else {
					resp = inboxResponse{
						Status:          "OK",
						Messages:        fittedMessages,
						HasMore:         fittedHasMore,
						CustodyContract: ackCustodyContract,
					}
				}
			}
		}

	case "ack":
		if len(req.EntryIds) == 0 {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: entryIds"}
		} else {
			acked, err := inbox.Ack(remotePeer, req.EntryIds)
			if err != nil {
				resp = inboxResponse{Status: "ERROR", Error: err.Error()}
			} else {
				resp = inboxResponse{Status: "OK", Acked: acked}
			}
		}

	case ackCustodyAckAction:
		if req.CustodyContract != ackCustodyContract {
			resp = inboxResponse{
				Status:    "ERROR",
				Error:     ackCustodyErrorIneligible,
				ErrorCode: ackCustodyErrorIneligible,
			}
		} else if len(req.EntryIds) == 0 {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: entryIds"}
		} else {
			acked, err := inbox.AckAckCustody(remotePeer, req.EntryIds)
			if err != nil {
				resp = inboxResponse{Status: "ERROR", Error: err.Error()}
			} else {
				resp = inboxResponse{
					Status:          "OK",
					Acked:           acked,
					CustodyContract: ackCustodyContract,
				}
			}
		}

	case "register_token":
		if req.Token == "" || req.Platform == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required fields: token, platform"}
		} else {
			err := inbox.push.RegisterToken(
				remotePeer,
				req.Token,
				req.Platform,
				req.Capabilities...,
			)
			if err != nil {
				log.Printf("[PUSH] outcome=registration_failed")
				resp = inboxResponse{Status: "ERROR", Error: "Push token persistence failed"}
			} else {
				resp = inboxResponse{Status: "OK"}
			}
		}

	case "unregister_token":
		if err := inbox.push.UnregisterToken(remotePeer); err != nil {
			log.Printf("[PUSH] outcome=unregistration_failed")
			resp = inboxResponse{Status: "ERROR", Error: "Push token deletion failed"}
		} else {
			inbox.ClearWakeTokens(remotePeer) // FDC-09 §12: no orphaned wake authorization
			resp = inboxResponse{Status: "OK"}
		}

	case "register_wake_tokens":
		// FDC-09 §12: the recipient registers the opaque wake-token SET it minted
		// for its contacts (anti-spam — only a contact presenting a member token can
		// wake it). Subject = the AUTHENTICATED stream peer (remotePeer), never a
		// request field. An empty set clears the gate (back to fail-open).
		inbox.RegisterWakeTokens(remotePeer, req.WakeTokens)
		resp = inboxResponse{Status: "OK"}

	case wakeOutcomeAction:
		outcome, err := decodeWakeOutcomeRequest(requestBytes)
		if err != nil {
			resp = inboxResponse{Status: "ERROR", Error: "invalid wake outcome request"}
		} else if inbox == nil {
			resp = inboxResponse{Status: "ERROR", Error: "wake outcome retryable"}
		} else if _, err := inbox.CompleteWakeOutcome(remotePeer, outcome.correlation); err != nil {
			// Capacity, backend availability, and transient storage failures are all
			// intentionally one finite retryable wire result. Never echo backend or
			// correlation material into the response/log surface.
			resp = inboxResponse{Status: "ERROR", Error: "wake outcome retryable"}
		} else {
			resp = inboxResponse{Status: "OK"}
		}

	case "group_store":
		if req.GroupId == "" || req.Message == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required fields: groupId, message"}
		} else if !isCanonicalGroupID(req.GroupId) {
			resp = inboxResponse{Status: "ERROR", Error: "invalid groupId"}
		} else if len(normalizePeerIds(req.RecipientPeerIds)) == 0 {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: recipientPeerIds"}
		} else {
			from := req.From
			if from == "" {
				from = remotePeer
			}
			if from != remotePeer {
				resp = inboxResponse{Status: "ERROR", Error: "not authorized"}
			} else if err := groupInbox.StoreWithPushRecipients(
				req.GroupId,
				remotePeer,
				req.Message,
				normalizePeerIds(req.RecipientPeerIds),
			); err != nil {
				resp = inboxResponse{Status: "ERROR", Error: err.Error()}
			} else {
				resp = inboxResponse{Status: "OK"}
			}
		}

	case "group_retrieve":
		if req.GroupId == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: groupId"}
		} else {
			messages := groupInbox.RetrieveAuthorized(req.GroupId, req.SinceTimestamp, remotePeer)
			if len(messages) > 0 {
				resp = inboxResponse{Status: "OK", GroupMessages: messages}
			} else {
				resp = inboxResponse{Status: "NO_MESSAGES"}
			}
		}

	case "group_retrieve_cursor":
		if req.GroupId == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required field: groupId"}
		} else {
			limit := req.Limit
			if limit <= 0 {
				limit = 50
			}
			messages, nextCursor, historyGaps := groupInbox.RetrieveWithCursorAuthorized(req.GroupId, req.Cursor, limit, remotePeer)
			if len(messages) > 0 {
				resp = inboxResponse{Status: "OK", GroupMessages: messages, NextCursor: nextCursor, HistoryGaps: historyGaps}
			} else {
				resp = inboxResponse{Status: "NO_MESSAGES"}
			}
		}

	case "group_history_repair_range":
		if req.GroupId == "" || req.GapId == "" || req.SourcePeerId == "" ||
			req.MissingAfterMessageId == "" || req.MissingBeforeMessageId == "" ||
			req.ExpectedRangeHash == "" || req.ExpectedHeadMessageId == "" {
			resp = inboxResponse{Status: "ERROR", Error: "Missing required history repair fields"}
		} else {
			limit := req.Limit
			if limit <= 0 {
				limit = 50
			}
			messages, rangeHash, headMessageId := groupInbox.RetrieveHistoryRepairRangeAuthorized(
				req.GroupId,
				req.MissingAfterMessageId,
				req.MissingBeforeMessageId,
				limit,
				remotePeer,
			)
			if len(messages) > 0 {
				resp = inboxResponse{
					Status:        "OK",
					GroupMessages: messages,
					GroupId:       req.GroupId,
					GapId:         req.GapId,
					SourcePeerId:  req.SourcePeerId,
					RangeHash:     rangeHash,
					HeadMessageId: headMessageId,
				}
			} else {
				resp = inboxResponse{Status: "NO_MESSAGES"}
			}
		}

	case "presence_get":
		resp = handlePresenceGet(req, h, presence)

	case "presence_set":
		resp = handlePresenceSet(s.Conn().RemotePeer(), req, presence)

	default:
		resp = inboxResponse{Status: "ERROR", Error: fmt.Sprintf("Unknown action: %s", req.Action)}
	}

	writeResponse(s, resp)
	log.Printf("[INBOX] Stream closed for %s", remotePeer[:min(20, len(remotePeer))])
}

// handlePresenceGet answers the additive `presence_get` inbox action: a cheap,
// read-only "is this peer online-ish?" lookup that replaces the blind ≤5 s
// circuit dial on the send-decision path (FDC-08). It NEVER dials a circuit and
// NEVER mutates inbox state (PRESENCE_LOOKUP_IS_READ_ONLY) — it reads the
// peer's live socket connectedness plus the shared presence store's last-seen /
// self-published state. The answer is coarse "online-ish, TTL-lagged" and
// carries no foreground/background field (PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND).
// A stale last-seen resolves to `unknown`, never silently `unreachable`.
func handlePresenceGet(req inboxRequest, h host.Host, presence *PresenceStore) inboxResponse {
	if req.To == "" {
		return inboxResponse{Status: "ERROR", Error: "Missing required field: to"}
	}
	pid, err := peer.Decode(req.To)
	if err != nil {
		return inboxResponse{Status: "ERROR", Error: fmt.Sprintf("invalid peer ID: %v", err)}
	}

	connected := h.Network().Connectedness(pid) == network.Connected
	res := presence.Lookup(pid, connected)

	ageMs := res.ageMs
	return inboxResponse{Status: "OK", Presence: res.presence, AgeMs: &ageMs}
}

// maxPresenceSelfTTL bounds a self-published presence TTL so a misbehaving peer
// cannot claim "reachable forever". The locked default is relayPresenceTTL
// (≈180 s); this is the generous upper clamp (FDC-S3 device-tunable window).
const maxPresenceSelfTTL = 10 * time.Minute

// handlePresenceSet answers the additive `presence_set` inbox action (FDC-09):
// a peer SELF-PUBLISHES its coarse foreground/background state to the shared
// presence store. The subject is the AUTHENTICATED stream peer (`self`), NEVER a
// request field — a peer can publish only ITS OWN presence (anti-spoof). The
// write records BOTH the self-published state (with its TTL, preferred by the
// resolver) AND seeds the connectedness last-seen, so a STALE self-state
// degrades to `unknown` via the same R5 freshness rule the last-seen uses
// (FDC-S3: never silently `unreachable`).
//
// Presence is a HINT, never load-bearing: this WRITE feeds the read-side
// emphasis hint only — the store→push delivery seam never consults it
// (PRESENCE_NEVER_LOAD_BEARING). Old relays answer "Unknown action: presence_set"
// (the stable `default` arm), which new clients map to "unsupported -> skip"
// (NET-REL-07).
func handlePresenceSet(self peer.ID, req inboxRequest, presence *PresenceStore) inboxResponse {
	if presence == nil {
		return inboxResponse{Status: "ERROR", Error: "presence store unavailable"}
	}

	state := trimmedString(req.Metadata["state"])
	switch state {
	case "foreground", "background":
		// accepted coarse self-published states
	default:
		return inboxResponse{Status: "ERROR", Error: fmt.Sprintf("invalid presence state: %q", state)}
	}

	ttl := relayPresenceTTL
	if ms := presenceMetadataTTLMs(req.Metadata); ms > 0 {
		ttl = time.Duration(ms) * time.Millisecond
		if ttl > maxPresenceSelfTTL {
			ttl = maxPresenceSelfTTL
		}
	}

	presence.SetSelfPublished(self, state, ttl)
	presence.RecordSeen(self) // seed last-seen so a stale self-state degrades to `unknown`, not `unreachable`
	return inboxResponse{Status: "OK"}
}

// presenceMetadataTTLMs extracts the optional `ttlMs` from a `presence_set`
// request's Metadata map. JSON numbers decode to float64 through the
// map[string]interface{} field; the other arms tolerate a node-side int64 /
// json.Number for robustness. A missing/zero value falls back to the default.
func presenceMetadataTTLMs(meta map[string]interface{}) int64 {
	if meta == nil {
		return 0
	}
	switch v := meta["ttlMs"].(type) {
	case float64:
		return int64(v)
	case int64:
		return v
	case int:
		return int64(v)
	case json.Number:
		n, _ := v.Int64()
		return n
	}
	return 0
}

func writeResponse(s network.Stream, resp inboxResponse) {
	data, err := json.Marshal(resp)
	if err != nil {
		streamErrorsCounter.WithLabelValues("inbox", "write").Inc()
		log.Printf("[INBOX] JSON encode error: %v", err)
		return
	}
	if err := writeFrame(s, data); err != nil {
		streamErrorsCounter.WithLabelValues("inbox", "write").Inc()
		log.Printf("[INBOX] Write error: %v", err)
	}
}
