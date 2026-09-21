package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
)

type apnsReceiptTransport func(*http.Request) (*http.Response, error)

func (f apnsReceiptTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func receiptTestContext(t *testing.T) (*callDiagnosticStore, context.Context, string) {
	t.Helper()
	s := diagnosticTestStore(t)
	actor, trace := "isolated-caller", uuid.NewString()
	if err := s.configure(actor, true, true, 1); err != nil {
		t.Fatal(err)
	}
	d := callDiagnosticContext{TraceID: trace}
	if !s.prepare(actor, &d, 1) {
		t.Fatal("prepare")
	}
	s.bindCommitted(actor, "isolated-callee", "private-handle", &d)
	s.flush()
	s.apnsCapture = apnsVoIPCapturePolicy{owner: diagnosticPrivateKey(actor), until: time.Now().Add(time.Minute)}
	return s, callDiagnosticWithContext(context.Background(), newCallDiagnosticSpan(s, actor, d, "store")), trace
}

func receiptTestProvider(headers http.Header, status int) *httpAPNSVoIPProvider {
	p := newHTTPAPNSVoIPProviderForEndpoint(apnsVoIPSandboxEndpoint, &vc205AuthorizationSource{authorization: "bearer private-jwt"})
	p.client = &http.Client{Transport: apnsReceiptTransport(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: status, Header: headers, Body: io.NopCloser(strings.NewReader("")), Request: r}, nil
	})}
	return p
}

func receiptTestSend(p *httpAPNSVoIPProvider, ctx context.Context) (apnsVoIPProviderResponse, error) {
	return p.Send(ctx, apnsVoIPProviderRequest{Token: "private-token", Topic: callTestVoIPTopic, Expiration: time.Now().Add(time.Second), Payload: []byte("private-payload")})
}

func TestAPNSVoIPPrivateReceiptOptionalIDsNeverChangeResponse(t *testing.T) {
	for _, tc := range []struct{ name, id, unique, state string }{
		{"present", "7E6EC2B2-5AA1-4B43-ACB9-93BC1A9029F3", "4090d3d1-b615-250a-79e5-d39e3801b542", "present"},
		{"missing", "", "", "missing"},
		{"malformed", "private-token\n", "private-payload\r", "malformed"},
		{"oversized", strings.Repeat("a", 300), strings.Repeat("b", 300), "malformed"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, ctx, trace := receiptTestContext(t)
			h := http.Header{}
			if tc.id != "" {
				h.Set("apns-id", tc.id)
			}
			if tc.unique != "" {
				h.Set("apns-unique-id", tc.unique)
			}
			p := receiptTestProvider(h, 200)
			for i := 0; i < 2; i++ {
				r, err := receiptTestSend(p, ctx)
				if err != nil || r.StatusCode != 200 {
					t.Fatalf("response changed: %v", err)
				}
			}
			s.flush()
			receipts := s.records[trace].APNSResponsesPrivate
			if len(receipts) != 2 {
				t.Fatalf("receipts = %d", len(receipts))
			}
			for _, r := range receipts {
				if r.APNSIDState != tc.state || r.APNSUniqueIDState != tc.state || r.StatusCode != 200 || r.Environment != "sandbox" || r.TraceID != trace || r.RequestID == "" || r.DurationNs < 0 || r.StartedAtMs <= 0 || r.ResponseAtMs <= 0 {
					t.Fatal("incorrect attempt evidence")
				}
				if tc.state == "present" && (r.APNSID != tc.id || r.APNSUniqueID != tc.unique) {
					t.Fatal("returned IDs altered")
				}
				if tc.state != "present" && (r.APNSID != "" || r.APNSUniqueID != "") {
					t.Fatal("invented or malformed ID retained")
				}
			}
			if receipts[0].AttemptID == receipts[1].AttemptID {
				t.Fatal("distinct sends coalesced")
			}
			raw, err := os.ReadFile(filepath.Join(s.dir, trace+".json"))
			if err != nil {
				t.Fatal(err)
			}
			for _, secret := range []string{"private-token", "private-jwt", "private-payload", "private-handle", "isolated-caller"} {
				if strings.Contains(string(raw), secret) {
					t.Fatal("private input copied to receipt")
				}
			}
			info, _ := os.Stat(filepath.Join(s.dir, trace+".json"))
			if info.Mode().Perm() != 0600 {
				t.Fatal("receipt permissions")
			}
		})
	}
}

