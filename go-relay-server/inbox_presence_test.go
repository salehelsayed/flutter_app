package main

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"sync"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

// FDC-08 relay-tier tests for the additive `presence_get` inbox action.
//
// Resolver (FDC-S3, locked): a peer's live socket connectedness
// (h.Network().Connectedness) PLUS a net-new connectedness-seeded last-seen map
// (presence_store.go), preferring a fresh self-published `presence_set` state.
// Reservation-table truth is OUT. The answer is coarse "online-ish, TTL-lagged"
// and never claims foreground/background.

// genDisconnectedPeerID returns a syntactically valid peer.ID for a peer that is
// NOT connected to the test server (so Connectedness == NotConnected) and has no
// last-seen entry until the test seeds one.
func genDisconnectedPeerID(t *testing.T) peer.ID {
	t.Helper()
	_, pub, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	pid, err := peer.IDFromPublicKey(pub)
	if err != nil {
		t.Fatalf("derive peer id: %v", err)
	}
	return pid
}

// sendPresenceGet drives a `presence_get` request to the server over a real
// stream and returns the decoded response plus the raw JSON keys (so schema
// locks like "never claims foreground" can inspect unknown keys).
func sendPresenceGet(t *testing.T, env *inboxStreamEnv, to string) (inboxResponse, map[string]json.RawMessage) {
	t.Helper()
	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open presence stream: %v", err)
	}
	defer stream.Close()

	sendInboxReq(t, stream, inboxRequest{Action: "presence_get", To: to})

	data, err := readFrame(stream)
	if err != nil {
		t.Fatalf("read presence frame: %v", err)
	}
	var resp inboxResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("decode presence response: %v", err)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("decode presence raw keys: %v", err)
	}
	return resp, raw
}

func newPresenceTestEnv(t *testing.T) (*inboxStreamEnv, *InboxStore) {
	t.Helper()
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)
	return env, inbox
}

// R1 — presence_get returns reachable for a connected peer (+ small ageMs).
func TestPresenceGet_ReturnsReachableForConnectedPeer(t *testing.T) {
	env, _ := newPresenceTestEnv(t)

	// env.sender is socket-connected to the server (mocknet ConnectAllButSelf);
	// seed a fresh last-seen too (mirrors what the connectedness handler does).
	env.presence.RecordSeen(env.sender.ID())

	resp, _ := sendPresenceGet(t, env, env.sender.ID().String())
	if resp.Status != "OK" {
		t.Fatalf("status = %q, want OK", resp.Status)
	}
	if resp.Presence != presenceReachable {
		t.Fatalf("presence = %q, want %q", resp.Presence, presenceReachable)
	}
	if resp.AgeMs == nil {
		t.Fatalf("ageMs missing; presence responses must always carry ageMs")
	}
	if *resp.AgeMs < 0 || *resp.AgeMs >= relayPresenceTTL.Milliseconds() {
		t.Fatalf("ageMs = %d, want a fresh value in [0, %d)", *resp.AgeMs, relayPresenceTTL.Milliseconds())
	}
}

// R2 — presence_get returns unreachable for a disconnected, never-seen peer,
// and the response schema NEVER carries a foreground/background field.
func TestPresenceGet_UnreachableForDisconnected(t *testing.T) {
	env, _ := newPresenceTestEnv(t)

	pid := genDisconnectedPeerID(t)
	resp, _ := sendPresenceGet(t, env, pid.String())
	if resp.Status != "OK" {
		t.Fatalf("status = %q, want OK", resp.Status)
	}
	if resp.Presence != presenceUnreachable {
		t.Fatalf("presence = %q, want %q", resp.Presence, presenceUnreachable)
	}
}

func TestPresenceResponseNeverClaimsForeground(t *testing.T) {
	env, _ := newPresenceTestEnv(t)
	env.presence.RecordSeen(env.sender.ID())

	_, raw := sendPresenceGet(t, env, env.sender.ID().String())
	for _, forbidden := range []string{"foreground", "background", "fg", "state"} {
		if _, ok := raw[forbidden]; ok {
			t.Fatalf("presence response leaked a %q key — presence is online-ish, never foreground (got keys %v)", forbidden, rawKeys(raw))
		}
	}
	// Sanity: it DOES carry the coarse presence + ageMs keys.
	if _, ok := raw["presence"]; !ok {
		t.Fatalf("presence response missing 'presence' key (got %v)", rawKeys(raw))
	}
	if _, ok := raw["ageMs"]; !ok {
		t.Fatalf("presence response missing 'ageMs' key (got %v)", rawKeys(raw))
	}
}

func rawKeys(m map[string]json.RawMessage) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

