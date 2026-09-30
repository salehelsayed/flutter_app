package node

import (
	"testing"

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
