package main

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/axiomhq/hyperloglog"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

type b29StoreClock struct {
	mu   sync.Mutex
	at   time.Time
	hook func(time.Time) time.Time
}

func (c *b29StoreClock) now() time.Time {
	c.mu.Lock()
	at, hook := c.at, c.hook
	c.mu.Unlock()
	if hook != nil {
		return hook(at)
	}
	return at
}

func (c *b29StoreClock) set(at time.Time) {
	c.mu.Lock()
	c.at = at
	c.mu.Unlock()
}

func (c *b29StoreClock) setHook(hook func(time.Time) time.Time) {
	c.mu.Lock()
	c.hook = hook
	c.mu.Unlock()
}

func b29StoreMidnight(t *testing.T, day string) time.Time {
	t.Helper()
	at, err := activitycalendar.Parse(day)
	if err != nil {
		t.Fatal(err)
	}
	return at
}

func b29StoreKey() []byte { return bytes.Repeat([]byte{17}, 32) }

func b29NewStore(t *testing.T, clock *b29StoreClock) *activeIdentityStore {
	t.Helper()
	path := filepath.Join(t.TempDir(), "active-identities.json")
	store, err := newActiveIdentityStore(path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	if store == nil {
		t.Fatal("valid constructor returned no store")
	}
	return store
}

func b29StoreAdmit(t *testing.T, store *activeIdentityStore, day, account string) {
	t.Helper()
	if err := store.admit(day, account); err != nil {
		t.Fatal(err)
	}
}

func b29StoreAdvance(t *testing.T, store *activeIdentityStore, clock *b29StoreClock, at time.Time) {
	t.Helper()
	clock.set(at)
	if err := store.advance(); err != nil {
		t.Fatal(err)
	}
}

func b29StoreDisk(t *testing.T, path string) activeIdentityStoreDisk {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var disk activeIdentityStoreDisk
	if err := json.Unmarshal(raw, &disk); err != nil {
		t.Fatal(err)
	}
	return disk
}

func b29StoreDiskEstimate(t *testing.T, disk activeIdentityStoreDisk, day string) activeIdentityEstimate {
	t.Helper()
	sketches, err := newActiveDailySketches(b29StoreKey())
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range disk.Days {
		sketch := hyperloglog.NewNoSparse()
		if err := sketch.UnmarshalBinary(value.Sketch); err != nil {
			t.Fatal(err)
		}
		sketches.days[value.Day] = sketch
	}
	estimate, err := sketches.estimate(day)
	if err != nil {
		t.Fatal(err)
	}
	return estimate
}

func b29StoreFinals(t *testing.T, store *activeIdentityStore) []activeIdentityFinalized {
	t.Helper()
	finals, ready := store.finalized()
	if !ready {
		t.Fatal("valid durable store is unavailable")
	}
	return finals
}

func b29StoreWaitSignal(t *testing.T, ch <-chan struct{}, name string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(5 * time.Second):
		t.Fatalf("%s did not reach its controlled checkpoint", name)
	}
}

func b29StoreWaitError(t *testing.T, ch <-chan error, name string) error {
	t.Helper()
	select {
	case err := <-ch:
		return err
	case <-time.After(5 * time.Second):
		t.Fatalf("%s did not finish after its barrier was released", name)
		return nil
	}
}

func TestB29StoreAckRequiresDurableGenerationAndReload(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-01")}
	store := b29NewStore(t, clock)
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	entered, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	defer unblock()
	write := store.write
	var committed atomic.Bool
	store.write = func(path string, raw []byte) error {
		close(entered)
		<-release
		err := write(path, raw)
		if err == nil {
			committed.Store(true)
		}
		return err
	}
	type ack struct {
		err     error
		durable bool
	}
	acknowledged := make(chan ack, 1)
	go func() {
		err := store.admit("2026-03-01", "private-b29-ack-account")
		acknowledged <- ack{err, committed.Load()}
	}()
	b29StoreWaitSignal(t, entered, "admission writer")
	select {
	case got := <-acknowledged:
		t.Fatalf("admission ACK preceded durable write: %+v", got)
	default:
	}
	still, err := os.ReadFile(store.path)
	if err != nil || !bytes.Equal(before, still) {
		t.Fatalf("blocked write changed authoritative file: %v", err)
	}
	readFinished := make(chan struct{})
	go func() { store.finalized(); close(readFinished) }()
	b29StoreWaitSignal(t, readFinished, "read while snapshot I/O is blocked")
	unblock()
	select {
	case got := <-acknowledged:
		if got.err != nil || !got.durable {
			t.Fatalf("ACK did not follow successful durable generation: %+v", got)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("admission did not ACK after durable writer completed")
	}
	store.write = write
	if _, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now); err != nil {
		t.Fatal(err)
	}
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, store.path), "2026-03-01"); got.Day != 1 {
		t.Fatalf("acknowledged identity lost on immediate reload: %+v", got)
	}
}

