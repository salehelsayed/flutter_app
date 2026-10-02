package node

import (
	"testing"

	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"

	ma "github.com/multiformats/go-multiaddr"
)

func TestRelayOnlyAddressesKeepsOnlyCircuits(t *testing.T) {
	circuit := "/ip4/51.21.194.144/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g/p2p-circuit"
	var addrs []ma.Multiaddr
	for _, s := range []string{
		"/ip4/192.168.1.100/tcp/1234",
		"/ip4/10.0.2.16/udp/4001/quic-v1",
		"/ip6/2001:db8::1/tcp/4001",
		circuit,
	} {
		addrs = append(addrs, ma.StringCast(s))
	}
	got := relayOnlyAddresses(addrs)
	if len(got) != 1 || got[0].String() != circuit {
		t.Fatalf("relayOnlyAddresses = %v, want only %s", got, circuit)
	}
	if len(relayOnlyAddresses(addrs[:3])) != 0 {
		t.Fatalf("direct-only input must advertise nothing")
	}
}

func TestDebugAdvertiseRelayOnlyDefaultsOff(t *testing.T) {
	if DefaultFeatureFlags().DebugAdvertiseRelayOnly {
		t.Fatal("DebugAdvertiseRelayOnly must default to false")
	}
	if (&NodeConfig{}).EffectiveFlags().DebugAdvertiseRelayOnly {
		t.Fatal("nil-map effective flags must not advertise relay-only")
	}
}

// Configured relay addresses must survive connected/session address expiry.
func TestConfiguredRelayAddressesSurviveSessionExpiry(t *testing.T) {
	const relayID = "12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
	node := NewNode()
	_, err := node.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{"/ip4/127.0.0.1/tcp/1/p2p/" + relayID},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer node.Stop()
	id, err := peer.Decode(relayID)
	if err != nil {
		t.Fatal(err)
	}
	store := node.Host().Peerstore()
	store.UpdateAddrs(id, peerstore.ConnectedAddrTTL, 0)
	store.UpdateAddrs(id, peerstore.RecentlyConnectedAddrTTL, 0)
	got := store.Addrs(id)
	if len(got) != 1 || got[0].String() != "/ip4/127.0.0.1/tcp/1" {
		t.Fatalf("configured relay address lost after session expiry: %v", got)
	}
}
