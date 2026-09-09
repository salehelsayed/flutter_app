package bridge

import "github.com/mknoon/go-mknoon/node"

var appDiagnosticsV1Invoke = func(n *node.Node, request node.AppDiagnosticRequest) (map[string]any, error) {
	return n.AppDiagnosticsV1(request)
}

// AppDiagnosticsV1 uploads only closed-schema app diagnostics. It is separate
// from call diagnostics and cannot change message, media or call authority.
func AppDiagnosticsV1(paramsJSON string) (result string) {
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var request node.AppDiagnosticRequest
	if decodeCallBridgeParams(paramsJSON, &request) != nil {
		return callBridgeInvalidInput()
	}
	data, err := appDiagnosticsV1Invoke(n, request)
	if err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{"ok": true, "data": data})
}
