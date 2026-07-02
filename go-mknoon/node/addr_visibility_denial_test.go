package node

// Test-Flight-Improv/190 — Android netlink SELinux denial: the Go node must
// still announce real local addresses when the raw netlink interface-address
// lane is denied (b/155595000). These darwin host tests drive real in-process
// nodes/hosts through two fork seams:
//
//   - manet.SetInterfaceAddrsProviderForTests (go-multiaddr fork) models the raw
//     interface-address lane: an error-returning provider reproduces the Android
//     denial; an addr-returning provider models wlynxg/anet succeeding.
//   - netroute.SetNewFailureHookForTests (go-netroute fork) blocks the routing
//     lane too. basichost seeds filteredInterfaceAddrs from netroute BEFORE
//     manet (basic_host.go:355-388), and netroute succeeds on macOS — so a
//     manet-only fixture would false-green here. Both lanes must be blocked to
//     reproduce Android.
//
// Marker IPs discriminate injected addrs from the machine's real interfaces:
//   192.168.190.10 / .20 — private markers (kept by filterAddresses)
//   190.190.190.190      — public marker (classified public by manet; the DCUtR
//                          candidate that survives the hole-punch !IsPublicAddr
//                          delete). 203.0.113.x is unroutable per manet, so it
//                          could NOT be used here.
//
// This file is deliberately NOT named *_android_test.go: that suffix carries an
// implicit GOOS=android constraint that would silently exclude it from darwin.

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	logging "github.com/ipfs/go-log/v2"
	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	relayclient "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	ma "github.com/multiformats/go-multiaddr"
	manet "github.com/multiformats/go-multiaddr/net"

	netroute "github.com/libp2p/go-netroute"
)

const (
	avMarkerPrivateIP  = "192.168.190.10"
	avMarkerPrivateIP2 = "192.168.190.20"
	avMarkerPublicIP   = "190.190.190.190" // manet-public; never dialed
)

// avIPNetAddrs converts marker IP strings into the *net.IPNet values that
// net.InterfaceAddrs returns (so manet.FromNetAddr yields /ip4/<ip>).
func avIPNetAddrs(ips ...string) []net.Addr {
	out := make([]net.Addr, 0, len(ips))
	for _, ip := range ips {
		parsed := net.ParseIP(ip)
		if parsed == nil {
			continue
		}
		mask := net.CIDRMask(24, 32)
		if parsed.To4() == nil {
			mask = net.CIDRMask(64, 128)
		}
		out = append(out, &net.IPNet{IP: parsed, Mask: mask})
	}
	return out
}

func avDenyNetroute() error {
	return errors.New("route ip+net: netlinkrib: permission denied")
}

// avInstallDenial models Android with NO fix: both netlink lanes denied.
func avInstallDenial(t *testing.T) {
	t.Helper()
	restore := manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return nil, errors.New("route ip+net: netlinkrib: permission denied")
	})
	t.Cleanup(restore)
	restoreNR := netroute.SetNewFailureHookForTests(avDenyNetroute)
	t.Cleanup(restoreNR)
}

// avInstallAnetShaped models Android WITH the fix: the netlink route lane stays
// denied (netroute keeps failing on Android — accepted difference), but
// interface-address enumeration succeeds via anet, modeled by a provider that
// returns the given addrs.
func avInstallAnetShaped(t *testing.T, ips ...string) {
	t.Helper()
	addrs := avIPNetAddrs(ips...)
	restore := manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return addrs, nil
	})
	t.Cleanup(restore)
	restoreNR := netroute.SetNewFailureHookForTests(avDenyNetroute)
	t.Cleanup(restoreNR)
}

// avStartLocalNode starts a real local-only Node — no relay, so no autorelay
// address wrapping — mirroring startLANDialTestNode/TestNodeStartStop.
func avStartLocalNode(t *testing.T) *Node {
	t.Helper()
	n := New(&testEventCollector{})
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })
	return n
}

func avAddrsContain(addrs []ma.Multiaddr, substr string) bool {
	for _, a := range addrs {
		if strings.Contains(a.String(), substr) {
			return true
		}
	}
	return false
}