func TestB29StoreMutationDuringWriteNeedsItsOwnDurableGeneration(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-01")}
	store := b29NewStore(t, clock)
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	defer unblock()
	write := store.write
	var writes atomic.Int32
	var firstSnapshot activeIdentityStoreDisk
	store.write = func(path string, raw []byte) error {
		if writes.Add(1) == 1 {
			if err := json.Unmarshal(raw, &firstSnapshot); err != nil {
				return err
			}
			close(entered)
			<-release
		}
		return write(path, raw)
	}
	firstDone := make(chan error, 1)
	go func() { firstDone <- store.admit("2026-03-01", "first-b29-account") }()
	b29StoreWaitSignal(t, entered, "first generation writer")
	secondClock := make(chan struct{})
	var clockOnce sync.Once
	clock.setHook(func(at time.Time) time.Time {
		clockOnce.Do(func() { close(secondClock) })
		return at
	})
	secondDone := make(chan error, 1)
	go func() { secondDone <- store.admit("2026-03-01", "second-b29-account") }()
	b29StoreWaitSignal(t, secondClock, "second admission while writer blocked")
	// Crossing the state mutex after the clock callback proves the second
	// admission finished its in-memory mutation, without waiting on snapshot I/O.
	store.mu.Lock()
	pendingGeneration := store.generation
	store.mu.Unlock()
	if pendingGeneration <= firstSnapshot.Generation {
		t.Fatal("second mutation did not remain dirty beyond the first snapshot")
	}
	select {
	case err := <-secondDone:
		t.Fatalf("second admission ACKed an older blocked generation: %v", err)
	default:
	}
	unblock()
	if err := b29StoreWaitError(t, firstDone, "first admission"); err != nil {
		t.Fatal(err)
	}
	if err := b29StoreWaitError(t, secondDone, "second admission"); err != nil {
		t.Fatal(err)
	}
	clock.setHook(nil)
	store.write = write
	if writes.Load() < 2 {
		t.Fatal("later generation was never written")
	}
	if got := b29StoreDiskEstimate(t, firstSnapshot, "2026-03-01"); got.Day != 1 {
		t.Fatalf("first snapshot was not the captured one-identity generation: %+v", got)
	}
	loaded, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	disk := b29StoreDisk(t, loaded.path)
	if got := b29StoreDiskEstimate(t, disk, "2026-03-01"); got.Day != 2 || disk.Generation < pendingGeneration {
		t.Fatalf("later acknowledged generation lost: %+v generation%d want>=%d", got, disk.Generation, pendingGeneration)
	}
}

func b29StoreFindFinal(t *testing.T, values []activeIdentityFinalized, day string) activeIdentityFinalized {
	t.Helper()
	for _, value := range values {
		if value.Day == day {
			return value
		}
	}
	t.Fatalf("no finalized row for measured day %s", day)
	return activeIdentityFinalized{}
}

func b29StoreFinalMap(t *testing.T, values []activeIdentityFinalized) map[string]activeIdentityEstimate {
	t.Helper()
	result := make(map[string]activeIdentityEstimate)
	for _, value := range values {
		if _, duplicate := result[value.Day]; duplicate {
			t.Fatalf("duplicate finalized date %s", value.Day)
		}
		result[value.Day] = value.Counts
	}
	return result
}

func TestB29StoreStorageFailureHidesAndRecoversDurableHistory(t *testing.T) {
	start := b29StoreMidnight(t, "2026-03-01")
	clock := &b29StoreClock{at: start}
	store := b29NewStore(t, clock)
	b29StoreAdmit(t, store, "2026-03-01", "public-before-failure-account")
	b29StoreAdvance(t, store, clock, start.AddDate(0, 0, 1))
	prior := b29StoreFinalMap(t, b29StoreFinals(t, store))
	if prior["2026-03-01"].Day != 1 {
		t.Fatal("valid durable-history positive control failed")
	}
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	write := store.write
	var attempted atomic.Bool
	store.write = func(string, []byte) error {
		attempted.Store(true)
		return errors.New("public controlled writer refusal")
	}
	if err := store.admit("2026-03-02", "public-during-failure-account"); !errors.Is(err, errActiveIdentityStoreStorage) {
		t.Fatalf("write failure error=%v, want fixed storage refusal", err)
	}
	if !attempted.Load() {
		t.Fatal("failure fixture never reached snapshot writer")
	}
	if values, ready := store.finalized(); ready || len(values) != 0 {
		t.Fatalf("failed storage exposed day rows: ready%t values%v", ready, values)
	}
	unchanged, err := os.ReadFile(store.path)
	if err != nil || !bytes.Equal(before, unchanged) {
		t.Fatalf("failed generation replaced authoritative snapshot: %v", err)
	}
	store.write = write
	if err := store.flush(); err != nil {
		t.Fatal(err)
	}
	if got := b29StoreFinalMap(t, b29StoreFinals(t, store)); !reflect.DeepEqual(got, prior) {
		t.Fatalf("recovery rewrote finalized history: got%v want%v", got, prior)
	}
	loaded, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, loaded.path), "2026-03-02"); got.Day != 1 || got.Week != 2 {
		t.Fatalf("retry did not preserve pending contribution: %+v", got)
	}
}

func TestB29StoreKeeps31RawDaysAnd7ImmutableFinalizedTriples(t *testing.T) {
	start := b29StoreMidnight(t, "2026-01-01")
	clock := &b29StoreClock{at: start}
	store := b29NewStore(t, clock)
	var captured activeIdentityFinalized
	for i := 0; i < 38; i++ {
		day := start.AddDate(0, 0, i).Format("2006-01-02")
		b29StoreAdmit(t, store, day, fmt.Sprintf("public-distinct-day-account-%02d", i))
		b29StoreAdvance(t, store, clock, start.AddDate(0, 0, i+1))
		if i == 31 {
			captured = b29StoreFindFinal(t, b29StoreFinals(t, store), day)
		}
	}
	disk := b29StoreDisk(t, store.path)
	if len(disk.Days) != 31 || len(disk.Finalized) != 7 {
		t.Fatalf("retained raw/finalized = %d/%d, want31/7", len(disk.Days), len(disk.Finalized))
	}
	rawDays := make(map[string]bool)
	for _, day := range disk.Days {
		if rawDays[day.Day] {
			t.Fatalf("duplicate raw date %s", day.Day)
		}
		rawDays[day.Day] = true
	}
	for i := 8; i <= 38; i++ {
		if !rawDays[start.AddDate(0, 0, i).Format("2006-01-02")] {
			t.Fatalf("raw window omitted observed calendar date index%d", i)
		}
	}
	values := b29StoreFinals(t, store)
	for i := 31; i < 38; i++ {
		b29StoreFindFinal(t, values, start.AddDate(0, 0, i).Format("2006-01-02"))
	}
	if got := b29StoreFindFinal(t, values, captured.Day); got != captured {
		t.Fatalf("oldest finalized triple changed after raw pruning: got%+v want%+v", got, captured)
	}
	// The controlled cohort is one distinct account per day. Compare an actual
	// earlier finalized estimate, not an assumed exact large-cohort HLL count.
	recomputed := b29StoreDiskEstimate(t, disk, captured.Day)
	if captured.Counts.Month <= recomputed.Month {
		t.Fatalf("fixture did not distinguish frozen MAU from recomputation: frozen%d retained-only%d", captured.Counts.Month, recomputed.Month)
	}
	loaded, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	if got := b29StoreFindFinal(t, b29StoreFinals(t, loaded), captured.Day); got != captured {
		t.Fatalf("collector backfill changed frozen triple on restart: got%+v want%+v", got, captured)
	}
}

