package main

import (
	"context"
	"io"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/prometheus/client_golang/prometheus"
)

func TestLL24ProductionRelayMetricsReservationAndTraffic(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	h := ll24Host(t)
	registry := prometheus.NewRegistry()
	service, err := newCircuitRelayService(h, DefaultServerLimits(), registry)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = service.Close() })
	before := relayMetricTotals(t, registry)
	destination, prober := ll24Host(t), ll24Host(t)
	if _, err := client.Reserve(ctx, destination, peer.AddrInfo{ID: h.ID(), Addrs: h.Addrs()}); err != nil {
		t.Fatal(err)
	}
	destination.SetStreamHandler("/mknoon/test/ll24-metrics/1", func(s network.Stream) {
		defer s.Close()
		_, _ = io.Copy(s, s)
	})
	circuit := h.Addrs()[0].Encapsulate(ma.StringCast("/p2p/" + h.ID().String() + "/p2p-circuit"))
	if err := prober.Connect(ctx, peer.AddrInfo{ID: destination.ID(), Addrs: []ma.Multiaddr{circuit}}); err != nil {
		t.Fatal(err)
	}
	s, err := prober.NewStream(network.WithAllowLimitedConn(ctx, "LL-24 metrics"), destination.ID(), "/mknoon/test/ll24-metrics/1")
	if err != nil {
		t.Fatal(err)
	}
	_ = s.SetDeadline(time.Now().Add(time.Second))
	payload := []byte("relay-metrics-traffic")
	if _, err := s.Write(payload); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, len(payload))
	if _, err := io.ReadFull(s, got); err != nil || string(got) != string(payload) {
		t.Fatalf("traffic read %q: %v", got, err)
	}
	_ = s.Close()
	_ = prober.Network().ClosePeer(destination.ID())
	wanted := []string{"libp2p_relaysvc_reservations_total", "libp2p_relaysvc_reservation_request_response_status_total", "libp2p_relaysvc_connections_total", "libp2p_relaysvc_connection_request_response_status_total", "libp2p_relaysvc_data_transferred_bytes_total"}
	deadline := time.Now().Add(time.Second)
	var after map[string]float64
	for {
		after = relayMetricTotals(t, registry)
		ready := after["libp2p_relaysvc_status"] == 1
		for _, name := range wanted {
			ready = ready && after[name] > before[name]
		}
		if ready {
			return
		}
		if time.Now().After(deadline) {
			break
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("production constructor did not publish reservation/traffic metrics: before=%v after=%v", before, after)
}

func relayMetricTotals(t *testing.T, registry *prometheus.Registry) map[string]float64 {
	t.Helper()
	families, err := registry.Gather()
	if err != nil {
		t.Fatal(err)
	}
	values := make(map[string]float64)
	for _, family := range families {
		for _, metric := range family.GetMetric() {
			if metric.Counter != nil {
				values[family.GetName()] += metric.GetCounter().GetValue()
			}
			if metric.Gauge != nil {
				values[family.GetName()] += metric.GetGauge().GetValue()
			}
		}
	}
	return values
}