func avSliceContains(ss []string, substr string) bool {
	for _, s := range ss {
		if strings.Contains(s, substr) {
			return true
		}
	}
	return false
}

// avWaitHostAddr polls h.Addrs() for an addr containing substr. Construction
// populates addrs synchronously (basic_host.go:202), so this is normally a
// single pass; the poll only guards async refinement.
func avWaitHostAddr(t *testing.T, h host.Host, substr string, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if avAddrsContain(h.Addrs(), substr) {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("host never announced an addr containing %q within %s; addrs=%v", substr, timeout, h.Addrs())
}

// avBoundIP4QuicPorts returns the set of concrete UDP ports the host bound for
// IPv4 quic-v1 listeners.
func avBoundIP4QuicPorts(h host.Host) map[string]bool {
	ports := map[string]bool{}
	for _, a := range h.Network().ListenAddresses() {
		s := a.String()
		if strings.Contains(s, "/ip4/") && strings.Contains(s, "/quic-v1") {
			if p, err := a.ValueForProtocol(ma.P_UDP); err == nil {
				ports[p] = true
			}
		}
	}
	return ports
}

func avIP4QuicPort(t *testing.T, h host.Host) string {
	t.Helper()
	for p := range avBoundIP4QuicPorts(h) {
		return p
	}
	t.Fatalf("no IPv4 quic listen port among %v", h.Network().ListenAddresses())
	return ""
}

// avMachinePrivateIPv4 returns a real routable private IPv4 of the test machine,
// or "" if none (e.g. loopback-only CI).
func avMachinePrivateIPv4() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return ""
	}
	for _, a := range addrs {
		ipnet, ok := a.(*net.IPNet)
		if !ok {
			continue
		}
		ip4 := ipnet.IP.To4()
		if ip4 == nil || ip4.IsLoopback() || ip4.IsLinkLocalUnicast() {
			continue
		}
		if ip4.IsPrivate() {
			return ip4.String()
		}
	}
	return ""
}

// avCaptureLogs runs fn while draining all go-log output, returning the text.
func avCaptureLogs(t *testing.T, fn func()) string {
	t.Helper()
	pr := logging.NewPipeReader(logging.PipeFormat(logging.PlaintextOutput))
	var buf bytes.Buffer
	done := make(chan struct{})
	go func() {
		_, _ = io.Copy(&buf, pr)
		close(done)
	}()
	fn()
	time.Sleep(100 * time.Millisecond) // let synchronous construction logs flush
	_ = pr.Close()
	<-done
	return buf.String()
}

// ---------------------------------------------------------------------------
// Catalog 4 (TC-190-01) — announce pipeline survives blocked enumeration.
// ---------------------------------------------------------------------------

func TestAnnouncedAddrsSurviveBlockedEnumeration(t *testing.T) {
	avInstallAnetShaped(t, avMarkerPrivateIP)
	n := avStartLocalNode(t)
	avWaitHostAddr(t, n.Host(), avMarkerPrivateIP, 3*time.Second)

	// (a) The announce set carries the marker with the REAL bound quic port.
	boundPorts := avBoundIP4QuicPorts(n.Host())
	matched := false
	for _, a := range n.Host().Addrs() {
		ip, _ := a.ValueForProtocol(ma.P_IP4)
		port, _ := a.ValueForProtocol(ma.P_UDP)
		if ip == avMarkerPrivateIP && strings.Contains(a.String(), "/quic-v1") && boundPorts[port] {
			matched = true
		}
	}
	if !matched {
		t.Fatalf("announce set lacks /ip4/%s/udp/<boundPort>/quic-v1; addrs=%v boundPorts=%v",
			avMarkerPrivateIP, n.Host().Addrs(), boundPorts)
	}

	// NodeState.Addresses carries the marker too (Go-internal announce surface).
	if !avSliceContains(n.State().Addresses, avMarkerPrivateIP) {
		t.Fatalf("NodeState.Addresses lacks the self-enumerated marker: %v", n.State().Addresses)
	}

	// (b) Status listenAddresses = real-IP shape, NOT the 0.0.0.0 FDC-11 fallback
	// (spec correction 1: node:status is non-empty today via the fallback; the fix
	// changes its SHAPE from 0.0.0.0 to the real IP).
	status := n.Status()
	listen, _ := status["listenAddresses"].([]string)
	if !avSliceContains(listen, avMarkerPrivateIP) {
		t.Fatalf("Status listenAddresses lacks the real-IP shape: %v", listen)
	}
	for _, s := range listen {
		if strings.HasPrefix(s, "/ip4/0.0.0.0/") || strings.HasPrefix(s, "/ip6/::/") {
			t.Fatalf("Status still using the 0.0.0.0 fallback shape after fix: %v", listen)
		}
	}
}

