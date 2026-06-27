package node

// FDC-S2 — QUIC identify-handshake re-validation (Spike / Measurement).
//
// Question (spike doc): on the current stack — go-mknoon go-libp2p v0.39.1 /
// quic-go v0.49.0 — does the historical "QUIC identify handshake hang"
// (proposal §5) still occur on a peer↔peer LAN-direct QUIC dial, and does the
// relay-QUIC control still complete identify within budget?
//
// This is a STANDALONE harness (the method's "test ... with a client"). It does
// NOT modify production node.go/relay. It builds libp2p hosts that mirror the
// production transport/security defaults from node.go:355-364 — QUIC-v1 + TCP +
// WS transports (libp2p defaults), Noise/TLS security, ConnectionManager(10,100),
// EnableRelay, EnableHolePunching, NATPortMap, ForceReachabilityPrivate (the
// test seam may swap ForceReachabilityPublic), and AddrsFactory(filterAddresses).
// The only deliberate deltas vs Start(): no injected holepunch tracer (the
// production tracer only observes, never changes connection policy) and no
// AutoRelay static-relay wiring (we dial targets directly via host.Connect, so
// the relay-warmup block at node.go:365-376 is irrelevant to the identify
// question).
//
// Tests:
//   M0 — relay-QUIC identify control (hermetic local QUIC relay).         host-runnable
//   M1 — peer↔peer direct LAN QUIC/TCP identify, N iters, private+public. host-runnable, HEADLINE
//   M2 — cross-version skew: dial the prod relay (v0.38.2) over QUIC.      network-gated (skips offline)
//
// Run (Go 1.26.x panics on quic-go session ticket — pin the declared toolchain):
//   cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
//       -run TestQuicIdentifyRevalidation -count=1 -v
//   (FDC_S2_ITERS overrides N for M1; default 100. -short skips all three.)

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/net/connmgr"
	ma "github.com/multiformats/go-multiaddr"
)

// ---------------------------------------------------------------------------
// Harness host — mirrors production hostOpts (node.go:355-364).
// ---------------------------------------------------------------------------

func s2BuildHost(t *testing.T, listenAddrs []string, forcePublic bool) host.Host {
	t.Helper()
	priv, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("s2: generate key: %v", err)
	}
	cm, err := connmgr.NewConnManager(10, 100, connmgr.WithGracePeriod(time.Minute))
	if err != nil {
		t.Fatalf("s2: conn manager: %v", err)
	}
	// Reachability: production ships ForceReachabilityPrivate(); the seam swaps
	// public to isolate whether private-reachability + AddrsFactory filtering is
	// implicated in any stall (decision-criteria "reachability-private implicated").
	reach := libp2p.ForceReachabilityPrivate()
	if forcePublic {
		reach = libp2p.ForceReachabilityPublic()
	}
	h, err := libp2p.New(
		libp2p.Identity(priv),
		libp2p.ListenAddrStrings(listenAddrs...),
		libp2p.ConnectionManager(cm),
		libp2p.EnableRelay(),
		libp2p.EnableHolePunching(),
		libp2p.NATPortMap(),
		reach,
		libp2p.AddrsFactory(filterAddresses), // production address filter (strips loopback from ANNOUNCE only)
	)
	if err != nil {
		t.Fatalf("s2: new host: %v", err)
	}
	return h
}

// s2PickListenAddr returns the host's concrete bound listen address for the
// requested transport. It reads Network().ListenAddresses() (the raw swarm
// listen addrs) NOT host.Addrs() — the latter is run through
// AddrsFactory(filterAddresses) which strips the loopback addrs we must dial.
func s2PickListenAddr(t *testing.T, h host.Host, kind string) ma.Multiaddr {
	t.Helper()
	for _, a := range h.Network().ListenAddresses() {
		s := a.String()
		switch kind {
		case "quic":
			if strings.Contains(s, "/quic-v1") {
				return a
			}
		case "tcp":
			if strings.Contains(s, "/tcp/") && !strings.Contains(s, "/ws") && !strings.Contains(s, "quic") {
				return a
			}
		}
	}
	t.Fatalf("s2: no %s listen addr among %v", kind, h.Network().ListenAddresses())
	return nil
}

