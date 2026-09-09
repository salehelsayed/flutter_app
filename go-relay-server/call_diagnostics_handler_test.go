package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/libp2p/go-libp2p/core/network"
)

type diagnosticTestWakeDispatcher struct {
	err      error
	payloads []CallWakePayload
}

func (d *diagnosticTestWakeDispatcher) DispatchCallWake(ctx context.Context, route CallWakeRoute, payload CallWakePayload) error {
	d.payloads = append(d.payloads, payload)
	callDiagnosticProvider(ctx, "ios", 0, true, nil)
	callDiagnosticProvider(ctx, "ios", 0, false, d.err)
	return d.err
}
func diagnosticWrappedRequest(trace string, request map[string]any) map[string]any {
	return map[string]any{"action": callDiagnosticsAction, "op": "request", "consentEpoch": int64(1), "diagnostics": map[string]any{"traceId": trace, "requestId": uuid.NewString()}, "request": request}
}
func TestCallDiagnosticsCommittedStoreProviderFailureAndPrivacy(t *testing.T) {
	now := time.Now()
	dispatcher := &diagnosticTestWakeDispatcher{err: errors.New("private provider IP or token")}
	service, _ := callTestService(t, now, dispatcher)
	store := diagnosticTestStore(t)
	service.diagnostics = store
	fixture := newCallHandlerFixture(t, service)
	sender, recipient := fixture.client.ID().String(), fixture.recipient.ID().String()
	authorizeCallFixture(t, service, now, sender, recipient)
	_ = store.configure(sender, true, false, 1)
	_ = store.configure(recipient, true, true, 1)
	trace := uuid.NewString()
	response := callHandlerRoundTrip(t, fixture, fixture.client, diagnosticWrappedRequest(trace, map[string]any{"action": callStoreAction, "to": recipient, "callHandle": callTestHandleA, "messageId": callTestMessageA, "envelope": "private-ciphertext", "expiresAtMs": now.Add(40 * time.Second).UnixMilli(), "wakeHandle": callTestWake, "wakeReceipt": true}))
	if response["status"] != "OK" || response["storeStatus"] != "stored" || response["wake"] != "failed" {
		t.Fatal("diagnostics changed committed store semantics")
	}
	store.flush()
	if len(dispatcher.payloads) != 1 || dispatcher.payloads[0].Diagnostics == nil || dispatcher.payloads[0].Diagnostics.TraceID != trace {
		t.Fatal("consenting recipient trace unavailable at provider entry")
	}
	if store.resolve(recipient, callTestHandleA) != trace {
		t.Fatal("participant binding missing")
	}
	seen := map[string]bool{}
	for _, row := range store.records[trace].Events {
		var event map[string]any
		_ = json.Unmarshal(row.Event, &event)
		seen[event["stage"].(string)+"/"+event["action"].(string)+"/"+event["outcome"].(string)] = true
		for _, secret := range []string{sender, recipient, callTestHandleA, callTestMessageA, callTestWake, "private-ciphertext", "private provider"} {
			if strings.Contains(string(row.Event), secret) {
				t.Fatal("diagnostic event privacy leak")
			}
		}
	}
	for _, key := range []string{"signaling/commit/ok", "push/dispatch/started", "push/dispatch/failed", "push/finish/failed", "signaling/response/ok"} {
		if !seen[key] {
			t.Fatalf("missing causal phase %s", key)
		}
	}
}
func TestCallDiagnosticsUnavailableDiskCannotDelayBusinessCall(t *testing.T) {
	now := time.Now()
	service, _ := callTestService(t, now, nil)
	store := diagnosticTestStore(t)
	service.diagnostics = store
	fixture := newCallHandlerFixture(t, service)
	actor := fixture.client.ID().String()
	_ = store.configure(actor, true, false, 1)
	// Simulate a blocked diagnostic disk worker. Authentication metadata and the
	// existing endpoint operation must remain independent of the persistence lock.
	store.mu.Lock()
	response := callHandlerRoundTrip(t, fixture, fixture.client, diagnosticWrappedRequest(uuid.NewString(), map[string]any{"action": callEndpointGetAction, "accountPeerId": actor}))
	store.mu.Unlock()
	if response["status"] != "OK" {
		t.Fatal("diagnostic lock altered lookup")
	}
	store.flush()
}

