package netroute

// newRouterFailureHook, when non-nil, forces New() to fail with the returned
// error before it builds the kernel routing table. It is a TEST-ONLY seam
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
