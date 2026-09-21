package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

// Exercise admission, real FIFO ordering, privacy transitions and durable bytes.
// The queued receipt must retain the capability admitted for that operation.
func TestAPNSReceiptQueuedLifetime(t *testing.T) {
	for _, mode := range []string{
		"valid", "mutable_context", "trace_retarget_before_enqueue", "exact_ttl",
		"owner_clear", "participant_clear", "owner_recreated", "participant_recreated",
		"owner_recreated_context_mutated", "participant_recreated_context_mutated",
		"participant_disable_reenabled", "participant_clear_failed", "participant_clear_recovered",
		"expired", "expired_failed_removal", "expired_recreated", "expired_recreated_context_mutated",
	} {
		for _, status := range []int{200, 410} {
			name := "accepted"
			if status == 410 {
				name = "rejected"
			}
			t.Run(mode+"/"+name, func(t *testing.T) {
				s, ctx, trace := receiptTestContext(t)
				actor, participant := "isolated-caller", "isolated-callee"
				if err := s.configure(participant, true, false, 1); err != nil {
					t.Fatal(err)
				}
				span := callDiagnosticSpanFromContext(ctx)
				admitted := span.diagnostics
				now := time.UnixMilli(s.records[trace].CreatedAtMs)
				s.now = func() time.Time { return now }
				other := publicationPrepare(t, s, actor, uuid.NewString())
				publicationEmit(s, actor, other)
				s.flush()
				if mode == "trace_retarget_before_enqueue" {
					// Another valid trace owned by the same actor cannot borrow this capability.
					span.diagnostics.TraceID = other.TraceID
				}
				resume := queuedPrivacyHold(t, s)
				response, err := receiptTestSend(receiptTestProvider(http.Header{}, status), ctx)
				if err != nil || response.StatusCode != status {
					t.Fatalf("provider changed: %+v, %v", response, err)
				}
				if mode == "mutable_context" {
					span.actor = participant
					span.diagnostics = other
				}
				recreate := strings.Contains(mode, "recreated") || mode == "participant_disable_reenabled"
				if strings.HasPrefix(mode, "owner_") || strings.HasPrefix(mode, "participant_") {
					who := actor
					if strings.HasPrefix(mode, "participant_") {
						who = participant
					}
					failed := mode == "participant_clear_failed" || mode == "participant_clear_recovered"
					if failed {
						s.remove = func(string) error { return errors.New("injected erase failure") }
					}
					var transitionErr error
					if mode == "participant_disable_reenabled" {
						transitionErr = s.configure(who, false, false, 2)
					} else {
						transitionErr = s.clearActor(who, 1)
					}
					if (transitionErr != nil) != failed {
						t.Fatalf("transition error=%v failed=%v", transitionErr, failed)
					}
					if mode == "participant_clear_recovered" {
						s.remove = os.Remove
						if err := s.clearActor(who, 1); err != nil {
							t.Fatal(err)
						}
						recreate = true
					}
					if mode == "participant_disable_reenabled" {
						if err := s.configure(who, true, false, 3); err != nil {
							t.Fatal(err)
						}
					}
				}
				if strings.HasPrefix(mode, "expired") || mode == "exact_ttl" {
					now = now.Add(callDiagnosticRetention)
					if mode != "exact_ttl" {
						now = now.Add(time.Millisecond)
					}
					for _, who := range []string{actor, participant} {
						if err := s.configure(who, true, who == actor, 1); err != nil {
							t.Fatal(err)
						}
					}
					if mode == "expired_failed_removal" {
						s.remove = func(string) error { return errors.New("injected expiry failure") }
					}
					s.mu.Lock()
					s.expireLocked()
					s.mu.Unlock()
				}
				if recreate {
					fresh := publicationPrepare(t, s, actor, trace)
					// Synchronous real upload persists the new lifetime while the worker waits.
					if !s.appendEvent(actor, diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
						t.Fatal("fresh record rejected")
					}
					s.mu.Lock()
					oldAllowed := s.contextAuthorizedLocked(actor, &admitted)
					freshAllowed := s.contextAuthorizedLocked(actor, &fresh)
					s.mu.Unlock()
					if oldAllowed || !freshAllowed {
						t.Fatal("core lifetime control failed")
					}
					if strings.HasSuffix(mode, "context_mutated") {
						span.diagnostics = fresh
					}
				}
				valid := mode == "valid" || mode == "mutable_context" || mode == "exact_ttl"
				var unchanged func()
				if !valid {
					unchanged = publicationObserve(t, s)
				}
				writes := 0
				writer := s.write
				s.write = func(path string, raw []byte) error {
					writes++
					if s.mu.TryLock() {
						s.mu.Unlock()
						t.Error("publication must hold privacy lock")
					}
					return writer(path, raw)
				}
				resume()
				s.flush()
				s.write = writer
				if !valid {
					unchanged()
				}
				want := 0
				if valid {
					want = 1
				}
				if writes != want || s.apnsCaptured != want {
					t.Errorf("writes=%d captured=%d want=%d", writes, s.apnsCaptured, want)
				}
				if rec := s.records[trace]; rec != nil && len(rec.APNSResponsesPrivate) != want {
					t.Error("unexpected memory receipt")
				}
				if rec := s.records[other.TraceID]; rec != nil && len(rec.APNSResponsesPrivate) != 0 {
					t.Error("receipt redirected to another trace")
				}
				if valid {
					var persisted callDiagnosticRecord
					if err := json.Unmarshal(queuedPrivacyRead(t, filepath.Join(s.dir, trace+".json")), &persisted); err != nil {
						t.Fatal(err)
					}
					if len(persisted.APNSResponsesPrivate) != 1 {
						t.Fatal("valid receipt not durable")
					}
					r := persisted.APNSResponsesPrivate[0]
					if r.TraceID != trace || r.RequestID != admitted.RequestID || r.StatusCode != status {
						t.Fatalf("receipt binding changed: %+v", r)
					}
				}
				hotfixAssertCallIndex(t, s)
				s.remove = os.Remove
				// Fresh admission after every denied transition remains capable of capture.
				if !valid {
					if err := s.clearActor(actor, 1); err != nil {
						t.Fatal(err)
					}
					fresh := publicationPrepare(t, s, actor, trace)
					publicationEmit(s, actor, fresh)
					s.flush()
					freshCtx := callDiagnosticWithContext(context.Background(), newCallDiagnosticSpan(s, actor, fresh, "store"))
					r, err := receiptTestSend(receiptTestProvider(http.Header{}, status), freshCtx)
					if err != nil || r.StatusCode != status {
						t.Fatal("fresh provider response changed")
					}
					s.flush()
					if s.apnsCaptured != 1 || len(s.records[trace].APNSResponsesPrivate) != 1 {
						t.Error("fresh capture refused or stale capture counted")
					}
					var persisted callDiagnosticRecord
					if err := json.Unmarshal(queuedPrivacyRead(t, filepath.Join(s.dir, trace+".json")), &persisted); err != nil || len(persisted.APNSResponsesPrivate) != 1 {
						t.Fatal("fresh receipt not durable", err)
					}
					hotfixAssertCallIndex(t, s)
				}
			})
		}
	}
}

func TestAPNSReceiptDeniedLifetimePreservesBodyError(t *testing.T) {
	s, ctx, trace := receiptTestContext(t)
	if err := s.clearActor("isolated-caller", 1); err != nil {
		t.Fatal(err)
	}
	fresh := publicationPrepare(t, s, "isolated-caller", trace)
	publicationEmit(s, "isolated-caller", fresh)
	s.flush()
	resume := queuedPrivacyHold(t, s)
	unchanged := publicationObserve(t, s)
	p := receiptTestProvider(http.Header{}, 503)
	p.client.Transport = apnsReceiptTransport(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 503, Header: http.Header{}, Body: apnsReceiptBrokenBody{}, Request: r}, nil
	})
	response, err := receiptTestSend(p, ctx)
	if !errors.Is(err, errAPNSVoIPNetwork) || response.StatusCode != 0 {
		t.Fatalf("body error changed: %+v %v", response, err)
	}
	resume()
	s.flush()
	unchanged()
	if s.apnsCaptured != 0 || len(s.records[trace].APNSResponsesPrivate) != 0 {
		t.Error("denied receipt persisted despite provider body error")
	}
}
