package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/axiomhq/hyperloglog"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

func b29EngagementStore(t *testing.T, clock *b29StoreClock) *activeIdentityStore {
	t.Helper()
	store, err := newActiveIdentityStoreWithEngagement(filepath.Join(t.TempDir(), "activity.json"), b29StoreKey(), clock.now, true)
	if err != nil || store == nil {
		t.Fatalf("enabled store: store=%v err=%v", store, err)
	}
	return store
}

func b29EngagementAdmit(t *testing.T, store *activeIdentityStore, clock *b29StoreClock, account string, kinds activeEngagementKinds) {
	t.Helper()
	if err := store.admitEngagement(activitycalendar.Week(clock.now()), account, kinds); err != nil {
		t.Fatalf("valid current-week engagement rejected: %v", err)
	}
}

func b29EngagementValues(t *testing.T, store *activeIdentityStore) []activeEngagementWeek {
	t.Helper()
	values, ready := store.engagement()
	if !ready {
		t.Fatal("durable enabled engagement is not ready")
	}
	return values
}

func b29EngagementCounts(t *testing.T, store *activeIdentityStore, week string, want activeEngagementEstimate) {
	t.Helper()
	for _, value := range b29EngagementValues(t, store) {
		if value.Week == week {
			if value.Counts != want {
				t.Fatalf("%s counts=%+v want=%+v", week, value.Counts, want)
			}
			return
		}
	}
	t.Fatalf("observed week %s missing", week)
}

// Independent JSON projection checks the persisted aggregate contract.
type b29EngagementDiskWeek struct {
	Week   string `json:"week"`
	Active []byte `json:"active"`
	Chat   []byte `json:"chat"`
	Call   []byte `json:"call"`
	Group  []byte `json:"group"`
}

type b29EngagementDisk struct {
	Weeks []b29EngagementDiskWeek `json:"weeks"`
}

func b29EngagementDiskBlock(t *testing.T, path string) b29EngagementDisk {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var disk struct {
		Engagement *b29EngagementDisk `json:"engagement"`
	}
	if err := json.Unmarshal(raw, &disk); err != nil {
		t.Fatal(err)
	}
	if disk.Engagement == nil {
		t.Fatal("durable snapshot omits enabled engagement block")
	}
	return *disk.Engagement
}

func b29EngagementReload(t *testing.T, store *activeIdentityStore, clock *b29StoreClock, enabled bool) *activeIdentityStore {
	t.Helper()
	reloaded, err := newActiveIdentityStoreWithEngagement(store.path, b29StoreKey(), clock.now, enabled)
	if err != nil || reloaded == nil {
		t.Fatalf("reload enabled=%v: %v", enabled, err)
	}
	return reloaded
}

func TestB29E1StoreObservedZeroAndNoInventedHistory(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-04")}
	store := b29EngagementStore(t, clock)
	values := b29EngagementValues(t, store)
	want := []activeEngagementWeek{{Week: "2026-W10"}}
	if !reflect.DeepEqual(values, want) {
		t.Fatalf("new observed history=%+v want=%+v", values, want)
	}
	b29StoreAdvance(t, store, clock, b29StoreMidnight(t, "2026-03-25"))
	values = b29EngagementValues(t, store)
	if len(values) != 2 || values[0].Week != "2026-W10" || values[1].Week != "2026-W13" {
		t.Fatalf("downtime invented history or lost observed zero: %+v", values)
	}
}

