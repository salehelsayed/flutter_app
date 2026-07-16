package node

import (
	"fmt"
	"net"
	"sync"
	"testing"
	"time"
)

// FDC-S5 — Go-bridge concurrency design note, host-runnable read-concurrency
// proof.
//
// The design note's source read concluded that "the single Go bridge serializes,
// Future.wait gives no Go concurrency" is REFUTED for the warm/steady state: the
// node mutex (n.mu, an RWMutex) is taken only as a *read* lock around a pointer
// read and is released BEFORE any network I/O —
//   - SendMessageWithTransport: n.mu.RLock(); h := n.host; n.mu.RUnlock() then
//     openChatStreamForSend/writeFrame/readFrame (node.go:1385-1426)
//   - DialPeerWithTimeout:       n.mu.RLock(); h := n.host; n.mu.RUnlock() then
//     h.Connect(ctx, ai)         (node.go:1139-1174)
// so concurrent sends/dials/probes do not block each other on n.mu.
//
// These tests confirm that empirically. If n.mu serialized send/dial (e.g. if the
// lock were held across the network I/O), K concurrent dials would take ~K*timeout
// and a user send fired alongside K speculative "warm" dials would head-of-line
// block behind them. Because the heavy work runs lock-free, the K dials overlap
// and finish in ~1*timeout, and the user send overtakes the warm dials.
//
// Run under the race detector — that part of M1 is the only host-runnable piece
// of this spike, and -race also proves there is no data race on the shared node
// state across concurrent send/dial:
//
//	cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
//	  -run 'TestConcurrentSendDialNoSerialize|TestStartEmitsColdStartLockWindow' -race
//
// (GOTOOLCHAIN=go1.25.0 avoids the Go 1.26.x quic-go/crypto-tls session-ticket
// panic that affects this package — see project memory.)

// deadDialListener is a loopback TCP listener that accepts connections and holds
// them open without ever speaking libp2p. A dial to it completes the TCP connect
// and then blocks in the security/multistream handshake (the listener never
// replies) until the dial context deadline fires. That makes each dial cost a
// fixed ~timeout — a deterministic, hermetic stand-in for an "unreachable" peer
// with no dependency on real network routing.
type deadDialListener struct {
	ln       net.Listener
	mu       sync.Mutex
	conns    []net.Conn
	port     int
	accepted chan struct{}
}

func startDeadDialListener(t *testing.T) *deadDialListener {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("dead listener: %v", err)
	}
	d := &deadDialListener{
		ln:       ln,
		port:     ln.Addr().(*net.TCPAddr).Port,
		accepted: make(chan struct{}, 1),
	}
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return // listener closed
			}
			d.mu.Lock()
			d.conns = append(d.conns, c)
			d.mu.Unlock()
			select {
			case d.accepted <- struct{}{}:
			default:
			}
			// Drain and discard inbound bytes; never write a reply, so the
			// dialer's handshake read blocks until its context deadline.
			go func(c net.Conn) {
				buf := make([]byte, 256)
				for {
					if _, err := c.Read(buf); err != nil {
						return
					}
				}
			}(c)
		}
	}()
	return d
}

func (d *deadDialListener) addr() string {
	return fmt.Sprintf("/ip4/127.0.0.1/tcp/%d", d.port)
}

func (d *deadDialListener) close() {
	d.ln.Close()
	d.mu.Lock()
	for _, c := range d.conns {
		c.Close()
	}
	d.mu.Unlock()
}

