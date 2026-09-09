package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/prometheus/client_golang/prometheus"
)

func callMetricsSnapshot(t *testing.T) map[string]float64 {
	t.Helper()
	families, err := prometheus.DefaultGatherer.Gather()
	if err != nil {
		t.Fatal(err)
	}
	result := map[string]float64{}
	for _, family := range families {
		if family.GetName() != "relay_call_control_requests_total" {
			continue
		}
		for _, metric := range family.Metric {
			labels := map[string]string{}
			for _, label := range metric.Label {
				labels[label.GetName()] = label.GetValue()
			}
			if len(labels) != 3 {
				t.Fatalf("unexpected call metric label dimensions: %v", labels)
			}
			result[labels["action"]+"|"+labels["outcome"]+"|"+labels["wake"]] = metric.GetCounter().GetValue()
		}
	}
	return result
}

func assertOneCallMetric(t *testing.T, before map[string]float64, key string) {
	t.Helper()
	after := callMetricsSnapshot(t)
	totalDelta := 0.0
	for label, value := range after {
		totalDelta += value - before[label]
	}
	if after[key]-before[key] != 1 || totalDelta != 1 {
		t.Fatalf("request metric %q delta = %v, total delta = %v; want exactly one", key, after[key]-before[key], totalDelta)
	}
}

func captureCallDiagnostics(t *testing.T) *bytes.Buffer {
	t.Helper()
	var output bytes.Buffer
	previous := log.Writer()
	log.SetOutput(&output)
	t.Cleanup(func() { log.SetOutput(previous) })
	return &output
}

func callDiagnosticLines(output *bytes.Buffer) []string {
	var result []string
	for _, line := range strings.Split(output.String(), "\n") {
		if strings.Contains(line, "call_control action=") {
			result = append(result, line)
		}
	}
	return result
}

func TestCallControlMetricsStoreWakeAckCancelAndReplay(t *testing.T) {
	now := time.Now().UTC()
	dispatcher := &callTestWakeDispatcher{err: errors.New("private-provider-error")}
	service, _ := callTestService(t, now, dispatcher)
	fixture := newCallHandlerFixture(t, service)
	sender, recipient := fixture.client.ID().String(), fixture.recipient.ID().String()
	authorizeCallFixture(t, service, now, sender, recipient)
	output := captureCallDiagnostics(t)
	store := map[string]any{
		"action": callStoreAction, "to": recipient, "callHandle": callTestHandleA,
		"messageId": callTestMessageA, "envelope": "private-encrypted-envelope",
		"expiresAtMs": now.Add(40 * time.Second).UnixMilli(), "wakeHandle": callTestWake,
	}
	before := callMetricsSnapshot(t)
	response := callHandlerRoundTrip(t, fixture, fixture.client, store)
	if response["status"] != "OK" || response["wake"] != nil {
		t.Fatalf("legacy store receipt changed: %#v", response)
	}
	assertOneCallMetric(t, before, callStoreAction+"|stored|failed")
	if len(callDiagnosticLines(output)) != 1 {
		t.Fatal("failed wake must emit one bounded diagnostic even on an OK store receipt")
	}
	dispatcher.err = nil
	before = callMetricsSnapshot(t)
	response = callHandlerRoundTrip(t, fixture, fixture.client, store)
	if response["storeStatus"] != "duplicate" {
		t.Fatalf("duplicate store changed: %#v", response)
	}
	assertOneCallMetric(t, before, callStoreAction+"|duplicate|not_attempted")
	for _, step := range []struct {
		request map[string]any
		outcome string
	}{
		{map[string]any{"action": callRetrieveAction, "callHandle": callTestHandleA}, "events"},
		{map[string]any{"action": callAckAction, "callHandle": callTestHandleA, "messageIds": []string{callTestMessageA}}, "acked"},
		{map[string]any{"action": callAckAction, "callHandle": callTestHandleA, "messageIds": []string{callTestMessageA}}, "noop"},
		{map[string]any{"action": callRetrieveAction, "callHandle": callTestHandleA}, "empty"},
	} {
		before = callMetricsSnapshot(t)
		if got := callHandlerRoundTrip(t, fixture, fixture.recipient, step.request); got["status"] != "OK" {
			t.Fatalf("poll/ack response changed: %#v", got)
		}
		assertOneCallMetric(t, before, step.request["action"].(string)+"|"+step.outcome+"|not_applicable")
	}
	if len(callDiagnosticLines(output)) != 1 {
		t.Fatal("successful store, polling and ACKs must not add diagnostic logs")
	}
	before = callMetricsSnapshot(t)
	response = callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
		"action": callCancelAction, "to": recipient, "callHandle": callTestHandleA,
	})
	if response["canceled"] != true {
		t.Fatalf("cancel response changed: %#v", response)
	}
	assertOneCallMetric(t, before, callCancelAction+"|canceled|not_applicable")
	before = callMetricsSnapshot(t)
	response = callHandlerRoundTrip(t, fixture, fixture.client, store)
	if response["errorCode"] != "CALL_REPLAY" {
		t.Fatalf("terminal replay rejection changed: %#v", response)
	}
	assertOneCallMetric(t, before, callStoreAction+"|CALL_REPLAY|not_attempted")
	if len(callDiagnosticLines(output)) != 3 {
		t.Fatal("cancel and replay rejection must each add one diagnostic")
	}
	for _, secret := range []string{sender, recipient, callTestHandleA, callTestMessageA, callTestWake, "private-encrypted-envelope", "private-provider-error"} {
		for _, line := range callDiagnosticLines(output) {
			if strings.Contains(line, secret) {
				t.Fatal("call diagnostic leaked request/provider material")
			}
		}
		for labels := range callMetricsSnapshot(t) {
			if strings.Contains(labels, secret) {
				t.Fatal("call metric leaked request/provider material")
			}
		}
	}
}