func TestB29StorePartialStartupAndMeasuredEmptyDayHaveDistinctCoverage(t *testing.T) {
	start := b29StoreMidnight(t, "2026-03-28")
	clock := &b29StoreClock{at: start.Add(12 * time.Hour)}
	store := b29NewStore(t, clock)
	if got := b29StoreFinals(t, store); len(got) != 0 {
		t.Fatalf("deployment invented history: %v", got)
	}
	b29StoreAdmit(t, store, "2026-03-28", "public-partial-day-account")
	b29StoreAdvance(t, store, clock, start.AddDate(0, 0, 1))
	partial := b29StoreFindFinal(t, b29StoreFinals(t, store), "2026-03-28")
	if !partial.Partial || partial.Counts != (activeIdentityEstimate{Day: 1, Week: 1, Month: 1}) {
		t.Fatalf("first partial day did not retain its observed marks and coverage: %+v", partial)
	}
	// March29 is a genuine observed empty Berlin day, despite being23 hours.
	b29StoreAdvance(t, store, clock, start.AddDate(0, 0, 2))
	got := b29StoreFinals(t, store)
	if len(got) != 2 || got[1].Day != "2026-03-29" || got[1].Partial || got[1].Counts != (activeIdentityEstimate{Day: 0, Week: 1, Month: 1}) {
		t.Fatalf("measured empty day/incomplete rolling coverage=%+v", got)
	}
	zeroClock := &b29StoreClock{at: start}
	zero := b29NewStore(t, zeroClock)
	b29StoreAdvance(t, zero, zeroClock, start.AddDate(0, 0, 1))
	if got := b29StoreFinals(t, zero); len(got) != 1 || got[0].Partial || got[0].Counts != (activeIdentityEstimate{}) {
		t.Fatalf("genuinely measured all-empty day was not a zero: %+v", got)
	}
}

func TestB29StoreRestartAndDowntimeRetainPartialDays(t *testing.T) {
	start := b29StoreMidnight(t, "2026-10-20")
	clock := &b29StoreClock{at: start}
	store := b29NewStore(t, clock)
	b29StoreAdmit(t, store, "2026-10-20", "public-before-restart-account")
	b29StoreAdvance(t, store, clock, start.AddDate(0, 0, 1))
	prior := b29StoreFinalMap(t, b29StoreFinals(t, store))
	clock.set(start.AddDate(0, 0, 1).Add(12 * time.Hour))
	restarted, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	if got := b29StoreFinalMap(t, b29StoreFinals(t, restarted)); !reflect.DeepEqual(got, prior) {
		t.Fatal("restart lost immutable collector history")
	}
	b29StoreAdmit(t, restarted, "2026-10-21", "public-restarted-partial-account")
	b29StoreAdvance(t, restarted, clock, start.AddDate(0, 0, 2))
	if got := b29StoreFindFinal(t, b29StoreFinals(t, restarted), "2026-10-21"); !got.Partial ||
		got.Counts != (activeIdentityEstimate{Day: 1, Week: 2, Month: 2}) {
		t.Fatalf("restart's partial open day lost its observed marks: %+v", got)
	}
	clock.set(start.AddDate(0, 0, 5).Add(12 * time.Hour))
	afterGap, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	finals := b29StoreFinals(t, afterGap)
	if len(finals) != 5 || finals[0].Partial || finals[0].Counts != prior["2026-10-20"] {
		t.Fatalf("restart did not retain the frozen full day and four partial days: %+v", finals)
	}
	for _, day := range []string{"2026-10-22", "2026-10-23", "2026-10-24"} {
		if got := b29StoreFindFinal(t, finals, day); !got.Partial ||
			got.Counts != (activeIdentityEstimate{Day: 0, Week: 2, Month: 2}) {
			t.Fatalf("downtime day missing its observed lower bound: %+v", got)
		}
	}
	b29StoreAdvance(t, afterGap, clock, start.AddDate(0, 0, 6))
	if got := b29StoreFindFinal(t, b29StoreFinals(t, afterGap), "2026-10-25"); !got.Partial {
		t.Fatalf("post-gap partial day was marked fully observed: %+v", got)
	}
	b29StoreAdvance(t, afterGap, clock, start.AddDate(0, 0, 7))
	if got := b29StoreFindFinal(t, b29StoreFinals(t, afterGap), "2026-10-26"); got.Partial || got.Counts.Day != 0 {
		t.Fatalf("first fully observed empty day after gap missing: %+v", got)
	}
}