type diagnosticWriteFailStream struct{ network.Stream }

func (s *diagnosticWriteFailStream) Write([]byte) (int, error) {
	return 0, errors.New("private write failure")
}
func TestCallDiagnosticsResponseWriteFailureIsDistinct(t *testing.T) {
	store := diagnosticTestStore(t)
	_ = store.configure("actor", true, false, 1)
	d := callDiagnosticContext{TraceID: uuid.NewString()}
	if !store.prepare("actor", &d) {
		t.Fatal("prepare")
	}
	span := newCallDiagnosticSpan(store, "actor", d, callCancelAction)
	response := callControlWireResponse{Status: "OK", Canceled: true}
	err := writeCallControlResponse(&diagnosticWriteFailStream{}, response)
	if err == nil {
		t.Fatal("missing write failure")
	}
	span.result(callControlWireRequest{Action: callCancelAction}, response, err)
	store.flush()
	seen := false
	for _, row := range store.records[d.TraceID].Events {
		var e map[string]any
		_ = json.Unmarshal(row.Event, &e)
		if e["action"] == "response" && e["reason"] == "write_failed" {
			seen = true
		}
	}
	if !seen {
		t.Fatal("reply write failure not retained")
	}
}
func TestCallDiagnosticsClearEpochRejectsOldUploadsAfterReenable(t *testing.T) {
	s := diagnosticTestStore(t)
	_ = s.configure("actor", true, true, 10)
	trace := uuid.NewString()
	event := diagnosticTestEvent(trace, "flutter", "attempt", "start")
	if !s.appendEvent("actor", event, false, 10) {
		t.Fatal("upload")
	}
	if s.clearActor("actor", 11) != nil || !s.enabled("actor") {
		t.Fatal("clear changed consent")
	}
	if s.appendEvent("actor", event, false, 10) {
		t.Fatal("old upload repopulated cleared records")
	}
	if s.configure("actor", true, true, 11) != nil {
		t.Fatal("same-epoch identical configure")
	}
	if !s.appendEvent("actor", event, false, 11) {
		t.Fatal("new consent epoch upload failed")
	}
	if s.configure("actor", false, false, 12) != nil || s.records[trace] != nil {
		t.Fatal("disable did not purge")
	}
	if s.configure("actor", true, true, 11) == nil {
		t.Fatal("stale enable accepted")
	}
}
func TestCallDiagnosticsOuterErrorsCannotMutateStrictLegacyEnvelope(t *testing.T) {
	now := time.Now()
	service, _ := callTestService(t, now, nil)
	fixture := newCallHandlerFixture(t, service)
	response := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{"action": callDiagnosticsAction, "op": "request", "consentEpoch": int64(1), "diagnostics": map[string]any{"traceId": "invalid", "rawSecret": "discard"}, "request": map[string]any{"action": callEndpointGetAction, "accountPeerId": fixture.client.ID().String()}})
	if response["status"] != "OK" {
		t.Fatal("invalid optional metadata blocked call")
	}
	response = callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{"action": callEndpointGetAction, "accountPeerId": fixture.client.ID().String(), "diagnostics": map[string]any{"traceId": uuid.NewString()}})
	if response["errorCode"] != "CALL_INVALID_REQUEST" {
		t.Fatal("strict v1 wire decoder changed")
	}
}

