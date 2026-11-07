package main

import (
	"bytes"
	"context"
	"log"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func missingRouteBackend(t *testing.T, kind string) PushTokenBackend {
	t.Helper()
	switch kind {
	case "memory":
		return newMemoryPushTokenStore()
	case "redis_legacy":
		_, backend := plan367RedisBackend(t, "missing-route:", nil)
		return backend
	case "redis_encrypted":
		_, backend, _ := plan367NewEncryptedFixture(t, "missing-route:")
		return backend
	default:
		t.Fatalf("unknown test backend %q", kind)
		return nil
	}
}

func missingRouteMetric(t *testing.T, reason, platform string) float64 {
	t.Helper()
	families, err := prometheus.DefaultGatherer.Gather()
	if err != nil {
		t.Fatalf("gather metrics: %v", err)
	}
	for _, family := range families {
		if family.GetName() != "relay_push_missing_route_total" {
			continue
		}
		for _, metric := range family.Metric {
			labels := make(map[string]string)
			for _, pair := range metric.Label {
				labels[pair.GetName()] = pair.GetValue()
			}
			if labels["reason"] == reason && labels["platform"] == platform {
				return metric.GetCounter().GetValue()
			}
		}
	}
	return 0
}

func missingRouteSend(push *PushService, scope string) {
	if scope == "direct" {
		push.SendNotification(context.Background(), "route-peer", "sender-peer", `{"id":"missing-direct","text":"private body"}`)
		return
	}
	push.SendGroupNotification(context.Background(), "route-peer", "group-private", "sender-peer", "missing-group", `{"id":"missing-group","text":"private body"}`)
}

// Exercise real route registration/removal and both existing provider-free nil
// branches. These tests compile before the diagnostics exist and fail on their
// absent reason records, rather than a missing test-only production interface.
func TestPushMissingRouteReasons(t *testing.T) {
	for _, kind := range []string{"memory", "redis_legacy", "redis_encrypted"} {
		for _, scope := range []string{"direct", "group"} {
			for _, reason := range []string{"unknown", "unregistered_by_client", "revoked_after_provider_rejection"} {
				t.Run(kind+"/"+scope+"/"+reason, func(t *testing.T) {
					backend := missingRouteBackend(t, kind)
					push := NewPushServiceWithBackend(backend)
					push.retryDelays = []time.Duration{0, 0}
					var providerCalls atomic.Int32
					push.sender = func(context.Context, *messaging.Message) (string, error) {
						providerCalls.Add(1)
						return "synthetic-result", nil
					}
					platform := "unknown"
					if reason != "unknown" {
						platform = "ios"
						if err := push.RegisterToken("route-peer", "private-provider-token", platform); err != nil {
							t.Fatalf("register: %v", err)
						}
					}
					switch reason {
					case "unregistered_by_client":
						if err := push.UnregisterToken("route-peer"); err != nil {
							t.Fatalf("unregister: %v", err)
						}
					case "revoked_after_provider_rejection":
						push.sender = nil
						push.client = plan367FirebaseClient(t, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
							providerCalls.Add(1)
							plan367WritePermanentFCMError(w)
						}))
						missingRouteSend(push, scope)
						if providerCalls.Load() != 1 {
							t.Fatalf("typed provider rejection calls = %d, want 1", providerCalls.Load())
						}
					}
					if route, err := backend.LookupRoute("route-peer"); err != nil || route != nil {
						t.Fatalf("expected absent route: route=%v error=%v", route != nil, err)
					}

					journal := &bytes.Buffer{}
					previousWriter := log.Writer()
					log.SetOutput(journal)
					defer log.SetOutput(previousWriter)
					beforeCalls := providerCalls.Load()
					beforeMissing := testutil.ToFloat64(pushSentCounter.WithLabelValues("missing_token"))
					beforeReason := missingRouteMetric(t, reason, platform)
					missingRouteSend(push, scope)
					if providerCalls.Load() != beforeCalls {
						t.Fatalf("missing route started provider work: before=%d after=%d", beforeCalls, providerCalls.Load())
					}
					if delta := testutil.ToFloat64(pushSentCounter.WithLabelValues("missing_token")) - beforeMissing; delta != 1 {
						t.Errorf("existing missing_token delta = %v, want 1", delta)
					}
					want := "[PUSH] outcome=missing_route missing_route_reason=" + reason
					if !strings.Contains(journal.String(), want) {
						t.Errorf("journal = %q, want closed reason record %q", journal.String(), want)
					}
					if delta := missingRouteMetric(t, reason, platform) - beforeReason; delta != 1 {
						t.Errorf("missing reason metric delta = %v, want 1", delta)
					}
					for _, forbidden := range []string{"route-peer", "sender-peer", "group-private", "private-provider-token", "private body", "platform="} {
						if strings.Contains(journal.String(), forbidden) {
							t.Errorf("missing-route record contains private value or forbidden key")
						}
					}
				})
			}
		}
	}
}
