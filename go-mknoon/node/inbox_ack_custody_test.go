package node

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	ma "github.com/multiformats/go-multiaddr"
)

func TestTC363GroupProtectedCustodyKinds(t *testing.T) {
	t.Parallel()

	for _, kind := range []string{
		CustodyKindGroupBootstrapV1,
		CustodyKindGroupAuthorityV1,
	} {
		if !isSupportedInboxCustodyKind(kind) {
			t.Fatalf("group custody kind %q is not registered", kind)
		}
	}
	for _, kind := range []string{
		"group_message",
		"group_reaction_v1",
		"group_bootstrap_v2",
	} {
		if isSupportedInboxCustodyKind(kind) {
			t.Fatalf("unsupported group/content kind %q was admitted", kind)
		}
	}
}

type ackCustodyTestRelay struct {
	host host.Host

	mu      sync.Mutex
	actions []inboxRequest
	reply   func(inboxRequest) string
}

func startAckCustodyTestRelay(t *testing.T, reply func(inboxRequest) string) *ackCustodyTestRelay {
	t.Helper()

	h, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("libp2p.New(): %v", err)
	}
	relay := &ackCustodyTestRelay{host: h, reply: reply}
	h.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		defer stream.Close()
		raw, readErr := readFrame(stream)
		if readErr != nil {
			return
		}
		var req inboxRequest
		if json.Unmarshal(raw, &req) != nil {
			return
		}
		relay.mu.Lock()
		relay.actions = append(relay.actions, req)
		relay.mu.Unlock()
		response := relay.reply(req)
		if response != "" {
			_ = writeFrame(stream, []byte(response))
		}
	})
	t.Cleanup(func() {
		if err := h.Close(); err != nil {
			t.Errorf("relay.Close(): %v", err)
		}
	})
	return relay
}

func (r *ackCustodyTestRelay) addr(t *testing.T) string {
	t.Helper()
	peerComponent, err := ma.NewMultiaddr(fmt.Sprintf("/p2p/%s", r.host.ID()))
	if err != nil {
		t.Fatalf("peer multiaddr: %v", err)
	}
	return r.host.Addrs()[0].Encapsulate(peerComponent).String()
}

func (r *ackCustodyTestRelay) snapshotActions() []inboxRequest {
	r.mu.Lock()
	defer r.mu.Unlock()
	actions := make([]inboxRequest, len(r.actions))
	copy(actions, r.actions)
	return actions
}

func configureAckCustodyTestRelays(t *testing.T, n *Node, relays ...*ackCustodyTestRelay) {
	t.Helper()
	addresses := make([]string, 0, len(relays))
	for _, relay := range relays {
		addresses = append(addresses, relay.addr(t))
	}
	n.mu.Lock()
	n.relayAddresses = addresses
	n.mu.Unlock()
}