func TestB29StoreShortRestartPreservesFullDayWithRecentCheckpoint(t *testing.T) {
	const day = "2026-03-29"
	start := b29StoreMidnight(t, day)
	closeDay := b29StoreMidnight(t, "2026-03-30")
	for _, stop := range []time.Time{start.Add(12 * time.Hour), closeDay.Add(-time.Second)} {
		t.Run(stop.Format(time.RFC3339), func(t *testing.T) {
			clock := &b29StoreClock{at: start}
			store := b29NewStore(t, clock)
			b29StoreAdmit(t, store, day, "public-before-checkpoint")

			before := b29StoreDisk(t, store.path)
			b29StoreAdvance(t, store, clock, stop)
			if idle := b29StoreDisk(t, store.path); idle.Generation != before.Generation {
				t.Fatal("idle same-day tick wrote a new snapshot")
			}
			if err := store.advanceAndSave(true); err != nil {
				t.Fatal(err)
			}
			clock.set(stop.Add(2 * time.Second))
			restarted, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
			if err != nil {
				t.Fatal(err)
			}
			if clock.now().Before(closeDay) {
				b29StoreAdvance(t, restarted, clock, closeDay)
			}
			got := b29StoreFindFinal(t, b29StoreFinals(t, restarted), day)
			if got.Partial || got.Counts != (activeIdentityEstimate{Day: 1, Week: 1, Month: 1}) {
				t.Fatalf("short restart lost full-day eligibility or observed marks: %+v", got)
			}
		})
	}
}

func TestB29StoreRestoresLegacySnapshotAndFillsRetainedMissingDay(t *testing.T) {
	start := b29StoreMidnight(t, "2026-10-20")
	clock := &b29StoreClock{at: start}
	store := b29NewStore(t, clock)
	b29StoreAdmit(t, store, "2026-10-20", "public-before-upgrade")
	b29StoreAdvance(t, store, clock, start.AddDate(0, 0, 1))
	b29StoreAdvance(t, store, clock, start.AddDate(0, 0, 2))
	legacy := b29StoreDisk(t, store.path)
	legacy.ObservedAt = nil
	legacy.Finalized = legacy.Finalized[:1]
	b29StorePutBytes(t, store.path, b29StoreDiskBytes(t, legacy))

	restarted, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	want := []activeIdentityFinalized{
		legacy.Finalized[0],
		{Day: "2026-10-21", Counts: activeIdentityEstimate{Day: 0, Week: 1, Month: 1}, Partial: true},
	}
	if got := b29StoreFinals(t, restarted); !reflect.DeepEqual(got, want) {
		t.Fatalf("migration produced wrong retained days: got %+v want %+v", got, want)
	}
	restarted, err = newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	if got := b29StoreFinals(t, restarted); !reflect.DeepEqual(got, want) {
		t.Fatalf("restart lost persisted coverage: got %+v want %+v", got, want)
	}
}

func b29StoreCloneDisk(t *testing.T, disk activeIdentityStoreDisk) activeIdentityStoreDisk {
	t.Helper()
	raw, err := json.Marshal(disk)
	if err != nil {
		t.Fatal(err)
	}
	var cloned activeIdentityStoreDisk
	if err := json.Unmarshal(raw, &cloned); err != nil {
		t.Fatal(err)
	}
	return cloned
}

