package node

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
)

func assertNoSendChecks(t *testing.T, n *Node) {
	t.Helper()
	n.sendConnectionsMu.Lock()
	defer n.sendConnectionsMu.Unlock()
	if len(n.sendConnections) != 0 {
		t.Fatalf("retained %d connection checks", len(n.sendConnections))
	}
}

func TestSendConnectionRecovery_ConcurrentTimeoutsCoalesce(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	const count = 8
	requests := make(chan network.Stream, count)
	releaseMessages := make(chan struct{})
	var releaseMessagesOnce sync.Once
	t.Cleanup(func() { releaseMessagesOnce.Do(func() { close(releaseMessages) }) })
	receiver.Host().SetStreamHandler(ChatProtocol, func(s network.Stream) {
		defer s.Reset()
		if _, err := readFrame(s); err == nil {
			requests <- s
			<-releaseMessages
		}
	})
	// Eight real send commands share an exact absolute deadline.
	start := time.Now()
	sender.sendNowHook = func() time.Time { return start }
	results := make(chan SendMessageResult, count)
	errorsCh := make(chan error, count)
	for range count {
		go func() {
			result, err := sender.SendMessageWithTransport(receiver.PeerId(), "synthetic-held-receipt", 1000)
			results <- result
			errorsCh <- err
		}()
	}
	for range count {
		if stream := awaitShared(t, requests); stream.Conn() != remoteB.Conn() {
			t.Fatal("concurrent sends escaped the shared connection")
		}
	}
	sharedProgress(t, b, remoteB, "during-concurrent-timeouts")
	for range count {
		if result := awaitShared(t, results); result.Acked {
			t.Fatal("invented ACK")
		}
		if err := awaitShared(t, errorsCh); err != nil {
			t.Fatalf("message did not reach ACK wait: %v", err)
		}
	}
	sender.sendNowHook = nil
	sharedProgress(t, b, remoteB, "after-concurrent-timeouts")
	assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), b.Conn())
	sender.sendConnectionsMu.Lock()
	if len(sender.sendConnections) != 1 || sender.sendConnections[b.Conn()] == nil || sender.sendConnections[b.Conn()].done != nil {
		t.Error("timeouts did not coalesce into one idle suspect")
	}
	sender.sendConnectionsMu.Unlock()

	// Hold only the fixture's protocol selection. Multistream already returned
	// its header, so a slow ping/application handler is never transport failure.
	entered := make(chan struct{}, count)
	releaseProbe := make(chan struct{})
	var releaseProbeOnce sync.Once
	t.Cleanup(func() { releaseProbeOnce.Do(func() { close(releaseProbe) }) })
	var probes atomic.Int32
	receiver.Host().RemoveStreamHandler(ping.ID)
	receiver.Host().SetStreamHandlerMatch("/test/held-ping-selection", func(p protocol.ID) bool {
		if p != ping.ID {
			return false
		}
		probes.Add(1)
		entered <- struct{}{}
		<-releaseProbe
		return true
	}, func(s network.Stream) { _ = s.Reset() })
	ctx, cancel := context.WithTimeout(sender.ctx, 2*time.Second)
	defer cancel()
	checked := make(chan error, count)
	go func() { checked <- sender.checkSendConnections(ctx, sender.Host(), receiver.Host().ID()) }()
	awaitShared(t, entered)
	for range count - 1 {
		go func() { checked <- sender.checkSendConnections(ctx, sender.Host(), receiver.Host().ID()) }()
	}
	sharedProgress(t, b, remoteB, "during-coalesced-check")
	releaseProbeOnce.Do(func() { close(releaseProbe) })
	for range count {
		if err := awaitShared(t, checked); err != nil {
			t.Fatal(err)
		}
	}
	if probes.Load() != 1 {
		t.Fatalf("simultaneous retries opened %d checks", probes.Load())
	}
	assertNoSendChecks(t, sender)
	sharedProgress(t, b, remoteB, "after-coalesced-check")
	releaseMessagesOnce.Do(func() { close(releaseMessages) })
}

