package node

import (
	"testing"
	"time"
)

func TestInteractiveAndBackgroundTimeoutProfilesRemainDistinct(t *testing.T) {
	interactive := InteractiveTimeouts()
	background := BackgroundTimeouts()

	if interactive.Dial >= background.Dial {
		t.Errorf("interactive dial (%v) should be shorter than background dial (%v)",
			interactive.Dial, background.Dial)
	}
	if interactive.Send >= background.Send {
		t.Errorf("interactive send (%v) should be shorter than background send (%v)",
			interactive.Send, background.Send)
	}
	if interactive.Discover >= background.Discover {
		t.Errorf("interactive discover (%v) should be shorter than background discover (%v)",
			interactive.Discover, background.Discover)
	}
	if interactive.Inbox >= background.Inbox {
		t.Errorf("interactive inbox (%v) should be shorter than background inbox (%v)",
			interactive.Inbox, background.Inbox)
	}
}

func TestForegroundRelayProbeIsNotRequiredForActiveSendPath(t *testing.T) {
	// The interactive timeout profile should provide dial and send timeouts
	// that are independent of relay probe timing. This test documents that
	// the interactive send path does not include a relay probe gate.
	interactive := InteractiveTimeouts()

	// Interactive dial should be short enough for user-facing actions (<=5s)
	if interactive.Dial.Seconds() > 5 {
		t.Errorf("interactive dial (%v) should be <= 5s for foreground use",
			interactive.Dial)
	}

	// Interactive discover should be short enough for user-facing actions (<=3s)
	if interactive.Discover.Seconds() > 3 {
		t.Errorf("interactive discover (%v) should be <= 3s for foreground use",
			interactive.Discover)
	}
}

func TestDirectConfirmTimeout_StaysWithinCommittedAckReserve(t *testing.T) {
	if DirectConfirmTimeout <= 0 {
		t.Fatal("DirectConfirmTimeout must be positive")
	}
	if DirectConfirmTimeout >= CommittedAckReserve {
		t.Fatalf(
			"DirectConfirmTimeout (%v) must stay below CommittedAckReserve (%v)",
			DirectConfirmTimeout,
			CommittedAckReserve,
		)
	}
}

func TestGroupPublishPeerSettleWindows_StayShortForForegroundSend(t *testing.T) {
	if GroupPublishZeroPeerSettleWait <= 0 {
		t.Fatal("GroupPublishZeroPeerSettleWait must be positive")
	}
	if GroupPublishPartialPeerSettleWait <= 0 {
		t.Fatal("GroupPublishPartialPeerSettleWait must be positive")
	}
	if GroupPublishZeroPeerSettleWait >= GroupPublishPartialPeerSettleWait {
		t.Fatalf(
			"zero-peer settle wait (%v) must stay below partial-peer settle wait (%v)",
			GroupPublishZeroPeerSettleWait,
			GroupPublishPartialPeerSettleWait,
		)
	}
	if GroupPublishZeroPeerSettleWait > 250*time.Millisecond {
		t.Fatalf(
			"zero-peer settle wait (%v) is too slow for the foreground durable-send race",
			GroupPublishZeroPeerSettleWait,
		)
	}
	if GroupPublishPartialPeerSettleWait > time.Second {
		t.Fatalf(
			"partial-peer settle wait (%v) should stay sub-second for foreground sends",
			GroupPublishPartialPeerSettleWait,
		)
	}
	if GroupPublishPartialPeerSettleWait >= InteractiveSendTimeout {
		t.Fatalf(
			"partial-peer settle wait (%v) must stay below InteractiveSendTimeout (%v)",
			GroupPublishPartialPeerSettleWait,
			InteractiveSendTimeout,
		)
	}
}

// TestConfig_TimeoutsMatchExecutedS1Verdict_NoRetime is FDC-07's permanent
// regression lock encoding the EXECUTED FDC-S1 timing verdict
// (FDC-S1-cold-start-timing-RESULTS.md §4: FOREGROUND_RELAY_BUDGET_MS=keep 3s,
// DIALTIMEOUT_RETIME=no). FDC-07 ships the cold-start mDNS/anchor hoist with
// ZERO timeout-value changes — S1 measured T_circuit p90 at 1564ms (Pixel 6) /
// 913ms (iPhone 13), both already inside the 3s foreground budget, so there is
// no value to move. The refuted "cap the cold relay dial to 3s" would abandon a
// slow-but-succeeding cold QUIC/TLS handshake → MORE inbox fallback; this test
// re-reds the instant anyone re-introduces it. Unlike the relationship checks
// above, these are LITERAL equality locks on the six cold-start durations.
func TestConfig_TimeoutsMatchExecutedS1Verdict_NoRetime(t *testing.T) {
	cases := []struct {
		name string
		got  time.Duration
		want time.Duration
	}{
		{"DialTimeout", DialTimeout, 15 * time.Second},
		{"ForegroundRelayDialTimeout", ForegroundRelayDialTimeout, 3 * time.Second},
		{"ForegroundRelayReserveTimeout", ForegroundRelayReserveTimeout, 3 * time.Second},
		{"ForegroundCircuitAddressWaitTimeout", ForegroundCircuitAddressWaitTimeout, 3 * time.Second},
		{"InteractiveDialTimeout", InteractiveDialTimeout, 4 * time.Second},
		{"InteractiveSendTimeout", InteractiveSendTimeout, 3 * time.Second},
	}
	for _, tc := range cases {
		if tc.got != tc.want {
			t.Errorf(
				"%s = %v, want %v — FDC-S1 verdict DIALTIMEOUT_RETIME=no: no cold-start "+
					"timeout value moves in FDC-07 (did someone re-introduce the refuted "+
					"\"cap to 3s\"?)",
				tc.name, tc.got, tc.want,
			)
		}
	}
}
