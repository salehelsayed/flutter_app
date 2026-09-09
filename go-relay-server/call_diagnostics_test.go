package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

func diagnosticTestStore(t *testing.T) *callDiagnosticStore {
	t.Helper()
	s, err := newCallDiagnosticStore(t.TempDir(), 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.close)
	return s
}
func diagnosticTestEvent(trace, source, stage, action string) json.RawMessage {
	e := map[string]any{"schemaVersion": 1, "eventId": uuid.NewString(), "traceId": trace, "source": source, "role": "caller", "runId": uuid.NewString(), "sequence": 0, "occurredAtMs": time.Now().UnixMilli(), "elapsedMs": 0, "stage": stage, "action": action, "outcome": "ok", "reason": "none", "values": map[string]any{}}
	raw, _ := json.Marshal(e)
	return raw
}
func TestCallDiagnosticsConsentAuthenticationDedupAndRestart(t *testing.T) {
	dir := t.TempDir()
	s, err := newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	trace := uuid.NewString()
	raw := diagnosticTestEvent(trace, "flutter", "attempt", "start")
	if s.appendEvent("caller-private", raw, false) {
		t.Fatal("consent default must be off")
	}
	if s.configure("caller-private", true, false, 10) != nil {
		t.Fatal("configure")
	}
	if !s.appendEvent("caller-private", raw, false) || !s.appendEvent("caller-private", raw, false) {
		t.Fatal("durable idempotent upload failed")
	}
	if s.configure("foreign-private", true, true, 1) != nil {
		t.Fatal("configure foreign")
	}
	if s.appendEvent("foreign-private", raw, false) {
		t.Fatal("foreign upload accepted")
	}
	if s.resolve("foreign-private", "raw-call-secret") != "" {
		t.Fatal("foreign resolve")
	}
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("caller-private", d) {
		t.Fatal("prepare")
	}
	s.bindCommitted("caller-private", "callee-private", "raw-call-secret", d)
	s.flush()
	if s.pushTrace("callee-private", "raw-call-secret") != nil {
		t.Fatal("push trace without recipient consent")
	}
	if s.configure("callee-private", true, true, 1) != nil {
		t.Fatal("configure callee")
	}
	if s.resolve("callee-private", "raw-call-secret") != trace || s.pushTrace("callee-private", "raw-call-secret") == nil {
		t.Fatal("participant resolve/push trace")
	}
	if !s.appendEvent("callee-private", diagnosticTestEvent(trace, "ios", "presentation", "present"), false) {
		t.Fatal("participant upload")
	}
	if s.configure("caller-private", false, false, 11) != nil || s.configure("caller-private", true, false, 10) == nil || s.enabled("caller-private") {
		t.Fatal("late consent enable must be rejected")
	}
	s.close()
	s, err = newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer s.close()
	if s.enabled("caller-private") || s.resolve("callee-private", "raw-call-secret") != "" {
		t.Fatal("restart lost consent/binding")
	}
	if s.records[trace] != nil {
		t.Fatal("disabled actor records retained")
	}
	files, _ := os.ReadDir(dir)
	for _, file := range files {
		data, _ := os.ReadFile(filepath.Join(dir, file.Name()))
		for _, secret := range []string{"caller-private", "callee-private", "foreign-private", "raw-call-secret"} {
			if bytes.Contains(data, []byte(secret)) {
				t.Fatal("private identity/handle leaked")
			}
		}
	}
}
func TestCallDiagnosticsSchemaRejectsSecretsServerSpoofAndUnknownFields(t *testing.T) {
	trace := uuid.NewString()
	base := diagnosticTestEvent(trace, "flutter", "attempt", "start")
	var event map[string]any
	_ = json.Unmarshal(base, &event)
	for name, mutate := range map[string]func(map[string]any){"extra": func(e map[string]any) { e["callHandle"] = "secret" }, "value": func(e map[string]any) { e["values"] = map[string]any{"token": "secret"} }, "source": func(e map[string]any) { e["source"] = "relay" }, "role": func(e map[string]any) { e["role"] = "server" }, "reason": func(e map[string]any) { e["reason"] = "raw error with IP" }, "enum": func(e map[string]any) { e["values"] = map[string]any{"transport": "192.0.2.1"} }, "required": func(e map[string]any) { delete(e, "elapsedMs") }} {
		t.Run(name, func(t *testing.T) {
			var e map[string]any
			_ = json.Unmarshal(base, &e)
			mutate(e)
			raw, _ := json.Marshal(e)
			if _, err := validateCallDiagnosticEvent(raw, false); err == nil {
				t.Fatal("invalid event accepted")
			}
		})
	}
	if _, err := validateCallDiagnosticEvent(base, false); err != nil {
		t.Fatal(err)
	}
}
func TestCallDiagnosticsQuotaPreservesTerminalSummaryAndExpiry(t *testing.T) {
	s := diagnosticTestStore(t)
	_ = s.configure("caller", true, false, 1)
	trace := uuid.NewString()
	accepted := 0
	for i := 0; i < callDiagnosticTraceEvents; i++ {
		if !s.appendEvent("caller", diagnosticTestEvent(trace, "flutter", "media", "snapshot"), false) {
			break
		}
		accepted++
	}
	if accepted == 0 || accepted > callDiagnosticTraceEvents {
		t.Fatal("invalid bounded event count")
	}

	if s.appendEvent("caller", diagnosticTestEvent(trace, "flutter", "media", "snapshot"), false) {
		t.Fatal("event cap ignored")
	}
	terminal := diagnosticTestEvent(trace, "flutter", "terminal", "finish")
	if !s.appendEvent("caller", terminal, false) {
		t.Fatal("terminal summary lost to event quota")
	}
	if len(s.records[trace].Events) != accepted || len(s.records[trace].Summaries) != 1 {
		t.Fatal("summary/event bounds")
	}
	s.mu.Lock()
	s.records[trace].CreatedAtMs = time.Now().Add(-15 * 24 * time.Hour).UnixMilli()
	s.expireLocked()
	s.mu.Unlock()
	if s.records[trace] != nil {
		t.Fatal("retention did not expire")
	}
	s.quota = 300
	if s.appendEvent("caller", diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start"), false) {
		t.Fatal("global quota ignored")
	}
}

