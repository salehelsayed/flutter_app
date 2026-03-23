package node

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// groupInboxRequest is the JSON envelope sent to the relay server
// for group inbox operations.
type groupInboxRequest struct {
	Action           string   `json:"action"`
	GroupId          string   `json:"groupId,omitempty"`
	From             string   `json:"from,omitempty"`
	Message          string   `json:"message,omitempty"`
	RecipientPeerIds []string `json:"recipientPeerIds,omitempty"`
	PushTitle        string   `json:"pushTitle,omitempty"`
	PushBody         string   `json:"pushBody,omitempty"`
	SinceTimestamp   int64    `json:"sinceTimestamp,omitempty"`
	Cursor           string   `json:"cursor,omitempty"`
	Limit            int      `json:"limit,omitempty"`
}

// groupInboxResponse is the JSON envelope received from the relay
// server for group inbox operations.
// NOTE: The relay uses "groupMessages" (not "messages") for group inbox.
type groupInboxResponse struct {
	Status     string         `json:"status"`
	Error      string         `json:"error,omitempty"`
	Messages   []InboxMessage `json:"groupMessages,omitempty"`
	NextCursor string         `json:"nextCursor,omitempty"`
}

// GroupInboxStore stores a group message in the relay's group inbox.
// This allows offline members to retrieve group messages they missed.
// Tries each configured relay in order until one succeeds.
func (n *Node) GroupInboxStore(
	groupId,
	message string,
	recipientPeerIds []string,
	pushTitle,
	pushBody string,
) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	return rs.ForEach(func(relay RelayInfo) error {
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

		req := buildGroupInboxStoreRequest(
			groupId,
			n.peerId,
			message,
			recipientPeerIds,
			pushTitle,
			pushBody,
		)

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

		var resp groupInboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status != "OK" {
			return fmt.Errorf("group inbox store failed: %s", resp.Error)
		}

		log.Printf("[GROUP_INBOX] Stored message for group %s", groupId)
		streamOK = true
		return nil
	})
}

func buildGroupInboxStoreRequest(
	groupId,
	from,
	message string,
	recipientPeerIds []string,
	pushTitle,
	pushBody string,
) groupInboxRequest {
	return groupInboxRequest{
		Action:           "group_store",
		GroupId:          groupId,
		From:             from,
		Message:          message,
		RecipientPeerIds: recipientPeerIds,
		PushTitle:        pushTitle,
		PushBody:         pushBody,
	}
}

// GroupInboxRetrieve retrieves missed group messages from the relay's group inbox
// since the given timestamp (unix milliseconds). Returns messages in chronological order.
// Tries each configured relay in order until one succeeds.
func (n *Node) GroupInboxRetrieve(groupId string, sinceTimestamp int64) ([]InboxMessage, error) {
	result, err := n.groupInboxRetrieve(groupInboxRequest{
		Action:         "group_retrieve",
		GroupId:        groupId,
		SinceTimestamp: sinceTimestamp,
		Limit:          50,
	})
	if err != nil {
		return nil, err
	}
	return result.Messages, nil
}

// GroupInboxRetrieveWithCursor retrieves missed group messages using cursor-based
// pagination. The cursor is opaque and comes from the relay server.
// Tries each configured relay in order until one succeeds.
func (n *Node) GroupInboxRetrieveWithCursor(groupId, cursor string, limit int) ([]InboxMessage, string, error) {
	if limit <= 0 {
		limit = 50
	}

	result, err := n.groupInboxRetrieve(groupInboxRequest{
		Action:  "group_retrieve_cursor",
		GroupId: groupId,
		Cursor:  cursor,
		Limit:   limit,
	})
	if err != nil {
		return nil, "", err
	}
	return result.Messages, result.NextCursor, nil
}

func (n *Node) groupInboxRetrieve(req groupInboxRequest) (*groupInboxResponse, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(nil)

	return ForEachWithResult(rs, func(relay RelayInfo) (*groupInboxResponse, error) {
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

		var resp groupInboxResponse
		if err := json.Unmarshal(respBytes, &resp); err != nil {
			return nil, fmt.Errorf("unmarshal response: %w", err)
		}

		if resp.Status == "NO_MESSAGES" {
			streamOK = true
			return &groupInboxResponse{}, nil
		}

		if resp.Status != "OK" {
			return nil, fmt.Errorf("group inbox retrieve failed: %s", resp.Error)
		}

		log.Printf(
			"[GROUP_INBOX] Retrieved %d messages for group %s (cursor=%q)",
			len(resp.Messages),
			req.GroupId,
			resp.NextCursor,
		)
		streamOK = true
		return &resp, nil
	})
}

// getGroupRelayInfo returns the relay peer ID and addresses.
// Deprecated: use buildRelaySelector instead for multi-relay support.
func (n *Node) getGroupRelayInfo() (peer.ID, []ma.Multiaddr, error) {
	return n.getRelayInfo(nil)
}
