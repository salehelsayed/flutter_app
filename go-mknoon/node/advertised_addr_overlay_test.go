package node

import (
	"net"
	"testing"
	"time"

	ma "github.com/multiformats/go-multiaddr"
	manet "github.com/multiformats/go-multiaddr/net"
)

// Task 15 finding 7: the first path event after Start must recognize the
// departed public interface address (the IPv6 the node started on) as
// interface-born and drop it, while an unrelated observed address and a
// circuit address survive. Before the first event the overlay is the
// identity.
func TestAdvertisedAddrOverlay_FirstPublicIPv6PathDropsDepartedInterface(t *testing.T) {
	const old = "2606:4700:4700::1111"
	const current = "2606:4700:4700::1001"
	restore := manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) { return avIPNetAddrs(old), nil })
	defer restore()
	o := newAdvertisedAddrOverlay()
	o.startHost(func() []ma.Multiaddr { return []ma.Multiaddr{ma.StringCast("/ip6/::/udp/9911/quic-v1")} })
	oldAddr := ma.StringCast("/ip6/" + old + "/udp/9911/quic-v1")
	observed := ma.StringCast("/ip6/2001:4860:4860::8888/udp/9911/quic-v1")
	circuit := ma.StringCast("/ip6/" + old + "/udp/9911/quic-v1/p2p-circuit")
	input := []ma.Multiaddr{oldAddr, observed, circuit}
	if !manet.IsPublicAddr(oldAddr) {
		t.Fatal("fixture is not public")
	}
	if len(o.apply(input)) != len(input) {
		t.Fatal("initial factory unexpectedly changed addresses")
	}
	manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) { return avIPNetAddrs(current), nil })
	if _, err := o.refresh(time.Now()); err != nil {
		t.Fatal(err)
	}
	output := o.apply(input)
	contains := func(want ma.Multiaddr) bool {
		for _, a := range output {
			if a.Equal(want) {
				return true
			}
		}
		return false
	}
	if !contains(observed) || !contains(circuit) {
		t.Error("unrelated observed/circuit address removed")
	}
	if contains(oldAddr) {
		t.Error("first usable path still advertises the departed public IPv6 interface")
	}
}