func b29StoreDiskBytes(t *testing.T, disk activeIdentityStoreDisk) []byte {
	t.Helper()
	raw, err := json.Marshal(disk)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func b29StorePutBytes(t *testing.T, path string, raw []byte) {
	t.Helper()
	if err := os.WriteFile(path, raw, 0600); err != nil {
		t.Fatal(err)
	}
}

func TestB29StoreRejectsCorruptSnapshotsWithoutChangingThem(t *testing.T) {
	start := b29StoreMidnight(t, "2026-11-12")
	clock := &b29StoreClock{at: start}
	store := b29NewStore(t, clock)
	b29StoreAdmit(t, store, "2026-11-12", "public-restore-account")
	b29StoreAdvance(t, store, clock, start.AddDate(0, 0, 1))
	clock.set(start.AddDate(0, 0, 1).Add(18 * time.Hour))
	if _, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now); err != nil {
		t.Fatalf("valid-load positive control: %v", err)
	}
	good := b29StoreDisk(t, store.path)
	if len(good.Days) != 2 || len(good.Finalized) != 1 {
		t.Fatal("valid raw/finalized snapshot positive controls are missing")
	}
	for _, tc := range []struct {
		name   string
		mutate func(*activeIdentityStoreDisk)
	}{
		{"version", func(d *activeIdentityStoreDisk) { d.Version++ }},
		{"calendar", func(d *activeIdentityStoreDisk) { d.Calendar = "UTC" }},
		{"missing-key-verifier", func(d *activeIdentityStoreDisk) { d.KeyID = "" }},
		{"malformed-key-verifier", func(d *activeIdentityStoreDisk) { d.KeyID = "not-a-key-verifier" }},
		{"missing-measurement-start", func(d *activeIdentityStoreDisk) { d.MeasurementStart = time.Time{} }},
		{"future-measurement-start", func(d *activeIdentityStoreDisk) { d.MeasurementStart = clock.now().AddDate(0, 0, 1) }},
		{"noncanonical-open-day", func(d *activeIdentityStoreDisk) { d.OpenDay.Day = "2026-2-13" }},
		{"future-open-day", func(d *activeIdentityStoreDisk) { d.OpenDay.Day = "2026-11-14" }},
		{"missing-observation-start", func(d *activeIdentityStoreDisk) { d.OpenDay.ObservingFrom = time.Time{} }},
		{"observation-outside-open-day", func(d *activeIdentityStoreDisk) { d.OpenDay.ObservingFrom = clock.now().AddDate(0, 0, 1) }},
		{"partial-marked-full", func(d *activeIdentityStoreDisk) {
			d.OpenDay.ObservingFrom = b29StoreMidnight(t, d.OpenDay.Day).Add(12 * time.Hour)
			d.OpenDay.FullDayEligible = true
		}},
		{"duplicate-raw-day", func(d *activeIdentityStoreDisk) { d.Days = append(d.Days, d.Days[0]) }},
		{"too-many-raw-days", func(d *activeIdentityStoreDisk) {
			for len(d.Days) <= 31 {
				d.Days = append(d.Days, d.Days[0])
			}
		}},
		{"future-raw-day", func(d *activeIdentityStoreDisk) { d.Days[0].Day = "2026-11-14" }},
		{"raw-before-measurement", func(d *activeIdentityStoreDisk) { d.Days[0].Day = "2026-11-11" }},
		{"noncanonical-raw-day", func(d *activeIdentityStoreDisk) { d.Days[0].Day = "2026-02-29" }},
		{"duplicate-finalized-day", func(d *activeIdentityStoreDisk) { d.Finalized = append(d.Finalized, d.Finalized[0]) }},
		{"too-many-finalized-days", func(d *activeIdentityStoreDisk) {
			for len(d.Finalized) <= 7 {
				d.Finalized = append(d.Finalized, d.Finalized[0])
			}
		}},
		{"open-day-finalized", func(d *activeIdentityStoreDisk) { d.Finalized[0].Day = d.OpenDay.Day }},
		{"finalized-before-measurement", func(d *activeIdentityStoreDisk) { d.Finalized[0].Day = "2026-11-11" }},
		{"truncated-dense", func(d *activeIdentityStoreDisk) { d.Days[0].Sketch = d.Days[0].Sketch[:8] }},
		{"wrong-dense-version", func(d *activeIdentityStoreDisk) { d.Days[0].Sketch[0] = 99 }},
		{"wrong-dense-precision", func(d *activeIdentityStoreDisk) { d.Days[0].Sketch[1] = 15 }},
		{"sparse-encoding", func(d *activeIdentityStoreDisk) { d.Days[0].Sketch[3] = 1 }},
		{"impossible-register-rank", func(d *activeIdentityStoreDisk) { d.Days[0].Sketch[8] = 255 }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			disk := b29StoreCloneDisk(t, good)
			tc.mutate(&disk)
			raw := b29StoreDiskBytes(t, disk)
			b29StorePutBytes(t, store.path, raw)
			if _, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now); !errors.Is(err, errActiveIdentityStoreSnapshot) {
				t.Fatalf("corrupt snapshot error=%v, want fixed snapshot refusal", err)
			}
			after, err := os.ReadFile(store.path)
			if err != nil || !bytes.Equal(raw, after) {
				t.Fatalf("refused snapshot was changed or erased: %v", err)
			}
		})
	}
	validRaw := b29StoreDiskBytes(t, good)
	b29StorePutBytes(t, store.path, validRaw)
	if _, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now); err != nil {
		t.Fatalf("valid compact JSON control: %v", err)
	}
	zeroClock := &b29StoreClock{at: start}
	zeroStore := b29NewStore(t, zeroClock)
	b29StoreAdvance(t, zeroStore, zeroClock, start.AddDate(0, 0, 1))
	zeroRaw, err := os.ReadFile(zeroStore.path)
	if err != nil {
		t.Fatal(err)
	}
	b29StorePutBytes(t, store.path, zeroRaw)
	zeroLoaded, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatalf("zero-count snapshot valid-load control: %v", err)
	}
	if got := b29StoreFindFinal(t, b29StoreFinals(t, zeroLoaded), "2026-11-12"); got.Counts != (activeIdentityEstimate{}) {
		t.Fatalf("presence refusal requires a genuine fully observed zero triple: %+v", got)
	}
	zeroRaw, err = os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	invalidCount := func(member string, null bool) []byte {
		var object map[string]json.RawMessage
		if err := json.Unmarshal(zeroRaw, &object); err != nil {
			t.Fatal(err)
		}
		var finalized []map[string]json.RawMessage
		if err := json.Unmarshal(object["finalized"], &finalized); err != nil || len(finalized) != 1 {
			t.Fatalf("valid finalized JSON control: %v", err)
		}
		var counts map[string]json.RawMessage
		if err := json.Unmarshal(finalized[0]["counts"], &counts); err != nil {
			t.Fatal(err)
		}
		for _, field := range []string{"Day", "Week", "Month"} {
			value, exists := counts[field]
			if !exists || !bytes.Equal(bytes.TrimSpace(value), []byte("0")) {
				t.Fatalf("valid zero control omitted explicit numeric member %s", field)
			}
		}
		if member == "counts" {
			if null {
				finalized[0]["counts"] = json.RawMessage("null")
			} else {
				delete(finalized[0], "counts")
			}
		} else {
			if null {
				counts[member] = json.RawMessage("null")
			} else {
				delete(counts, member)
			}
			finalized[0]["counts"], _ = json.Marshal(counts)
		}
		object["finalized"], _ = json.Marshal(finalized)
		raw, err := json.Marshal(object)
		if err != nil {
			t.Fatal(err)
		}
		return raw
	}
	duplicateVersion := bytes.Replace(validRaw, []byte(fmt.Sprintf(`"version":%d`, good.Version)), []byte(fmt.Sprintf(`"version":%d,"version":%d`, good.Version, good.Version)), 1)
	duplicateNested := bytes.Replace(validRaw, []byte(fmt.Sprintf(`"day":%q`, good.OpenDay.Day)), []byte(fmt.Sprintf(`"day":%q,"day":%q`, good.OpenDay.Day, good.OpenDay.Day)), 1)
	if bytes.Equal(validRaw, duplicateVersion) || bytes.Equal(validRaw, duplicateNested) {
		t.Fatal("duplicate-field fixtures did not change the valid snapshot")
	}
	for _, tc := range []struct {
		name string
		raw  []byte
	}{
		{"truncated-json", validRaw[:len(validRaw)/2]},
		{"unknown-field", append(append([]byte{}, validRaw[:len(validRaw)-1]...), []byte(`,"account_history":[]}`)...)},
		{"trailing-value", append(bytes.Clone(validRaw), []byte(` {"extra":true}`)...)},
		{"duplicate-root-field", duplicateVersion},
		{"duplicate-nested-field", duplicateNested},
		{"missing-daily-count", invalidCount("Day", false)},
		{"missing-weekly-count", invalidCount("Week", false)},
		{"missing-monthly-count", invalidCount("Month", false)},
		{"missing-counts-object", invalidCount("counts", false)},
		{"null-daily-count", invalidCount("Day", true)},
		{"null-weekly-count", invalidCount("Week", true)},
		{"null-monthly-count", invalidCount("Month", true)},
		{"null-counts-object", invalidCount("counts", true)},
		{"oversized", append(bytes.Clone(validRaw), bytes.Repeat([]byte(" "), activeIdentityStoreSnapshotLimit+1)...)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b29StorePutBytes(t, store.path, tc.raw)
			if _, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now); !errors.Is(err, errActiveIdentityStoreSnapshot) {
				t.Fatalf("malformed snapshot error=%v, want fixed snapshot refusal", err)
			}
			after, err := os.ReadFile(store.path)
			if err != nil || !bytes.Equal(tc.raw, after) {
				t.Fatalf("malformed source evidence was changed: %v", err)
			}
		})
	}
}

