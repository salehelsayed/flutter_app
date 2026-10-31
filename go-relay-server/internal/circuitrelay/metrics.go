package relay

import (
	upstream "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/relay"
	"github.com/prometheus/client_golang/prometheus"
)

// Sharing the upstream tracer also shares its collectors: patched and upstream
// relays can coexist in tests without duplicate Prometheus registration.
type MetricsTracer = upstream.MetricsTracer
type MetricsTracerOption = upstream.MetricsTracerOption

func WithRegisterer(reg prometheus.Registerer) MetricsTracerOption {
	return upstream.WithRegisterer(reg)
}

func NewMetricsTracer(opts ...MetricsTracerOption) MetricsTracer {
	return upstream.NewMetricsTracer(opts...)
}