func TestB29E1StoreDurableKindsUnionsAndLinkedRetry(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-04")}
	store := b29EngagementStore(t, clock)
	for _, mark := range []struct {
		account string
		kinds   activeEngagementKinds
	}{
		{"same-canonical-account", activeEngagementChat}, {"same-canonical-account", activeEngagementCall},
		{"same-canonical-account", activeEngagementChat | activeEngagementCall},
		{"chat-only", activeEngagementChat}, {"group-only", activeEngagementGroup}, {"active-only", activeEngagementActive},
	} {
		b29EngagementAdmit(t, store, clock, mark.account, mark.kinds)
	}
	want := activeEngagementEstimate{Active: 4, Chat: 2, Call: 1, Group: 1, Reciprocal: 2}
	b29EngagementCounts(t, store, "2026-W10", want)
	b29EngagementCounts(t, b29EngagementReload(t, store, clock, true), "2026-W10", want)
	block := b29EngagementDiskBlock(t, store.path)
	if len(block.Weeks) != 1 {
		t.Fatalf("disk weeks=%d", len(block.Weeks))
	}
	prototype, err := hyperloglog.NewNoSparse().MarshalBinary()
	if err != nil {
		t.Fatal(err)
	}
	for _, data := range [][]byte{block.Weeks[0].Active, block.Weeks[0].Chat, block.Weeks[0].Call, block.Weeks[0].Group} {
		if len(data) != len(prototype) || !bytes.Equal(data[:8], prototype[:8]) {
			t.Fatal("weekly kind is not fixed dense p14")
		}
	}
}

func TestB29E1StoreDailyMarksWeeklyButWeeklyRetryNeverCreatesDaily(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-03")}
	store := b29EngagementStore(t, clock)
	b29StoreAdmit(t, store, "2026-03-03", "daily-person")
	b29EngagementCounts(t, store, "2026-W10", activeEngagementEstimate{Active: 1})
	b29StoreAdvance(t, store, clock, b29StoreMidnight(t, "2026-03-04"))
	b29EngagementAdmit(t, store, clock, "yesterday-chat-retry", activeEngagementChat)
	b29EngagementCounts(t, store, "2026-W10", activeEngagementEstimate{Active: 2, Chat: 1, Reciprocal: 1})
	counts := b29StoreDiskEstimate(t, b29StoreDisk(t, store.path), "2026-03-04")
	if counts.Day != 0 || counts.Week != 1 {
		t.Fatalf("weekly retry fabricated daily membership: %+v", counts)
	}
}

func TestB29E1StoreDisabledAndAbsentBlockCompatibility(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-03")}
	legacy := b29NewStore(t, clock)
	b29StoreAdmit(t, legacy, "2026-03-03", "legacy")
	raw, err := os.ReadFile(legacy.path)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		t.Fatal(err)
	}
	if _, exists := fields["engagement"]; exists {
		t.Fatal("disabled legacy constructor created weekly block")
	}
	enabled := b29EngagementReload(t, legacy, clock, true)
	b29EngagementCounts(t, enabled, "2026-W10", activeEngagementEstimate{})
	b29EngagementAdmit(t, enabled, clock, "weekly", activeEngagementGroup)
	before := b29EngagementDiskBlock(t, enabled.path)
	disabled, err := newActiveIdentityStore(enabled.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatalf("old constructor cannot load known optional block: %v", err)
	}
	if values, ready := disabled.engagement(); ready || len(values) != 0 {
		t.Fatalf("disabled published %+v ready=%v", values, ready)
	}
	if err := disabled.admitEngagement("2026-W10", "forbidden", activeEngagementChat); err == nil {
		t.Fatal("disabled weekly admission ACKed")
	}
	b29StoreAdmit(t, disabled, "2026-03-03", "daily-while-disabled")
	after := b29EngagementDiskBlock(t, disabled.path)
	if !reflect.DeepEqual(before, after) {
		t.Fatal("disabled daily admission changed existing weekly aggregates")
	}
	b29EngagementCounts(t, b29EngagementReload(t, disabled, clock, true), "2026-W10", activeEngagementEstimate{Active: 1, Group: 1})
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, disabled.path), "2026-03-03"); got.Day != 2 {
		t.Fatalf("daily compatibility lost: %+v", got)
	}
}

func TestB29E1StoreDisabledPrunesWithoutCreatingWeek(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-02")}
	store := b29EngagementStore(t, clock)
	b29EngagementAdmit(t, store, clock, "old", activeEngagementChat)
	clock.set(b29StoreMidnight(t, "2026-05-04"))
	disabled := b29EngagementReload(t, store, clock, false)
	if got := b29EngagementDiskBlock(t, disabled.path); len(got.Weeks) != 0 {
		t.Fatalf("disabled retained expired or invented current week: %+v", got)
	}
	b29StoreAdmit(t, disabled, "2026-05-04", "daily-only")
	if got := b29EngagementDiskBlock(t, disabled.path); len(got.Weeks) != 0 {
		t.Fatalf("disabled daily mark created week: %+v", got)
	}
}

