package node

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
)

const callDiagnosticsV2Action = "call_diagnostics_v2"

// CallDiagnosticContext is advisory metadata, outside all signed v1 records.
// An absent, malformed or unsupported context leaves v1 bytes unchanged.
type CallDiagnosticContext struct {
	consentEpoch      int64
	TraceID           string `json:"traceId,omitempty"`
	RequestID         string `json:"requestId,omitempty"`
	OperationID       string `json:"operationId,omitempty"`
	ParentOperationID string `json:"parentOperationId,omitempty"`
	Reason            string `json:"cause,omitempty"`
}

func validDiagnosticUUID(value string) bool {
	u, err := uuid.Parse(value)
	return err == nil && u.String() == value && u.Variant() == uuid.RFC4122 && u.Version() == 4
}
func (d *CallDiagnosticContext) Valid() bool {
	if d == nil {
		return false
	}
	for _, v := range []string{d.TraceID, d.RequestID, d.OperationID, d.ParentOperationID} {
		if v != "" && !validDiagnosticUUID(v) {
			return false
		}
	}
	return (d.TraceID != "" || d.OperationID != "") && len(d.Reason) <= 64 && !strings.ContainsAny(d.Reason, " \r\n\t")
}
func diagnosticContext(values []*CallDiagnosticContext) *CallDiagnosticContext {
	if len(values) > 0 && values[0].Valid() {
		return values[0]
	}
	return nil
}
func (n *Node) diagnosticReady(relay peer.ID) bool {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.callDiagnosticsEnabled && time.Now().Before(n.callDiagnosticRelays[relay])
}
func (n *Node) diagnosticForRelay(relay peer.ID, values []*CallDiagnosticContext) *CallDiagnosticContext {
	d := diagnosticContext(values)
	if d == nil {
		return nil
	}
	n.mu.RLock()
	defer n.mu.RUnlock()
	if !n.callDiagnosticsEnabled || !time.Now().Before(n.callDiagnosticRelays[relay]) {
		return nil
	}
	copy := *d
	copy.consentEpoch = n.callDiagnosticConsentEpoch
	return &copy
}
func (n *Node) setDiagnosticRelay(relay peer.ID, supported bool) {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.callDiagnosticRelays == nil {
		n.callDiagnosticRelays = map[peer.ID]time.Time{}
	}
	if supported {
		n.callDiagnosticRelays[relay] = time.Now().Add(time.Hour)
	} else {
		delete(n.callDiagnosticRelays, relay)
	}
}
func diagnosticWrapRequest(raw []byte, d *CallDiagnosticContext) []byte {
	if !d.Valid() {
		return raw
	}
	wrapped, err := json.Marshal(map[string]any{"action": callDiagnosticsV2Action, "op": "request", "request": json.RawMessage(raw), "diagnostics": d, "consentEpoch": d.consentEpoch})
	if err != nil {
		return raw
	}
	return wrapped
}
func diagnosticUnsupported(raw []byte) bool {
	var r struct {
		Status string `json:"status"`
		Error  string `json:"error"`
	}
	return json.Unmarshal(raw, &r) == nil && r.Status == "ERROR" && r.Error == "Unknown action: "+callDiagnosticsV2Action
}

type CallDiagnosticRequest struct {
	ConsentEpoch int64             `json:"consentEpoch,omitempty"`
	Action       string            `json:"action,omitempty"`
	Op           string            `json:"op"`
	Enabled      bool              `json:"enabled,omitempty"`
	PushTrace    bool              `json:"pushTrace,omitempty"`
	TraceID      string            `json:"traceId,omitempty"`
	CallHandle   string            `json:"callHandle,omitempty"`
	Events       []json.RawMessage `json:"events,omitempty"`
	Summaries    []json.RawMessage `json:"summaries,omitempty"`
}

