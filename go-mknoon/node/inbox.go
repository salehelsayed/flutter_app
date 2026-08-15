package node

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"sort"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// Push capabilities are additive. Old relays ignore the capabilities field and
// old clients omit values they cannot honor.
const (
	DirectReactionPushCapability = "direct_reaction_v1"
	OpaqueWakePushCapability     = "opaque_wake_v1"
	WakeOutcomePushCapability    = "wake_outcome_v1"
)

const (
	// AckOrExpiryCustodyContract is the exact proof returned only by the
	// non-destructive direct-inbox lane. A generic OK or legacy store result is
	// deliberately not equivalent to this receipt.
	AckOrExpiryCustodyContract = "ack_or_expiry_v1"

	CustodyKindDirectTextV108     = "direct_text_v108"
	CustodyKindDirectReactionV109 = "direct_reaction_v109"
	CustodyKindDirectMutationV109 = "direct_mutation_v109"
	CustodyKindGroupBootstrapV1   = "group_bootstrap_v1"
	CustodyKindGroupAuthorityV1   = "group_authority_v1"
	CustodyKindGroupContentV1     = "group_content_v1"

	inboxStoreAckCustodyAction    = "store_custody_v1"
	inboxRetrieveAckCustodyAction = "retrieve_custody_pending_v1"
	inboxAckCustodyAction         = "ack_custody_v1"
	inboxAckCustodyFanoutLimit    = 3
	inboxWakeOutcomeAction        = "wake_outcome_v1"
)

