package node

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"strconv"
	"strings"

	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

const groupInboxSyntheticSinceCursorPrefix = "mknoon-since-ms:"

// groupInboxRequest is the JSON envelope sent to the relay server
// for group inbox operations.
type groupInboxRequest struct {
	Action                 string   `json:"action"`
	GroupId                string   `json:"groupId,omitempty"`
	From                   string   `json:"from,omitempty"`
	Message                string   `json:"message,omitempty"`
	RecipientPeerIds       []string `json:"recipientPeerIds,omitempty"`
	SinceTimestamp         int64    `json:"sinceTimestamp,omitempty"`
	Cursor                 string   `json:"cursor,omitempty"`
	Limit                  int      `json:"limit,omitempty"`
	GapId                  string   `json:"gapId,omitempty"`
	SourcePeerId           string   `json:"sourcePeerId,omitempty"`
	MissingAfterMessageId  string   `json:"missingAfterMessageId,omitempty"`
	MissingBeforeMessageId string   `json:"missingBeforeMessageId,omitempty"`
	ExpectedRangeHash      string   `json:"expectedRangeHash,omitempty"`
	ExpectedHeadMessageId  string   `json:"expectedHeadMessageId,omitempty"`
}

// groupInboxResponse is the JSON envelope received from the relay
// server for group inbox operations.
// NOTE: The relay uses "groupMessages" (not "messages") for group inbox.
type groupInboxResponse struct {
	Status        string                 `json:"status"`
	Error         string                 `json:"error,omitempty"`
	Messages      []InboxMessage         `json:"groupMessages,omitempty"`
	NextCursor    string                 `json:"nextCursor,omitempty"`
	HistoryGaps   []GroupInboxHistoryGap `json:"historyGaps,omitempty"`
	GroupId       string                 `json:"groupId,omitempty"`
	GapId         string                 `json:"gapId,omitempty"`
	SourcePeerId  string                 `json:"sourcePeerId,omitempty"`
	RangeHash     string                 `json:"rangeHash,omitempty"`
	HeadMessageId string                 `json:"headMessageId,omitempty"`
}

// GroupInboxHistoryGap is relay-provided continuity metadata for a cursor page.
type GroupInboxHistoryGap struct {
	GroupId                string   `json:"groupId"`
	GapId                  string   `json:"gapId"`
	MissingAfterMessageId  string   `json:"missingAfterMessageId"`
	MissingBeforeMessageId string   `json:"missingBeforeMessageId"`
	ExpectedRangeHash      string   `json:"expectedRangeHash"`
	ExpectedHeadMessageId  string   `json:"expectedHeadMessageId"`
	CandidateSourcePeerIds []string `json:"candidateSourcePeerIds"`
}

// GroupInboxCursorResult carries a cursor page plus any detected history gaps.
type GroupInboxCursorResult struct {
	Messages    []InboxMessage
	NextCursor  string
	HistoryGaps []GroupInboxHistoryGap
}

type GroupInboxStoreOptions struct {
	PreserveRecipientPeerIds bool
}

// GroupHistoryRepairRangeRequest describes a bounded request for encrypted
// replay envelopes that fill one explicit history gap.
type GroupHistoryRepairRangeRequest struct {
	GroupId                string `json:"groupId"`
	GapId                  string `json:"gapId"`
	SourcePeerId           string `json:"sourcePeerId"`
	MissingAfterMessageId  string `json:"missingAfterMessageId"`
	MissingBeforeMessageId string `json:"missingBeforeMessageId"`
	ExpectedRangeHash      string `json:"expectedRangeHash"`
	ExpectedHeadMessageId  string `json:"expectedHeadMessageId"`
	Limit                  int    `json:"limit,omitempty"`
}

// GroupHistoryRepairRangeResponse carries source-provided encrypted replay
// envelopes plus the range integrity values Flutter validates before replay.
type GroupHistoryRepairRangeResponse struct {
	GroupId       string         `json:"groupId"`
	GapId         string         `json:"gapId"`
	SourcePeerId  string         `json:"sourcePeerId"`
	RangeHash     string         `json:"rangeHash"`
	HeadMessageId string         `json:"headMessageId"`
	Messages      []InboxMessage `json:"messages"`
}

