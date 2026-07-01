package node

import (
	"context"
	"fmt"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
)

// PingPeer actively pings peerIdStr over the libp2p ping protocol and returns the
// first round-trip time. It is the active-chat keepalive's liveness probe (183):
// the node is a ping RESPONDER by default (libp2p installs the handler when the
// host is created), and this is the first app-level CALLER.
//
// A nil host (node not started), an undecodable peer id, an unreachable peer, or
// a timeout all return an error — the bridge maps that to a best-effort "miss"
// (ok:false), never a hard failure. The [timeout] bounds the probe so a hung
// ping can never overlap the keepalive's next tick.
func (n *Node) PingPeer(peerIdStr string, timeout time.Duration) (time.Duration, error) {
	n.mu.RLock()
	h := n.host
	baseCtx := n.ctx
	n.mu.RUnlock()
	if h == nil {
		return 0, fmt.Errorf("node not started")
	}
	if baseCtx == nil {
		baseCtx = context.Background()
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return 0, fmt.Errorf("invalid peerId: %w", err)
	}

	ctx, cancel := context.WithTimeout(baseCtx, timeout)
	defer cancel()

	select {
	case res := <-ping.Ping(ctx, h, pid):
		if res.Error != nil {
			return 0, res.Error
		}
		return res.RTT, nil
	case <-ctx.Done():
		return 0, ctx.Err()
	}
}
