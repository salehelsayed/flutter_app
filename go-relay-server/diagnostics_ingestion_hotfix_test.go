package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

type hotfixStream struct {
	network.Stream
	buffer bytes.Buffer
}

func (s *hotfixStream) Read(p []byte) (int, error)  { return s.buffer.Read(p) }
func (s *hotfixStream) Write(p []byte) (int, error) { return s.buffer.Write(p) }
func hotfixUpload(t *testing.T, s *callDiagnosticStore, actor string, epoch int64, events ...json.RawMessage) map[string]any {
	t.Helper()
	stream := &hotfixStream{}
	handleCallDiagnosticRequest(stream, appJSON(map[string]any{"action": callDiagnosticsAction, "op": "upload", "consentEpoch": epoch, "events": events}), actor, &CallControlService{diagnostics: s}, nil)
	var response struct {
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(stream.buffer.Bytes()[4:], &response); err != nil {
		t.Fatal(err)
	}
	return response.Data
}
func hotfixCall(t *testing.T) *callDiagnosticStore {
	t.Helper()
	s := diagnosticTestStore(t)
	if err := s.configure("owner", true, false, 1); err != nil {
		t.Fatal(err)
	}
	return s
}
func TestHotfixFirstAppendRollback(t *testing.T) {
	for _, runtime := range []bool{false, true} {
		for _, failure := range []string{"quota", "disk"} {
			t.Run(fmt.Sprint(runtime, "/", failure), func(t *testing.T) {
				s := hotfixCall(t)
				oldDir := s.dir
				if failure == "quota" {
					s.quota = 300
				} else {
					s.dir = filepath.Join(s.dir, "missing")
				}
				raw := diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start")
				if runtime {
					raw = runtimeDiagnosticTestEvent(uuid.NewString(), "ios", "publish", "ok")
				}
				for i := 0; i < 3; i++ {
					if s.appendEventResult("owner", raw, false, 1) != callDiagnosticAppendRetry {
						t.Fatal("must retry")
					}
				}
				if len(s.records) != 0 || len(s.metadata) != 0 || len(s.runtimeHeads) != 0 || len(s.runtimeEventRecords) != 0 {
					t.Fatalf("failed append leaked records=%d metadata=%d runtime=%d/%d", len(s.records), len(s.metadata), len(s.runtimeHeads), len(s.runtimeEventRecords))
				}
				s.dir = oldDir
				s.quota = callDiagnosticGlobalBytes
				if !s.appendEvent("owner", raw, false, 1) {
					t.Fatal("recovery failed")
				}
			})
		}
	}
}
func TestHotfixConflictWire(t *testing.T) {
	for _, runtime := range []bool{false, true} {
		t.Run(fmt.Sprint(runtime), func(t *testing.T) {
			s := hotfixCall(t)
			raw := diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start")
			if runtime {
				raw = runtimeDiagnosticTestEvent(uuid.NewString(), "ios", "publish", "ok")
			}
			if !s.appendEvent("owner", raw, false, 1) {
				t.Fatal("seed")
			}
			var fields map[string]any
			_ = json.Unmarshal(raw, &fields)
			fields["reason"] = "timeout"
			conflict := appJSON(fields)
			before := appJSON(s.records)
			data := hotfixUpload(t, s, "owner", 1, raw, conflict)
			if len(data["acceptedEventIds"].([]any)) != 1 || len(data["rejectedEventIds"].([]any)) != 1 || data["reason"] == "sink_unavailable" {
				t.Fatalf("conflict must terminate, duplicate must ACK: %v", data)
			}
			if !bytes.Equal(before, appJSON(s.records)) {
				t.Fatal("conflict changed storage")
			}
			data = hotfixUpload(t, s, "owner", 2, conflict)
			if len(data["acceptedEventIds"].([]any)) != 0 || len(data["rejectedEventIds"].([]any)) != 0 {
				t.Fatal("epoch must precede conflict")
			}
		})
	}
}
func TestHotfixBindingBudget(t *testing.T) {
	s := hotfixCall(t)
	trace := uuid.NewString()
	if !s.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
		t.Fatal("seed")
	}
	before := appJSON(s.records[trace])
	s.quota = len(before)
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("owner", d, 1) {
		t.Fatal("prepare")
	}
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	disk, err := os.ReadFile(filepath.Join(s.dir, trace+".json"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, disk) || !bytes.Equal(before, appJSON(s.records[trace])) {
		t.Fatal("binding bypassed quota or mutated durable record on refusal")
	}
	if s.resolve("owner", "handle") != trace {
		t.Fatal("quota lost committed in-process authority")
	}
	s.quota = callDiagnosticGlobalBytes
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	if len(s.records[trace].Bindings) != 2 {
		t.Fatal("binding recovery")
	}
}
func TestHotfixOwnerConfiguration(t *testing.T) {
	for _, kind := range []string{"APP", "CALL"} {
		t.Run(kind, func(t *testing.T) {
			global, def := appDiagnosticGlobalBytes, appDiagnosticOwnerBytes
			if kind == "CALL" {
				global, def = callDiagnosticGlobalBytes, callDiagnosticOwnerBytes
			}
			for _, tc := range []struct {
				raw  string
				want int
			}{{"", def}, {fmt.Sprint(def * 2), def * 2}, {fmt.Sprint(global), global}, {"0", def}, {"-1", def}, {"bad", def}, {"9223372036854775808", def}, {fmt.Sprint(global + 1), def}, {" 123", def}} {
				t.Run(tc.raw, func(t *testing.T) {
					t.Setenv(kind+"_DIAGNOSTICS_DIR", t.TempDir())
					t.Setenv(kind+"_DIAGNOSTICS_OWNER_MAX_BYTES", tc.raw)
					var value reflect.Value
					if kind == "APP" {
						s := initAppDiagnosticsFromEnvironment()
						if s == nil {
							t.Fatal("invalid override must fall back, retain service")
						}
						defer s.close()
						value = reflect.ValueOf(s).Elem()
					} else {
						s := initCallDiagnosticsFromEnvironment()
						if s == nil {
							t.Fatal("invalid override must fall back")
						}
						defer s.close()
						value = reflect.ValueOf(s).Elem()
					}
					q := value.FieldByName("ownerQuota")
					if !q.IsValid() || int(q.Int()) != tc.want {
						t.Fatalf("effective owner limit: got %v want %d", q, tc.want)
					}
				})
			}
		})
	}
}
func TestHotfixRetainedOverGlobalRestart(t *testing.T) {
	for _, kind := range []string{"app", "call"} {
		t.Run(kind, func(t *testing.T) {
			dir := t.TempDir()
			if kind == "call" {
				s, err := newCallDiagnosticStore(dir, 0, time.Now)
				if err != nil {
					t.Fatal(err)
				}
				_ = s.configure("owner", true, false, 1)
				for i := 0; i < 2; i++ {
					trace := uuid.NewString()
					if !s.ensureLocked("owner", trace) {
						t.Fatal("seed")
					}
					r := s.records[trace]
					raw := diagnosticTestEvent(trace, "flutter", "attempt", "start")
					for j := 0; j < 450; j++ {
						r.Events = append(r.Events, callDiagnosticStoredEvent{s.now().UnixMilli(), raw})
					}
					if err := s.persistLocked(trace); err != nil {
						t.Fatal(err)
					}
				}
				s.close()
				s, err = newCallDiagnosticStore(dir, 1, time.Now)
				if err != nil {
					t.Fatal("retained records must load over quota:", err)
				}
				defer s.close()
				if len(s.records) != 2 {
					t.Fatal("retained data lost")
				}
			} else {
				s, err := newAppDiagnosticStore(dir, 0, time.Now)
				if err != nil {
					t.Fatal(err)
				}
				_ = s.configure("owner", true, 1, false)
				for i := 0; i < 2; i++ {
					e := appTestEvent()
					r := &appDiagnosticRecord{OwnerDigest: appDiagnosticOwner("owner"), ConsentEpoch: 1, CreatedAtMs: time.Now().UnixMilli(), Finals: map[string]appDiagnosticStoredEvent{}}
					for j := 0; j < 250; j++ {
						e["eventId"] = uuid.NewString()
						r.Events = append(r.Events, appDiagnosticStoredEvent{time.Now().UnixMilli(), appJSON(e)})
					}
					if err := appDiagnosticAtomicWrite(filepath.Join(dir, appDiagnosticBucket(r.OwnerDigest, e)+".json"), appJSON(r)); err != nil {
						t.Fatal(err)
					}
				}
				s.close()
				s, err = newAppDiagnosticStore(dir, 1, time.Now)
				if err != nil {
					t.Fatal("retained records must load over quota:", err)
				}
				defer s.close()
				if len(s.records) != 2 {
					t.Fatal("retained data lost")
				}
			}
		})
	}
}

// Identical synthetic workload on baseline and candidate; setup is outside timer.
func BenchmarkHotfixQuotaRetry(b *testing.B) {
	for _, count := range []int{40, 829} {
		b.Run(fmt.Sprint(count), func(b *testing.B) {
			s, err := newCallDiagnosticStore(b.TempDir(), 0, time.Now)
			if err != nil {
				b.Fatal(err)
			}
			defer s.close()
			_ = s.configure("owner", true, false, 1)
			for i := 0; i < count; i++ {
				key := uuid.NewString()
				owner := diagnosticPrivateKey("other")
				if i < 20 {
					owner = diagnosticPrivateKey("owner")
				}
				r := &callDiagnosticRecord{Owner: owner, CreatedAtMs: time.Now().UnixMilli(), DropAccountingVersion: 1}
				for j := 0; j < 100; j++ {
					r.Events = append(r.Events, callDiagnosticStoredEvent{time.Now().UnixMilli(), diagnosticTestEvent(key, "flutter", "attempt", "start")})
				}
				s.records[key] = r
			}
			if indexed, ok := any(s).(interface{ rebuildByteIndexesLocked() }); ok {
				indexed.rebuildByteIndexesLocked()
			}
			s.quota = 1
			raw := diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start")
			b.ReportAllocs()
			b.ResetTimer()
			for n := 0; n < b.N; n++ {
				if s.appendEventResult("owner", raw, false, 1) != callDiagnosticAppendRetry {
					b.Fatal("must retry")
				}
			}
		})
	}
}

func hotfixAssertCallIndex(t *testing.T, s *callDiagnosticStore) {
	t.Helper()
	total := 0
	reserved := 0
	owners := map[string]int{}
	ownerReserves := map[string]int{}
	for key, r := range s.records {
		raw := appJSON(r)
		total += len(raw)
		// Compute the full expected binding shape independently of the index helper.
		bound := *r
		bound.Participants = append([]string(nil), r.Participants...)
		bound.Bindings = append([]string(nil), r.Bindings...)
		if bound.HandleDigest == "" {
			bound.HandleDigest = strings.Repeat("0", 64)
		}
		for len(bound.Participants) < 1 {
			bound.Participants = append(bound.Participants, strings.Repeat("0", 64))
		}
		for len(bound.Bindings) < 2 {
			bound.Bindings = append(bound.Bindings, strings.Repeat("0", 64))
		}
		reservation := max(0, len(appJSON(&bound))-len(raw))
		if isCallDiagnosticRuntimeKey(key) {
			reservation = 0
		}
		ownerReserves[r.Owner] += reservation
		reserved += reservation
		if s.bindingReserves[key] != reservation {
			t.Fatal("binding reservation index mismatch")
		}
		owners[r.Owner] += len(raw)
		if s.sizes[key] != len(raw) {
			t.Fatalf("record byte index mismatch: %d != %d", s.sizes[key], len(raw))
		}
	}
	for owner, reserve := range ownerReserves {
		if s.ownerBindingReserves[owner] != reserve {
			t.Fatal("owner binding reserve mismatch")
		}
	}
	for owner, reserve := range s.ownerBindingReserves {
		if ownerReserves[owner] != reserve {
			t.Fatal("stale owner binding reserve")
		}
	}
	if len(s.bindingReserves) != len(s.records) {
		t.Fatal("stale binding reserve")
	}
	if s.bindingReserved != reserved {
		t.Fatal("total binding reserve mismatch")
	}
	if s.usedBytes != total || !reflect.DeepEqual(s.ownerSizes, owners) || len(s.sizes) != len(s.records) {
		t.Fatalf("canonical byte index mismatch: used=%d want=%d owners=%v want=%v", s.usedBytes, total, s.ownerSizes, owners)
	}
}
func TestHotfixCallIndexLifecycle(t *testing.T) {
	dir := t.TempDir()
	now := time.Now()
	s, err := newCallDiagnosticStore(dir, 0, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if s != nil {
			s.close()
		}
	}()
	_ = s.configure("owner", true, false, 1)
	_ = s.configure("recipient", true, false, 1)
	trace := uuid.NewString()
	first := diagnosticTestEvent(trace, "flutter", "attempt", "start")
	runtime := runtimeDiagnosticTestEvent(uuid.NewString(), "ios", "publish", "ok")
	for _, raw := range []json.RawMessage{first, runtime} {
		if !s.appendEvent("owner", raw, false, 1) {
			t.Fatal("seed")
		}
		hotfixAssertCallIndex(t, s)
	}
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("owner", d, 1) {
		t.Fatal("prepare")
	}
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	hotfixAssertCallIndex(t, s)
	saved := appJSON(s.records)
	used := s.usedBytes
	s.write = func(string, []byte) error { return fmt.Errorf("injected persistence failure") }
	if s.appendEventResult("recipient", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) != callDiagnosticAppendRetry {
		t.Fatal("failure ACK")
	}
	if used != s.usedBytes || !bytes.Equal(saved, appJSON(s.records)) {
		t.Fatal("failed write changed committed state")
	}
	hotfixAssertCallIndex(t, s)
	s.write = appDiagnosticAtomicWrite
	if !s.appendEvent("recipient", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
		t.Fatal("participant recovery")
	}
	hotfixAssertCallIndex(t, s)
	saved = appJSON(s.records)
	s.close()
	s, err = newCallDiagnosticStore(dir, 0, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	hotfixAssertCallIndex(t, s)
	if !bytes.Equal(saved, appJSON(s.records)) || s.resolve("recipient", "handle") != trace {
		t.Fatal("restart changed records/authority")
	}
	if !s.appendEvent("owner", first, false, 1) || !s.appendEvent("owner", runtime, false, 1) {
		t.Fatal("restart duplicate")
	}
	hotfixAssertCallIndex(t, s)
	if err = s.clearActor("recipient", 2); err != nil {
		t.Fatal(err)
	}
	if len(s.records) != 1 {
		t.Fatal("participant erase must retain unrelated runtime")
	}
	hotfixAssertCallIndex(t, s)
	now = now.Add(15 * 24 * time.Hour)
	s.mu.Lock()
	s.expireLocked()
	s.mu.Unlock()
	hotfixAssertCallIndex(t, s)
	if len(s.records) != 0 {
		t.Fatal("expiry")
	}
}
func TestHotfixBindingPersistenceRollback(t *testing.T) {
	s := hotfixCall(t)
	trace := uuid.NewString()
	if !s.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
		t.Fatal("seed")
	}
	before := appJSON(s.records)
	s.write = func(string, []byte) error { return fmt.Errorf("injected") }
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("owner", d, 1) {
		t.Fatal("prepare")
	}
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	if !bytes.Equal(before, appJSON(s.records)) {
		t.Fatal("failed binding mutated record")
	}
	hotfixAssertCallIndex(t, s)
	if s.resolve("owner", "handle") != trace {
		t.Fatal("failed diagnostic write lost business authority")
	}
	s.write = appDiagnosticAtomicWrite
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	hotfixAssertCallIndex(t, s)
}
func TestHotfixEraseAndExpiryRemoveFailure(t *testing.T) {
	for _, op := range []string{"erase", "expiry"} {
		t.Run(op, func(t *testing.T) {
			s := hotfixCall(t)
			trace := uuid.NewString()
			if !s.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
				t.Fatal("seed")
			}
			s.remove = func(string) error { return fmt.Errorf("injected removal failure") }
			if op == "erase" {
				if s.clearActor("owner", 2) == nil {
					t.Fatal("erase must report removal failure")
				}
			} else {
				s.now = func() time.Time { return time.Now().Add(15 * 24 * time.Hour) }
				s.mu.Lock()
				s.expireLocked()
				s.mu.Unlock()
			}
			if len(s.records) != 1 {
				t.Fatal("failed removal lost retained index")
			}
			hotfixAssertCallIndex(t, s)
			s.remove = os.Remove
			if op == "erase" {
				if err := s.clearActor("owner", 2); err != nil {
					t.Fatal(err)
				}
			} else {
				s.mu.Lock()
				s.expireLocked()
				s.mu.Unlock()
			}
			if len(s.records) != 0 {
				t.Fatal("removal retry")
			}
			hotfixAssertCallIndex(t, s)
		})
	}
}
func TestHotfixReservedOwnerPressure(t *testing.T) {
	t.Run("call", func(t *testing.T) {
		s := hotfixCall(t)
		trace := uuid.NewString()
		s.ownerQuota = 48 << 10
		d := &callDiagnosticContext{TraceID: trace}
		if !s.prepare("owner", d, 1) {
			t.Fatal("prepare")
		}
		s.bindCommitted("owner", "recipient", "handle", d)
		s.flush()
		for i := 0; i < 1000; i++ {
			if !s.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
				break
			}
		}
		_ = s.configure("recipient", true, false, 1)
		for _, actor := range []string{"owner", "recipient"} {
			media := map[string]any{}
			_ = json.Unmarshal(diagnosticTestEvent(trace, "flutter", "media", "snapshot"), &media)
			media["role"] = "callee"
			media["outcome"] = "media_flow_verified"
			media["values"] = map[string]any{"mediaFlowVerified": true}
			if !s.appendEvent(actor, appJSON(media), false, 1) {
				t.Fatal("ordinary owner pressure consumed first-media headroom")
			}
			if !s.appendEvent(actor, diagnosticTestEvent(trace, "flutter", "terminal", "finish"), false, 1) {
				t.Fatal("ordinary owner pressure consumed terminal headroom")
			}
		}
		hotfixAssertCallIndex(t, s)
	})
	t.Run("app", func(t *testing.T) {
		s := appTestStore(t)
		_ = s.configure("owner", true, 1, false)
		s.ownerQuota = 32 << 10
		e := appTestEvent()
		for i := 0; i < 1000; i++ {
			e["eventId"] = uuid.NewString()
			if status, _ := s.append("owner", 1, appJSON(e)); status != "accepted" {
				break
			}
		}
		e["eventId"] = uuid.NewString()
		e["stage"] = "finish"
		appExpect(t, s, "owner", 1, e, "accepted", "none")
	})
}