func TestAPNSVoIPPrivateReceiptProductionMissingUniqueIDAndObserverFailure(t *testing.T) {
	s, ctx, trace := receiptTestContext(t)
	p := receiptTestProvider(http.Header{}, 200)
	p.endpoint = apnsVoIPProductionEndpoint
	r, err := receiptTestSend(p, ctx)
	if err != nil || r.StatusCode != 200 {
		t.Fatal("production requires a development ID")
	}
	s.flush()
	if rows := s.records[trace].APNSResponsesPrivate; len(rows) != 1 || rows[0].Environment != "production" || rows[0].APNSUniqueIDState != "missing" {
		t.Fatal("production evidence")
	}
	p.responseObserver = func(context.Context, apnsVoIPResponseReceipt) { panic("private-observer-error") }
	if r, err := receiptTestSend(p, ctx); err != nil || r.StatusCode != 200 {
		t.Fatal("observer panic changed delivery")
	}
	// A diagnostic disk failure cannot change the provider result or its retry classification.
	p.responseObserver = nil
	s.dir = filepath.Join(t.TempDir(), "absent", "directory")
	if r, err := receiptTestSend(p, ctx); err != nil || r.StatusCode != 200 {
		t.Fatal("observer I/O changed delivery")
	}
	s.flush()
}

func TestAPNSVoIPPrivateReceiptScopeQuotaConsentAndRetention(t *testing.T) {
	s, ctx, trace := receiptTestContext(t)
	p := receiptTestProvider(http.Header{}, 400)
	for _, policy := range []apnsVoIPCapturePolicy{{}, {owner: "wrong-owner", until: time.Now().Add(time.Minute)}, {owner: diagnosticPrivateKey("isolated-caller"), until: time.Now().Add(-time.Second)}} {
		s.apnsCapture = policy
		if r, err := receiptTestSend(p, ctx); err != nil || r.StatusCode != 400 {
			t.Fatal("diagnostics changed rejection")
		}
		s.flush()
	}
	if len(s.records[trace].APNSResponsesPrivate) != 0 {
		t.Fatal("unscoped capture")
	}
	s.apnsCapture = apnsVoIPCapturePolicy{owner: diagnosticPrivateKey("isolated-caller"), until: time.Now().Add(time.Minute)}
	for i := 0; i < apnsVoIPCaptureMaxResponses+2; i++ {
		_, _ = receiptTestSend(p, ctx)
		s.flush()
	}
	if len(s.records[trace].APNSResponsesPrivate) != apnsVoIPCaptureMaxResponses {
		t.Fatal("unbounded capture")
	}
	if err := s.configure("isolated-caller", false, false, 2); err != nil {
		t.Fatal(err)
	}
	_, _ = receiptTestSend(p, ctx)
	s.flush()
	if s.records[trace] != nil {
		t.Fatal("receipt recreated after consent withdrawal")
	}
	if _, err := os.Stat(filepath.Join(s.dir, trace+".json")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("private receipt survived purge")
	}
}

func TestAPNSVoIPPrivateReceiptPolicyFailsClosed(t *testing.T) {
	now := time.Now()
	owner := diagnosticPrivateKey("isolated-caller")
	for _, until := range []string{"", "invalid", now.Add(-time.Second).Format(time.RFC3339), now.Add(time.Hour).Format(time.RFC3339)} {
		if p := parseAPNSVoIPCapturePolicy(owner, until, now); p.owner != "" {
			t.Fatal("invalid window enabled capture")
		}
	}
	if p := parseAPNSVoIPCapturePolicy(owner, now.Add(time.Minute).Format(time.RFC3339), now); p.owner != owner {
		t.Fatal("valid capture refused")
	}
	if p := parseAPNSVoIPCapturePolicy("not-an-owner-digest", now.Add(time.Minute).Format(time.RFC3339), now); p.owner != "" {
		t.Fatal("invalid owner accepted")
	}
}

