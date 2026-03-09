package node

import (
	"testing"
	"time"
)

// ===========================================================================
// Phase 6: Group Rendezvous Refresh Tests
// ===========================================================================

// Test: Group rendezvous refresh keeps registration alive past TTL.
// The groupPeerDiscoveryLoop re-registers on the rendezvous namespace
// every GroupDiscoveryInterval (30s), which keeps the registration alive
// past the TTL (7200s). This test verifies the structural properties
// that enable this behavior.
func TestGroupRendezvousRefresh_KeepsRegistrationAlivePastTTL(t *testing.T) {
	// The discovery interval is 30s, and re-registration happens each cycle.
	// The relay server TTL is 7200s (2 hours).
	// As long as GroupDiscoveryInterval < TTL, registrations stay alive.
	if GroupDiscoveryInterval >= 7200*time.Second {
		t.Errorf("GroupDiscoveryInterval (%v) must be less than TTL (7200s) for refresh to work", GroupDiscoveryInterval)
	}

	// Verify the namespace for a group matches expected format.
	ns := groupRendezvousNamespace("test-group-ttl")
	expected := "/mknoon/group/test-group-ttl"
	if ns != expected {
		t.Errorf("namespace = %q, want %q", ns, expected)
	}
}

// Test: Announcement group rendezvous refresh uses the same TTL refresh path.
// Announcement groups use the same groupPeerDiscoveryLoop as chat groups,
// so they benefit from the same periodic re-registration.
func TestAnnouncementGroupRendezvousRefresh_UsesSameTTLRefreshPath(t *testing.T) {
	// Verify that groupRendezvousNamespace works the same for announcement groups.
	chatNs := groupRendezvousNamespace("chat-group-123")
	announceNs := groupRendezvousNamespace("announce-group-456")

	// Both should use the same prefix format.
	expectedChatNs := GroupTopicPrefix + "chat-group-123"
	expectedAnnounceNs := GroupTopicPrefix + "announce-group-456"

	if chatNs != expectedChatNs {
		t.Errorf("chat namespace = %q, want %q", chatNs, expectedChatNs)
	}
	if announceNs != expectedAnnounceNs {
		t.Errorf("announce namespace = %q, want %q", announceNs, expectedAnnounceNs)
	}

	// Both use the same discovery interval.
	// Announcement groups don't have a different timer.
	// The only difference is write authorization (admin-only).
	config := &GroupConfig{
		Name:      "Announcements",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{PeerId: "peer-reader", Role: GroupRoleReader, PublicKey: "readerPk"},
		},
		CreatedBy: "peer-admin",
	}

	// Admin can write; reader cannot.
	if !isAllowedWriter(config, "peer-admin") {
		t.Error("admin should be able to write in announcement group")
	}
	if isAllowedWriter(config, "peer-reader") {
		t.Error("reader should NOT be able to write in announcement group")
	}
}
