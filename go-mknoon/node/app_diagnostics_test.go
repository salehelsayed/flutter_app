package node

import (
	"encoding/json"
	"github.com/libp2p/go-libp2p/core/network"
	"strings"
	"testing"
)

func TestAppDiagnosticTransportAuthenticatedAndSeparate(t *testing.T) {
	relay, _ := startTurnCredentialsRelayFixture(t, "")
	n := turnCredentialsNode(t, relay)
	enabled := true
	seen := make(chan map[string]any, 1)
	relay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		raw, _ := readFrame(s)
		var request map[string]any
		_ = json.Unmarshal(raw, &request)
		seen <- request
		_ = writeFrame(s, []byte(`{"status":"OK","version":1,"data":{"supported":true,"enabled":true,"consentEpoch":7}}`))
	})
	result, err := n.AppDiagnosticsV1(AppDiagnosticRequest{Op: "configure", ConsentEpoch: 7, Enabled: &enabled})
	if err != nil || result["supported"] != true {
		t.Fatal("app configure failed")
	}
	req := <-seen
	if len(req) != 4 || req["action"] != appDiagnosticsV1Action || req["op"] != "configure" {
		t.Fatal("app request grammar")
	}
	n.mu.RLock()
	callEnabled, callEpoch := n.callDiagnosticsEnabled, n.callDiagnosticConsentEpoch
	n.mu.RUnlock()
	if callEnabled || callEpoch != 0 {
		t.Fatal("app consent changed call consent")
	}
}
func TestAppDiagnosticOldRelayAndTransientResponses(t *testing.T) {
	for _, test := range []struct {
		response    string
		unsupported bool
	}{
		{`{"status":"ERROR","error":"Unknown action: app_diagnostics_v1"}`, true},
		{`{"status":"ERROR","error":"secret provider failure"}`, false},
		{`{"status":"OK","version":2,"data":{"supported":true}}`, false},
	} {
		relay, _ := startTurnCredentialsRelayFixture(t, test.response)
		n := turnCredentialsNode(t, relay)
		r, err := n.AppDiagnosticsV1(AppDiagnosticRequest{Op: "capabilities"})
		if test.unsupported {
			if err != nil || r["supported"] != false {
				t.Fatal("old relay not safely unsupported")
			}
		} else if err == nil || strings.Contains(err.Error(), "secret") {
			t.Fatal("invalid relay response accepted/exposed")
		}
	}
	relay, _ := startTurnCredentialsRelayFixture(t, `{"status":"OK","version":1,"data":{"supported":true,"reason":"sink_unavailable","acceptedEventIds":[],"rejectedEventIds":[]}}`)
	n := turnCredentialsNode(t, relay)
	r, err := n.AppDiagnosticsV1(AppDiagnosticRequest{Op: "upload", ConsentEpoch: 1})
	if err != nil || r["reason"] != "sink_unavailable" {
		t.Fatal("upload retry classification lost")
	}
	enabled := true
	if _, err := n.AppDiagnosticsV1(AppDiagnosticRequest{Op: "configure", ConsentEpoch: 1, Enabled: &enabled}); err == nil {
		t.Fatal("failed configuration hidden")
	}
}
func TestAppDiagnosticRejectsMalformedRequestsBeforeTransport(t *testing.T) {
	n := &Node{}
	enabled := true
	for _, r := range []AppDiagnosticRequest{{Op: "request"}, {Op: "configure", ConsentEpoch: 1}, {Op: "upload", ConsentEpoch: 1, Enabled: &enabled}, {Op: "clear", ConsentEpoch: -1}, {Op: "upload", ConsentEpoch: 1, Events: make([]json.RawMessage, 65)}} {
		if _, err := n.AppDiagnosticsV1(r); err != ErrCallControlInvalidRequest {
			t.Fatal("invalid input reached transport")
		}
	}
}
