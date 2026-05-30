package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	dto "github.com/prometheus/client_model/go"
)

func metricValue(t *testing.T, metric prometheus.Metric) float64 {
	t.Helper()

	var out dto.Metric
	if err := metric.Write(&out); err != nil {
		t.Fatalf("write metric: %v", err)
	}
	if gauge := out.GetGauge(); gauge != nil {
		return gauge.GetValue()
	}
	if counter := out.GetCounter(); counter != nil {
		return counter.GetValue()
	}
	t.Fatalf("metric %T did not expose gauge or counter data", metric)
	return 0
}

func histogramSampleCount(t *testing.T, observer prometheus.Observer) uint64 {
	t.Helper()

	metric, ok := observer.(prometheus.Metric)
	if !ok {
		t.Fatalf("observer %T does not expose a prometheus metric", observer)
	}

	var out dto.Metric
	if err := metric.Write(&out); err != nil {
		t.Fatalf("write histogram metric: %v", err)
	}
	histogram := out.GetHistogram()
	if histogram == nil {
		t.Fatalf("observer %T did not write histogram data", observer)
	}
	return histogram.GetSampleCount()
}

func TestRelayMetricsDeltas(t *testing.T) {
	const proto = "metrics_contract"

	beforeStored := metricValue(t, inboxStoredCounter)
	beforePending := metricValue(t, inboxMessagesPending)
	beforeActiveStreams := metricValue(t, activeStreams.WithLabelValues(proto))
	beforeStreamErrors := metricValue(
		t,
		streamErrorsCounter.WithLabelValues(proto, "decode"),
	)
	histogram := streamDuration.WithLabelValues(proto, "ok")
	beforeDurationCount := histogramSampleCount(t, histogram)

	inboxStoredCounter.Inc()
	inboxMessagesPending.Inc()
	inboxMessagesPending.Inc()
	inboxMessagesPending.Dec()
	activeStreams.WithLabelValues(proto).Inc()
	streamErrorsCounter.WithLabelValues(proto, "decode").Inc()
	streamDuration.WithLabelValues(proto, "ok").Observe(0.02)

	if got := metricValue(t, inboxStoredCounter) - beforeStored; got != 1 {
		t.Fatalf("relay_inbox_stored_total delta = %v, want 1", got)
	}
	if got := metricValue(t, inboxMessagesPending) - beforePending; got != 1 {
		t.Fatalf("relay_inbox_messages_pending delta = %v, want 1", got)
	}
	if got := metricValue(t, activeStreams.WithLabelValues(proto)) - beforeActiveStreams; got != 1 {
		t.Fatalf("relay_active_streams delta = %v, want 1", got)
	}
	if got := metricValue(t, streamErrorsCounter.WithLabelValues(proto, "decode")) - beforeStreamErrors; got != 1 {
		t.Fatalf("relay_stream_errors_total delta = %v, want 1", got)
	}
	if got := histogramSampleCount(t, histogram) - beforeDurationCount; got != 1 {
		t.Fatalf("relay_stream_duration_seconds count delta = %d, want 1", got)
	}
}

func TestRelayMetricsHandlerScrapeContract(t *testing.T) {
	const proto = "metrics_contract_scrape"

	inboxStoredCounter.Inc()
	activeStreams.WithLabelValues(proto).Set(3)
	streamDuration.WithLabelValues(proto, "ok").Observe(0.03)

	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	rec := httptest.NewRecorder()
	promhttp.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("/metrics status = %d, want %d", rec.Code, http.StatusOK)
	}

	body := rec.Body.String()
	for _, want := range []string{
		"# HELP relay_inbox_stored_total Messages accepted into inbox.",
		"relay_inbox_stored_total",
		"relay_active_streams{proto=\"metrics_contract_scrape\"} 3",
		"relay_stream_duration_seconds_count{proto=\"metrics_contract_scrape\",result=\"ok\"}",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("/metrics scrape missing %q", want)
		}
	}

	for _, forbidden := range []string{
		"12D3Koo",
		"/p2p/",
		"messageBody",
		"conversationId",
	} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("/metrics scrape leaked forbidden fragment %q", forbidden)
		}
	}
}