// ---------------------------------------------------------------------------
// Catalog 5 (TC-190-02) — signed peer record (rendezvous) is non-empty.
// ---------------------------------------------------------------------------

func TestSignedPeerRecordNonEmptyUnderDenial(t *testing.T) {
	avInstallAnetShaped(t, avMarkerPrivateIP)
	n := avStartLocalNode(t)
	avWaitHostAddr(t, n.Host(), avMarkerPrivateIP, 3*time.Second)

	cab, ok := n.Host().Peerstore().(peerstore.CertifiedAddrBook)
	if !ok {
		t.Fatal("peerstore is not a CertifiedAddrBook")
	}

	// The signed record is regenerated on address change; poll up to 3s for it to
	// reflect the self-enumerated marker (rendezvous.go:54 reads exactly this).
	var lastAddrs []ma.Multiaddr
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		env := cab.GetPeerRecord(n.Host().ID())
		if env != nil {
			if r, err := env.Record(); err == nil {
				if pr, ok := r.(*peer.PeerRecord); ok {
					lastAddrs = pr.Addrs
					if avAddrsContain(pr.Addrs, avMarkerPrivateIP) {
						return
					}
				}
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("signed peer record never carried the self-enumerated marker %s (rendezvous would register a marker-less record); last=%v",
		avMarkerPrivateIP, lastAddrs)
}

// ---------------------------------------------------------------------------
// Catalog 6 (TC-190-03) — a peer dials the node via identify-learned addrs,
// with NO mDNS advert lane.
// ---------------------------------------------------------------------------

func TestPeerDialsIdentifyLearnedAddr_NoMdnsLane(t *testing.T) {
	if testing.Short() {
		t.Skip("two-host identify/dial test skipped in -short")
	}
	realPriv := avMachinePrivateIPv4()
	if realPriv == "" {
		t.Skip("machine has no routable private IPv4; identify-dial proof needs one")
	}
	avInstallAnetShaped(t, realPriv, avMarkerPrivateIP)

	// A announces its self-enumerated addrs; it listens on the production wildcard
	// so AllAddrs resolves 0.0.0.0 against the injected interface addrs.
	a := s2BuildHost(t, []string{"/ip4/0.0.0.0/udp/0/quic-v1"}, false)
	defer a.Close()
	avWaitHostAddr(t, a, avMarkerPrivateIP, 3*time.Second)

	portA := avIP4QuicPort(t, a)
	aLoopback := ma.StringCast("/ip4/127.0.0.1/udp/" + portA + "/quic-v1")
	aRealPriv := ma.StringCast("/ip4/" + realPriv + "/udp/" + portA + "/quic-v1")

	b := s2BuildHost(t, []string{"/ip4/127.0.0.1/udp/0/quic-v1"}, false)
	defer b.Close()

	sub, err := b.EventBus().Subscribe(new(event.EvtPeerIdentificationCompleted))
	if err != nil {
		t.Fatalf("subscribe identify: %v", err)
	}
	defer sub.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	// B is told ONLY A's loopback addr — never the marker, never the real-private.
	if err := b.Connect(ctx, peer.AddrInfo{ID: a.ID(), Addrs: []ma.Multiaddr{aLoopback}}); err != nil {
		t.Fatalf("B could not connect to A on loopback: %v", err)
	}
	done := make(chan struct{})
	defer close(done)
	if ok, reason := s2WaitIdentify(sub, a.ID(), done); !ok {
		t.Fatalf("identify with A did not complete: %s", reason)
	}

	// B must have LEARNED A's self-enumerated addrs via identify.
	learned := b.Peerstore().Addrs(a.ID())
	if !avAddrsContain(learned, avMarkerPrivateIP) {
		t.Fatalf("identify did not carry the self-enumerated marker %s to B; learned=%v", avMarkerPrivateIP, learned)
	}
	if !avAddrsContain(learned, realPriv) {
		t.Fatalf("identify did not carry the real-private addr %s to B; learned=%v", realPriv, learned)
	}

	// A fresh peer given ONLY the identify-announced real-private addr (no mDNS TXT,
	// no loopback) can dial the node directly.
	d := s2BuildHost(t, []string{"/ip4/127.0.0.1/udp/0/quic-v1"}, false)
	defer d.Close()
	dctx, dcancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer dcancel()
	if err := d.Connect(dctx, peer.AddrInfo{ID: a.ID(), Addrs: []ma.Multiaddr{aRealPriv}}); err != nil {
		t.Fatalf("fresh dialer could not reach A via identify-announced real-private addr %s: %v", aRealPriv, err)
	}
}

// ---------------------------------------------------------------------------
// Catalog 7 (TC-190-04) — runtime interface change updates the announced set
// with no stale address. This is the suite's single ticker-bound slow test.
// ---------------------------------------------------------------------------

func TestInterfaceChangeUpdatesAnnouncedSet_NoStaleAddr(t *testing.T) {
	if testing.Short() {
		t.Skip("addr-change test rides the unexported 5s ticker; skipped in -short")
	}
	restore := manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return avIPNetAddrs(avMarkerPrivateIP), nil
	})
	t.Cleanup(restore)
	restoreNR := netroute.SetNewFailureHookForTests(avDenyNetroute)
	t.Cleanup(restoreNR)

	n := avStartLocalNode(t)
	avWaitHostAddr(t, n.Host(), avMarkerPrivateIP, 3*time.Second)

	// WiFi→cellular: the interface set changes address. (The returned restore is
	// discarded; the t.Cleanup above restores the original provider at test end.)
	manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return avIPNetAddrs(avMarkerPrivateIP2), nil
	})

	// basichost re-enumerates on its unexported ~5s ticker (do NOT override it).
	deadline := time.Now().Add(16 * time.Second)
	for time.Now().Before(deadline) {
		addrs := n.Host().Addrs()
		if avAddrsContain(addrs, avMarkerPrivateIP2) && !avAddrsContain(addrs, avMarkerPrivateIP) {
			return
		}
		time.Sleep(200 * time.Millisecond)
	}
	t.Fatalf("announced set did not converge to %s (and drop stale %s) within budget; addrs=%v",
		avMarkerPrivateIP2, avMarkerPrivateIP, n.Host().Addrs())
}

