package node

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// InboxMessage represents a message stored in the offline inbox.
type InboxMessage struct {
	From      string `json:"from"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

type inboxRequest struct {
	Action   string `json:"action"`
	To       string `json:"to,omitempty"`
	From     string `json:"from,omitempty"`
	Message  string `json:"message,omitempty"`
	Limit    int    `json:"limit,omitempty"`
	Token    string `json:"token,omitempty"`
	Platform string `json:"platform,omitempty"`
}

type inboxResponse struct {
	Status   string         `json:"status"`
	Error    string         `json:"error,omitempty"`
	Messages []InboxMessage `json:"messages,omitempty"`
}

// InboxStore stores a message in the offline inbox for a peer.
func (n *Node) InboxStore(toPeerId string, message string) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	relayPeer, relayAddrs, err := n.getRelayInfo(nil)
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(n.ctx, InboxTimeout)
	defer cancel()

	// Ensure connected to relay
	if err := h.Connect(ctx, peer.AddrInfo{ID: relayPeer, Addrs: relayAddrs}); err != nil {
		return fmt.Errorf("connect to relay: %w", err)
	}

	s, err := h.NewStream(ctx, relayPeer, InboxProtocol)
	if err != nil {
		return fmt.Errorf("open inbox stream: %w", err)
	}
	defer s.Close()

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
		return fmt.Errorf("inbox store failed: %s", resp.Error)
	}

	log.Printf("[INBOX] Stored message for %s", toPeerId[:min(20, len(toPeerId))])
	return nil
}

// InboxRetrieve retrieves pending messages from the offline inbox.
func (n *Node) InboxRetrieve() ([]InboxMessage, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	relayPeer, relayAddrs, err := n.getRelayInfo(nil)
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
		return nil, nil
	}

	if resp.Status != "OK" {
		return nil, fmt.Errorf("inbox retrieve failed: %s", resp.Error)
	}

	log.Printf("[INBOX] Retrieved %d messages", len(resp.Messages))
	return resp.Messages, nil
}

// InboxRegisterToken registers an FCM push token with the relay.
func (n *Node) InboxRegisterToken(token string, platform string) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	relayPeer, relayAddrs, err := n.getRelayInfo(nil)
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

	log.Printf("[INBOX] Push token registered (%s)", platform)
	return nil
}

// getRelayInfo returns the relay peer ID and addresses.
func (n *Node) getRelayInfo(serverAddresses []string) (peer.ID, []ma.Multiaddr, error) {
	addrs := serverAddresses
	if len(addrs) == 0 {
		addrs = n.relayAddresses
	}
	if len(addrs) == 0 {
		addrs = []string{DefaultRelayAddress}
	}

	maddr, err := ma.NewMultiaddr(addrs[0])
	if err != nil {
		return "", nil, fmt.Errorf("parse relay address: %w", err)
	}

	addrInfo, err := peer.AddrInfoFromP2pAddr(maddr)
	if err != nil {
		return "", nil, fmt.Errorf("parse relay addr info: %w", err)
	}

	return addrInfo.ID, addrInfo.Addrs, nil
}