func TestInboxAckCustodyMixedRelayAndProofContract(t *testing.T) {
	t.Run("strict response parser", func(t *testing.T) {
		for _, status := range []string{"stored", "duplicate"} {
			outcome, err := parseInboxAckCustodyStoreResponse([]byte(fmt.Sprintf(
				`{"status":"OK","storeStatus":%q,"custodyContract":"ack_or_expiry_v1","expiresAtMs":99}`,
				status,
			)))
			if err != nil {
				t.Fatalf("parse exact %s receipt: %v", status, err)
			}
			if outcome.StoreStatus != status || outcome.CustodyContract != AckOrExpiryCustodyContract {
				t.Fatalf("exact receipt = %#v", outcome)
			}
		}

		invalidReceipts := []string{
			`{"status":"OK"}`,
			`{"status":"OK","storeStatus":"stored"}`,
			`{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v2"}`,
			`{"status":"OK","storeStatus":"accepted","custodyContract":"ack_or_expiry_v1"}`,
			`not-json`,
		}
		for _, raw := range invalidReceipts {
			if _, err := parseInboxAckCustodyStoreResponse([]byte(raw)); err == nil {
				t.Fatalf("parseInboxAckCustodyStoreResponse(%q) unexpectedly accepted", raw)
			}
		}

		outcome, err := parseInboxAckCustodyStoreResponse([]byte(
			`{"status":"ERROR","storeStatus":"rejected_full","errorCode":"INBOX_FULL"}`,
		))
		if !errors.Is(err, ErrInboxFull) || outcome.StoreStatus != "rejected_full" {
			t.Fatalf("full outcome = %#v, err=%v", outcome, err)
		}
		for _, malformedFull := range []string{
			`{"status":"ERROR","storeStatus":"rejected_full","error":"INBOX_FULL"}`,
			`{"status":"ERROR","errorCode":"INBOX_FULL"}`,
			`{"status":"ERROR","storeStatus":"rejected_full","errorCode":"INBOX_CAPACITY"}`,
		} {
			if _, err := parseInboxAckCustodyStoreResponse([]byte(malformedFull)); !errors.Is(err, ErrInboxCustodyInvalidReceipt) {
				t.Fatalf("malformed full %q error = %v", malformedFull, err)
			}
		}
		if _, err := parseInboxAckCustodyStoreResponse([]byte(
			`{"status":"ERROR","errorCode":"CUSTODY_IDENTITY_CONFLICT"}`,
		)); !errors.Is(err, ErrInboxCustodyIdentityConflict) {
			t.Fatalf("identity conflict error = %v", err)
		}
		if _, err := parseInboxAckCustodyStoreResponse([]byte(
			`{"status":"ERROR","errorCode":"CUSTODY_INELIGIBLE"}`,
		)); !errors.Is(err, ErrInboxCustodyIneligible) {
			t.Fatalf("ineligible error = %v", err)
		}
	})

	t.Run("old first upgraded second never falls back to legacy store", func(t *testing.T) {
		oldRelay := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			if req.Action == "store" {
				t.Fatal("strict custody store fell back to legacy store")
			}
			return fmt.Sprintf(`{"status":"ERROR","error":"Unknown action: %s"}`, req.Action)
		})
		newRelay := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			if req.Action != "store_custody_v1" {
				t.Fatalf("new relay action = %q", req.Action)
			}
			if req.CustodyKind != CustodyKindDirectTextV108 {
				t.Fatalf("custodyKind = %q", req.CustodyKind)
			}
			return `{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v1"}`
		})

		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, oldRelay, newRelay)
		outcome, err := n.InboxStoreAckCustodyDetailedWithWakeToken(
			generatePeerIDStr(t), "envelope", 1000, "wake-token", CustodyKindDirectTextV108,
		)
		if err != nil {
			t.Fatalf("InboxStoreAckCustodyDetailedWithWakeToken(): %v", err)
		}
		if outcome.CustodyContract != AckOrExpiryCustodyContract {
			t.Fatalf("outcome = %#v", outcome)
		}
		if actions := oldRelay.snapshotActions(); len(actions) != 1 || actions[0].Action != "store_custody_v1" {
			t.Fatalf("old relay actions = %#v", actions)
		}
		if oldRelay.snapshotActions()[0].CustodyContract != AckOrExpiryCustodyContract {
			t.Fatalf("strict request contract = %q", oldRelay.snapshotActions()[0].CustodyContract)
		}
	})

	t.Run("identity conflict is terminal", func(t *testing.T) {
		conflictRelay := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return `{"status":"ERROR","errorCode":"CUSTODY_IDENTITY_CONFLICT"}`
		})
		var secondCalls int
		acceptingRelay := startAckCustodyTestRelay(t, func(inboxRequest) string {
			secondCalls++
			return `{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v1"}`
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, conflictRelay, acceptingRelay)
		_, err := n.InboxStoreAckCustodyDetailedWithWakeToken(
			generatePeerIDStr(t), "changed-envelope", 1000, "", CustodyKindDirectReactionV109,
		)
		if !errors.Is(err, ErrInboxCustodyIdentityConflict) {
			t.Fatalf("error = %v, want identity conflict", err)
		}
		if secondCalls != 0 {
			t.Fatalf("terminal conflict reached second relay %d times", secondCalls)
		}
	})

	t.Run("all retryable wire outcomes select past the first relay", func(t *testing.T) {
		for _, tc := range []struct {
			name  string
			reply string
		}{
			{name: "admission disabled", reply: `{"status":"ERROR","errorCode":"CUSTODY_ADMISSION_DISABLED"}`},
			{name: "full", reply: `{"status":"ERROR","storeStatus":"rejected_full","errorCode":"INBOX_FULL"}`},
			{name: "generic OK", reply: `{"status":"OK"}`},
			{name: "malformed", reply: `not-json`},
			{name: "transport", reply: ""},
		} {
			t.Run(tc.name, func(t *testing.T) {
				first := startAckCustodyTestRelay(t, func(req inboxRequest) string {
					if req.Action == "store" {
						t.Fatal("strict store used legacy fallback")
					}
					return tc.reply
				})
				var secondCalls int
				second := startAckCustodyTestRelay(t, func(req inboxRequest) string {
					secondCalls++
					return `{"status":"OK","storeStatus":"duplicate","custodyContract":"ack_or_expiry_v1"}`
				})
				n := startLocalNodeForMultiRelayTest(t)
				configureAckCustodyTestRelays(t, n, first, second)
				outcome, err := n.InboxStoreAckCustodyDetailedWithWakeToken(
					generatePeerIDStr(t), "retryable-envelope", 250, "", CustodyKindDirectTextV108,
				)
				if err != nil || outcome.StoreStatus != "duplicate" {
					t.Fatalf("retryable selection outcome=%#v err=%v", outcome, err)
				}
				if secondCalls != 1 {
					t.Fatalf("second relay calls = %d, want 1", secondCalls)
				}
			})
		}
	})

	t.Run("ineligible is terminal", func(t *testing.T) {
		ineligible := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return `{"status":"ERROR","errorCode":"CUSTODY_INELIGIBLE"}`
		})
		var secondCalls int
		second := startAckCustodyTestRelay(t, func(inboxRequest) string {
			secondCalls++
			return `{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v1"}`
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, ineligible, second)
		_, err := n.InboxStoreAckCustodyDetailedWithWakeToken(
			generatePeerIDStr(t), "ineligible-envelope", 1000, "", CustodyKindDirectTextV108,
		)
		if !errors.Is(err, ErrInboxCustodyIneligible) || secondCalls != 0 {
			t.Fatalf("ineligible err=%v secondCalls=%d", err, secondCalls)
		}
	})
}

