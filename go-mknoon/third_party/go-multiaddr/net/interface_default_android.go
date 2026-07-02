//go:build android

package manet

import (
	"net"

	"github.com/wlynxg/anet"
)

// defaultInterfaceAddrsProvider on Android uses wlynxg/anet instead of the
// standard library. anet enumerates interface addresses via RTM_GETADDR plus
// ioctl and never performs the netlink route-socket bind that Android's SELinux
// policy denies for apps targeting SDK >= 30 (b/155595000). This is what makes
// the node's h.Addrs() non-empty on Android 11+. anet auto-detects the Android
// API level via cgo (gomobile always builds cgo), so no explicit version needs
// to be injected here.
func defaultInterfaceAddrsProvider() ([]net.Addr, error) {
	return anet.InterfaceAddrs()
}
