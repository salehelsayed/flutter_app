package node

import (
	"errors"
	"testing"
	"time"
)

func TestTurnCredentialsV1_EstablishedRelayBlackholeRecoversWithoutRestart(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	relay, requests := startTurnCredentialsRelayFixture(t, validTurnCredentialsResponse(now, "fixture"))
	n := startLocalNodeForMultiRelayTest(t)
	originalHost := n.Host()
	originalPeerID := originalHost.ID()
	v4 := relay.Addrs()[0]
	proxy := newEstablishedPathProxy(t, v4)
	pid := relay.ID()
	n.mu.Lock()
	n.relayAddresses = []string{
		proxy.address.String() + "/p2p/" + pid.String(),
		v4.String() + "/p2p/" + pid.String(),
	}
	n.mu.Unlock()
	if err := n.DialPeerWithTimeout(pid.String(), []string{proxy.address.String()}, 3000); err != nil {
		t.Fatal("could not establish the proxied relay transport")
	}
	conns := originalHost.Network().ConnsToPeer(pid)
	if len(conns) != 1 || !conns[0].RemoteMultiaddr().Equal(proxy.address) {
		t.Fatal("fixture must warm only the proxied relay connection")
	}
	original := conns[0]
	sibling, remote := sharedTraffic(t, originalHost, relay)
	if sibling.Conn() != original {
		t.Fatal("TURN control sibling used another connection")
	}
	sharedProgress(t, sibling, remote, "before-turn-blackhole")
	assertCredentials := func(bundle TurnCredentialBundle) {
		t.Helper()
		if validateTurnCredentialBundle(bundle, time.Now()) != nil ||
			bundle.Username != turnTestUsername || bundle.Password != turnTestPassword ||
			bundle.TTLSeconds != 600 || bundle.ServerTimeMs != now.UnixMilli() ||
			bundle.ExpiresAtMs != now.Add(10*time.Minute).UnixMilli() {
			t.Fatal("TURN request did not return the real validated fixture response")
		}
		wantURLs := []string{
			"turn:relay.invalid:3478?transport=udp",
			"turn:relay.invalid:3478?transport=tcp",
			"turns:relay.invalid:443?transport=tcp",
		}
		if len(bundle.URLs) != len(wantURLs) {
			t.Fatal("TURN response URL count changed")
		}
		for i, want := range wantURLs {
			if bundle.URLs[i] != want {
				t.Fatal("TURN response URL value or order changed")
			}
		}
	}
	assertRequest := func() {
		t.Helper()
		select {
		case raw := <-requests:
			if raw != `{"action":"turn_credentials_v1"}` {
				t.Fatal("TURN recovery changed the action-only request")
			}
		default:
			t.Fatal("relay did not receive the real TURN request")
		}
	}

	// Both addresses are already configured, but the successful warm request
	// must reuse the sole proxy connection. No healthy replacement is predialed.
	warm, err := n.TurnCredentialsV1()
	if err != nil {
		t.Fatal("warm TURN request failed")
	}
	assertCredentials(warm)
	assertRequest()
	assertOriginalSharedConnection(t, originalHost, pid, original)
	sharedProgress(t, sibling, remote, "after-warm-turn-request")

	// Silent loss keeps the established socket open. The first ordinary TURN
	// request retains the public API's unchanged four-second total deadline.
	proxy.drop.Store(true)
	failed, firstErr := n.TurnCredentialsV1()
	if !errors.Is(firstErr, ErrTurnCredentialsUnavailable) {
		t.Fatal("faulted TURN request did not fail as unavailable")
	}
	if failed.Schema != "" || failed.Username != "" || failed.Password != "" || len(failed.URLs) != 0 {
		t.Fatal("failed TURN request exposed an unvalidated credential bundle")
	}
	assertOriginalSharedConnection(t, originalHost, pid, original)
	select {
	case <-requests:
		t.Fatal("blackholed TURN request unexpectedly reached the relay")
	default:
	}

	// A fresh ordinary request must check and retire the exact silent
	// connection, then use the previously known healthy address. No manual
	// suspect marking, liveness call, post-fault dial, or timeout hook intervenes.
	started := time.Now()
	recovered, recoveryErr := n.TurnCredentialsV1()
	elapsed := time.Since(started)
	if recoveryErr != nil {
		t.Fatalf("fresh TURN request remained trapped on the stale relay connection: elapsed_ms=%d stale_closed=%v", elapsed.Milliseconds(), original.IsClosed())
	}
	if elapsed > 4*time.Second {
		t.Fatalf("TURN recovery exceeded its original 4000 ms budget: elapsed_ms=%d", elapsed.Milliseconds())
	}
	assertCredentials(recovered)
	assertRequest()
	if n.Host() != originalHost || n.Host().ID() != originalPeerID {
		t.Fatal("TURN recovery restarted or replaced the node host")
	}
	conns = originalHost.Network().ConnsToPeer(pid)
	if !original.IsClosed() || len(conns) != 1 || conns[0] == original ||
		conns[0].RemotePeer() != pid || !conns[0].RemoteMultiaddr().Equal(v4) {
		t.Fatal("TURN recovery did not retire the exact stale connection and use the healthy address of the same relay")
	}
	assertNoSendChecks(t, n)
}
