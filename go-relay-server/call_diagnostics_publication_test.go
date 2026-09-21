package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/google/uuid"
)

// Observe actual writes as well as final bytes: a write followed by rollback is
// still publication. Install only while the FIFO worker is held at its barrier.
func publicationObserve(t *testing.T, s *callDiagnosticStore) func() {
	t.Helper()
	snapshot := func() map[string]string {
		files, err := os.ReadDir(s.dir)
		if err != nil {
			t.Fatal(err)
		}
		result := map[string]string{}
		for _, f := range files {
			result[f.Name()] = string(queuedPrivacyRead(t, filepath.Join(s.dir, f.Name())))
		}
		result["memory records"] = string(appJSON(s.records))
		result["memory privacy and authority"] = string(appJSON(s.state))
		return result
	}
	before := snapshot()
	writer, writes := s.write, 0
	s.write = func(path string, raw []byte) error {
		writes++
		return writer(path, raw)
	}
	return func() {
		t.Helper()
		s.write = writer
		if writes != 0 || !reflect.DeepEqual(before, snapshot()) {
			t.Errorf("stale queue published: writes=%d; record/privacy/authority bytes changed=%v", writes, !reflect.DeepEqual(before, snapshot()))
		}
		hotfixAssertCallIndex(t, s)
	}
}

func publicationPrepare(t *testing.T, s *callDiagnosticStore, actor, trace string) callDiagnosticContext {
	t.Helper()
	d := callDiagnosticContext{TraceID: trace, OperationID: uuid.NewString(), Reason: "calls_disabled"}
	if !s.prepare(actor, &d, 1) {
		t.Fatal("prepare publication")
	}
	return d
}

func publicationEmit(s *callDiagnosticStore, actor string, d callDiagnosticContext) {
	newCallDiagnosticSpan(s, actor, d, callStoreAction).emit("signaling", "commit", "ok", "none", map[string]any{"storeCommitted": true, "eventCount": 1})
}

func TestPublicationSpanBeforeAuthorityExpiry(t *testing.T) {
	for _, actor := range []string{"owner", "participant"} {
		for _, mode := range []string{"exact_ttl", "removed", "failed_removal", "new_metadata", "new_record"} {
			t.Run(actor+"/"+mode, func(t *testing.T) {
				s := hotfixCall(t)
				now := time.Now()
				s.now = func() time.Time { return now }
				if err := s.configure("participant", true, false, 1); err != nil {
					t.Fatal(err)
				}
				trace := uuid.NewString()
				if !s.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
					t.Fatal("seed record")
				}
				owner := publicationPrepare(t, s, "owner", trace)
				s.bindCommitted("owner", "participant", "old-handle", &owner)
				s.flush()
				d := publicationPrepare(t, s, actor, trace)
				resume := queuedPrivacyHold(t, s)
				publicationEmit(s, actor, d) // Must precede authority on the real FIFO.
				s.authorityChange(actor, "target", &d, "endpoint")
				now = now.Add(callDiagnosticRetention)
				if mode != "exact_ttl" {
					now = now.Add(time.Millisecond)
				}
				// Renew at the same epoch before cleanup, preserving actor generation.
				for _, who := range []string{"owner", "participant"} {
					if err := s.configure(who, true, false, 1); err != nil {
						t.Fatal(err)
					}
				}
				if mode == "failed_removal" {
					s.remove = func(string) error { return fmt.Errorf("injected expiry removal failure") }
				}
				s.mu.Lock()
				s.expireLocked()
				s.mu.Unlock()
				if mode == "removed" || mode == "new_metadata" || mode == "new_record" {
					if s.records[trace] != nil || s.metadata[trace] != nil {
						t.Fatal("successful expiry must remove record and metadata")
					}
					if _, err := os.Stat(filepath.Join(s.dir, trace+".json")); !os.IsNotExist(err) {
						t.Fatal("successful expiry must remove persisted record")
					}
				}
				if mode == "new_metadata" || mode == "new_record" {
					publicationPrepare(t, s, actor, trace)
					if mode == "new_record" && !s.appendEvent(actor, diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
						t.Fatal("fresh upload must be allowed")
					}
				}
				if mode == "exact_ttl" {
					resume()
					s.flush()
					if len(s.records[trace].Events) != 2 || s.records[trace].Owner != diagnosticPrivateKey("owner") || s.lastAuthority("target").OperationID != d.OperationID {
						t.Fatal("exact TTL must publish with original ownership")
					}
				} else {
					unchanged := publicationObserve(t, s)
					resume()
					s.flush()
					unchanged()
					if s.lastAuthority("target").OperationID != "" {
						t.Error("stale authority became readable")
					}
				}
				s.remove = os.Remove
				s.mu.Lock()
				s.expireLocked()
				s.mu.Unlock()
				// Fresh contexts can publish even when reusing the removed trace ID.
				fresh := publicationPrepare(t, s, actor, trace)
				publicationEmit(s, actor, fresh)
				s.authorityChange(actor, "fresh-target", &fresh, "endpoint")
				s.flush()
				if s.records[trace] == nil || s.lastAuthority("fresh-target").OperationID != fresh.OperationID {
					t.Fatal("fresh publication denied")
				}
				hotfixAssertCallIndex(t, s)
			})
		}
	}
}

