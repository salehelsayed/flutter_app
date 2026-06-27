package bridge

import (
	"encoding/json"
	"fmt"
)

// RegisterWakeTokens registers the local peer's opaque wake-token SET (the tokens
// it minted for its contacts) with the relay via the additive
// `register_wake_tokens` action (FDC-09 §12 access-token anti-spam gate: "only
// contacts can wake you"). It is in its own bridge file (not the 2880-line
// bridge.go) per the new-entrypoint isolation rule.
//
// Input JSON:  { "tokens": ["...", "..."] }
// Returns JSON: { "ok": true } on accept; { "ok": false, "error": "..." } when an
// OLD relay answers "Unknown action: register_wake_tokens" or registration could
// not be delivered. An old relay / failure NEVER throws away the plain push — the
// caller degrades gracefully (NET-REL-07). Only NOT_INITIALIZED / INVALID_INPUT
// produce an ok:false error envelope.
func RegisterWakeTokens(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		Tokens []string `json:"tokens"`
	}
	if paramsJSON != "" {
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
	}

	if err := n.RelayRegisterWakeTokens(params.Tokens); err != nil {
		// Best-effort: a relay outage / old relay never throws away the plain push.
		return okJSON(map[string]interface{}{"ok": false, "error": err.Error()})
	}

	return okJSON(map[string]interface{}{"ok": true})
}
