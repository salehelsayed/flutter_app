//go:build integration

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

type redisHelperRequest struct {
	Op                         string   `json:"op"`
	RedisURL                   string   `json:"redisUrl"`
	RedisPrefix                string   `json:"redisPrefix"`
	Namespace                  string   `json:"namespace,omitempty"`
	Requester                  string   `json:"requester,omitempty"`
	PeerID                     string   `json:"peerId,omitempty"`
	From                       string   `json:"from,omitempty"`
	Record                     string   `json:"record,omitempty"`
	GroupID                    string   `json:"groupId,omitempty"`
	Cursor                     string   `json:"cursor,omitempty"`
	Token                      string   `json:"token,omitempty"`
	Platform                   string   `json:"platform,omitempty"`
	Limit                      int      `json:"limit,omitempty"`
	TTL                        uint64   `json:"ttl,omitempty"`
	Messages                   []string `json:"messages,omitempty"`
	EntryIDs                   []string `json:"entryIds,omitempty"`
	CustodyKind                string   `json:"custodyKind,omitempty"`
	Admission                  bool     `json:"admission,omitempty"`
	CustodyExpiresAtOrBeforeMs int64    `json:"custodyExpiresAtOrBeforeMs,omitempty"`
	NowMs                      int64    `json:"nowMs,omitempty"`
}

type redisHelperResponse struct {
	Records     []string `json:"records,omitempty"`
	Messages    []string `json:"messages,omitempty"`
	HasMore     bool     `json:"hasMore,omitempty"`
	NextCursor  string   `json:"nextCursor,omitempty"`
	Token       string   `json:"token,omitempty"`
	Platform    string   `json:"platform,omitempty"`
	StoreStatus string   `json:"storeStatus,omitempty"`
	EntryIDs    []string `json:"entryIds,omitempty"`
	Timestamps  []int64  `json:"timestamps,omitempty"`
	ExpiresAtMs []int64  `json:"expiresAtMs,omitempty"`
	Acked       int      `json:"acked,omitempty"`
	Count       int      `json:"count,omitempty"`
	Peers       int      `json:"peers,omitempty"`
}

func TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace(t *testing.T) {
	const baselineCommit = "6bab4c485dd4d13887392915abaaaabf85ea4b21"
	baselineSource, err := exec.Command(
		"git",
		"show",
		baselineCommit+":go-relay-server/backend_redis.go",
	).Output()
	if err != nil {
		t.Fatalf("read pinned baseline Redis backend source: %v", err)
	}
	const frozenLegacyKeySource = `func (b *redisInboxBackend) key(peerId string) string {
	return b.prefix + "inbox:" + encodeRedisComponent(peerId)
}`
	if !bytes.Contains(baselineSource, []byte(frozenLegacyKeySource)) {
		t.Fatalf("baseline %s no longer proves the frozen inbox: key constructor", baselineCommit)
	}
	if bytes.Contains(baselineSource, []byte("custody_inbox:")) {
		t.Fatalf("baseline %s unexpectedly knows the protected namespace", baselineCommit)
	}

	server := miniredis.RunT(t)
	base := redisHelperRequest{
		RedisURL:    "redis://" + server.Addr(),
		RedisPrefix: "ack-process:",
		PeerID:      "peer-recipient",
		From:        "peer-sender",
		CustodyKind: ackCustodyDirectReactionKind,
		Admission:   true,
		Messages: []string{
			ackCustodyReactionEnvelope("process-handoff", "add", "target", "peer-sender", "cipher"),
		},
	}
	keyProbe := newAckCustodyRedisBackend(t, server, base.RedisPrefix, 1)
	wantLegacyKey := base.RedisPrefix + "inbox:" + encodeRedisComponent(base.PeerID)
	wantProtectedKey := base.RedisPrefix + "custody_inbox:" + encodeRedisComponent(base.PeerID)
	if got := keyProbe.key(base.PeerID); got != wantLegacyKey {
		t.Fatalf("current legacy key = %q, want frozen %q", got, wantLegacyKey)
	}
	if got := keyProbe.ackCustodyKey(base.PeerID); got != wantProtectedKey || got == wantLegacyKey {
		t.Fatalf("protected key = %q, want separate %q", got, wantProtectedKey)
	}

	stored := runRedisHelper(t, withOp(base, "store_ack_custody", nil))
	if stored.StoreStatus != string(InboxStoreResultStored) ||
		len(stored.EntryIDs) != 1 || stored.EntryIDs[0] == "" ||
		len(stored.Timestamps) != 1 {
		t.Fatalf("process A protected store = %#v", stored)
	}
	originalID := stored.EntryIDs[0]
	originalTimestamp := stored.Timestamps[0]

	flagOff := base
	flagOff.Admission = false
	drained := runRedisHelper(t, withOp(flagOff, "retrieve_ack_custody", func(r *redisHelperRequest) {
		r.Limit = 50
	}))
	if len(drained.EntryIDs) != 1 || drained.EntryIDs[0] != originalID ||
		len(drained.Timestamps) != 1 || drained.Timestamps[0] != originalTimestamp {
		t.Fatalf("process B flag-off protected retrieve = %#v", drained)
	}

	// The independently spawned legacy action can destructively consume only
	// the inbox: shadow. It has no path to custody_inbox: authority.
	legacy := runRedisHelper(t, withOp(flagOff, "retrieve_inbox", func(r *redisHelperRequest) {
		r.Limit = 50
	}))
	if len(legacy.Messages) != 1 || legacy.Messages[0] != base.Messages[0] {
		t.Fatalf("legacy destructive shadow retrieve = %#v", legacy)
	}
	stillProtected := runRedisHelper(t, withOp(flagOff, "retrieve_ack_custody", func(r *redisHelperRequest) {
		r.Limit = 50
	}))
	if len(stillProtected.EntryIDs) != 1 || stillProtected.EntryIDs[0] != originalID ||
		stillProtected.Timestamps[0] != originalTimestamp {
		t.Fatalf("legacy action addressed protected namespace: %#v", stillProtected)
	}

	// Re-enable and exact-retry through a third process: duplicate preserves the
	// original ID/expiry instead of minting/refanning out.
	reenabled := runRedisHelper(t, withOp(base, "store_ack_custody", nil))
	if reenabled.StoreStatus != string(InboxStoreResultDuplicate) ||
		len(reenabled.EntryIDs) != 1 || reenabled.EntryIDs[0] != originalID ||
		reenabled.Timestamps[0] != originalTimestamp {
		t.Fatalf("process C re-enabled retry = %#v", reenabled)
	}

	acked := runRedisHelper(t, withOp(flagOff, "ack_ack_custody", func(r *redisHelperRequest) {
		r.EntryIDs = []string{originalID}
	}))
	if acked.Acked != 1 {
		t.Fatalf("flag-off process ACK = %#v", acked)
	}
	final := runRedisHelper(t, withOp(flagOff, "retrieve_ack_custody", func(r *redisHelperRequest) {
		r.Limit = 50
	}))
	if len(final.Messages) != 0 || len(final.EntryIDs) != 0 || final.HasMore {
		t.Fatalf("protected row survived exact ACK: %#v", final)
	}

	// Plan 347: a media-envelope ceiling is persisted in both physical rows,
	// survives exact retry through another process, and is authoritative for
	// legacy count/stats/read as well as protected count/stats/read.
	const processNowMs int64 = 2_000_000_000_000
	expiryBase := base
	expiryBase.PeerID = "peer-media-expiry"
	expiryBase.CustodyKind = ackCustodyDirectTextKind
	expiryBase.Messages = []string{
		ackCustodyTextEnvelope("process-media-expiry", "peer-sender", "cipher"),
	}
	expiryBase.NowMs = processNowMs
	expiryBase.CustodyExpiresAtOrBeforeMs = processNowMs + time.Hour.Milliseconds()

	expiryStored := runRedisHelper(t, withOp(expiryBase, "store_ack_custody", nil))
	if expiryStored.StoreStatus != string(InboxStoreResultStored) ||
		len(expiryStored.ExpiresAtMs) != 1 ||
		expiryStored.ExpiresAtMs[0] != expiryBase.CustodyExpiresAtOrBeforeMs {
		t.Fatalf("process media bounded store = %#v", expiryStored)
	}
	expiryRetry := expiryBase
	expiryRetry.NowMs += time.Minute.Milliseconds()
	expiryDuplicate := runRedisHelper(t, withOp(expiryRetry, "store_ack_custody", nil))
	if expiryDuplicate.StoreStatus != string(InboxStoreResultDuplicate) ||
		len(expiryDuplicate.EntryIDs) != 1 ||
		expiryDuplicate.EntryIDs[0] != expiryStored.EntryIDs[0] ||
		expiryDuplicate.ExpiresAtMs[0] != expiryBase.CustodyExpiresAtOrBeforeMs {
		t.Fatalf("process media bounded duplicate = %#v", expiryDuplicate)
	}

	atExpiry := expiryBase
	atExpiry.NowMs = expiryBase.CustodyExpiresAtOrBeforeMs
	for _, operation := range []string{
		"count_inbox",
		"stats_inbox",
		"count_ack_custody",
		"stats_ack_custody",
	} {
		counted := runRedisHelper(t, withOp(atExpiry, operation, nil))
		if counted.Count != 0 || counted.Peers != 0 {
			t.Fatalf("%s retained media row at exact bound: %#v", operation, counted)
		}
	}
	expiredShadow := runRedisHelper(t, withOp(atExpiry, "retrieve_inbox", func(r *redisHelperRequest) {
		r.Limit = 50
	}))
	if len(expiredShadow.Messages) != 0 || expiredShadow.HasMore {
		t.Fatalf("legacy shadow outlived media ceiling: %#v", expiredShadow)
	}
	expiredProtected := runRedisHelper(t, withOp(atExpiry, "retrieve_ack_custody", func(r *redisHelperRequest) {
		r.Limit = 50
	}))
	if len(expiredProtected.Messages) != 0 || expiredProtected.HasMore {
		t.Fatalf("protected row outlived media ceiling: %#v", expiredProtected)
	}
}