func TestPublicationBindingThroughStore(t *testing.T) {
	for _, mode := range []string{"valid", "first", "mutated", "clear", "clear_reenabled", "clear_failed", "clear_recovered", "participant_clear", "participant_recreated", "expired", "expired_recreated"} {
		t.Run(mode, func(t *testing.T) {
			now := time.Now()
			service, _ := callTestService(t, now, nil)
			actor, recipient := callTestPeerID(t), callTestPeerID(t)
			authorizeCallFixture(t, service, now, actor, recipient)
			s := diagnosticTestStore(t)
			s.now = func() time.Time { return now }
			for _, who := range []string{actor, recipient} {
				if err := s.configure(who, true, false, 1); err != nil {
					t.Fatal(err)
				}
			}
			trace := uuid.NewString()
			if mode != "first" && !s.appendEvent(actor, diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
				t.Fatal("seed binding record")
			}
			d := publicationPrepare(t, s, actor, trace)
			span := newCallDiagnosticSpan(s, actor, d, callStoreAction)
			resume := queuedPrivacyHold(t, s)
			request := CallStoreRequest{RecipientDevicePeerID: recipient, CallHandle: callTestHandleA, MessageID: callTestMessageA, Envelope: []byte("encrypted-publication-fixture"), ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake}
			receipt, err := service.Store(callDiagnosticWithContext(context.Background(), span), actor, request)
			if err != nil || receipt.StoreStatus != CallStoreStatusStored {
				t.Fatalf("business Store = %+v, %v", receipt, err)
			}
			s.authorityChange(actor, "binding-target", &span.diagnostics, "endpoint")
			valid := mode == "valid" || mode == "first" || mode == "mutated"
			if mode == "mutated" {
				span.diagnostics.TraceID = uuid.NewString()
				span.diagnostics.OperationID = uuid.NewString()
			} else if !valid {
				if mode == "expired" || mode == "expired_recreated" {
					now = now.Add(callDiagnosticRetention + time.Millisecond)
					if err := s.configure(actor, true, false, 1); err != nil {
						t.Fatal(err)
					}
					s.mu.Lock()
					s.expireLocked()
					s.mu.Unlock()
				} else {
					who := actor
					if mode == "participant_clear" || mode == "participant_recreated" {
						who = recipient
					}
					failed := mode == "clear_failed" || mode == "clear_recovered"
					if failed {
						s.remove = func(string) error { return fmt.Errorf("injected clear removal failure") }
					}
					if err := s.clearActor(who, 1); (err != nil) != failed {
						t.Fatalf("clear = %v, expected failure = %v", err, failed)
					}
					if mode == "clear_reenabled" || mode == "clear_recovered" {
						s.remove = os.Remove
						if err := s.configure(who, true, false, 1); err != nil {
							t.Fatal(err)
						}
					}
				}
				if mode == "participant_recreated" || mode == "expired_recreated" {
					publicationPrepare(t, s, actor, trace)
					if !s.appendEvent(actor, diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
						t.Fatal("fresh record")
					}
				}
			}
			var unchanged func()
			if !valid {
				unchanged = publicationObserve(t, s)
			}
			resume()
			s.flush()
			if !valid {
				unchanged()
				if s.lastAuthority("binding-target").OperationID != "" {
					t.Error("stale binding authority published")
				}
			} else {
				r := s.records[trace]
				if r == nil || r.Owner != diagnosticPrivateKey(actor) || r.HandleDigest != diagnosticPrivateKey(request.CallHandle) || !diagnosticContains(r.Participants, diagnosticPrivateKey(recipient)) || s.resolve(recipient, request.CallHandle) != trace {
					t.Fatal("valid captured binding lost or ownership changed")
				}
				if !bytes.Contains(queuedPrivacyRead(t, filepath.Join(s.dir, trace+".json")), []byte(d.OperationID)) || s.lastAuthority("binding-target").OperationID != d.OperationID {
					t.Fatal("valid captured diagnostics lost")
				}
				if mode == "mutated" && s.records[span.diagnostics.TraceID] != nil {
					t.Error("mutated context redirected binding")
				}
			}
			// The actual mailbox commit survives diagnostic rejection, including
			// the same exact idempotent business result after the queue drains.
			duplicate, err := service.Store(context.Background(), actor, request)
			if err != nil || duplicate.StoreStatus != CallStoreStatusDuplicate {
				t.Fatalf("business commit lost: %+v, %v", duplicate, err)
			}
			s.remove = os.Remove
			hotfixAssertCallIndex(t, s)
		})
	}
}

