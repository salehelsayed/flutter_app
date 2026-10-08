package main

import (
	"net/netip"
	"strings"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/network"
	rcmgr "github.com/libp2p/go-libp2p/p2p/host/resource-manager"
	"github.com/libp2p/go-libp2p/x/rate"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/prometheus/client_golang/prometheus"
)

// Plan 406 (decision D3): go-libp2p v0.42+ rate-limits NEW connections per
// source address by default (0.2/s per IPv4 address, burst 16). Many phones
// share one carrier-NAT IPv4 address, so the relay raises the limit well above
// that load instead of turning it off, and counts every connection the
// resource manager refuses.
var connAdmissionRejected = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "relay_conn_admission_rejected_total", Help: "Connections refused by the libp2p resource manager, by reason."}, []string{"reason"})

func init() {
	prometheus.MustRegister(connAdmissionRejected)
	for _, reason := range []string{"rate_limit", "per_ip_limit", "other"} {
		connAdmissionRejected.WithLabelValues(reason).Add(0)
	}
}

func relayConnRateLimiter() *rate.Limiter {
	return &rate.Limiter{
		// Loopback stays unlimited, as in go-libp2p's default.
		NetworkPrefixLimits: []rate.PrefixLimit{
			{Prefix: netip.MustParsePrefix("127.0.0.0/8"), Limit: rate.Limit{}},
			{Prefix: netip.MustParsePrefix("::1/128"), Limit: rate.Limit{}},
		},
		SubnetRateLimiter: rate.SubnetLimiter{
			IPv4SubnetLimits: []rate.SubnetLimit{
				{PrefixLength: 32, Limit: rate.Limit{RPS: 20, Burst: 200}},
			},
			IPv6SubnetLimits: []rate.SubnetLimit{
				{PrefixLength: 56, Limit: rate.Limit{RPS: 20, Burst: 200}},
				{PrefixLength: 48, Limit: rate.Limit{RPS: 50, Burst: 1000}},
			},
			GracePeriod: time.Minute,
		},
	}
}

// newRelayResourceManager builds go-libp2p's default resource manager (same
// limits as libp2p.DefaultResourceManager) with only the connection rate
// limiter replaced, wrapped so refusals are counted.
func newRelayResourceManager() (network.ResourceManager, error) {
	limits := rcmgr.DefaultLimits
	libp2p.SetDefaultServiceLimits(&limits)
	mgr, err := rcmgr.NewResourceManager(
		rcmgr.NewFixedLimiter(limits.AutoScale()),
		rcmgr.WithConnRateLimiters(relayConnRateLimiter()),
	)
	if err != nil {
		return nil, err
	}
	return &countingResourceManager{ResourceManager: mgr}, nil
}

type countingResourceManager struct {
	network.ResourceManager
}

func (m *countingResourceManager) OpenConnection(dir network.Direction, usefd bool, endpoint ma.Multiaddr) (network.ConnManagementScope, error) {
	scope, err := m.ResourceManager.OpenConnection(dir, usefd, endpoint)
	if err != nil {
		connAdmissionRejected.WithLabelValues(connAdmissionRejectReason(err)).Inc()
	}
	return scope, err
}

// The resource manager returns plain errors, so match its two messages
// (rcmgr.go openConnection).
func connAdmissionRejectReason(err error) string {
	msg := err.Error()
	switch {
	case strings.Contains(msg, "rate limit exceeded"):
		return "rate_limit"
	case strings.Contains(msg, "connections per ip limit exceeded"):
		return "per_ip_limit"
	default:
		return "other"
	}
}
