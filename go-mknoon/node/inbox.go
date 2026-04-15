package node

import (
	"context"
	"encoding/json"
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
}

type inboxResponse struct {
	Status   string         `json:"status"`
	Error    string         `json:"error,omitempty"`
	Messages []InboxMessage `json:"messages,omitempty"`
	HasMore  bool           `json:"hasMore,omitempty"`
	Acked    int            `json:"acked,omitempty"`
}

// InboxStore stores a message in the offline inbox for a peer.
// Tries each configured relay in order until one succeeds.
func (n *Node) InboxStore(toPeerId string, message string, timeoutMs int) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	totalStart := time.Now()
	return rs.ForEach(func(relay RelayInfo) error {
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
			Action:  "store",
			To:      toPeerId,
			From:    n.peerId,
			Message: message,
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

		var resp inboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status != "OK" {
			return fmt.Errorf("inbox store failed: %s", resp.Error)
		}

		n.emitEvent("inbox:store_timing", map[string]interface{}{
			"connectMs":    connectMs,
			"streamOpenMs": streamOpenMs,
			"writeMs":      writeMs,
			"readMs":       readMs,
			"totalMs":      time.Since(totalStart).Milliseconds(),
			"outcome":      "success",
		})
		log.Printf("[INBOX] Stored message for %s", toPeerId[:min(20, len(toPeerId))])
		streamOK = true
		return nil
	})
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