// CallDiagnosticsV1 performs only diagnostics operations. Call paths never wait
// for capability probes: configure/capabilities warms this cache separately.
func (n *Node) CallDiagnosticsV1(request CallDiagnosticRequest) (map[string]any, error) {
	switch request.Op {
	case "configure", "capabilities", "upload", "resolve", "bind", "clear":
	default:
		return nil, ErrCallControlInvalidRequest
	}
	if len(request.Events)+len(request.Summaries) > 64 || len(request.CallHandle) > 128 {
		return nil, ErrCallControlInvalidRequest
	}
	n.mu.Lock()
	h, ctx := n.host, n.ctx
	if request.Op == "configure" || request.Op == "clear" {
		if request.ConsentEpoch <= 0 || request.ConsentEpoch < n.callDiagnosticConsentEpoch {
			n.mu.Unlock()
			return nil, ErrCallControlInvalidRequest
		}
		n.callDiagnosticConsentEpoch = request.ConsentEpoch
		if request.Op == "configure" && !request.Enabled {
			n.callDiagnosticsEnabled = false
		}
	}
	n.mu.Unlock()
	if h == nil || ctx == nil {
		return nil, ErrCallControlUnavailable
	}
	request.Action = callDiagnosticsV2Action
	raw, err := json.Marshal(request)
	if err != nil || len(raw) > 300<<10 {
		return nil, ErrCallControlInvalidRequest
	}
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	var result map[string]any
	var lastErr error
	relays := n.buildRelaySelector(nil).Relays()
	for i, relay := range relays {
		deadline, _ := ctx.Deadline()
		attemptCtx, stop := context.WithTimeout(ctx, time.Until(deadline)/time.Duration(len(relays)-i))
		response, err := exchangeCallDiagnosticRaw(attemptCtx, h, relay, raw)
		stop()
		if err != nil {
			lastErr = err
			continue
		}
		if diagnosticUnsupported(response) {
			n.setDiagnosticRelay(relay.ID, false)
			continue
		}
		var decoded struct {
			Status    string         `json:"status"`
			Version   int            `json:"version"`
			Data      map[string]any `json:"data"`
			ErrorCode string         `json:"errorCode"`
		}
		if json.Unmarshal(response, &decoded) != nil || decoded.Status != "OK" || decoded.Version != 2 || decoded.Data == nil {
			lastErr = ErrCallControlInvalidResponse
			continue
		}
		supported, _ := decoded.Data["supported"].(bool)
		n.setDiagnosticRelay(relay.ID, supported)
		if !supported {
			continue
		}
		result = decoded.Data
		if request.Op == "configure" {
			enabled, _ := result["enabled"].(bool)
			if enabled {
				n.mu.Lock()
				if n.callDiagnosticConsentEpoch == request.ConsentEpoch {
					n.callDiagnosticsEnabled = true
				}
				n.mu.Unlock()
			}
			continue
		}
		if request.Op == "clear" {
			continue
		}
		return result, nil
	}
	if result != nil {
		return result, nil
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return map[string]any{"supported": false}, nil
}
func exchangeCallDiagnosticRaw(ctx context.Context, h host.Host, relay RelayInfo, raw []byte) ([]byte, error) {
	if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
		return nil, ErrCallControlUnavailable
	}
	stream, err := h.NewStream(ctx, relay.ID, InboxProtocol)
	if err != nil {
		return nil, ErrCallControlUnavailable
	}
	streamOK := false
	defer finishStream(stream, &streamOK)
	deadline, _ := ctx.Deadline()
	if stream.SetDeadline(deadline) != nil {
		return nil, ErrCallControlUnavailable
	}
	stop := context.AfterFunc(ctx, func() { _ = stream.Reset() })
	defer stop()
	if writeFrame(stream, raw) != nil {
		return nil, ErrCallControlUnavailable
	}
	response, err := readFrame(stream)
	if err != nil {
		return nil, ErrCallControlUnavailable
	}
	streamOK = true
	return response, nil
}