func TestHotfixAmbiguousPersistenceRollback(t *testing.T) {
	for _, existing := range []bool{false, true} {
		t.Run(fmt.Sprint(existing), func(t *testing.T) {
			s := hotfixCall(t)
			trace := uuid.NewString()
			first := diagnosticTestEvent(trace, "flutter", "attempt", "start")
			if existing && !s.appendEvent("owner", first, false, 1) {
				t.Fatal("seed")
			}
			before := appJSON(s.records)
			path := filepath.Join(s.dir, trace+".json")
			old, _ := os.ReadFile(path)
			once := true
			s.write = func(path string, raw []byte) error {
				if err := appDiagnosticAtomicWrite(path, raw); err != nil {
					return err
				}
				if once {
					once = false
					return fmt.Errorf("injected directory sync failure after rename")
				}
				return nil
			}
			if s.appendEventResult("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) != callDiagnosticAppendRetry {
				t.Fatal("uncertain write acknowledged")
			}
			disk, err := os.ReadFile(path)
			if existing {
				if err != nil || !bytes.Equal(old, disk) {
					t.Fatal("failed publication not rolled back on disk")
				}
			} else if !os.IsNotExist(err) {
				t.Fatal("failed first publication left a file")
			}
			if !bytes.Equal(before, appJSON(s.records)) {
				t.Fatal("failed publication changed memory")
			}
			hotfixAssertCallIndex(t, s)
		})
	}
}
func TestHotfixMetricsOrigins(t *testing.T) {
	s := hotfixCall(t)
	s.quota = 1
	before := testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", "upload", "global_bytes"))
	data := hotfixUpload(t, s, "owner", 1, diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start"))
	if data["reason"] != "sink_unavailable" || len(data["acceptedEventIds"].([]any)) != 0 || len(data["rejectedEventIds"].([]any)) != 0 {
		t.Fatal("legacy retry shape changed")
	}
	if testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", "upload", "global_bytes")) != before+1 {
		t.Fatal("missing detailed quota counter")
	}
	s.quota = callDiagnosticGlobalBytes
	s.write = func(string, []byte) error { return fmt.Errorf("injected") }
	before = testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", "authority", "persistence"))
	d := &callDiagnosticContext{OperationID: uuid.NewString()}
	if !s.prepare("owner", d, 1) {
		t.Fatal("prepare")
	}
	s.authorityChange("owner", "target", d, "endpoint")
	s.flush()
	if testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", "authority", "persistence")) != before+1 {
		t.Fatal("missing authority persistence counter")
	}
	// A blocked worker gives deterministic saturation without a timing race.
	s.write = appDiagnosticAtomicWrite
	entered, release := make(chan struct{}), make(chan struct{})
	s.enqueueSource("span", func() { close(entered); <-release })
	<-entered
	for i := 0; i < cap(s.queue); i++ {
		s.enqueueSource("span", func() {})
	}
	before = testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", "binding", "queue_full"))
	s.enqueueSource("binding", func() { t.Error("full queue ran job") })
	close(release)
	s.flush()
	if testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", "binding", "queue_full")) != before+1 {
		t.Fatal("missing queue origin")
	}
}