func TestSendConnectionRecovery_CoalescedWaitKeepsOperationReserve(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	t.Cleanup(func() { releaseOnce.Do(func() { close(release) }) })
	var probes atomic.Int32
	receiver.Host().RemoveStreamHandler(ping.ID)
	receiver.Host().SetStreamHandlerMatch("/test/coalesced-reserve", func(p protocol.ID) bool {
		if p != ping.ID {
			return false
		}
		if probes.Add(1) == 1 {
			close(entered)
		}
		<-release
		return true
	}, func(s network.Stream) { _ = s.Reset() })
	ownerCtx, cancelOwner := context.WithTimeout(sender.ctx, 4*time.Second)
	defer cancelOwner()
	sender.noteSendTimeout(ownerCtx, sender.Host(), b.Conn(), context.DeadlineExceeded)
	ownerDone := make(chan error, 1)
	go func() { ownerDone <- sender.checkSendConnections(ownerCtx, sender.Host(), receiver.Host().ID()) }()
	awaitShared(t, entered)

	// The owner stays gated. This shorter operation must stop waiting at its
	// own check deadline, retaining time for useful I/O without another probe.
	waitCtx, cancelWait := context.WithTimeout(sender.ctx, 500*time.Millisecond)
	defer cancelWait()
	if err := sender.checkSendConnections(waitCtx, sender.Host(), receiver.Host().ID()); err != nil {
		t.Fatalf("coalesced wait consumed the operation budget: %v", err)
	}
	deadline, _ := waitCtx.Deadline()
	if remaining := time.Until(deadline); remaining < 100*time.Millisecond {
		t.Fatalf("coalesced wait left only %s for the operation", remaining)
	}
	select {
	case err := <-ownerDone:
		t.Fatalf("owner finished before fixture release: %v", err)
	default:
	}
	if probes.Load() != 1 {
		t.Fatalf("coalesced waiter opened %d probes", probes.Load())
	}
	sharedProgress(t, b, remoteB, "after-short-coalesced-wait")
	releaseOnce.Do(func() { close(release) })
	if err := awaitShared(t, ownerDone); err != nil {
		t.Fatal(err)
	}
	assertNoSendChecks(t, sender)
	assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), b.Conn())
}

func TestSendConnectionRecovery_StreamResetAndBackpressure(t *testing.T) {
	for _, backpressure := range []bool{false, true} {
		t.Run(map[bool]string{false: "reset", true: "backpressure"}[backpressure], func(t *testing.T) {
			sender := startLocalNodeForMultiRelayTest(t)
			receiver := startLocalNodeForMultiRelayTest(t)
			connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
			b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
			opened := make(chan network.Stream, 1)
			release := make(chan struct{})
			t.Cleanup(func() { close(release) })
			receiver.Host().SetStreamHandler(ChatProtocol, func(s network.Stream) {
				defer s.Reset()
				opened <- s
				if backpressure {
					<-release
				}
			})
			if backpressure {
				ctx, cancel := context.WithTimeout(sender.ctx, time.Second)
				defer cancel()
				s, err := sender.Host().NewStream(ctx, receiver.Host().ID(), ChatProtocol)
				if err != nil {
					t.Fatal(err)
				}
				defer s.Reset()
				_ = s.SetDeadline(time.Now().Add(300 * time.Millisecond))
				// Exceed the pinned yamux stream window without relying on
				// OS socket buffers or pretending a large frame is a message.
				done := make(chan error, 1)
				go func() { _, err := io.Copy(s, strings.NewReader(strings.Repeat("x", 1024*1024))); done <- err }()
				if remote := awaitShared(t, opened); remote.Conn() != remoteB.Conn() {
					t.Fatal("backpressured stream used another connection")
				}
				sharedProgress(t, b, remoteB, "during-stream-backpressure")
				err = awaitShared(t, done)
				if !isSendTimeout(err) {
					t.Fatalf("expected real stream write deadline: %v", err)
				}
				_ = s.Reset()
				sender.noteSendTimeout(ctx, sender.Host(), s.Conn(), err)
				if err := sender.checkSendConnections(ctx, sender.Host(), receiver.Host().ID()); err != nil {
					t.Fatal(err)
				}
			} else {
				result, _ := sender.SendMessageWithTransport(receiver.PeerId(), "synthetic-reset", 1000)
				if result.Acked {
					t.Fatal("reset claimed an ACK")
				}
				awaitShared(t, opened)
			}
			assertNoSendChecks(t, sender)
			assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), b.Conn())
			sharedProgress(t, b, remoteB, "after-stream-failure")
		})
	}
}