func TestB29StoreExplicitZeroCountsReloadAcrossJSONObjectOrdering(t *testing.T) {
	start := b29StoreMidnight(t, "2026-11-12")
	clock := &b29StoreClock{at: start}
	store := b29NewStore(t, clock)
	b29StoreAdvance(t, store, clock, start.AddDate(0, 0, 1))
	if got := b29StoreFindFinal(t, b29StoreFinals(t, store), "2026-11-12"); got.Counts != (activeIdentityEstimate{}) {
		t.Fatalf("fully observed empty day is not a zero control: %+v", got)
	}
	raw, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	var object map[string]json.RawMessage
	if err := json.Unmarshal(raw, &object); err != nil {
		t.Fatal(err)
	}
	var finalized []map[string]json.RawMessage
	if err := json.Unmarshal(object["finalized"], &finalized); err != nil || len(finalized) != 1 {
		t.Fatalf("explicit-zero finalized control: %v", err)
	}
	var counts map[string]json.RawMessage
	if err := json.Unmarshal(finalized[0]["counts"], &counts); err != nil {
		t.Fatal(err)
	}
	for _, member := range []string{"Day", "Week", "Month"} {
		value, exists := counts[member]
		if !exists || !bytes.Equal(bytes.TrimSpace(value), []byte("0")) {
			t.Fatalf("measured zero member %s was not explicitly present as zero", member)
		}
	}
	keys := make([]string, 0, len(object))
	for key := range object {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	countKeys := make([]string, 0, len(counts))
	for key := range counts {
		countKeys = append(countKeys, key)
	}
	sort.Strings(countKeys)
	encodeObject := func(keys []string, fields map[string]json.RawMessage) []byte {
		var encoded bytes.Buffer
		encoded.WriteString("{\n  ")
		for i, key := range keys {
			if i > 0 {
				encoded.WriteString(",\n  ")
			}
			fmt.Fprintf(&encoded, "%q : %s", key, fields[key])
		}
		encoded.WriteString("\n}\n")
		return encoded.Bytes()
	}
	for _, reverse := range []bool{false, true} {
		if reverse {
			for _, order := range [][]string{keys, countKeys} {
				for i, j := 0, len(order)-1; i < j; i, j = i+1, j-1 {
					order[i], order[j] = order[j], order[i]
				}
			}
		}
		finalized[0]["counts"] = encodeObject(countKeys, counts)
		object["finalized"], err = json.Marshal(finalized)
		if err != nil {
			t.Fatal(err)
		}
		b29StorePutBytes(t, store.path, encodeObject(keys, object))
		loaded, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
		if err != nil {
			t.Fatalf("valid reordered/re-encoded zero snapshot rejected: %v", err)
		}
		if got := b29StoreFindFinal(t, b29StoreFinals(t, loaded), "2026-11-12"); got.Counts != (activeIdentityEstimate{}) {
			t.Fatalf("explicit zero changed after reload: %+v", got)
		}
	}
}

func TestB29StoreAcceptsMaximumDenseRankAndRejectsImpossibleRank(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-11-14")}
	store := b29NewStore(t, clock)
	good := b29StoreDisk(t, store.path)
	if len(good.Days) != 1 || len(good.Days[0].Sketch) != 8+(1<<14) {
		t.Fatal("valid dense snapshot positive control missing")
	}
	good.Days[0].Sketch[8] = 51
	b29StorePutBytes(t, store.path, b29StoreDiskBytes(t, good))
	if _, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now); err != nil {
		t.Fatalf("valid maximum p14 rank51 rejected: %v", err)
	}
	bad := b29StoreCloneDisk(t, good)
	bad.Days[0].Sketch[8] = 255
	raw := b29StoreDiskBytes(t, bad)
	b29StorePutBytes(t, store.path, raw)
	if _, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now); !errors.Is(err, errActiveIdentityStoreSnapshot) {
		t.Fatalf("impossible p14 rank255 accepted: %v", err)
	}
	if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(after, raw) {
		t.Fatalf("corrupt dense evidence was erased: %v", err)
	}
}

func TestB29StoreKeyEpochNeedsExplicitFreshStorage(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-11-14")}
	store := b29NewStore(t, clock)
	b29StoreAdmit(t, store, "2026-11-14", "public-key-epoch-account")
	if _, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now); err != nil {
		t.Fatalf("same-key valid-load control: %v", err)
	}
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	newKey := bytes.Repeat([]byte{18}, 32)
	if _, err := newActiveIdentityStore(store.path, newKey, clock.now); !errors.Is(err, errActiveIdentityStoreKeyEpoch) {
		t.Fatalf("different key error=%v, want explicit epoch refusal", err)
	}
	if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("key mismatch silently reset existing authority: %v", err)
	}
	freshPath := filepath.Join(t.TempDir(), "fresh-epoch.json")
	fresh, err := newActiveIdentityStore(freshPath, newKey, clock.now)
	if err != nil {
		t.Fatalf("explicit fresh epoch was not available: %v", err)
	}
	if values := b29StoreFinals(t, fresh); len(values) != 0 {
		t.Fatalf("fresh key epoch inherited old history: %v", values)
	}
	if freshDisk := b29StoreDisk(t, freshPath); freshDisk.KeyID == b29StoreDisk(t, store.path).KeyID {
		t.Fatal("new key did not change snapshot verifier")
	}
}

