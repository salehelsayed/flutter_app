package main

import (
	"errors"
	"net/netip"
	"testing"

	"github.com/libp2p/go-libp2p/core/network"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

// Plan 406 / D3: many phones share one carrier-NAT IPv4 address. go-libp2p's
// default (0.2 new connections/s per IPv4 address, burst 16) would refuse them,
// so the relay admits a burst of 200 per address and 20/s after that.
func TestRelayConnRateLimiterAdmitsCarrierNATBurstButStaysBounded(t *testing.T) {
	cases := []struct {
		name  string
		ip    string
		burst int
	}{
		{"ipv4 /32", "51.0.0.7", 200},
		{"ipv6 /56", "2a05:d016::7", 200},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			limiter := relayConnRateLimiter()
			ip := netip.MustParseAddr(tc.ip)
			for i := 0; i < tc.burst; i++ {
				if !limiter.Allow(ip) {
					t.Fatalf("connection %d from one %s address refused; want a burst of %d", i+1, tc.name, tc.burst)
				}
			}
			if limiter.Allow(ip) {
				t.Fatalf("connection %d from one %s address admitted; the limit must stay bounded", tc.burst+1, tc.name)
			}
		})
	}
}

func TestRelayConnRateLimiterKeepsLoopbackUnlimited(t *testing.T) {
	limiter := relayConnRateLimiter()
	for _, raw := range []string{"127.0.0.1", "::1"} {
		ip := netip.MustParseAddr(raw)
		for i := 0; i < 1000; i++ {
			if !limiter.Allow(ip) {
				t.Fatalf("loopback %s refused at connection %d", raw, i+1)
			}
		}
	}
}

// The relay's resource manager must actually use the raised limiter: 30 short
// connections from one public address in a row (each closed before the next,
// so the separate 8-concurrent-per-IP cap is not the limit under test).
func TestRelayResourceManagerAdmitsRapidConnectionsFromOneAddress(t *testing.T) {
	rm, err := newRelayResourceManager()
	if err != nil {
		t.Fatalf("newRelayResourceManager: %v", err)
	}
	t.Cleanup(func() { _ = rm.Close() })
	endpoint := ma.StringCast("/ip4/51.0.0.7/tcp/4001")
	for i := 0; i < 30; i++ {
		scope, err := rm.OpenConnection(network.DirInbound, true, endpoint)
		if err != nil {
			t.Fatalf("connection %d refused: %v", i+1, err)
		}
		scope.Done()
	}
}

type refusingResourceManager struct {
	network.ResourceManager
	err error
}

func (m refusingResourceManager) OpenConnection(network.Direction, bool, ma.Multiaddr) (network.ConnManagementScope, error) {
	return nil, m.err
}

func TestRelayResourceManagerCountsRefusedConnectionsByReason(t *testing.T) {
	cases := []struct {
		err    error
		reason string
	}{
		{errors.New("rate limit exceeded"), "rate_limit"},
		{errors.New("connections per ip limit exceeded for /ip4/51.0.0.7/tcp/4001"), "per_ip_limit"},
		{errors.New("resource limit exceeded"), "other"},
	}
	endpoint := ma.StringCast("/ip4/51.0.0.7/tcp/4001")
	for _, tc := range cases {
		before := testutil.ToFloat64(connAdmissionRejected.WithLabelValues(tc.reason))
		rm := &countingResourceManager{ResourceManager: refusingResourceManager{err: tc.err}}
		if _, err := rm.OpenConnection(network.DirInbound, true, endpoint); err == nil {
			t.Fatalf("%s: want the refusal passed through", tc.reason)
		}
		if got := testutil.ToFloat64(connAdmissionRejected.WithLabelValues(tc.reason)) - before; got != 1 {
			t.Fatalf("%s: counter moved by %v, want 1", tc.reason, got)
		}
	}
}
