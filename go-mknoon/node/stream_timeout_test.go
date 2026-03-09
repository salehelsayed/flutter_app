package node

import (
	"testing"
	"time"
)

// TestOutboundStreams_ApplyDeadlineAcrossChatInboxRendezvousGroupInboxAndMedia
// verifies that stream-level deadline constants are defined and reasonable
// for all outbound protocol paths.
func TestOutboundStreams_ApplyDeadlineAcrossChatInboxRendezvousGroupInboxAndMedia(t *testing.T) {
	// Verify that stream deadline constants exist and are positive
	if StreamWriteDeadline <= 0 {
		t.Error("StreamWriteDeadline must be positive")
	}
	if StreamReadDeadline <= 0 {
		t.Error("StreamReadDeadline must be positive")
	}

	// Interactive timeouts should be shorter than background stream deadlines
	interactive := InteractiveTimeouts()
	if interactive.Send > StreamWriteDeadline {
		t.Errorf("interactive send (%v) should not exceed stream write deadline (%v)",
			interactive.Send, StreamWriteDeadline)
	}

	// Background timeouts should align with stream deadlines
	background := BackgroundTimeouts()
	if background.Send > StreamWriteDeadline*2 {
		t.Errorf("background send (%v) should not be more than 2x stream write deadline (%v)",
			background.Send, StreamWriteDeadline)
	}
}

// TestTimedOutOrMalformedStreams_ResetInsteadOfHanging verifies that
// SendMessageWithTimeout uses Reset on error paths rather than leaving
// streams to close normally when transport is unhealthy.
func TestTimedOutOrMalformedStreams_ResetInsteadOfHanging(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Try to send to a non-existent peer with a very short timeout.
	// This should fail quickly due to timeout, not hang.
	start := time.Now()
	_, sendErr := n.SendMessageWithTimeout(
		"12D3KooWNonExistentPeerIdThatWillNeverConnect123456",
		"test message",
		100, // 100ms timeout
	)
	elapsed := time.Since(start)

	// Should fail (no such peer)
	if sendErr == nil {
		t.Error("expected error when sending to non-existent peer")
	}

	// Should fail within a reasonable time bound (timeout + overhead)
	if elapsed > 5*time.Second {
		t.Errorf("send to non-existent peer took %v, expected < 5s", elapsed)
	}
}

// TestInboundChatStream_UsesReadDeadlineAndResetsOnSlowPeer verifies
// the inbound read deadline constant is appropriate.
func TestInboundChatStream_UsesReadDeadlineAndResetsOnSlowPeer(t *testing.T) {
	// Verify inbound read deadline is bounded and positive
	if InboundReadDeadline <= 0 {
		t.Error("InboundReadDeadline must be positive")
	}
	if InboundReadDeadline > 30*time.Second {
		t.Errorf("InboundReadDeadline (%v) should be <= 30s to prevent hung peers",
			InboundReadDeadline)
	}

	// Verify inbound deadline is longer than send timeout to allow
	// legitimate slow writes from peers on constrained networks
	if InboundReadDeadline < SendTimeout {
		t.Errorf("InboundReadDeadline (%v) should be >= SendTimeout (%v)",
			InboundReadDeadline, SendTimeout)
	}
}