func TestB29E1StoreCurrentWeekCutoffAndInvalidInputNoMutation(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2027-01-03").Add(23 * time.Hour)}
	store := b29EngagementStore(t, clock)
	b29EngagementAdmit(t, store, clock, "valid", activeEngagementCall)
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	for _, input := range []struct {
		week, account string
		kinds         activeEngagementKinds
	}{
		{"2026-W52", "a", activeEngagementChat}, {"2027-W01", "a", activeEngagementChat},
		{"2026-W54", "a", activeEngagementChat}, {"2026-W53", "", activeEngagementChat},
		{"2026-W53", "a", 0}, {"2026-W53", "a", 16}, {"2026-W53", "a", 255},
	} {
		if err := store.admitEngagement(input.week, input.account, input.kinds); err == nil {
			t.Fatalf("invalid input ACKed: %+v", input)
		}
	}
	after, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("rejected input changed durable bytes")
	}
	clock.set(b29StoreMidnight(t, "2027-01-04"))
	if err := store.admitEngagement("2026-W53", "late", activeEngagementChat); err == nil {
		t.Fatal("previous-week retry ACKed after Monday cutoff")
	}
	b29EngagementAdmit(t, store, clock, "new-week", activeEngagementGroup)
	b29EngagementCounts(t, store, "2026-W53", activeEngagementEstimate{Active: 1, Call: 1, Reciprocal: 1})
	b29EngagementCounts(t, store, "2027-W01", activeEngagementEstimate{Active: 1, Group: 1})
}

func TestB29E1StoreWeekCheckedUnderAuthoritativeLock(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29").Add(22 * time.Hour)}
	store := b29EngagementStore(t, clock)
	monday := b29StoreMidnight(t, "2026-03-30")
	clockReads, unlockedRead := 0, false
	clock.setHook(func(time.Time) time.Time {
		clockReads++
		if store.mu.TryLock() {
			unlockedRead = true
			store.mu.Unlock()
		}
		return monday
	})
	err := store.admitEngagement("2026-W13", "late", activeEngagementChat)
	clock.setHook(nil)
	clock.set(b29StoreMidnight(t, "2026-03-30"))
	if err == nil {
		t.Fatal("old week admitted after authoritative Monday clock read")
	}
	if clockReads == 0 || unlockedRead {
		t.Fatalf("admission clock reads=%d outside store mutex=%v", clockReads, unlockedRead)
	}
	b29EngagementAdmit(t, store, clock, "current", activeEngagementChat)
	b29EngagementCounts(t, store, "2026-W14", activeEngagementEstimate{Active: 1, Chat: 1, Reciprocal: 1})
}

func TestB29E1StoreEightCalendarWeeksAcrossDSTAndISOYear(t *testing.T) {
	for _, start := range []string{"2026-02-23", "2026-11-30"} {
		t.Run(start, func(t *testing.T) {
			at := b29StoreMidnight(t, start)
			clock := &b29StoreClock{at: at}
			store := b29EngagementStore(t, clock)
			for i := 0; i < 10; i++ {
				clock.set(at.AddDate(0, 0, 7*i))
				b29EngagementAdmit(t, store, clock, fmt.Sprintf("person-%d", i), activeEngagementChat)
			}
			values := b29EngagementValues(t, store)
			if len(values) != 8 {
				t.Fatalf("retained %d weeks want8", len(values))
			}
			for i, value := range values {
				if want := activitycalendar.Week(at.AddDate(0, 0, 7*(i+2))); value.Week != want || value.Counts != (activeEngagementEstimate{Active: 1, Chat: 1, Reciprocal: 1}) {
					t.Fatalf("week[%d]=%+v want%s", i, value, want)
				}
			}
			reloaded := b29EngagementReload(t, store, clock, true)
			if got := b29EngagementValues(t, reloaded); !reflect.DeepEqual(values, got) {
				t.Fatalf("reload changed calendar history: %+v", got)
			}
		})
	}
}