func TestB29StoreMidnightAdmissionAndCloseUseOneLock(t *testing.T) {
	start := b29StoreMidnight(t, "2026-03-28")
	clock := &b29StoreClock{at: start}
	store := b29NewStore(t, clock)
	clock.set(start.AddDate(0, 0, 1).Add(-time.Second))
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	defer unblock()
	var first atomic.Bool
	clock.setHook(func(at time.Time) time.Time {
		// This is the specified linearization lock, not a guessed delay: a
		// concurrent close cannot pass this authoritative clock checkpoint.
		if store.mu.TryLock() {
			store.mu.Unlock()
			t.Error("authoritative clock was read outside the admission/close lock")
		}
		if first.CompareAndSwap(false, true) {
			close(entered)
			<-release
		}
		return at
	})
	admitted := make(chan error, 1)
	go func() { admitted <- store.admit("2026-03-28", "public-midnight-account") }()
	b29StoreWaitSignal(t, entered, "pre-midnight admission clock")
	clock.set(start.AddDate(0, 0, 1))
	closingStarted := make(chan struct{})
	closed := make(chan error, 1)
	go func() { close(closingStarted); closed <- store.advance() }()
	b29StoreWaitSignal(t, closingStarted, "concurrent midnight close")
	unblock()
	if err := b29StoreWaitError(t, admitted, "pre-midnight admission"); err != nil {
		t.Fatal(err)
	}
	if err := b29StoreWaitError(t, closed, "midnight close"); err != nil {
		t.Fatal(err)
	}
	clock.setHook(nil)
	if got := b29StoreFindFinal(t, b29StoreFinals(t, store), "2026-03-28"); got.Counts.Day != 1 {
		t.Fatalf("admitted contribution missed its serialized close: %+v", got)
	}
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.admit("2026-03-28", "public-late-closed-day-account"); !errors.Is(err, errActiveIdentityStoreDay) {
		t.Fatalf("closed-day request error=%v", err)
	}
	if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("closed-day refusal rewrote finalized generation: %v", err)
	}
}

func TestB29StoreRefusesInvalidRequestsWithoutMutation(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-11-14")}
	store := b29NewStore(t, clock)
	b29StoreAdmit(t, store, "2026-11-14", "public-valid-input-account")
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	for _, day := range []string{"", "2026-1-01", "2026-02-29", "2026-11-14T00:00:00Z"} {
		if err := store.admit(day, "public-invalid-day-account"); !errors.Is(err, activitycalendar.ErrInvalidDay) {
			t.Errorf("malformed day %q error=%v", day, err)
		}
	}
	for _, day := range []string{"2026-11-13", "2026-11-15"} {
		if err := store.admit(day, "public-out-of-window-account"); !errors.Is(err, errActiveIdentityStoreDay) {
			t.Errorf("noncurrent day %q error=%v", day, err)
		}
	}
	if err := store.admit("2026-11-14", ""); !errors.Is(err, errActiveIdentityAccount) {
		t.Errorf("empty canonical account error=%v", err)
	}
	if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("refused input changed the persisted generation: %v", err)
	}
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, store.path), "2026-11-14"); got.Day != 1 {
		t.Fatalf("refused input changed identity registers: %+v", got)
	}
}

func TestB29StoreOnlyPublishesDurableHistoryAndReturnsCopies(t *testing.T) {
	start := b29StoreMidnight(t, "2026-11-12")
	clock := &b29StoreClock{at: start}
	store := b29NewStore(t, clock)
	b29StoreAdmit(t, store, "2026-11-12", "public-first-finalized-account")
	b29StoreAdvance(t, store, clock, start.AddDate(0, 0, 1))
	b29StoreAdmit(t, store, "2026-11-13", "public-second-finalized-account")
	prior := b29StoreFinalMap(t, b29StoreFinals(t, store))
	if len(prior) != 1 || prior["2026-11-12"].Day != 1 {
		t.Fatal("durable-history positive control is missing")
	}
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	defer unblock()
	write := store.write
	store.write = func(path string, raw []byte) error {
		close(entered)
		<-release
		return write(path, raw)
	}
	clock.set(start.AddDate(0, 0, 2))
	advanced := make(chan error, 1)
	go func() { advanced <- store.advance() }()
	b29StoreWaitSignal(t, entered, "new finalized generation writer")
	read := make(chan []activeIdentityFinalized, 1)
	readError := make(chan error, 1)
	go func() {
		values, ready := store.finalized()
		if !ready {
			readError <- errors.New("previous durable generation became unavailable during a pending write")
			return
		}
		read <- values
	}()
	var values []activeIdentityFinalized
	select {
	case values = <-read:
	case err := <-readError:
		t.Fatal(err)
	case <-time.After(5 * time.Second):
		t.Fatal("durable history read waited for pending snapshot I/O")
	}
	if got := b29StoreFinalMap(t, values); !reflect.DeepEqual(got, prior) {
		t.Fatalf("uncommitted finalization leaked before durable write: got%v want%v", got, prior)
	}
	values[0].Day = "1900-01-01"
	values[0].Counts.Day = 999
	if got := b29StoreFinalMap(t, b29StoreFinals(t, store)); !reflect.DeepEqual(got, prior) {
		t.Fatalf("caller mutated owned immutable history: %v", got)
	}
	unblock()
	if err := b29StoreWaitError(t, advanced, "durable finalization"); err != nil {
		t.Fatal(err)
	}
	store.write = write
	if got := b29StoreFinalMap(t, b29StoreFinals(t, store)); len(got) != 2 || got["2026-11-13"].Day != 1 {
		t.Fatalf("new finalized generation did not publish after commit: %v", got)
	}
}

