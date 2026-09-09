package bridge

import (
	"github.com/mknoon/go-mknoon/node"
	"testing"
)

func TestAppDiagnosticBridgeExactPayloadBoundary(t *testing.T) {
	withSingletonNode(t)
	prior := appDiagnosticsV1Invoke
	t.Cleanup(func() { appDiagnosticsV1Invoke = prior })
	calls := 0
	appDiagnosticsV1Invoke = func(_ *node.Node, r node.AppDiagnosticRequest) (map[string]any, error) {
		calls++
		if r.Op != "configure" || r.Enabled == nil || !*r.Enabled || r.ConsentEpoch != 7 {
			t.Fatal("nested payload changed")
		}
		return map[string]any{"supported": true, "enabled": true, "consentEpoch": 7}, nil
	}
	result := parseJSON(t, AppDiagnosticsV1(`{"op":"configure","enabled":true,"consentEpoch":7}`))
	if result["ok"] != true || calls != 1 {
		t.Fatal("native bridge boundary")
	}
	result = parseJSON(t, AppDiagnosticsV1(`{"op":"configure","enabled":true,"consentEpoch":7,"owner":"private"}`))
	if result["ok"] == true || calls != 1 {
		t.Fatal("unknown identity accepted")
	}
}
