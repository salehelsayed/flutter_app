package manet

import (
	"net"
	"sync/atomic"
)

// InterfaceAddrsProvider returns the machine's unicast interface addresses,
// mirroring the contract of the standard library's net.InterfaceAddrs.
//
// The indirection exists to work around an Android platform restriction: on
// Android 11+ (apps targeting SDK >= 30) SELinux denies the Go runtime's
// netlink route-socket bind (b/155595000). net.InterfaceAddrs binds a netlink
// socket under the hood (syscall.NetlinkRIB), so it fails there and the host
// enumerates no local addresses. The default provider is selected per build
// tag: the stdlib on every non-Android platform (byte-for-byte the upstream
// behavior — see interface_default_other.go) and wlynxg/anet on Android, which
// enumerates via RTM_GETADDR + ioctl without the denied bind (see
// interface_default_android.go).
type InterfaceAddrsProvider func() ([]net.Addr, error)

// interfaceAddrsProvider holds the active provider. It is read at host
// construction AND from basichost's address-change ticker goroutine, so every
// access goes through an atomic pointer.
var interfaceAddrsProvider atomic.Pointer[InterfaceAddrsProvider]

func init() {
	def := InterfaceAddrsProvider(defaultInterfaceAddrsProvider)
	interfaceAddrsProvider.Store(&def)
}

// currentInterfaceAddrs invokes the active interface-address provider.
func currentInterfaceAddrs() ([]net.Addr, error) {
	return (*interfaceAddrsProvider.Load())()
}

// SetInterfaceAddrsProviderForTests swaps the interface-address provider and
// returns a function that restores the previous one. It is a TEST-ONLY seam
// (Test-Flight-Improv/190): it lets a host test reproduce the Android condition
// (raw netlink enumeration denied) by injecting an anet-shaped provider that
// returns addresses, or an error-returning provider that returns the netlink
// permission-denied error. Production code never calls it.
func SetInterfaceAddrsProviderForTests(p InterfaceAddrsProvider) (restore func()) {
	prev := interfaceAddrsProvider.Load()
	interfaceAddrsProvider.Store(&p)
	return func() { interfaceAddrsProvider.Store(prev) }
}