func TestHotfixPendingRepairCannotResurrectAfterClear(t *testing.T) {
	s := appTestStore(t)
	_ = s.configure("owner", true, 1, false)
	e := appTestEvent()
	appExpect(t, s, "owner", 1, e, "accepted", "none")
	// Both attempted publication and restoration fail. Clear must settle or erase
	// the repair obligation, so a later upload cannot restore erased old bytes.
	s.write = func(string, []byte) error { return fmt.Errorf("injected") }
	e["eventId"] = uuid.NewString()
	appExpect(t, s, "owner", 1, e, "retry", "sink_unavailable")
	s.write = appDiagnosticAtomicWrite
	if err := s.configure("owner", true, 2, true); err != nil {
		t.Fatal(err)
	}
	e = appTestEvent()
	appExpect(t, s, "owner", 2, e, "accepted", "none")
	files, _ := filepath.Glob(filepath.Join(s.dir, "*.json"))
	if len(files) != 2 {
		t.Fatalf("erased record resurrected: files=%d", len(files))
	}
}
func TestHotfixInterruptedCallEraseRestart(t *testing.T) {
	dir := t.TempDir()
	s, err := newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	_ = s.configure("owner", true, false, 1)
	_ = s.configure("recipient", true, false, 1)
	trace := uuid.NewString()
	raw := diagnosticTestEvent(trace, "flutter", "attempt", "start")
	if !s.appendEvent("owner", raw, false, 1) {
		t.Fatal("seed")
	}
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("owner", d, 1) {
		t.Fatal("prepare")
	}
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	s.remove = func(string) error { return fmt.Errorf("injected") }
	if s.clearActor("recipient", 2) == nil {
		t.Fatal("erase must fail")
	}
	if s.appendEvent("owner", raw, false, 1) {
		t.Fatal("pending participant erase must block duplicate ACK")
	}
	s.close()
	s, err = newCallDiagnosticStore(dir, 0, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer s.close()
	if len(s.records) != 0 || s.resolve("owner", "handle") != "" {
		t.Fatal("restart resurrected interrupted participant erase")
	}
	hotfixAssertCallIndex(t, s)
}
func TestHotfixAppExpirationDeadline(t *testing.T) {
	s := appTestStore(t)
	now := time.Now()
	s.now = func() time.Time { return now }
	_ = s.configure("owner", true, 1, false)
	e := appTestEvent()
	e["occurredAtMs"] = now.UnixMilli()
	appExpect(t, s, "owner", 1, e, "accepted", "none")
	deadline := s.nextExpiryMs
	if deadline != now.UnixMilli()+appDiagnosticRetention.Milliseconds()+1 {
		t.Fatal("expiry deadline not derived from retained timestamps")
	}
	now = now.Add(appDiagnosticRetention)
	appExpect(t, s, "owner", 1, e, "accepted", "none")
	now = now.Add(time.Millisecond)
	e["occurredAtMs"] = now.UnixMilli()
	e["eventId"] = uuid.NewString()
	appExpect(t, s, "owner", 1, e, "retry", "diagnostics_disabled")
	if len(s.records) != 0 || len(s.sizes) != 0 || s.usedBytes != 0 {
		t.Fatal("deadline did not purge records/indexes")
	}
}
func BenchmarkHotfixAppDuplicate(b *testing.B) {
	for _, count := range []int{40, 10000} {
		b.Run(fmt.Sprint(count), func(b *testing.B) {
			now := time.Now()
			s, err := newAppDiagnosticStore(b.TempDir(), 0, func() time.Time { return now })
			if err != nil {
				b.Fatal(err)
			}
			defer s.close()
			_ = s.configure("owner", true, 1, false)
			var event map[string]any
			for i := 0; i < count; i++ {
				event = appTestEvent()
				r := &appDiagnosticRecord{OwnerDigest: appDiagnosticOwner("owner"), ConsentEpoch: 1, CreatedAtMs: now.UnixMilli(), Events: []appDiagnosticStoredEvent{{now.UnixMilli(), appJSON(event)}}, Finals: map[string]appDiagnosticStoredEvent{}}
				key := appDiagnosticBucket(r.OwnerDigest, event)
				s.records[key] = r
				s.indexRecord(key, r)
			}
			raw := appJSON(event)
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				if status, _ := s.append("owner", 1, raw); status != "accepted" {
					b.Fatal(status)
				}
			}
		})
	}
}