// R4 — presence_get is read-only: it never stores or consumes inbox entries.
func TestPresenceGetDoesNotStoreOrConsume(t *testing.T) {
	env, inbox := newPresenceTestEnv(t)
	recipient := env.recipient.ID().String()

	// Store one message for the recipient.
	storeStream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open store stream: %v", err)
	}
	sendInboxReq(t, storeStream, inboxRequest{
		Action:  "store",
		To:      recipient,
		From:    env.sender.ID().String(),
		Message: `{"type":"chat_message","version":"1","payload":{"id":"r4-msg-1","text":"hi"}}`,
	})
	_ = recvInboxResp(t, storeStream)
	storeStream.Close()

	occBefore := inbox.Count(recipient)
	if occBefore != 1 {
		t.Fatalf("occupancy before presence_get = %d, want 1", occBefore)
	}

	// A presence query for that recipient must not touch the queue.
	resp, _ := sendPresenceGet(t, env, recipient)
	if resp.Status != "OK" {
		t.Fatalf("presence status = %q, want OK", resp.Status)
	}

	if occAfter := inbox.Count(recipient); occAfter != occBefore {
		t.Fatalf("presence_get changed occupancy: before=%d after=%d (must be read-only)", occBefore, occAfter)
	}
}

// R5 — a stale last-seen (age >= TTL) for a disconnected peer resolves to
// `unknown` (NEVER silently `unreachable`) and reports ageMs >= TTL.
func TestPresenceGet_StaleLastSeenIsUnknown(t *testing.T) {
	env, _ := newPresenceTestEnv(t)

	pid := genDisconnectedPeerID(t) // not socket-connected
	base := time.Now()
	cur := base
	env.presence.now = func() time.Time { return cur }

	env.presence.RecordSeen(pid) // lastSeen = base
	cur = base.Add(relayPresenceTTL + time.Second)

	resp, _ := sendPresenceGet(t, env, pid.String())
	if resp.Status != "OK" {
		t.Fatalf("status = %q, want OK", resp.Status)
	}
	if resp.Presence != presenceUnknown {
		t.Fatalf("stale presence = %q, want %q (must never silently be unreachable)", resp.Presence, presenceUnknown)
	}
	if resp.AgeMs == nil || *resp.AgeMs < relayPresenceTTL.Milliseconds() {
		t.Fatalf("stale ageMs = %v, want >= %d", resp.AgeMs, relayPresenceTTL.Milliseconds())
	}
}

// R6 — the connectedness handler seeds the net-new last-seen map: a Connected
// event makes a (not-yet-socket-connected) peer read `reachable`.
func TestConnectednessHandlerSeedsLastSeen(t *testing.T) {
	env, _ := newPresenceTestEnv(t)

	pid := genDisconnectedPeerID(t)

	// Before seeding: disconnected + never seen -> unreachable.
	if resp, _ := sendPresenceGet(t, env, pid.String()); resp.Presence != presenceUnreachable {
		t.Fatalf("pre-seed presence = %q, want %q", resp.Presence, presenceUnreachable)
	}

	// Fire the connectedness handler's Connected branch.
	recordConnectednessPresence(env.presence, event.EvtPeerConnectednessChanged{
		Peer:          pid,
		Connectedness: network.Connected,
	})

	resp, _ := sendPresenceGet(t, env, pid.String())
	if resp.Presence != presenceReachable {
		t.Fatalf("post-seed presence = %q, want %q (handler must seed the last-seen map)", resp.Presence, presenceReachable)
	}
	if resp.AgeMs == nil || *resp.AgeMs < 0 || *resp.AgeMs >= relayPresenceTTL.Milliseconds() {
		t.Fatalf("post-seed ageMs = %v, want a fresh value", resp.AgeMs)
	}

	// A NotConnected event must NOT seed a never-seen peer.
	other := genDisconnectedPeerID(t)
	recordConnectednessPresence(env.presence, event.EvtPeerConnectednessChanged{
		Peer:          other,
		Connectedness: network.NotConnected,
	})
	if resp, _ := sendPresenceGet(t, env, other.String()); resp.Presence != presenceUnreachable {
		t.Fatalf("NotConnected event must not seed; presence = %q, want %q", resp.Presence, presenceUnreachable)
	}
}

// R6 (concurrency lock) — the net-new last-seen map is written by the
// connectedness goroutine and read by the per-stream handler; this exercises
// concurrent RecordSeen + Lookup so `go test -race` catches an unguarded map.
func TestPresenceStore_ConcurrentRecordAndLookup(t *testing.T) {
	ps := NewPresenceStore()
	pids := make([]peer.ID, 8)
	for i := range pids {
		pids[i] = genDisconnectedPeerID(t)
	}

	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(2)
		go func() {
			defer wg.Done()
			for j := 0; j < 200; j++ {
				ps.RecordSeen(pids[j%len(pids)])
				ps.SetSelfPublished(pids[j%len(pids)], "foreground", time.Minute)
			}
		}()
		go func() {
			defer wg.Done()
			for j := 0; j < 200; j++ {
				_ = ps.Lookup(pids[j%len(pids)], j%2 == 0)
			}
		}()
	}
	wg.Wait()
}
