//go:build !android

package manet

import "net"

// defaultInterfaceAddrsProvider on every non-Android platform is the standard
// library's net.InterfaceAddrs — byte-for-byte the upstream go-multiaddr
// behavior. iOS and macOS take this path, so their address enumeration is
// unchanged by the fork.
func defaultInterfaceAddrsProvider() ([]net.Addr, error) {
	return net.InterfaceAddrs()
}