func TestCallDiagnosticsFullBudgetPreservesBothEndpointMediaAndTerminal(t *testing.T) {
	dir := t.TempDir()
	s, err := newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if s != nil {
			s.close()
		}
	}()
	for _, actor := range []string{"caller", "callee"} {
		if err := s.configure(actor, true, false, 1); err != nil {
			t.Fatal(err)
		}
	}
	trace := uuid.NewString()
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("caller", d) {
		t.Fatal("prepare")
	}
	s.bindCommitted("caller", "callee", "private-handle", d)
	s.flush()
	var overflow json.RawMessage
	for i := 0; i <= callDiagnosticTraceEvents; i++ {
		overflow = diagnosticTestEvent(trace, "flutter", "signaling", "snapshot")
		if !s.appendEvent("caller", overflow, false, 1) {
			break
		}
	}
	count, dropped := len(s.records[trace].Events), s.records[trace].Dropped
	for i := 0; i < 10; i++ {
		if s.appendEvent("caller", overflow, false, 1) {
			t.Fatal("ordinary overflow cannot be acknowledged as retained")
		}
	}
	if s.records[trace].Dropped != dropped {
		t.Fatal("duplicate overflow retry inflated dropped-event count")
	}
	var proofs []json.RawMessage
	for _, actor := range []string{"caller", "callee"} {
		for _, stage := range []string{"media", "terminal"} {
			raw := diagnosticTestEvent(trace, "flutter", stage, "snapshot")
			var event map[string]any
			_ = json.Unmarshal(raw, &event)
			event["role"] = actor
			event["outcome"] = "media_flow_verified"
			event["values"] = map[string]any{"mediaFlowVerified": true}
			if stage == "terminal" {
				event["action"] = "finish"
				event["outcome"] = "completed_after_media"
			}
			raw, _ = json.Marshal(event)
			if !s.appendEvent(actor, raw, false, 1) {
				t.Fatalf("%s %s proof lost to ordinary trace quota", actor, stage)
			}
			proofs = append(proofs, raw)
		}
	}
	if len(s.records[trace].Events) != count || len(s.records[trace].Summaries) != 4 || s.records[trace].Dropped != dropped {
		t.Fatal("reserved evidence must remain bounded without counting retained proof as dropped")
	}
	s.close()
	s, err = newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	if len(s.records[trace].Summaries) != 4 {
		t.Fatal("restart lost endpoint evidence")
	}
	if s.appendEvent("caller", overflow, false, 1) || s.records[trace].Dropped != dropped {
		t.Fatal("restart lost permanent-discard deduplication")
	}
	for i, raw := range proofs {
		actor := "caller"
		if i >= 2 {
			actor = "callee"
		}
		if !s.appendEvent(actor, raw, false, 1) {
			t.Fatal("reserved proof retry is not idempotent")
		}
	}
	for i := 0; i <= callDiagnosticDiscardIDLimit; i++ {
		if s.appendEventResult("caller", diagnosticTestEvent(trace, "flutter", "signaling", "snapshot"), false, 1) != callDiagnosticAppendDiscarded {
			t.Fatal("full trace must permanently discard ordinary events")
		}
	}
	if len(s.records[trace].DiscardedEventIDs) != callDiagnosticDiscardIDLimit || s.records[trace].Dropped != callDiagnosticDiscardIDLimit || !s.records[trace].DiscardLedgerSaturated {
		t.Fatal("discard ledger must be bounded and report a saturated lower bound")
	}
	if err := s.clearActor("caller", 2); err != nil || s.records[trace] != nil {
		t.Fatal("clear must erase reserved evidence and its private discard ledger")
	}
}

