package main

import (
	"context"
	"net/http"
	"testing"
)

// Evidence-only composition probe: exact approved core and APNs production
// bytes, real FIFO worker/persistence, existing in-process provider transport.
func TestCompositionAPNSStaleContextAfterRecreation(t *testing.T) {
	for _, mode := range []string{"valid", "fresh_after_participant_clear", "stale_after_participant_clear", "stale_after_owner_clear"} {
		t.Run(mode, func(t *testing.T) {
			s, ctx, trace := receiptTestContext(t)
			if err := s.configure("isolated-callee", true, false, 1); err != nil {
				t.Fatal(err)
			}
			stale := callDiagnosticSpanFromContext(ctx).diagnostics
			if mode != "valid" {
				who := "isolated-callee"
				if mode == "stale_after_owner_clear" {
					who = "isolated-caller"
				}
				if err := s.clearActor(who, 1); err != nil {
					t.Fatal(err)
				}
				if s.records[trace] != nil {
					t.Fatal("clear did not remove original record")
				}
				fresh := publicationPrepare(t, s, "isolated-caller", trace)
				publicationEmit(s, "isolated-caller", fresh)
				s.flush()
				if s.records[trace] == nil {
					t.Fatal("fresh trace not persisted")
				}
				s.mu.Lock()
				staleAllowed := s.contextAuthorizedLocked("isolated-caller", &stale)
				freshAllowed := s.contextAuthorizedLocked("isolated-caller", &fresh)
				s.mu.Unlock()
				if staleAllowed || !freshAllowed {
					t.Fatal("core lifetime control failed")
				}
				if mode == "fresh_after_participant_clear" {
					ctx = callDiagnosticWithContext(context.Background(), newCallDiagnosticSpan(s, "isolated-caller", fresh, "store"))
				}
			}
			resume := queuedPrivacyHold(t, s)
			staleCase := mode == "stale_after_participant_clear" || mode == "stale_after_owner_clear"
			var unchanged func()
			if staleCase {
				unchanged = publicationObserve(t, s)
			}
			response, err := receiptTestSend(receiptTestProvider(http.Header{}, 200), ctx)
			if err != nil || response.StatusCode != 200 {
				t.Fatal("provider response changed")
			}
			resume()
			s.flush()
			want := 1
			if staleCase {
				want = 0
				unchanged()
			}
			if got := len(s.records[trace].APNSResponsesPrivate); got != want || s.apnsCaptured != want {
				t.Errorf("APNs capture across trace lifetime: receipts=%d captureCount=%d want=%d", got, s.apnsCaptured, want)
			}
			hotfixAssertCallIndex(t, s)
		})
	}
}
