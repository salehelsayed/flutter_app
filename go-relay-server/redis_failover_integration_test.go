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
	Op          string   `json:"op"`
	RedisURL    string   `json:"redisUrl"`
	RedisPrefix string   `json:"redisPrefix"`
	Namespace   string   `json:"namespace,omitempty"`
	Requester   string   `json:"requester,omitempty"`
	PeerID      string   `json:"peerId,omitempty"`
	From        string   `json:"from,omitempty"`
	Record      string   `json:"record,omitempty"`
	GroupID     string   `json:"groupId,omitempty"`
	Cursor      string   `json:"cursor,omitempty"`
	Token       string   `json:"token,omitempty"`
	Platform    string   `json:"platform,omitempty"`
	Limit       int      `json:"limit,omitempty"`
	TTL         uint64   `json:"ttl,omitempty"`
	Messages    []string `json:"messages,omitempty"`
}

type redisHelperResponse struct {
	Records    []string `json:"records,omitempty"`
	Messages   []string `json:"messages,omitempty"`
	HasMore    bool     `json:"hasMore,omitempty"`
	NextCursor string   `json:"nextCursor,omitempty"`
	Token      string   `json:"token,omitempty"`
	Platform   string   `json:"platform,omitempty"`
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
		Kind:        backendKindRedis,
		RedisURL:    req.RedisURL,
		RedisPrefix: req.RedisPrefix,
	}, DefaultServerLimits(), "/path/that/does/not/exist.json")
	if err != nil {
		t.Fatalf("newControlPlaneStores() error: %v", err)
	}
	defer func() { _ = stores.Close() }()

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