func TestAPNSVoIPPrivateReceiptExpiryAndFullWorkerDoNotAffectDelivery(t *testing.T) {
	s, ctx, trace := receiptTestContext(t)
	p := receiptTestProvider(http.Header{}, 200)
	_, _ = receiptTestSend(p, ctx)
	s.flush()
	s.mu.Lock()
	s.records[trace].CreatedAtMs = time.Now().Add(-callDiagnosticRetention - time.Minute).UnixMilli()
	s.expireLocked()
	s.mu.Unlock()
	if _, err := os.Stat(filepath.Join(s.dir, trace+".json")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("expired private receipt retained")
	}
	entered, release := make(chan struct{}), make(chan struct{})
	s.queue <- func() { close(entered); <-release }
	<-entered
	for i := 0; i < cap(s.queue); i++ {
		s.queue <- func() {}
	}
	done := make(chan error, 1)
	go func() {
		r, err := receiptTestSend(p, ctx)
		if err == nil && r.StatusCode != 200 {
			err = errors.New("response changed")
		}
		done <- err
	}()
	select {
	case err := <-done:
		close(release)
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		close(release)
		t.Fatal("HTTP result waited for diagnostic worker")
	}
	s.flush()
}

func TestAPNSVoIPPrivateReceiptSurvivesBodyFailureWithoutInventingAcceptance(t *testing.T) {
	s, ctx, trace := receiptTestContext(t)
	p := receiptTestProvider(http.Header{}, 200)
	p.client.Transport = apnsReceiptTransport(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 503, Header: http.Header{"Apns-Id": []string{uuid.NewString(), uuid.NewString()}}, Body: apnsReceiptBrokenBody{}, Request: r}, nil
	})
	_, err := receiptTestSend(p, ctx)
	if !errors.Is(err, errAPNSVoIPNetwork) {
		t.Fatal("body failure classification changed")
	}
	s.flush()
	rows := s.records[trace].APNSResponsesPrivate
	if len(rows) != 1 || rows[0].StatusCode != 503 || rows[0].APNSIDState != "malformed" || rows[0].APNSID != "" {
		t.Fatal("response headers lost or ambiguous ID accepted")
	}
	raw, _ := json.Marshal(rows[0])
	if strings.Contains(string(raw), "body-secret") {
		t.Fatal("body error leaked")
	}
}

type apnsReceiptBrokenBody struct{}

func (apnsReceiptBrokenBody) Read([]byte) (int, error) { return 0, errors.New("body-secret") }
func (apnsReceiptBrokenBody) Close() error             { return nil }

// Integration regressions exercise the real queued receipt observer against the
// ingestion store. Provider I/O is an in-process transport, never live APNs.
func receiptIntegrationSend(t *testing.T, s *callDiagnosticStore, ctx context.Context) {
	t.Helper()
	if r, err := receiptTestSend(receiptTestProvider(http.Header{}, 200), ctx); err != nil || r.StatusCode != 200 {
		t.Fatalf("diagnostic capture changed provider response: %v", err)
	}
	s.flush()
}

func receiptIntegrationDisk(t *testing.T, s *callDiagnosticStore, trace string) []byte {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(s.dir, trace+".json"))
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func TestAPNSVoIPIntegrationQueuedPrivacy(t *testing.T) {
	for _, mode := range []string{"normal", "window_expired", "disabled", "owner_erase_pending", "participant_erase_pending", "stale_epoch", "expired_record", "quarantined_record"} {
		t.Run(mode, func(t *testing.T) {
			s, ctx, trace := receiptTestContext(t)
			if err := s.configure("isolated-callee", true, false, 1); err != nil {
				t.Fatal(err)
			}
			entered, release := make(chan struct{}), make(chan struct{})
			s.queue <- func() { close(entered); <-release }
			<-entered
			var once sync.Once
			defer once.Do(func() { close(release) })
			if r, err := receiptTestSend(receiptTestProvider(http.Header{}, 200), ctx); err != nil || r.StatusCode != 200 {
				t.Fatal("provider response changed")
			}
			s.remove = func(string) error { return errors.New("injected erase failure") }
			switch mode {
			case "window_expired":
				s.apnsCapture.until = time.Now().Add(-time.Second)
			case "disabled":
				if s.configure("isolated-caller", false, false, 2) == nil {
					t.Fatal("expected erase fault")
				}
			case "owner_erase_pending":
				if s.clearActor("isolated-caller", 1) == nil {
					t.Fatal("expected erase fault")
				}
			case "participant_erase_pending":
				if s.clearActor("isolated-callee", 1) == nil {
					t.Fatal("expected erase fault")
				}
			case "stale_epoch":
				if err := s.configure("isolated-caller", true, true, 2); err != nil {
					t.Fatal(err)
				}
			case "expired_record", "quarantined_record":
				s.mu.Lock()
				s.records[trace].CreatedAtMs = s.now().Add(-callDiagnosticRetention - time.Second).UnixMilli()
				err := s.persistLocked(trace)
				if mode == "quarantined_record" {
					s.expireLocked()
				}
				s.mu.Unlock()
				if err != nil {
					t.Fatal(err)
				}
			}
			before := receiptIntegrationDisk(t, s, trace)
			writes := 0
			s.write = func(path string, raw []byte) error { writes++; return appDiagnosticAtomicWrite(path, raw) }
			once.Do(func() { close(release) })
			s.flush()
			want := 0
			if mode == "normal" {
				want = 1
			}
			if len(s.records[trace].APNSResponsesPrivate) != want || s.apnsCaptured != want || writes != want {
				t.Errorf("queued %s capture: receipts=%d counter=%d writes=%d, want %d", mode, len(s.records[trace].APNSResponsesPrivate), s.apnsCaptured, writes, want)
			}
			if want == 0 && !bytes.Equal(before, receiptIntegrationDisk(t, s, trace)) {
				t.Error("privacy refusal changed retained bytes")
			}
			hotfixAssertCallIndex(t, s)
		})
	}
}