func TestSendConnectionRecovery_UnsupportedProbeAndQuietProtocol(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	receiver.Host().RemoveStreamHandler(ping.ID)
	receiver.Host().RemoveStreamHandler(QuietRecoveryChatProtocol)
	var alertable atomic.Int32
	receiver.Host().SetStreamHandler(ChatProtocol, func(s network.Stream) { alertable.Add(1); _ = s.Reset() })
	_ = sender.Host().Peerstore().RemoveProtocols(receiver.Host().ID(), QuietRecoveryChatProtocol)
	ctx, cancel := context.WithTimeout(sender.ctx, time.Second)
	defer cancel()
	sender.noteSendTimeout(ctx, sender.Host(), b.Conn(), context.DeadlineExceeded)
	if result, _ := sender.SendMessageWithNotificationPolicy(receiver.PeerId(), "quiet-synthetic", 1000, true); result.Acked {
		t.Fatal("unsupported quiet protocol did not fail closed")
	}
	if alertable.Load() != 0 {
		t.Fatal("unsupported quiet protocol downgraded to alertable delivery")
	}
	assertNoSendChecks(t, sender)
	sharedProgress(t, b, remoteB, "unsupported-protocols")
	assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), b.Conn())
}

func TestSendConnectionRecovery_CancelAndExpiredAdmission(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	var opens, recovery atomic.Int32
	sender.openChatStreamHook = func(context.Context, host.Host, peer.ID) (network.Stream, error) {
		opens.Add(1)
		return nil, fmt.Errorf("failed to open stream: %w", network.ErrResourceLimitExceeded)
	}
	sender.recoverPeerForSendHook = func(context.Context, host.Host, peer.ID, string) error {
		recovery.Add(1)
		return nil
	}
	for _, expired := range []bool{false, true} {
		var ctx context.Context
		var cancel context.CancelFunc
		if expired {
			ctx, cancel = context.WithDeadline(sender.ctx, time.Now().Add(-time.Second))
		} else {
			ctx, cancel = context.WithCancel(sender.ctx)
			cancel()
		}
		_, err := sender.openChatStreamForSendWithContext(ctx, sender.Host(), receiver.Host().ID(), receiver.PeerId(), time.Second)
		cancel()
		if err == nil {
			t.Fatal("canceled/expired operation succeeded")
		}
	}
	if opens.Load() != 0 || recovery.Load() != 0 {
		t.Fatal("canceled work opened streams or dialed")
	}
	ctx, cancel := context.WithTimeout(sender.ctx, time.Second)
	defer cancel()
	_, err := sender.openChatStreamForSendWithContext(ctx, sender.Host(), receiver.Host().ID(), receiver.PeerId(), time.Second)
	if !errors.Is(err, network.ErrResourceLimitExceeded) || opens.Load() != 1 || recovery.Load() != 0 {
		t.Fatal("resource rejection started transport recovery")
	}
	assertNoSendChecks(t, sender)
	sharedProgress(t, b, remoteB, "after-expired-admission")
}

// A second local host with the same test key initiates an independent inbound
// connection. This bypasses peer-level dial reuse without replacing libp2p.
func addSharedPeerConnection(t *testing.T, sender, receiver host.Host) (network.Stream, network.Stream) {
	t.Helper()
	h, err := libp2p.New(libp2p.Identity(receiver.Peerstore().PrivKey(receiver.ID())), libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { h.Close() })
	h.SetStreamHandler(ChatProtocol, func(s network.Stream) {
		defer s.Close()
		if _, err := readFrame(s); err == nil {
			_ = writeFrame(s, []byte(`{"ack":true}`))
		}
	})
	connectSharedNodes(t, h, sender, "tcp")
	return sharedTraffic(t, h, sender)
}

