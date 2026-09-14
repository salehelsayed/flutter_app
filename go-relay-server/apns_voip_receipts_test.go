package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
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