// ---------------------------------------------------------------------------
// Catalog 8 (TC-190-05 Go) — genuinely-empty interface set still yields the
// FDC-11 port-mining fallback, without error spam.
// ---------------------------------------------------------------------------

func TestLoopbackOnlyKeepsFdc11PortMiningFallback(t *testing.T) {
	// Loopback-only interface set: enumeration SUCCEEDS (no error) but yields no
	// routable addr, so the announce set is empty after filtering.
	restore := manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return avIPNetAddrs("127.0.0.1"), nil
	})
	t.Cleanup(restore)
	restoreNR := netroute.SetNewFailureHookForTests(avDenyNetroute)
	t.Cleanup(restoreNR)

	var n *Node
	logs := avCaptureLogs(t, func() { n = avStartLocalNode(t) })

	// Post-filter announce is empty of routable addrs.
	for _, a := range n.Host().Addrs() {
		s := a.String()
		if !strings.Contains(s, "/p2p-circuit") {
			ip, _ := a.ValueForProtocol(ma.P_IP4)
			if ip != "" && ip != "127.0.0.1" {
				t.Fatalf("expected no routable announce addr with loopback-only ifaces; got %s", s)
			}
		}
	}

	// FDC-11 fallback still mines the bound 0.0.0.0/:: ports for the advert lane.
	status := n.Status()
	listen, _ := status["listenAddresses"].([]string)
	if len(listen) == 0 {
		t.Fatal("FDC-11 fallback did not mine bound ports when the announce set is empty")
	}
	minedShape := false
	for _, s := range listen {
		if strings.HasPrefix(s, "/ip4/0.0.0.0/") || strings.HasPrefix(s, "/ip6/::/") {
			minedShape = true
		}
	}
	if !minedShape {
		t.Fatalf("expected the FDC-11 mined 0.0.0.0/:: port shape, got %v", listen)
	}

	// Enumeration SUCCEEDED (found loopback) → no netlink-denial ERROR.
	if strings.Contains(logs, "failed to resolve local interface addresses") {
		t.Fatalf("unexpected enumeration ERROR when the provider succeeded with loopback:\n%s", logs)
	}
}