func TestSendConnectionRecovery_OpenSnapshotChanges(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	t.Cleanup(func() { releaseOnce.Do(func() { close(release) }) })
	sender.openChatStreamHook = func(context.Context, host.Host, peer.ID) (network.Stream, error) {
		close(entered)
		<-release
		return nil, context.DeadlineExceeded
	}
	ctx, cancel := context.WithTimeout(sender.ctx, 2*time.Second)
	defer cancel()
	done := make(chan error, 1)
	go func() { _, err := sender.openChatStream(ctx, sender.Host(), receiver.Host().ID()); done <- err }()
	awaitShared(t, entered)
	c, remoteC := addSharedPeerConnection(t, sender.Host(), receiver.Host())
	releaseOnce.Do(func() { close(release) })
	if err := awaitShared(t, done); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
	assertNoSendChecks(t, sender)
	if len(sender.Host().Network().ConnsToPeer(receiver.Host().ID())) != 2 {
		t.Fatal("connection snapshot control did not retain both connections")
	}
	sharedProgress(t, b, remoteB, "original-after-open-timeout")
	sharedProgress(t, c, remoteC, "successor-after-open-timeout")
}

func TestSendConnectionRecovery_BlackholePreservesOtherConnection(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	var targetAddress = receiver.Host().Addrs()[0]
	for _, addr := range receiver.Host().Addrs() {
		if strings.HasPrefix(addr.String(), "/ip4/") && strings.Contains(addr.String(), "/tcp/") && !strings.Contains(addr.String(), "/ws") {
			targetAddress = addr
			break
		}
	}
	proxy := newEstablishedPathProxy(t, targetAddress)
	if err := sender.DialPeerWithTimeout(receiver.PeerId(), []string{proxy.address.String()}, 3000); err != nil {
		t.Fatal(err)
	}
	// The pinned swarm prefers the connection with more streams. Keep two on
	// the IPv6 connection so the first actual send cannot escape the fault.
	a, remoteA := sharedTraffic(t, sender.Host(), receiver.Host())
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	dead := a.Conn()
	if dead != b.Conn() || !dead.RemoteMultiaddr().Equal(proxy.address) {
		t.Fatal("missing established IPv6 connection")
	}
	sharedProgress(t, a, remoteA, "before-IPv6-loss")
	sharedProgress(t, b, remoteB, "before-IPv6-loss")
	healthy, localHealthy := addSharedPeerConnection(t, sender.Host(), receiver.Host())
	if dead == localHealthy.Conn() || len(sender.Host().Network().ConnsToPeer(receiver.Host().ID())) != 2 {
		t.Fatal("missing independent same-peer healthy connection")
	}
	proxy.drop.Store(true)
	result, _ := sender.SendMessageWithTransport(receiver.PeerId(), "faulted-synthetic", 500)
	if result.Acked {
		t.Fatal("send escaped the established IPv6 fault")
	}
	sharedProgress(t, healthy, localHealthy, "during-other-connection-blackhole")
	ctx, cancel := context.WithTimeout(sender.ctx, time.Second)
	defer cancel()
	// Now bias the pinned swarm toward the healthy connection. A peer-level
	// ping would succeed there and incorrectly certify the suspect connection.
	// Keep these fixture streams open only through this bounded check.
	extraStreams := len(dead.GetStreams()) + 2 // include pinned identify/pubsub streams
	if extraStreams > 32 {
		t.Fatal("unexpected fixture stream population")
	}
	for range extraStreams {
		s, err := localHealthy.Conn().NewStream(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer s.Reset()
	}
	selected, err := sender.Host().Network().NewStream(network.WithNoDial(ctx, "fixture-selection"), receiver.Host().ID())
	if err != nil {
		t.Fatal(err)
	}
	if selected.Conn() != localHealthy.Conn() {
		t.Fatalf("fixture did not prefer healthy sibling: old=%d healthy=%d", len(dead.GetStreams()), len(localHealthy.Conn().GetStreams()))
	}
	_ = selected.Reset()
	// Concurrent recovery owners must share one check and one closure. The
	// healthy peer-level ping route must not certify the dead IPv6 connection.
	closed := make(chan struct{}, 2)
	notifiee := &network.NotifyBundle{DisconnectedF: func(_ network.Network, c network.Conn) {
		if c == dead {
			closed <- struct{}{}
		}
	}}
	sender.Host().Network().Notify(notifiee)
	defer sender.Host().Network().StopNotify(notifiee)
	done := make(chan error, 8)
	for range 8 {
		go func() { done <- sender.checkSendConnections(ctx, sender.Host(), receiver.Host().ID()) }()
	}
	for range 8 {
		if err := awaitShared(t, done); err != nil {
			t.Fatal(err)
		}
	}
	if !dead.IsClosed() || localHealthy.Conn().IsClosed() {
		t.Fatal("retirement did not isolate the dead connection")
	}
	awaitShared(t, closed)
	if result, err := sender.SendMessageWithTransport(receiver.PeerId(), "ordinary-after-fault", 1000); err != nil || !result.Acked {
		t.Fatalf("healthy connection ordinary send failed: ack=%v err=%v", result.Acked, err)
	}
	assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), localHealthy.Conn())
	sharedProgress(t, healthy, localHealthy, "after-dead-connection-retired")
	select {
	case <-closed:
		t.Fatal("competing recovery closures")
	default:
	}
	assertNoSendChecks(t, sender)
}