// ---------------------------------------------------------------------------
// Identify wait — subscribe BEFORE dialing so the post-connect identify events
// are never missed. The original "hang" was the handshake never COMPLETING, so
// EvtPeerIdentificationCompleted is the exact signal.
// ---------------------------------------------------------------------------

func s2WaitIdentify(sub event.Subscription, want peer.ID, done <-chan struct{}) (bool, string) {
	for {
		select {
		case ev, ok := <-sub.Out():
			if !ok {
				return false, "sub-closed"
			}
			switch e := ev.(type) {
			case event.EvtPeerIdentificationCompleted:
				if e.Peer == want {
					return true, ""
				}
			case event.EvtPeerIdentificationFailed:
				if e.Peer == want {
					return false, "identify-failed: " + e.Reason.Error()
				}
			}
		case <-done:
			return false, "deadline"
		}
	}
}

// ---------------------------------------------------------------------------
// Records & stats.
// ---------------------------------------------------------------------------

type s2Probe struct {
	Transport     string `json:"transport"`
	Reachability  string `json:"reachability"`
	Iteration     int    `json:"iteration"`
	DialMs        int64  `json:"dialMs"`
	IdentifyMs    int64  `json:"identifyMs"`
	FirstStreamMs int64  `json:"firstStreamMs"`
	Completed     bool   `json:"completed"`
	NeverDone     bool   `json:"neverCompleted"`
	Hung          bool   `json:"hung"` // decision-criteria hang: !completed OR identifyMs > PeerDialTimeout(2s)
	Err           string `json:"err,omitempty"`
}

type s2VariantSummary struct {
	Name             string `json:"name"`
	Transport        string `json:"transport"`
	Reachability     string `json:"reachability"`
	N                int    `json:"n"`
	HangCount        int    `json:"hangCount"`
	NeverDoneCount   int    `json:"neverCompletedCount"`
	P50IdentifyMs    int64  `json:"p50IdentifyMs"`
	P95IdentifyMs    int64  `json:"p95IdentifyMs"`
	MaxIdentifyMs    int64  `json:"maxIdentifyMs"`
	P95DialMs        int64  `json:"p95DialMs"`
	P95FirstStreamMs int64  `json:"p95FirstStreamMs"`
}

func s2Pctl(vals []int64, p float64) int64 {
	if len(vals) == 0 {
		return 0
	}
	s := append([]int64(nil), vals...)
	sort.Slice(s, func(i, j int) bool { return s[i] < s[j] })
	idx := int(math.Ceil(p*float64(len(s)))) - 1
	if idx < 0 {
		idx = 0
	}
	if idx >= len(s) {
		idx = len(s) - 1
	}
	return s[idx]
}

func s2Max(vals []int64) int64 {
	var m int64
	for _, v := range vals {
		if v > m {
			m = v
		}
	}
	return m
}

func s2Reach(public bool) string {
	if public {
		return "public"
	}
	return "private"
}