func TestCallDiagnosticsLegacyDropAttemptsAreNotUniqueEventLoss(t *testing.T) {
	dir := t.TempDir()
	s, err := newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	_ = s.configure("caller", true, false, 1)
	trace := uuid.NewString()
	if !s.appendEvent("caller", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
		t.Fatal("seed")
	}
	s.records[trace].DropAccountingVersion = 0
	s.records[trace].Dropped = 742
	if err := s.persistLocked(trace); err != nil {
		t.Fatal(err)
	}
	s.close()
	s, err = newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer s.close()
	if s.records[trace].Dropped != 0 || s.records[trace].LegacyDropAttempts != 742 || s.records[trace].DropAccountingVersion != 1 {
		t.Fatal("legacy retry attempts were mislabeled as unique losses")
	}
	raw, _ := os.ReadFile(filepath.Join(dir, trace+".json"))
	if !bytes.Contains(raw, []byte(`"legacyDropAttempts":742`)) {
		t.Fatal("legacy accounting migration was not persisted")
	}
	// An old record with no summaries omits that map from JSON. The first
	// reserved proof after a relay restart must not write through a nil map.
	var media map[string]any
	_ = json.Unmarshal(diagnosticTestEvent(trace, "flutter", "media", "snapshot"), &media)
	media["outcome"] = "media_flow_verified"
	raw, _ = json.Marshal(media)
	if !s.appendEvent("caller", raw, false, 1) || !s.appendEvent("caller", diagnosticTestEvent(trace, "flutter", "terminal", "finish"), false, 1) || len(s.records[trace].Summaries) != 2 {
		t.Fatal("first reserved evidence after restart was not retained")
	}
}
func TestCallDiagnosticsSinkFailureAndOperationOnly(t *testing.T) {
	s := diagnosticTestStore(t)
	_ = s.configure("actor", true, false, 1)
	d := callDiagnosticContext{OperationID: uuid.NewString(), RequestID: uuid.NewString(), Reason: "calls_disabled"}
	if !s.prepare("actor", &d) {
		t.Fatal("operation-only context rejected")
	}
	span := newCallDiagnosticSpan(s, "actor", d, callEndpointRevokeAction)
	span.emit("authority", "revoke", "ok", d.Reason, nil)
	s.flush()
	if len(s.records) != 1 {
		t.Fatal("operation-only event not retained")
	}
	for _, rec := range s.records {
		if len(rec.Events) != 1 || strings.Contains(string(rec.Events[0].Event), "traceId") {
			t.Fatal("authority event invented call trace")
		}
	}
	original := s.dir
	s.dir = filepath.Join(s.dir, "unavailable")
	if s.appendEvent("actor", diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start"), false) {
		t.Fatal("failed persistence acknowledged")
	}
	s.dir = original
}