func TestConcurrentSendDialNoSerialize(t *testing.T) {
	const (
		k         = 8
		dialBlock = 600 * time.Millisecond
	)
	// Serial execution (lock held across I/O) would take ~k*dialBlock. Concurrent
	// execution (lock released before I/O) takes ~1*dialBlock. The ceiling sits
	// far below the serial floor and far above the concurrent expectation, so it
	// is robust under the race detector and on loaded CI (the block is real-time
	// wait on a dial deadline, which -race does not slow).
	serialFloor := time.Duration(k) * dialBlock // ~4.8s
	concurrentCeiling := 3 * dialBlock          // 1.8s

	t.Run("concurrent_dials_are_not_serialized_at_node_mutex", func(t *testing.T) {
		nodeA := New(&testEventCollector{})
		if _, err := nodeA.Start(NodeConfig{
			PrivateKeyHex:  generateTestKey(t),
			RelayAddresses: []string{},
			AutoRegister:   false,
		}); err != nil {
			t.Fatalf("Start A: %v", err)
		}
		defer nodeA.Stop()

		dead := startDeadDialListener(t)
		defer dead.close()

		// K distinct unreachable peers. Distinct peer IDs avoid libp2p's
		// same-peer dial coalescing/backoff, so each is an independent dial.
		peers := make([]string, k)
		for i := range peers {
			peers[i] = generatePeerIDStr(t)
		}

		durations := make([]time.Duration, k)
		var wg sync.WaitGroup
		wg.Add(k)
		start := time.Now()
		for i := 0; i < k; i++ {
			go func(i int) {
				defer wg.Done()
				opStart := time.Now()
				// Error is expected (unreachable) and irrelevant — we measure timing.
				_ = nodeA.DialPeerWithTimeout(peers[i], []string{dead.addr()}, int(dialBlock.Milliseconds()))
				durations[i] = time.Since(opStart)
			}(i)
		}
		wg.Wait()
		elapsed := time.Since(start)

		// Decisive assertion: total wall-clock for K concurrent dials must be far
		// below the serial floor. If n.mu serialized them, elapsed ~= serialFloor.
		if elapsed >= concurrentCeiling {
			t.Fatalf("FDC-S5 read-concurrency REFUTED: %d concurrent dials took %v "+
				"(ceiling %v, serial floor %v) — n.mu appears to serialize send/dial",
				k, elapsed, concurrentCeiling, serialFloor)
		}

		// Corroborating: no single dial's duration stacked up behind the others.
		// Under serialization the last-scheduled dial's duration approaches
		// k*dialBlock; under concurrency every dial finishes within ~dialBlock.
		var maxDur time.Duration
		for _, d := range durations {
			if d > maxDur {
				maxDur = d
			}
		}
		// Anti-vacuous guard: every dial must actually have blocked near dialBlock.
		// If a future libp2p change fast-fails the loopback dial (dial gating, early
		// rejection), maxDur collapses to ~ms and the upper-bound assertions would
		// pass while exercising nothing. Fail loudly instead of logging a false
		// "CONFIRMED": the dials must sit in the blocking band [dialBlock/2, ceiling).
		if maxDur < dialBlock/2 {
			t.Fatalf("FDC-S5 microbench VACUOUS: slowest dial only took %v (< %v) — the dead-listener "+
				"did not block the dial, so concurrency was never actually tested in this environment",
				maxDur, dialBlock/2)
		}
		if maxDur >= concurrentCeiling {
			t.Fatalf("FDC-S5 read-concurrency REFUTED: slowest dial took %v "+
				"(ceiling %v) — dials stacked behind one another", maxDur, concurrentCeiling)
		}

		t.Logf("FDC-S5 CONFIRMED: %d concurrent dials finished in %v (slowest %v); "+
			"serial floor would be %v — n.mu does NOT serialize send/dial",
			k, elapsed, maxDur, serialFloor)
	})

	t.Run("user_send_not_head_of_line_blocked_by_warm_dials", func(t *testing.T) {
		holDialBlock := 3 * dialBlock
		nodeA := New(&testEventCollector{})
		if _, err := nodeA.Start(NodeConfig{
			PrivateKeyHex:  generateTestKey(t),
			RelayAddresses: []string{},
			AutoRegister:   false,
		}); err != nil {
			t.Fatalf("Start A: %v", err)
		}
		defer nodeA.Stop()

		nodeB := New(&testEventCollector{})
		if _, err := nodeB.Start(NodeConfig{
			PrivateKeyHex:  generateTestKey(t),
			RelayAddresses: []string{},
			AutoRegister:   false,
		}); err != nil {
			t.Fatalf("Start B: %v", err)
		}
		defer nodeB.Stop()

		// Establish a warm A->B connection so the user's send is a fast stream
		// open over the existing connection, not a fresh dial.
		peerIDB := nodeB.PeerId()
		var addrsB []string
		for _, a := range nodeB.Host().Addrs() {
			addrsB = append(addrsB, a.String())
		}
		if len(addrsB) == 0 {
			t.Fatal("node B has no addresses")
		}
		if err := nodeA.DialPeer(peerIDB, addrsB); err != nil {
			t.Fatalf("connect A->B: %v", err)
		}

		dead := startDeadDialListener(t)
		defer dead.close()

		// Fire K speculative "warm" dials that each block ~dialBlock. This is the
		// exact contention FDC-S5 asks about: does warmPeer/fastReprime work on the
		// single bridge head-of-line block the user's send?
		var warmWg sync.WaitGroup
		warmWg.Add(k)
		warmDone := make(chan struct{}, k)
		for i := 0; i < k; i++ {
			pid := generatePeerIDStr(t)
			go func(pid string) {
				defer warmWg.Done()
				_ = nodeA.DialPeerWithTimeout(pid, []string{dead.addr()}, int(holDialBlock.Milliseconds()))
				warmDone <- struct{}{}
			}(pid)
		}

		// Wait until at least one warm dial has reached the blocking listener, then
		// prove none has already completed. This keeps the HOL assertion causal even
		// on a loaded host where a fixed startup sleep is not a reliable barrier.
		select {
		case <-dead.accepted:
		case <-time.After(holDialBlock / 2):
			t.Fatal("warm dial never reached the blocking listener")
		}
		select {
		case <-warmDone:
			t.Fatal("warm dial completed before the user send started")
		default:
		}

		// Send a real message while the speculative work is demonstrably blocked.
		// The message
		// is a plain (non-chat-envelope) payload, so node B ACKs it immediately
		// (handleIncomingMessage, node.go:1680) rather than taking the deferred-ack
		// path — the send completes as soon as the bridge lets it run.
		sendStart := time.Now()
		_, acked, err := nodeA.SendMessage(peerIDB, `{"hello":"world"}`, 5000)
		sendElapsed := time.Since(sendStart)
		if err != nil {
			t.Fatalf("user send errored under concurrent warm dials: %v", err)
		}

		// If the send were serialized behind even the already-blocked warm dial, it
		// would approach holDialBlock. Keep a generous loaded-host margin while
		// still requiring it to finish in less than half that causal blocker.
		if sendElapsed >= holDialBlock/2 {
			t.Fatalf("FDC-S5 HOL-block REFUTED: user send took %v while %d warm dials "+
				"block ~%v each — the send was head-of-line blocked behind speculative warm work",
				sendElapsed, k, holDialBlock)
		}
		select {
		case <-warmDone:
			t.Fatal("FDC-S5 HOL proof invalid: a warm dial completed before the user send")
		default:
		}

		t.Logf("FDC-S5 CONFIRMED: user send completed in %v (acked=%v) while %d warm dials "+
			"each blocked ~%v — the user send is NOT head-of-line blocked", sendElapsed, acked, k, holDialBlock)
		warmWg.Wait()
	})
}