func TestCallDiagnosticsUploadTransientFailureIsNotTerminalRejection(t *testing.T) {
	now := time.Now()
	service, _ := callTestService(t, now, nil)
	store := diagnosticTestStore(t)
	service.diagnostics = store
	fixture := newCallHandlerFixture(t, service)
	actor := fixture.client.ID().String()
	_ = store.configure(actor, true, false, 1)
	trace := uuid.NewString()
	event := diagnosticTestEvent(trace, "flutter", "attempt", "start")
	old := store.dir
	store.dir = old + "/missing"
	response := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{"action": callDiagnosticsAction, "op": "upload", "consentEpoch": 1, "events": []json.RawMessage{event}})
	store.dir = old
	data := response["data"].(map[string]any)
	if len(data["acceptedEventIds"].([]any)) != 0 || len(data["rejectedEventIds"].([]any)) != 0 || data["reason"] != "sink_unavailable" {
		t.Fatal("transient disk failure discarded client event")
	}
	response = callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{"action": callDiagnosticsAction, "op": "upload", "consentEpoch": 1, "events": []json.RawMessage{event}})
	data = response["data"].(map[string]any)
	if len(data["acceptedEventIds"].([]any)) != 1 {
		t.Fatal("retry did not durably ACK event")
	}
}

func TestCallDiagnosticsUploadTraceCapacityIsPermanentButSinkFailureRetries(t *testing.T) {
	service, _ := callTestService(t, time.Now(), nil)
	store := diagnosticTestStore(t)
	service.diagnostics = store
	fixture := newCallHandlerFixture(t, service)
	actor := fixture.client.ID().String()
	_ = store.configure(actor, true, false, 1)
	trace := uuid.NewString()
	var overflow json.RawMessage
	for i := 0; i <= callDiagnosticTraceEvents; i++ {
		overflow = diagnosticTestEvent(trace, "flutter", "signaling", "snapshot")
		if !store.appendEvent(actor, overflow, false, 1) {
			break
		}
	}
	dropped := store.records[trace].Dropped
	request := map[string]any{"action": callDiagnosticsAction, "op": "upload", "consentEpoch": 1, "events": []json.RawMessage{overflow}}
	for i := 0; i < 2; i++ {
		response := callHandlerRoundTrip(t, fixture, fixture.client, request)
		data := response["data"].(map[string]any)
		if len(data["acceptedEventIds"].([]any)) != 0 || len(data["rejectedEventIds"].([]any)) != 1 || data["reason"] != "quota_exceeded" || store.records[trace].Dropped != dropped {
			t.Fatal("permanent trace overflow must advance the client queue without retry inflation")
		}
	}
	terminal := diagnosticTestEvent(trace, "flutter", "terminal", "finish")
	request["events"] = []json.RawMessage{terminal}
	quota := store.quota
	store.quota = 1
	response := callHandlerRoundTrip(t, fixture, fixture.client, request)
	store.quota = quota
	data := response["data"].(map[string]any)
	if len(data["acceptedEventIds"].([]any)) != 0 || len(data["rejectedEventIds"].([]any)) != 0 || data["reason"] != "sink_unavailable" {
		t.Fatal("global quota must remain retryable and preserve terminal evidence")
	}
	response = callHandlerRoundTrip(t, fixture, fixture.client, request)
	data = response["data"].(map[string]any)
	if len(data["acceptedEventIds"].([]any)) != 1 || len(data["rejectedEventIds"].([]any)) != 0 {
		t.Fatal("terminal evidence did not survive the full ordinary event budget")
	}
}
func TestCallDiagnosticsDelayedOuterEpochCannotRepopulateClear(t *testing.T) {
	now := time.Now()
	service, _ := callTestService(t, now, nil)
	store := diagnosticTestStore(t)
	service.diagnostics = store
	fixture := newCallHandlerFixture(t, service)
	actor := fixture.client.ID().String()
	_ = store.configure(actor, true, false, 1)
	_ = store.clearActor(actor, 2)
	request := diagnosticWrappedRequest(uuid.NewString(), map[string]any{"action": callEndpointGetAction, "accountPeerId": actor})
	response := callHandlerRoundTrip(t, fixture, fixture.client, request)
	store.flush()
	if response["status"] != "OK" || len(store.records) != 0 {
		t.Fatal("old outer diagnostic epoch recreated cleared trace or affected call")
	}
}
func TestCallDiagnosticsTraceCannotEnrollSecondCallOrThirdParticipant(t *testing.T) {
	s := diagnosticTestStore(t)
	_ = s.configure("caller", true, false, 1)
	_ = s.configure("callee", true, true, 1)
	_ = s.configure("third", true, true, 1)
	d := &callDiagnosticContext{TraceID: uuid.NewString()}
	if !s.prepare("caller", d) {
		t.Fatal("prepare")
	}
	s.bindCommitted("caller", "callee", "first-handle", d)
	s.flush()
	s.bindCommitted("caller", "third", "second-handle", d)
	s.flush()
	if s.resolve("third", "second-handle") != "" || s.resolve("caller", "second-handle") != "" || s.resolve("callee", "first-handle") != d.TraceID {
		t.Fatal("trace binding crossed admitted call/participant boundary")
	}
}