func TestB29E1StoreFullDailyWeeklySnapshotFitsExistingLimit(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-01-05")}
	store := b29EngagementStore(t, clock)
	start := clock.now()
	for i := 0; i < 56; i++ {
		clock.set(start.AddDate(0, 0, i))
		b29StoreAdmit(t, store, activitycalendar.Day(clock.now()), fmt.Sprintf("day-%d", i))
		b29EngagementAdmit(t, store, clock, fmt.Sprintf("week-person-%d", i), activeEngagementChat|activeEngagementCall|activeEngagementGroup)
	}
	raw, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	disk := b29StoreDisk(t, store.path)
	weekly := b29EngagementDiskBlock(t, store.path)
	if len(disk.Days) != 31 || len(weekly.Weeks) != 8 {
		t.Fatalf("not full63 dense bound: days%d weeks%d", len(disk.Days), len(weekly.Weeks))
	}
	if len(raw) > 2<<20 || activeIdentityStoreSnapshotLimit != 2<<20 {
		t.Fatalf("snapshot %d exceeds unchanged2MiB limit", len(raw))
	}
	b29EngagementReload(t, store, clock, true)
}

func TestB29E1StoreFailedWriteHidesBothUntilDurableRecovery(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-02")}
	store := b29EngagementStore(t, clock)
	b29StoreAdmit(t, store, "2026-03-02", "daily")
	b29StoreAdvance(t, store, clock, b29StoreMidnight(t, "2026-03-03"))
	b29EngagementAdmit(t, store, clock, "before-failure", activeEngagementGroup)
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	store.mu.Lock()
	write := store.write
	store.write = func(string, []byte) error { return errors.New("synthetic disk failure") }
	store.mu.Unlock()
	if err := store.admitEngagement("2026-W10", "pending", activeEngagementCall); err == nil {
		t.Fatal("failed durable write ACKed")
	}
	if values, ready := store.engagement(); ready || len(values) != 0 {
		t.Fatalf("failed weekly publication %+v %v", values, ready)
	}
	if values, ready := store.finalized(); ready || len(values) != 0 {
		t.Fatalf("failed daily publication %+v %v", values, ready)
	}
	after, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("failed write replaced disk")
	}
	store.mu.Lock()
	store.write = write
	store.mu.Unlock()
	if err := store.flush(); err != nil {
		t.Fatal(err)
	}
	b29EngagementCounts(t, store, "2026-W10", activeEngagementEstimate{Active: 3, Call: 1, Group: 1, Reciprocal: 1})
	if len(b29StoreFinals(t, store)) != 1 {
		t.Fatal("daily publication did not recover with weekly snapshot")
	}
}

func b29EngagementBlockWriter(t *testing.T, store *activeIdentityStore) (<-chan struct{}, func()) {
	t.Helper()
	entered, release := make(chan struct{}), make(chan struct{})
	var first, finish sync.Once
	store.mu.Lock()
	write := store.write
	store.write = func(path string, raw []byte) error {
		var waitErr error
		first.Do(func() {
			close(entered)
			select {
			case <-release:
			case <-time.After(5 * time.Second):
				waitErr = errors.New("test writer release deadline")
			}
		})
		if waitErr != nil {
			return waitErr
		}
		return write(path, raw)
	}
	store.mu.Unlock()
	unblock := func() { finish.Do(func() { close(release) }) }
	t.Cleanup(unblock)
	return entered, unblock
}