// TestStartEmitsColdStartLockWindow is the host-observable half of FDC-S5 M2: it
// asserts that Start emits the cold-start write-lock hold window so the device
// M2 run (a concurrent reader's n.mu.RLock wait, read from existing bridgeMs) has
// the window to correlate against. The window value itself is environment
// dependent; here we only lock in that the instrument is wired and non-negative.
func TestStartEmitsColdStartLockWindow(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	ev := waitForStartupPhase(t, collector, "start_lock_window", 2*time.Second)
	if ev == nil {
		t.Fatal("FDC-S5 M2: Start did not emit node:startup_timing{phase:start_lock_window}")
	}
	hold, ok := ev["lockHoldMs"].(float64)
	if !ok {
		t.Fatalf("FDC-S5 M2: lockHoldMs missing or not a number in %v", ev)
	}
	if hold < 0 {
		t.Fatalf("FDC-S5 M2: lockHoldMs should be >= 0, got %v", hold)
	}
	t.Logf("FDC-S5 M2: cold-start write-lock hold window = %.0fms", hold)
}

// waitForStartupPhase polls the collector until a node:startup_timing event with
// the given phase appears, or the timeout elapses. Needed because emitEvent is
// delivered asynchronously through the EventDispatcher.
func waitForStartupPhase(t *testing.T, c *testEventCollector, phase string, timeout time.Duration) map[string]interface{} {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		for _, ev := range c.collectEvents("node:startup_timing") {
			if p, _ := ev["phase"].(string); p == phase {
				return ev
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	return nil
}
