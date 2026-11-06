// Package circuitrelay exposes the production relay to cross-module host fixtures.
package circuitrelay

import (
	"io"

	"github.com/libp2p/go-libp2p/core/host"
	relay "github.com/mknoon/relay-server/internal/circuitrelay"
)

// New starts the current production circuit relay on h.
func New(h host.Host) (io.Closer, error) {
	return relay.New(h)
}
