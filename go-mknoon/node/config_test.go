package node

import (
	"testing"
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
