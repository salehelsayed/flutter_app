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

// R1b — a peer that has been CONNECTED longer than the TTL still reports
// reachable with a FRESH ageMs (< TTL). The connectedness-seeded last-seen is
// only stamped on a NotConnected->Connected transition (EvtPeerConnectednessChanged
// is transition-only), so a steadily-connected peer's last-seen ages past the
// TTL — but a live socket means "seen now", so ageMs must NOT report that stale
// record age (locks `reachable requires ageMs < relayTTL` for the common case).
func TestPresenceGet_ConnectedPeerReportsFreshAgeDespiteStaleLastSeen(t *testing.T) {
	env, _ := newPresenceTestEnv(t)

	base := time.Now()
	cur := base
	env.presence.now = func() time.Time { return cur }

	// Seed last-seen at the connect transition, then let it age WELL past the TTL
	// while the socket stays connected (mocknet connection persists; only the
	// store clock advances).
	env.presence.RecordSeen(env.sender.ID())
	cur = base.Add(relayPresenceTTL + 2*time.Minute)

	resp, _ := sendPresenceGet(t, env, env.sender.ID().String())
	if resp.Presence != presenceReachable {
		t.Fatalf("presence = %q, want %q (still connected)", resp.Presence, presenceReachable)
	}
	if resp.AgeMs == nil || *resp.AgeMs >= relayPresenceTTL.Milliseconds() {
		t.Fatalf("connected ageMs = %v, want a FRESH value < %d (a live socket is seen-now, not the stale last-seen)",
			resp.AgeMs, relayPresenceTTL.Milliseconds())
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

// ---------------------------------------------------------------------------
// FDC-09 — `presence_set` self-publish WRITE (Option C, FDC-S3-locked).
//
// FDC-08 created the shared presence store (SetSelfPublished + a Lookup resolver
// that already PREFERS a fresh self-published state). FDC-09 adds the additive
// `presence_set` inbox action that wires a peer's authenticated self-publish to
// that write seam. A self-publish records BOTH the foreground/background state
// AND seeds the connectedness last-seen, so a TTL'd self-state degrades to
// `unknown` via the SAME R5 freshness path the last-seen uses — never silently
// `unreachable`. The action targets the AUTHENTICATED stream peer only (a peer
// can publish ITS OWN presence, never another's).
// ---------------------------------------------------------------------------

// sendPresenceSet drives a `presence_set` request to the server over a real
// stream from env.sender (the authenticated self-publisher) and returns the
// decoded response. The relay derives the subject peer from the stream's
// authenticated RemotePeer, NOT from any request field (anti-spoof).
func sendPresenceSet(t *testing.T, env *inboxStreamEnv, state string, ttlMs int64) inboxResponse {
	t.Helper()
	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open presence_set stream: %v", err)
	}
	defer stream.Close()

	sendInboxReq(t, stream, inboxRequest{
		Action:   "presence_set",
		Metadata: map[string]interface{}{"state": state, "ttlMs": ttlMs},
	})

	data, err := readFrame(stream)
	if err != nil {
		t.Fatalf("read presence_set frame: %v", err)
	}
	var resp inboxResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("decode presence_set response: %v", err)
	}
	return resp
}

// TC-09-01 — `presence_set` is an additive action that stores the caller's
// self-published foreground state. RED on HEAD: the action is unknown -> the
// `default` dispatch arm answers "Unknown action: presence_set" (Status ERROR).
// The self-state is ISOLATED from the connectedness-seeded last-seen by reading
// at an age PAST the last-seen TTL but WITHIN the (deliberately longer) self
// TTL: only a fresh self-published state can keep the peer reachable there.
func TestPresenceSet_AdditiveAction_StoresState(t *testing.T) {
	env, _ := newPresenceTestEnv(t)

	base := time.Now()
	cur := base
	env.presence.now = func() time.Time { return cur }

	// Self TTL deliberately LONGER than the connectedness last-seen TTL.
	resp := sendPresenceSet(t, env, "foreground", (relayPresenceTTL + 10*time.Minute).Milliseconds())
	if resp.Status != "OK" {
		t.Fatalf("presence_set status = %q, want OK (additive action must be accepted)", resp.Status)
	}

	// Advance past the connectedness last-seen TTL but within the self TTL.
	cur = base.Add(relayPresenceTTL + time.Minute)

	// Read the store with connected=false: reachable ONLY if the self-state write
	// landed (a stale last-seen alone would read `unknown`, an absent state
	// `unreachable`).
	res := env.presence.Lookup(env.sender.ID(), false)
	if res.presence != presenceReachable {
		t.Fatalf("self-published presence = %q, want %q (presence_set must store the self-state)", res.presence, presenceReachable)
	}
}