func TestHotfixCallRefusalReasons(t *testing.T) {
	for _, reason := range []string{"owner_bytes", "global_bytes", "record_count", "record_bytes", "consent", "epoch", "conflict", "persistence"} {
		t.Run(reason, func(t *testing.T) {
			s := hotfixCall(t)
			trace := uuid.NewString()
			raw := diagnosticTestEvent(trace, "flutter", "attempt", "start")
			epoch := int64(1)
			if reason == "record_bytes" || reason == "conflict" {
				if !s.appendEvent("owner", raw, false, 1) {
					t.Fatal("seed")
				}
			}
			switch reason {
			case "owner_bytes":
				s.ownerQuota = 1
			case "global_bytes":
				s.quota = 1
			case "record_count":
				for i := 0; i < 10000; i++ {
					s.records[fmt.Sprint(i)] = &callDiagnosticRecord{Owner: diagnosticPrivateKey("other")}
				}
				s.rebuildByteIndexesLocked()
			case "record_bytes":
				r := s.records[trace]
				r.LegacyDropAttempts = 0
				r.Summaries["synthetic-record-capacity"] = callDiagnosticStoredEvent{Event: appJSON(map[string]any{"legacy": strings.Repeat("x", callDiagnosticRecordBytes)})}
				s.rebuildByteIndexesLocked()
				raw = diagnosticTestEvent(trace, "flutter", "attempt", "start")
			case "consent":
				if err := s.configure("owner", false, false, 2); err != nil {
					t.Fatal(err)
				}
				epoch = 2
			case "epoch":
				epoch = 2
			case "conflict":
				var event map[string]any
				_ = json.Unmarshal(raw, &event)
				event["reason"] = "timeout"
				raw = appJSON(event)
			case "persistence":
				s.write = func(string, []byte) error { return fmt.Errorf("injected") }
			}
			before := testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", "upload", reason))
			result := s.appendEventResult("owner", raw, false, epoch)
			if result == callDiagnosticAppendAccepted {
				t.Fatal("refusal accepted")
			}
			if testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", "upload", reason)) != before+1 {
				t.Fatal("missing exact reason")
			}
		})
	}
}
func TestHotfixEffectiveLimitMetricsAndPrivacy(t *testing.T) {
	t.Setenv("APP_DIAGNOSTICS_DIR", t.TempDir())
	t.Setenv("CALL_DIAGNOSTICS_DIR", t.TempDir())
	t.Setenv("APP_DIAGNOSTICS_OWNER_MAX_BYTES", "16777216")
	t.Setenv("CALL_DIAGNOSTICS_OWNER_MAX_BYTES", "10485760")
	a, c := initAppDiagnosticsFromEnvironment(), initCallDiagnosticsFromEnvironment()
	if a == nil || c == nil {
		t.Fatal("init")
	}
	defer a.close()
	defer c.close()
	if a.ownerQuota != 16<<20 || c.ownerQuota != 10<<20 || a.quota != 128<<20 || c.quota != 64<<20 {
		t.Fatal("effective limits")
	}
	for _, tc := range []struct {
		store         string
		owner, global int
	}{{"app", 16 << 20, 128 << 20}, {"call", 10 << 20, 64 << 20}} {
		if testutil.ToFloat64(diagnosticOwnerLimit.WithLabelValues(tc.store)) != float64(tc.owner) || testutil.ToFloat64(diagnosticGlobalLimit.WithLabelValues(tc.store)) != float64(tc.global) {
			t.Fatal("metric not effective numeric value")
		}
	}
	diagnosticRefusal("private-owner", "private-peer", "private-trace")
	families, err := prometheus.DefaultGatherer.Gather()
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range families {
		if !strings.HasPrefix(f.GetName(), "relay_diagnostics_") {
			continue
		}
		for _, m := range f.Metric {
			for _, label := range m.Label {
				for _, secret := range []string{"private-owner", "private-peer", "private-trace"} {
					if strings.Contains(label.GetValue(), secret) {
						t.Fatal("private label escaped fixed vocabulary")
					}
				}
			}
		}
	}
}

