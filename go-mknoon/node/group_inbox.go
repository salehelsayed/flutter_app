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
	Action         string `json:"action"`
	GroupId        string `json:"groupId,omitempty"`
	From           string `json:"from,omitempty"`
	Message        string `json:"message,omitempty"`
	SinceTimestamp int64  `json:"sinceTimestamp,omitempty"`
	Limit          int    `json:"limit,omitempty"`
}

// groupInboxResponse is the JSON envelope received from the relay
// server for group inbox operations.
// NOTE: The relay uses "groupMessages" (not "messages") for group inbox.
type groupInboxResponse struct {
	Status   string         `json:"status"`
	Error    string         `json:"error,omitempty"`
	Messages []InboxMessage `json:"groupMessages,omitempty"`
}

// GroupInboxStore stores a group message in the relay's group inbox.
// This allows offline members to retrieve group messages they missed.
func (n *Node) GroupInboxStore(groupId, message string) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	relayPeer, relayAddrs, err := n.getGroupRelayInfo()
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(n.ctx, InboxTimeout)
	defer cancel()

	if err := h.Connect(ctx, peer.AddrInfo{ID: relayPeer, Addrs: relayAddrs}); err != nil {
		return fmt.Errorf("connect to relay: %w", err)
	}

	s, err := h.NewStream(ctx, relayPeer, InboxProtocol)
	if err != nil {
		return fmt.Errorf("open inbox stream: %w", err)
	}
	defer s.Close()

	req := groupInboxRequest{
		Action:  "group_store",
		GroupId: groupId,
		From:    n.peerId,
		Message: message,
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

	var resp groupInboxResponse
	if err := json.Unmarshal(respBytes, &resp); err != nil {
		return fmt.Errorf("unmarshal response: %w", err)
	}

	if resp.Status != "OK" {
		return fmt.Errorf("group inbox store failed: %s", resp.Error)
	}

	log.Printf("[GROUP_INBOX] Stored message for group %s", groupId)
	return nil
}

// GroupInboxRetrieve retrieves missed group messages from the relay's group inbox
// since the given timestamp (unix milliseconds). Returns messages in chronological order.
func (n *Node) GroupInboxRetrieve(groupId string, sinceTimestamp int64) ([]InboxMessage, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	relayPeer, relayAddrs, err := n.getGroupRelayInfo()
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(n.ctx, InboxTimeout)
	defer cancel()

	if err := h.Connect(ctx, peer.AddrInfo{ID: relayPeer, Addrs: relayAddrs}); err != nil {
		return nil, fmt.Errorf("connect to relay: %w", err)
	}

	s, err := h.NewStream(ctx, relayPeer, InboxProtocol)
	if err != nil {
		return nil, fmt.Errorf("open inbox stream: %w", err)
	}
	defer s.Close()

	req := groupInboxRequest{
		Action:         "group_retrieve",
		GroupId:        groupId,
		SinceTimestamp: sinceTimestamp,
		Limit:          50,
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

	var resp groupInboxResponse
	if err := json.Unmarshal(respBytes, &resp); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}

	if resp.Status == "NO_MESSAGES" {
		return nil, nil
	}

	if resp.Status != "OK" {
		return nil, fmt.Errorf("group inbox retrieve failed: %s", resp.Error)
	}

	log.Printf("[GROUP_INBOX] Retrieved %d messages for group %s", len(resp.Messages), groupId)
	return resp.Messages, nil
}

// getGroupRelayInfo returns the relay peer ID and addresses.
// Uses the same relay as the 1:1 inbox.
func (n *Node) getGroupRelayInfo() (peer.ID, []ma.Multiaddr, error) {
	return n.getRelayInfo(nil)
}