func TestRedisControlPlaneSharedAcrossProcesses(t *testing.T) {
	t.Run("rendezvous", func(t *testing.T) {
		server := miniredis.RunT(t)
		req := redisHelperRequest{
			RedisURL:    "redis://" + server.Addr(),
			RedisPrefix: "integration:",
		}

		runRedisHelper(t, withOp(req, "register_rendezvous", func(r *redisHelperRequest) {
			r.Namespace = "ns-1"
			r.PeerID = "peer-1"
			r.Record = "record-1"
			r.TTL = 60
		}))

		resp := runRedisHelper(t, withOp(req, "discover_rendezvous", func(r *redisHelperRequest) {
			r.Namespace = "ns-1"
			r.Requester = "other-peer"
			r.Limit = 10
		}))

		if len(resp.Records) != 1 || resp.Records[0] != "record-1" {
			t.Fatalf("expected discover through a separate process to return record-1, got %#v", resp.Records)
		}
	})

	t.Run("inbox", func(t *testing.T) {
		server := miniredis.RunT(t)
		req := redisHelperRequest{
			RedisURL:    "redis://" + server.Addr(),
			RedisPrefix: "integration:",
		}

		runRedisHelper(t, withOp(req, "store_inbox", func(r *redisHelperRequest) {
			r.PeerID = "peer-recipient"
			r.From = "peer-sender"
			r.Messages = []string{"msg-0", "msg-1", "msg-2", "msg-3"}
		}))

		page1 := runRedisHelper(t, withOp(req, "retrieve_inbox", func(r *redisHelperRequest) {
			r.PeerID = "peer-recipient"
			r.Limit = 2
		}))
		if len(page1.Messages) != 2 || page1.Messages[0] != "msg-0" || page1.Messages[1] != "msg-1" {
			t.Fatalf("unexpected first page from separate process: %#v", page1.Messages)
		}
		if !page1.HasMore {
			t.Fatal("expected hasMore=true after first inbox page")
		}

		page2 := runRedisHelper(t, withOp(req, "retrieve_inbox", func(r *redisHelperRequest) {
			r.PeerID = "peer-recipient"
			r.Limit = 10
		}))
		if len(page2.Messages) != 2 || page2.Messages[0] != "msg-2" || page2.Messages[1] != "msg-3" {
			t.Fatalf("unexpected second page from separate process: %#v", page2.Messages)
		}
		if page2.HasMore {
			t.Fatal("expected hasMore=false after final inbox page")
		}
	})

	t.Run("push_tokens", func(t *testing.T) {
		server := miniredis.RunT(t)
		req := redisHelperRequest{
			RedisURL:    "redis://" + server.Addr(),
			RedisPrefix: "integration:",
		}

		runRedisHelper(t, withOp(req, "register_push", func(r *redisHelperRequest) {
			r.PeerID = "peer-1"
			r.Token = "token-xyz"
			r.Platform = "android"
		}))

		resp := runRedisHelper(t, withOp(req, "lookup_push", func(r *redisHelperRequest) {
			r.PeerID = "peer-1"
		}))
		if resp.Token != "token-xyz" || resp.Platform != "android" {
			t.Fatalf("expected push token to survive process restart, got token=%q platform=%q", resp.Token, resp.Platform)
		}
	})

	t.Run("group_cursor", func(t *testing.T) {
		server := miniredis.RunT(t)
		req := redisHelperRequest{
			RedisURL:    "redis://" + server.Addr(),
			RedisPrefix: "integration:",
		}

		runRedisHelper(t, withOp(req, "store_group_batch", func(r *redisHelperRequest) {
			r.GroupID = "group-1"
			r.From = "peer-1"
			r.Messages = []string{"msg-00", "msg-01", "msg-02", "msg-03", "msg-04"}
		}))

		page1 := runRedisHelper(t, withOp(req, "group_cursor", func(r *redisHelperRequest) {
			r.GroupID = "group-1"
			r.Limit = 2
		}))
		if len(page1.Messages) != 2 || page1.Messages[0] != "msg-00" || page1.Messages[1] != "msg-01" {
			t.Fatalf("unexpected first group page: %#v", page1.Messages)
		}
		if page1.NextCursor == "" {
			t.Fatal("expected non-empty cursor after first group page")
		}

		page2 := runRedisHelper(t, withOp(req, "group_cursor", func(r *redisHelperRequest) {
			r.GroupID = "group-1"
			r.Cursor = page1.NextCursor
			r.Limit = 2
		}))
		if len(page2.Messages) != 2 || page2.Messages[0] != "msg-02" || page2.Messages[1] != "msg-03" {
			t.Fatalf("unexpected second group page: %#v", page2.Messages)
		}
		if page2.NextCursor == "" {
			t.Fatal("expected non-empty cursor after second group page")
		}

		page3 := runRedisHelper(t, withOp(req, "group_cursor", func(r *redisHelperRequest) {
			r.GroupID = "group-1"
			r.Cursor = page2.NextCursor
			r.Limit = 2
		}))
		if len(page3.Messages) != 1 || page3.Messages[0] != "msg-04" {
			t.Fatalf("unexpected final group page: %#v", page3.Messages)
		}
		if page3.NextCursor != "" {
			t.Fatalf("expected empty cursor after final group page, got %q", page3.NextCursor)
		}
	})
}