func TestCallControlMetricsWakeReceiptOptInDoesNotChangeObservation(t *testing.T) {
	now := time.Now().UTC()
	service, _ := callTestService(t, now, &callTestWakeDispatcher{})
	fixture := newCallHandlerFixture(t, service)
	authorizeCallFixture(t, service, now, fixture.client.ID().String(), fixture.recipient.ID().String())
	output := captureCallDiagnostics(t)
	for i, handle := range []string{callTestHandleA, callTestHandleB} {
		before := callMetricsSnapshot(t)
		response := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
			"action": callStoreAction, "to": fixture.recipient.ID().String(), "callHandle": handle,
			"messageId": callTestMessageA, "envelope": "private-envelope", "wakeHandle": callTestWake,
			"expiresAtMs": now.Add(40 * time.Second).UnixMilli(), "wakeReceipt": i == 1,
		})
		if response["status"] != "OK" || (i == 0 && response["wake"] != nil) || (i == 1 && response["wake"] != "dispatched") {
			t.Fatalf("wake receipt opt-in changed: %#v", response)
		}
		assertOneCallMetric(t, before, callStoreAction+"|stored|dispatched")
	}
	if len(callDiagnosticLines(output)) != 0 {
		t.Fatal("successful store must not create diagnostic logs")
	}
}

func TestCallControlMetricsUnknownValuesHaveBoundedLabels(t *testing.T) {
	output := captureCallDiagnostics(t)
	for _, tc := range []struct {
		action   string
		response callControlWireResponse
		wake     CallWakeStatus
		key      string
	}{
		{"private-action", callControlWireResponse{Status: "private-status", ErrorCode: "private-error"}, "private-wake", "unknown|CALL_BACKEND_UNAVAILABLE|not_applicable"},
		{callStoreAction, callControlWireResponse{Status: "OK", StoreStatus: "private-store-status"}, "private-wake", callStoreAction + "|unknown|unknown"},
	} {
		before := callMetricsSnapshot(t)
		recordCallControlRequest(tc.action, tc.response, tc.wake)
		assertOneCallMetric(t, before, tc.key)
	}
	for labels := range callMetricsSnapshot(t) {
		if strings.Contains(labels, "private-") {
			t.Fatal("unknown values escaped telemetry allowlist")
		}
	}
	for _, line := range callDiagnosticLines(output) {
		if strings.Contains(line, "private-") {
			t.Fatal("unknown values escaped diagnostic allowlist")
		}
	}
}