func TestSendConnectionRecovery_HardFailureAndSuccessor(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	sharedProgress(t, b, remoteB, "before-hard-failure")
	old := b.Conn()
	ctx, cancel := context.WithTimeout(sender.ctx, 2*time.Second)
	defer cancel()
	sender.noteSendTimeout(ctx, sender.Host(), old, context.DeadlineExceeded)
	// Fail the connection during the production send's receipt wait.
	hardFailure := make(chan struct{}, 1)
	receiver.Host().SetStreamHandler(ChatProtocol, func(s network.Stream) {
		if _, err := readFrame(s); err == nil {
			_ = s.Conn().Close()
			hardFailure <- struct{}{}
		}
	})
	if result, _ := sender.SendMessageWithTransport(receiver.PeerId(), "hard-failure", 1000); result.Acked {
		t.Fatal("hard failure invented an ACK")
	}
	awaitShared(t, hardFailure)
	_ = b.SetDeadline(time.Now().Add(time.Second))
	if _, err := b.Read(make([]byte, 1)); err == nil {
		t.Fatal("hard connection failure did not reach the sibling")
	}
	c, remoteC := addSharedPeerConnection(t, sender.Host(), receiver.Host())
	if err := sender.checkSendConnections(ctx, sender.Host(), receiver.Host().ID()); err != nil {
		t.Fatal(err)
	}
	sender.noteSendTimeout(ctx, sender.Host(), old, context.DeadlineExceeded)
	assertNoSendChecks(t, sender)
	sharedProgress(t, c, remoteC, "successor-after-hard-failure")
	if result, err := sender.SendMessageWithTransport(receiver.PeerId(), "after-hard-failure", 1000); err != nil || !result.Acked {
		t.Fatalf("hard failure retry: ack=%v err=%v", result.Acked, err)
	}
	assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), remoteC.Conn())
}