func (req GroupHistoryRepairRangeRequest) Validate() error {
	if strings.TrimSpace(req.GroupId) == "" {
		return fmt.Errorf("missing groupId")
	}
	if strings.TrimSpace(req.GapId) == "" {
		return fmt.Errorf("missing gapId")
	}
	if strings.TrimSpace(req.SourcePeerId) == "" {
		return fmt.Errorf("missing sourcePeerId")
	}
	if strings.TrimSpace(req.MissingAfterMessageId) == "" {
		return fmt.Errorf("missing missingAfterMessageId")
	}
	if strings.TrimSpace(req.MissingBeforeMessageId) == "" {
		return fmt.Errorf("missing missingBeforeMessageId")
	}
	if strings.TrimSpace(req.ExpectedRangeHash) == "" {
		return fmt.Errorf("missing expectedRangeHash")
	}
	if strings.TrimSpace(req.ExpectedHeadMessageId) == "" {
		return fmt.Errorf("missing expectedHeadMessageId")
	}
	return nil
}

func NormalizeGroupHistoryRepairRangeRequest(req GroupHistoryRepairRangeRequest) (GroupHistoryRepairRangeRequest, error) {
	req.GroupId = strings.TrimSpace(req.GroupId)
	req.GapId = strings.TrimSpace(req.GapId)
	req.SourcePeerId = strings.TrimSpace(req.SourcePeerId)
	req.MissingAfterMessageId = strings.TrimSpace(req.MissingAfterMessageId)
	req.MissingBeforeMessageId = strings.TrimSpace(req.MissingBeforeMessageId)
	req.ExpectedRangeHash = strings.TrimSpace(req.ExpectedRangeHash)
	req.ExpectedHeadMessageId = strings.TrimSpace(req.ExpectedHeadMessageId)
	if req.Limit <= 0 {
		req.Limit = 50
	}
	if err := req.Validate(); err != nil {
		return GroupHistoryRepairRangeRequest{}, err
	}
	return req, nil
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
	return n.GroupInboxStoreWithOptions(
		groupId,
		message,
		recipientPeerIds,
		pushTitle,
		pushBody,
		GroupInboxStoreOptions{},
	)
}

func (n *Node) GroupInboxStoreWithOptions(
	groupId,
	message string,
	recipientPeerIds []string,
	pushTitle,
	pushBody string,
	options GroupInboxStoreOptions,
) error {
	groupId = strings.TrimSpace(groupId)
	n.mu.RLock()
	h := n.host
	senderTransportPeerId := strings.TrimSpace(n.peerId)
	var config *GroupConfig
	if storedConfig := n.groupConfigs[groupId]; storedConfig != nil {
		config = cloneGroupConfig(storedConfig)
	}
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	if config != nil {
		if options.PreserveRecipientPeerIds {
			if _, err := validateGroupConfigIdentityUniqueness(config); err != nil {
				return fmt.Errorf("invalid group config for group %s: %w", groupId, err)
			}
			if len(normalizeGroupInboxRecipientPeerIds(recipientPeerIds)) == 0 {
				return fmt.Errorf("explicit group inbox recipients empty for group %s", groupId)
			}
		} else {
			if senderTransportPeerId == "" {
				return fmt.Errorf("missing sender transport peer id")
			}
			derivedRecipients, err := activeGroupInboxRecipientsForConfig(groupId, config, senderTransportPeerId)
			if err != nil {
				return err
			}
			recipientPeerIds = derivedRecipients
		}
	}

	return n.groupInboxStore(groupId, message, recipientPeerIds, pushTitle, pushBody)
}

func (n *Node) groupInboxStore(
	groupId,
	message string,
	recipientPeerIds []string,
	pushTitle,
	pushBody string,
) error {
	err := n.groupInboxStoreOnce(groupId, message, recipientPeerIds, pushTitle, pushBody)
	if err == nil || !isTransientGroupInboxRelayStreamError(err) {
		return err
	}

	log.Printf("[GROUP_INBOX] Store hit transient relay stream error, reconnecting relays before retry: %v", err)
	if recoverErr := n.recoverGroupInboxRelayStream(err); recoverErr != nil {
		log.Printf("[GROUP_INBOX] Relay reconnect after group inbox store stream error failed: %v", recoverErr)
		return err
	}

	return n.groupInboxStoreOnce(groupId, message, recipientPeerIds, pushTitle, pushBody)
}