func TestInboxAckCustodyMediaExpiryCeiling(t *testing.T) {
	const ceiling int64 = 2_000_000_123_456

	t.Run("exact ceiling is sent and exact relay proof is required", func(t *testing.T) {
		relay := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			if req.Action != inboxStoreAckCustodyAction ||
				req.CustodyContract != AckOrExpiryCustodyContract ||
				req.CustodyKind != CustodyKindDirectTextV108 ||
				req.CustodyExpiresAtOrBeforeMs != ceiling {
				t.Fatalf("media expiry request = %#v", req)
			}
			return fmt.Sprintf(
				`{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v1","expiresAtMs":%d}`,
				ceiling,
			)
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, relay)
		outcome, err := n.InboxStoreAckCustodyDetailedWithWakeTokenAndExpiryCeiling(
			generatePeerIDStr(t),
			"media-envelope",
			1000,
			"wake-token",
			CustodyKindDirectTextV108,
			ceiling,
		)
		if err != nil || outcome.ExpiresAtMs != ceiling ||
			outcome.CustodyContract != AckOrExpiryCustodyContract {
			t.Fatalf("exact media expiry outcome=%#v err=%v", outcome, err)
		}
	})

	t.Run("mutated or missing proof is retryable but never accepted", func(t *testing.T) {
		first := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return fmt.Sprintf(
				`{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v1","expiresAtMs":%d}`,
				ceiling+1,
			)
		})
		second := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return fmt.Sprintf(
				`{"status":"OK","storeStatus":"duplicate","custodyContract":"ack_or_expiry_v1","expiresAtMs":%d}`,
				ceiling,
			)
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, first, second)
		outcome, err := n.InboxStoreAckCustodyDetailedWithWakeTokenAndExpiryCeiling(
			generatePeerIDStr(t),
			"media-envelope",
			1000,
			"",
			CustodyKindDirectTextV108,
			ceiling,
		)
		if err != nil || outcome.StoreStatus != "duplicate" || outcome.ExpiresAtMs != ceiling {
			t.Fatalf("retry after mutated expiry outcome=%#v err=%v", outcome, err)
		}
		if len(first.snapshotActions()) != 1 || len(second.snapshotActions()) != 1 {
			t.Fatal("mutated proof did not advance exactly once to the next relay")
		}

		missing := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return `{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v1"}`
		})
		missingNode := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, missingNode, missing)
		if _, err := missingNode.InboxStoreAckCustodyDetailedWithWakeTokenAndExpiryCeiling(
			generatePeerIDStr(t),
			"media-envelope",
			1000,
			"",
			CustodyKindDirectTextV108,
			ceiling,
		); !errors.Is(err, ErrInboxCustodyInvalidReceipt) {
			t.Fatalf("missing media expiry proof error = %v", err)
		}
	})

	t.Run("omission preserves the existing request and invalid media selectors stop locally", func(t *testing.T) {
		relay := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			if req.CustodyExpiresAtOrBeforeMs != 0 {
				t.Fatalf("legacy strict request gained expiry ceiling: %#v", req)
			}
			return `{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v1"}`
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, relay)
		if _, err := n.InboxStoreAckCustodyDetailedWithWakeToken(
			generatePeerIDStr(t),
			"text-envelope",
			1000,
			"",
			CustodyKindDirectTextV108,
		); err != nil {
			t.Fatalf("omitted ceiling store: %v", err)
		}

		before := len(relay.snapshotActions())
		for _, tc := range []struct {
			kind    string
			ceiling int64
		}{
			{kind: CustodyKindDirectTextV108, ceiling: 0},
			{kind: CustodyKindDirectTextV108, ceiling: -1},
			{kind: CustodyKindDirectReactionV109, ceiling: ceiling},
		} {
			_, err := n.InboxStoreAckCustodyDetailedWithWakeTokenAndExpiryCeiling(
				generatePeerIDStr(t),
				"excluded-envelope",
				1000,
				"",
				tc.kind,
				tc.ceiling,
			)
			if !errors.Is(err, ErrInboxCustodyIneligible) {
				t.Fatalf("kind=%q ceiling=%d err=%v", tc.kind, tc.ceiling, err)
			}
		}
		if got := len(relay.snapshotActions()); got != before {
			t.Fatalf("invalid media selectors reached relay: before=%d after=%d", before, got)
		}
	})
}