func s2Iters() int {
	if v := os.Getenv("FDC_S2_ITERS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return 100
}

// s2Budget = max(p95 rounded UP to 250ms, 750ms) — the FDC-11/FDC-12 per-leg
// dial+identify budget formula from the spike's Decision Criteria (Option A).
func s2Budget(p95 int64) int64 {
	b := ((p95 + 249) / 250) * 250
	if b < 750 {
		b = 750
	}
	return b
}

// ---------------------------------------------------------------------------
// M1 — one peer↔peer direct-LAN dial + identify-both-ways + chat stream.
// ---------------------------------------------------------------------------

type s2IdRes struct {
	d      time.Duration
	ok     bool
	reason string
}

func s2RunM1Iter(t *testing.T, iter int, kind string, forcePublic bool) s2Probe {
	t.Helper()
	res := s2Probe{Transport: kind, Iteration: iter, Reachability: s2Reach(forcePublic)}

	// Two fresh production-mirrored hosts on loopback (= same-LAN direct dial for
	// the PROTOCOL question; real multicast/NIC is FDC-11's device gate, M3).
	listen := []string{
		"/ip4/127.0.0.1/udp/0/quic-v1",
		"/ip4/127.0.0.1/tcp/0",
		"/ip4/127.0.0.1/tcp/0/ws",
	}
	hostA := s2BuildHost(t, listen, forcePublic)
	hostB := s2BuildHost(t, listen, forcePublic)
	defer hostA.Close()
	defer hostB.Close()

	// B answers ChatProtocol so we can prove the conn is stream-usable post-identify.
	chatRecv := make(chan struct{}, 1)
	hostB.SetStreamHandler(ChatProtocol, func(s network.Stream) {
		buf := make([]byte, 8)
		_, _ = s.Read(buf)
		select {
		case chatRecv <- struct{}{}:
		default:
		}
		_ = s.Close()
	})

	subA, err := hostA.EventBus().Subscribe([]interface{}{
		new(event.EvtPeerIdentificationCompleted),
		new(event.EvtPeerIdentificationFailed),
	})
	if err != nil {
		res.Hung, res.Err = true, "subA: "+err.Error()
		return res
	}
	subB, err := hostB.EventBus().Subscribe([]interface{}{
		new(event.EvtPeerIdentificationCompleted),
		new(event.EvtPeerIdentificationFailed),
	})
	if err != nil {
		subA.Close()
		res.Hung, res.Err = true, "subB: "+err.Error()
		return res
	}
	defer subA.Close()
	defer subB.Close()

	dialAddr := s2PickListenAddr(t, hostB, kind)
	info := peer.AddrInfo{ID: hostB.ID(), Addrs: []ma.Multiaddr{dialAddr}}

	hardCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dialStart := time.Now()
	if err := hostA.Connect(hardCtx, info); err != nil {
		res.DialMs = time.Since(dialStart).Milliseconds()
		res.Hung, res.NeverDone, res.Err = true, true, "connect: "+err.Error()
		return res
	}
	res.DialMs = time.Since(dialStart).Milliseconds()

	// Identify BOTH directions concurrently; measure each from dialStart.
	aCh := make(chan s2IdRes, 1)
	bCh := make(chan s2IdRes, 1)
	go func() {
		ok, reason := s2WaitIdentify(subA, hostB.ID(), hardCtx.Done())
		aCh <- s2IdRes{time.Since(dialStart), ok, reason}
	}()
	go func() {
		ok, reason := s2WaitIdentify(subB, hostA.ID(), hardCtx.Done())
		bCh <- s2IdRes{time.Since(dialStart), ok, reason}
	}()
	a := <-aCh
	b := <-bCh

	if !a.ok || !b.ok {
		res.Hung, res.NeverDone = true, true
		res.IdentifyMs = 10000
		res.Err = strings.TrimSpace("A:" + a.reason + " B:" + b.reason)
		return res
	}
	res.Completed = true
	idMs := a.d
	if b.d > idMs {
		idMs = b.d
	}
	res.IdentifyMs = idMs.Milliseconds()
	if res.IdentifyMs > PeerDialTimeout.Milliseconds() {
		res.Hung = true // slow-but-eventually counts toward hang_rate (decision criteria)
	}

	// Prove stream usability A->B over the freshly-identified direct conn.
	sctx, scancel := context.WithTimeout(hardCtx, 5*time.Second)
	defer scancel()
	streamStart := time.Now()
	st, err := hostA.NewStream(sctx, hostB.ID(), ChatProtocol)
	if err != nil {
		res.Hung = true
		res.Err = "newstream: " + err.Error()
		return res
	}
	_, _ = st.Write([]byte("ping"))
	_ = st.CloseWrite()
	select {
	case <-chatRecv:
		res.FirstStreamMs = time.Since(streamStart).Milliseconds()
	case <-time.After(3 * time.Second):
		res.Hung = true
		res.Err = "stream-no-recv"
	}
	_ = st.Close()
	return res
}

func s2RunVariant(t *testing.T, name, kind string, forcePublic bool, n int) s2VariantSummary {
	t.Helper()
	sum := s2VariantSummary{Name: name, Transport: kind, Reachability: s2Reach(forcePublic), N: n}
	probes := make([]s2Probe, 0, n)
	var idMs, dialMs, streamMs []int64
	for i := 0; i < n; i++ {
		p := s2RunM1Iter(t, i, kind, forcePublic)
		probes = append(probes, p)
		if p.Hung {
			sum.HangCount++
		}
		if p.NeverDone {
			sum.NeverDoneCount++
		}
		if p.Completed {
			idMs = append(idMs, p.IdentifyMs)
			dialMs = append(dialMs, p.DialMs)
			if p.FirstStreamMs > 0 {
				streamMs = append(streamMs, p.FirstStreamMs)
			}
		}
	}
	sum.P50IdentifyMs = s2Pctl(idMs, 0.50)
	sum.P95IdentifyMs = s2Pctl(idMs, 0.95)
	sum.MaxIdentifyMs = s2Max(idMs)
	sum.P95DialMs = s2Pctl(dialMs, 0.95)
	sum.P95FirstStreamMs = s2Pctl(streamMs, 0.95)

	if b, err := json.Marshal(struct {
		Summary s2VariantSummary `json:"summary"`
		Probes  []s2Probe        `json:"probes"`
	}{sum, probes}); err == nil {
		t.Logf("S2_PROBE_JSON %s", string(b))
	}
	return sum
}

// ---------------------------------------------------------------------------
// M0 — relay-QUIC identify control (hermetic local QUIC relay). The sanity
// control: if THIS fails, the harness is wrong, not the stack.
// ---------------------------------------------------------------------------

func TestQuicIdentifyRevalidation_M0RelayControl(t *testing.T) {
	if testing.Short() {
		t.Skip("M0 spins up libp2p hosts; skip in -short")
	}
	relayPriv, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("M0: relay key: %v", err)
	}
	relayHost, err := libp2p.New(
		libp2p.Identity(relayPriv),
		libp2p.ListenAddrStrings("/ip4/127.0.0.1/udp/0/quic-v1", "/ip4/127.0.0.1/tcp/0"),
		libp2p.EnableRelayService(),
		libp2p.ForceReachabilityPublic(),
	)
	if err != nil {
		t.Fatalf("M0: relay host: %v", err)
	}
	defer relayHost.Close()

	client := s2BuildHost(t, []string{"/ip4/127.0.0.1/udp/0/quic-v1", "/ip4/127.0.0.1/tcp/0"}, false)
	defer client.Close()

	sub, err := client.EventBus().Subscribe([]interface{}{
		new(event.EvtPeerIdentificationCompleted),
		new(event.EvtPeerIdentificationFailed),
	})
	if err != nil {
		t.Fatalf("M0: subscribe: %v", err)
	}
	defer sub.Close()

	relayQuic := s2PickListenAddr(t, relayHost, "quic")
	info := peer.AddrInfo{ID: relayHost.ID(), Addrs: []ma.Multiaddr{relayQuic}}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	dialStart := time.Now()
	if err := client.Connect(ctx, info); err != nil {
		t.Fatalf("M0: connect relay over QUIC: %v", err)
	}
	ok, reason := s2WaitIdentify(sub, relayHost.ID(), ctx.Done())
	idMs := time.Since(dialStart).Milliseconds()
	if !ok {
		t.Fatalf("M0: relay-QUIC identify did not complete within 10s (%s)", reason)
	}
	threshold := ForegroundRelayDialTimeout.Milliseconds()
	t.Logf("S2_M0 hermetic relay-QUIC identify=%dms (control threshold ForegroundRelayDialTimeout=%dms)", idMs, threshold)
	if idMs > threshold {
		t.Fatalf("M0: relay-QUIC identify %dms exceeds control threshold %dms", idMs, threshold)
	}
}