func TestRedisBackendHelperProcess(t *testing.T) {
	if os.Getenv("GO_WANT_REDIS_HELPER") != "1" {
		t.Skip("helper process only")
	}

	var req redisHelperRequest
	if err := json.Unmarshal([]byte(os.Getenv("REDIS_HELPER_REQUEST")), &req); err != nil {
		t.Fatalf("decode helper request: %v", err)
	}

	stores, err := newControlPlaneStores(context.Background(), backendConfig{
		Kind:                       backendKindRedis,
		RedisURL:                   req.RedisURL,
		RedisPrefix:                req.RedisPrefix,
		AckCustodyAdmissionEnabled: req.Admission,
	}, DefaultServerLimits(), "/path/that/does/not/exist.json")
	if err != nil {
		t.Fatalf("newControlPlaneStores() error: %v", err)
	}
	defer func() { _ = stores.Close() }()
	helperNow := time.Now()
	if req.NowMs > 0 {
		helperNow = time.UnixMilli(req.NowMs)
		stores.Inbox.SetAckCustodyNowForTest(func() time.Time { return helperNow })
	}

	var resp redisHelperResponse

	switch req.Op {
	case "register_rendezvous":
		stores.Rendezvous.Register(req.Namespace, req.PeerID, []byte(req.Record), req.TTL)
	case "discover_rendezvous":
		regs := stores.Rendezvous.Discover(req.Namespace, req.Requester, uint64(req.Limit))
		resp.Records = make([]string, 0, len(regs))
		for _, reg := range regs {
			resp.Records = append(resp.Records, string(reg.SignedPeerRecord))
		}
	case "store_inbox":
		for _, message := range req.Messages {
			requireInboxStoreResult(t, stores.Inbox, req.PeerID, inboxMessage{
				From:      req.From,
				Message:   message,
				Timestamp: time.Now().UnixMilli(),
			}, InboxStoreResultStored)
		}
	case "retrieve_inbox":
		messages, hasMore := stores.Inbox.RetrieveWithMeta(req.PeerID, req.Limit)
		resp.HasMore = hasMore
		resp.Messages = make([]string, 0, len(messages))
		for _, message := range messages {
			resp.Messages = append(resp.Messages, message.Message)
		}
	case "store_ack_custody":
		if len(req.Messages) != 1 {
			t.Fatalf("store_ack_custody requires exactly one message")
		}
		result, stored, err := stores.Inbox.StoreAckCustody(req.PeerID, inboxMessage{
			From:        req.From,
			Message:     req.Messages[0],
			Timestamp:   helperNow.UnixMilli(),
			ExpiresAtMs: req.CustodyExpiresAtOrBeforeMs,
		}, req.CustodyKind)
		if err != nil {
			t.Fatalf("StoreAckCustody: %v", err)
		}
		resp.StoreStatus = string(result)
		resp.EntryIDs = []string{stored.ID}
		resp.Timestamps = []int64{stored.Timestamp}
		resp.ExpiresAtMs = []int64{ackCustodyEntryExpiresAtMs(stored)}
	case "retrieve_ack_custody":
		messages, hasMore, err := stores.Inbox.RetrieveAckCustodyPending(req.PeerID, req.Limit)
		if err != nil {
			t.Fatalf("RetrieveAckCustodyPending: %v", err)
		}
		resp.HasMore = hasMore
		resp.Messages = make([]string, 0, len(messages))
		resp.EntryIDs = make([]string, 0, len(messages))
		resp.Timestamps = make([]int64, 0, len(messages))
		resp.ExpiresAtMs = make([]int64, 0, len(messages))
		for _, message := range messages {
			resp.Messages = append(resp.Messages, message.Message)
			resp.EntryIDs = append(resp.EntryIDs, message.ID)
			resp.Timestamps = append(resp.Timestamps, message.Timestamp)
			resp.ExpiresAtMs = append(resp.ExpiresAtMs, ackCustodyEntryExpiresAtMs(message))
		}
	case "count_inbox":
		resp.Count = stores.Inbox.Count(req.PeerID)
	case "stats_inbox":
		resp.Peers, resp.Count = stores.Inbox.Stats()
	case "count_ack_custody":
		resp.Count = stores.Inbox.CountAckCustody(req.PeerID)
	case "stats_ack_custody":
		resp.Peers, resp.Count = stores.Inbox.AckCustodyStats()
	case "ack_ack_custody":
		acked, err := stores.Inbox.AckAckCustody(req.PeerID, req.EntryIDs)
		if err != nil {
			t.Fatalf("AckAckCustody: %v", err)
		}
		resp.Acked = acked
	case "register_push":
		stores.Push.RegisterToken(req.PeerID, req.Token, req.Platform)
	case "lookup_push":
		entry := stores.Push.tokenBackend.LookupToken(req.PeerID)
		if entry != nil {
			resp.Token = entry.Token
			resp.Platform = entry.Platform
		}
	case "store_group_batch":
		for _, message := range req.Messages {
			if err := stores.GroupInbox.Store(req.GroupID, req.From, message); err != nil {
				t.Fatalf("GroupInbox.Store() error: %v", err)
			}
		}
	case "group_cursor":
		messages, nextCursor, _ := stores.GroupInbox.RetrieveWithCursor(req.GroupID, req.Cursor, req.Limit)
		resp.NextCursor = nextCursor
		resp.Messages = make([]string, 0, len(messages))
		for _, message := range messages {
			resp.Messages = append(resp.Messages, message.Message)
		}
	default:
		t.Fatalf("unknown helper op %q", req.Op)
	}

	payload, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("encode helper response: %v", err)
	}
	payload = append(payload, '\n')
	if _, err := os.Stdout.Write(payload); err != nil {
		t.Fatalf("write helper response: %v", err)
	}
}

