package main

import (
	"context"
	"encoding/json"
	"runtime/debug"
	"time"

	"github.com/google/uuid"
	"github.com/libp2p/go-libp2p/core/network"
)

const callDiagnosticsAction = "call_diagnostics_v2"

// Set to the reviewed source digest at release build time. No environment data.
var callDiagnosticBuild string

func serverCallDiagnosticBuild() string {
	if diagnosticBuild.MatchString(callDiagnosticBuild) {
		return callDiagnosticBuild
	}
	if info, ok := debug.ReadBuildInfo(); ok {
		revision := ""
		dirty := false
		for _, setting := range info.Settings {
			if setting.Key == "vcs.revision" {
				revision = setting.Value
			}
			if setting.Key == "vcs.modified" && setting.Value == "true" {
				dirty = true
			}
		}
		if dirty {
			revision += ".dirty"
		}
		if diagnosticBuild.MatchString(revision) {
			return revision
		}
	}
	return "unknown"
}

type callDiagnosticWireRequest struct {
	ConsentEpoch int64             `json:"consentEpoch,omitempty"`
	Action       string            `json:"action"`
	Op           string            `json:"op"`
	Enabled      bool              `json:"enabled,omitempty"`
	PushTrace    bool              `json:"pushTrace,omitempty"`
	TraceID      string            `json:"traceId,omitempty"`
	CallHandle   string            `json:"callHandle,omitempty"`
	Events       []json.RawMessage `json:"events,omitempty"`
	Summaries    []json.RawMessage `json:"summaries,omitempty"`
	Request      json.RawMessage   `json:"request,omitempty"`
	Diagnostics  json.RawMessage   `json:"diagnostics,omitempty"`
}

func handleCallDiagnosticRequest(s network.Stream, raw []byte, actor string, service *CallControlService, issuer TurnCredentialIssuer) {
	var req callDiagnosticWireRequest
	if len(raw) > 300<<10 || diagnosticDecode(raw, &req) != nil || req.Action != callDiagnosticsAction || actor == "" {
		_ = writeFrame(s, []byte(`{"status":"ERROR","errorCode":"CALL_INVALID_REQUEST"}`))
		return
	}
	var store *callDiagnosticStore
	if service != nil {
		store = service.diagnostics
	}
	if req.Op == "request" {
		// Metadata is advisory. A malformed/unavailable/disabled diagnostic sink
		// never changes authorization or execution of the strictly decoded v1 body.
		var inner struct {
			Action string `json:"action"`
		}
		if json.Unmarshal(req.Request, &inner) != nil || (!isCallControlAction(inner.Action) && inner.Action != turnCredentialsAction) {
			_ = writeFrame(s, []byte(`{"status":"ERROR","errorCode":"CALL_INVALID_REQUEST"}`))
			return
		}
		var d callDiagnosticContext
		var span *callDiagnosticSpan
		if len(req.Diagnostics) <= 512 && diagnosticDecode(req.Diagnostics, &d) == nil && store.prepare(actor, &d, req.ConsentEpoch) {
			span = newCallDiagnosticSpan(store, actor, d, inner.Action)
		}
		wrapped := &callDiagnosticStream{Stream: s, span: span}
		if isCallControlAction(inner.Action) {
			handleCallControlRequest(wrapped, req.Request, actor, service)
		} else {
			handleTurnCredentialRequest(wrapped, req.Request, actor, issuer)
		}
		return
	}
	data := map[string]any{"supported": store != nil}
	if store == nil {
		diagnosticWriteData(s, data)
		return
	}
	switch req.Op {
	case "capabilities":
		data["version"] = 2
	case "configure":
		if store.configure(actor, req.Enabled, req.PushTrace, req.ConsentEpoch) != nil {
			data["enabled"] = false
			data["reason"] = "sink_unavailable"
		} else {
			data["enabled"] = req.Enabled
		}
	case "clear":
		if store.clearActor(actor, req.ConsentEpoch) != nil {
			data["reason"] = "sink_unavailable"
		}
		data["enabled"] = store.enabled(actor)
	case "resolve":
		trace := ""
		if len(req.CallHandle) <= 128 {
			trace = store.resolve(actor, req.CallHandle)
		}
		data["resolved"] = trace != ""
		if trace != "" {
			data["traceId"] = trace
		}
	case "bind": // Only confirm an already proven participant binding; this cannot create call authority.
		data["bound"] = diagnosticUUID.MatchString(req.TraceID) && len(req.CallHandle) <= 128 && store.resolve(actor, req.CallHandle) == req.TraceID
	case "upload":
		accepted, rejected := []string{}, []string{}
		batch := append(append([]json.RawMessage(nil), req.Events...), req.Summaries...)
		if len(batch) > 64 {
			data["reason"] = "quota_exceeded"
			data["acceptedEventIds"] = accepted
			data["rejectedEventIds"] = rejected
			break
		}
		for _, event := range batch {
			var id struct {
				EventID string `json:"eventId"`
			}
			_ = json.Unmarshal(event, &id)
			if !diagnosticUUID.MatchString(id.EventID) {
				continue
			}
			fields, validationErr := validateCallDiagnosticEvent(event, false)
			if validationErr != nil {
				rejected = append(rejected, id.EventID)
				callDiagnosticEvents.WithLabelValues("rejected").Inc()
				continue
			}
			trace, _ := fields["traceId"].(string)
			if trace != "" {
				store.metaMu.Lock()
				exists := store.metadata[trace] != nil
				authorized := store.authorizedMetadataLocked(actor, trace)
				store.metaMu.Unlock()
				if exists && !authorized {
					rejected = append(rejected, id.EventID)
					callDiagnosticEvents.WithLabelValues("rejected").Inc()
					continue
				}
			}
			switch store.appendEventResult(actor, event, false, req.ConsentEpoch) {
			case callDiagnosticAppendAccepted:
				accepted = append(accepted, id.EventID)
				callDiagnosticEvents.WithLabelValues("accepted").Inc()
			case callDiagnosticAppendDiscarded:
				// A full retained trace cannot recover ordinary event capacity;
				// let the client advance to its reserved media/terminal records.
				rejected = append(rejected, id.EventID)
				if data["reason"] == nil {
					data["reason"] = "quota_exceeded"
				}
				callDiagnosticEvents.WithLabelValues("quota_exceeded").Inc()
			default:
				data["reason"] = "sink_unavailable"
				callDiagnosticEvents.WithLabelValues("sink_unavailable").Inc()
			}

		}
		data["acceptedEventIds"] = accepted
		data["rejectedEventIds"] = rejected
	default:
		_ = writeFrame(s, []byte(`{"status":"ERROR","errorCode":"CALL_INVALID_REQUEST"}`))
		return
	}
	diagnosticWriteData(s, data)
}
func diagnosticWriteData(s network.Stream, data map[string]any) {
	raw, _ := json.Marshal(map[string]any{"status": "OK", "version": 2, "data": data})
	_ = writeFrame(s, raw)
}