// ---------------------------------------------------------------------------
// M1 — HEADLINE: peer↔peer direct LAN QUIC/TCP identify, N iters, the
// private/public reachability pair. Regression lock: production-config QUIC
// LAN-direct identify MUST NOT hang.
// ---------------------------------------------------------------------------

func TestQuicIdentifyRevalidation_M1DirectLAN(t *testing.T) {
	if testing.Short() {
		t.Skip("M1 spins up many libp2p hosts; skip in -short")
	}
	n := s2Iters()
	t.Logf("S2_M1 N=%d (override via FDC_S2_ITERS)", n)

	quicPriv := s2RunVariant(t, "M1-quic-private", "quic", false, n)
	quicPub := s2RunVariant(t, "M1-quic-public", "quic", true, n)
	tcpPriv := s2RunVariant(t, "M1-tcp-private", "tcp", false, n)
	tcpPub := s2RunVariant(t, "M1-tcp-public", "tcp", true, n)

	for _, s := range []s2VariantSummary{quicPriv, quicPub, tcpPriv, tcpPub} {
		t.Logf("S2_VARIANT %-18s N=%d hang=%d neverDone=%d p50=%dms p95=%dms max=%dms dialP95=%dms streamP95=%dms",
			s.Name, s.N, s.HangCount, s.NeverDoneCount, s.P50IdentifyMs, s.P95IdentifyMs, s.MaxIdentifyMs, s.P95DialMs, s.P95FirstStreamMs)
	}

	budget := s2Budget(quicPriv.P95IdentifyMs)
	t.Logf("S2_VERDICT quicPrivate{hang=%d/%d, p95=%dms} tcpPrivate{hang=%d/%d, p95=%dms} => recommendedDirectLanBudgetMs=%d",
		quicPriv.HangCount, quicPriv.N, quicPriv.P95IdentifyMs,
		tcpPriv.HangCount, tcpPriv.N, tcpPriv.P95IdentifyMs, budget)

	// HEADLINE REGRESSION LOCK: the spike exists to answer "does the QUIC identify
	// hang still reproduce?". Production config is QUIC + ForceReachabilityPrivate.
	// A future go-libp2p/quic-go bump that reintroduces the indefinite hang (an
	// iter that never completes within 10s) turns this RED.
	if quicPriv.NeverDoneCount > 0 {
		t.Fatalf("M1 QUIC-private: %d/%d iters never completed identify within 10s — the historical QUIC identify HANG reproduced",
			quicPriv.NeverDoneCount, quicPriv.N)
	}
}