func TestCallControlMetricsInvalidRequestsAndUnavailableBackend(t *testing.T) {
	service, _ := callTestService(t, time.Now(), nil)
	for _, tc := range []struct {
		name, raw, key, code string
		service              *CallControlService
	}{
		{"unsupported", `{"action":"private-unsupported-action"}`, "unknown|CALL_INVALID_REQUEST|not_applicable", "CALL_INVALID_REQUEST", service},
		{"malformed", `{"action":"call_store_v1","envelope":`, "unknown|CALL_INVALID_REQUEST|not_applicable", "CALL_INVALID_REQUEST", service},
		{"foreign fields", `{"action":"call_retrieve_v1","token":"private-token"}`, "unknown|CALL_INVALID_REQUEST|not_applicable", "CALL_INVALID_REQUEST", service},
		{"unavailable", `{"action":"call_store_v1"}`, callStoreAction + "|CALL_BACKEND_UNAVAILABLE|not_attempted", "CALL_BACKEND_UNAVAILABLE", nil},
		{"unavailable malformed preserves precedence", `{`, "unknown|CALL_BACKEND_UNAVAILABLE|not_applicable", "CALL_BACKEND_UNAVAILABLE", nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fixture := newCallHandlerFixture(t, tc.service)
			fixture.relay.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
				defer stream.Close()
				defer func() { fixture.handled <- struct{}{} }()
				raw, err := readFrame(stream)
				if err == nil {
					handleCallControlRequest(stream, raw, stream.Conn().RemotePeer().String(), tc.service)
				}
			})
			output := captureCallDiagnostics(t)
			before := callMetricsSnapshot(t)
			stream, err := fixture.client.NewStream(context.Background(), fixture.relay.ID(), InboxProtocol)
			if err != nil {
				t.Fatal(err)
			}
			defer stream.Close()
			if err := writeFrame(stream, []byte(tc.raw)); err != nil {
				t.Fatal(err)
			}
			raw, err := readFrame(stream)
			if err != nil {
				t.Fatal(err)
			}
			select {
			case <-fixture.handled:
			case <-time.After(2 * time.Second):
				t.Fatal("handler did not finish")
			}
			var response callControlWireResponse
			if err := json.Unmarshal(raw, &response); err != nil {
				t.Fatal(err)
			}
			if response.ErrorCode != tc.code {
				t.Fatalf("response code = %q, want %q", response.ErrorCode, tc.code)
			}
			assertOneCallMetric(t, before, tc.key)
			lines := callDiagnosticLines(output)
			if len(lines) != 1 || strings.Contains(lines[0], "private-") {
				t.Fatalf("expected one sanitized diagnostic: %v", lines)
			}
		})
	}
}

func TestCallControlMetricsAuthorityWithdrawals(t *testing.T) {
	now := time.Now().UTC()
	service, _ := callTestService(t, now, nil)
	fixture := newCallHandlerFixture(t, service)
	sender, recipient := fixture.client.ID().String(), fixture.recipient.ID().String()
	authorizeCallFixture(t, service, now, sender, recipient)
	if err := service.SetCallToken(context.Background(), recipient, callTestIOSVoIPToken("private-voip-token", now.Add(time.Hour), 3)); err != nil {
		t.Fatal(err)
	}
	output := captureCallDiagnostics(t)
	for _, step := range []struct {
		request map[string]any
		outcome string
		revoked bool
	}{
		{map[string]any{"action": callTokenRevokeAction, "tokenKind": "ios_voip", "expectedRefreshEpoch": 2}, "noop", false},
		{map[string]any{"action": callTokenRevokeAction, "tokenKind": "ios_voip", "expectedRefreshEpoch": 3}, "revoked", true},
		{map[string]any{"action": callEndpointRevokeAction, "accountPeerId": recipient, "preferenceEpoch": 1}, "revoked", true},
	} {
		before := callMetricsSnapshot(t)
		response := callHandlerRoundTrip(t, fixture, fixture.recipient, step.request)
		if response["status"] != "OK" || response["revoked"] != step.revoked {
			t.Fatalf("withdrawal response changed: %#v", response)
		}
		assertOneCallMetric(t, before, step.request["action"].(string)+"|"+step.outcome+"|not_applicable")
	}
	lines := callDiagnosticLines(output)
	if len(lines) != 3 {
		t.Fatalf("withdrawal diagnostic count = %d, want 3", len(lines))
	}
	for _, line := range lines {
		if strings.Contains(line, recipient) || strings.Contains(line, "private-voip-token") || strings.Contains(line, "Epoch") {
			t.Fatal("withdrawal diagnostic leaked identity or token metadata")
		}
	}
}