// Seed retained records through the existing persistence/index path. Padding is
// a storage fixture, not a claim that oversized endpoint events are admissible.
func receiptIntegrationSeed(t *testing.T, s *callDiagnosticStore, owner string, bytes int) {
	t.Helper()
	key := uuid.NewString()
	s.records[key] = &callDiagnosticRecord{Owner: owner, CreatedAtMs: s.now().UnixMilli(), DropAccountingVersion: 1,
		Events: []callDiagnosticStoredEvent{{Event: json.RawMessage(`{"padding":"` + strings.Repeat("x", bytes) + `"}`)}}}
	if err := s.persistLocked(key); err != nil {
		t.Fatal(err)
	}
}

func TestAPNSVoIPIntegrationBudgets(t *testing.T) {
	for _, mode := range []string{"owner_hard", "global_hard", "record_hard", "owner_priority", "global_priority", "owner_binding_reserves", "global_binding_reserves", "raised_owner_override"} {
		t.Run(mode, func(t *testing.T) {
			s, ctx, trace := receiptTestContext(t)
			owner := diagnosticPrivateKey("isolated-caller")
			switch mode {
			case "owner_hard":
				s.ownerQuota = s.ownerSizes[owner] + 1
			case "global_hard":
				s.quota = s.usedBytes + 1
			case "record_hard":
				rec := s.records[trace]
				rec.Events = []callDiagnosticStoredEvent{{Event: json.RawMessage(`{"padding":""}`)}}
				padding := callDiagnosticRecordBytes - len(mustDiagnosticJSON(rec)) - 100
				rec.Events[0].Event = json.RawMessage(`{"padding":"` + strings.Repeat("x", padding) + `"}`)
				if err := s.persistLocked(trace); err != nil {
					t.Fatal(err)
				}
			case "owner_priority":
				s.ownerQuota = s.ownerSizes[owner] + callDiagnosticPriorityBytes + 1
			case "global_priority":
				s.quota = s.usedBytes + callDiagnosticPriorityBytes + 1
			case "owner_binding_reserves", "global_binding_reserves":
				for i := 0; i < 128; i++ {
					receiptIntegrationSeed(t, s, owner, 0)
				}
				if s.bindingReserved < callDiagnosticPriorityBytes+1024 {
					t.Fatal("fixture needs binding reserve beyond priority headroom")
				}
				if mode == "owner_binding_reserves" {
					s.ownerQuota = s.ownerSizes[owner] + s.ownerBindingReserves[owner] + 1
				} else {
					s.quota = s.usedBytes + s.bindingReserved + 1
				}
			case "raised_owner_override":
				for i := 0; i < 18; i++ {
					receiptIntegrationSeed(t, s, owner, 300<<10)
				}
				if s.ownerSizes[owner] <= callDiagnosticOwnerBytes {
					t.Fatal("fixture must exceed old constant owner cap")
				}
				t.Setenv("CALL_DIAGNOSTICS_OWNER_MAX_BYTES", "8388608")
				s.ownerQuota = diagnosticOwnerQuota("CALL_DIAGNOSTICS_OWNER_MAX_BYTES", callDiagnosticOwnerBytes, s.quota)
			}
			before := receiptIntegrationDisk(t, s, trace)
			writes := 0
			s.write = func(path string, raw []byte) error { writes++; return appDiagnosticAtomicWrite(path, raw) }
			receiptIntegrationSend(t, s, ctx)
			want := 0
			if mode == "raised_owner_override" {
				want = 1
			}
			if len(s.records[trace].APNSResponsesPrivate) != want || s.apnsCaptured != want || writes != want {
				t.Errorf("%s receipts=%d counter=%d writes=%d, want %d", mode, len(s.records[trace].APNSResponsesPrivate), s.apnsCaptured, writes, want)
			}
			if want == 0 && !bytes.Equal(before, receiptIntegrationDisk(t, s, trace)) {
				t.Error("budget refusal changed durable record")
			}
			hotfixAssertCallIndex(t, s)
			if mode == "owner_priority" || mode == "global_priority" {
				media := map[string]any{}
				_ = json.Unmarshal(diagnosticTestEvent(trace, "flutter", "media", "snapshot"), &media)
				media["outcome"] = "media_flow_verified"
				media["values"] = map[string]any{"mediaFlowVerified": true}
				if !s.appendEvent("isolated-caller", appJSON(media), false, 1) || !s.appendEvent("isolated-caller", diagnosticTestEvent(trace, "flutter", "terminal", "finish"), false, 1) {
					t.Error("receipt consumed causal headroom")
				}
				hotfixAssertCallIndex(t, s)
			}
		})
	}
}