func TestSendConnectionRecovery_CanceledCheckReleasesWork(t *testing.T) {
	for _, stopNode := range []bool{false, true} {
		t.Run(fmt.Sprintf("stop=%v", stopNode), func(t *testing.T) {
			sender := startLocalNodeForMultiRelayTest(t)
			receiver := startLocalNodeForMultiRelayTest(t)
			connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
			b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
			originalHost := sender.Host()
			entered, release := make(chan struct{}), make(chan struct{})
			var releaseOnce sync.Once
			t.Cleanup(func() { releaseOnce.Do(func() { close(release) }) })
			receiver.Host().RemoveStreamHandler(ping.ID)
			receiver.Host().SetStreamHandlerMatch("/test/canceled-selection", func(p protocol.ID) bool {
				if p != ping.ID {
					return false
				}
				close(entered)
				<-release
				return true
			}, func(s network.Stream) { _ = s.Reset() })
			ctx, cancel := context.WithTimeout(sender.ctx, 2*time.Second)
			defer cancel()
			sender.noteSendTimeout(ctx, originalHost, b.Conn(), context.DeadlineExceeded)
			done := make(chan error, 1)
			go func() { done <- sender.checkSendConnections(ctx, originalHost, receiver.Host().ID()) }()
			awaitShared(t, entered)
			if stopNode {
				if err := sender.Stop(); err != nil {
					t.Fatal(err)
				}
			} else {
				cancel()
			}
			if err := awaitShared(t, done); !errors.Is(err, context.Canceled) {
				t.Fatalf("canceled check: %v", err)
			}
			releaseOnce.Do(func() { close(release) })
			if !stopNode {
				// An inconclusive suspect may remain for the next existing
				// retry, but the canceled check must retain no active work.
				sender.sendConnectionsMu.Lock()
				for _, check := range sender.sendConnections {
					if check.done != nil {
						t.Error("canceled check retained an active owner")
					}
				}
				sender.sendConnectionsMu.Unlock()
				assertOriginalSharedConnection(t, originalHost, receiver.Host().ID(), b.Conn())
				sharedProgress(t, b, remoteB, "after-canceled-check")
			} else {
				assertNoSendChecks(t, sender)
				// An obsolete host/owner may never check or dial a new session.
				if err := sender.checkSendConnections(context.Background(), originalHost, receiver.Host().ID()); !errors.Is(err, context.Canceled) {
					t.Fatalf("stopped owner resumed: %v", err)
				}
			}
		})
	}
}

type rejectedRecoveryStreamConn struct {
	network.Conn
	err error
}

func (c rejectedRecoveryStreamConn) NewStream(context.Context) (network.Stream, error) {
	return nil, c.err
}

func TestSendConnectionRecovery_ProbeAdmissionIsInconclusive(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	for _, err := range []error{context.DeadlineExceeded, context.Canceled, network.ErrResourceLimitExceeded, network.ErrResourceScopeClosed, network.ErrReset} {
		ctx, cancel := context.WithTimeout(sender.ctx, time.Second)
		responsive, unresponsive := checkSendConnectionResponse(ctx, rejectedRecoveryStreamConn{Conn: b.Conn(), err: err})
		cancel()
		if responsive || unresponsive {
			t.Fatalf("unadmitted stream classified connection liveness: %v", err)
		}
	}
	sharedProgress(t, b, remoteB, "after-probe-admission-failures")
}

func TestSendConnectionRecovery_PartialNegotiationResponseIsLiveness(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	t.Cleanup(func() { releaseOnce.Do(func() { close(release) }) })
	receiver.Host().RemoveStreamHandler(ping.ID)
	receiver.Host().SetStreamHandlerMatch("/test/slow-selection", func(p protocol.ID) bool {
		if p != ping.ID {
			return false
		}
		close(entered)
		<-release
		return true
	}, func(s network.Stream) { _ = s.Reset() })
	ctx, cancel := context.WithTimeout(sender.ctx, time.Second)
	defer cancel()
	sender.noteSendTimeout(ctx, sender.Host(), b.Conn(), context.DeadlineExceeded)
	done := make(chan error, 1)
	go func() { done <- sender.checkSendConnections(ctx, sender.Host(), receiver.Host().ID()) }()
	awaitShared(t, entered)
	sharedProgress(t, b, remoteB, "during-slow-protocol-selection")
	// Keep selection held through the check's read deadline. The returned
	// multistream header is enough evidence; no ping payload/ACK is necessary.
	if err := awaitShared(t, done); err != nil {
		t.Fatal(err)
	}
	assertNoSendChecks(t, sender)
	sharedProgress(t, b, remoteB, "after-partial-negotiation-timeout")
	assertOriginalSharedConnection(t, sender.Host(), receiver.Host().ID(), b.Conn())
	releaseOnce.Do(func() { close(release) })
}