func runtimeDiagnosticTestEvent(run, source, action, outcome string) json.RawMessage {
	var event map[string]any
	_ = json.Unmarshal(diagnosticTestEvent(uuid.NewString(), source, "authority", action), &event)
	delete(event, "traceId")
	event["runId"], event["role"] = run, "local"
	if source == "relay" {
		event["role"] = "server"
	}
	event["requestId"], event["operationId"] = uuid.NewString(), uuid.NewString()
	event["build"], event["outcome"], event["reason"] = "1.0.1+112", outcome, "resume_refresh"
	event["values"] = map[string]any{"authorityKind": "wake_grant"}
	if outcome == "failed" {
		event["reason"] = "backend_unavailable"
	}
	raw, _ := json.Marshal(event)
	return raw
}

func TestCallDiagnosticsRuntimeRotationPreservesBurstFailureAndRetry(t *testing.T) {
	dir := t.TempDir()
	s, err := newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if s != nil {
			s.close()
		}
	}()
	if err := s.configure("runtime-owner", true, false, 1); err != nil {
		t.Fatal(err)
	}
	run := uuid.NewString()
	var first json.RawMessage
	for i := 0; i < 300; i++ {
		for j, outcome := range []string{"started", "ok", "ok"} {
			action := "publish"
			if j == 2 {
				action = "response"
			}
			raw := runtimeDiagnosticTestEvent(run, "relay", action, outcome)
			if first == nil {
				first = raw
			}
			if result := s.appendEventResult("runtime-owner", raw, true, 1); result != callDiagnosticAppendAccepted {
				t.Fatalf("successful runtime publication %d/%d lost to one-record quota: %v", i, j, result)
			}
		}
	}
	failure := runtimeDiagnosticTestEvent(run, "relay", "publish", "failed")
	if !s.appendEvent("runtime-owner", failure, true, 1) {
		t.Fatal("later runtime failure was lost")
	}
	count := func() int {
		total := 0
		for key, record := range s.records {
			if !strings.HasPrefix(key, "runtime-") || len(key) != 72 {
				t.Fatal("operator-incompatible runtime filename")
			}
			bytes := 0
			for _, e := range record.Events {
				bytes += len(e.Event)
			}
			if len(record.Events) > callDiagnosticTraceEvents || bytes > callDiagnosticTraceBytes || record.Dropped != 0 {
				t.Fatal("runtime rotation changed caps or silently dropped events")
			}
			total += len(record.Events)
		}
		return total
	}
	if len(s.records) < 2 || count() != 901 {
		t.Fatal("burst was not preserved across bounded partitions")
	}
	if !s.appendEvent("runtime-owner", first, true, 1) || count() != 901 {
		t.Fatal("rotation retry duplicated an event")
	}
	s.close()
	s, err = newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	if !s.appendEvent("runtime-owner", first, true, 1) || !s.appendEvent("runtime-owner", failure, true, 1) || count() != 901 {
		t.Fatal("restart lost cross-partition deduplication")
	}
	quota := s.quota
	s.quota = 1
	later := runtimeDiagnosticTestEvent(run, "relay", "publish", "failed")
	if s.appendEventResult("runtime-owner", later, true, 1) != callDiagnosticAppendRetry || count() != 901 {
		t.Fatal("hard global pressure must remain retryable without eviction")
	}
	s.quota = quota
	if !s.appendEvent("runtime-owner", later, true, 1) || count() != 902 {
		t.Fatal("storage recovery lost runtime failure")
	}
	if err := s.clearActor("runtime-owner", 2); err != nil {
		t.Fatal(err)
	}
	if !s.appendEvent("runtime-owner", first, true, 2) || count() != 1 {
		t.Fatal("clear retained stale runtime deduplication")
	}
}