func runRedisHelper(t *testing.T, req redisHelperRequest) redisHelperResponse {
	t.Helper()

	payload, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("marshal helper request: %v", err)
	}

	exe, err := os.Executable()
	if err != nil {
		t.Fatalf("os.Executable() error: %v", err)
	}

	cmd := exec.Command(exe, "-test.run=^TestRedisBackendHelperProcess$")
	cmd.Env = append(os.Environ(),
		"GO_WANT_REDIS_HELPER=1",
		"REDIS_HELPER_REQUEST="+string(payload),
	)

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		t.Fatalf("helper process failed: %v\nstdout=%s\nstderr=%s", err, stdout.String(), stderr.String())
	}

	var resp redisHelperResponse
	responseLine := bytes.TrimSpace(stdout.Bytes())
	if newline := bytes.IndexByte(responseLine, '\n'); newline >= 0 {
		responseLine = responseLine[:newline]
	}
	if err := json.Unmarshal(responseLine, &resp); err != nil {
		t.Fatalf("decode helper response: %v\nstdout=%s\nstderr=%s", err, stdout.String(), stderr.String())
	}
	return resp
}

func withOp(base redisHelperRequest, op string, mutate func(*redisHelperRequest)) redisHelperRequest {
	base.Op = op
	if mutate != nil {
		mutate(&base)
	}
	return base
}