func TestB29E1StoreAckAndFiveCountsWaitForOwnDurableGeneration(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-02")}
	store := b29EngagementStore(t, clock)
	b29EngagementAdmit(t, store, clock, "initial", activeEngagementGroup)
	before := b29EngagementValues(t, store)
	rawBefore, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	entered, release := b29EngagementBlockWriter(t, store)
	done := make(chan error, 1)
	go func() { done <- store.admitEngagement("2026-W10", "new", activeEngagementChat|activeEngagementCall) }()
	b29StoreWaitSignal(t, entered, "weekly snapshot I/O")
	select {
	case err := <-done:
		t.Fatalf("admission finished before write: %v", err)
	default:
	}
	if got := b29EngagementValues(t, store); !reflect.DeepEqual(before, got) {
		t.Fatalf("uncommitted counts published: %+v", got)
	}
	raw, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(rawBefore, raw) {
		t.Fatal("blocked writer changed durable snapshot")
	}
	release()
	if err := b29StoreWaitError(t, done, "weekly durable ACK"); err != nil {
		t.Fatal(err)
	}
	want := activeEngagementEstimate{Active: 2, Chat: 1, Call: 1, Group: 1, Reciprocal: 1}
	b29EngagementCounts(t, store, "2026-W10", want)
	b29EngagementCounts(t, b29EngagementReload(t, store, clock, true), "2026-W10", want)
}

func TestB29E1StoreMutationDuringWriteNeedsLaterGeneration(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-02")}
	store := b29EngagementStore(t, clock)
	b29EngagementAdmit(t, store, clock, "initial", activeEngagementGroup)
	entered, release := b29EngagementBlockWriter(t, store)
	first, second := make(chan error, 1), make(chan error, 1)
	go func() { first <- store.admitEngagement("2026-W10", "one", activeEngagementChat) }()
	b29StoreWaitSignal(t, entered, "first write")
	store.mu.Lock()
	generation := store.generation
	store.mu.Unlock()
	go func() { second <- store.admitEngagement("2026-W10", "two", activeEngagementCall) }()
	deadline := time.Now().Add(3 * time.Second)
	for {
		store.mu.Lock()
		changed := store.generation > generation
		store.mu.Unlock()
		if changed {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("mutation blocked by filesystem I/O")
		}
		time.Sleep(time.Millisecond)
	}
	select {
	case err := <-second:
		t.Fatalf("second generation prematurely ACKed: %v", err)
	default:
	}
	release()
	if err := b29StoreWaitError(t, first, "first ACK"); err != nil {
		t.Fatal(err)
	}
	if err := b29StoreWaitError(t, second, "second ACK"); err != nil {
		t.Fatal(err)
	}
	want := activeEngagementEstimate{Active: 3, Chat: 1, Call: 1, Group: 1, Reciprocal: 2}
	b29EngagementCounts(t, store, "2026-W10", want)
	b29EngagementCounts(t, b29EngagementReload(t, store, clock, true), "2026-W10", want)
}

func TestB29E1StorePublicationReturnsCopiesAndExpiresWithoutRefresh(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-02")}
	store := b29EngagementStore(t, clock)
	b29EngagementAdmit(t, store, clock, "one", activeEngagementChat)
	values := b29EngagementValues(t, store)
	values[0].Counts.Active = 999
	values[0].Week = "2099-W01"
	b29EngagementCounts(t, store, "2026-W10", activeEngagementEstimate{Active: 1, Chat: 1, Reciprocal: 1})
	clock.set(b29StoreMidnight(t, "2026-05-04"))
	if values := b29EngagementValues(t, store); len(values) != 0 {
		t.Fatalf("expired durable rows published: %+v", values)
	}
	clock.set(b29StoreMidnight(t, "2026-03-01"))
	if values, ready := store.engagement(); ready || len(values) != 0 {
		t.Fatalf("rollback published %+v ready%v", values, ready)
	}
}

func TestB29E1StorePrivateAggregateOnlyAndKeyEpoch(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-02")}
	store := b29EngagementStore(t, clock)
	account := "synthetic-private-canonical-account-do-not-store"
	b29EngagementAdmit(t, store, clock, account, activeEngagementChat)
	raw, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{account, "pair_digest", "contact_id", "group_id", "event_id", "account_id"} {
		if bytes.Contains(raw, []byte(forbidden)) {
			t.Fatalf("private identity/history field leaked: %s", forbidden)
		}
	}
	info, err := os.Stat(store.path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("snapshot mode=%v", info.Mode().Perm())
	}
	key := bytes.Repeat([]byte{99}, 32)
	if _, err := newActiveIdentityStoreWithEngagement(store.path, key, clock.now, true); !errors.Is(err, errActiveIdentityStoreKeyEpoch) {
		t.Fatalf("key epoch mismatch accepted: %v", err)
	}
	after, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(raw, after) {
		t.Fatal("key refusal overwrote snapshot")
	}
}

