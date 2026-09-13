package node

import (
	"context"
	"errors"
	"net"
	"net/netip"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
	ma "github.com/multiformats/go-multiaddr"
)

// ConnectionDiagnostic is an operation-local, bounded sidecar, never a log or
// routing input. Only these coarse values cross the bridge. No peer/address,
// errors, stream IDs, candidate lists, or message material are retained.
type ConnectionDiagnostic struct {
	Stage    string `json:"connectionStage"`
	Outcome  string `json:"connectionOutcome"`
	Family   string `json:"addressFamily"`
	Protocol string `json:"transportProtocol"`
	Path     string `json:"pathClass"`
	Leg      string `json:"observedLeg"`
	Fallback string `json:"familyFallback"`
}

const maxConnectionDiagnostics = 12

type connectionDiagnosticsKey struct{}
type connectionDiagnostics struct {
	records []ConnectionDiagnostic
	target  peer.ID // operation-local correlation only; never serialized
	leg     string
	failed  map[diagnosticRoute]bool
}

type diagnosticRoute struct{ family, protocol, path, leg string }

func (d *connectionDiagnostics) setTarget(target peer.ID) {
	if d == nil {
		return
	}
	if d.target != target {
		d.failed = nil
	}
	d.target = target
}

func unknownConnectionDiagnostic(stage, outcome string) ConnectionDiagnostic {
	return ConnectionDiagnostic{stage, outcome, "unknown", "unknown", "unknown", "unknown", "unknown"}
}

func (d *connectionDiagnostics) add(record ConnectionDiagnostic) {
	if d == nil {
		return
	}
	// Retain the first candidate failures and the latest operation boundaries.
	if len(d.records) == maxConnectionDiagnostics {
		copy(d.records[4:], d.records[5:])
		d.records = d.records[:maxConnectionDiagnostics-1]
	}
	d.records = append(d.records, record)
}

func diagnosticsFromContext(ctx context.Context) *connectionDiagnostics {
	d, _ := ctx.Value(connectionDiagnosticsKey{}).(*connectionDiagnostics)
	return d
}

// Multiaddr syntax is parsed without resolving DNS. A circuit prefix names
// the endpoint-to-relay leg only, never the unobserved relay-to-peer socket.
func diagnosticAddress(addr ma.Multiaddr) (family, protocol, path, leg string) {
	family, protocol, path, leg = "unknown", "unknown", "direct", "endpoint_to_peer"
	if addr == nil {
		return "unknown", "unknown", "unknown", "unknown"
	}
	count := 0
	tls := false
	ma.ForEach(addr, func(c ma.Component) bool {
		switch c.Protocol().Code {
		case ma.P_CIRCUIT:
			path, leg = "circuit", "endpoint_to_relay"
			return false
		case ma.P_IP4, ma.P_IP6:
			count++
			ip, err := netip.ParseAddr(c.Value())
			if err != nil || ambiguousDiagnosticIP(ip) {
				family = "unknown"
				break
			}
			if ip.Is4() {
				family = "ipv4"
			} else {
				family = "ipv6"
			}
		case ma.P_DNS, ma.P_DNS4, ma.P_DNS6, ma.P_DNSADDR:
			count++ // A DNS record is not a selected numeric route.
			family = "unknown"
		case ma.P_TCP:
			protocol = "tcp"
		case ma.P_TLS:
			tls = true
		case ma.P_QUIC, ma.P_QUIC_V1:
			protocol = "quic"
		case ma.P_WS:
			protocol = "ws"
			if tls {
				protocol = "wss"
			}
		case ma.P_WSS:
			protocol = "wss"
		}
		return true
	})
	if count != 1 {
		family = "unknown"
	}
	return
}

func ambiguousDiagnosticIP(ip netip.Addr) bool {
	if !ip.IsValid() || ip.Is4In6() || ip.IsUnspecified() {
		return true
	}
	if ip.Is6() && !ip.IsLoopback() {
		// IPv4-compatible addresses have the same ambiguity in hex and dotted form.
		bytes := ip.As16()
		compatible := true
		for _, b := range bytes[:12] {
			compatible = compatible && b == 0
		}
		return compatible
	}
	return false
}

func (d *connectionDiagnostics) established(h host.Host) {
	if d == nil {
		return
	}
	defer func() { _ = recover() }()
	for i, conn := range h.Network().ConnsToPeer(d.target) {
		if i == 4 {
			break
		}
		d.connection(conn, "established")
	}
}

func diagnosticConnection(conn network.Conn, stage string) ConnectionDiagnostic {
	r := unknownConnectionDiagnostic(stage, "ok")
	if conn == nil {
		return r
	}
	r.Family, r.Protocol, r.Path, r.Leg = diagnosticAddress(conn.RemoteMultiaddr())
	// Some circuit implementations expose only /p2p/.../p2p-circuit; an address
	// prefix, when present, is still not independent evidence of the relay socket.
	if r.Path == "circuit" || (conn.LocalMultiaddr() != nil && isCircuitAddr(conn.LocalMultiaddr())) {
		r.Path, r.Leg, r.Family, r.Protocol = "circuit", "endpoint_to_relay", "unknown", "unknown"
	}
	return r
}

func (d *connectionDiagnostics) failedDial(err error) {
	if d == nil || err == nil {
		return
	}
	defer func() { _ = recover() }() // Observation cannot replace a dial result.
	var dial *swarm.DialError
	if !errors.As(err, &dial) || dial == nil || dial.Peer != d.target {
		return
	}
	for i, attempt := range dial.DialErrors {
		if i == 4 {
			break
		}
		// Backoff, filtering and absent addresses also appear in DialError. Only
		// an actual socket dial failure qualifies as candidate-attempt evidence.
		var op *net.OpError
		if !errors.As(attempt.Cause, &op) || op.Op != "dial" {
			continue
		}
		r := unknownConnectionDiagnostic("candidate_failed", "failed")
		r.Family, r.Protocol, r.Path, r.Leg = diagnosticAddress(attempt.Address)
		if d.leg == "endpoint_to_relay" {
			r.Leg = d.leg
		}
		if r.Path == "direct" && r.Family != "unknown" && r.Protocol != "unknown" {
			if d.failed == nil {
				d.failed = make(map[diagnosticRoute]bool)
			}
			d.failed[diagnosticRoute{r.Family, r.Protocol, r.Path, r.Leg}] = true
		}
		d.add(r)
	}
}

func (d *connectionDiagnostics) connection(conn network.Conn, stage string) {
	if d == nil {
		return
	}
	defer func() { _ = recover() }()
	r := diagnosticConnection(conn, stage)
	if d.leg == "endpoint_to_relay" {
		r.Leg = d.leg
	}
	// Correlation is limited to this command, the same observed leg and protocol.
	// Circuit prefixes cannot certify a selected relay socket; leave them unknown.
	if r.Path == "direct" && r.Family != "unknown" && r.Protocol != "unknown" {
		opposite := "ipv6"
		if r.Family == "ipv6" {
			opposite = "ipv4"
		}
		if d.failed[diagnosticRoute{opposite, r.Protocol, r.Path, r.Leg}] {
			r.Fallback = opposite + "_to_" + r.Family
		}
	}
	d.add(r)
}

func (d *connectionDiagnostics) stream(s network.Stream, err error) {
	if d == nil {
		return
	}
	defer func() { _ = recover() }()
	if err != nil {
		d.failedDial(err)
		d.add(unknownConnectionDiagnostic("stream_failed", "failed"))
	} else if s != nil {
		d.connection(s.Conn(), "stream_opened")
	}
}
