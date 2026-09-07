package main

import (
	"fmt"
	"net/netip"
	"strings"

	ma "github.com/multiformats/go-multiaddr"
)

// IPv6 is opt-in so IPv4-only deployments do not advertise unconfigured IPv6.
// A DNS IPv6 advertisement also requires the operator to have enabled IPv6 on
// the TLS proxy and published its AAAA record.
type relayAddressPlan struct {
	listen            []ma.Multiaddr
	announce          []ma.Multiaddr
	ipv6Listeners     []ma.Multiaddr
	ipv4Announcements int
}

func buildRelayAddressPlan(cfg ServerConfig) (relayAddressPlan, error) {
	var plan relayAddressPlan
	for _, port := range []struct {
		name  string
		value int
	}{
		{relayWSPortEnv, cfg.WSPort}, {relayTCPPortEnv, cfg.TCPPort},
		{relayWSSPortEnv, cfg.WSSPort}, {relayQUICPortEnv, cfg.QUICPort},
	} {
		if port.value < 1 || port.value > 65535 {
			return plan, fmt.Errorf("%s must be between 1 and 65535", port.name)
		}
	}
	ip6 := strings.TrimSpace(cfg.ServerIP6)
	if cfg.ServerDNSIPv6 && ip6 == "" {
		return plan, fmt.Errorf("%s requires %s", relayServerDNSIPv6Env, relayServerIP6Env)
	}
	if ip6 != "" {
		addr, err := netip.ParseAddr(ip6)
		if err != nil || !publicRelayIPv6(addr) {
			return plan, fmt.Errorf("%s must be a public native IPv6 address without a zone", relayServerIP6Env)
		}
		ip6 = addr.String()
	}
	plan.listen = relayTransportListenAddrs(cfg, "ip4", "0.0.0.0")
	for _, raw := range []string{
		fmt.Sprintf("/dns4/%s/tcp/%d/wss", cfg.ServerDNS, cfg.WSSPort),
		fmt.Sprintf("/ip4/%s/tcp/%d", cfg.ServerIP4, cfg.TCPPort),
		fmt.Sprintf("/dns4/%s/udp/%d/quic-v1", cfg.ServerDNS, cfg.QUICPort),
	} {
		addr, err := ma.NewMultiaddr(raw)
		if err != nil {
			return plan, fmt.Errorf("invalid relay advertisement: %w", err)
		}
		plan.announce = append(plan.announce, addr)
	}
	plan.ipv4Announcements = len(plan.announce)
	if ip6 == "" {
		return plan, nil
	}
	// Bind this address, not ::, so an unassigned configured address cannot
	// silently become a public advertisement from a wildcard listener.
	plan.ipv6Listeners = relayTransportListenAddrs(cfg, "ip6", ip6)
	plan.listen = append(plan.listen, plan.ipv6Listeners...)
	plan.announce = append(plan.announce,
		ma.StringCast(fmt.Sprintf("/ip6/%s/tcp/%d", ip6, cfg.TCPPort)),
		ma.StringCast(fmt.Sprintf("/ip6/%s/udp/%d/quic-v1", ip6, cfg.QUICPort)),
	)
	if cfg.ServerDNSIPv6 {
		plan.announce = append(plan.announce,
			ma.StringCast(fmt.Sprintf("/dns6/%s/tcp/%d/wss", cfg.ServerDNS, cfg.WSSPort)),
			ma.StringCast(fmt.Sprintf("/dns6/%s/udp/%d/quic-v1", cfg.ServerDNS, cfg.QUICPort)),
		)
	}
	return plan, nil
}

func publicRelayIPv6(addr netip.Addr) bool {
	if !addr.Is6() || addr.Is4In6() || addr.Zone() != "" || !addr.IsGlobalUnicast() || addr.IsPrivate() {
		return false
	}
	// Require native globally allocated unicast space, excluding documentation,
	// protocol assignments and deprecated 6to4. This is address validation, not a
	// claim that external routing or firewall reachability has been verified.
	if !netip.MustParsePrefix("2000::/3").Contains(addr) {
		return false
	}
	for _, reserved := range []string{"2001::/23", "2001:db8::/32", "2002::/16", "3fff::/20"} {
		if netip.MustParsePrefix(reserved).Contains(addr) {
			return false
		}
	}
	return true
}

// Kept separate from public advertisement validation so local transport tests
// can exercise ::1 without weakening the production configuration contract.
func relayTransportListenAddrs(cfg ServerConfig, family, ip string) []ma.Multiaddr {
	return []ma.Multiaddr{
		ma.StringCast(fmt.Sprintf("/%s/%s/tcp/%d/ws", family, ip, cfg.WSPort)),
		ma.StringCast(fmt.Sprintf("/%s/%s/tcp/%d", family, ip, cfg.TCPPort)),
		ma.StringCast(fmt.Sprintf("/%s/%s/udp/%d/quic-v1", family, ip, cfg.QUICPort)),
	}
}

func (p relayAddressPlan) verifyIPv6Listeners(actual []ma.Multiaddr) error {
	for _, expected := range p.ipv6Listeners {
		found := false
		for _, addr := range actual {
			if expected.Equal(addr) {
				found = true
				break
			}
		}
		if !found {
			return fmt.Errorf("configured IPv6 listener did not bind: %s", expected)
		}
	}
	return nil
}

func (p relayAddressPlan) advertisedAddresses(actual []ma.Multiaddr) []ma.Multiaddr {
	if p.verifyIPv6Listeners(actual) != nil {
		return append([]ma.Multiaddr(nil), p.announce[:p.ipv4Announcements]...)
	}
	return append([]ma.Multiaddr(nil), p.announce...)
}