func TestCallDiagnosticsLegacyRuntimeSaturationDoesNotTrapNewEvidence(t *testing.T) {
	dir := t.TempDir()
	s, err := newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if s != nil {
			s.close()
		}
	}()
	actor, run := "legacy-runtime-owner", uuid.NewString()
	if err := s.configure(actor, true, false, 1); err != nil {
		t.Fatal(err)
	}
	key := "runtime-" + diagnosticPrivateKey(actor, run)
	if !s.ensureLocked(actor, key) {
		t.Fatal("legacy setup")
	}
	record := s.records[key]
	var first json.RawMessage
	bytes := 0
	for {
		raw := runtimeDiagnosticTestEvent(run, "relay", "publish", "ok")
		if bytes+len(raw) > callDiagnosticTraceBytes {
			break
		}
		if first == nil {
			first = raw
		}
		record.Events = append(record.Events, callDiagnosticStoredEvent{time.Now().UnixMilli(), raw})
		bytes += len(raw)
	}
	rejected := runtimeDiagnosticTestEvent(run, "relay", "publish", "ok")
	var fields map[string]any
	_ = json.Unmarshal(rejected, &fields)
	record.Dropped, record.DiscardedEventIDs = 1, []string{fields["eventId"].(string)}
	if err := s.persistLocked(key); err != nil {
		t.Fatal(err)
	}
	s.close()
	s, err = newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	oldCount := len(s.records[key].Events)
	if !s.appendEvent(actor, runtimeDiagnosticTestEvent(run, "relay", "publish", "failed"), true, 1) {
		t.Fatal("saturated legacy runtime trapped new failure")
	}
	if !s.appendEvent(actor, first, true, 1) || len(s.records[key].Events) != oldCount {
		t.Fatal("legacy accepted-event retry was duplicated")
	}
	if s.appendEventResult(actor, rejected, true, 1) != callDiagnosticAppendDiscarded || s.records[key].Dropped != 1 {
		t.Fatal("legacy permanent refusal was resurrected or recounted")
	}
	if len(s.records) != 2 {
		t.Fatal("legacy evidence was replaced instead of retained")
	}
}

func TestCallDiagnosticsRuntimeSameRunAndEventAreOwnerIsolated(t *testing.T) {
	s := diagnosticTestStore(t)
	raw := runtimeDiagnosticTestEvent(uuid.NewString(), "ios", "publish", "ok")
	for _, actor := range []string{"runtime-one", "runtime-two"} {
		if err := s.configure(actor, true, false, 1); err != nil {
			t.Fatal(err)
		}
		if !s.appendEvent(actor, raw, false, 1) {
			t.Fatal("one owner's runtime UUID blocked another owner")
		}
	}
	if len(s.records) != 2 {
		t.Fatal("cross-owner runtime deduplication")
	}
	// Expiry must release the indexes as well as the files. Reusing a retained
	// UUID after explicit expiry is new evidence, not a false durable ACK.
	for _, record := range s.records {
		record.CreatedAtMs = time.Now().Add(-15 * 24 * time.Hour).UnixMilli()
	}
	s.expireLocked()
	if len(s.runtimeEventRecords) != 0 || len(s.runtimeHeads) != 0 || !s.appendEvent("runtime-one", raw, false, 1) || len(s.records) != 1 {
		t.Fatal("expired runtime index acknowledged a missing record")
	}
}

func TestCallDiagnosticsRuntimeRotationKeepsOwnerAndRecordLimits(t *testing.T) {
	s := diagnosticTestStore(t)
	for _, actor := range []string{"full-owner", "other-owner"} {
		if err := s.configure(actor, true, false, 1); err != nil {
			t.Fatal(err)
		}
	}
	// Seed valid retained records near the existing owner ceiling without
	// thousands of individual fsyncs; a runtime partition must not bypass it.
	run := uuid.NewString()
	raw := runtimeDiagnosticTestEvent(run, "ios", "publish", "ok")
	ownerBytes := 0
	for partition := 0; ownerBytes < callDiagnosticOwnerBytes; partition++ {
		group := callDiagnosticRuntimeGroup(diagnosticPrivateKey("full-owner"), run)
		key := callDiagnosticRuntimePartitionKey(group, partition)
		if !s.ensureLocked("full-owner", key) {
			t.Fatal("owner fixture reached ceiling early")
		}
		record := s.records[key]
		record.RuntimeGroup, record.RuntimePartition = group, partition
		for i := 0; i < callDiagnosticTraceBytes/len(raw); i++ {
			record.Events = append(record.Events, callDiagnosticStoredEvent{time.Now().UnixMilli(), raw})
		}
		encoded, _ := json.Marshal(record)
		if len(encoded) > callDiagnosticRecordBytes {
			t.Fatal("fixture exceeded record size")
		}
		ownerBytes += len(encoded)
	}
	count := len(s.records)
	if s.appendEventResult("full-owner", runtimeDiagnosticTestEvent(run, "ios", "publish", "failed"), false, 1) != callDiagnosticAppendRetry || len(s.records) != count {
		t.Fatal("rotation bypassed hard owner quota or evicted retained evidence")
	}
	if !s.appendEvent("other-owner", raw, false, 1) {
		t.Fatal("one owner's pressure blocked another below the global ceiling")
	}
	// The pre-existing global record count guard also applies to rotations.
	for i := len(s.records); i < 10000; i++ {
		s.records[uuid.NewString()] = &callDiagnosticRecord{Owner: "unrelated-private-owner"}
	}
	if s.appendEventResult("other-owner", runtimeDiagnosticTestEvent(uuid.NewString(), "ios", "publish", "failed"), false, 1) != callDiagnosticAppendRetry || len(s.records) != 10000 {
		t.Fatal("runtime partitions bypassed retained-record bound")
	}
}