func TestB29E1StoreRejectsCorruptWeeklyBlockWithoutOverwrite(t *testing.T) {
	for _, name := range []string{"missing-weeks", "null-weeks", "unknown-field", "duplicate-week", "invalid-week", "future-week", "expired-at-saved-day", "before-measurement", "too-many-weeks", "missing-kind", "null-kind", "sparse-kind", "wrong-header", "rank-overflow", "chat-outside-active", "call-outside-active", "group-outside-active", "unknown-pair-field"} {
		t.Run(name, func(t *testing.T) {
			clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-02")}
			store := b29EngagementStore(t, clock)
			b29EngagementAdmit(t, store, clock, "valid", activeEngagementChat|activeEngagementCall|activeEngagementGroup)
			raw, err := os.ReadFile(store.path)
			if err != nil {
				t.Fatal(err)
			}
			var disk map[string]any
			if err := json.Unmarshal(raw, &disk); err != nil {
				t.Fatal(err)
			}
			var block b29EngagementDisk
			if err := json.Unmarshal(mustB29EngagementJSON(t, disk["engagement"]), &block); err != nil {
				t.Fatal(err)
			}
			if len(block.Weeks) != 1 {
				t.Fatal("missing enabled persisted weekly row")
			}
			week := block.Weeks[0]
			var row map[string]any
			if err := json.Unmarshal(mustB29EngagementJSON(t, week), &row); err != nil {
				t.Fatal(err)
			}
			engagement := map[string]any{"weeks": []any{row}}
			switch name {
			case "missing-weeks":
				delete(engagement, "weeks")
			case "null-weeks":
				engagement["weeks"] = nil
			case "unknown-field":
				engagement["people"] = []string{"forbidden"}
			case "duplicate-week":
				engagement["weeks"] = []any{row, row}
			case "invalid-week":
				row["week"] = "2026-W54"
			case "future-week":
				row["week"] = "2026-W11"
			case "expired-at-saved-day":
				row["week"] = "2026-W02"
			case "before-measurement":
				row["week"] = "2026-W09"
			case "too-many-weeks":
				engagement["weeks"] = []any{row, row, row, row, row, row, row, row, row}
			case "missing-kind":
				delete(row, "chat")
			case "null-kind":
				row["chat"] = nil
			case "sparse-kind":
				data, err := hyperloglog.New().MarshalBinary()
				if err != nil {
					t.Fatal(err)
				}
				row["chat"] = data
			case "wrong-header":
				data := bytes.Clone(week.Chat)
				data[1]++
				row["chat"] = data
			case "rank-overflow":
				active, chat := bytes.Clone(week.Active), bytes.Clone(week.Chat)
				active[8], chat[8] = 51, 51
				row["active"], row["chat"] = active, chat
				disk["engagement"] = engagement
				if err := os.WriteFile(store.path, mustB29EngagementJSON(t, disk), 0600); err != nil {
					t.Fatal(err)
				}
				for _, enabled := range []bool{false, true} {
					b29EngagementReload(t, store, clock, enabled)
					control := b29EngagementDiskBlock(t, store.path)
					if len(control.Weeks) != 1 || control.Weeks[0].Active[8] != 51 || control.Weeks[0].Chat[8] != 51 {
						t.Fatalf("valid maximum rank was lost on reload enabled=%v", enabled)
					}
				}
				active[8], chat[8] = 52, 52
			case "chat-outside-active", "call-outside-active", "group-outside-active":
				kind := name[:len(name)-len("-outside-active")]
				data := bytes.Clone(week.Active)
				changed := false
				for i := 8; i < len(data); i++ {
					if data[i] < 51 {
						data[i]++
						changed = true
						break
					}
				}
				if !changed {
					t.Fatal("fixture has no available register")
				}
				row[kind] = data
			case "unknown-pair-field":
				row["pair_digest"] = "forbidden"
			}
			disk["engagement"] = engagement
			corrupt := mustB29EngagementJSON(t, disk)
			if err := os.WriteFile(store.path, corrupt, 0600); err != nil {
				t.Fatal(err)
			}
			for _, enabled := range []bool{false, true} {
				if _, err := newActiveIdentityStoreWithEngagement(store.path, b29StoreKey(), clock.now, enabled); err == nil {
					t.Fatalf("corrupt %s accepted enabled=%v", name, enabled)
				}
				after, err := os.ReadFile(store.path)
				if err != nil {
					t.Fatal(err)
				}
				if !bytes.Equal(corrupt, after) {
					t.Fatalf("rejected %s overwritten enabled=%v", name, enabled)
				}
			}
		})
	}
}