// ---------------------------------------------------------------------------
// M2 — cross-version skew: a v0.39.1 client dials the PRODUCTION relay, which
// runs go-libp2p v0.38.2 (go-relay-server/go.mod:10), over QUIC. Network-gated:
// skips (does not fail) when the relay is unreachable from this host, since the
// PROTOCOL question (M1) is answered hermetically. When it runs, it doubles as
// the real-relay control for DefaultQUICRelay being in the client defaults.
// ---------------------------------------------------------------------------

func TestQuicIdentifyRevalidation_M2CrossVersionProdRelay(t *testing.T) {
	if testing.Short() {
		t.Skip("M2 reaches the network; skip in -short")
	}
	client := s2BuildHost(t, []string{"/ip4/0.0.0.0/udp/0/quic-v1"}, false)
	defer client.Close()

	info, err := peer.AddrInfoFromString(DefaultQUICRelay)
	if err != nil {
		t.Fatalf("M2: parse DefaultQUICRelay: %v", err)
	}
	sub, err := client.EventBus().Subscribe([]interface{}{
		new(event.EvtPeerIdentificationCompleted),
		new(event.EvtPeerIdentificationFailed),
	})
	if err != nil {
		t.Fatalf("M2: subscribe: %v", err)
	}
	defer sub.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	dialStart := time.Now()
	if err := client.Connect(ctx, *info); err != nil {
		t.Skipf("M2: prod relay %s unreachable from this host (%v) — cross-version skew check needs network; M1 protocol verdict stands hermetically",
			DefaultQUICRelay, err)
	}
	ok, reason := s2WaitIdentify(sub, info.ID, ctx.Done())
	idMs := time.Since(dialStart).Milliseconds()
	if !ok {
		t.Fatalf("M2: prod relay-QUIC (v0.38.2 <- v0.39.1 client) identify did not complete within 8s (%s) — cross-version skew suspected", reason)
	}
	t.Logf("S2_M2 prod relay-QUIC cross-version (v0.38.2 relay <- v0.39.1 client) identify=%dms", idMs)
}
