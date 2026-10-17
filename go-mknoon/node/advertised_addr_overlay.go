package node

import (
	"slices"
	"sync"
	"time"

	ma "github.com/multiformats/go-multiaddr"
	manet "github.com/multiformats/go-multiaddr/net"
)

// advertisedAddrOverlayWindow is how long a path-event snapshot stays in
// force. libp2p re-reads the interfaces at most once per minute
// (basic/addrs_manager.go interfaceAddrsCacheTTL) and recomputes addresses on
// a 5 s ticker, so after this window its own view is current again and the
// overlay steps aside.
const advertisedAddrOverlayWindow = 70 * time.Second

// advertisedAddrOverlay keeps h.Addrs() honest right after a network path
// change. libp2p resolves the wildcard listen addresses against an interface
// snapshot it refreshes at most once a minute, so after Wi-Fi -> LTE the host
// would keep announcing the dead Wi-Fi address for up to a minute. On a path
// event the node takes its own snapshot through the same provider libp2p uses
// (manet.InterfaceMultiaddrs, anet on Android). Until libp2p's cache has
// certainly caught up the host's AddrsFactory drops addresses of interfaces
// that are gone and adds the current interfaces' addresses. Outside that
// window, and until the first path event, it is the identity.
type advertisedAddrOverlay struct {
	mu sync.RWMutex
	// ifaceAddrs is the interface snapshot of the last path event (/ip4/x,
	// /ip6/y), current holds the same IPs as a set.
	ifaceAddrs []ma.Multiaddr
	current    map[string]struct{}
	// seen holds every interface IP snapshotted this host generation. A
	// public interface IP (an LTE IPv6) that disappears is only known to be
	// an interface address because it was seen here.
	seen  map[string]struct{}
	until time.Time
	// listenAddrs reports the host's current listen addresses. It is read at
	// apply time because the QUIC listeners move on the same path event.
	listenAddrs func() []ma.Multiaddr
}

func newAdvertisedAddrOverlay() *advertisedAddrOverlay {
	return &advertisedAddrOverlay{seen: make(map[string]struct{})}
}

// reset forgets the snapshots of a previous host generation.
func (o *advertisedAddrOverlay) reset() {
	o.mu.Lock()
	defer o.mu.Unlock()
	o.ifaceAddrs, o.current, o.until, o.listenAddrs = nil, nil, time.Time{}, nil
	o.seen = make(map[string]struct{})
}

// startHost prepares the overlay for a new host generation: it forgets the
// previous one, records the interface IPs present now as seen, and installs
// the host's listen-address source. The seed is what lets the first path
// event tell a departed public interface address (the LTE IPv6 the node
// started on) from an observed NAT address, which is kept. Nothing is armed:
// until the first path event the overlay stays the identity.
func (o *advertisedAddrOverlay) startHost(listenAddrs func() []ma.Multiaddr) {
	addrs, err := manet.InterfaceMultiaddrs()
	o.mu.Lock()
	defer o.mu.Unlock()
	o.ifaceAddrs, o.current, o.until = nil, nil, time.Time{}
	o.seen = make(map[string]struct{})
	o.listenAddrs = listenAddrs
	if err != nil {
		return
	}
	for _, a := range addrs {
		if manet.IsIP6LinkLocal(a) {
			continue
		}
		if ip := extractIP(a); ip != nil {
			o.seen[ip.String()] = struct{}{}
		}
	}
}

// refresh snapshots the interfaces now and arms the overlay for one window.
// On an enumeration error the overlay is disarmed, so a platform that denies
// enumeration keeps libp2p's own behavior.
func (o *advertisedAddrOverlay) refresh(now time.Time) (int, error) {
	addrs, err := manet.InterfaceMultiaddrs()
	o.mu.Lock()
	defer o.mu.Unlock()
	if err != nil {
		o.ifaceAddrs, o.current, o.until = nil, nil, time.Time{}
		return 0, err
	}
	addrs = slices.DeleteFunc(addrs, manet.IsIP6LinkLocal)
	current := make(map[string]struct{}, len(addrs))
	for _, a := range addrs {
		if ip := extractIP(a); ip != nil {
			current[ip.String()] = struct{}{}
			o.seen[ip.String()] = struct{}{}
		}
	}
	o.ifaceAddrs, o.current, o.until = addrs, current, now.Add(advertisedAddrOverlayWindow)
	return len(addrs), nil
}

// wrap returns the AddrsFactory to install: the overlay first, then the
// node's own filter, so what the overlay adds is filtered like everything else.
func (o *advertisedAddrOverlay) wrap(base func([]ma.Multiaddr) []ma.Multiaddr) func([]ma.Multiaddr) []ma.Multiaddr {
	return func(addrs []ma.Multiaddr) []ma.Multiaddr {
		return base(o.apply(addrs))
	}
}

// apply removes addresses of interfaces that are gone and adds the current
// interfaces' addresses for every wildcard listen address. An address is
// treated as interface-born when its IP is not public or was seen on an
// interface before; public NAT or observed addresses are left to libp2p.
// Added addresses are never public: this node is forced-private, and public
// interface addresses follow libp2p's own policy once its cache refreshes.
func (o *advertisedAddrOverlay) apply(addrs []ma.Multiaddr) []ma.Multiaddr {
	o.mu.RLock()
	defer o.mu.RUnlock()
	if o.current == nil || o.listenAddrs == nil || time.Now().After(o.until) {
		return addrs
	}
	out := make([]ma.Multiaddr, 0, len(addrs)+len(o.ifaceAddrs))
	for _, a := range addrs {
		if !o.goneInterfaceAddr(a) {
			out = append(out, a)
		}
	}
	for _, la := range o.listenAddrs() {
		if !manet.IsIPUnspecified(la) {
			continue
		}
		resolved, err := manet.ResolveUnspecifiedAddress(la, o.ifaceAddrs)
		if err != nil {
			continue
		}
		for _, r := range resolved {
			if !manet.IsPublicAddr(r) {
				out = append(out, r)
			}
		}
	}
	return out
}

func (o *advertisedAddrOverlay) goneInterfaceAddr(a ma.Multiaddr) bool {
	if isCircuitAddr(a) {
		return false
	}
	ip := extractIP(a)
	if ip == nil || ip.IsLoopback() {
		return false
	}
	key := ip.String()
	if _, present := o.current[key]; present {
		return false
	}
	if _, known := o.seen[key]; known {
		return true
	}
	return !manet.IsPublicAddr(a)
}