func TestHotfixParticipantUsesOriginalOwnerBudget(t *testing.T) {
	s := hotfixCall(t)
	_ = s.configure("recipient", true, false, 1)
	trace := uuid.NewString()
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("owner", d, 1) {
		t.Fatal("prepare")
	}
	s.quota = 1
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	if len(s.records) != 0 {
		t.Fatal("binding fixture persisted over quota")
	}
	s.quota = callDiagnosticGlobalBytes
	// A retained over-cap runtime partition belongs only to the participant.
	key := "runtime-" + diagnosticPrivateKey("retained-recipient")
	r := &callDiagnosticRecord{Owner: diagnosticPrivateKey("recipient"), CreatedAtMs: time.Now().UnixMilli(), DropAccountingVersion: 1}
	raw := runtimeDiagnosticTestEvent(uuid.NewString(), "ios", "publish", "ok")
	for i := 0; i < 200; i++ {
		r.Events = append(r.Events, callDiagnosticStoredEvent{time.Now().UnixMilli(), raw})
	}
	s.records[key] = r
	s.rebuildByteIndexesLocked()
	s.ownerQuota = 64 << 10
	if !s.appendEvent("recipient", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
		t.Fatal("participant's unrelated pressure blocked original-owner budget")
	}
	if s.records[trace].Owner != diagnosticPrivateKey("owner") {
		t.Fatal("charged participant instead of original owner")
	}
	hotfixAssertCallIndex(t, s)
}

func TestHotfixClearPreservesCapabilityInvalidation(t *testing.T) {
	s := hotfixCall(t)
	if err := s.configure("owner", true, true, 2); err != nil {
		t.Fatal(err)
	}
	s.write = func(path string, raw []byte) error {
		if filepath.Base(path) == "private.json" {
			var state callDiagnosticPrivateState
			if json.Unmarshal(raw, &state) != nil {
				t.Fatal("state")
			}
			c := state.Consent[diagnosticPrivateKey("owner")]
			if c.ConsentEpoch == 3 && !c.ErasePending {
				s.invalidateLegacyPushCapability("owner")
			}
		}
		return appDiagnosticAtomicWrite(path, raw)
	}
	if err := s.clearActor("owner", 3); err != nil {
		t.Fatal(err)
	}
	s.metaMu.Lock()
	capable := s.consentMetadata[diagnosticPrivateKey("owner")].PushCapability
	s.metaMu.Unlock()
	if capable {
		t.Fatal("erase completion undid concurrent capability invalidation")
	}
}
func TestHotfixBindingReservationFitsHardLimits(t *testing.T) {
	for _, limit := range []string{"owner", "global"} {
		t.Run(limit, func(t *testing.T) {
			s := hotfixCall(t)
			trace := uuid.NewString()
			if !s.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
				t.Fatal("seed")
			}
			budget := s.usedBytes + s.bindingReserved
			if limit == "owner" {
				s.ownerQuota = budget
			} else {
				s.quota = budget
			}
			d := &callDiagnosticContext{TraceID: trace}
			if !s.prepare("owner", d, 1) {
				t.Fatal("prepare")
			}
			s.bindCommitted("owner", "recipient", "handle", d)
			s.flush()
			if len(s.records[trace].Bindings) != 2 || s.usedBytes > budget || s.bindingReserved != 0 {
				t.Fatal("binding did not consume its accounted reservation")
			}
			hotfixAssertCallIndex(t, s)
		})
	}
}

func TestHotfixEmptyBindingRecordAppendRollback(t *testing.T) {
	s := hotfixCall(t)
	trace := uuid.NewString()
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("owner", d, 1) {
		t.Fatal("prepare")
	}
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	before := appJSON(s.records[trace])
	s.quota = 1
	if s.appendEventResult("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) != callDiagnosticAppendRetry {
		t.Fatal("quota")
	}
	if !bytes.Equal(before, appJSON(s.records[trace])) {
		t.Fatal("rollback changed empty committed event array")
	}
	hotfixAssertCallIndex(t, s)
}
func TestHotfixSaturatedDiscardCannotPublishUnpersistedBinding(t *testing.T) {
	s := hotfixCall(t)
	trace := uuid.NewString()
	raw := diagnosticTestEvent(trace, "flutter", "attempt", "start")
	if !s.appendEvent("owner", raw, false, 1) {
		t.Fatal("seed")
	}
	r := s.records[trace]
	for len(r.Events) < callDiagnosticTraceEvents {
		r.Events = append(r.Events, r.Events[0])
	}
	for len(r.DiscardedEventIDs) < callDiagnosticDiscardIDLimit {
		r.DiscardedEventIDs = append(r.DiscardedEventIDs, uuid.NewString())
	}
	r.DiscardLedgerSaturated = true
	s.rebuildByteIndexesLocked()
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("owner", d, 1) {
		t.Fatal("prepare")
	}
	s.quota = 1
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	before := appJSON(r)
	if s.appendEventResult("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) != callDiagnosticAppendDiscarded {
		t.Fatal("saturated discard")
	}
	if !bytes.Equal(before, appJSON(r)) {
		t.Fatal("saturated retry published unpersisted metadata")
	}
	hotfixAssertCallIndex(t, s)
}

// Correction cycle 1: each regression below was run against the inherited v1
// production bytes before any production correction.
func TestHotfixCorrectionR1ExpiredAuthorityQuarantine(t *testing.T) {
	s := hotfixCall(t)
	now := time.Now()
	s.now = func() time.Time { return now }
	for _, actor := range []string{"owner", "recipient"} {
		if err := s.configure(actor, true, true, 2); err != nil {
			t.Fatal(err)
		}
	}
	trace := uuid.NewString()
	raw := diagnosticTestEvent(trace, "flutter", "attempt", "start")
	if !s.appendEvent("owner", raw, false, 2) {
		t.Fatal("seed")
	}
	d := &callDiagnosticContext{TraceID: trace}
	if !s.prepare("owner", d, 2) {
		t.Fatal("prepare")
	}
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	before, err := os.ReadFile(filepath.Join(s.dir, trace+".json"))
	if err != nil {
		t.Fatal(err)
	}
	used := s.usedBytes
	now = now.Add(callDiagnosticRetention + time.Millisecond)
	for _, actor := range []string{"owner", "recipient"} {
		if err := s.configure(actor, true, true, 2); err != nil {
			t.Fatal(err)
		}
	}
	s.remove = func(string) error { return fmt.Errorf("injected expiry removal failure") }
	s.mu.Lock()
	s.expireLocked()
	s.mu.Unlock()
	for _, actor := range []string{"owner", "recipient"} {
		if s.authorizedLocked(actor, trace) {
			t.Error("expired trace remains authorized")
		}
		if s.resolve(actor, "handle") != "" {
			t.Error("expired trace resolves")
		}
		if s.pushTrace(actor, "handle") != nil {
			t.Error("expired trace leaks to push")
		}
		if s.prepare(actor, &callDiagnosticContext{TraceID: trace}, 2) {
			t.Error("expired trace admits prepare")
		}
		for _, event := range []json.RawMessage{raw, diagnosticTestEvent(trace, "flutter", "attempt", "start")} {
			data := hotfixUpload(t, s, actor, 2, event)
			if len(data["acceptedEventIds"].([]any)) != 0 {
				t.Error("expired trace ACKs upload")
			}
		}
	}
	s.bindCommitted("owner", "recipient", "handle", d)
	s.flush()
	if s.appendEventResult("owner", diagnosticTestEvent(trace, "relay", "signaling", "store"), true, 2) != callDiagnosticAppendRetry {
		t.Error("expired trace admits server span")
	}
	after, err := os.ReadFile(filepath.Join(s.dir, trace+".json"))
	if err != nil || !bytes.Equal(before, after) || s.usedBytes != used {
		t.Error("failed cleanup changed retained bytes/accounting")
	}
	hotfixAssertCallIndex(t, s)
	s.remove = os.Remove
	s.mu.Lock()
	s.expireLocked()
	s.mu.Unlock()
	if len(s.records) != 0 || s.usedBytes != 0 || s.resolve("owner", "handle") != "" {
		t.Error("cleanup retry did not release bytes and authority")
	}
	hotfixAssertCallIndex(t, s)
}

