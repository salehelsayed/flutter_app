package node

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	ma "github.com/multiformats/go-multiaddr"
)

const sharedTrafficProtocol protocol.ID = "/mknoon/test/shared-traffic/1"

func awaitShared[T any](t *testing.T, ch <-chan T) T {
	t.Helper()
	select {
	case value := <-ch:
		return value
	case <-time.After(6 * time.Second):
		t.Fatal("fixture synchronization timed out")
		var zero T
		return zero
	}
}

// Both ends are real negotiated streams. Tests assert connection identity at
// both hosts; opening a replacement stream/connection cannot satisfy progress.
func sharedTraffic(t *testing.T, sender, receiver host.Host) (network.Stream, network.Stream) {
	t.Helper()
	incoming := make(chan network.Stream, 1)
	receiver.SetStreamHandler(sharedTrafficProtocol, func(s network.Stream) { incoming <- s })
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	s, err := sender.NewStream(network.WithNoDial(ctx, "shared-connection-fixture"), receiver.ID(), sharedTrafficProtocol)
	if err != nil {
		t.Fatal(err)
	}
	// Force lazy multistream negotiation before waiting for the handler.
	if err := s.SetDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	if err := writeFrame(s, []byte("ready")); err != nil {
		t.Fatal(err)
	}
	r := awaitShared(t, incoming)
	t.Cleanup(func() { _ = s.Reset(); _ = r.Reset() })
	if err := r.SetDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err := readFrame(r); err != nil {
		t.Fatal(err)
	}
	return s, r
}

func sharedProgress(t *testing.T, s, r network.Stream, phase string) {
	t.Helper()
	if err := s.SetDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	if err := r.SetDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	for _, pair := range [][2]network.Stream{{s, r}, {r, s}} {
		want := []byte("bounded-synthetic-" + phase)
		if err := writeFrame(pair[0], want); err != nil {
			t.Fatalf("sibling write %s: %v", phase, err)
		}
		got, err := readFrame(pair[1])
		if err != nil || string(got) != string(want) {
			t.Fatalf("sibling progress %s: bytes match=%v err=%v", phase, string(got) == string(want), err)
		}
	}
}

func assertOriginalSharedConnection(t *testing.T, h host.Host, pid peer.ID, original network.Conn) {
	t.Helper()
	conns := h.Network().ConnsToPeer(pid)
	if original.IsClosed() || len(conns) != 1 || conns[0] != original {
		t.Fatal("original shared connection was closed or replaced")
	}
}

func connectSharedNodes(t *testing.T, sender, receiver host.Host, transport string) {
	t.Helper()
	var addresses []ma.Multiaddr
	for _, address := range receiver.Addrs() {
		if (transport == "tcp" && strings.Contains(address.String(), "/tcp/") && !strings.Contains(address.String(), "/ws")) ||
			(transport == "quic" && strings.Contains(address.String(), "/quic-v1")) {
			addresses = append(addresses, address)
		}
	}
	if len(addresses) == 0 {
		t.Fatal("fixture transport unavailable")
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := sender.Connect(ctx, peer.AddrInfo{ID: receiver.ID(), Addrs: addresses}); err != nil {
		t.Fatal(err)
	}
}

type heldCommitCallback struct{ events chan map[string]interface{} }

func (c *heldCommitCallback) OnEvent(raw string) {
	var event struct {
		Event string                 `json:"event"`
		Data  map[string]interface{} `json:"data"`
	}
	if json.Unmarshal([]byte(raw), &event) == nil && event.Event == "message:received" {
		c.events <- event.Data
	}
}

func commitSharedMessage(t *testing.T, receiver *Node, event map[string]interface{}, path string) {
	t.Helper()
	nonce, ok := event["confirmNonce"].(string)
	if !ok || nonce == "" {
		t.Fatal("real message bypassed deferred application commit")
	}
	// Synthetic application commit, explicitly before ResolveDirectConfirm.
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString(event["content"].(string)); err != nil {
		t.Fatal(err)
	}
	if err := f.Sync(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	receiver.ResolveDirectConfirm(nonce, true)
}

func TestSendMessage_SlowCommitPreservesSharedConnection(t *testing.T) {
	for _, tc := range []struct {
		quiet     bool
		transport string
	}{{false, "tcp"}, {true, "tcp"}, {false, "quic"}, {true, "quic"}} {
		t.Run(fmt.Sprintf("%s/quiet=%v", tc.transport, tc.quiet), func(t *testing.T) {
			quiet := tc.quiet
			sender := startLocalNodeForMultiRelayTest(t)
			callback := &heldCommitCallback{events: make(chan map[string]interface{}, 4)}
			receiver := New(callback)
			receiver.hermeticLocalNetworkForTests = true
			// Fixture-only hold beyond the unchanged 3s sender ACK reserve.
			receiver.directConfirmTimeoutOverride = 10 * time.Second
			if _, err := receiver.Start(NodeConfig{PrivateKeyHex: generateTestKey(t), RelayAddresses: []string{}, AutoRegister: false}); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { receiver.Stop() })
			opened := make(chan network.Stream, 4)
			finished := make(chan struct{}, 4)
			for _, p := range []protocol.ID{ChatProtocol, QuietRecoveryChatProtocol} {
				receiver.Host().SetStreamHandler(p, func(s network.Stream) {
					opened <- s
					receiver.handleIncomingMessage(s)
					finished <- struct{}{}
				})
			}
			connectSharedNodes(t, sender.Host(), receiver.Host(), tc.transport)
			b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
			original := b.Conn()
			assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), original)
			sharedProgress(t, b, remoteB, "before")
			const wire = `{"type":"chat_message","version":"2","id":"held-commit","encrypted":{"ciphertext":"immutable-synthetic"}}`
			type outcome struct {
				result SendMessageResult
				err    error
			}
			done := make(chan outcome, 1)
			start := time.Now()
			go func() {
				result, err := sender.SendMessageWithNotificationPolicy(receiver.PeerId(), wire, 4000, quiet)
				done <- outcome{result, err}
			}()
			a := awaitShared(t, opened)
			event := awaitShared(t, callback.events)
			t.Cleanup(func() { receiver.ResolveDirectConfirm(event["confirmNonce"].(string), false) })
			if a.Conn() != remoteB.Conn() || a.Conn().RemotePeer() != sender.Host().ID() || original.RemotePeer() != receiver.Host().ID() {
				t.Fatal("message and independent traffic did not share the authenticated connection")
			}
			localMessage := false
			for _, stream := range original.GetStreams() {
				if stream.Protocol() == a.Protocol() && stream.Conn() == original {
					localMessage = true
				}
			}
			if !localMessage {
				t.Fatal("sender's message stream is not registered on the original connection")
			}
			if event["content"] != wire || (event["quietRecovery"] == true) != quiet {
				t.Fatal("message bytes or quiet intent changed")
			}
			sharedProgress(t, b, remoteB, "during-uncommitted-message")
			select {
			case <-done:
				t.Fatal("send finished before its ACK wait")
			default:
			}
			result := awaitShared(t, done)
			elapsed := time.Since(start)
			if result.err != nil || result.result.Acked || result.result.Reply != "" || elapsed < CommittedAckReserve || elapsed > 4500*time.Millisecond {
				t.Fatalf("slow commit result: ack=%v err=%v elapsed=%v", result.result.Acked, result.err, elapsed)
			}
			sharedProgress(t, b, remoteB, "after-ACK-timeout")
			assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), original)
			commitSharedMessage(t, receiver, event, filepath.Join(t.TempDir(), "committed.json"))
			awaitShared(t, finished)
			go func() {
				result, err := sender.SendMessageWithNotificationPolicy(receiver.PeerId(), wire, 4000, false)
				done <- outcome{result, err}
			}()
			later := awaitShared(t, opened)
			if later.Conn() != remoteB.Conn() {
				t.Fatal("ordinary send used a replacement connection")
			}
			commitSharedMessage(t, receiver, awaitShared(t, callback.events), filepath.Join(t.TempDir(), "later.json"))
			if next := awaitShared(t, done); next.err != nil || !next.result.Acked {
				t.Fatalf("later committed send failed: ack=%v err=%v", next.result.Acked, next.err)
			}
			awaitShared(t, finished)
			sharedProgress(t, b, remoteB, "after-ordinary-send")
			assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), original)
		})
	}
}