func TestAPNSVoIPIntegrationWriteRepair(t *testing.T) {
	for _, mode := range []string{"before_publish", "after_publish", "pending_then_second_failure"} {
		t.Run(mode, func(t *testing.T) {
			s, ctx, trace := receiptTestContext(t)
			first := diagnosticTestEvent(trace, "flutter", "attempt", "start")
			if !s.appendEvent("isolated-caller", first, false, 1) {
				t.Fatal("seed")
			}
			before := receiptIntegrationDisk(t, s, trace)
			calls := 0
			s.write = func(path string, raw []byte) error {
				calls++
				if calls == 1 {
					if mode != "before_publish" {
						if err := appDiagnosticAtomicWrite(path, raw); err != nil {
							return err
						}
					}
					return errors.New("injected publication failure")
				}
				if mode == "pending_then_second_failure" {
					return errors.New("injected repair failure")
				}
				return appDiagnosticAtomicWrite(path, raw)
			}
			receiptIntegrationSend(t, s, ctx)
			if len(s.records[trace].APNSResponsesPrivate) != 0 || s.apnsCaptured != 0 {
				t.Fatal("failed receipt committed in memory")
			}
			hotfixAssertCallIndex(t, s)
			if mode == "pending_then_second_failure" {
				if s.pendingWrite == nil {
					t.Fatal("lost repair obligation")
				}
				if s.appendEventResult("isolated-caller", first, false, 1) != callDiagnosticAppendRetry {
					t.Fatal("duplicate ACK before durable repair")
				}
				calls = 0
				s.write = func(path string, raw []byte) error {
					calls++
					if err := appDiagnosticAtomicWrite(path, raw); err != nil {
						return err
					}
					if calls == 2 {
						return errors.New("second ambiguous publication failure after successful repair")
					}
					return nil
				}
				receiptIntegrationSend(t, s, ctx)
				if calls != 3 {
					t.Fatalf("expected repair, publication, rollback; calls=%d", calls)
				}
			}
			if s.pendingWrite != nil || !bytes.Equal(before, receiptIntegrationDisk(t, s, trace)) {
				t.Error("rollback did not restore last committed bytes")
			}
			if len(s.records[trace].APNSResponsesPrivate) != 0 || s.apnsCaptured != 0 {
				t.Error("failed receipt changed accounting")
			}
			hotfixAssertCallIndex(t, s)
			s.write = appDiagnosticAtomicWrite
			receiptIntegrationSend(t, s, ctx)
			if len(s.records[trace].APNSResponsesPrivate) != 1 || s.apnsCaptured != 1 {
				t.Fatal("capture did not recover exactly once")
			}
			if !bytes.Equal(mustDiagnosticJSON(s.records[trace]), receiptIntegrationDisk(t, s, trace)) {
				t.Fatal("durable receipt differs from memory")
			}
			hotfixAssertCallIndex(t, s)
		})
	}
}