func (n *Node) groupInboxStoreOnce(
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

func (n *Node) ActiveGroupInboxRecipients(groupId string, senderTransportPeerId string) ([]string, error) {
	groupId = strings.TrimSpace(groupId)
	senderTransportPeerId = strings.TrimSpace(senderTransportPeerId)
	if groupId == "" {
		return nil, fmt.Errorf("missing group id")
	}
	if senderTransportPeerId == "" {
		return nil, fmt.Errorf("missing sender transport peer id")
	}

	n.mu.RLock()
	config := cloneGroupConfig(n.groupConfigs[groupId])
	n.mu.RUnlock()
	if config == nil {
		return nil, fmt.Errorf("group not joined: %s", groupId)
	}

	return activeGroupInboxRecipientsForConfig(groupId, config, senderTransportPeerId)
}

func activeGroupInboxRecipientsForConfig(groupId string, config *GroupConfig, senderTransportPeerId string) ([]string, error) {
	if _, err := validateGroupConfigIdentityUniqueness(config); err != nil {
		return nil, fmt.Errorf("invalid group config for group %s: %w", groupId, err)
	}
	recipients, hasActiveRemote := deriveActiveGroupInboxRecipients(config, senderTransportPeerId)
	if len(recipients) == 0 && hasActiveRemote {
		return nil, fmt.Errorf("active group inbox recipients empty for group %s with active remote members", groupId)
	}
	return recipients, nil
}

func deriveActiveGroupInboxRecipients(config *GroupConfig, senderTransportPeerId string) ([]string, bool) {
	if config == nil {
		return nil, false
	}

	senderTransportPeerId = strings.TrimSpace(senderTransportPeerId)
	seen := make(map[string]struct{})
	recipients := make([]string, 0, len(config.Members))
	hasActiveRemote := false
	add := func(peerId string) {
		peerId = strings.TrimSpace(peerId)
		if peerId == "" {
			hasActiveRemote = true
			return
		}
		if peerId == senderTransportPeerId {
			return
		}
		hasActiveRemote = true
		if _, exists := seen[peerId]; exists {
			return
		}
		seen[peerId] = struct{}{}
		recipients = append(recipients, peerId)
	}

	for _, member := range normalizeGroupConfigMembers(config.Members) {
		if len(member.Devices) == 0 {
			add(member.PeerId)
			continue
		}
		for _, device := range member.Devices {
			if groupMemberDeviceIsActive(device) {
				add(device.TransportPeerId)
			}
		}
	}
	return recipients, hasActiveRemote
}

func buildGroupInboxStoreRequest(
	groupId,
	from,
	message string,
	recipientPeerIds []string,
	_,
	_ string,
) groupInboxRequest {
	return groupInboxRequest{
		Action:           "group_store",
		GroupId:          groupId,
		From:             from,
		Message:          message,
		RecipientPeerIds: normalizeGroupInboxRecipientPeerIds(recipientPeerIds),
	}
}

func normalizeGroupInboxRecipientPeerIds(recipientPeerIds []string) []string {
	if len(recipientPeerIds) == 0 {
		return nil
	}

	normalized := make([]string, 0, len(recipientPeerIds))
	seen := make(map[string]struct{}, len(recipientPeerIds))
	for _, recipientPeerId := range recipientPeerIds {
		trimmed := strings.TrimSpace(recipientPeerId)
		if trimmed == "" {
			continue
		}
		if _, exists := seen[trimmed]; exists {
			continue
		}
		seen[trimmed] = struct{}{}
		normalized = append(normalized, trimmed)
	}
	if len(normalized) == 0 {
		return nil
	}
	return normalized
}

// GroupInboxRetrieve retrieves missed group messages from the relay's group inbox
// since the given timestamp (unix milliseconds). Returns messages in chronological order.
// Tries each configured relay in order until one succeeds.
func (n *Node) GroupInboxRetrieve(groupId string, sinceTimestamp int64) ([]InboxMessage, error) {
	result, err := n.groupInboxRetrieve(groupInboxRequest{
		Action:         "group_retrieve",
		GroupId:        groupId,
		SinceTimestamp: inclusiveGroupInboxSinceTimestamp(sinceTimestamp),
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
	result, err := n.GroupInboxRetrieveWithCursorResult(groupId, cursor, limit)
	if err != nil {
		return nil, "", err
	}
	return result.Messages, result.NextCursor, nil
}

// GroupInboxRetrieveWithCursorResult retrieves a cursor page and preserves
// relay-provided history-gap metadata for Dart repair orchestration.
func (n *Node) GroupInboxRetrieveWithCursorResult(groupId, cursor string, limit int) (*GroupInboxCursorResult, error) {
	if limit <= 0 {
		limit = 50
	}

	if sinceTimestamp, ok, err := parseGroupInboxSyntheticSinceCursor(cursor); ok || err != nil {
		if err != nil {
			return nil, err
		}
		result, err := n.groupInboxRetrieve(groupInboxRequest{
			Action:         "group_retrieve",
			GroupId:        groupId,
			SinceTimestamp: inclusiveGroupInboxSinceTimestamp(sinceTimestamp),
			Limit:          limit,
		})
		if err != nil {
			return nil, err
		}
		return &GroupInboxCursorResult{
			Messages:    result.Messages,
			NextCursor:  result.NextCursor,
			HistoryGaps: result.HistoryGaps,
		}, nil
	}

	result, err := n.groupInboxRetrieve(groupInboxRequest{
		Action:  "group_retrieve_cursor",
		GroupId: groupId,
		Cursor:  cursor,
		Limit:   limit,
	})
	if err != nil {
		return nil, err
	}
	return &GroupInboxCursorResult{
		Messages:    result.Messages,
		NextCursor:  result.NextCursor,
		HistoryGaps: result.HistoryGaps,
	}, nil
}

func parseGroupInboxSyntheticSinceCursor(cursor string) (int64, bool, error) {
	if !strings.HasPrefix(cursor, groupInboxSyntheticSinceCursorPrefix) {
		return 0, false, nil
	}
	raw := strings.TrimPrefix(cursor, groupInboxSyntheticSinceCursorPrefix)
	sinceTimestamp, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || sinceTimestamp <= 0 {
		return 0, true, fmt.Errorf("invalid synthetic group inbox cursor")
	}
	return sinceTimestamp, true, nil
}

func inclusiveGroupInboxSinceTimestamp(sinceTimestamp int64) int64 {
	if sinceTimestamp <= 0 {
		return sinceTimestamp
	}
	return sinceTimestamp - 1
}

// GroupHistoryRepairRange requests a bounded encrypted replay-envelope range
// from the configured relay inbox repair action.
func (n *Node) GroupHistoryRepairRange(req GroupHistoryRepairRangeRequest) (*GroupHistoryRepairRangeResponse, error) {
	normalized, err := NormalizeGroupHistoryRepairRangeRequest(req)
	if err != nil {
		return nil, err
	}

	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	result, err := n.groupInboxRetrieve(groupInboxRequest{
		Action:                 "group_history_repair_range",
		GroupId:                normalized.GroupId,
		GapId:                  normalized.GapId,
		SourcePeerId:           normalized.SourcePeerId,
		MissingAfterMessageId:  normalized.MissingAfterMessageId,
		MissingBeforeMessageId: normalized.MissingBeforeMessageId,
		ExpectedRangeHash:      normalized.ExpectedRangeHash,
		ExpectedHeadMessageId:  normalized.ExpectedHeadMessageId,
		Limit:                  normalized.Limit,
	})
	if err != nil {
		return nil, err
	}

	response := &GroupHistoryRepairRangeResponse{
		GroupId:       result.GroupId,
		GapId:         result.GapId,
		SourcePeerId:  result.SourcePeerId,
		RangeHash:     result.RangeHash,
		HeadMessageId: result.HeadMessageId,
		Messages:      result.Messages,
	}
	if response.GroupId == "" {
		response.GroupId = normalized.GroupId
	}
	if response.GapId == "" {
		response.GapId = normalized.GapId
	}
	if response.SourcePeerId == "" {
		response.SourcePeerId = normalized.SourcePeerId
	}
	return response, nil
}

func (n *Node) groupInboxRetrieve(req groupInboxRequest) (*groupInboxResponse, error) {
	result, err := n.groupInboxRetrieveOnce(req)
	if err == nil || !isTransientGroupInboxRelayStreamError(err) {
		return result, err
	}

	log.Printf("[GROUP_INBOX] Retrieve %s hit transient relay stream error, reconnecting relays before retry: %v", req.Action, err)
	if recoverErr := n.recoverGroupInboxRelayStream(err); recoverErr != nil {
		log.Printf("[GROUP_INBOX] Relay reconnect after group inbox stream error failed: %v", recoverErr)
		return nil, err
	}

	return n.groupInboxRetrieveOnce(req)
}

func (n *Node) recoverGroupInboxRelayStream(err error) error {
	if n.groupInboxRecoverHook != nil {
		return n.groupInboxRecoverHook(err)
	}
	_, recoverErr := n.ReconnectRelays()
	return recoverErr
}

func isTransientGroupInboxRelayStreamError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, io.EOF) || errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	msg := strings.ToLower(err.Error())
	if strings.Contains(msg, "group inbox store failed") || strings.Contains(msg, "group inbox retrieve failed") {
		return false
	}
	if strings.Contains(msg, "connect to relay") ||
		strings.Contains(msg, "open inbox stream") ||
		strings.Contains(msg, "failed to dial") ||
		strings.Contains(msg, "no addresses") {
		return true
	}
	if strings.Contains(msg, "read response") || strings.Contains(msg, "write request") {
		return strings.Contains(msg, "eof") ||
			strings.Contains(msg, "reset") ||
			strings.Contains(msg, "timeout") ||
			strings.Contains(msg, "deadline")
	}
	return strings.Contains(msg, "reset") ||
		strings.Contains(msg, "timeout") ||
		strings.Contains(msg, "deadline")
}

func (n *Node) groupInboxRetrieveOnce(req groupInboxRequest) (*groupInboxResponse, error) {
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
