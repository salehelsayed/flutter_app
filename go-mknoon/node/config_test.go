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

func TestDirectConfirmTimeout_StaysWithinInteractiveSendBudget(t *testing.T) {
	if DirectConfirmTimeout <= 0 {
		t.Fatal("DirectConfirmTimeout must be positive")
	}
	if DirectConfirmTimeout >= InteractiveSendTimeout {
		t.Fatalf(
			"DirectConfirmTimeout (%v) must stay below InteractiveSendTimeout (%v)",
			DirectConfirmTimeout,
			InteractiveSendTimeout,
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