func TestAPNSVoIPIntegrationInitPreservesBothPolicies(t *testing.T) {
	t.Setenv("CALL_DIAGNOSTICS_DIR", t.TempDir())
	t.Setenv("CALL_DIAGNOSTICS_OWNER_MAX_BYTES", "8388608")
	owner := diagnosticPrivateKey("isolated-caller")
	t.Setenv("APNS_VOIP_CAPTURE_OWNER_SHA256", owner)
	t.Setenv("APNS_VOIP_CAPTURE_UNTIL", time.Now().Add(time.Minute).UTC().Format(time.RFC3339))
	s := initCallDiagnosticsFromEnvironment()
	if s == nil {
		t.Fatal("init")
	}
	defer s.close()
	if s.ownerQuota != 8<<20 || s.apnsCapture.owner != owner || !s.apnsCapture.until.After(time.Now()) {
		t.Fatal("init merge lost an independent policy")
	}
}

func TestAPNSVoIPIntegrationReceiptLifecycle(t *testing.T) {
	s, ctx, trace := receiptTestContext(t)
	publicBefore := mustDiagnosticJSON(struct {
		Events    []callDiagnosticStoredEvent
		Summaries map[string]callDiagnosticStoredEvent
	}{s.records[trace].Events, s.records[trace].Summaries})
	for i := 0; i < apnsVoIPCaptureMaxResponses; i++ {
		receiptIntegrationSend(t, s, ctx)
	}
	if s.apnsCaptured != apnsVoIPCaptureMaxResponses {
		t.Fatal("normal capture cap")
	}
	publicAfter := mustDiagnosticJSON(struct {
		Events    []callDiagnosticStoredEvent
		Summaries map[string]callDiagnosticStoredEvent
	}{s.records[trace].Events, s.records[trace].Summaries})
	if !bytes.Equal(publicBefore, publicAfter) {
		t.Fatal("private receipts entered public Events/Summaries")
	}
	hotfixAssertCallIndex(t, s)
	// The process cap also applies to a fresh trace with no private receipts.
	d := callDiagnosticContext{TraceID: uuid.NewString()}
	if !s.prepare("isolated-caller", &d, 1) {
		t.Fatal("prepare second trace")
	}
	s.bindCommitted("isolated-caller", "isolated-callee", "second-private-handle", &d)
	s.flush()
	secondCtx := callDiagnosticWithContext(context.Background(), newCallDiagnosticSpan(s, "isolated-caller", d, "store"))
	receiptIntegrationSend(t, s, secondCtx)
	if len(s.records[d.TraceID].APNSResponsesPrivate) != 0 {
		t.Fatal("process response cap bypassed across traces")
	}
	// Reload reconstructs byte/reservation indexes from private receipt bytes.
	reloaded, err := newCallDiagnosticStore(s.dir, s.quota, s.now)
	if err != nil {
		t.Fatal(err)
	}
	defer reloaded.close()
	reloaded.apnsCapture = s.apnsCapture
	d = callDiagnosticContext{TraceID: trace}
	if !reloaded.prepare("isolated-caller", &d, 1) {
		t.Fatal("prepare retained trace")
	}
	reloadedCtx := callDiagnosticWithContext(context.Background(), newCallDiagnosticSpan(reloaded, "isolated-caller", d, "store"))
	before := receiptIntegrationDisk(t, reloaded, trace)
	receiptIntegrationSend(t, reloaded, reloadedCtx)
	if reloaded.apnsCaptured != 0 || len(reloaded.records[trace].APNSResponsesPrivate) != apnsVoIPCaptureMaxResponses || !bytes.Equal(before, receiptIntegrationDisk(t, reloaded, trace)) {
		t.Fatal("persisted per-record cap bypassed after restart")
	}
	hotfixAssertCallIndex(t, reloaded)
	if err := reloaded.clearActor("isolated-caller", 1); err != nil {
		t.Fatal(err)
	}
	receiptIntegrationSend(t, reloaded, reloadedCtx)
	if len(reloaded.records) != 0 || reloaded.usedBytes != 0 {
		t.Fatal("clear recreated private receipt or retained byte charge")
	}
	hotfixAssertCallIndex(t, reloaded)
	if _, err := os.Stat(filepath.Join(s.dir, trace+".json")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("receipt survived erase")
	}
}