func TestCallDiagnosticsServerConsumesSharedDartCauseFixtures(t *testing.T) {
	raw, err := os.ReadFile("../tool/call_diagnostics/wire_fixtures_v1.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Contexts map[string]json.RawMessage `json:"contexts"`
	}
	_ = json.Unmarshal(raw, &fixture)
	s := diagnosticTestStore(t)
	_ = s.configure("actor", true, false, 1)
	for name, ctx := range fixture.Contexts {
		t.Run(name, func(t *testing.T) {
			var d callDiagnosticContext
			if diagnosticDecode(ctx, &d) != nil || !d.valid() || d.Reason == "" {
				t.Fatal("exact Dart wire cause rejected")
			}
			if !s.prepare("actor", &d, 1) {
				t.Fatal("prepare")
			}
			span := newCallDiagnosticSpan(s, "actor", d, callEndpointRevokeAction)
			span.emit("authority", "revoke", "ok", d.Reason, nil)
			s.flush()
		})
	}
	found := false
	for _, r := range s.records {
		for _, row := range r.Events {
			var e map[string]any
			_ = json.Unmarshal(row.Event, &e)
			if e["reason"] == "calls_disabled" {
				found = true
			}
			if e["cause"] != nil {
				t.Fatal("wire cause leaked into closed event schema")
			}
		}
	}
	if !found {
		t.Fatal("causal origin did not become event reason")
	}
}

func TestCallDiagnosticsClearErasesPrivateAuthorityOriginsAndMigratesOrphans(t *testing.T) {
	dir := t.TempDir()
	s, err := newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	_ = s.configure("actor", true, false, 1)
	d := &callDiagnosticContext{OperationID: uuid.NewString(), Reason: "calls_disabled"}
	if !s.prepare("actor", d, 1) {
		t.Fatal("prepare")
	}
	s.authorityChange("actor", "private-account", d, "endpoint")
	s.flush()
	if s.lastAuthority("private-account").OperationID != d.OperationID {
		t.Fatal("authority origin missing")
	}
	if s.clearActor("actor", 2) != nil || s.lastAuthority("private-account").OperationID != "" {
		t.Fatal("clear retained private origin")
	}
	raw, err := os.ReadFile(dir + "/private.json")
	if err != nil || strings.Contains(string(raw), d.OperationID) {
		t.Fatal("clear did not durably erase origin")
	}
	s.close()
	// An older build's diagnostic-only map lacks authorDigest; dropping it on
	// load is safe and cannot affect actual Redis call authority.
	var state map[string]any
	_ = json.Unmarshal(raw, &state)
	state["authority"] = map[string]any{"orphan": map[string]any{"operationId": d.OperationID, "atMs": time.Now().UnixMilli(), "reason": "calls_disabled"}}
	raw, _ = json.Marshal(state)
	if os.WriteFile(dir+"/private.json", raw, 0600) != nil {
		t.Fatal("fixture write")
	}
	s, err = newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer s.close()
	if len(s.state.Authority) != 0 {
		t.Fatal("orphan diagnostic origins retained")
	}
	raw, _ = os.ReadFile(dir + "/private.json")
	if strings.Contains(string(raw), d.OperationID) {
		t.Fatal("orphan migration was not durable")
	}
}

