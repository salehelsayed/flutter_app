package bridge

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/mknoon/go-mknoon/node"
)

func TestCallDiagnosticsBridgeStripsOptionalMetadataBeforeStrictV1(t *testing.T) {
	withSingletonNode(t)
	previous := callAckV1Invoke
	t.Cleanup(func() { callAckV1Invoke = previous })
	trace := uuid.NewString()
	calls := 0
	callAckV1Invoke = func(_ *node.Node, r node.CallAckRequest) (int, error) {
		calls++
		if r.CallHandle != nodeCallBridgeHandle {
			t.Fatal("base request changed")
		}
		if calls == 1 && (r.Diagnostics == nil || r.Diagnostics.TraceID != trace) {
			t.Fatal("valid context lost")
		}
		if calls == 2 && r.Diagnostics != nil {
			t.Fatal("malformed context retained")
		}
		return 1, nil
	}
	for _, diagnostics := range []string{`{"traceId":"` + trace + `"}`, `{"traceId":"not-an-id","secret":"must-be-discarded"}`} {
		raw := `{"callHandle":"` + nodeCallBridgeHandle + `","messageIds":["` + nodeCallBridgeMessage + `"],"diagnostics":` + diagnostics + `}`
		response := parseJSON(t, CallAckV1(raw))
		if response["ok"] != true {
			t.Fatal("metadata rejected valid legacy action")
		}
	}
	if calls != 2 {
		t.Fatal("call invoked more than once")
	}
	base, d := splitCallBridgeDiagnostics(`{"accountPeerId":"peer","unexpected":"secret","diagnostics":{"operationId":"` + uuid.NewString() + `","cause":"calls_disabled"}}`)
	if d == nil || d.TraceID != "" {
		t.Fatal("operation-only context rejected")
	}
	var fields map[string]any
	_ = json.Unmarshal([]byte(base), &fields)
	if fields["unexpected"] != "secret" || fields["diagnostics"] != nil {
		t.Fatal("stripping bypassed strict legacy field validation")
	}
}

func TestCallDiagnosticsBridgeConsumesExactDartWireFixtures(t *testing.T) {
	raw, err := os.ReadFile("../../tool/call_diagnostics/wire_fixtures_v1.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Contexts map[string]json.RawMessage `json:"contexts"`
	}
	_ = json.Unmarshal(raw, &fixture)
	for name, ctx := range fixture.Contexts {
		t.Run(name, func(t *testing.T) {
			base, d := splitCallBridgeDiagnostics(`{"accountPeerId":"private-peer","diagnostics":` + string(ctx) + `}`)
			if d == nil || d.Reason == "" {
				t.Fatal("exact Dart context silently discarded")
			}
			var params struct {
				AccountPeerID string `json:"accountPeerId"`
			}
			if decodeCallBridgeParams(base, &params) != nil || params.AccountPeerID != "private-peer" {
				t.Fatal("diagnostic context changed strict base request")
			}
		})
	}
}
