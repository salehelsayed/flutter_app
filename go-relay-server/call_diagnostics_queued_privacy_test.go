package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
)

// The worker has entered a real FIFO job before the caller looks up an origin.
// Release is idempotent so failed setup assertions cannot deadlock store cleanup.
func queuedPrivacyHold(t *testing.T, s *callDiagnosticStore) func() {
	t.Helper()
	entered, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	resume := func() { once.Do(func() { close(release) }) }
	s.enqueueSource("span", func() { close(entered); <-release })
	<-entered
	t.Cleanup(resume)
	return resume
}

func queuedPrivacyRead(t *testing.T, path string) []byte {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func TestQueuedPrivacyOrigin(t *testing.T) {
	for _, mode := range []string{"valid", "clear", "clear_interrupted", "clear_recovered", "clear_private_interrupted", "disable", "disable_interrupted", "disable_reenabled", "epoch_changed", "recipient_clear", "recipient_clear_recovered", "recipient_disable_reenabled", "recipient_epoch_mutated"} {
		t.Run(mode, func(t *testing.T) {
			s := hotfixCall(t)
			if err := s.configure("reader", true, false, 1); err != nil {
				t.Fatal(err)
			}
			traceA := uuid.NewString()
			if !s.appendEvent("owner", diagnosticTestEvent(traceA, "flutter", "attempt", "start"), false, 1) {
				t.Fatal("seed author record")
			}
			author := callDiagnosticContext{OperationID: uuid.NewString(), Reason: "calls_disabled"}
			if !s.prepare("owner", &author, 1) {
				t.Fatal("prepare author")
			}
			s.authorityChange("owner", "target", &author, "endpoint")
			s.flush()
			if s.lastAuthority("target").OperationID != author.OperationID {
				t.Fatal("seed readable authority")
			}
			reader := callDiagnosticContext{TraceID: uuid.NewString(), OperationID: uuid.NewString()}
			if !s.prepare("reader", &reader, 1) {
				t.Fatal("prepare reader")
			}
			if s.authorizedLocked("reader", traceA) || s.authorizedLocked("owner", reader.TraceID) {
				t.Fatal("fixture must use unrelated records")
			}
			resume := queuedPrivacyHold(t, s)
			span := newCallDiagnosticSpan(s, "reader", reader, callEndpointGetAction)
			span.result(callControlWireRequest{Action: callEndpointGetAction, AccountPeerID: "target"}, callControlWireResponse{Status: "OK", Found: true}, nil)
			if span.diagnostics.ParentOperationID != author.OperationID {
				t.Fatal("lookup must copy A's origin before erasure")
			}
			// Cover every emit route, including a copied context and provider observations.
			copySpan := newCallDiagnosticSpan(s, "reader", span.diagnostics, callEndpointGetAction)
			copySpan.emit("push", "dispatch", "started", "none", map[string]any{"platform": "ios", "retry": 0, "providerInvoked": true})
			if mode == "clear_private_interrupted" {
				writer, privateWrites := s.write, 0
				s.write = func(path string, raw []byte) error {
					if filepath.Base(path) == "private.json" {
						privateWrites++
						if privateWrites == 2 {
							return fmt.Errorf("injected erase completion failure")
						}
					}
					return writer(path, raw)
				}
			}
			interrupted := mode == "clear_interrupted" || mode == "disable_interrupted" || mode == "clear_recovered"
			if interrupted {
				s.remove = func(string) error { return fmt.Errorf("injected removal failure") }
			}
			var err error
			switch mode {
			case "clear", "clear_interrupted", "clear_recovered", "clear_private_interrupted":
				err = s.clearActor("owner", 1)
			case "disable", "disable_interrupted", "disable_reenabled":
				err = s.configure("owner", false, false, 2)
			case "epoch_changed":
				err = s.configure("owner", true, false, 2)
			case "recipient_clear", "recipient_clear_recovered":
				err = s.clearActor("reader", 1)
			case "recipient_epoch_mutated":
				err = s.configure("reader", true, false, 2)
				span.diagnostics.consentEpoch = 2
				copySpan.diagnostics.consentEpoch = 2
			case "recipient_disable_reenabled":
				err = s.configure("reader", false, false, 2)
			}
			interrupted = interrupted || mode == "clear_private_interrupted"
			if (err != nil) != interrupted {
				t.Fatalf("transition error = %v, interrupted = %v", err, interrupted)
			}
			if interrupted && !s.state.Consent[diagnosticPrivateKey("owner")].ErasePending {
				t.Fatal("erasure must be pending")
			}
			if mode == "clear_recovered" {
				s.remove = os.Remove
				if err := s.clearActor("owner", 1); err != nil {
					t.Fatal(err)
				}
			}
			if mode == "disable_reenabled" {
				if err := s.configure("owner", true, false, 3); err != nil {
					t.Fatal(err)
				}
			}
			if mode == "recipient_disable_reenabled" {
				if err := s.configure("reader", true, false, 3); err != nil {
					t.Fatal(err)
				}
			}
			if mode == "recipient_clear_recovered" {
				if err := s.configure("reader", true, false, 1); err != nil {
					t.Fatal(err)
				}
			}
			writer := s.write
			var publications [][]byte
			s.write = func(path string, raw []byte) error {
				if filepath.Base(path) == reader.TraceID+".json" {
					if s.mu.TryLock() {
						s.mu.Unlock()
						t.Error("publication is not serialized with privacy transitions")
					}
					publications = append(publications, append([]byte(nil), raw...))
				}
				return writer(path, raw)
			}
			resume()
			s.flush()
			recipientDenied := mode == "recipient_clear" || mode == "recipient_clear_recovered" || mode == "recipient_disable_reenabled" || mode == "recipient_epoch_mutated"
			if recipientDenied {
				if len(publications) != 0 {
					t.Error("stale recipient published bytes")
				}
				if _, err := os.Stat(filepath.Join(s.dir, reader.TraceID+".json")); !os.IsNotExist(err) {
					t.Error("stale recipient job persisted after privacy transition")
				}
				if s.records[reader.TraceID] != nil {
					t.Error("stale recipient job is publicly readable")
				}
			} else {
				rec := s.records[reader.TraceID]
				if rec == nil || len(rec.Events) != 3 {
					t.Fatalf("recipient diagnostics lost: %+v", rec)
				}
				persisted := queuedPrivacyRead(t, filepath.Join(s.dir, reader.TraceID+".json"))
				for _, raw := range append(publications, persisted, appJSON(rec.Events)) {
					has := bytes.Contains(raw, []byte(author.OperationID))
					if has != (mode == "valid") {
						t.Errorf("queued author ID publication = %v after %s", has, mode)
					}
					if !bytes.Contains(raw, []byte(reader.OperationID)) {
						t.Error("recipient's own operation lost")
					}
					if bytes.Contains(raw, []byte(diagnosticPrivateKey("owner"))) {
						t.Error("private author provenance leaked to recipient")
					}
				}
				for _, event := range rec.Events {
					if bytes.Contains(event.Event, []byte(author.OperationID)) != (mode == "valid") {
						t.Error("emit route failed origin fence")
					}
				}
			}
			if mode != "valid" && mode != "epoch_changed" && !recipientDenied && s.lastAuthority("target").OperationID != "" {
				t.Error("erased authority remains readable")
			}
			s.remove = os.Remove
			hotfixAssertCallIndex(t, s)
		})
	}
}

func TestQueuedPrivacyAuthority(t *testing.T) {
	for _, mode := range []string{"valid_trace", "trace_less", "expired_failed_removal", "expired_removed", "clear_recovered", "disable_reenabled", "epoch_changed", "epoch_mutated", "expired_context_mutated", "mutable_context"} {
		t.Run(mode, func(t *testing.T) {
			s := hotfixCall(t)
			now := time.Now()
			s.now = func() time.Time { return now }
			d := callDiagnosticContext{TraceID: uuid.NewString(), OperationID: uuid.NewString(), Reason: "calls_disabled"}
			if mode == "trace_less" {
				d.TraceID = ""
			} else if !s.appendEvent("owner", diagnosticTestEvent(d.TraceID, "flutter", "attempt", "start"), false, 1) {
				t.Fatal("seed")
			}
			if !s.prepare("owner", &d, 1) {
				t.Fatal("prepare")
			}
			original := d
			resume := queuedPrivacyHold(t, s)
			s.authorityChange("owner", "queued-target", &d, "endpoint")
			if mode == "expired_failed_removal" || mode == "expired_removed" || mode == "expired_context_mutated" {
				now = now.Add(callDiagnosticRetention + time.Millisecond)
				if err := s.configure("owner", true, false, 1); err != nil {
					t.Fatal(err)
				}
				if mode == "expired_failed_removal" || mode == "expired_context_mutated" {
					s.remove = func(string) error { return fmt.Errorf("injected expiry failure") }
				}
				s.mu.Lock()
				s.expireLocked()
				s.mu.Unlock()
				if s.authorizedLocked("owner", d.TraceID) {
					t.Fatal("expiry must revoke trace authority")
				}
			}
			switch mode {
			case "clear_recovered":
				if err := s.clearActor("owner", 1); err != nil {
					t.Fatal(err)
				}
			case "disable_reenabled":
				if err := s.configure("owner", false, false, 2); err != nil {
					t.Fatal(err)
				}
				if err := s.configure("owner", true, false, 3); err != nil {
					t.Fatal(err)
				}
			case "epoch_changed":
				if err := s.configure("owner", true, false, 2); err != nil {
					t.Fatal(err)
				}
			case "epoch_mutated":
				if err := s.configure("owner", true, false, 2); err != nil {
					t.Fatal(err)
				}
				d.consentEpoch = 2
			case "expired_context_mutated":
				d.TraceID = ""
			case "mutable_context":
				d.OperationID = uuid.NewString()
				d.TraceID = ""
				d.Reason = "none"
			}
			before := queuedPrivacyRead(t, filepath.Join(s.dir, "private.json"))
			writes := 0
			writer := s.write
			s.write = func(path string, raw []byte) error {
				if filepath.Base(path) == "private.json" {
					writes++
					if s.mu.TryLock() {
						s.mu.Unlock()
						t.Error("authority write is not serialized with privacy transitions")
					}
				}
				return writer(path, raw)
			}
			resume()
			s.flush()
			after := queuedPrivacyRead(t, filepath.Join(s.dir, "private.json"))
			valid := mode == "valid_trace" || mode == "trace_less" || mode == "mutable_context"
			change := s.lastAuthority("queued-target")
			if valid {
				if change.OperationID != original.OperationID || !bytes.Contains(after, []byte(original.OperationID)) || writes != 1 {
					t.Error("valid captured authority not durably published")
				}
				if mode == "mutable_context" && bytes.Contains(after, []byte(d.OperationID)) {
					t.Error("queued context mutation changed persisted authority")
				}
			} else {
				if change.OperationID != "" {
					t.Error("invalid queued authority is readable")
				}
				if !bytes.Equal(before, after) || writes != 0 || bytes.Contains(after, []byte(original.OperationID)) {
					t.Error("invalid queued authority wrote private authority file")
				}
				if _, exists := s.state.Authority[diagnosticPrivateKey("queued-target", "endpoint")]; exists {
					t.Error("invalid queued authority in private state")
				}
			}
			s.remove = os.Remove
			hotfixAssertCallIndex(t, s)
		})
	}
}