func TestCallDiagnosticsLegacyTokenRegistrationInvalidatesOnlyEffectivePushCapability(t *testing.T) {
	now := time.Now()
	service, _ := callTestService(t, now, nil)
	store := diagnosticTestStore(t)
	service.diagnostics = store
	fixture := newCallHandlerFixture(t, service)
	caller, callee := fixture.client.ID().String(), fixture.recipient.ID().String()
	_ = store.configure(caller, true, false, 1)
	_ = store.configure(callee, true, true, 1)
	d := &callDiagnosticContext{TraceID: uuid.NewString()}
	if !store.prepare(caller, d, 1) {
		t.Fatal("prepare")
	}
	store.bindCommitted(caller, callee, callTestHandleA, d)
	store.flush()
	if store.pushTrace(callee, callTestHandleA) == nil {
		t.Fatal("current capable recipient missing sidecar")
	}
	token := map[string]any{"action": callTokenSetAction, "tokenKind": string(CallTokenKindStandard), "platform": "android", "token": "private-token", "expiresAtMs": now.Add(time.Hour).UnixMilli()}
	response := callHandlerRoundTrip(t, fixture, fixture.recipient, token)
	if response["status"] != "OK" || store.pushTrace(callee, callTestHandleA) != nil {
		t.Fatal("legacy registration retained incompatible sidecar")
	}
	consent := store.state.Consent[diagnosticPrivateKey(callee)]
	if !consent.Enabled || !consent.PushTrace || consent.ConsentEpoch != 1 {
		t.Fatal("legacy registration changed desired consent")
	}
	if store.configure(callee, true, true, 1) != nil || store.pushTrace(callee, callTestHandleA) == nil {
		t.Fatal("same epoch current configure failed to restore capability")
	}
	response = callHandlerRoundTrip(t, fixture, fixture.recipient, diagnosticWrappedRequest(d.TraceID, token))
	if response["status"] != "OK" || store.pushTrace(callee, callTestHandleA) == nil {
		t.Fatal("negotiated current registration invalidated capability")
	}
	store.flush()
}
func TestCallDiagnosticsLateConfigureCannotUndoNewerLegacyRegistration(t *testing.T) {
	s := diagnosticTestStore(t)
	_ = s.configure("actor", true, true, 1)
	entered, release, done := make(chan struct{}), make(chan struct{}), make(chan struct{})
	s.beforeConfigurePublish = func() { close(entered); <-release }
	go func() { _ = s.configure("actor", true, true, 1); close(done) }()
	<-entered
	s.invalidateLegacyPushCapability("actor")
	close(release)
	<-done
	s.beforeConfigurePublish = nil
	s.metaMu.Lock()
	capability := s.consentMetadata[diagnosticPrivateKey("actor")].PushCapability
	s.metaMu.Unlock()
	if capability {
		t.Fatal("late configure resurrected older parser capability")
	}
	if s.configure("actor", true, true, 1) != nil {
		t.Fatal("same epoch new configure rejected")
	}
	s.metaMu.Lock()
	capability = s.consentMetadata[diagnosticPrivateKey("actor")].PushCapability
	s.metaMu.Unlock()
	if !capability {
		t.Fatal("fresh configure could not restore current parser capability")
	}
}
func TestCallDiagnosticsPushCapabilityRequiresFreshProofAfterRelayRestart(t *testing.T) {
	dir := t.TempDir()
	s, err := newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	_ = s.configure("actor", true, true, 1)
	s.close()
	s, err = newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer s.close()
	c := s.consentMetadata[diagnosticPrivateKey("actor")]
	if !c.Enabled || !c.PushTrace || c.PushCapability {
		t.Fatal("persisted consent incorrectly proved current native parser")
	}
	if s.configure("actor", true, true, 1) != nil || !s.consentMetadata[diagnosticPrivateKey("actor")].PushCapability {
		t.Fatal("fresh authenticated configure did not restore capability")
	}
}