// TC-09-02 — a self-published state degrades to `unknown` after its TTL (never
// silently `unreachable`), via the SAME R5 freshness rule the last-seen uses
// (FDC-09's write feeds the same expiresAt). RED on HEAD: no presence_set action.
func TestPresenceSet_TTLExpiry_DegradesToUnknown(t *testing.T) {
	env, _ := newPresenceTestEnv(t)

	base := time.Now()
	cur := base
	env.presence.now = func() time.Time { return cur }

	resp := sendPresenceSet(t, env, "background", relayPresenceTTL.Milliseconds())
	if resp.Status != "OK" {
		t.Fatalf("presence_set status = %q, want OK", resp.Status)
	}

	// Past BOTH the self TTL and the last-seen TTL.
	cur = base.Add(relayPresenceTTL + time.Second)
	res := env.presence.Lookup(env.sender.ID(), false)
	if res.presence != presenceUnknown {
		t.Fatalf("expired self-published presence = %q, want %q (must never silently be unreachable)", res.presence, presenceUnknown)
	}
}

// TC-09b-01 — a fresh self-published `background` resolves to `unreachable`
// (§6.3 inbox-first + push-to-wake), while `foreground` resolves to `reachable`
// (direct-race + lazy inbox). The relay consumes the self-published fg/bg
// INTERNALLY to pick the COARSE value; the response still exposes no fg/bg field
// (locked separately by TestPresenceResponseNeverClaimsForeground). Disconnected
// peers (connected=false) so the connectedness branch cannot mask the self-state
// branch. RED on HEAD: rule #1 folds ANY fresh self-state to reachable.
func TestPresenceSet_BackgroundResolvesUnreachable_ForegroundReachable(t *testing.T) {
	env, _ := newPresenceTestEnv(t)

	fg := genDisconnectedPeerID(t)
	bg := genDisconnectedPeerID(t)
	env.presence.SetSelfPublished(fg, "foreground", relayPresenceTTL)
	env.presence.SetSelfPublished(bg, "background", relayPresenceTTL)

	if resp, _ := sendPresenceGet(t, env, fg.String()); resp.Presence != presenceReachable {
		t.Fatalf("fresh foreground self-state presence = %q, want %q", resp.Presence, presenceReachable)
	}
	if resp, _ := sendPresenceGet(t, env, bg.String()); resp.Presence != presenceUnreachable {
		t.Fatalf("fresh background self-state presence = %q, want %q (§6.3 inbox-first; HEAD wrongly folds bg->reachable)", resp.Presence, presenceUnreachable)
	}
}

// TC-09-03 (NET-REL-07) — an UNIMPLEMENTED action degrades via the stable
// `default` arm to the exact "Unknown action: <action>" text. This locks the
// contract an OLD relay returns for `presence_set` (which a new client maps to
// "presence unsupported -> skip", Dart TC-09-08). On THIS build presence_set is
// known, so the stable default-arm format is exercised with a sentinel action.
func TestPresenceSet_BackCompat_OldRelayUnknownAction(t *testing.T) {
	env, _ := newPresenceTestEnv(t)

	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open stream: %v", err)
	}
	defer stream.Close()

	sendInboxReq(t, stream, inboxRequest{Action: "presence_set_UNIMPLEMENTED_v2"})
	resp := recvInboxResp(t, stream)
	if resp.Status != "ERROR" {
		t.Fatalf("status = %q, want ERROR for an unknown action", resp.Status)
	}
	if want := "Unknown action: presence_set_UNIMPLEMENTED_v2"; resp.Error != want {
		t.Fatalf("error = %q, want %q (stable default-arm contract for NET-REL-07)", resp.Error, want)
	}
}

// TC-09-09 — the FDC-09 `presence_set` WRITE (self-state + last-seen seed) is a
// net-new third concurrent accessor of the shared presence map, alongside
// FDC-08's connectedness write (RecordSeen) and the presence_get read (Lookup).
// `go test -race ./...` must stay clean; dropping the store's mutex re-reds this.
func TestPresenceStore_PresenceSetWriteRaceClean(t *testing.T) {
	ps := NewPresenceStore()
	pids := make([]peer.ID, 8)
	for i := range pids {
		pids[i] = genDisconnectedPeerID(t)
	}

	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(3)
		// FDC-09 presence_set write path (self-state + last-seen seed — exactly
		// what handlePresenceSet performs).
		go func() {
			defer wg.Done()
			for j := 0; j < 200; j++ {
				p := pids[j%len(pids)]
				ps.SetSelfPublished(p, "foreground", relayPresenceTTL)
				ps.RecordSeen(p)
			}
		}()
		// FDC-08 connectedness write.
		go func() {
			defer wg.Done()
			for j := 0; j < 200; j++ {
				ps.RecordSeen(pids[j%len(pids)])
			}
		}()
		// presence_get read + TTL expiry evaluation.
		go func() {
			defer wg.Done()
			for j := 0; j < 200; j++ {
				_ = ps.Lookup(pids[j%len(pids)], j%2 == 0)
			}
		}()
	}
	wg.Wait()
}
