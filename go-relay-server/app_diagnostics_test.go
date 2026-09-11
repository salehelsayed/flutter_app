package main

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/google/uuid"
	"github.com/libp2p/go-libp2p/core/network"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func appTestStore(t *testing.T) *appDiagnosticStore {
	t.Helper()
	s, err := newAppDiagnosticStore(t.TempDir(), 0, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.close)
	return s
}
func appTestEvent() map[string]any {
	return map[string]any{"schemaVersion": 1, "eventId": uuid.NewString(), "traceId": uuid.NewString(), "attemptId": uuid.NewString(), "source": "flutter", "platform": "android", "runId": uuid.NewString(), "sequence": 0, "occurredAtMs": time.Now().UnixMilli(), "elapsedMs": 0, "feature": "media", "stage": "start", "outcome": "started", "reason": "none", "build": "1.0.1+112", "values": map[string]any{}}
}
func appJSON(v any) []byte { b, _ := json.Marshal(v); return b }
func appExpect(t *testing.T, s *appDiagnosticStore, actor string, epoch int64, e map[string]any, status, reason string) {
	t.Helper()
	a, b := s.append(actor, epoch, appJSON(e))
	if a != status || b != reason {
		t.Fatalf("got %s/%s want %s/%s", a, b, status, reason)
	}
}
func TestAppDiagnosticSchemaStrictPrivacy(t *testing.T) {
	for _, mutate := range []func(map[string]any){
		func(e map[string]any) { e["reason"] = "secret exception" }, func(e map[string]any) { e["token"] = "secret" }, func(e map[string]any) { e["source"] = "relay" }, func(e map[string]any) { e["traceId"] = "message-handle" }, func(e map[string]any) { e["attemptId"] = uuid.NewSHA1(uuid.Nil, []byte("x")).String() }, func(e map[string]any) { e["values"] = map[string]any{"path": "/private"} }, func(e map[string]any) { e["values"] = map[string]any{"fingerprint": "invalid"} }, func(e map[string]any) { e["values"] = map[string]any{"count": true} }, func(e map[string]any) { e["elapsedMs"] = -1 }, func(e map[string]any) { e["build"] = strings.Repeat("a", 81) },
	} {
		e := appTestEvent()
		mutate(e)
		if _, err := validateAppDiagnosticEvent(appJSON(e), false); err == nil {
			t.Fatal("accepted unsafe event")
		}
	}
	e := appTestEvent()
	delete(e, "traceId")
	delete(e, "attemptId")
	e["values"] = map[string]any{"fingerprint": strings.Repeat("a", 64), "reportTimeIsIntervalEnd": true, "extensionProcess": true, "operation": "relay_probe", "osMajor": 26}
	if _, err := validateAppDiagnosticEvent(appJSON(e), false); err != nil {
		t.Fatal(err)
	}
	raw := strings.TrimSuffix(string(appJSON(e)), "}") + `,"reason":"none"}`
	if _, err := validateAppDiagnosticEvent([]byte(raw), false); err == nil {
		t.Fatal("duplicate keys accepted")
	}
	canonical, err := os.ReadFile("../tool/app_diagnostics/schema_v1.json")
	if err != nil || string(canonical) != string(appDiagnosticSchemaJSON) {
		t.Fatal("canonical schema drift")
	}
}
func TestAppDiagnosticOwnerIsolationEpochAndRetry(t *testing.T) {
	s := appTestStore(t)
	e := appTestEvent()
	appExpect(t, s, "a", 1, e, "retry", "diagnostics_disabled")
	for _, actor := range []string{"a", "b"} {
		if err := s.configure(actor, true, 1, false); err != nil {
			t.Fatal(err)
		}
		appExpect(t, s, actor, 1, e, "accepted", "none")
	}
	if len(s.records) != 2 {
		t.Fatal("owners merged")
	}
	appExpect(t, s, "a", 1, e, "accepted", "none")
	e["reason"] = "timeout"
	appExpect(t, s, "a", 1, e, "rejected", "invalid_request")
	if err := s.configure("a", false, 2, false); err != nil {
		t.Fatal(err)
	}
	if len(s.records) != 1 {
		t.Fatal("disable erased wrong owner")
	}
	if s.configure("a", true, 1, false) == nil || s.configure("a", true, 2, false) == nil {
		t.Fatal("stale/conflicting enable accepted")
	}
	if err := s.configure("a", true, 3, false); err != nil {
		t.Fatal(err)
	}
	e["eventId"] = uuid.NewString()
	appExpect(t, s, "a", 1, e, "retry", "stale_epoch")
	appExpect(t, s, "a", 3, e, "accepted", "none")
	if err := s.configure("a", true, 4, true); err != nil {
		t.Fatal(err)
	}
	appExpect(t, s, "a", 3, e, "retry", "stale_epoch")
	e["eventId"] = uuid.NewString()
	appExpect(t, s, "a", 4, e, "accepted", "none")
	if err := s.configure("a", true, 4, true); err != nil {
		t.Fatal(err)
	}
	if len(s.records) != 2 {
		t.Fatal("idempotent clear erased new records")
	}
}
func TestAppDiagnosticInterruptedClearCannotResurrect(t *testing.T) {
	s := appTestStore(t)
	_ = s.configure("a", true, 1, false)
	e := appTestEvent()
	appExpect(t, s, "a", 1, e, "accepted", "none")
	s.remove = func(string) error { return errors.New("private filesystem") }
	if s.configure("a", true, 2, true) == nil {
		t.Fatal("erase failure hidden")
	}
	e["eventId"] = uuid.NewString()
	appExpect(t, s, "a", 2, e, "retry", "sink_unavailable")
	s.close()
	next, err := newAppDiagnosticStore(s.dir, 0, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer next.close()
	if len(next.records) != 0 || next.state("a").ErasePending {
		t.Fatal("restart failed pending erase")
	}
	appExpect(t, next, "a", 1, e, "retry", "stale_epoch")
	appExpect(t, next, "a", 2, e, "accepted", "none")
}
func TestAppDiagnosticFinalReservationAndDistinctRetry(t *testing.T) {
	s := appTestStore(t)
	_ = s.configure("a", true, 1, false)
	e := appTestEvent()
	// A normal record reaches the configured byte/event cap; repeated discard is unique.
	reached := false
	for i := 0; i < appDiagnosticBucketEvents+1; i++ {
		e["eventId"] = uuid.NewString()
		e["sequence"] = i
		a, _ := s.append("a", 1, appJSON(e))
		if a == "rejected" {
			reached = true
			break
		}
	}
	if !reached {
		t.Fatal("quota not exercised")
	}
	r := s.records[appDiagnosticBucket(appDiagnosticOwner("a"), e)]
	dropped := r.Dropped
	appExpect(t, s, "a", 1, e, "rejected", "quota_exceeded")
	if s.records[appDiagnosticBucket(appDiagnosticOwner("a"), e)].Dropped != dropped {
		t.Fatal("retry inflated loss")
	}
	e["eventId"] = uuid.NewString()
	e["stage"] = "finish"
	e["outcome"] = "failed"
	e["reason"] = "hash_mismatch"
	appExpect(t, s, "a", 1, e, "accepted", "none")
	e["attemptId"] = uuid.NewString()
	e["eventId"] = uuid.NewString()
	e["outcome"] = "success"
	e["reason"] = "none"
	appExpect(t, s, "a", 1, e, "accepted", "none")
	if len(s.records) != 2 {
		t.Fatal("retry terminal lost")
	}
	for _, r := range s.records {
		if len(r.Finals) != 1 || len(appJSON(r)) > appDiagnosticRecordBytes {
			t.Fatal("terminal reservation unbounded")
		}
	}
}
func TestAppDiagnosticTransientPressureDoesNotDiscard(t *testing.T) {
	s := appTestStore(t)
	_ = s.configure("a", true, 1, false)
	e := appTestEvent()
	original := s.write
	s.write = func(string, []byte) error { return errors.New("secret disk path") }
	appExpect(t, s, "a", 1, e, "retry", "sink_unavailable")
	if len(s.records) != 0 {
		t.Fatal("failed write published")
	}
	s.write = original
	s.ownerQuota = 1
	appExpect(t, s, "a", 1, e, "retry", "quota_exceeded")
	s.ownerQuota = appDiagnosticOwnerBytes
	s.quota = 1
	appExpect(t, s, "a", 1, e, "retry", "quota_exceeded")
	s.quota = appDiagnosticGlobalBytes
	appExpect(t, s, "a", 1, e, "accepted", "none")
}
func TestAppDiagnosticRetentionAndRestart(t *testing.T) {
	s := appTestStore(t)
	_ = s.configure("a", true, 1, false)
	e := appTestEvent()
	appExpect(t, s, "a", 1, e, "accepted", "none")
	s.close()
	next, err := newAppDiagnosticStore(s.dir, 0, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer next.close()
	appExpect(t, next, "a", 1, e, "accepted", "none")
	next.now = func() time.Time { return time.Now().Add(15 * 24 * time.Hour) }
	appExpect(t, next, "a", 1, e, "retry", "diagnostics_disabled")
	if len(next.records) != 0 {
		t.Fatal("retention not applied")
	}
	files, _ := os.ReadDir(s.dir)
	for _, file := range files {
		info, _ := os.Stat(filepath.Join(s.dir, file.Name()))
		if info.Mode().Perm() != 0600 {
			t.Fatal("private file permissions")
		}
	}
}
func TestAppDiagnosticHandlerAcknowledgesOnlyDurableOrPermanent(t *testing.T) {
	s := appTestStore(t)
	e := appTestEvent()
	invoke := func(req map[string]any) map[string]any {
		req["action"] = appDiagnosticsAction
		return appDiagnosticResponse(appJSON(req), "a", s)
	}
	if invoke(map[string]any{"op": "configure", "enabled": true, "consentEpoch": 1})["status"] != "OK" {
		t.Fatal("configure")
	}
	raw := map[string]any{"op": "upload", "consentEpoch": 1, "events": []any{e}}
	original := s.write
	s.write = func(string, []byte) error { return errors.New("secret") }
	data := invoke(raw)["data"].(map[string]any)
	if len(data["acceptedEventIds"].([]string)) != 0 || len(data["rejectedEventIds"].([]string)) != 0 || data["reason"] != "sink_unavailable" {
		t.Fatal("transient failure discarded")
	}
	s.write = original
	data = invoke(raw)["data"].(map[string]any)
	if len(data["acceptedEventIds"].([]string)) != 1 {
		t.Fatal("durable ack missing")
	}
	e["eventId"] = uuid.NewString()
	e["reason"] = "secret"
	data = invoke(raw)["data"].(map[string]any)
	if len(data["rejectedEventIds"].([]string)) != 1 {
		t.Fatal("invalid event not permanently rejected")
	}
	raw["owner"] = "victim"
	if invoke(raw)["status"] != "ERROR" {
		t.Fatal("owner injection accepted")
	}
	if appDiagnosticResponse(appJSON(raw), "", s)["status"] != "ERROR" {
		t.Fatal("unauthenticated accepted")
	}
}

func TestAppDiagnosticLegacySchemaAcceptsProjectedLockInMixedBatch(t *testing.T) {

	// Exercise the real handler/store with the pre-lock-observation vocabulary.
	// No production receiver upgrade or capability negotiation is assumed.
	originalRules := appDiagnosticRules
	var legacyRules appDiagnosticSchema
	if err := json.Unmarshal(appDiagnosticSchemaJSON, &legacyRules); err != nil {
		t.Fatal(err)
	}
	delete(legacyRules.EnumValues, "appLifecycle")
	operations := []string{}
	for _, operation := range legacyRules.EnumValues["operation"] {
		if operation != "notification_flock" {
			operations = append(operations, operation)
		}
	}
	legacyRules.EnumValues["operation"] = operations
	appDiagnosticRules = legacyRules
	t.Cleanup(func() { appDiagnosticRules = originalRules })

	s := appTestStore(t)
	if err := s.configure("a", true, 1, false); err != nil {
		t.Fatal(err)
	}
	original := appTestEvent()
	rich := appTestEvent()
	rich["feature"], rich["stage"], rich["outcome"] = "push", "snapshot", "pending"
	rich["values"] = map[string]any{
		"operation": "notification_flock", "appLifecycle": "paused",
		"count": 1, "queuedEvents": 0, "durationMs": 40,
		"droppedEvents": 0, "cleanupComplete": false,
	}
	if _, err := validateAppDiagnosticEvent(appJSON(rich), false); err == nil {
		t.Fatal("legacy schema unexpectedly admitted the rich local vocabulary")
	}
	var projected map[string]any
	if err := json.Unmarshal(appJSON(rich), &projected); err != nil {
		t.Fatal(err)
	}
	values := projected["values"].(map[string]any)
	values["operation"] = "other"
	delete(values, "appLifecycle")
	response := appDiagnosticResponse(appJSON(map[string]any{
		"action": appDiagnosticsAction, "op": "upload", "consentEpoch": 1,
		"events": []any{original, projected},
	}), "a", s)
	data := response["data"].(map[string]any)
	accepted := data["acceptedEventIds"].([]string)
	if response["status"] != "OK" || len(accepted) != 2 ||
		accepted[0] != original["eventId"] || accepted[1] != rich["eventId"] ||
		len(data["rejectedEventIds"].([]string)) != 0 {
		t.Fatal("legacy receiver failed mixed-batch admission with original event IDs")
	}
	for _, event := range []map[string]any{original, projected} {
		record := s.records[appDiagnosticBucket(appDiagnosticOwner("a"), event)]
		if record == nil || len(record.Events) != 1 ||
			string(record.Events[0].Event) != string(appJSON(event)) {
			t.Fatal("receiver changed or lost an admitted event")
		}
	}
	if rich["values"].(map[string]any)["appLifecycle"] != "paused" ||
		rich["values"].(map[string]any)["operation"] != "notification_flock" {
		t.Fatal("projection mutated rich local evidence")
	}
}

func TestAppDiagnosticOriginalRunAndMultipleOSReportsRemainDistinct(t *testing.T) {
	s := appTestStore(t)
	_ = s.configure("a", true, 1, false)
	e := appTestEvent()
	delete(e, "attemptId")
	delete(e, "traceId")
	e["reportingRunId"] = uuid.NewString()
	e["stage"] = "crash"
	e["feature"] = "runtime"
	e["source"] = "ios"
	e["outcome"] = "failed"
	e["reason"] = "os_crash"
	appExpect(t, s, "a", 1, e, "accepted", "none")
	e["eventId"] = uuid.NewString()
	appExpect(t, s, "a", 1, e, "accepted", "none")
	r := s.records[appDiagnosticBucket(appDiagnosticOwner("a"), e)]
	if len(r.Finals) != 2 {
		t.Fatal("independent OS report lost")
	}
	e["stage"] = "finish"
	e["eventId"] = uuid.NewString()
	appExpect(t, s, "a", 1, e, "accepted", "none")
	e["runId"] = uuid.NewString()
	e["eventId"] = uuid.NewString()
	appExpect(t, s, "a", 1, e, "accepted", "none")
	if len(s.records) != 2 {
		t.Fatal("new native run merged")
	}
}
func TestAppDiagnosticConsentExpiryAlsoErasesNewerRecords(t *testing.T) {
	s := appTestStore(t)
	_ = s.configure("a", true, 1, false)
	c := s.consent[appDiagnosticOwner("a")]
	c.UpdatedAtMs = time.Now().Add(-15 * 24 * time.Hour).UnixMilli()
	s.consent[appDiagnosticOwner("a")] = c
	e := appTestEvent()
	appExpect(t, s, "a", 1, e, "retry", "diagnostics_disabled")
	if len(s.records) != 0 {
		t.Fatal("expired consent retained records")
	}
}

func TestAppDiagnosticBootstrapUsesIndependentEnvironment(t *testing.T) {
	t.Setenv("APP_DIAGNOSTICS_DIR", t.TempDir())
	t.Setenv("APP_DIAGNOSTICS_MAX_BYTES", "2097152")
	stores, err := newControlPlaneStores(context.Background(), backendConfig{Kind: backendKindMemory}, DefaultServerLimits(), "")
	if err != nil {
		t.Fatal(err)
	}
	defer stores.Close()
	if stores.Inbox.appDiagnostics == nil || stores.Inbox.appDiagnostics.quota != 2097152 {
		t.Fatal("app collector not registered at bootstrap")
	}
	t.Setenv("APP_DIAGNOSTICS_MAX_BYTES", "invalid")
	if initAppDiagnosticsFromEnvironment() != nil {
		t.Fatal("invalid config exposed ready collector")
	}
}

func TestAppDiagnosticRegisteredOnAuthenticatedInboxStream(t *testing.T) {
	store := appTestStore(t)
	fixture := newCallHandlerFixture(t, nil)
	inbox := NewInboxStore(NewPushServiceWithBackend(newMemoryPushTokenStore()))
	inbox.appDiagnostics = store
	fixture.relay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		HandleInboxStream(s, inbox, nil, fixture.relay, nil, nil)
		fixture.handled <- struct{}{}
	})
	for _, actor := range []string{fixture.client.ID().String(), fixture.recipient.ID().String()} {
		if store.state(actor).Enabled {
			t.Fatal("consent default enabled")
		}
	}
	configure := map[string]any{"action": appDiagnosticsAction, "op": "configure", "consentEpoch": 1, "enabled": true}
	for _, from := range []bool{false, true} {
		client := fixture.client
		if from {
			client = fixture.recipient
		}
		r := callHandlerRoundTrip(t, fixture, client, configure)
		if r["status"] != "OK" {
			t.Fatal("registered configure")
		}
	}
	e := appTestEvent()
	upload := map[string]any{"action": appDiagnosticsAction, "op": "upload", "consentEpoch": 1, "events": []any{e}}
	for _, from := range []bool{false, true} {
		client := fixture.client
		if from {
			client = fixture.recipient
		}
		r := callHandlerRoundTrip(t, fixture, client, upload)
		data := r["data"].(map[string]any)
		if len(data["acceptedEventIds"].([]any)) != 1 {
			t.Fatal("registered upload")
		}
	}
	if len(store.records) != 2 {
		t.Fatal("authenticated stream owners merged")
	}
	configure["enabled"] = false
	configure["consentEpoch"] = 2
	_ = callHandlerRoundTrip(t, fixture, fixture.client, configure)
	if store.state(fixture.client.ID().String()).Enabled || !store.state(fixture.recipient.ID().String()).Enabled || len(store.records) != 1 {
		t.Fatal("consent erased other actor")
	}
}

func TestAppDiagnosticDisableSerializesAfterInFlightDurableWrite(t *testing.T) {
	s := appTestStore(t)
	_ = s.configure("a", true, 1, false)
	e := appTestEvent()
	original := s.write
	entered, release, uploaded, disabled := make(chan struct{}), make(chan struct{}), make(chan struct{}), make(chan struct{})
	s.write = func(path string, raw []byte) error {
		if filepath.Base(path) != "consent.json" {
			close(entered)
			<-release
		}
		return original(path, raw)
	}
	go func() { s.append("a", 1, appJSON(e)); close(uploaded) }()
	<-entered
	go func() { _ = s.configure("a", false, 2, false); close(disabled) }()
	close(release)
	<-uploaded
	<-disabled
	if len(s.records) != 0 || s.state("a").Enabled || s.usedBytes != 0 || len(s.eventIndex) != 0 {
		t.Fatal("late upload resurrected erased data")
	}
}