type failedProbeWriteStream struct {
	network.Stream
	protocolErr error
	writes      int
}

func (s *failedProbeWriteStream) SetProtocol(protocol.ID) error { return s.protocolErr }
func (s *failedProbeWriteStream) SetDeadline(time.Time) error   { return nil }
func (s *failedProbeWriteStream) Reset() error                  { return nil }
func (s *failedProbeWriteStream) Read([]byte) (int, error) {
	return 0, context.DeadlineExceeded
}
func (s *failedProbeWriteStream) Write(p []byte) (int, error) {
	s.writes++
	return min(1, len(p)), context.DeadlineExceeded
}

type suppliedRecoveryStreamConn struct {
	network.Conn
	stream network.Stream
}

func (c suppliedRecoveryStreamConn) NewStream(context.Context) (network.Stream, error) {
	return c.stream, nil
}

func TestSendConnectionRecovery_PartialWriteAndProtocolRejectionAreInconclusive(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	connectSharedNodes(t, sender.Host(), receiver.Host(), "tcp")
	b, remoteB := sharedTraffic(t, sender.Host(), receiver.Host())
	for _, protocolErr := range []error{nil, network.ErrResourceLimitExceeded} {
		ctx, cancel := context.WithTimeout(sender.ctx, time.Second)
		stream := &failedProbeWriteStream{protocolErr: protocolErr}
		responsive, unresponsive := checkSendConnectionResponse(ctx, suppliedRecoveryStreamConn{Conn: b.Conn(), stream: stream})
		cancel()
		if responsive || unresponsive {
			t.Fatalf("incomplete request classified connection liveness: protocol error=%v", protocolErr)
		}
		if protocolErr != nil && stream.writes != 0 {
			t.Fatal("protocol resource rejection still sent a probe")
		}
	}
	sharedProgress(t, b, remoteB, "after-incomplete-probes")
}

func TestSendConnectionRecovery_InboxCheckDoesNotRenewAttemptBudget(t *testing.T) {
	for _, protected := range []bool{false, true} {
		t.Run(fmt.Sprint(protected), func(t *testing.T) {
			inboxEntered, probeEntered := make(chan struct{}, 1), make(chan struct{}, 1)
			release := make(chan struct{})
			var releaseOnce sync.Once
			relay := startAckCustodyTestRelay(t, func(inboxRequest) string {
				inboxEntered <- struct{}{}
				<-release
				return ""
			})
			relay.host.RemoveStreamHandler(ping.ID)
			relay.host.SetStreamHandlerMatch("/test/inbox-budget", func(p protocol.ID) bool {
				if p != ping.ID {
					return false
				}
				probeEntered <- struct{}{}
				<-release
				return true
			}, func(s network.Stream) { _ = s.Reset() })
			sender := startLocalNodeForMultiRelayTest(t)
			configureAckCustodyTestRelays(t, sender, relay)
			connectSharedNodes(t, sender.Host(), relay.host, "tcp")
			b, remoteB := sharedTraffic(t, sender.Host(), relay.host)
			t.Cleanup(func() { releaseOnce.Do(func() { close(release) }) })
			ctx, cancel := context.WithTimeout(sender.ctx, time.Second)
			defer cancel()
			sender.noteSendTimeout(ctx, sender.Host(), b.Conn(), context.DeadlineExceeded)
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
			awaitShared(t, probeEntered)
			// The handshake consumes half the existing 500ms budget; its
			// partial response keeps the connection while the actual store
			// must use only the remaining interval for the delayed receipt.
			awaitShared(t, inboxEntered)
			if err := awaitShared(t, done); err == nil {
				t.Fatal("uncommitted inbox request accepted")
			}
			if elapsed := time.Since(start); elapsed < 450*time.Millisecond || elapsed > 650*time.Millisecond {
				t.Fatalf("check renewed inbox attempt budget: %v", elapsed)
			}
			sharedProgress(t, b, remoteB, "after-shared-inbox-budget")
			releaseOnce.Do(func() { close(release) })
		})
	}
}