// ---------------------------------------------------------------------------
// Catalog 9 (TC-190-10) — the enumeration ERROR fires under denial (control)
// and is gone when the provider succeeds (fix). Cadence-over-time = device.
// ---------------------------------------------------------------------------

func TestNoEnumerationErrorSpamUnderDenial(t *testing.T) {
	const errMsg = "failed to resolve local interface addresses"

	t.Run("control_denialReproducesTheError", func(t *testing.T) {
		var n *Node
		logs := avCaptureLogs(t, func() {
			avInstallDenial(t)
			n = avStartLocalNode(t)
		})
		_ = n
		if !strings.Contains(logs, errMsg) {
			t.Fatalf("denial fixture did not reproduce the construction-time ERROR %q; got:\n%s", errMsg, logs)
		}
	})

	t.Run("fix_anetProviderSilencesTheError", func(t *testing.T) {
		var n *Node
		logs := avCaptureLogs(t, func() {
			avInstallAnetShaped(t, avMarkerPrivateIP)
			n = avStartLocalNode(t)
		})
		avWaitHostAddr(t, n.Host(), avMarkerPrivateIP, 3*time.Second) // announce populated
		if strings.Contains(logs, errMsg) {
			t.Fatalf("enumeration ERROR should be gone when the provider succeeds; got:\n%s", logs)
		}
	})
}

// ---------------------------------------------------------------------------
// Catalog 10 (TC-190-11) — other basichost errors are NOT suppressed (locks
// "no blanket log demotion shipped").
// ---------------------------------------------------------------------------

func TestOtherBasichostErrorsNotSuppressed(t *testing.T) {
	const probe = "av190-synthetic-basichost-error"
	logs := avCaptureLogs(t, func() {
		// A node start is where the forbidden SetLogLevel("basichost", FATAL)
		// mutation would live; run it so the mutation would take effect here.
		_ = avStartLocalNode(t)
		logging.Logger("basichost").Errorw(probe, "k", "v")
	})
	if !strings.Contains(logs, probe) {
		t.Fatalf("a basichost Errorw did not reach the sink — over-suppression regression? got:\n%s", logs)
	}
}

// ---------------------------------------------------------------------------
// Catalog 11 (TC-190-20 re-scoped) — the hole-punch input term carries the
// self-enumerated addrs (incl. the public DCUtR candidate) under a relay.
// ---------------------------------------------------------------------------

