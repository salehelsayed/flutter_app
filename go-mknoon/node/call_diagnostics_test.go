package node

import (
	"encoding/json"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/libp2p/go-libp2p/core/network"
)

func TestCallDiagnosticsNegotiatesOuterEnvelopeAndPreservesV1(t *testing.T) {
	relay, _ := startTurnCredentialsRelayFixture(t, "")
	n := turnCredentialsNode(t, relay)
	seen := make(chan map[string]json.RawMessage, 8)
	relay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		raw, _ := readFrame(s)
		var req map[string]json.RawMessage
		_ = json.Unmarshal(raw, &req)
		seen <- req
		var action, op string
		_ = json.Unmarshal(req["action"], &action)
		_ = json.Unmarshal(req["op"], &op)
		if action == callDiagnosticsV2Action && op == "configure" {
			_ = writeFrame(s, []byte(`{"status":"OK","version":2,"data":{"supported":true,"enabled":true}}`))
			return
		}
		_ = writeFrame(s, []byte(`{"status":"OK","found":false}`))
	})
	d := &CallDiagnosticContext{OperationID: uuid.NewString(), RequestID: uuid.NewString(), Reason: "resume_refresh"}
	if _, err := n.CallEndpointGetV1(n.peerId, d); err != nil {
		t.Fatal(err)
	}
	first := <-seen
	if first["diagnostics"] != nil || first["request"] != nil {
		t.Fatal("unnegotiated context changed v1 request")
	}
	data, err := n.CallDiagnosticsV1(CallDiagnosticRequest{Op: "configure", Enabled: true, ConsentEpoch: 1})
	if err != nil || data["supported"] != true {
		t.Fatal("capability negotiation failed")
	}
	<-seen
	if _, err := n.CallEndpointGetV1(n.peerId, d); err != nil {
		t.Fatal(err)
	}
	wrapped := <-seen
	var action string
	_ = json.Unmarshal(wrapped["action"], &action)
	if action != callDiagnosticsV2Action || wrapped["diagnostics"] == nil {
		t.Fatal("missing negotiated wrapper")
	}
	var inner map[string]any
	_ = json.Unmarshal(wrapped["request"], &inner)
	if len(inner) != 2 || inner["action"] != callEndpointGetAction || inner["accountPeerId"] != n.peerId {
		t.Fatal("diagnostics modified canonical v1 request")
	}
}
func TestCallDiagnosticsExplicitOldRelayFallbackOnly(t *testing.T) {
	relay, _ := startTurnCredentialsRelayFixture(t, "")
	n := turnCredentialsNode(t, relay)
	var requests atomic.Int32
	relay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		raw, _ := readFrame(s)
		requests.Add(1)
		var req struct {
			Action string `json:"action"`
		}
		_ = json.Unmarshal(raw, &req)
		if req.Action == callDiagnosticsV2Action {
			_ = writeFrame(s, []byte(`{"status":"ERROR","error":"Unknown action: call_diagnostics_v2"}`))
			return
		}
		_ = writeFrame(s, []byte(`{"status":"OK","found":false}`))
	})
	n.mu.Lock()
	n.callDiagnosticsEnabled = true
	n.mu.Unlock()
	n.setDiagnosticRelay(relay.ID(), true)
	if _, err := n.CallEndpointGetV1(n.peerId, &CallDiagnosticContext{TraceID: uuid.NewString()}); err != nil {
		t.Fatal(err)
	}
	if requests.Load() != 2 || n.diagnosticReady(relay.ID()) {
		t.Fatal("old relay fallback/capability invalidation")
	}
	if _, err := n.CallEndpointGetV1(n.peerId, &CallDiagnosticContext{TraceID: uuid.NewString()}); err != nil {
		t.Fatal(err)
	}
	if requests.Load() != 3 {
		t.Fatal("old relay retried unsupported diagnostic wrapper")
	}
}
func TestCallDiagnosticsLateConfigureCannotUndoDisable(t *testing.T) {
	relay, _ := startTurnCredentialsRelayFixture(t, "")
	n := turnCredentialsNode(t, relay)
	started := make(chan struct{})
	release := make(chan struct{})
	relay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		raw, _ := readFrame(s)
		var req CallDiagnosticRequest
		_ = json.Unmarshal(raw, &req)
		if req.ConsentEpoch == 1 {
			close(started)
			<-release
		}
		response, _ := json.Marshal(map[string]any{"status": "OK", "version": 2, "data": map[string]any{"supported": true, "enabled": req.Enabled}})
		_ = writeFrame(s, response)
	})
	done := make(chan struct{})
	go func() {
		_, _ = n.CallDiagnosticsV1(CallDiagnosticRequest{Op: "configure", Enabled: true, ConsentEpoch: 1})
		close(done)
	}()
	select {
	case <-started:
	case <-time.After(3 * time.Second):
		t.Fatal("enable never reached relay")
	}
	if _, err := n.CallDiagnosticsV1(CallDiagnosticRequest{Op: "configure", Enabled: false, ConsentEpoch: 2}); err != nil {
		t.Fatal(err)
	}
	close(release)
	<-done
	n.mu.RLock()
	enabled, epoch := n.callDiagnosticsEnabled, n.callDiagnosticConsentEpoch
	n.mu.RUnlock()
	if enabled || epoch != 2 {
		t.Fatal("late old configure re-enabled diagnostics")
	}
}
func TestCallDiagnosticsMalformedContextLeavesLegacyBytes(t *testing.T) {
	raw := []byte(`{"action":"call_ack_v1","callHandle":"private-handle","messageIds":[]}`)
	for _, d := range []*CallDiagnosticContext{nil, {TraceID: "private-handle"}, {RequestID: uuid.NewString()}} {
		if string(diagnosticWrapRequest(raw, d)) != string(raw) {
			t.Fatal("invalid diagnostic context changed legacy bytes")
		}
	}
}

