package main

import (
	"context"
	"net"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

func addressStrings(addrs []ma.Multiaddr) []string {
	values := make([]string, len(addrs))
	for i, addr := range addrs {
		values[i] = addr.String()
	}
	return values
}

func TestRelayAddressPlanPreservesIPv4WithoutIPv6Config(t *testing.T) {
	cfg := DefaultServerConfig()
	plan, err := buildRelayAddressPlan(cfg)
	if err != nil {
		t.Fatal(err)
	}
	wantListen := []string{"/ip4/0.0.0.0/tcp/4000/ws", "/ip4/0.0.0.0/tcp/4005", "/ip4/0.0.0.0/udp/4002/quic-v1"}
	wantAnnounce := []string{"/dns4/mknoun.xyz/tcp/4001/wss", "/ip4/13.60.15.36/tcp/4005", "/dns4/mknoun.xyz/udp/4002/quic-v1"}
	if got := addressStrings(plan.listen); !reflect.DeepEqual(got, wantListen) {
		t.Fatalf("listeners=%v, want %v", got, wantListen)
	}
	if got := addressStrings(plan.advertisedAddresses(nil)); !reflect.DeepEqual(got, wantAnnounce) {
		t.Fatalf("advertisements=%v, want %v", got, wantAnnounce)
	}
}

func TestRelayAddressPlanOnlyAdvertisesBoundOptedInIPv6(t *testing.T) {
	cfg := DefaultServerConfig()
	cfg.ServerIP6 = "2606:4700:4700::1111"
	for _, dnsEnabled := range []bool{false, true} {
		cfg.ServerDNSIPv6 = dnsEnabled
		plan, err := buildRelayAddressPlan(cfg)
		if err != nil {
			t.Fatal(err)
		}
		if len(plan.listen) != 6 {
			t.Fatalf("listeners=%v", plan.listen)
		}
		for _, addr := range plan.ipv6Listeners {
			if !strings.HasPrefix(addr.String(), "/ip6/2606:4700:4700::1111/") {
				t.Fatalf("listener does not bind configured address: %s", addr)
			}
		}
		// libp2p can retain successful IPv4 listeners after another listener
		// fails. Never announce IPv6 from that partial startup.
		for _, actual := range [][]ma.Multiaddr{nil, plan.listen[:3], plan.listen[:5]} {
			if plan.verifyIPv6Listeners(actual) == nil {
				t.Fatal("missing IPv6 transport was accepted")
			}
			if got := plan.advertisedAddresses(actual); len(got) != 3 {
				t.Fatalf("unbound IPv6 advertised: %v", got)
			}
		}
		if err := plan.verifyIPv6Listeners(plan.listen); err != nil {
			t.Fatal(err)
		}
		want := []string{
			"/dns4/mknoun.xyz/tcp/4001/wss", "/ip4/13.60.15.36/tcp/4005", "/dns4/mknoun.xyz/udp/4002/quic-v1",
			"/ip6/2606:4700:4700::1111/tcp/4005", "/ip6/2606:4700:4700::1111/udp/4002/quic-v1",
		}
		if dnsEnabled {
			want = append(want, "/dns6/mknoun.xyz/tcp/4001/wss", "/dns6/mknoun.xyz/udp/4002/quic-v1")
		}
		if got := addressStrings(plan.advertisedAddresses(plan.listen)); !reflect.DeepEqual(got, want) {
			t.Fatalf("DNS IPv6 enabled=%v: advertisements=%v, want %v", dnsEnabled, got, want)
		}
	}
}

func TestRelayAddressPlanRejectsUnusableIPv6(t *testing.T) {
	for _, ip := range []string{
		"not-an-ip", "192.0.2.1", "::ffff:192.0.2.1", "::", "::1",
		"fe80::1", "fe80::1%en0", "fd12::1", "ff02::1", "2001:db8::1",
		"3fff::1", "2001::1", "2002:c000:201::1", "64:ff9b::c000:201",
		"2606:4700:4700::1111%en0",
	} {
		t.Run(ip, func(t *testing.T) {
			cfg := DefaultServerConfig()
			cfg.ServerIP6 = ip
			if _, err := buildRelayAddressPlan(cfg); err == nil {
				t.Fatalf("invalid public IPv6 accepted: %s", ip)
			}
		})
	}
	cfg := DefaultServerConfig()
	cfg.ServerDNSIPv6 = true
	if _, err := buildRelayAddressPlan(cfg); err == nil {
		t.Fatal("DNS IPv6 enabled without an IPv6 listener")
	}
}

func TestRelayServerIPv6EnvIsExplicit(t *testing.T) {
	t.Setenv(relayPrivateKeyEnv, "")
	t.Setenv(relayServerIP6Env, "")
	t.Setenv(relayServerDNSIPv6Env, "")
	if cfg := loadServerConfigFromEnv(); cfg.ServerIP6 != "" || cfg.ServerDNSIPv6 {
		t.Fatal("IPv6 enabled without configuration")
	}
	t.Setenv(relayServerIP6Env, " 2606:4700:4700::1111 ")
	t.Setenv(relayServerDNSIPv6Env, "true")
	cfg := loadServerConfigFromEnv()
	if cfg.ServerIP6 != "2606:4700:4700::1111" || !cfg.ServerDNSIPv6 {
		t.Fatalf("IPv6 configuration was not loaded: address=%q DNS=%v", cfg.ServerIP6, cfg.ServerDNSIPv6)
	}
	t.Setenv(relayServerDNSIPv6Env, "false")
	if loadServerConfigFromEnv().ServerDNSIPv6 {
		t.Fatal("explicit DNS IPv6 disable ignored")
	}
}

func TestRelayAddressPlanRejectsInvalidPorts(t *testing.T) {
	for _, value := range []int{-1, 0, 65536} {
		for _, name := range []string{"ws", "tcp", "wss", "quic"} {
			cfg := DefaultServerConfig()
			switch name {
			case "ws":
				cfg.WSPort = value
			case "tcp":
				cfg.TCPPort = value
			case "wss":
				cfg.WSSPort = value
			case "quic":
				cfg.QUICPort = value
			}
			if _, err := buildRelayAddressPlan(cfg); err == nil {
				t.Fatalf("invalid %s port %d accepted", name, value)
			}
		}
	}
}

func TestRelayDualStackListenersAcceptTCPWebSocketAndQUIC(t *testing.T) {
	probe, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Skipf("IPv6 loopback unavailable on this host: %v", err)
	}
	_ = probe.Close()
	// Ephemeral loopback binds exercise actual transports. They do not pass
	// through the production public-address validator or get advertised.
	cfg := ServerConfig{}
	listen := append(relayTransportListenAddrs(cfg, "ip4", "127.0.0.1"), relayTransportListenAddrs(cfg, "ip6", "::1")...)
	server, err := libp2p.New(libp2p.ListenAddrs(listen...), libp2p.DisableRelay())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = server.Close() })
	actual := server.Network().ListenAddresses()
	if len(actual) != 6 {
		t.Fatalf("bound %d listeners, want all six: %v", len(actual), actual)
	}
	for _, addr := range actual {
		t.Run(addr.String(), func(t *testing.T) {
			client, err := libp2p.New(libp2p.NoListenAddrs, libp2p.DisableRelay())
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = client.Close() })
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := client.Connect(ctx, peer.AddrInfo{ID: server.ID(), Addrs: []ma.Multiaddr{addr}}); err != nil {
				t.Fatalf("connect through %s: %v", addr, err)
			}
			connections := client.Network().ConnsToPeer(server.ID())
			if len(connections) != 1 || !connections[0].RemoteMultiaddr().Equal(addr) {
				t.Fatalf("connection did not use requested transport %s", addr)
			}
		})
	}
}