// InboxMessage represents a message stored in the offline inbox.
type InboxMessage struct {
	ID        string `json:"id,omitempty"`
	From      string `json:"from"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

type inboxRequest struct {
	Action          string   `json:"action"`
	Correlation     string   `json:"correlation,omitempty"`
	WakeNotRequired bool     `json:"wakeNotRequired,omitempty"`
	To              string   `json:"to,omitempty"`
	From            string   `json:"from,omitempty"`
	Message         string   `json:"message,omitempty"`
	Limit           int      `json:"limit,omitempty"`
	EntryIds        []string `json:"entryIds,omitempty"`
	Token           string   `json:"token,omitempty"`
	Platform        string   `json:"platform,omitempty"`
	// Plan 256: additive push-token capabilities. Omitted for legacy clients so
	// their register_token frame remains byte-compatible with old relays.
	Capabilities []string `json:"capabilities,omitempty"`
	// FDC-09 presence_set write field (additive): carries {state, ttlMs} for the
	// self-publish action. omitempty keeps every other action's frame unchanged.
	Metadata map[string]interface{} `json:"metadata,omitempty"`
	// FDC-09 §12: the opaque wake-token SET registered via register_wake_tokens.
	WakeTokens []string `json:"wakeTokens,omitempty"`
	// FDC-09 §12 (CV-14): the SINGLE opaque wake-token a SENDER presents on a
	// `store` request — the token the RECIPIENT issued to this sender — so the
	// relay's access-token wake gate authorizes waking the recipient ("only
	// contacts can wake you"). omitempty keeps every non-attaching frame
	// byte-identical to the pre-FDC-09 store frame (NET-REL-07).
	WakeToken string `json:"wakeToken,omitempty"`
	// Plan 344: present only on the additive protected store action. The action
	// itself selects the contract; this discriminator constrains the two local
	// custody owners permitted to use it.
	CustodyKind     string `json:"custodyKind,omitempty"`
	CustodyContract string `json:"custodyContract,omitempty"`
	// Plan 347: optional relay-authoritative ceiling for strict direct-media
	// v108 envelope custody. Omission preserves the Plan 344 wire frame.
	CustodyExpiresAtOrBeforeMs int64 `json:"custodyExpiresAtOrBeforeMs,omitempty"`
}

type inboxResponse struct {
	Status      string         `json:"status"`
	Error       string         `json:"error,omitempty"`
	ErrorCode   string         `json:"errorCode,omitempty"`
	StoreStatus string         `json:"storeStatus,omitempty"`
	ExpiresAtMs int64          `json:"expiresAtMs,omitempty"`
	Occupancy   int            `json:"occupancy,omitempty"`
	Capacity    int            `json:"capacity,omitempty"`
	Messages    []InboxMessage `json:"messages,omitempty"`
	HasMore     bool           `json:"hasMore,omitempty"`
	Acked       int            `json:"acked,omitempty"`
	// Plan 344: exact proof carried by each valid protected store/retrieve/ACK
	// response. Legacy actions omit it.
	CustodyContract string `json:"custodyContract,omitempty"`
	// FDC-08 presence_get response fields (additive). Presence is "online-ish",
	// never a foreground/background claim. AgeMs is the age of the relay's
	// freshest record for the peer in ms (-1 when nothing is known).
	Presence string `json:"presence,omitempty"`
	AgeMs    int64  `json:"ageMs,omitempty"`
}

var (
	ErrInboxFull                     = errors.New("inbox full")
	ErrInboxCustodyIdentityConflict  = errors.New("inbox custody identity conflict")
	ErrInboxCustodyIneligible        = errors.New("inbox custody message ineligible")
	ErrInboxCustodyAdmissionDisabled = errors.New("inbox custody admission disabled")
	ErrInboxCustodyInvalidReceipt    = errors.New("invalid inbox custody receipt")
	ErrInboxCustodyPartial           = errors.New("partial inbox custody operation")
	ErrInboxWakeOutcomeRetryable     = errors.New("retryable inbox wake outcome")
)

// InboxWakeOutcomeRelayDisposition is the terminal/retryable result for one
// distinct configured relay peer. Multiple transport addresses for one peer do
// not create additional participants.
type InboxWakeOutcomeRelayDisposition string

const (
	InboxWakeOutcomeAccepted    InboxWakeOutcomeRelayDisposition = "accepted"
	InboxWakeOutcomeUnsupported InboxWakeOutcomeRelayDisposition = "unsupported"
	InboxWakeOutcomeRetryable   InboxWakeOutcomeRelayDisposition = "retryable"
)

type InboxWakeOutcomeRelayResult struct {
	RelayID     string
	Disposition InboxWakeOutcomeRelayDisposition
	Error       string
}

// InboxWakeOutcomeResult retains the outcome for every distinct configured
// relay. AllParticipantsTerminal is true only when every participant returned
// OK/idempotent or the exact old-relay unsupported response.
type InboxWakeOutcomeResult struct {
	Relays                  []InboxWakeOutcomeRelayResult
	ParticipantCount        int
	AcceptedCount           int
	UnsupportedCount        int
	RetryableCount          int
	AllParticipantsTerminal bool
}

type InboxStoreOutcome struct {
	StoreStatus     string
	ErrorCode       string
	ErrorMessage    string
	CustodyContract string
	ExpiresAtMs     int64
	Occupancy       int
	Capacity        int
}

func parseInboxStoreResponse(respBytes []byte) (InboxStoreOutcome, error) {
	var resp inboxResponse
	if err := json.Unmarshal(respBytes, &resp); err != nil {
		return InboxStoreOutcome{}, fmt.Errorf("unmarshal response: %w", err)
	}

	outcome := InboxStoreOutcome{
		StoreStatus:  resp.StoreStatus,
		ErrorCode:    resp.ErrorCode,
		ErrorMessage: resp.Error,
		ExpiresAtMs:  resp.ExpiresAtMs,
		Occupancy:    resp.Occupancy,
		Capacity:     resp.Capacity,
	}

	if resp.Status == "OK" {
		if outcome.StoreStatus == "" {
			outcome.StoreStatus = "stored"
		}
		return outcome, nil
	}

	errorCode := resp.ErrorCode
	if errorCode == "" && resp.Error == "INBOX_FULL" {
		errorCode = "INBOX_FULL"
	}
	if errorCode == "INBOX_FULL" || resp.StoreStatus == "rejected_full" {
		outcome.ErrorCode = "INBOX_FULL"
		if outcome.StoreStatus == "" {
			outcome.StoreStatus = "rejected_full"
		}
		return outcome, fmt.Errorf("%w: %s", ErrInboxFull, resp.Error)
	}

	if outcome.ErrorCode == "" {
		outcome.ErrorCode = "INBOX_ERROR"
	}
	return outcome, fmt.Errorf("inbox store failed: %s", resp.Error)
}

// parseInboxAckCustodyStoreResponse owns the strict Plan 344 receipt table.
// Only stored/duplicate plus the exact proof is accepting. All other replies
// remain retryable except identity conflict and structural ineligibility,
// which callers must stop on rather than route around.
func parseInboxAckCustodyStoreResponse(respBytes []byte) (InboxStoreOutcome, error) {
	var resp inboxResponse
	if err := json.Unmarshal(respBytes, &resp); err != nil {
		return InboxStoreOutcome{}, fmt.Errorf("%w: unmarshal response: %v", ErrInboxCustodyInvalidReceipt, err)
	}

	outcome := InboxStoreOutcome{
		StoreStatus:     resp.StoreStatus,
		ErrorCode:       resp.ErrorCode,
		ErrorMessage:    resp.Error,
		CustodyContract: resp.CustodyContract,
		ExpiresAtMs:     resp.ExpiresAtMs,
		Occupancy:       resp.Occupancy,
		Capacity:        resp.Capacity,
	}

	if resp.Status == "OK" {
		if resp.CustodyContract != AckOrExpiryCustodyContract {
			return outcome, fmt.Errorf("%w: missing or unknown custody contract", ErrInboxCustodyInvalidReceipt)
		}
		if resp.StoreStatus != "stored" && resp.StoreStatus != "duplicate" {
			return outcome, fmt.Errorf("%w: unsupported store status %q", ErrInboxCustodyInvalidReceipt, resp.StoreStatus)
		}
		return outcome, nil
	}

	if resp.Status != "ERROR" {
		return outcome, fmt.Errorf("%w: unsupported response status %q", ErrInboxCustodyInvalidReceipt, resp.Status)
	}

	code := resp.ErrorCode
	outcome.ErrorCode = code
	if code == "INBOX_FULL" || resp.StoreStatus == "rejected_full" {
		if code != "INBOX_FULL" || resp.StoreStatus != "rejected_full" {
			return outcome, fmt.Errorf("%w: incomplete protected full response", ErrInboxCustodyInvalidReceipt)
		}
		outcome.ErrorCode = "INBOX_FULL"
		return outcome, fmt.Errorf("%w: %s", ErrInboxFull, responseErrorText(resp))
	}
	switch code {
	case "CUSTODY_IDENTITY_CONFLICT":
		return outcome, fmt.Errorf("%w: %s", ErrInboxCustodyIdentityConflict, responseErrorText(resp))
	case "CUSTODY_INELIGIBLE":
		return outcome, fmt.Errorf("%w: %s", ErrInboxCustodyIneligible, responseErrorText(resp))
	case "CUSTODY_ADMISSION_DISABLED":
		return outcome, fmt.Errorf("%w: %s", ErrInboxCustodyAdmissionDisabled, responseErrorText(resp))
	default:
		return outcome, fmt.Errorf("inbox custody store failed: %s", responseErrorText(resp))
	}
}

func responseErrorText(resp inboxResponse) string {
	if resp.Error != "" {
		return resp.Error
	}
	if resp.ErrorCode != "" {
		return resp.ErrorCode
	}
	return resp.Status
}

// InboxStore stores a message in the offline inbox for a peer.
// Tries each configured relay in order until one succeeds.
func (n *Node) InboxStore(toPeerId string, message string, timeoutMs int) error {
	_, err := n.InboxStoreDetailed(toPeerId, message, timeoutMs)
	return err
}

// InboxStoreDetailed stores a message and returns relay custody metadata when
// the relay supports the enriched store response. It presents no wake-token —
// equivalent to InboxStoreDetailedWithWakeToken with an empty token, so the
// store frame is byte-identical to the pre-FDC-09 frame (NET-REL-07).
func (n *Node) InboxStoreDetailed(
	toPeerId string,
	message string,
	timeoutMs int,
) (InboxStoreOutcome, error) {
	return n.InboxStoreDetailedWithWakeToken(toPeerId, message, timeoutMs, "")
}

// InboxStoreDetailedWithWakeToken is InboxStoreDetailed plus the FDC-09 §12
// (CV-14) send-side wake-token attach: it presents on the `store` request the
// opaque wake-token the RECIPIENT issued to this sender, so the relay's §12
// access-token gate authorizes waking the recipient. An empty wakeToken keeps
// the store frame byte-identical to the pre-FDC-09 frame (omitempty), so
// absent-token recipients and old relays are unaffected (NET-REL-07). The
// production source of the token (the recipient's issued token, distributed out
// of band) is wired separately; this method owns only the transport attach.
//
// SHIP-ORDER (FDC-09 H1 / INV-2): this attach must land + saturate the sender
// fleet BEFORE the relay flips wakeTokenGateEnforced ON (CV-19), or enforcing the
// gate the instant a recipient registers a set would hard-silence every empty-token
// sender's 1:1 pushes.
//
//nolint:funlen // inherited length of the per-relay store retry loop (the former InboxStoreDetailed body verbatim); CV-14's wake-token attach is a 1-line additive change, matching the HandleInboxStream precedent.
func (n *Node) InboxStoreDetailedWithWakeToken(
	toPeerId string,
	message string,
	timeoutMs int,
	wakeToken string,
) (InboxStoreOutcome, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return InboxStoreOutcome{}, fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	totalStart := time.Now()
	var lastOutcome InboxStoreOutcome
	err := rs.ForEach(func(relay RelayInfo) error {
		timeout := InboxTimeout
		if timeoutMs > 0 {
			timeout = time.Duration(timeoutMs) * time.Millisecond
		}
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		// Ensure connected to relay
		connectStart := time.Now()
		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			n.emitEvent("inbox:store_timing", map[string]interface{}{
				"connectMs": time.Since(connectStart).Milliseconds(),
				"totalMs":   time.Since(totalStart).Milliseconds(),
				"outcome":   "connect_failed",
			})
			return fmt.Errorf("connect to relay: %w", err)
		}
		connectMs := time.Since(connectStart).Milliseconds()

		streamStart := time.Now()
		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		streamOpenMs := time.Since(streamStart).Milliseconds()
		if err != nil {
			n.emitEvent("inbox:store_timing", map[string]interface{}{
				"connectMs":    connectMs,
				"streamOpenMs": streamOpenMs,
				"totalMs":      time.Since(totalStart).Milliseconds(),
				"outcome":      "stream_failed",
			})
			return fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		req := inboxRequest{
			Action:    "store",
			To:        toPeerId,
			From:      n.peerId,
			Message:   message,
			WakeToken: wakeToken, // FDC-09 §12 (CV-14): present recipient-issued token; empty => omitted (NET-REL-07)
		}

		reqBytes, err := json.Marshal(req)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}

		writeStart := time.Now()
		if err := writeFrame(s, reqBytes); err != nil {
			return fmt.Errorf("write request: %w", err)
		}
		writeMs := time.Since(writeStart).Milliseconds()

		readStart := time.Now()
		respBytes, err := readFrame(s)
		readMs := time.Since(readStart).Milliseconds()
		if err != nil {
			return fmt.Errorf("read response: %w", err)
		}

		outcome, err := parseInboxStoreResponse(respBytes)
		lastOutcome = outcome
		if err != nil {
			n.emitEvent("inbox:store_timing", map[string]interface{}{
				"connectMs":    connectMs,
				"streamOpenMs": streamOpenMs,
				"writeMs":      writeMs,
				"readMs":       readMs,
				"totalMs":      time.Since(totalStart).Milliseconds(),
				"outcome":      "store_failed",
				"storeStatus":  outcome.StoreStatus,
				"errorCode":    outcome.ErrorCode,
			})
			return err
		}

		n.emitEvent("inbox:store_timing", map[string]interface{}{
			"connectMs":    connectMs,
			"streamOpenMs": streamOpenMs,
			"writeMs":      writeMs,
			"readMs":       readMs,
			"totalMs":      time.Since(totalStart).Milliseconds(),
			"outcome":      "success",
			"storeStatus":  outcome.StoreStatus,
			"occupancy":    outcome.Occupancy,
			"capacity":     outcome.Capacity,
		})
		log.Printf("[INBOX] Stored message for %s", toPeerId[:min(20, len(toPeerId))])
		streamOK = true
		return nil
	})
	return lastOutcome, err
}

// InboxStoreAckCustodyDetailedWithWakeToken stores only through the additive
// ACK-or-expiry action. It never falls back to legacy store: a sender may hand
// off local custody only after this method receives the exact protected proof.
// Retryable failures continue across relay peers; identity conflict and
// ineligibility are terminal because routing around either would split the
// logical identity contract.
func (n *Node) InboxStoreAckCustodyDetailedWithWakeToken(
	toPeerID string,
	message string,
	timeoutMs int,
	wakeToken string,
	custodyKind string,
) (InboxStoreOutcome, error) {
	return n.inboxStoreAckCustodyDetailedWithWakeToken(
		toPeerID,
		message,
		timeoutMs,
		wakeToken,
		custodyKind,
		0,
	)
}

// InboxStoreAckCustodyDetailedWithWakeTokenAndExpiryCeiling is the media-bound
// sibling of InboxStoreAckCustodyDetailedWithWakeToken. The positive ceiling
// is sent on the existing protected action and the returned relay proof must
// carry that exact persisted expiry.
func (n *Node) InboxStoreAckCustodyDetailedWithWakeTokenAndExpiryCeiling(
	toPeerID string,
	message string,
	timeoutMs int,
	wakeToken string,
	custodyKind string,
	custodyExpiresAtOrBeforeMs int64,
) (InboxStoreOutcome, error) {
	if (custodyKind != CustodyKindDirectTextV108 && custodyKind != CustodyKindGroupContentV1) ||
		custodyExpiresAtOrBeforeMs <= 0 {
		return InboxStoreOutcome{ErrorCode: "CUSTODY_INELIGIBLE"}, fmt.Errorf(
			"%w: media expiry ceiling requires direct_text_v108 or group_content_v1 and a positive ceiling",
			ErrInboxCustodyIneligible,
		)
	}
	return n.inboxStoreAckCustodyDetailedWithWakeToken(
		toPeerID,
		message,
		timeoutMs,
		wakeToken,
		custodyKind,
		custodyExpiresAtOrBeforeMs,
	)
}

func (n *Node) inboxStoreAckCustodyDetailedWithWakeToken(
	toPeerID string,
	message string,
	timeoutMs int,
	wakeToken string,
	custodyKind string,
	custodyExpiresAtOrBeforeMs int64,
) (InboxStoreOutcome, error) {
	if !isSupportedInboxCustodyKind(custodyKind) {
		return InboxStoreOutcome{ErrorCode: "CUSTODY_INELIGIBLE"},
			fmt.Errorf("%w: unsupported custody kind %q", ErrInboxCustodyIneligible, custodyKind)
	}

	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()
	if h == nil {
		return InboxStoreOutcome{}, fmt.Errorf("node not started")
	}

	timeout := InboxTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}
	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return InboxStoreOutcome{}, fmt.Errorf("no relays configured")
	}

	req := inboxRequest{
		Action:                     inboxStoreAckCustodyAction,
		To:                         toPeerID,
		From:                       n.peerId,
		Message:                    message,
		WakeToken:                  wakeToken,
		CustodyKind:                custodyKind,
		CustodyContract:            AckOrExpiryCustodyContract,
		CustodyExpiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
	}
	start := time.Now()
	var lastErr error
	var lastOutcome InboxStoreOutcome
	var fullOutcome *InboxStoreOutcome

	for _, relay := range relays {
		var peerResponded bool
		for _, candidate := range relayInfoAttemptCandidates(relay) {
			respBytes, err := n.exchangeInboxRequest(h, candidate, req, timeout)
			if err != nil {
				lastErr = err
				continue
			}
			peerResponded = true
			outcome, parseErr := parseInboxAckCustodyStoreResponse(respBytes)
			if parseErr == nil && custodyExpiresAtOrBeforeMs > 0 &&
				outcome.ExpiresAtMs != custodyExpiresAtOrBeforeMs {
				parseErr = fmt.Errorf(
					"%w: media expiry proof=%d want=%d",
					ErrInboxCustodyInvalidReceipt,
					outcome.ExpiresAtMs,
					custodyExpiresAtOrBeforeMs,
				)
			}
			lastOutcome = outcome
			if parseErr == nil {
				n.emitEvent("inbox:store_timing", map[string]interface{}{
					"totalMs":         time.Since(start).Milliseconds(),
					"outcome":         "success",
					"storeStatus":     outcome.StoreStatus,
					"custodyContract": outcome.CustodyContract,
					"occupancy":       outcome.Occupancy,
					"capacity":        outcome.Capacity,
				})
				log.Printf("[INBOX] Stored protected message for %s", toPeerID[:min(20, len(toPeerID))])
				return outcome, nil
			}
			lastErr = parseErr
			if errors.Is(parseErr, ErrInboxCustodyIdentityConflict) ||
				errors.Is(parseErr, ErrInboxCustodyIneligible) {
				return outcome, parseErr
			}
			if errors.Is(parseErr, ErrInboxFull) && fullOutcome == nil {
				copyOutcome := outcome
				fullOutcome = &copyOutcome
			}
			// A protocol response is authoritative for this relay peer. Move to
			// the next peer rather than repeating the same action over a sibling
			// transport address.
			break
		}
		if !peerResponded {
			continue
		}
	}

	if fullOutcome != nil {
		return *fullOutcome, fmt.Errorf("all %d relays rejected protected custody: %w", len(relays), ErrInboxFull)
	}
	if lastErr == nil {
		lastErr = ErrInboxCustodyInvalidReceipt
	}
	n.emitEvent("inbox:store_timing", map[string]interface{}{
		"totalMs":   time.Since(start).Milliseconds(),
		"outcome":   "store_failed",
		"errorCode": lastOutcome.ErrorCode,
	})
	return lastOutcome, fmt.Errorf("all %d relays failed to accept protected custody: %w", len(relays), lastErr)
}

func isSupportedInboxCustodyKind(kind string) bool {
	return kind == CustodyKindDirectTextV108 ||
		kind == CustodyKindDirectReactionV109 ||
		kind == CustodyKindDirectMutationV109 ||
		kind == CustodyKindGroupBootstrapV1 ||
		kind == CustodyKindGroupAuthorityV1 ||
		kind == CustodyKindGroupContentV1
}

func (n *Node) exchangeInboxRequest(
	h host.Host,
	relay RelayInfo,
	req inboxRequest,
	timeout time.Duration,
) ([]byte, error) {
	ctx, cancel := context.WithTimeout(n.ctx, timeout)
	defer cancel()

	if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
		return nil, fmt.Errorf("connect to relay: %w", err)
	}
	s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
	if err != nil {
		return nil, fmt.Errorf("open inbox stream: %w", err)
	}
	streamOK := false
	defer finishStream(s, &streamOK)
	setStreamDeadline(s, timeout)

	reqBytes, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}
	if err := writeFrame(s, reqBytes); err != nil {
		return nil, fmt.Errorf("write request: %w", err)
	}
	respBytes, err := readFrame(s)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	streamOK = true
	return respBytes, nil
}

// RelayPresence is the coarse, "online-ish, TTL-lagged" presence answer the
// relay's additive `presence_get` action returns. It is NEVER a
// foreground/background claim.
type RelayPresence string

const (
	RelayPresenceReachable   RelayPresence = "reachable"
	RelayPresenceUnreachable RelayPresence = "unreachable"
	RelayPresenceUnknown     RelayPresence = "unknown"
)

// RelayPresenceResult is the decoded `presence_get` answer: a coarse presence
// plus the age (ms) of the relay's freshest record for the peer.
type RelayPresenceResult struct {
	Presence RelayPresence
	AgeMs    int64
}

// parsePresenceResponse decodes a relay `presence_get` reply into a
// RelayPresenceResult. It NEVER returns an error for a protocol-level problem
// (malformed JSON, a non-OK status such as an old relay's
// "Unknown action: presence_get", or an unrecognized presence value): all of
// those degrade to `unknown` so a stale/old/garbled hint can never throw away a
// send (NET-REL-07 / INBOX_UNKNOWN_ACTION_DEGRADES_TO_UNKNOWN_PRESENCE).
func parsePresenceResponse(respBytes []byte) RelayPresenceResult {
	var resp inboxResponse
	if err := json.Unmarshal(respBytes, &resp); err != nil {
		return RelayPresenceResult{Presence: RelayPresenceUnknown}
	}
	if resp.Status != "OK" {
		// Old relay (Unknown action) or any error -> unknown, never unreachable.
		return RelayPresenceResult{Presence: RelayPresenceUnknown}
	}
	presence := RelayPresence(resp.Presence)
	switch presence {
	case RelayPresenceReachable, RelayPresenceUnreachable, RelayPresenceUnknown:
		// recognized
	default:
		presence = RelayPresenceUnknown
	}
	return RelayPresenceResult{Presence: presence, AgeMs: resp.AgeMs}
}

// RelayPresenceLookup asks the relay whether a peer is online-ish via the
// additive `presence_get` inbox action — WITHOUT dialing a circuit (unlike the
// blind ≤5 s DialPeerViaRelay probe). It is the cheap up-front emphasis hint
// the send path consults (FDC-08 §6.3): reachable -> direct-race + lazy inbox /
// unreachable -> inbox-first + push / unknown -> today's full concurrent race.
//
// It tries each configured relay in turn (parity with the store/probe paths): a
// connect/stream/read failure rolls over to the next relay, while ANY received
// reply — including an old relay's "Unknown action" — is a definitive answer
// that degrades to `unknown` rather than retrying. If every relay is
// unreachable it returns `unknown` plus the aggregate error, so a relay outage
// is never mistaken for an offline peer.
func (n *Node) RelayPresenceLookup(peerIdStr string) (RelayPresenceResult, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return RelayPresenceResult{Presence: RelayPresenceUnknown}, fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	result := RelayPresenceResult{Presence: RelayPresenceUnknown}
	err := rs.ForEach(func(relay RelayInfo) error {
		ctx, cancel := context.WithTimeout(n.ctx, RelayProbeTimeout)
		defer cancel()

		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			return fmt.Errorf("connect to relay: %w", err)
		}

		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		if err != nil {
			return fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, RelayProbeTimeout)

		req := inboxRequest{
			Action: "presence_get",
			To:     peerIdStr,
			From:   n.peerId,
		}
		reqBytes, err := json.Marshal(req)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}
		if err := writeFrame(s, reqBytes); err != nil {
			return fmt.Errorf("write request: %w", err)
		}

		respBytes, err := readFrame(s)
		if err != nil {
			return fmt.Errorf("read response: %w", err)
		}

		// A received reply is definitive (even an old relay's Unknown-action,
		// which parsePresenceResponse degrades to unknown) — stop rolling over.
		result = parsePresenceResponse(respBytes)
		streamOK = true
		return nil
	})
	if err != nil {
		return RelayPresenceResult{Presence: RelayPresenceUnknown}, err
	}
	return result, nil
}

// RelayPresenceSetResult is the decoded `presence_set` write outcome. OK is true
// when the relay accepted the self-publish; on an OLD relay it is false with
// Error == "Unknown action: presence_set", which the client maps to "presence
// unsupported -> skip" (NET-REL-07).
type RelayPresenceSetResult struct {
	OK    bool
	Error string
}

// parsePresenceSetResponse decodes a relay `presence_set` reply. A malformed or
// non-OK reply (including an old relay's "Unknown action: presence_set") yields
// OK:false with the relay's error text — never a thrown error, because presence
// is a best-effort HINT that must never throw away a send.
func parsePresenceSetResponse(respBytes []byte) RelayPresenceSetResult {
	var resp inboxResponse
	if err := json.Unmarshal(respBytes, &resp); err != nil {
		return RelayPresenceSetResult{OK: false, Error: "invalid response"}
	}
	if resp.Status == "OK" {
		return RelayPresenceSetResult{OK: true}
	}
	return RelayPresenceSetResult{OK: false, Error: resp.Error}
}

// RelayPresenceSet SELF-PUBLISHES this node's coarse foreground/background state
// to the relay via the additive `presence_set` inbox action (FDC-09 §6.3 write
// side, Option C). The relay derives the subject peer from the AUTHENTICATED
// stream identity (anti-spoof), so this carries only {state, ttlMs}. It is a
// best-effort HINT feeding the read-side emphasis (FDC-08): a relay outage / old
// relay never throws away delivery — the inbox + push remain the guarantee
// (PRESENCE_NEVER_LOAD_BEARING).
//
// It tries each configured relay in turn (parity with store/probe/lookup): a
// connect/stream/read failure rolls over to the next relay, while ANY received
// reply — including an old relay's "Unknown action: presence_set" — is a
// definitive answer (OK:false, surfaced for the client's NET-REL-07 skip).
func (n *Node) RelayPresenceSet(state string, ttlMs int64) (RelayPresenceSetResult, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return RelayPresenceSetResult{}, fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	result := RelayPresenceSetResult{}
	err := rs.ForEach(func(relay RelayInfo) error {
		ctx, cancel := context.WithTimeout(n.ctx, RelayProbeTimeout)
		defer cancel()

		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			return fmt.Errorf("connect to relay: %w", err)
		}

		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		if err != nil {
			return fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, RelayProbeTimeout)

		req := inboxRequest{
			Action:   "presence_set",
			From:     n.peerId,
			Metadata: map[string]interface{}{"state": state, "ttlMs": ttlMs},
		}
		reqBytes, err := json.Marshal(req)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}
		if err := writeFrame(s, reqBytes); err != nil {
			return fmt.Errorf("write request: %w", err)
		}

		respBytes, err := readFrame(s)
		if err != nil {
			return fmt.Errorf("read response: %w", err)
		}

		// A received reply is definitive (even an old relay's Unknown-action) —
		// stop rolling over.
		result = parsePresenceSetResponse(respBytes)
		streamOK = true
		return nil
	})
	if err != nil {
		return RelayPresenceSetResult{}, err
	}
	return result, nil
}

// InboxRetrieve retrieves pending messages from the offline inbox.
// Tries each configured relay in order until one succeeds.
func (n *Node) InboxRetrieve() ([]InboxMessage, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	retrieveStart := time.Now()
	result, err := ForEachWithResult(rs, func(relay RelayInfo) ([]InboxMessage, error) {
		timeout := InboxTimeout
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			return nil, fmt.Errorf("connect to relay: %w", err)
		}

		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		if err != nil {
			return nil, fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		req := inboxRequest{
			Action: "retrieve",
			Limit:  50,
		}

		reqBytes, err := json.Marshal(req)
		if err != nil {
			return nil, fmt.Errorf("marshal request: %w", err)
		}

		if err := writeFrame(s, reqBytes); err != nil {
			return nil, fmt.Errorf("write request: %w", err)
		}

		respBytes, err := readFrame(s)
		if err != nil {
			return nil, fmt.Errorf("read response: %w", err)
		}

		var resp inboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return nil, fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status == "NO_MESSAGES" {
			streamOK = true
			return nil, nil
		}

		if resp.Status != "OK" {
			return nil, fmt.Errorf("inbox retrieve failed: %s", resp.Error)
		}

		log.Printf("[INBOX] Retrieved %d messages", len(resp.Messages))
		streamOK = true
		return resp.Messages, nil
	})
	outcome := "success"
	if err != nil {
		outcome = "failed"
	}
	msgCount := 0
	if result != nil {
		msgCount = len(result)
	}
	n.emitEvent("inbox:retrieve_timing", map[string]interface{}{
		"totalMs":      time.Since(retrieveStart).Milliseconds(),
		"outcome":      outcome,
		"messageCount": msgCount,
	})
	return result, err
}

// InboxRetrieveResult holds the paginated result from InboxRetrieveWithTimeout.
type InboxRetrieveResult struct {
	Messages []InboxMessage
	HasMore  bool
}

// InboxRetrieveWithTimeout retrieves pending messages with an explicit timeout
// and pagination support. If timeoutMs <= 0, the default InboxTimeout is used.
// The HasMore field indicates whether additional pages are available.
// Tries each configured relay in order until one succeeds.
func (n *Node) InboxRetrieveWithTimeout(timeoutMs int) (*InboxRetrieveResult, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	timeout := InboxTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}

	rs := n.buildRelaySelector(nil)

	return ForEachWithResult(rs, func(relay RelayInfo) (*InboxRetrieveResult, error) {
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			return nil, fmt.Errorf("connect to relay: %w", err)
		}

		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		if err != nil {
			return nil, fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		req := inboxRequest{
			Action: "retrieve",
			Limit:  50,
		}

		reqBytes, err := json.Marshal(req)
		if err != nil {
			return nil, fmt.Errorf("marshal request: %w", err)
		}

		if err := writeFrame(s, reqBytes); err != nil {
			return nil, fmt.Errorf("write request: %w", err)
		}

		respBytes, err := readFrame(s)
		if err != nil {
			return nil, fmt.Errorf("read response: %w", err)
		}

		var resp inboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return nil, fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status == "NO_MESSAGES" {
			streamOK = true
			return &InboxRetrieveResult{Messages: nil, HasMore: false}, nil
		}

		if resp.Status != "OK" {
			return nil, fmt.Errorf("inbox retrieve failed: %s", resp.Error)
		}

		log.Printf("[INBOX] Retrieved %d messages (hasMore=%v, timeout=%v)", len(resp.Messages), resp.HasMore, timeout)
		streamOK = true
		return &InboxRetrieveResult{Messages: resp.Messages, HasMore: resp.HasMore}, nil
	})
}

// InboxRetrievePendingResult holds the paginated result from
// InboxRetrievePendingWithTimeout.
type InboxRetrievePendingResult struct {
	Messages        []InboxMessage
	HasMore         bool
	CustodyContract string
}

// InboxRetrievePendingWithTimeout retrieves pending inbox messages without
// deleting them from the relay. If timeoutMs <= 0, the default InboxTimeout is
// used.
func (n *Node) InboxRetrievePendingWithTimeout(timeoutMs int) (*InboxRetrievePendingResult, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	timeout := InboxTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}

	rs := n.buildRelaySelector(nil)

	return ForEachWithResult(rs, func(relay RelayInfo) (*InboxRetrievePendingResult, error) {
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			return nil, fmt.Errorf("connect to relay: %w", err)
		}

		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		if err != nil {
			return nil, fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		req := inboxRequest{
			Action: "retrieve_pending",
			Limit:  50,
		}

		reqBytes, err := json.Marshal(req)
		if err != nil {
			return nil, fmt.Errorf("marshal request: %w", err)
		}

		if err := writeFrame(s, reqBytes); err != nil {
			return nil, fmt.Errorf("write request: %w", err)
		}

		respBytes, err := readFrame(s)
		if err != nil {
			return nil, fmt.Errorf("read response: %w", err)
		}

		var resp inboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return nil, fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status == "NO_MESSAGES" {
			streamOK = true
			return &InboxRetrievePendingResult{Messages: nil, HasMore: false}, nil
		}

		if resp.Status != "OK" {
			return nil, fmt.Errorf("inbox retrieve pending failed: %s", resp.Error)
		}

		log.Printf("[INBOX] Retrieved pending %d messages (hasMore=%v, timeout=%v)",
			len(resp.Messages), resp.HasMore, timeout)
		streamOK = true
		return &InboxRetrievePendingResult{Messages: resp.Messages, HasMore: resp.HasMore}, nil
	})
}

// InboxAck deletes only the relay inbox entries whose stable entry IDs match
// the provided slice. If timeoutMs <= 0, the default InboxTimeout is used.
func (n *Node) InboxAck(entryIDs []string, timeoutMs int) (int, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return 0, fmt.Errorf("node not started")
	}

	timeout := InboxTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}

	rs := n.buildRelaySelector(nil)

	return ForEachWithResult(rs, func(relay RelayInfo) (int, error) {
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			return 0, fmt.Errorf("connect to relay: %w", err)
		}

		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		if err != nil {
			return 0, fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		req := inboxRequest{
			Action:   "ack",
			EntryIds: entryIDs,
		}

		reqBytes, err := json.Marshal(req)
		if err != nil {
			return 0, fmt.Errorf("marshal request: %w", err)
		}

		if err := writeFrame(s, reqBytes); err != nil {
			return 0, fmt.Errorf("write request: %w", err)
		}

		respBytes, err := readFrame(s)
		if err != nil {
			return 0, fmt.Errorf("read response: %w", err)
		}

		var resp inboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return 0, fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status != "OK" {
			return 0, fmt.Errorf("inbox ack failed: %s", resp.Error)
		}

		log.Printf("[INBOX] Acked %d messages (timeout=%v)", resp.Acked, timeout)
		streamOK = true
		return resp.Acked, nil
	})
}

// InboxRetrieveAckCustodyPendingWithTimeout scans every configured relay peer.
// Each peer is negotiated independently: the protected action is attempted
// first and any invalid/unsupported leg falls back to legacy retrieve_pending
// on that same peer. Results are exact-coalesced and globally FIFO sorted.
func (n *Node) InboxRetrieveAckCustodyPendingWithTimeout(
	timeoutMs int,
) (*InboxRetrievePendingResult, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()
	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	timeout := InboxTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}
	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return nil, fmt.Errorf("no relays configured")
	}

	legs := mapInboxAckCustodyRelays(relays, func(relay RelayInfo) (inboxCustodyRetrieveLeg, error) {
		return n.retrieveAckCustodyRelay(h, relay, timeout)
	})
	allMessages := make([]InboxMessage, 0)
	sourceHasMore := false
	validPeers := 0
	failedPeers := 0
	var lastErr error
	for _, leg := range legs {
		if leg.err != nil {
			failedPeers++
			lastErr = leg.err
			continue
		}
		validPeers++
		allMessages = append(allMessages, leg.value.Messages...)
		sourceHasMore = sourceHasMore || leg.value.HasMore
	}

	merged, err := coalesceAndSortInboxCustodyMessages(allMessages)
	if err != nil {
		return nil, err
	}
	if len(merged) == 0 && validPeers != len(relays) {
		if lastErr == nil {
			lastErr = ErrInboxCustodyPartial
		}
		return nil, fmt.Errorf("%w: empty scan reached %d/%d relays: %v",
			ErrInboxCustodyPartial, validPeers, len(relays), lastErr)
	}
	if validPeers == 0 {
		return nil, fmt.Errorf("%w: no relay returned a valid inbox response", ErrInboxCustodyPartial)
	}

	page, hasMore, err := fitInboxAckCustodyPage(
		merged,
		sourceHasMore || (failedPeers > 0 && len(merged) > 0),
	)
	if err != nil {
		return nil, err
	}
	return &InboxRetrievePendingResult{
		Messages:        page,
		HasMore:         hasMore,
		CustodyContract: AckOrExpiryCustodyContract,
	}, nil
}

type inboxCustodyRetrieveLeg struct {
	Messages []InboxMessage
	HasMore  bool
}

func (n *Node) retrieveAckCustodyRelay(
	h host.Host,
	relay RelayInfo,
	timeout time.Duration,
) (inboxCustodyRetrieveLeg, error) {
	var lastErr error
	for _, candidate := range relayInfoAttemptCandidates(relay) {
		strictRaw, err := n.exchangeInboxRequest(h, candidate, inboxRequest{
			Action:          inboxRetrieveAckCustodyAction,
			Limit:           50,
			CustodyContract: AckOrExpiryCustodyContract,
		}, timeout)
		if err == nil {
			if result, parseErr := parseInboxCustodyRetrieveResponse(strictRaw, true); parseErr == nil {
				return result, nil
			} else {
				lastErr = parseErr
			}
		} else {
			lastErr = err
		}

		legacyRaw, legacyErr := n.exchangeInboxRequest(h, candidate, inboxRequest{
			Action: "retrieve_pending",
			Limit:  50,
		}, timeout)
		if legacyErr == nil {
			if result, parseErr := parseInboxCustodyRetrieveResponse(legacyRaw, false); parseErr == nil {
				return result, nil
			} else {
				lastErr = parseErr
			}
		} else {
			lastErr = legacyErr
		}
	}
	if lastErr == nil {
		lastErr = ErrInboxCustodyInvalidReceipt
	}
	return inboxCustodyRetrieveLeg{}, lastErr
}

func parseInboxCustodyRetrieveResponse(raw []byte, requireProof bool) (inboxCustodyRetrieveLeg, error) {
	var resp inboxResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return inboxCustodyRetrieveLeg{}, fmt.Errorf("unmarshal inbox retrieve response: %w", err)
	}
	if requireProof && resp.CustodyContract != AckOrExpiryCustodyContract {
		return inboxCustodyRetrieveLeg{}, fmt.Errorf("%w: retrieve response missing exact proof", ErrInboxCustodyInvalidReceipt)
	}
	switch resp.Status {
	case "NO_MESSAGES":
		if len(resp.Messages) != 0 || resp.HasMore {
			return inboxCustodyRetrieveLeg{}, fmt.Errorf("%w: inconsistent NO_MESSAGES response", ErrInboxCustodyInvalidReceipt)
		}
		return inboxCustodyRetrieveLeg{}, nil
	case "OK":
		return inboxCustodyRetrieveLeg{Messages: resp.Messages, HasMore: resp.HasMore}, nil
	default:
		return inboxCustodyRetrieveLeg{}, fmt.Errorf("inbox retrieve failed: %s", responseErrorText(resp))
	}
}

func coalesceAndSortInboxCustodyMessages(messages []InboxMessage) ([]InboxMessage, error) {
	byID := make(map[string]InboxMessage, len(messages))
	for _, message := range messages {
		if message.ID == "" {
			return nil, fmt.Errorf("%w: relay returned a blank entry ID", ErrInboxCustodyInvalidReceipt)
		}
		if existing, ok := byID[message.ID]; ok {
			if existing.From != message.From || existing.Message != message.Message {
				return nil, fmt.Errorf("%w: relay entry ID %q has conflicting sender or bytes",
					ErrInboxCustodyIdentityConflict, message.ID)
			}
			if message.Timestamp < existing.Timestamp {
				existing.Timestamp = message.Timestamp
				byID[message.ID] = existing
			}
			continue
		}
		byID[message.ID] = message
	}

	merged := make([]InboxMessage, 0, len(byID))
	for _, message := range byID {
		merged = append(merged, message)
	}
	sort.Slice(merged, func(i, j int) bool {
		if merged[i].Timestamp == merged[j].Timestamp {
			return merged[i].ID < merged[j].ID
		}
		return merged[i].Timestamp < merged[j].Timestamp
	})
	return merged, nil
}

func fitInboxAckCustodyPage(
	messages []InboxMessage,
	sourceHasMore bool,
) ([]InboxMessage, bool, error) {
	limit := min(len(messages), 50)
	page := append([]InboxMessage(nil), messages[:limit]...)
	hasMore := sourceHasMore || len(messages) > limit
	for len(page) > 0 {
		encoded, err := json.Marshal(inboxResponse{
			Status:          "OK",
			Messages:        page,
			HasMore:         hasMore,
			CustodyContract: AckOrExpiryCustodyContract,
		})
		if err != nil {
			return nil, false, fmt.Errorf("marshal merged inbox page: %w", err)
		}
		if len(encoded) <= MaxFrameLen {
			return page, hasMore, nil
		}
		page = page[:len(page)-1]
		hasMore = true
	}
	if len(messages) > 0 {
		return nil, false, fmt.Errorf("%w: first merged inbox entry exceeds frame limit", ErrInboxCustodyInvalidReceipt)
	}
	return nil, hasMore, nil
}

// InboxAckCustody best-effort fans the unique entry IDs out to every relay
// peer. Each peer uses protected ACK when supported and legacy ACK otherwise.
// A partial relay failure or aggregate count below the requested logical count
// is non-accepting; callers safely retry after their durable local replay.
func (n *Node) InboxAckCustody(entryIDs []string, timeoutMs int) (int, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()
	if h == nil {
		return 0, fmt.Errorf("node not started")
	}

	uniqueIDs := uniqueNonblankInboxEntryIDs(entryIDs)
	if len(uniqueIDs) == 0 {
		return 0, fmt.Errorf("missing nonblank entry IDs")
	}
	timeout := InboxTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}
	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return 0, fmt.Errorf("no relays configured")
	}

	legs := mapInboxAckCustodyRelays(relays, func(relay RelayInfo) (int, error) {
		return n.ackCustodyRelay(h, relay, uniqueIDs, timeout)
	})
	totalAcked := 0
	failedPeers := 0
	var lastErr error
	for _, leg := range legs {
		if leg.err != nil {
			failedPeers++
			lastErr = leg.err
			continue
		}
		totalAcked += leg.value
	}
	logicalAcked := min(totalAcked, len(uniqueIDs))
	if failedPeers > 0 {
		return logicalAcked, fmt.Errorf("%w: ACK reached %d/%d relays: %v",
			ErrInboxCustodyPartial, len(relays)-failedPeers, len(relays), lastErr)
	}
	if totalAcked < len(uniqueIDs) {
		return logicalAcked, fmt.Errorf("%w: ACK count %d below requested logical count %d",
			ErrInboxCustodyPartial, totalAcked, len(uniqueIDs))
	}
	return logicalAcked, nil
}

func (n *Node) ackCustodyRelay(
	h host.Host,
	relay RelayInfo,
	entryIDs []string,
	timeout time.Duration,
) (int, error) {
	var lastErr error
	for _, candidate := range relayInfoAttemptCandidates(relay) {
		strictRaw, err := n.exchangeInboxRequest(h, candidate, inboxRequest{
			Action:          inboxAckCustodyAction,
			EntryIds:        entryIDs,
			CustodyContract: AckOrExpiryCustodyContract,
		}, timeout)
		if err == nil {
			if acked, parseErr := parseInboxCustodyAckResponse(strictRaw, true, len(entryIDs)); parseErr == nil {
				return acked, nil
			} else {
				lastErr = parseErr
			}
		} else {
			lastErr = err
		}

		legacyRaw, legacyErr := n.exchangeInboxRequest(h, candidate, inboxRequest{
			Action:   "ack",
			EntryIds: entryIDs,
		}, timeout)
		if legacyErr == nil {
			if acked, parseErr := parseInboxCustodyAckResponse(legacyRaw, false, len(entryIDs)); parseErr == nil {
				return acked, nil
			} else {
				lastErr = parseErr
			}
		} else {
			lastErr = legacyErr
		}
	}
	if lastErr == nil {
		lastErr = ErrInboxCustodyInvalidReceipt
	}
	return 0, lastErr
}

func parseInboxCustodyAckResponse(raw []byte, requireProof bool, requested int) (int, error) {
	var resp inboxResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return 0, fmt.Errorf("unmarshal inbox ACK response: %w", err)
	}
	if resp.Status != "OK" {
		return 0, fmt.Errorf("inbox ACK failed: %s", responseErrorText(resp))
	}
	if requireProof && resp.CustodyContract != AckOrExpiryCustodyContract {
		return 0, fmt.Errorf("%w: ACK response missing exact proof", ErrInboxCustodyInvalidReceipt)
	}
	if resp.Acked < 0 {
		return 0, fmt.Errorf("%w: negative ACK count", ErrInboxCustodyInvalidReceipt)
	}
	if resp.Acked > requested {
		return 0, fmt.Errorf("%w: ACK count %d exceeds requested count %d",
			ErrInboxCustodyInvalidReceipt, resp.Acked, requested)
	}
	return resp.Acked, nil
}

func uniqueNonblankInboxEntryIDs(entryIDs []string) []string {
	seen := make(map[string]struct{}, len(entryIDs))
	unique := make([]string, 0, len(entryIDs))
	for _, entryID := range entryIDs {
		if entryID == "" {
			continue
		}
		if _, ok := seen[entryID]; ok {
			continue
		}
		seen[entryID] = struct{}{}
		unique = append(unique, entryID)
	}
	return unique
}

type inboxAckCustodyRelayResult[T any] struct {
	value T
	err   error
}

func mapInboxAckCustodyRelays[T any](
	relays []RelayInfo,
	fn func(RelayInfo) (T, error),
) []inboxAckCustodyRelayResult[T] {
	results := make([]inboxAckCustodyRelayResult[T], len(relays))
	if len(relays) == 0 {
		return results
	}
	type relayJob struct {
		index int
		relay RelayInfo
	}
	jobs := make(chan relayJob)
	var wg sync.WaitGroup
	for worker := 0; worker < min(len(relays), inboxAckCustodyFanoutLimit); worker++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for job := range jobs {
				results[job.index].value, results[job.index].err = fn(job.relay)
			}
		}()
	}
	for index, relay := range relays {
		jobs <- relayJob{index: index, relay: relay}
	}
	close(jobs)
	wg.Wait()
	return results
}

// IsCanonicalWakeOutcomeCorrelation reports whether value is the sole wire
// identity accepted by wake_outcome_v1: exactly 32 SHA-256 bytes encoded as 64
// lowercase hexadecimal characters.
func IsCanonicalWakeOutcomeCorrelation(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, char := range value {
		if (char < '0' || char > '9') && (char < 'a' || char > 'f') {
			return false
		}
	}
	return true
}

// InboxWakeOutcome submits the local completed-notification outcome to every
// distinct configured relay. Unlike RelaySelector.FanOut, one accepting leg
// never hides another participant's retryable failure.
func (n *Node) InboxWakeOutcome(correlation string) (InboxWakeOutcomeResult, error) {
	if !IsCanonicalWakeOutcomeCorrelation(correlation) {
		return InboxWakeOutcomeResult{}, fmt.Errorf("invalid wake outcome correlation")
	}

	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()
	if h == nil {
		return InboxWakeOutcomeResult{}, fmt.Errorf("node not started")
	}

	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return InboxWakeOutcomeResult{}, fmt.Errorf("no relays configured")
	}

	deadline := time.Now().Add(InboxTimeout)
	legs := mapInboxAckCustodyRelays(relays, func(relay RelayInfo) (InboxWakeOutcomeRelayDisposition, error) {
		return n.sendInboxWakeOutcomeRelay(h, relay, correlation, deadline)
	})
	result := InboxWakeOutcomeResult{
		Relays:           make([]InboxWakeOutcomeRelayResult, len(relays)),
		ParticipantCount: len(relays),
	}
	for index, relay := range relays {
		disposition := legs[index].value
		if legs[index].err != nil {
			disposition = InboxWakeOutcomeRetryable
		}
		result.Relays[index] = InboxWakeOutcomeRelayResult{
			RelayID:     relay.ID.String(),
			Disposition: disposition,
		}
		switch disposition {
		case InboxWakeOutcomeAccepted:
			result.AcceptedCount++
		case InboxWakeOutcomeUnsupported:
			result.UnsupportedCount++
		default:
			result.RetryableCount++
			if legs[index].err != nil {
				result.Relays[index].Error = legs[index].err.Error()
			}
		}
	}
	result.AllParticipantsTerminal = result.RetryableCount == 0
	if !result.AllParticipantsTerminal {
		return result, fmt.Errorf(
			"%w: %d/%d relay participants require retry",
			ErrInboxWakeOutcomeRetryable,
			result.RetryableCount,
			result.ParticipantCount,
		)
	}
	return result, nil
}

func (n *Node) sendInboxWakeOutcomeRelay(
	h host.Host,
	relay RelayInfo,
	correlation string,
	deadline time.Time,
) (InboxWakeOutcomeRelayDisposition, error) {
	var lastErr error
	for _, candidate := range relayInfoAttemptCandidates(relay) {
		timeout := time.Until(deadline)
		if timeout <= 0 {
			lastErr = context.DeadlineExceeded
			break
		}
		raw, err := n.exchangeInboxRequest(h, candidate, inboxRequest{
			Action:          inboxWakeOutcomeAction,
			Correlation:     correlation,
			WakeNotRequired: true,
		}, timeout)
		if err != nil {
			lastErr = err
			continue
		}
		disposition, parseErr := parseInboxWakeOutcomeResponse(raw)
		if parseErr != nil {
			lastErr = parseErr
			continue
		}
		return disposition, nil
	}
	if lastErr == nil {
		lastErr = ErrInboxWakeOutcomeRetryable
	}
	return InboxWakeOutcomeRetryable, lastErr
}

func parseInboxWakeOutcomeResponse(raw []byte) (InboxWakeOutcomeRelayDisposition, error) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	start, err := decoder.Token()
	if err != nil {
		return InboxWakeOutcomeRetryable, fmt.Errorf("decode wake outcome response: %w", err)
	}
	if delimiter, ok := start.(json.Delim); !ok || delimiter != '{' {
		return InboxWakeOutcomeRetryable, fmt.Errorf("wake outcome response must be an object")
	}

	seen := make(map[string]struct{}, 2)
	status := ""
	errorText := ""
	for decoder.More() {
		token, tokenErr := decoder.Token()
		if tokenErr != nil {
			return InboxWakeOutcomeRetryable, fmt.Errorf("decode wake outcome response key: %w", tokenErr)
		}
		key, ok := token.(string)
		if !ok {
			return InboxWakeOutcomeRetryable, fmt.Errorf("wake outcome response key must be a string")
		}
		if _, duplicate := seen[key]; duplicate {
			return InboxWakeOutcomeRetryable, fmt.Errorf("duplicate wake outcome response key %q", key)
		}
		seen[key] = struct{}{}
		switch key {
		case "status":
			if err := decoder.Decode(&status); err != nil {
				return InboxWakeOutcomeRetryable, fmt.Errorf("decode wake outcome status: %w", err)
			}
		case "error":
			if err := decoder.Decode(&errorText); err != nil {
				return InboxWakeOutcomeRetryable, fmt.Errorf("decode wake outcome error: %w", err)
			}
		default:
			return InboxWakeOutcomeRetryable, fmt.Errorf("unknown wake outcome response key %q", key)
		}
	}
	if _, err := decoder.Token(); err != nil {
		return InboxWakeOutcomeRetryable, fmt.Errorf("close wake outcome response: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		if err == nil {
			return InboxWakeOutcomeRetryable, fmt.Errorf("wake outcome response has trailing JSON")
		}
		return InboxWakeOutcomeRetryable, fmt.Errorf("decode wake outcome response tail: %w", err)
	}

	switch {
	case status == "OK" && errorText == "":
		return InboxWakeOutcomeAccepted, nil
	case status == "ERROR" && errorText == "Unknown action: wake_outcome_v1":
		return InboxWakeOutcomeUnsupported, nil
	case status == "":
		return InboxWakeOutcomeRetryable, fmt.Errorf("wake outcome response missing status")
	default:
		return InboxWakeOutcomeRetryable, fmt.Errorf("wake outcome relay returned nonterminal response")
	}
}

// InboxRegisterToken registers an FCM push token with all configured relays.
// Optional capabilities are additive: an upgraded client advertises
// DirectReactionPushCapability, while an omitted slice preserves the legacy
// register_token frame. Succeeds if at least one relay accepts the token.
func (n *Node) InboxRegisterToken(
	token string,
	platform string,
	capabilities ...string,
) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	return rs.FanOut(func(relay RelayInfo) error {
		timeout := InboxTimeout
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			return fmt.Errorf("connect to relay: %w", err)
		}

		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		if err != nil {
			return fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		req := inboxRequest{
			Action:       "register_token",
			Token:        token,
			Platform:     platform,
			Capabilities: append([]string(nil), capabilities...),
		}

		reqBytes, err := json.Marshal(req)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}

		if err := writeFrame(s, reqBytes); err != nil {
			return fmt.Errorf("write request: %w", err)
		}

		respBytes, err := readFrame(s)
		if err != nil {
			return fmt.Errorf("read response: %w", err)
		}

		var resp inboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status != "OK" {
			return fmt.Errorf("register token failed: %s", resp.Error)
		}

		log.Printf("[INBOX] Push token registered on relay %s (%s)",
			relay.ID.String()[:min(20, len(relay.ID.String()))], platform)
		streamOK = true
		return nil
	})
}

// RelayRegisterWakeTokens registers this peer's opaque wake-token SET (the tokens
// it minted for its contacts) with all configured relays via the additive
// `register_wake_tokens` action (FDC-09 §12 access-token gate). Succeeds if at
// least one relay accepts. An old relay's "Unknown action" is surfaced as an
// error so the caller degrades gracefully (the plain push keeps working ungated,
// NET-REL-07) — it never throws away delivery.
func (n *Node) RelayRegisterWakeTokens(tokens []string) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	return rs.FanOut(func(relay RelayInfo) error {
		timeout := InboxTimeout
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			return fmt.Errorf("connect to relay: %w", err)
		}

		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		if err != nil {
			return fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		req := inboxRequest{
			Action:     "register_wake_tokens",
			WakeTokens: tokens,
		}

		reqBytes, err := json.Marshal(req)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}

		if err := writeFrame(s, reqBytes); err != nil {
			return fmt.Errorf("write request: %w", err)
		}

		respBytes, err := readFrame(s)
		if err != nil {
			return fmt.Errorf("read response: %w", err)
		}

		var resp inboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status != "OK" {
			return fmt.Errorf("register wake tokens failed: %s", resp.Error)
		}

		streamOK = true
		return nil
	})
}

// InboxUnregisterToken unregisters this peer's FCM push token with all
// configured relays. Missing server-side token state is idempotent at the
// relay; this call only fails if no relay accepts the command.
func (n *Node) InboxUnregisterToken(serverAddresses []string) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(serverAddresses)

	return rs.FanOut(func(relay RelayInfo) error {
		timeout := InboxTimeout
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
			return fmt.Errorf("connect to relay: %w", err)
		}

		s, err := h.NewStream(ctx, relay.ID, InboxProtocol)
		if err != nil {
			return fmt.Errorf("open inbox stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		req := inboxRequest{
			Action: "unregister_token",
		}

		reqBytes, err := json.Marshal(req)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}

		if err := writeFrame(s, reqBytes); err != nil {
			return fmt.Errorf("write request: %w", err)
		}

		respBytes, err := readFrame(s)
		if err != nil {
			return fmt.Errorf("read response: %w", err)
		}

		var resp inboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status != "OK" {
			return fmt.Errorf("unregister token failed: %s", resp.Error)
		}

		log.Printf("[INBOX] Push token unregistered on relay %s",
			relay.ID.String()[:min(20, len(relay.ID.String()))])
		streamOK = true
		return nil
	})
}

// getRelayInfo returns the relay peer ID and addresses.
// Deprecated: use buildRelaySelector instead for multi-relay support.
// Kept for backward compatibility with any callers not yet migrated.
func (n *Node) getRelayInfo(serverAddresses []string) (peer.ID, []ma.Multiaddr, error) {
	rs := n.buildRelaySelector(serverAddresses)
	first, err := rs.First()
	if err != nil {
		return "", nil, err
	}
	return first.ID, first.Addrs, nil
}
