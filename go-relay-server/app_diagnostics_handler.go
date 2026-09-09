package main

import (
	"encoding/json"
	"log"
	"os"
	"strconv"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

const appDiagnosticsAction = "app_diagnostics_v1"

var appDiagnosticReady = promauto.NewGauge(prometheus.GaugeOpts{Name: "relay_app_diagnostics_storage_ready", Help: "Whether the independent durable app diagnostic collector is available."})
var appDiagnosticRequests = promauto.NewCounterVec(prometheus.CounterOpts{Name: "relay_app_diagnostics_requests_total", Help: "App diagnostic requests by fixed operation and result."}, []string{"operation", "result"})
var appDiagnosticReplyFailures = promauto.NewCounter(prometheus.CounterOpts{Name: "relay_app_diagnostics_reply_write_failures_total", Help: "Response write failures after app diagnostic processing; retries remain idempotent."})
var appDiagnosticEvents = promauto.NewCounterVec(prometheus.CounterOpts{Name: "relay_app_diagnostics_events_total", Help: "App diagnostic upload acknowledgements by fixed result/reason; includes idempotent retries, not unique event counts."}, []string{"result", "reason"})

func initAppDiagnosticsFromEnvironment() *appDiagnosticStore {
	appDiagnosticReady.Set(0)
	dir := os.Getenv("APP_DIAGNOSTICS_DIR")
	if dir == "" {
		return nil
	}
	quota := appDiagnosticGlobalBytes
	if raw := os.Getenv("APP_DIAGNOSTICS_MAX_BYTES"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1<<20 || n > 1<<30 {
			log.Print("app_diagnostics state=invalid_config")
			return nil
		}
		quota = n
	}
	s, err := newAppDiagnosticStore(dir, quota, nil)
	if err != nil {
		log.Print("app_diagnostics state=sink_unavailable")
		return nil
	}
	appDiagnosticReady.Set(1)
	log.Print("app_diagnostics state=ready")
	return s
}

type appDiagnosticWireRequest struct {
	Action       string            `json:"action"`
	Op           string            `json:"op"`
	ConsentEpoch int64             `json:"consentEpoch,omitempty"`
	Enabled      *bool             `json:"enabled,omitempty"`
	Events       []json.RawMessage `json:"events,omitempty"`
}

func appDiagnosticErrorReason(err error) string {
	if err == nil {
		return "none"
	}
	switch err.Error() {
	case "stale_epoch":
		return "stale_epoch"
	case "quota_exceeded":
		return "quota_exceeded"
	}
	if err == errAppDiagnosticInvalid {
		return "invalid_request"
	}
	return "sink_unavailable"
}

// Only the authenticated stream actor chooses the private owner partition.
// The payload has no owner, peer, account, handle or server-event authority field.
func appDiagnosticResponse(raw []byte, actor string, store *appDiagnosticStore) map[string]any {
	var req appDiagnosticWireRequest
	op, result := "unknown", "invalid_request"
	defer func() { appDiagnosticRequests.WithLabelValues(op, result).Inc() }()
	invalid := map[string]any{"status": "ERROR", "errorCode": "APP_DIAGNOSTICS_INVALID_REQUEST"}
	if actor == "" || len(raw) > 300<<10 || appDiagnosticDecode(raw, &req) != nil || req.Action != appDiagnosticsAction {
		return invalid
	}
	switch req.Op {
	case "configure", "clear", "upload", "capabilities":
		op = req.Op
	default:
		return invalid
	}
	if (op != "capabilities" && (req.ConsentEpoch <= 0 || req.ConsentEpoch > 9007199254740991)) || (op == "configure" && req.Enabled == nil) || (op != "configure" && req.Enabled != nil) || (op != "upload" && req.Events != nil) {
		return invalid
	}
	data := map[string]any{"supported": store != nil}
	response := map[string]any{"status": "OK", "version": 1, "data": data}
	if store == nil {
		result = "unsupported"
		return response
	}
	result = "ok"
	switch op {
	case "configure", "clear":
		enabled := false
		if req.Enabled != nil {
			enabled = *req.Enabled
		}
		if err := store.configure(actor, enabled, req.ConsentEpoch, op == "clear"); err != nil {
			result = appDiagnosticErrorReason(err)
			data["reason"] = result
		}
	case "upload":
		accepted, rejected := []string{}, []string{}
		if len(req.Events) > 64 {
			data["reason"] = "quota_exceeded"
			result = "quota_exceeded"
		} else {
			for _, event := range req.Events {
				status, reason := store.append(actor, req.ConsentEpoch, event)
				appDiagnosticEvents.WithLabelValues(status, reason).Inc()
				var id struct {
					EventID string `json:"eventId"`
				}
				_ = json.Unmarshal(event, &id)
				if diagnosticUUID.MatchString(id.EventID) {
					if status == "accepted" {
						accepted = append(accepted, id.EventID)
					} else if status == "rejected" {
						rejected = append(rejected, id.EventID)
					}
				}
				if reason != "none" {
					data["reason"] = reason
					result = reason
				}
			}
		}
		data["acceptedEventIds"] = accepted
		data["rejectedEventIds"] = rejected
	}
	state := store.state(actor)
	data["enabled"] = state.Enabled && !state.ErasePending
	data["consentEpoch"] = state.Epoch
	return response
}
func handleAppDiagnosticRequest(s network.Stream, raw []byte, actor string, store *appDiagnosticStore) {
	response := appDiagnosticResponse(raw, actor, store)
	encoded, err := json.Marshal(response)
	if err == nil && writeFrame(s, encoded) != nil {
		appDiagnosticReplyFailures.Inc()
	}
}