func TestCallDiagnosticsTURNInvalidatesUnsupportedWrapperCache(t *testing.T) {
	now := time.Now()
	relay, _ := startTurnCredentialsRelayFixture(t, "")
	n := turnCredentialsNode(t, relay)
	var requests atomic.Int32
	relay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		raw, _ := readFrame(s)
		requests.Add(1)
		var req struct {
			Action string `json:"action"`
		}
		_ = json.Unmarshal(raw, &req)
		if req.Action == callDiagnosticsV2Action {
			_ = writeFrame(s, []byte(`{"status":"ERROR","error":"Unknown action: call_diagnostics_v2"}`))
			return
		}
		_ = writeFrame(s, []byte(validTurnCredentialsResponse(now, "diagnostic-fallback")))
	})
	n.mu.Lock()
	n.callDiagnosticsEnabled = true
	n.callDiagnosticConsentEpoch = 1
	n.mu.Unlock()
	n.setDiagnosticRelay(relay.ID(), true)
	d := &CallDiagnosticContext{TraceID: uuid.NewString()}
	if _, err := n.TurnCredentialsWithDiagnosticsV1(d); err != nil {
		t.Fatal(err)
	}
	if requests.Load() != 2 || n.diagnosticReady(relay.ID()) {
		t.Fatal("TURN fallback failed to invalidate wrapper support")
	}
	if _, err := n.TurnCredentialsWithDiagnosticsV1(d); err != nil {
		t.Fatal(err)
	}
	if requests.Load() != 3 {
		t.Fatal("second TURN repeated diagnostic-only round trip")
	}
}
func TestCallDiagnosticsSharedDartWireFixtures(t *testing.T) {
	raw, err := os.ReadFile("../../tool/call_diagnostics/wire_fixtures_v1.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Contexts map[string]json.RawMessage `json:"contexts"`
	}
	if json.Unmarshal(raw, &fixture) != nil {
		t.Fatal("fixture")
	}
	for name, raw := range fixture.Contexts {
		t.Run(name, func(t *testing.T) {
			var d CallDiagnosticContext
			if json.Unmarshal(raw, &d) != nil || !d.Valid() || d.Reason == "" {
				t.Fatal("Dart cause context silently dropped")
			}
			encoded, _ := json.Marshal(d)
			var fields map[string]any
			_ = json.Unmarshal(encoded, &fields)
			if fields["cause"] != d.Reason || fields["reason"] != nil {
				t.Fatal("wire cause diverged from event reason")
			}
		})
	}
}
