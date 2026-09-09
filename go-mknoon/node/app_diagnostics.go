package node

import (
	"context"
	"encoding/json"
	"time"
)

const appDiagnosticsV1Action = "app_diagnostics_v1"

// AppDiagnosticRequest is independent of call diagnostics and call authority.
type AppDiagnosticRequest struct {
	Action       string            `json:"action,omitempty"`
	Op           string            `json:"op"`
	ConsentEpoch int64             `json:"consentEpoch,omitempty"`
	Enabled      *bool             `json:"enabled,omitempty"`
	Events       []json.RawMessage `json:"events,omitempty"`
}

func (n *Node) AppDiagnosticsV1(request AppDiagnosticRequest) (map[string]any, error) {
	switch request.Op {
	case "configure", "clear", "upload", "capabilities":
	default:
		return nil, ErrCallControlInvalidRequest
	}
	if len(request.Events) > 64 || (request.Op != "capabilities" && (request.ConsentEpoch <= 0 || request.ConsentEpoch > 9007199254740991)) || (request.Op == "configure" && request.Enabled == nil) || (request.Op != "configure" && request.Enabled != nil) || (request.Op != "upload" && request.Events != nil) {
		return nil, ErrCallControlInvalidRequest
	}
	n.mu.RLock()
	h, ctx := n.host, n.ctx
	n.mu.RUnlock()
	if h == nil || ctx == nil {
		return nil, ErrCallControlUnavailable
	}
	request.Action = appDiagnosticsV1Action
	raw, err := json.Marshal(request)
	if err != nil || len(raw) > 300<<10 {
		return nil, ErrCallControlInvalidRequest
	}
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return nil, ErrCallControlUnavailable
	}
	var result map[string]any
	var lastErr error
	fanout := request.Op == "configure" || request.Op == "clear"
	for i, relay := range relays {
		deadline, _ := ctx.Deadline()
		attempt, stop := context.WithTimeout(ctx, time.Until(deadline)/time.Duration(len(relays)-i))
		response, err := exchangeCallDiagnosticRaw(attempt, h, relay, raw)
		stop()
		if err != nil {
			lastErr = err
			continue
		}
		var decoded struct {
			Status  string         `json:"status"`
			Version int            `json:"version"`
			Data    map[string]any `json:"data"`
			Error   string         `json:"error"`
		}
		if json.Unmarshal(response, &decoded) != nil {
			lastErr = ErrCallControlInvalidResponse
			continue
		}
		if decoded.Status == "ERROR" && decoded.Error == "Unknown action: "+appDiagnosticsV1Action {
			continue
		}
		if decoded.Status != "OK" || decoded.Version != 1 || decoded.Data == nil {
			lastErr = ErrCallControlInvalidResponse
			continue
		}
		supported, ok := decoded.Data["supported"].(bool)
		if !ok {
			lastErr = ErrCallControlInvalidResponse
			continue
		}
		if !supported {
			continue
		}
		if !fanout {
			return decoded.Data, nil
		}
		if reason, _ := decoded.Data["reason"].(string); reason != "" && reason != "none" {
			lastErr = ErrCallControlUnavailable
			continue
		}
		result = decoded.Data
	}
	// A successful relay cannot hide failed erasure/configuration on another one.
	if lastErr != nil {
		return nil, lastErr
	}
	if result != nil {
		return result, nil
	}
	return map[string]any{"supported": false}, nil
}
