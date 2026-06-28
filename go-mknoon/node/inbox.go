package node

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// InboxMessage represents a message stored in the offline inbox.
type InboxMessage struct {
	ID        string `json:"id,omitempty"`
	From      string `json:"from"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

type inboxRequest struct {
	Action   string   `json:"action"`
	To       string   `json:"to,omitempty"`
	From     string   `json:"from,omitempty"`
	Message  string   `json:"message,omitempty"`
	Limit    int      `json:"limit,omitempty"`
	EntryIds []string `json:"entryIds,omitempty"`
	Token    string   `json:"token,omitempty"`
	Platform string   `json:"platform,omitempty"`
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
	// FDC-08 presence_get response fields (additive). Presence is "online-ish",
	// never a foreground/background claim. AgeMs is the age of the relay's
	// freshest record for the peer in ms (-1 when nothing is known).
	Presence string `json:"presence,omitempty"`
	AgeMs    int64  `json:"ageMs,omitempty"`
}

var ErrInboxFull = errors.New("inbox full")

type InboxStoreOutcome struct {
	StoreStatus  string
	ErrorCode    string
	ErrorMessage string
	ExpiresAtMs  int64
	Occupancy    int
	Capacity     int
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
	Messages []InboxMessage
	HasMore  bool
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

// InboxRegisterToken registers an FCM push token with all configured relays.
// Succeeds if at least one relay accepts the token.
func (n *Node) InboxRegisterToken(token string, platform string) error {
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
			Action:   "register_token",
			Token:    token,
			Platform: platform,
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