func TestHotfixCorrectionR2InterruptedEraseOrigins(t *testing.T) {
	for _, op := range []string{"clear", "disable"} {
		t.Run(op, func(t *testing.T) {
			s := hotfixCall(t)
			if err := s.configure("reader", true, false, 1); err != nil {
				t.Fatal(err)
			}
			trace := uuid.NewString()
			if !s.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
				t.Fatal("seed")
			}
			d := &callDiagnosticContext{OperationID: uuid.NewString(), Reason: "calls_disabled"}
			if !s.prepare("owner", d, 1) {
				t.Fatal("prepare")
			}
			s.authorityChange("owner", "target", d, "endpoint")
			s.flush()
			if s.lastAuthority("target").OperationID != d.OperationID {
				t.Fatal("seed origin")
			}
			queued := *d
			queued.OperationID = uuid.NewString()
			entered, release := make(chan struct{}), make(chan struct{})
			s.enqueueSource("authority", func() { close(entered); <-release })
			<-entered
			s.authorityChange("owner", "queued-target", &queued, "endpoint")
			s.remove = func(string) error { return fmt.Errorf("injected erase failure") }
			var err error
			if op == "clear" {
				err = s.clearActor("owner", 1)
			} else {
				err = s.configure("owner", false, false, 2)
			}
			close(release)
			s.flush()
			if err == nil || !s.state.Consent[diagnosticPrivateKey("owner")].ErasePending {
				t.Fatal("erase was not interrupted")
			}
			if s.lastAuthority("target").OperationID != "" {
				t.Error("erased origin still readable")
			}
			if _, ok := s.state.Authority[diagnosticPrivateKey("queued-target", "endpoint")]; ok {
				t.Error("queued same-epoch origin published during erase")
			}
			reader := callDiagnosticContext{TraceID: uuid.NewString(), OperationID: uuid.NewString()}
			if !s.prepare("reader", &reader, 1) {
				t.Fatal("reader prepare")
			}
			span := newCallDiagnosticSpan(s, "reader", reader, callEndpointGetAction)
			span.result(callControlWireRequest{Action: callEndpointGetAction, AccountPeerID: "target"}, callControlWireResponse{Status: "OK", Found: true}, nil)
			s.flush()
			if span.diagnostics.ParentOperationID != "" {
				t.Error("lookup inherited erased actor ID")
			}
			record := s.records[reader.TraceID]
			if record == nil || len(record.Events) == 0 {
				t.Fatal("reader lookup did not emit")
			}
			if strings.Contains(string(appJSON(record)), d.OperationID) || strings.Contains(string(appJSON(record)), queued.OperationID) {
				t.Error("another actor received erased-origin ID")
			}
			s.remove = os.Remove
			if err := s.clearActor("owner", 2); err != nil {
				t.Fatal(err)
			}
			if s.lastAuthority("target").OperationID != "" {
				t.Fatal("origin survived recovery")
			}
			hotfixAssertCallIndex(t, s)
		})
	}
}

func TestHotfixCorrectionR3RollbackRemovalDurability(t *testing.T) {
	for _, kind := range []string{"app", "call"} {
		t.Run(kind, func(t *testing.T) {
			// /dev/null opens successfully but fsync fails. Substitute it for the
			// parent only while repair synchronizes: this injects a real sync failure.
			dir := t.TempDir()
			moved := dir + "-held"
			broken := false
			restore := func() {
				if broken {
					if err := os.Remove(dir); err != nil {
						t.Fatal(err)
					}
					if err := os.Rename(moved, dir); err != nil {
						t.Fatal(err)
					}
					broken = false
				}
			}
			defer restore()
			remove := func(path string) error {
				restore()
				err := os.Remove(path)
				if err != nil && !os.IsNotExist(err) {
					return err
				}
				if e := os.Rename(dir, moved); e != nil {
					t.Fatal(e)
				}
				if e := os.Symlink("/dev/null", dir); e != nil {
					t.Fatal(e)
				}
				broken = true
				return err
			}
			var pending **diagnosticRepair
			var retry func() bool
			var fail func()
			if kind == "call" {
				s, err := newCallDiagnosticStore(dir, 0, time.Now)
				if err != nil {
					t.Fatal(err)
				}
				defer s.close()
				if err := s.configure("owner", true, false, 1); err != nil {
					t.Fatal(err)
				}
				first := diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start")
				if !s.appendEvent("owner", first, false, 1) {
					t.Fatal("seed")
				}
				pending = &s.pendingWrite
				s.remove = remove
				s.write = func(path string, raw []byte) error {
					if err := appDiagnosticAtomicWrite(path, raw); err != nil {
						return err
					}
					return fmt.Errorf("ambiguous first publication")
				}
				fail = func() {
					if s.appendEventResult("owner", diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start"), false, 1) != callDiagnosticAppendRetry {
						t.Fatal("failed write ACK")
					}
				}
				retry = func() bool { return s.appendEvent("owner", first, false, 1) }
			} else {
				s, err := newAppDiagnosticStore(dir, 0, time.Now)
				if err != nil {
					t.Fatal(err)
				}
				defer s.close()
				if err := s.configure("owner", true, 1, false); err != nil {
					t.Fatal(err)
				}
				first := appTestEvent()
				appExpect(t, s, "owner", 1, first, "accepted", "none")
				pending = &s.pendingWrite
				s.remove = remove
				s.write = func(path string, raw []byte) error {
					if err := appDiagnosticAtomicWrite(path, raw); err != nil {
						return err
					}
					return fmt.Errorf("ambiguous first publication")
				}
				fail = func() { appExpect(t, s, "owner", 1, appTestEvent(), "retry", "sink_unavailable") }
				retry = func() bool { disposition, _ := s.append("owner", 1, appJSON(first)); return disposition == "accepted" }
			}
			fail()
			if *pending == nil {
				t.Error("rollback cleared obligation before directory sync")
			}
			restore()
			if retry() {
				t.Error("duplicate ACK before durable rollback removal")
			}
			if *pending == nil {
				t.Error("already-absent retry lost sync obligation")
			}
			restore()
			if err := repairDiagnosticWrite(pending, appDiagnosticAtomicWrite, os.Remove); err != nil {
				t.Fatal(err)
			}
			if *pending != nil || !retry() {
				t.Fatal("durable already-absent repair did not restore duplicate ACK")
			}
		})
	}
}

func TestHotfixCorrectionR4PendingEraseWireRetry(t *testing.T) {
	for _, erased := range []string{"owner", "recipient"} {
		t.Run(erased, func(t *testing.T) {
			s := hotfixCall(t)
			for _, actor := range []string{"recipient", "foreign"} {
				if err := s.configure(actor, true, false, 1); err != nil {
					t.Fatal(err)
				}
			}
			trace := uuid.NewString()
			raw := diagnosticTestEvent(trace, "flutter", "attempt", "start")
			if !s.appendEvent("owner", raw, false, 1) {
				t.Fatal("seed")
			}
			d := &callDiagnosticContext{TraceID: trace}
			if !s.prepare("owner", d, 1) {
				t.Fatal("prepare")
			}
			s.bindCommitted("owner", "recipient", "handle", d)
			s.flush()
			s.remove = func(string) error { return fmt.Errorf("injected erase failure") }
			if s.clearActor(erased, 1) == nil {
				t.Fatal("erase")
			}
			for _, actor := range []string{"owner", "recipient", "foreign"} {
				data := hotfixUpload(t, s, actor, 1, raw)
				if len(data["acceptedEventIds"].([]any)) != 0 {
					t.Error("pending erase ACK")
				}
				rejected := len(data["rejectedEventIds"].([]any))
				if actor == "foreign" {
					if rejected != 1 {
						t.Error("foreign actor must remain terminal")
					}
				} else if rejected != 0 || data["reason"] != "sink_unavailable" {
					t.Errorf("legitimate participant must retry: %s %v", actor, data)
				}
			}
		})
	}
}

