package bridge

import (
	"encoding/json"

	"github.com/mknoon/go-mknoon/node"
)

// CallDiagnosticsV1 is a separately authenticated, optional diagnostics surface.
// It does not authorize, accept, revoke or otherwise control a call.
func CallDiagnosticsV1(paramsJSON string) (result string) {
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var request node.CallDiagnosticRequest
	if decodeCallBridgeParams(paramsJSON, &request) != nil {
		return callBridgeInvalidInput()
	}
	data, err := n.CallDiagnosticsV1(request)
	if err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{"ok": true, "data": data})
}

// Remove advisory metadata before the unchanged strict v1 decoder and signing
// helpers. Invalid metadata cannot invalidate an otherwise valid call request.
func splitCallBridgeDiagnostics(raw string) (string, *node.CallDiagnosticContext) {
	var fields map[string]json.RawMessage
	if json.Unmarshal([]byte(raw), &fields) != nil {
		return raw, nil
	}
	value, present := fields["diagnostics"]
	if !present {
		return raw, nil
	}
	delete(fields, "diagnostics")
	base, err := json.Marshal(fields)
	if err != nil {
		return raw, nil
	}
	var d node.CallDiagnosticContext
	if len(value) > 512 || decodeCallBridgeParams(string(value), &d) != nil || !d.Valid() {
		return string(base), nil
	}
	return string(base), &d
}
func callEndpointGetDiagnosticInvoke(n *node.Node, account string, d *node.CallDiagnosticContext) (node.CallEndpointResult, error) {
	if d != nil {
		return n.CallEndpointGetV1(account, d)
	}
	return callEndpointGetV1Invoke(n, account)
}
func callEndpointRevokeDiagnosticInvoke(n *node.Node, account string, epoch uint64, d *node.CallDiagnosticContext) error {
	if d != nil {
		return n.CallEndpointRevokeV1(account, epoch, d)
	}
	return callEndpointRevokeV1Invoke(n, account, epoch)
}
func callWakeHandleRevokeDiagnosticInvoke(n *node.Node, peer string, d *node.CallDiagnosticContext) error {
	if d != nil {
		return n.CallWakeHandleRevokeV1(peer, d)
	}
	return callWakeHandleRevokeV1Invoke(n, peer)
}
func callTokenRevokeDiagnosticInvoke(n *node.Node, kind string, epoch uint64, d *node.CallDiagnosticContext) (bool, error) {
	if d != nil {
		return n.CallTokenRevokeV1(kind, epoch, d)
	}
	return callTokenRevokeV1Invoke(n, kind, epoch)
}
