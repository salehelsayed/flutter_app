package bridge

import "github.com/mknoon/go-mknoon/node"

// StickerUsageV1 is separate from diagnostic consent/event ingestion. It
// cannot change app/call diagnostics or communication authority.
func StickerUsageV1(paramsJSON string) (result string) {
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	var request node.StickerUsageRequest
	if decodeCallBridgeParams(paramsJSON, &request) != nil {
		return callBridgeInvalidInput()
	}
	data, err := n.StickerUsageV1(request)
	if err != nil {
		return callBridgeError(err)
	}
	return okJSON(map[string]any{"ok": true, "data": data})
}