type callDiagnosticStream struct {
	network.Stream
	span *callDiagnosticSpan
}
type callDiagnosticContextKey struct{}
type callDiagnosticSpan struct {
	authorityKind string
	store         *callDiagnosticStore
	actor         string
	diagnostics   callDiagnosticContext
	action        string
	started       time.Time
}

func newCallDiagnosticSpan(store *callDiagnosticStore, actor string, d callDiagnosticContext, action string) *callDiagnosticSpan {
	if d.RequestID == "" {
		d.RequestID = uuid.NewString()
	}
	return &callDiagnosticSpan{store: store, actor: actor, diagnostics: d, action: action, started: time.Now()}
}
func callDiagnosticSpanFromStream(stream any) *callDiagnosticSpan {
	if wrapped, ok := stream.(*callDiagnosticStream); ok {
		return wrapped.span
	}
	return nil
}
func callDiagnosticWithContext(ctx context.Context, span *callDiagnosticSpan) context.Context {
	if span == nil {
		return ctx
	}
	return context.WithValue(ctx, callDiagnosticContextKey{}, span)
}
func callDiagnosticSpanFromContext(ctx context.Context) *callDiagnosticSpan {
	span, _ := ctx.Value(callDiagnosticContextKey{}).(*callDiagnosticSpan)
	return span
}
func (s *callDiagnosticSpan) emit(stage, action, outcome, reason string, values map[string]any) {
	if s == nil {
		return
	}
	if reason == "" {
		reason = "none"
	}
	if values == nil {
		values = map[string]any{}
	}
	if stage == "authority" {
		kind := s.authorityKind
		if kind == "" {
			kind = "unknown"
		}
		values["authorityKind"] = kind
	}
	e := map[string]any{"schemaVersion": 1, "eventId": uuid.NewString(), "source": "relay", "role": "server", "runId": s.store.runID, "sequence": s.store.sequence.Add(1), "occurredAtMs": s.store.now().UnixMilli(), "elapsedMs": time.Since(s.started).Milliseconds(), "stage": stage, "action": action, "outcome": outcome, "reason": reason, "values": values, "requestId": s.diagnostics.RequestID, "build": serverCallDiagnosticBuild()}
	if s.diagnostics.TraceID != "" {
		e["traceId"] = s.diagnostics.TraceID
	}
	if s.diagnostics.OperationID != "" {
		e["operationId"] = s.diagnostics.OperationID
	}
	if s.diagnostics.ParentOperationID != "" {
		e["parentOperationId"] = s.diagnostics.ParentOperationID
	}
	raw, err := json.Marshal(e)
	if err != nil {
		return
	}
	s.store.enqueue(func() {
		switch s.store.appendEventResult(s.actor, raw, true, s.diagnostics.consentEpoch) {
		case callDiagnosticAppendDiscarded:
			s.store.drop("quota_exceeded")
		case callDiagnosticAppendRetry:
			s.store.drop("sink_unavailable")
		}
	})
}
func diagnosticAction(action string) (string, string) {
	switch action {
	case callStoreAction:
		return "signaling", "store"
	case callRetrieveAction:
		return "signaling", "retrieve"
	case callAckAction:
		return "signaling", "ack"
	case callCancelAction:
		return "terminal", "cancel"
	case callEndpointGetAction:
		return "authority", "lookup"
	case callEndpointSetAction, callWakeHandleSetAction, callTokenSetAction:
		return "authority", "publish"
	case callEndpointRevokeAction, callWakeHandleRevokeAction, callTokenRevokeAction:
		return "authority", "revoke"
	case turnCredentialsAction:
		return "turn", "mint"
	}
	return "runtime", "check"
}
func (s *callDiagnosticSpan) result(request callControlWireRequest, response callControlWireResponse, writeErr error) {
	if s == nil {
		return
	}
	stage, action := diagnosticAction(request.Action)
	outcome, reason := "ok", s.diagnostics.Reason
	values := map[string]any{}
	if response.Status != "OK" {
		outcome = "failed"
		reason = diagnosticReason(response.ErrorCode)
	} else {
		switch request.Action {
		case callRetrieveAction:
			if len(response.Events) == 0 && writeErr == nil {
				return
			}
			values["count"] = len(response.Events)
			values["hasMore"] = response.HasMore
		case callAckAction:
			values["acked"] = response.Acked
		case callEndpointGetAction:
			values["found"] = response.Found
			if !response.Found {
				outcome = "not_found_or_expired"
				reason = "not_found_or_expired"
			}
			change := s.store.lastAuthority(request.AccountPeerID)
			if change.OperationID != "" && s.diagnostics.ParentOperationID == "" {
				s.diagnostics.ParentOperationID = change.OperationID
			}
		case callEndpointSetAction, callEndpointRevokeAction:
			s.store.authorityChange(s.actor, request.AccountPeerID, &s.diagnostics, "endpoint")
		case callWakeHandleSetAction, callWakeHandleRevokeAction, callTokenSetAction, callTokenRevokeAction:
			if response.Revoked != nil && !*response.Revoked {
				values["accepted"] = false
				outcome = "skipped"
			} else {
				s.store.authorityChange(s.actor, s.actor, &s.diagnostics, diagnosticAuthorityKind(request))
			}
		}
	}
	s.emit(stage, action, outcome, reason, values)
	outcome, reason = "ok", "none"
	if writeErr != nil {
		outcome, reason = "failed", "write_failed"
	}
	s.emit(stage, "response", outcome, reason, map[string]any{"responseWritten": writeErr == nil})
}
func callDiagnosticProvider(ctx context.Context, platform string, attempt int, started bool, err error) {
	span := callDiagnosticSpanFromContext(ctx)
	if span == nil {
		return
	}
	outcome, reason := "ok", "none"
	if started {
		outcome = "started"
	} else if err != nil {
		outcome, reason = "failed", "provider_error"
	}
	span.emit("push", "dispatch", outcome, reason, map[string]any{"platform": platform, "retry": attempt, "providerInvoked": true})
}

func diagnosticAuthorityKind(request callControlWireRequest) string {
	switch request.Action {
	case callEndpointSetAction, callEndpointGetAction, callEndpointRevokeAction:
		return "endpoint"
	case callWakeHandleSetAction, callWakeHandleRevokeAction:
		return "wake_grant"
	case callTokenSetAction, callTokenRevokeAction:
		if request.TokenKind == string(CallTokenKindStandard) {
			return "standard_call_token"
		}
		if request.TokenKind == string(CallTokenKindIOSVoIP) {
			return "ios_voip_token"
		}
	}
	return "unknown"
}