func TestInboxAckCustodyReceiveFanoutContract(t *testing.T) {
	t.Run("fanout concurrency is bounded", func(t *testing.T) {
		relays := make([]RelayInfo, 9)
		var current atomic.Int32
		var maximum atomic.Int32
		results := mapInboxAckCustodyRelays(relays, func(RelayInfo) (int, error) {
			active := current.Add(1)
			for {
				observed := maximum.Load()
				if active <= observed || maximum.CompareAndSwap(observed, active) {
					break
				}
			}
			time.Sleep(5 * time.Millisecond)
			current.Add(-1)
			return 1, nil
		})
		if len(results) != len(relays) || maximum.Load() > inboxAckCustodyFanoutLimit {
			t.Fatalf("results=%d max concurrency=%d limit=%d",
				len(results), maximum.Load(), inboxAckCustodyFanoutLimit)
		}
	})

	t.Run("new empty does not mask old relay row", func(t *testing.T) {
		newRelay := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			if req.Action != "retrieve_custody_pending_v1" {
				t.Fatalf("upgraded relay received fallback action %q", req.Action)
			}
			return `{"status":"NO_MESSAGES","custodyContract":"ack_or_expiry_v1"}`
		})
		oldRelay := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			switch req.Action {
			case "retrieve_custody_pending_v1":
				return `{"status":"ERROR","error":"Unknown action: retrieve_custody_pending_v1"}`
			case "retrieve_pending":
				return `{"status":"OK","messages":[{"id":"legacy-1","from":"sender","message":"old-row","timestamp":10}]}`
			default:
				t.Fatalf("old relay action = %q", req.Action)
				return ""
			}
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, newRelay, oldRelay)
		page, err := n.InboxRetrieveAckCustodyPendingWithTimeout(1000)
		if err != nil {
			t.Fatalf("InboxRetrieveAckCustodyPendingWithTimeout(): %v", err)
		}
		if len(page.Messages) != 1 || page.Messages[0].ID != "legacy-1" {
			t.Fatalf("messages = %#v", page.Messages)
		}
		if page.CustodyContract != AckOrExpiryCustodyContract {
			t.Fatalf("custody contract = %q", page.CustodyContract)
		}
	})

	t.Run("union coalesces and sorts globally", func(t *testing.T) {
		first := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			return `{"status":"OK","custodyContract":"ack_or_expiry_v1","messages":[` +
				`{"id":"b","from":"s","message":"b","timestamp":20},` +
				`{"id":"shared","from":"s","message":"same","timestamp":15}]}`
		})
		second := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			if req.Action == "retrieve_custody_pending_v1" {
				return `{"status":"ERROR","error":"Unknown action: retrieve_custody_pending_v1"}`
			}
			return `{"status":"OK","messages":[` +
				`{"id":"a","from":"s","message":"a","timestamp":10},` +
				`{"id":"shared","from":"s","message":"same","timestamp":15}]}`
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, first, second)
		page, err := n.InboxRetrieveAckCustodyPendingWithTimeout(1000)
		if err != nil {
			t.Fatalf("retrieve union: %v", err)
		}
		got := make([]string, len(page.Messages))
		for i, message := range page.Messages {
			got[i] = message.ID
		}
		if strings.Join(got, ",") != "a,shared,b" {
			t.Fatalf("global order/coalesce = %v", got)
		}
	})

	t.Run("same ID with different bytes fails closed", func(t *testing.T) {
		first := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return `{"status":"OK","custodyContract":"ack_or_expiry_v1","messages":[{"id":"collision","from":"s","message":"one","timestamp":1}]}`
		})
		second := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return `{"status":"OK","custodyContract":"ack_or_expiry_v1","messages":[{"id":"collision","from":"s","message":"two","timestamp":1}]}`
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, first, second)
		if _, err := n.InboxRetrieveAckCustodyPendingWithTimeout(1000); !errors.Is(err, ErrInboxCustodyIdentityConflict) {
			t.Fatalf("collision error = %v", err)
		}
	})

	t.Run("empty partial scan is retryable", func(t *testing.T) {
		empty := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return `{"status":"NO_MESSAGES","custodyContract":"ack_or_expiry_v1"}`
		})
		failed := startAckCustodyTestRelay(t, func(inboxRequest) string { return "" })
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, empty, failed)
		if _, err := n.InboxRetrieveAckCustodyPendingWithTimeout(150); err == nil {
			t.Fatal("empty partial scan unexpectedly succeeded")
		}
	})

	t.Run("nonempty partial scan succeeds with hasMore", func(t *testing.T) {
		nonempty := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return `{"status":"OK","custodyContract":"ack_or_expiry_v1","messages":[{"id":"partial","from":"s","message":"row","timestamp":1}]}`
		})
		failed := startAckCustodyTestRelay(t, func(inboxRequest) string { return "" })
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, nonempty, failed)
		page, err := n.InboxRetrieveAckCustodyPendingWithTimeout(150)
		if err != nil {
			t.Fatalf("nonempty partial scan: %v", err)
		}
		if len(page.Messages) != 1 || !page.HasMore {
			t.Fatalf("partial page = %#v", page)
		}
	})

	t.Run("ACK reaches upgraded and legacy relays", func(t *testing.T) {
		upgraded := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			if req.Action != "ack_custody_v1" {
				t.Fatalf("upgraded ACK relay action = %q", req.Action)
			}
			return `{"status":"OK","acked":1,"custodyContract":"ack_or_expiry_v1"}`
		})
		legacy := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			if req.Action == "ack_custody_v1" {
				return `{"status":"ERROR","error":"Unknown action: ack_custody_v1"}`
			}
			if req.Action != "ack" {
				t.Fatalf("legacy ACK relay action = %q", req.Action)
			}
			return `{"status":"OK","acked":1}`
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, upgraded, legacy)
		acked, err := n.InboxAckCustody([]string{"entry-a", "entry-b"}, 1000)
		if err != nil {
			t.Fatalf("InboxAckCustody(): %v", err)
		}
		if acked != 2 {
			t.Fatalf("acked = %d, want 2", acked)
		}
	})

	t.Run("partial ACK is nonaccepting after best effort", func(t *testing.T) {
		success := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return `{"status":"OK","acked":1,"custodyContract":"ack_or_expiry_v1"}`
		})
		failed := startAckCustodyTestRelay(t, func(inboxRequest) string { return "" })
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, success, failed)
		acked, err := n.InboxAckCustody([]string{"entry"}, 150)
		if !errors.Is(err, ErrInboxCustodyPartial) || acked != 1 {
			t.Fatalf("partial ACK acked=%d err=%v", acked, err)
		}
		if len(failed.snapshotActions()) < 2 {
			t.Fatalf("failed relay actions = %#v, want strict then legacy best effort", failed.snapshotActions())
		}
	})

	t.Run("oversized ACK counts cannot mask a partial pool", func(t *testing.T) {
		malformed := startAckCustodyTestRelay(t, func(req inboxRequest) string {
			if req.Action == "ack_custody_v1" {
				return `{"status":"OK","acked":2,"custodyContract":"ack_or_expiry_v1"}`
			}
			return `{"status":"ERROR","error":"legacy unavailable"}`
		})
		missing := startAckCustodyTestRelay(t, func(inboxRequest) string {
			return `{"status":"OK","acked":0,"custodyContract":"ack_or_expiry_v1"}`
		})
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, malformed, missing)
		if acked, err := n.InboxAckCustody([]string{"one"}, 1000); err == nil || acked != 0 {
			t.Fatalf("oversized ACK count acked=%d err=%v", acked, err)
		}
	})

	t.Run("nonempty partial scan is bounded and advertises continuation", func(t *testing.T) {
		largeReply := func(prefix string, start int64) string {
			messages := make([]InboxMessage, 25)
			for i := range messages {
				messages[i] = InboxMessage{
					ID:        fmt.Sprintf("%s-%02d", prefix, i),
					From:      "sender",
					Message:   strings.Repeat(prefix, 3000),
					Timestamp: start + int64(i),
				}
			}
			encoded, err := json.Marshal(inboxResponse{
				Status:          "OK",
				CustodyContract: AckOrExpiryCustodyContract,
				Messages:        messages,
			})
			if err != nil {
				t.Fatalf("marshal large reply: %v", err)
			}
			return string(encoded)
		}
		first := startAckCustodyTestRelay(t, func(inboxRequest) string { return largeReply("a", 1) })
		second := startAckCustodyTestRelay(t, func(inboxRequest) string { return largeReply("b", 100) })
		n := startLocalNodeForMultiRelayTest(t)
		configureAckCustodyTestRelays(t, n, first, second)
		page, err := n.InboxRetrieveAckCustodyPendingWithTimeout(1000)
		if err != nil {
			t.Fatalf("large retrieve: %v", err)
		}
		if !page.HasMore || len(page.Messages) >= 50 {
			t.Fatalf("large page len=%d hasMore=%v", len(page.Messages), page.HasMore)
		}
		encoded, err := json.Marshal(inboxResponse{
			Status:          "OK",
			CustodyContract: page.CustodyContract,
			Messages:        page.Messages,
			HasMore:         page.HasMore,
		})
		if err != nil {
			t.Fatalf("marshal merged page: %v", err)
		}
		if len(encoded) > MaxFrameLen {
			t.Fatalf("merged page = %d bytes, max %d", len(encoded), MaxFrameLen)
		}
	})
}
