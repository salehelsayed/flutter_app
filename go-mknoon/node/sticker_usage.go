package node

import (
	"context"
	"encoding/json"
	"time"
)

// Only aggregate counts and a random batch nonce cross the transport. The
// authenticated peer is used transiently by the relay's abuse limiter only.
type StickerUsageRequest struct {
	Action string         `json:"action,omitempty"`
	Day    string         `json:"day"`
	Nonce  string         `json:"nonce"`
	Counts map[string]int `json:"counts"`
}

func (n *Node) StickerUsageV1(request StickerUsageRequest) (map[string]any, error) {
	if len(request.Counts) == 0 || len(request.Counts) > 512 || !validDiagnosticUUID(request.Nonce) {
		return nil, ErrCallControlInvalidRequest
	}
	total := 0
	for id, count := range request.Counts {
		if len(id) > 100 || count < 1 || count > 1000 {
			return nil, ErrCallControlInvalidRequest
		}
		total += count
	}
	if total > 1000 {
		return nil, ErrCallControlInvalidRequest
	}
	request.Action = "sticker_usage_v1"
	raw, err := json.Marshal(request)
	if err != nil || len(raw) > 32768 {
		return nil, ErrCallControlInvalidRequest
	}
	n.mu.RLock()
	h, ctx := n.host, n.ctx
	n.mu.RUnlock()
	if h == nil || ctx == nil {
		return nil, ErrCallControlUnavailable
	}
	relays := n.buildRelaySelector(nil).Relays()
	if len(relays) == 0 {
		return nil, ErrCallControlUnavailable
	}
	// Do not fail over an ambiguous write to another authority: it might have
	// been committed. Retry the preferred relay with the same nonce later.
	attempt, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	response, err := exchangeCallDiagnosticRaw(attempt, h, relays[0], raw)
	if err != nil {
		return nil, ErrCallControlUnavailable
	}
	var decoded struct {
		Status  string         `json:"status"`
		Version int            `json:"version"`
		Error   string         `json:"error"`
		Data    map[string]any `json:"data"`
	}
	if json.Unmarshal(response, &decoded) != nil {
		return nil, ErrCallControlInvalidResponse
	}
	if decoded.Status == "ERROR" && decoded.Error == "Unknown action: sticker_usage_v1" {
		return map[string]any{"supported": false}, nil
	}
	if decoded.Status != "OK" || decoded.Version != 1 || decoded.Data == nil {
		return nil, ErrCallControlInvalidResponse
	}
	if _, ok := decoded.Data["supported"].(bool); !ok {
		return nil, ErrCallControlInvalidResponse
	}
	return decoded.Data, nil
}
