package node

import (
	"errors"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
)

const wakeOutcomeTestCorrelation = "8de60f1321300162dd4b0fed8d87b2017c4fa5b459cced3ec6d3a1d52241076d"

func TestInboxWakeOutcomeAllRelayCompletion(t *testing.T) {
	t.Run("mixed upgraded and old relays are terminal per distinct peer", func(t *testing.T) {
		upgraded, upgradedRaw := startWakeOutcomeRelayFixture(t, `{"status":"OK"}`)
		old, oldRaw := startWakeOutcomeRelayFixture(
			t,
			`{"status":"ERROR","error":"Unknown action: wake_outcome_v1"}`,
		)

		n := startLocalNodeForMultiRelayTest(t)
		upgradedAddr := wakeOutcomeRelayAddress(upgraded)
		n.mu.Lock()
		// Repeating one transport address must not manufacture another relay
		// participant. RelaySelector groups by authenticated peer ID.
		n.relayAddresses = []string{
			upgradedAddr,
			upgradedAddr,
			wakeOutcomeRelayAddress(old),
		}
		n.mu.Unlock()

		outcome, err := n.InboxWakeOutcome(wakeOutcomeTestCorrelation)
		if err != nil {
			t.Fatalf("InboxWakeOutcome: %v", err)
		}
		if !outcome.AllParticipantsTerminal || outcome.ParticipantCount != 2 ||
			outcome.AcceptedCount != 1 || outcome.UnsupportedCount != 1 ||
			outcome.RetryableCount != 0 {
			t.Fatalf("mixed relay outcome = %#v", outcome)
		}

		const exactRequest = `{"action":"wake_outcome_v1","correlation":"` +
			wakeOutcomeTestCorrelation + `","wakeNotRequired":true}`
		for name, requests := range map[string]<-chan string{
			"upgraded": upgradedRaw,
			"old":      oldRaw,
		} {
			select {
			case raw := <-requests:
				if raw != exactRequest {
					t.Fatalf("%s relay request = %s, want exact %s", name, raw, exactRequest)
				}
			case <-time.After(2 * time.Second):
				t.Fatalf("timed out waiting for %s relay request", name)
			}
		}
	})

	t.Run("one success cannot hide malformed or new-relay failure", func(t *testing.T) {
		accepted, _ := startWakeOutcomeRelayFixture(t, `{"status":"OK"}`)
		malformed, _ := startWakeOutcomeRelayFixture(
			t,
			`{"status":"ERROR","error":"wake outcome temporarily unavailable"}`,
		)

		n := startLocalNodeForMultiRelayTest(t)
		n.mu.Lock()
		n.relayAddresses = []string{
			wakeOutcomeRelayAddress(accepted),
			wakeOutcomeRelayAddress(malformed),
		}
		n.mu.Unlock()

		outcome, err := n.InboxWakeOutcome(wakeOutcomeTestCorrelation)
		if !errors.Is(err, ErrInboxWakeOutcomeRetryable) {
			t.Fatalf("error = %v, want ErrInboxWakeOutcomeRetryable", err)
		}
		if outcome.AllParticipantsTerminal || outcome.ParticipantCount != 2 ||
			outcome.AcceptedCount != 1 || outcome.UnsupportedCount != 0 ||
			outcome.RetryableCount != 1 {
			t.Fatalf("partial relay outcome = %#v", outcome)
		}
	})

	t.Run("unsupported spelling and malformed JSON remain retryable", func(t *testing.T) {
		for name, response := range map[string]string{
			"non-exact old error":  `{"status":"ERROR","error":"Unknown action: wake_outcome_v1 "}`,
			"unknown response key": `{"status":"OK","extra":true}`,
			"duplicate status":     `{"status":"OK","status":"OK"}`,
		} {
			t.Run(name, func(t *testing.T) {
				relay, _ := startWakeOutcomeRelayFixture(t, response)
				n := startLocalNodeForMultiRelayTest(t)
				n.mu.Lock()
				n.relayAddresses = []string{wakeOutcomeRelayAddress(relay)}
				n.mu.Unlock()

				outcome, err := n.InboxWakeOutcome(wakeOutcomeTestCorrelation)
				if !errors.Is(err, ErrInboxWakeOutcomeRetryable) ||
					outcome.AllParticipantsTerminal || outcome.RetryableCount != 1 {
					t.Fatalf("outcome = %#v, error = %v", outcome, err)
				}
			})
		}
	})

	t.Run("noncanonical correlation is rejected before network", func(t *testing.T) {
		n := startLocalNodeForMultiRelayTest(t)
		if _, err := n.InboxWakeOutcome("8DE60F1321300162DD4B0FED8D87B2017C4FA5B459CCED3EC6D3A1D52241076D"); err == nil {
			t.Fatal("uppercase correlation unexpectedly accepted")
		}
	})
}

func startWakeOutcomeRelayFixture(t *testing.T, response string) (host.Host, <-chan string) {
	t.Helper()
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	t.Cleanup(func() { _ = relayHost.Close() })

	requests := make(chan string, 4)
	relayHost.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		defer stream.Close()
		raw, err := readFrame(stream)
		if err != nil {
			return
		}
		requests <- string(raw)
		_ = writeFrame(stream, []byte(response))
	})
	return relayHost, requests
}

func wakeOutcomeRelayAddress(relayHost host.Host) string {
	return relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
}
