package main

import "github.com/prometheus/client_golang/prometheus"

var callDiagnosticStorageReady = prometheus.NewGauge(prometheus.GaugeOpts{Name: "relay_call_diagnostics_storage_ready", Help: "Whether separate durable diagnostic storage initialized."})
var callDiagnosticEvents = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "relay_call_diagnostics_events_total", Help: "Bounded diagnostic ingestion and loss outcomes; no attempt identifiers."}, []string{"outcome"})

func init() {
	prometheus.MustRegister(callDiagnosticEvents, callDiagnosticStorageReady)
	for _, outcome := range []string{"accepted", "rejected", "sink_unavailable", "queue_full", "quota_exceeded"} {
		callDiagnosticEvents.WithLabelValues(outcome).Add(0)
	}
}
func (s *callDiagnosticStore) drop(outcome string) {
	if s != nil {
		s.dropped.Add(1)
	}
	switch outcome {
	case "queue_full", "quota_exceeded":
	default:
		outcome = "sink_unavailable"
	}
	callDiagnosticEvents.WithLabelValues(outcome).Inc()
}
