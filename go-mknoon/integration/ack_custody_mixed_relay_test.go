//go:build integration

package integration_test

import (
	"encoding/json"
	"fmt"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/mknoon/go-mknoon/node"
)

type ackCustodyMatrixRequest struct {
	Action          string   `json:"action"`
	To              string   `json:"to,omitempty"`
	From            string   `json:"from,omitempty"`
	Message         string   `json:"message,omitempty"`
	Limit           int      `json:"limit,omitempty"`
	EntryIDs        []string `json:"entryIds,omitempty"`
	CustodyKind     string   `json:"custodyKind,omitempty"`
	CustodyContract string   `json:"custodyContract,omitempty"`
}

type ackCustodyMatrixMessage struct {
	ID        string `json:"id"`
	From      string `json:"from"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

type ackCustodyMatrixResponse struct {
	Status          string                    `json:"status"`
	Error           string                    `json:"error,omitempty"`
	ErrorCode       string                    `json:"errorCode,omitempty"`
	StoreStatus     string                    `json:"storeStatus,omitempty"`
	CustodyContract string                    `json:"custodyContract,omitempty"`
	Messages        []ackCustodyMatrixMessage `json:"messages,omitempty"`
	HasMore         bool                      `json:"hasMore,omitempty"`
	Acked           int                       `json:"acked,omitempty"`
}

type ackCustodyMatrixState struct {
	mu        sync.Mutex
	upgraded  bool
	admission bool
	sequence  int64
	legacy    map[string][]ackCustodyMatrixMessage
	protected map[string][]ackCustodyMatrixMessage
	actions   []string
}

func newAckCustodyMatrixState(upgraded bool) *ackCustodyMatrixState {
	return &ackCustodyMatrixState{
		upgraded:  upgraded,
		admission: true,
		legacy:    make(map[string][]ackCustodyMatrixMessage),
		protected: make(map[string][]ackCustodyMatrixMessage),
	}
}

func startAckCustodyMatrixRelay(
	t *testing.T,
	upgraded bool,
) (*localRelayServer, *ackCustodyMatrixState) {
	t.Helper()
	relay := newLocalRelayServer(t, newLocalRelaySharedState())
	relay.start()
	state := newAckCustodyMatrixState(upgraded)
	relay.host.SetStreamHandler(node.InboxProtocol, state.handleStream)
	t.Cleanup(func() { relay.stop() })
	return relay, state
}

func (s *ackCustodyMatrixState) handleStream(stream network.Stream) {
	defer stream.Close()
	raw, err := readLocalRelayFrame(stream)
	if err != nil {
		return
	}
	var req ackCustodyMatrixRequest
	if json.Unmarshal(raw, &req) != nil {
		_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{Status: "ERROR", Error: "invalid JSON"})
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.actions = append(s.actions, req.Action)
	remotePeer := stream.Conn().RemotePeer().String()

	switch req.Action {
	case "store":
		s.sequence++
		entry := ackCustodyMatrixMessage{
			ID:        fmt.Sprintf("legacy-%06d", s.sequence),
			From:      req.From,
			Message:   req.Message,
			Timestamp: time.Now().UnixMilli() + s.sequence,
		}
		s.legacy[req.To] = append(s.legacy[req.To], entry)
		_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{Status: "OK", StoreStatus: "stored"})
	case "store_custody_v1":
		if !s.validStrictRequest(req) ||
			(req.CustodyKind != node.CustodyKindDirectTextV108 &&
				req.CustodyKind != node.CustodyKindDirectReactionV109) {
			s.writeUnsupported(stream, req.Action)
			return
		}
		if !s.admission {
			_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{
				Status: "ERROR", ErrorCode: "CUSTODY_ADMISSION_DISABLED",
			})
			return
		}
		s.sequence++
		entry := ackCustodyMatrixMessage{
			ID:        fmt.Sprintf("protected-%06d", s.sequence),
			From:      req.From,
			Message:   req.Message,
			Timestamp: time.Now().UnixMilli() + s.sequence,
		}
		s.protected[req.To] = append(s.protected[req.To], entry)
		// Compatibility shadow: same ID/sender/bytes/timestamp in the legacy lane.
		s.legacy[req.To] = append(s.legacy[req.To], entry)
		_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{
			Status:          "OK",
			StoreStatus:     "stored",
			CustodyContract: node.AckOrExpiryCustodyContract,
		})
	case "retrieve":
		messages, hasMore := takeAckCustodyMatrixPage(s.legacy[remotePeer], req.Limit)
		if len(messages) == 0 {
			_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{Status: "NO_MESSAGES"})
			return
		}
		s.legacy[remotePeer] = append([]ackCustodyMatrixMessage(nil), s.legacy[remotePeer][len(messages):]...)
		_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{
			Status: "OK", Messages: messages, HasMore: hasMore,
		})
	case "retrieve_pending":
		messages, hasMore := takeAckCustodyMatrixPage(s.legacy[remotePeer], req.Limit)
		if len(messages) == 0 {
			_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{Status: "NO_MESSAGES"})
			return
		}
		_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{
			Status: "OK", Messages: messages, HasMore: hasMore,
		})
	case "retrieve_custody_pending_v1":
		if !s.validStrictRequest(req) {
			s.writeUnsupported(stream, req.Action)
			return
		}
		logical, identityOK := mergeAckCustodyMatrixMessages(
			append(append([]ackCustodyMatrixMessage(nil), s.protected[remotePeer]...), s.legacy[remotePeer]...),
		)
		if !identityOK {
			_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{
				Status: "ERROR", ErrorCode: "CUSTODY_IDENTITY_CONFLICT",
			})
			return
		}
		messages, hasMore := takeAckCustodyMatrixPage(logical, req.Limit)
		if len(messages) == 0 {
			_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{
				Status: "NO_MESSAGES", CustodyContract: node.AckOrExpiryCustodyContract,
			})
			return
		}
		_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{
			Status:          "OK",
			CustodyContract: node.AckOrExpiryCustodyContract,
			Messages:        messages,
			HasMore:         hasMore,
		})
	case "ack":
		remaining, removed := removeAckCustodyMatrixIDs(s.legacy[remotePeer], req.EntryIDs)
		s.legacy[remotePeer] = remaining
		_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{Status: "OK", Acked: removed})
	case "ack_custody_v1":
		if !s.validStrictRequest(req) {
			s.writeUnsupported(stream, req.Action)
			return
		}
		legacyRemaining, legacyRemovedIDs := removeAckCustodyMatrixIDsSet(s.legacy[remotePeer], req.EntryIDs)
		protectedRemaining, protectedRemovedIDs := removeAckCustodyMatrixIDsSet(s.protected[remotePeer], req.EntryIDs)
		s.legacy[remotePeer] = legacyRemaining
		s.protected[remotePeer] = protectedRemaining
		for id := range protectedRemovedIDs {
			legacyRemovedIDs[id] = struct{}{}
		}
		_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{
			Status:          "OK",
			CustodyContract: node.AckOrExpiryCustodyContract,
			Acked:           len(legacyRemovedIDs),
		})
	default:
		s.writeUnsupported(stream, req.Action)
	}
}

func (s *ackCustodyMatrixState) validStrictRequest(req ackCustodyMatrixRequest) bool {
	return s.upgraded && req.CustodyContract == node.AckOrExpiryCustodyContract
}

func (s *ackCustodyMatrixState) writeUnsupported(stream network.Stream, action string) {
	_ = writeAckCustodyMatrixResponse(stream, ackCustodyMatrixResponse{
		Status: "ERROR",
		Error:  "Unknown action: " + action,
	})
}

func (s *ackCustodyMatrixState) snapshotActions() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	actions := make([]string, len(s.actions))
	copy(actions, s.actions)
	return actions
}

func (s *ackCustodyMatrixState) laneSizes(peerID string) (legacy int, protected int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.legacy[peerID]), len(s.protected[peerID])
}

func (s *ackCustodyMatrixState) setAdmission(enabled bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.admission = enabled
}

func writeAckCustodyMatrixResponse(stream network.Stream, response ackCustodyMatrixResponse) error {
	raw, err := json.Marshal(response)
	if err != nil {
		return err
	}
	return writeLocalRelayFrame(stream, raw)
}

func takeAckCustodyMatrixPage(
	messages []ackCustodyMatrixMessage,
	limit int,
) ([]ackCustodyMatrixMessage, bool) {
	if limit <= 0 {
		limit = 50
	}
	limit = min(limit, len(messages))
	return append([]ackCustodyMatrixMessage(nil), messages[:limit]...), len(messages) > limit
}

func mergeAckCustodyMatrixMessages(
	messages []ackCustodyMatrixMessage,
) ([]ackCustodyMatrixMessage, bool) {
	byID := make(map[string]ackCustodyMatrixMessage, len(messages))
	for _, message := range messages {
		if existing, ok := byID[message.ID]; ok {
			if existing.From != message.From || existing.Message != message.Message {
				return nil, false
			}
			continue
		}
		byID[message.ID] = message
	}
	logical := make([]ackCustodyMatrixMessage, 0, len(byID))
	for _, message := range byID {
		logical = append(logical, message)
	}
	sort.Slice(logical, func(i, j int) bool {
		if logical[i].Timestamp == logical[j].Timestamp {
			return logical[i].ID < logical[j].ID
		}
		return logical[i].Timestamp < logical[j].Timestamp
	})
	return logical, true
}

func removeAckCustodyMatrixIDs(
	messages []ackCustodyMatrixMessage,
	entryIDs []string,
) ([]ackCustodyMatrixMessage, int) {
	remaining, removed := removeAckCustodyMatrixIDsSet(messages, entryIDs)
	return remaining, len(removed)
}

func removeAckCustodyMatrixIDsSet(
	messages []ackCustodyMatrixMessage,
	entryIDs []string,
) ([]ackCustodyMatrixMessage, map[string]struct{}) {
	requested := make(map[string]struct{}, len(entryIDs))
	for _, entryID := range entryIDs {
		if entryID != "" {
			requested[entryID] = struct{}{}
		}
	}
	remaining := make([]ackCustodyMatrixMessage, 0, len(messages))
	removed := make(map[string]struct{})
	for _, message := range messages {
		if _, ok := requested[message.ID]; ok {
			removed[message.ID] = struct{}{}
			continue
		}
		remaining = append(remaining, message)
	}
	return remaining, removed
}

func TestAckCustodyMixedVersionMatrix(t *testing.T) {
	t.Run("old sender and receiver remain compatible with upgraded handler", func(t *testing.T) {
		relay, _ := startAckCustodyMatrixRelay(t, true)
		sender, _ := startNodeWithRelays(t, []string{relay.addr()}, nil, nil)
		receiver, receiverID := startNodeWithRelays(t, []string{relay.addr()}, nil, nil)

		if err := sender.InboxStore(receiverID, "legacy-envelope", 1000); err != nil {
			t.Fatalf("legacy InboxStore(): %v", err)
		}
		messages, err := receiver.InboxRetrieve()
		if err != nil {
			t.Fatalf("legacy InboxRetrieve(): %v", err)
		}
		if len(messages) != 1 || messages[0].Message != "legacy-envelope" {
			t.Fatalf("legacy messages = %#v", messages)
		}
	})

	t.Run("new sender never legacy-stores on old-only relay", func(t *testing.T) {
		oldRelay, oldState := startAckCustodyMatrixRelay(t, false)
		sender, _ := startNodeWithRelays(t, []string{oldRelay.addr()}, nil, nil)
		_, err := sender.InboxStoreAckCustodyDetailedWithWakeToken(
			"recipient", "protected-envelope", 1000, "", node.CustodyKindDirectTextV108,
		)
		if err == nil {
			t.Fatal("old-only relay unexpectedly returned protected proof")
		}
		for _, action := range oldState.snapshotActions() {
			if action == "store" {
				t.Fatalf("strict sender legacy-fell back: %v", oldState.snapshotActions())
			}
		}
	})

	t.Run("old-first store selects upgraded relay and destructive shadow leaves protected row", func(t *testing.T) {
		oldRelay, _ := startAckCustodyMatrixRelay(t, false)
		newRelay, newState := startAckCustodyMatrixRelay(t, true)
		sender, _ := startNodeWithRelays(t, []string{oldRelay.addr(), newRelay.addr()}, nil, nil)
		receiver, receiverID := startNodeWithRelays(t, []string{newRelay.addr()}, nil, nil)

		outcome, err := sender.InboxStoreAckCustodyDetailedWithWakeToken(
			receiverID, "shadowed-protected", 1000, "", node.CustodyKindDirectReactionV109,
		)
		if err != nil || outcome.CustodyContract != node.AckOrExpiryCustodyContract {
			t.Fatalf("strict store outcome=%#v err=%v", outcome, err)
		}
		legacySize, protectedSize := newState.laneSizes(receiverID)
		if legacySize != 1 || protectedSize != 1 {
			t.Fatalf("lane sizes legacy=%d protected=%d", legacySize, protectedSize)
		}

		legacyMessages, err := receiver.InboxRetrieve()
		if err != nil || len(legacyMessages) != 1 {
			t.Fatalf("old destructive retrieve messages=%#v err=%v", legacyMessages, err)
		}
		legacySize, protectedSize = newState.laneSizes(receiverID)
		if legacySize != 0 || protectedSize != 1 {
			t.Fatalf("post-legacy lane sizes legacy=%d protected=%d", legacySize, protectedSize)
		}

		protectedPage, err := receiver.InboxRetrieveAckCustodyPendingWithTimeout(1000)
		if err != nil || len(protectedPage.Messages) != 1 ||
			protectedPage.Messages[0].ID != legacyMessages[0].ID {
			t.Fatalf("protected redelivery page=%#v err=%v", protectedPage, err)
		}
		if acked, err := receiver.InboxAckCustody([]string{protectedPage.Messages[0].ID}, 1000); err != nil || acked != 1 {
			t.Fatalf("protected ACK acked=%d err=%v", acked, err)
		}
	})

	t.Run("new empty plus old row scans and ACKs every relay", func(t *testing.T) {
		newRelay, newState := startAckCustodyMatrixRelay(t, true)
		oldRelay, oldState := startAckCustodyMatrixRelay(t, false)
		sender, _ := startNodeWithRelays(t, []string{oldRelay.addr()}, nil, nil)
		receiver, receiverID := startNodeWithRelays(t, []string{newRelay.addr(), oldRelay.addr()}, nil, nil)

		if err := sender.InboxStore(receiverID, "old-disjoint-row", 1000); err != nil {
			t.Fatalf("seed legacy row: %v", err)
		}
		page, err := receiver.InboxRetrieveAckCustodyPendingWithTimeout(1000)
		if err != nil || len(page.Messages) != 1 || page.Messages[0].Message != "old-disjoint-row" {
			t.Fatalf("mixed retrieve page=%#v err=%v", page, err)
		}
		if acked, err := receiver.InboxAckCustody([]string{page.Messages[0].ID}, 1000); err != nil || acked != 1 {
			t.Fatalf("mixed ACK acked=%d err=%v", acked, err)
		}
		if !containsAckCustodyAction(newState.snapshotActions(), "ack_custody_v1") ||
			containsAckCustodyAction(newState.snapshotActions(), "ack") {
			t.Fatalf("new relay actions = %v", newState.snapshotActions())
		}
		if !containsAckCustodyAction(oldState.snapshotActions(), "ack_custody_v1") ||
			!containsAckCustodyAction(oldState.snapshotActions(), "ack") {
			t.Fatalf("old relay actions = %v", oldState.snapshotActions())
		}
	})

	t.Run("protected and legacy disjoint rows form one union", func(t *testing.T) {
		newRelay, _ := startAckCustodyMatrixRelay(t, true)
		oldRelay, _ := startAckCustodyMatrixRelay(t, false)
		strictSender, _ := startNodeWithRelays(t, []string{newRelay.addr()}, nil, nil)
		legacySender, _ := startNodeWithRelays(t, []string{oldRelay.addr()}, nil, nil)
		receiver, receiverID := startNodeWithRelays(t, []string{newRelay.addr(), oldRelay.addr()}, nil, nil)

		if _, err := strictSender.InboxStoreAckCustodyDetailedWithWakeToken(
			receiverID, "protected-union-row", 1000, "", node.CustodyKindDirectTextV108,
		); err != nil {
			t.Fatalf("seed protected row: %v", err)
		}
		if err := legacySender.InboxStore(receiverID, "legacy-union-row", 1000); err != nil {
			t.Fatalf("seed legacy row: %v", err)
		}
		page, err := receiver.InboxRetrieveAckCustodyPendingWithTimeout(1000)
		if err != nil || len(page.Messages) != 2 {
			t.Fatalf("union page=%#v err=%v", page, err)
		}
		seen := map[string]bool{}
		ids := make([]string, 0, len(page.Messages))
		for _, message := range page.Messages {
			seen[message.Message] = true
			ids = append(ids, message.ID)
		}
		if !seen["protected-union-row"] || !seen["legacy-union-row"] {
			t.Fatalf("union messages = %#v", page.Messages)
		}
		if acked, err := receiver.InboxAckCustody(ids, 1000); err != nil || acked != 2 {
			t.Fatalf("union ACK acked=%d err=%v", acked, err)
		}
	})

	t.Run("admission off still drains and re-enable accepts", func(t *testing.T) {
		relay, state := startAckCustodyMatrixRelay(t, true)
		sender, _ := startNodeWithRelays(t, []string{relay.addr()}, nil, nil)
		receiver, receiverID := startNodeWithRelays(t, []string{relay.addr()}, nil, nil)

		if _, err := sender.InboxStoreAckCustodyDetailedWithWakeToken(
			receiverID, "before-disable", 1000, "", node.CustodyKindDirectTextV108,
		); err != nil {
			t.Fatalf("seed before disable: %v", err)
		}
		state.setAdmission(false)
		if _, err := sender.InboxStoreAckCustodyDetailedWithWakeToken(
			receiverID, "while-disabled", 1000, "", node.CustodyKindDirectTextV108,
		); err == nil {
			t.Fatal("disabled admission unexpectedly accepted a store")
		}
		page, err := receiver.InboxRetrieveAckCustodyPendingWithTimeout(1000)
		if err != nil || len(page.Messages) != 1 || page.Messages[0].Message != "before-disable" {
			t.Fatalf("flag-off drain page=%#v err=%v", page, err)
		}
		if acked, err := receiver.InboxAckCustody([]string{page.Messages[0].ID}, 1000); err != nil || acked != 1 {
			t.Fatalf("flag-off ACK acked=%d err=%v", acked, err)
		}

		state.setAdmission(true)
		if outcome, err := sender.InboxStoreAckCustodyDetailedWithWakeToken(
			receiverID, "after-re-enable", 1000, "", node.CustodyKindDirectTextV108,
		); err != nil || outcome.CustodyContract != node.AckOrExpiryCustodyContract {
			t.Fatalf("re-enabled outcome=%#v err=%v", outcome, err)
		}
	})
}

func containsAckCustodyAction(actions []string, want string) bool {
	for _, action := range actions {
		if action == want {
			return true
		}
	}
	return false
}
