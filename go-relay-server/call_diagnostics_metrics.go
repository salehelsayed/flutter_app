package main

import (
	"sync/atomic"

	"github.com/prometheus/client_golang/prometheus"
)

var callDiagnosticStorageReady = prometheus.NewGauge(prometheus.GaugeOpts{Name: "relay_call_diagnostics_storage_ready", Help: "Whether separate durable diagnostic storage initialized."})
var callDiagnosticEvents = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "relay_call_diagnostics_events_total", Help: "Bounded diagnostic ingestion and loss outcomes; no attempt identifiers."}, []string{"outcome"})
var callDiagnosticMetricsStore atomic.Pointer[callDiagnosticStore]
var callDiagnosticOwnersAtLimit = prometheus.NewGaugeFunc(prometheus.GaugeOpts{
	Name:        "relay_diagnostics_owners_at_limit",
	Help:        "Number of diagnostic owners at or above the ordinary accounted byte limit.",
	ConstLabels: prometheus.Labels{"store": "call"},
}, func() float64 {
	store := callDiagnosticMetricsStore.Load()
	if store == nil {
		return 0
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	count := 0
	for owner, size := range store.ownerSizes {
		if size+store.ownerBindingReserves[owner] >= store.ownerQuota {
			count++
		}
	}
	return float64(count)
})

func init() {
	prometheus.MustRegister(callDiagnosticEvents, callDiagnosticStorageReady, callDiagnosticOwnersAtLimit)
	for _, outcome := range []string{"accepted", "rejected", "sink_unavailable", "queue_full", "quota_exceeded", "budget_exceeded"} {
		callDiagnosticEvents.WithLabelValues(outcome).Add(0)
	}
}

func callDiagnosticRefusalOutcome(reason string) string {
	switch reason {
	case "owner_bytes", "global_bytes", "record_bytes", "record_count":
		return "budget_exceeded"
	case "record_capacity":
		return "quota_exceeded"
	default:
		return "sink_unavailable"
	}
}

func (s *callDiagnosticStore) drop(outcome string) {
	if s != nil {
		s.dropped.Add(1)
	}
	switch outcome {
	case "queue_full", "quota_exceeded", "budget_exceeded":
	default:
		outcome = "sink_unavailable"
	}
	callDiagnosticEvents.WithLabelValues(outcome).Inc()
}