func TestCallDiagnosticsRuntimeOldRetryDoesNotRewindWriteHead(t *testing.T) {
	s := diagnosticTestStore(t)
	_ = s.configure("owner", true, false, 1)
	run := uuid.NewString()
	group := callDiagnosticRuntimeGroup(diagnosticPrivateKey("owner"), run)
	first := runtimeDiagnosticTestEvent(run, "ios", "publish", "ok")
	for partition := 0; partition < 2; partition++ {
		key := callDiagnosticRuntimePartitionKey(group, partition)
		if !s.ensureLocked("owner", key) {
			t.Fatal("setup")
		}
		record := s.records[key]
		record.RuntimeGroup, record.RuntimePartition = group, partition
		if partition == 0 {
			record.Events = append(record.Events, callDiagnosticStoredEvent{time.Now().UnixMilli(), first})
		}
		bytes := len(record.Events) * len(first)
		for {
			raw := runtimeDiagnosticTestEvent(run, "ios", "publish", "ok")
			if bytes+len(raw) > callDiagnosticTraceBytes {
				break
			}
			record.Events = append(record.Events, callDiagnosticStoredEvent{time.Now().UnixMilli(), raw})
			bytes += len(raw)
		}
	}
	s.rebuildRuntimeIndexesLocked()
	if !s.appendEvent("owner", first, false, 1) {
		t.Fatal("old retry")
	}
	if !s.appendEvent("owner", runtimeDiagnosticTestEvent(run, "ios", "publish", "failed"), false, 1) || len(s.records) != 3 {
		t.Fatal("old accepted retry rewound the head and trapped a fresh failure")
	}
}

func TestCallDiagnosticsLegacyRuntimeUUIDv5RetainsRetryEvidence(t *testing.T) {
	dir := t.TempDir()
	s, err := newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	_ = s.configure("legacy", true, false, 1)
	key := "runtime-" + uuid.NewSHA1(uuid.Nil, []byte("legacy runtime")).String()
	if !s.ensureLocked("legacy", key) {
		t.Fatal("legacy setup")
	}
	raw := runtimeDiagnosticTestEvent(uuid.NewString(), "ios", "publish", "ok")
	s.records[key].Events = []callDiagnosticStoredEvent{{time.Now().UnixMilli(), raw}}
	if err := s.persistLocked(key); err != nil {
		t.Fatal(err)
	}
	s.close()
	s, err = newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer s.close()
	if s.records[key] == nil || !s.appendEvent("legacy", raw, false, 1) || len(s.records) != 1 || len(s.records[key].Events) != 1 {
		t.Fatal("legacy UUIDv5 filename lost retained evidence or deduplication")
	}
}

