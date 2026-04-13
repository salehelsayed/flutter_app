package pubsub

import (
	"context"

	"github.com/libp2p/go-libp2p/core/network"
)

func connectednessSupportsPubSub(c network.Connectedness) bool {
	return c == network.Connected || c == network.Limited
}

func withLimitedConn(ctx context.Context) context.Context {
	if ok, _ := network.GetAllowLimitedConn(ctx); ok {
		return ctx
	}
	return network.WithAllowLimitedConn(ctx, "pubsub")
}