func TestPublicationStaleContextAfterRecreation(t *testing.T) {
	for _, mode := range []string{"same_trace", "other_trace", "trace_removed"} {
		t.Run(mode, func(t *testing.T) {
			s := hotfixCall(t)
			if err := s.configure("participant", true, false, 1); err != nil {
				t.Fatal(err)
			}
			trace := uuid.NewString()
			d := publicationPrepare(t, s, "owner", trace)
			s.bindCommitted("owner", "participant", "old-handle", &d)
			s.flush()
			if err := s.clearActor("participant", 1); err != nil {
				t.Fatal(err)
			}
			// The owner's consent is unchanged. Another operation recreates the
			// same ID; neither the old context nor a modified copy regains access.
			fresh := publicationPrepare(t, s, "owner", trace)
			publicationEmit(s, "owner", fresh)
			s.flush()
			stale := d
			if mode == "other_trace" {
				stale.TraceID = uuid.NewString()
				publicationPrepare(t, s, "owner", stale.TraceID)
			} else if mode == "trace_removed" {
				stale.TraceID = ""
			}
			resume := queuedPrivacyHold(t, s)
			unchanged := publicationObserve(t, s)
			s.bindCommitted("owner", "new-recipient", "new-handle", &stale)
			publicationEmit(s, "owner", stale)
			s.authorityChange("owner", "stale-target", &stale, "endpoint")
			resume()
			s.flush()
			unchanged()
			if s.resolve("owner", "new-handle") != "" {
				t.Error("stale context regained immediate binding authority")
			}
		})
	}
}

func TestPublicationParticipantBindingFirstWrite(t *testing.T) {
	s := hotfixCall(t)
	if err := s.configure("participant", true, false, 1); err != nil {
		t.Fatal(err)
	}
	trace := uuid.NewString()
	d := publicationPrepare(t, s, "owner", trace)
	resume := queuedPrivacyHold(t, s)
	s.bindCommitted("owner", "participant", "handle", &d)
	p := publicationPrepare(t, s, "participant", trace)
	s.bindCommitted("participant", "owner", "handle", &p)
	publicationEmit(s, "participant", p)
	s.authorityChange("participant", "target", &p, "endpoint")
	resume()
	s.flush()
	r := s.records[trace]
	if r == nil || r.Owner != diagnosticPrivateKey("owner") || len(r.Events) != 1 || s.ownerSizes[diagnosticPrivateKey("participant")] != 0 || s.ownerSizes[diagnosticPrivateKey("owner")] == 0 || s.lastAuthority("target").OperationID != p.OperationID {
		t.Fatal("participant first publication lost original ownership/accounting or authority")
	}
	hotfixAssertCallIndex(t, s)
}