func TestCallDiagnosticsDropTimestampsAreDurableAndDoNotInventLegacyTime(t *testing.T) {
	for _, legacy := range []bool{false, true} {
		t.Run(map[bool]string{false: "new", true: "legacy"}[legacy], func(t *testing.T) {
			s := diagnosticTestStore(t)
			now := time.Now()
			s.now = func() time.Time { return now }
			_ = s.configure("owner", true, false, 1)
			trace := uuid.NewString()
			if !s.ensureLocked("owner", trace) {
				t.Fatal("setup")
			}
			record := s.records[trace]
			raw := diagnosticTestEvent(trace, "flutter", "signaling", "snapshot")
			for i := 0; i < callDiagnosticTraceBytes/len(raw); i++ {
				record.Events = append(record.Events, callDiagnosticStoredEvent{now.UnixMilli(), raw})
			}
			if legacy {
				record.Dropped = 2
			}
			first := diagnosticTestEvent(trace, "flutter", "signaling", "snapshot")
			if s.appendEventResult("owner", first, false, 1) != callDiagnosticAppendDiscarded {
				t.Fatal("expected bounded discard")
			}
			firstTime := now.UnixMilli()
			if record.DroppedUpdatedAtMs != firstTime || (!legacy && record.DroppedFirstAtMs != firstTime) || (legacy && record.DroppedFirstAtMs != 0) {
				t.Fatal("incorrect first/new legacy loss timestamp")
			}
			now = now.Add(time.Second)
			if s.appendEventResult("owner", first, false, 1) != callDiagnosticAppendDiscarded || record.DroppedUpdatedAtMs != firstTime {
				t.Fatal("known retry refreshed unique-loss time")
			}
			before := *record
			s.quota = 1
			later := diagnosticTestEvent(trace, "flutter", "signaling", "snapshot")
			if s.appendEventResult("owner", later, false, 1) != callDiagnosticAppendRetry || record.Dropped != before.Dropped || record.DroppedUpdatedAtMs != before.DroppedUpdatedAtMs {
				t.Fatal("transient quota refusal persisted a loss timestamp")
			}
			s.quota = callDiagnosticGlobalBytes
			if s.appendEventResult("owner", later, false, 1) != callDiagnosticAppendDiscarded || record.DroppedUpdatedAtMs != now.UnixMilli() || record.DroppedFirstAtMs != before.DroppedFirstAtMs {
				t.Fatal("new loss did not update last time independently")
			}
			for len(record.DiscardedEventIDs) < callDiagnosticDiscardIDLimit {
				record.DiscardedEventIDs = append(record.DiscardedEventIDs, uuid.NewString())
			}
			now = now.Add(time.Second)
			if s.appendEventResult("owner", diagnosticTestEvent(trace, "flutter", "signaling", "snapshot"), false, 1) != callDiagnosticAppendDiscarded || !record.DiscardLedgerSaturated || record.DroppedUpdatedAtMs != now.UnixMilli() {
				t.Fatal("first saturation time missing")
			}
			saturatedAt := now.UnixMilli()
			now = now.Add(time.Second)
			if s.appendEventResult("owner", diagnosticTestEvent(trace, "flutter", "signaling", "snapshot"), false, 1) != callDiagnosticAppendDiscarded || record.DroppedUpdatedAtMs != saturatedAt {
				t.Fatal("saturated unknown retries invented exact new-loss time")
			}
			stored, err := os.ReadFile(filepath.Join(s.dir, trace+".json"))
			if err != nil {
				t.Fatal(err)
			}
			var saved callDiagnosticRecord
			if json.Unmarshal(stored, &saved) != nil || saved.DroppedFirstAtMs != record.DroppedFirstAtMs || saved.DroppedUpdatedAtMs != saturatedAt {
				t.Fatal("loss timestamps were not durable")
			}
		})
	}
}

func TestCallDiagnosticsSharedSchemaFixture(t *testing.T) {
	raw, err := os.ReadFile("../tool/call_diagnostics/schema_v1.json")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(raw, callDiagnosticSchemaJSON) {
		t.Fatal("embedded schema drift")
	}
}

func TestCallDiagnosticsNativeAdmissionDispositionAndCustodySchema(t *testing.T) {
	var event map[string]any
	_ = json.Unmarshal(diagnosticTestEvent(uuid.NewString(), "android", "admission", "finish"), &event)
	event["role"] = "callee"
	values := map[string]any{"admissionDisposition": "admitted", "databaseClosed": true, "leaseReleased": true, "requiredPersistenceComplete": true}
	event["values"] = values
	for _, disposition := range []string{"admitted", "terminal", "permanent_reject", "empty_or_already_acked", "deferred", "unknown"} {
		values["admissionDisposition"] = disposition
		raw, _ := json.Marshal(event)
		if _, err := validateCallDiagnosticEvent(raw, false); err != nil {
			t.Fatalf("native admission disposition %s rejected: %v", disposition, err)
		}
	}
	values["admissionDisposition"] = "private error text"
	raw, _ := json.Marshal(event)
	if _, err := validateCallDiagnosticEvent(raw, false); err == nil {
		t.Fatal("unbounded admission disposition accepted")
	}
	values["admissionDisposition"] = "deferred"
	for _, flag := range []string{"databaseClosed", "leaseReleased", "requiredPersistenceComplete"} {
		values[flag] = "private error text"
		raw, _ = json.Marshal(event)
		if _, err := validateCallDiagnosticEvent(raw, false); err == nil {
			t.Fatalf("non-boolean custody flag %s accepted", flag)
		}
		values[flag] = false
	}
}