func TestB29StoreIgnoresUncommittedPartialTempSnapshot(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-11-14")}
	store := b29NewStore(t, clock)
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	partialPath := store.path + ".uncommitted-owned-fixture"
	store.write = func(_ string, raw []byte) error {
		if err := os.WriteFile(partialPath, raw[:len(raw)/2], 0600); err != nil {
			return err
		}
		return errors.New("public partial temp write fixture")
	}
	if err := store.admit("2026-11-14", "public-unacknowledged-account"); !errors.Is(err, errActiveIdentityStoreStorage) {
		t.Fatalf("partial writer ACKed or returned wrong error: %v", err)
	}
	partial, err := os.ReadFile(partialPath)
	if err != nil || len(partial) == 0 {
		t.Fatalf("partial-temp failure fixture did not run: %v", err)
	}
	if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("uncommitted partial output replaced authority: %v", err)
	}
	loaded, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, loaded.path), "2026-11-14"); got.Day != 0 {
		t.Fatalf("reload promoted an uncommitted temp snapshot: %+v", got)
	}
	if after, err := os.ReadFile(partialPath); err != nil || !bytes.Equal(partial, after) {
		t.Fatalf("restore touched an unrelated nonauthoritative file: %v", err)
	}
}

func TestB29StoreSnapshotHasPrivateModesAndNoIdentityHistory(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-11-14")}
	store := b29NewStore(t, clock)
	sentinelPath := filepath.Join(filepath.Dir(store.path), "unrelated-owned-sentinel")
	b29StorePutBytes(t, sentinelPath, []byte("public unrelated data"))
	b29StoreAdmit(t, store, "2026-11-14", "private-b29-account-never-retained-in-snapshot")
	raw, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range [][]byte{
		[]byte("private-b29-account-never-retained-in-snapshot"),
		b29StoreKey(),
		[]byte(base64.StdEncoding.EncodeToString(b29StoreKey())),
		[]byte(hex.EncodeToString(b29StoreKey())),
		[]byte(`"account_id"`), []byte(`"peer_id"`), []byte(`"device_id"`),
		[]byte(`"signature"`), []byte(`"event_id"`), []byte(`"recipient"`), []byte(`"ip"`),
	} {
		if bytes.Contains(raw, forbidden) {
			t.Fatal("snapshot retained a forbidden identity/secret data category")
		}
	}
	disk := b29StoreDisk(t, store.path)
	if disk.Version != activeIdentityStoreVersion || disk.Calendar != "Europe/Berlin" || len(disk.Days) != 1 {
		t.Fatal("snapshot metadata/dense-positive control is invalid")
	}
	prototype, err := hyperloglog.NewNoSparse().MarshalBinary()
	if err != nil {
		t.Fatal(err)
	}
	for _, day := range disk.Days {
		if len(day.Sketch) != len(prototype) || !bytes.Equal(day.Sketch[:8], prototype[:8]) {
			t.Fatal("snapshot retained a sparse/per-input representation")
		}
	}
	file, err := os.Stat(store.path)
	if err != nil || file.Mode().Perm() != 0600 {
		t.Fatalf("snapshot is not a private0600 file: %v", err)
	}
	dir, err := os.Stat(filepath.Dir(store.path))
	if err != nil || dir.Mode().Perm() != 0700 {
		t.Fatalf("owned private snapshot directory changed mode: %v", err)
	}
	files, err := os.ReadDir(filepath.Dir(store.path))
	if err != nil || len(files) != 2 {
		t.Fatalf("snapshot left unexpected temp output: files%d error%v", len(files), err)
	}
	if sentinel, err := os.ReadFile(sentinelPath); err != nil || string(sentinel) != "public unrelated data" {
		t.Fatalf("snapshot changed unrelated owner data: %v", err)
	}
}

func TestB29StoreInvalidConstructorInputsHaveSpecificErrors(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-11-14")}
	store := b29NewStore(t, clock)
	if _, ready := store.finalized(); !ready {
		t.Fatal("valid constructor positive control is unavailable")
	}
	for _, tc := range []struct {
		name string
		path string
		key  []byte
		now  func() time.Time
		want error
	}{
		{"empty-path", "", b29StoreKey(), clock.now, errActiveIdentityStoreInput},
		{"nil-clock", store.path, b29StoreKey(), nil, errActiveIdentityStoreInput},
		{"missing-key", store.path, nil, clock.now, errActiveIdentityKey},
		{"short-key", store.path, bytes.Repeat([]byte{17}, 31), clock.now, errActiveIdentityKey},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := newActiveIdentityStore(tc.path, tc.key, tc.now); !errors.Is(err, tc.want) {
				t.Fatalf("constructor error=%v, want specific refusal%v", err, tc.want)
			}
		})
	}
}

func TestB29StoreConcurrentDuplicateAdmissionsRemainOneIdentity(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-11-14")}
	store := b29NewStore(t, clock)
	var workers sync.WaitGroup
	results := make(chan error, 8)
	for range 8 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			results <- store.admit("2026-11-14", "public-same-canonical-account")
		}()
	}
	allFinished := make(chan struct{})
	go func() { workers.Wait(); close(allFinished) }()
	b29StoreWaitSignal(t, allFinished, "concurrent duplicate admissions")
	close(results)
	for err := range results {
		if err != nil {
			t.Fatal(err)
		}
	}
	loaded, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, loaded.path), "2026-11-14"); got != (activeIdentityEstimate{Day: 1, Week: 1, Month: 1}) {
		t.Fatalf("concurrent/restarted duplicates changed cardinality: %+v", got)
	}
}
