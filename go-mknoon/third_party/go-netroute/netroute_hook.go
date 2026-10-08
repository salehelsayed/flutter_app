package netroute

import "net"

// newRouterFailureHook, when non-nil, makes New() return a router whose every
// lookup fails with the returned error, before any kernel routing access. It is a TEST-ONLY seam
// (Test-Flight-Improv/190).
//
// basichost seeds filteredInterfaceAddrs from netroute.New()/Route BEFORE it
// calls manet.InterfaceMultiaddrs, and netroute succeeds on macOS. So a host
// test that only blocks the manet interface-address lane would still observe a
// real routed LAN address on the macOS CI box and false-green the Android
// "no local addresses" condition. This hook lets the test also block the
// netroute lane, reproducing Android — where netroute hits the same SELinux
// netlink denial and fails (logged at Debug level, gracefully degraded by every
// caller). Nil in production, so New() behaves exactly as upstream.
var newRouterFailureHook func() error

// SetNewFailureHookForTests installs a hook consulted at the top of New() and
// returns a function restoring the previous hook. Test-only.
func SetNewFailureHookForTests(hook func() error) (restore func()) {
	prev := newRouterFailureHook
	newRouterFailureHook = hook
	return func() { newRouterFailureHook = prev }
}

// failingRouter answers every lookup with err and never touches the kernel.
// New() returns it (with a nil error) instead of failing outright, because
// go-libp2p v0.50 quicreuse ignores the error from New() and wraps the router
// anyway, so a nil Router crashes the first QUIC dial (plan 406). A Route
// error, by contrast, is a case every caller already handles.
type failingRouter struct{ err error }

func (r failingRouter) Route(net.IP) (*net.Interface, net.IP, net.IP, error) {
	return nil, nil, nil, r.err
}

func (r failingRouter) RouteWithSrc(net.HardwareAddr, net.IP, net.IP) (*net.Interface, net.IP, net.IP, error) {
	return nil, nil, nil, r.err
}
