package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
)

const apnsVoIPCaptureMaxResponses = 32
const apnsVoIPCaptureMaxWindow = 30 * time.Minute

// A private, opt-in sidecar to the existing authenticated call trace. Neither
// IDs nor absence of IDs are delivery evidence or call authority. AttemptID is
// local correlation only; APNSID/UniqueID are exclusively returned HTTP headers.
type apnsVoIPResponseReceipt struct {
	AttemptID         string `json:"attemptId"`
	TraceID           string `json:"traceId"`
	RequestID         string `json:"requestId"`
	Environment       string `json:"environment"`
	Topic             string `json:"topic"`
	ExpirationSeconds int64  `json:"expirationSeconds"`
	StartedAtMs       int64  `json:"startedAtMs"`
	ResponseAtMs      int64  `json:"responseAtMs"`
	DurationNs        int64  `json:"durationNs"`
	StatusCode        int    `json:"statusCode"`
	APNSID            string `json:"apnsId,omitempty"`
	APNSIDState       string `json:"apnsIdState"`
	APNSUniqueID      string `json:"apnsUniqueId,omitempty"`
	APNSUniqueIDState string `json:"apnsUniqueIdState"`
}

type apnsVoIPCapturePolicy struct {
	owner string
	until time.Time
}

func parseAPNSVoIPCapturePolicy(owner, until string, now time.Time) apnsVoIPCapturePolicy {
	digest, err := hex.DecodeString(owner)
	deadline, timeErr := time.Parse(time.RFC3339, until)
	if err != nil || len(digest) != 32 || hex.EncodeToString(digest) != owner || timeErr != nil ||
		!deadline.After(now) || deadline.Sub(now) > apnsVoIPCaptureMaxWindow {
		return apnsVoIPCapturePolicy{}
	}
	// Carry the local monotonic clock so a wall-clock rollback cannot extend capture.
	return apnsVoIPCapturePolicy{owner: owner, until: now.Add(deadline.Sub(now))}
}

func apnsVoIPResponseID(header http.Header, name string, appleUUID bool) (string, string) {
	values := header.Values(name)
	if len(values) == 0 {
		return "", "missing"
	}
	if len(values) != 1 {
		return "", "malformed"
	}
	v := values[0]
	if appleUUID {
		if _, err := uuid.Parse(v); err != nil || len(v) != 36 {
			return "", "malformed"
		}
	} else {
		// Same bounded opaque grammar as the private development alert adapter.
		if len(v) < 8 || len(v) > 160 {
			return "", "malformed"
		}
		for _, c := range v {
			if !(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '.' || c == '_' || c == ':' || c == '-') {
				return "", "malformed"
			}
		}
	}
	return v, "present"
}

func (p *httpAPNSVoIPProvider) observeResponse(ctx context.Context, request apnsVoIPProviderRequest, response *http.Response, started time.Time) {
	// Closed queues and diagnostic observer failures must not change Send's result.
	defer func() { _ = recover() }()
	if p.responseObserver == nil && callDiagnosticSpanFromContext(ctx) == nil {
		return
	}
	received := time.Now()
	environment := "unknown"
	switch p.endpoint {
	case apnsVoIPSandboxEndpoint:
		environment = apnsVoIPEnvironmentSandbox
	case apnsVoIPProductionEndpoint:
		environment = apnsVoIPEnvironmentProduction
	}
	id, idState := apnsVoIPResponseID(response.Header, "apns-id", true)
	unique, uniqueState := apnsVoIPResponseID(response.Header, "apns-unique-id", false)
	r := apnsVoIPResponseReceipt{
		AttemptID: uuid.NewString(), Environment: environment, Topic: request.Topic,
		ExpirationSeconds: request.Expiration.Unix(), StartedAtMs: started.UnixMilli(),
		ResponseAtMs: received.UnixMilli(), DurationNs: received.Sub(started).Nanoseconds(),
		StatusCode: response.StatusCode, APNSID: id, APNSIDState: idState,
		APNSUniqueID: unique, APNSUniqueIDState: uniqueState,
	}
	if p.responseObserver != nil {
		p.responseObserver(ctx, r)
		return
	}
	span := callDiagnosticSpanFromContext(ctx)
	if span == nil || span.store == nil {
		return
	}
	s := span.store
	if s.apnsCapture.owner == "" || s.apnsCapture.owner != diagnosticPrivateKey(span.actor) ||
		!received.Before(s.apnsCapture.until) || !diagnosticUUID.MatchString(span.diagnostics.TraceID) {
		return
	}
	r.TraceID, r.RequestID = span.diagnostics.TraceID, span.diagnostics.RequestID
	actor, epoch := span.actor, span.diagnostics.consentEpoch
	s.enqueue(func() {
		// All disk work stays on the existing bounded worker, after HTTP response.
		defer func() { _ = recover() }()
		s.mu.Lock()
		defer s.mu.Unlock()
		consent := s.state.Consent[diagnosticPrivateKey(actor)]
		rec := s.records[r.TraceID]
		if !time.Now().Before(s.apnsCapture.until) || !consent.Enabled || consent.ConsentEpoch != epoch ||
			rec == nil || rec.Owner != s.apnsCapture.owner || s.apnsCaptured >= apnsVoIPCaptureMaxResponses ||
			len(rec.APNSResponsesPrivate) >= apnsVoIPCaptureMaxResponses {
			return
		}
		old := rec.APNSResponsesPrivate
		rec.APNSResponsesPrivate = append(append([]apnsVoIPResponseReceipt(nil), old...), r)
		// Share the existing global/owner/record quotas; private receipts cannot
		// consume unbounded space or silently displace causal stage events.
		total, ownerBytes := 0, 0
		for _, record := range s.records {
			raw, _ := json.Marshal(record)
			total += len(raw)
			if record.Owner == rec.Owner {
				ownerBytes += len(raw)
			}
		}
		raw, _ := json.Marshal(rec)
		if total > s.quota || ownerBytes > callDiagnosticOwnerBytes || len(raw) > callDiagnosticRecordBytes || s.persistLocked(r.TraceID) != nil {
			rec.APNSResponsesPrivate = old
			return
		}
		s.apnsCaptured++
	})
}