func mustB29EngagementJSON(t *testing.T, value any) []byte {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func TestB29E1StoreDirtyWeekReachesDiskBeforeLongJumpPruning(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-02")}
	store := b29EngagementStore(t, clock)
	b29EngagementAdmit(t, store, clock, "initial", activeEngagementGroup)
	var writesMu sync.Mutex
	var persisted []b29EngagementDisk
	store.mu.Lock()
	write := store.write
	store.write = func(path string, raw []byte) error {
		var disk struct {
			Engagement b29EngagementDisk `json:"engagement"`
		}
		if err := json.Unmarshal(raw, &disk); err != nil {
			return err
		}
		if err := write(path, raw); err != nil {
			return err
		}
		writesMu.Lock()
		persisted = append(persisted, disk.Engagement)
		writesMu.Unlock()
		return nil
	}
	store.mu.Unlock()
	entered, release := b29EngagementBlockWriter(t, store)
	first, second, advance := make(chan error, 1), make(chan error, 1), make(chan error, 1)
	go func() { first <- store.admitEngagement("2026-W10", "one", activeEngagementChat) }()
	b29StoreWaitSignal(t, entered, "old-week write")
	store.mu.Lock()
	generation := store.generation
	store.mu.Unlock()
	go func() { second <- store.admitEngagement("2026-W10", "two", activeEngagementChat) }()
	deadline := time.Now().Add(3 * time.Second)
	for {
		store.mu.Lock()
		changed := store.generation > generation
		store.mu.Unlock()
		if changed {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("second old-week mutation did not enter")
		}
		time.Sleep(time.Millisecond)
	}
	clock.set(b29StoreMidnight(t, "2026-05-04"))
	advanceRead := make(chan struct{})
	var advanceOnce sync.Once
	clock.setHook(func(at time.Time) time.Time {
		advanceOnce.Do(func() { close(advanceRead) })
		return at
	})
	go func() { advance <- store.advance() }()
	b29StoreWaitSignal(t, advanceRead, "advance clock checkpoint")
	deadline = time.Now().Add(3 * time.Second)
	for !store.mu.TryLock() {
		if time.Now().After(deadline) {
			t.Fatal("advance did not release calendar mutex before writer release")
		}
		time.Sleep(time.Millisecond)
	}
	store.mu.Unlock()
	clock.setHook(nil)
	release()
	for name, ch := range map[string]<-chan error{"first": first, "second": second, "advance": advance} {
		if err := b29StoreWaitError(t, ch, name); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
	}
	writesMu.Lock()
	defer writesMu.Unlock()
	sawBoth := false
	for _, disk := range persisted {
		for _, week := range disk.Weeks {
			if week.Week == "2026-W10" {
				sketch := hyperloglog.NewNoSparse()
				if err := sketch.UnmarshalBinary(week.Chat); err != nil {
					t.Fatal(err)
				}
				if sketch.Estimate() == 2 {
					sawBoth = true
				}
			}
		}
	}
	if !sawBoth {
		t.Fatal("ACKed old-week contribution pruned before any durable generation contained it")
	}
	values := b29EngagementValues(t, store)
	if len(values) != 1 || values[0].Week != "2026-W19" || values[0].Counts != (activeEngagementEstimate{}) {
		t.Fatalf("long jump retention=%+v", values)
	}
}