func TestHotfixCorrectionR5EveryCapacityRefusal(t *testing.T) {
	for _, source := range []string{"upload", "span"} {
		for _, path := range []string{"new-discard", "remembered-discard", "first-saturation", "saturated"} {
			t.Run(source+"/"+path, func(t *testing.T) {
				s := hotfixCall(t)
				trace := uuid.NewString()
				raw := diagnosticTestEvent(trace, "flutter", "attempt", "start")
				if !s.appendEvent("owner", raw, false, 1) {
					t.Fatal("seed")
				}
				r := s.records[trace]
				// Small, valid stored rows isolate the event-count capacity from bytes.
				r.Events = make([]callDiagnosticStoredEvent, callDiagnosticTraceEvents)
				for i := range r.Events {
					r.Events[i] = callDiagnosticStoredEvent{Event: appJSON(map[string]any{"eventId": uuid.NewString()})}
				}
				eventSource := "flutter"
				if source == "span" {
					eventSource = "relay"
				}
				event := diagnosticTestEvent(trace, eventSource, "signaling", "store")
				var fields map[string]any
				_ = json.Unmarshal(event, &fields)
				if path == "remembered-discard" {
					r.DiscardedEventIDs = []string{fields["eventId"].(string)}
					r.Dropped = 1
				}
				if path == "first-saturation" || path == "saturated" {
					for i := 0; i < callDiagnosticDiscardIDLimit; i++ {
						r.DiscardedEventIDs = append(r.DiscardedEventIDs, uuid.NewString())
					}
					r.Dropped = callDiagnosticDiscardIDLimit
					r.DiscardLedgerSaturated = path == "saturated"
				}
				if err := s.persistLocked(trace); err != nil {
					t.Fatal(err)
				}
				dropped := r.Dropped
				before := testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", source, "record_capacity"))
				writes := 0
				s.write = func(path string, raw []byte) error { writes++; return appDiagnosticAtomicWrite(path, raw) }
				for i := 0; i < 2; i++ {
					if s.appendEventResult("owner", event, source == "span", 1) != callDiagnosticAppendDiscarded {
						t.Fatal("capacity disposition")
					}
				}
				if got := testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", source, "record_capacity")); got != before+2 {
					t.Errorf("every refusal must count: delta=%v", got-before)
				}
				wantWrites := 0
				if path == "new-discard" {
					dropped++
					wantWrites = 1
				}
				if path == "first-saturation" {
					wantWrites = 1
				}
				if r.Dropped != dropped || writes != wantWrites {
					t.Fatalf("distinct loss/persistence changed: dropped=%d writes=%d", r.Dropped, writes)
				}
				hotfixAssertCallIndex(t, s)
			})
		}
	}
}

func TestHotfixCorrectionR6PurgeFailureSource(t *testing.T) {
	for _, source := range []string{"configure", "clear", "maintenance"} {
		for _, failure := range []string{"remove", "private"} {
			t.Run(source+"/"+failure, func(t *testing.T) {
				s := hotfixCall(t)
				trace := uuid.NewString()
				if !s.appendEvent("owner", diagnosticTestEvent(trace, "flutter", "attempt", "start"), false, 1) {
					t.Fatal("seed")
				}
				if failure == "remove" {
					s.remove = func(string) error { return fmt.Errorf("injected removal failure") }
				} else {
					s.write = func(path string, raw []byte) error {
						var state callDiagnosticPrivateState
						if filepath.Base(path) == "private.json" && json.Unmarshal(raw, &state) == nil && !state.Consent[diagnosticPrivateKey("owner")].ErasePending {
							return fmt.Errorf("injected final private write failure")
						}
						return appDiagnosticAtomicWrite(path, raw)
					}
				}
				before := map[string]float64{}
				for _, label := range []string{"configure", "clear", "maintenance"} {
					before[label] = testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", label, "persistence"))
				}
				var err error
				switch source {
				case "configure":
					err = s.configure("owner", false, false, 2)
				case "clear":
					err = s.clearActor("owner", 2)
				case "maintenance":
					s.mu.Lock()
					c := s.state.Consent[diagnosticPrivateKey("owner")]
					c.ErasePending = true
					s.state.Consent[diagnosticPrivateKey("owner")] = c
					err = s.purgeDigestLocked(diagnosticPrivateKey("owner"))
					s.mu.Unlock()
				}
				if err == nil {
					t.Fatal("fault not reached")
				}
				for label, value := range before {
					want := value
					if label == source {
						want++
					}
					if got := testutil.ToFloat64(diagnosticRefusals.WithLabelValues("call", label, "persistence")); got != want {
						t.Errorf("source %s: delta=%v want=%v", label, got-value, want-value)
					}
				}
			})
		}
	}
}

func TestHotfixCorrectionS2BoundedRetainedFile(t *testing.T) {
	for _, kind := range []string{"valid-oversized", "expired-oversized", "corrupt-oversized", "corrupt-bounded"} {
		t.Run(kind, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, uuid.NewString()+".json")
			rec := &callDiagnosticRecord{Owner: diagnosticPrivateKey("owner"), CreatedAtMs: time.Now().UnixMilli(), DropAccountingVersion: 1, Events: []callDiagnosticStoredEvent{}, Summaries: map[string]callDiagnosticStoredEvent{}}
			if kind == "expired-oversized" {
				rec.CreatedAtMs = time.Now().Add(-15 * 24 * time.Hour).UnixMilli()
			}
			raw := appJSON(rec)
			if strings.HasPrefix(kind, "corrupt") {
				raw = []byte("{")
			}
			if kind != "corrupt-bounded" {
				raw = append(raw, bytes.Repeat([]byte(" "), callDiagnosticRecordBytes+1-len(raw))...)
			}
			if err := os.WriteFile(path, raw, 0600); err != nil {
				t.Fatal(err)
			}
			s, err := newCallDiagnosticStore(dir, 1, time.Now)
			if s != nil {
				s.close()
			}
			if err == nil {
				t.Error("oversized/corrupt record must fail closed without loading")
			}
			if kind != "corrupt-bounded" && err != nil && err.Error() != "invalid diagnostic file" {
				t.Errorf("oversized record reached JSON decoding: %v", err)
			}
			after, readErr := os.ReadFile(path)
			if readErr != nil || !bytes.Equal(raw, after) {
				t.Error("startup removed/changed retained or corrupt bytes")
			}
		})
	}
}