func TestInboxStore_SlowReceiptPreservesSharedConnection(t *testing.T) {
	for _, protected := range []bool{false, true} {
		t.Run(fmt.Sprint(protected), func(t *testing.T) {
			entered := make(chan struct{}, 4)
			release := make(chan struct{})
			var releaseOnce sync.Once
			relay := startAckCustodyTestRelay(t, func(inboxRequest) string {
				entered <- struct{}{}
				<-release // fixture-local durable store/receipt delay
				return `{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v1"}`
			})
			t.Cleanup(func() { releaseOnce.Do(func() { close(release) }) })
			sender := startLocalNodeForMultiRelayTest(t)
			configureAckCustodyTestRelays(t, sender, relay)
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			if err := sender.Host().Connect(ctx, peer.AddrInfo{ID: relay.host.ID(), Addrs: relay.host.Addrs()}); err != nil {
				t.Fatal(err)
			}
			b, remoteB := sharedTraffic(t, sender.Host(), relay.host)
			original := b.Conn()
			sharedProgress(t, b, remoteB, "before-inbox")
			done := make(chan error, 1)
			start := time.Now()
			go func() {
				var err error
				if protected {
					_, err = sender.InboxStoreAckCustodyDetailedWithNotificationPolicy("recipient", "synthetic", 500, "", CustodyKindDirectTextV108, 0, false, true)
				} else {
					_, err = sender.InboxStoreDetailedWithNotificationPolicy("recipient", "synthetic", 500, "", false, true)
				}
				done <- err
			}()
			awaitShared(t, entered)
			for _, h := range []host.Host{sender.Host(), relay.host} {
				if len(h.Network().Conns()) != 1 {
					t.Fatal("inbox fixture has an alternative connection")
				}
			}
			sharedProgress(t, b, remoteB, "during-inbox-receipt")
			if err := awaitShared(t, done); err == nil {
				t.Fatal("slow receipt falsely accepted custody")
			}
			if elapsed := time.Since(start); elapsed < 450*time.Millisecond || elapsed > 800*time.Millisecond {
				t.Fatalf("inbox receipt exceeded its existing attempt budget: %v", elapsed)
			}
			for _, req := range relay.snapshotActions() {
				if req.Message != "synthetic" || req.To != "recipient" || !req.QuietRecovery || !req.SuppressNotification {
					t.Fatal("slow receipt changed immutable request or quiet policy")
				}
			}
			sharedProgress(t, b, remoteB, "after-inbox-timeout")
			assertOriginalSharedConnection(t, sender.Host(), relay.host.ID(), original)
			releaseOnce.Do(func() { close(release) })
			if result, err := sender.InboxStoreDetailedWithNotificationPolicy("recipient", "ordinary-later", 1000, "", false, false); err != nil || result.StoreStatus != "stored" {
				t.Fatalf("later ordinary store: status=%s err=%v", result.StoreStatus, err)
			}
			sharedProgress(t, b, remoteB, "after-ordinary-inbox-store")
			assertOriginalSharedConnection(t, sender.Host(), relay.host.ID(), original)
		})
	}
}