func TestHolePunchInputAddrsContainSelfEnumerated_WithRelay(t *testing.T) {
	if testing.Short() {
		t.Skip("relay + host test skipped in -short")
	}
	avInstallAnetShaped(t, avMarkerPrivateIP, avMarkerPublicIP)

	_, relayAddr := startNW002LocalCircuitRelay(t)

	// A production-shaped host (EnableHolePunching + AddrsFactory(filterAddresses))
	// WITHOUT autorelay wrapping, so h.Addrs() equals the hole-punch closure's
	// INPUT term: basic_host.go:271-279 captures the raw opts.AddrsFactory before
	// its DeleteFunc(!IsPublicAddr). The node's autorelay-wrapped h.Addrs() cannot
	// hold both markers at once — private reachability strips the public addr,
	// public omits the circuit (autorelay.go:63-66) — so reconstructing the raw
	// input term here is the faithful host-tier assertion (spec correction 2).
	h := s2BuildHost(t, []string{"/ip4/0.0.0.0/udp/0/quic-v1"}, false)
	defer h.Close()
	avWaitHostAddr(t, h, avMarkerPrivateIP, 3*time.Second)

	// "with relay": reserve a slot on the in-process circuit relay.
	relayInfo, err := peer.AddrInfoFromString(relayAddr)
	if err != nil {
		t.Fatalf("parse relay addr: %v", err)
	}
	rctx, rcancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer rcancel()
	if _, err := relayclient.Reserve(rctx, h, *relayInfo); err != nil {
		t.Fatalf("could not reserve circuit relay: %v", err)
	}

	addrs := h.Addrs()
	if !avAddrsContain(addrs, avMarkerPrivateIP) {
		t.Fatalf("hole-punch input term lacks the self-enumerated private addr %s: %v", avMarkerPrivateIP, addrs)
	}
	var publicMarker ma.Multiaddr
	for _, a := range addrs {
		if strings.Contains(a.String(), avMarkerPublicIP) {
			publicMarker = a
		}
	}
	if publicMarker == nil {
		t.Fatalf("hole-punch input term lacks the self-enumerated public addr %s: %v", avMarkerPublicIP, addrs)
	}
	// The public marker is what survives the closure's DeleteFunc(!IsPublicAddr) —
	// the real DCUtR candidate material.
	if !manet.IsPublicAddr(publicMarker) {
		t.Fatalf("public marker %s is not classified public by manet — choose a different marker", publicMarker)
	}
}

// ---------------------------------------------------------------------------
// Catalog 12 (TC-190-33) — the fix does not leak non-routable addrs. Only the
// FILTER INPUT gets richer; filterAddresses policy is byte-unchanged.
// ---------------------------------------------------------------------------

func TestFixedEnumerationDoesNotLeakNonRoutable(t *testing.T) {
	avInstallAnetShaped(t, avMarkerPrivateIP, "127.0.0.1", "fe80::1", "0.0.0.0")
	n := avStartLocalNode(t)
	avWaitHostAddr(t, n.Host(), avMarkerPrivateIP, 3*time.Second)

	// Announce carries ONLY the private marker — no loopback/link-local/unspecified.
	for _, a := range n.Host().Addrs() {
		s := a.String()
		if strings.Contains(s, "/p2p-circuit") {
			continue
		}
		if strings.Contains(s, "127.0.0.1") || strings.Contains(s, "/ip6/fe80") ||
			strings.HasPrefix(s, "/ip4/0.0.0.0") || strings.HasPrefix(s, "/ip6/::/") {
			t.Errorf("fixed enumeration leaked a non-routable addr into announce: %s", s)
		}
	}
	if !avAddrsContain(n.Host().Addrs(), avMarkerPrivateIP) {
		t.Fatalf("the private marker was dropped by over-filtering: %v", n.Host().Addrs())
	}

	// Status + NodeState carry no leak either.
	status := n.Status()
	listen, _ := status["listenAddresses"].([]string)
	for _, s := range listen {
		if strings.Contains(s, "127.0.0.1") || strings.Contains(s, "/ip6/fe80") ||
			strings.HasPrefix(s, "/ip4/0.0.0.0") || strings.HasPrefix(s, "/ip6/::/") {
			t.Errorf("Status listenAddresses leaked a non-routable addr: %s", s)
		}
	}
	for _, s := range n.State().Addresses {
		if strings.Contains(s, "127.0.0.1") || strings.Contains(s, "/ip6/fe80") {
			t.Errorf("NodeState.Addresses leaked a non-routable addr: %s", s)
		}
	}
}