func TestHotfixCorrectionS3OverCapRecovery(t *testing.T) {
	for _, kind := range []string{"app", "call"} {
		t.Run(kind, func(t *testing.T) {
			dir := t.TempDir()
			now := time.Now()
			clock := func() time.Time { return now }
			saved := map[string][]byte{}
			quota := 0
			if kind == "call" {
				s, err := newCallDiagnosticStore(dir, 0, clock)
				if err != nil {
					t.Fatal(err)
				}
				if err = s.configure("owner", true, false, 1); err != nil {
					t.Fatal(err)
				}
				var duplicate json.RawMessage
				for i := 0; i < 2; i++ {
					trace := uuid.NewString()
					duplicate = diagnosticTestEvent(trace, "flutter", "attempt", "start")
					if !s.appendEvent("owner", duplicate, false, 1) {
						t.Fatal("seed")
					}
					r := s.records[trace]
					for len(r.Events) < 120 {
						r.Events = append(r.Events, r.Events[0])
					}
					if err = s.persistLocked(trace); err != nil {
						t.Fatal(err)
					}
					saved[trace+".json"] = appJSON(r)
					quota = len(appJSON(r))
				}
				s.close()
				s, err = newCallDiagnosticStore(dir, quota, clock)
				if err != nil {
					t.Fatal(err)
				}
				defer s.close()
				hotfixAssertCallIndex(t, s)
				if s.usedBytes <= quota {
					t.Fatal("fixture not over quota")
				}
				if !s.appendEvent("owner", duplicate, false, 1) {
					t.Error("over-cap duplicate not ACKed")
				}
				if s.appendEventResult("owner", diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start"), false, 1) != callDiagnosticAppendRetry {
					t.Error("over-cap new write not retry")
				}
				for file, before := range saved {
					after, err := os.ReadFile(filepath.Join(dir, file))
					if err != nil || !bytes.Equal(before, after) {
						t.Fatal("retained bytes changed")
					}
				}
				now = now.Add(callDiagnosticRetention + time.Millisecond)
				if err = s.configure("owner", true, false, 1); err != nil {
					t.Fatal(err)
				}
				s.mu.Lock()
				s.expireLocked()
				s.mu.Unlock()
				hotfixAssertCallIndex(t, s)
				if s.usedBytes != 0 || len(s.records) != 0 || s.quota != quota {
					t.Fatal("expiry accounting")
				}
				if !s.appendEvent("owner", diagnosticTestEvent(uuid.NewString(), "flutter", "attempt", "start"), false, 1) {
					t.Error("expiry did not restore capacity")
				}
				hotfixAssertCallIndex(t, s)
			} else {
				s, err := newAppDiagnosticStore(dir, 0, clock)
				if err != nil {
					t.Fatal(err)
				}
				if err = s.configure("owner", true, 1, false); err != nil {
					t.Fatal(err)
				}
				var duplicate map[string]any
				for i := 0; i < 2; i++ {
					duplicate = appTestEvent()
					r := &appDiagnosticRecord{OwnerDigest: appDiagnosticOwner("owner"), ConsentEpoch: 1, CreatedAtMs: now.UnixMilli(), Finals: map[string]appDiagnosticStoredEvent{}}
					for j := 0; j < 120; j++ {
						r.Events = append(r.Events, appDiagnosticStoredEvent{now.UnixMilli(), appJSON(duplicate)})
					}
					file := appDiagnosticBucket(r.OwnerDigest, duplicate) + ".json"
					saved[file] = appJSON(r)
					quota = len(appJSON(r))
					if err := appDiagnosticAtomicWrite(filepath.Join(dir, file), appJSON(r)); err != nil {
						t.Fatal(err)
					}
				}
				s.close()
				s, err = newAppDiagnosticStore(dir, quota, clock)
				if err != nil {
					t.Fatal(err)
				}
				defer s.close()
				total := 0
				for key, r := range s.records {
					size := len(appJSON(r))
					total += size
					if s.sizes[key] != size {
						t.Error("record byte index")
					}
				}
				if s.usedBytes != total || s.ownerSizes[appDiagnosticOwner("owner")] != total || total <= quota {
					t.Fatal("over-cap byte indexes")
				}
				appExpect(t, s, "owner", 1, duplicate, "accepted", "none")
				appExpect(t, s, "owner", 1, appTestEvent(), "retry", "quota_exceeded")
				for file, before := range saved {
					after, err := os.ReadFile(filepath.Join(dir, file))
					if err != nil || !bytes.Equal(before, after) {
						t.Fatal("retained bytes changed")
					}
				}
				now = now.Add(appDiagnosticRetention + time.Millisecond)
				if err = s.configure("owner", true, 1, false); err != nil {
					t.Fatal(err)
				}
				s.mu.Lock()
				err = s.expireLocked()
				s.mu.Unlock()
				if err != nil {
					t.Fatal(err)
				}
				if s.usedBytes != 0 || len(s.records) != 0 || len(s.sizes) != 0 || s.quota != quota {
					t.Fatal("expiry accounting")
				}
				fresh := appTestEvent()
				fresh["occurredAtMs"] = now.UnixMilli()
				appExpect(t, s, "owner", 1, fresh, "accepted", "none")
			}
		})
	}
}

func TestHotfixCorrectionS4AppCachedExpiry(t *testing.T) {
	t.Run("refreshed-consent-cleanup-retry", func(t *testing.T) {
		s := appTestStore(t)
		now := time.Now()
		s.now = func() time.Time { return now }
		if err := s.configure("owner", true, 1, false); err != nil {
			t.Fatal(err)
		}
		e := appTestEvent()
		appExpect(t, s, "owner", 1, e, "accepted", "none")
		before := appJSON(s.records)
		used := s.usedBytes
		deadline := s.nextExpiryMs
		now = now.Add(appDiagnosticRetention)
		if err := s.configure("owner", true, 1, false); err != nil {
			t.Fatal(err)
		}
		if s.nextExpiryMs != deadline {
			t.Fatal("consent refresh postponed record expiry")
		}
		now = now.Add(time.Millisecond)
		s.remove = func(string) error { return fmt.Errorf("injected expiry cleanup failure") }
		fresh := appTestEvent()
		fresh["occurredAtMs"] = now.UnixMilli()
		appExpect(t, s, "owner", 1, fresh, "retry", "sink_unavailable")
		if s.nextExpiryMs > now.UnixMilli() || s.usedBytes != used || !bytes.Equal(before, appJSON(s.records)) {
			t.Fatal("cleanup failure lost deadline/accounting")
		}
		s.remove = os.Remove
		appExpect(t, s, "owner", 1, fresh, "accepted", "none")
		if len(s.records) != 1 {
			t.Fatal("expired record retained after recovery")
		}
	})
	t.Run("earlier-consent-deadline", func(t *testing.T) {
		s := appTestStore(t)
		now := time.Now()
		s.now = func() time.Time { return now }
		if err := s.configure("later", true, 1, false); err != nil {
			t.Fatal(err)
		}
		s.mu.Lock()
		if err := s.expireLocked(); err != nil {
			t.Fatal(err)
		}
		s.mu.Unlock()
		later := s.nextExpiryMs
		now = now.Add(-time.Hour)
		if err := s.configure("earlier", true, 1, false); err != nil {
			t.Fatal(err)
		}
		if s.nextExpiryMs != later-time.Hour.Milliseconds() {
			t.Fatal("new earlier consent did not lower cached deadline")
		}
	})
	t.Run("record-newer-than-expired-consent", func(t *testing.T) {
		s := appTestStore(t)
		now := time.Now()
		s.now = func() time.Time { return now }
		if err := s.configure("owner", true, 1, false); err != nil {
			t.Fatal(err)
		}
		deadline := now.Add(appDiagnosticRetention + time.Millisecond)
		now = now.Add(time.Hour)
		e := appTestEvent()
		e["occurredAtMs"] = now.UnixMilli()
		appExpect(t, s, "owner", 1, e, "accepted", "none")
		now = deadline
		s.remove = func(string) error { return fmt.Errorf("injected orphan cleanup failure") }
		fresh := appTestEvent()
		fresh["occurredAtMs"] = now.UnixMilli()
		appExpect(t, s, "owner", 1, fresh, "retry", "sink_unavailable")
		if len(s.records) != 1 || s.usedBytes == 0 || s.nextExpiryMs > now.UnixMilli() {
			t.Fatal("newer retained record/accounting or due deadline lost")
		}
		s.remove = os.Remove
		appExpect(t, s, "owner", 1, fresh, "retry", "diagnostics_disabled")
		if len(s.records) != 0 || s.usedBytes != 0 {
			t.Fatal("expired consent retained newer record")
		}
	})
}
