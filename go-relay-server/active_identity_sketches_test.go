package main

import (
	"bytes"
	"encoding/hex"
	"errors"
	"fmt"
	"testing"

	"github.com/axiomhq/hyperloglog"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

func b29Sketches(t *testing.T) *activeDailySketches {
	t.Helper()
	sketches, err := newActiveDailySketches(bytes.Repeat([]byte{17}, 32))
	if err != nil {
		t.Fatal(err)
	}
	return sketches
}

func b29Insert(t *testing.T, sketches *activeDailySketches, day, account string) {
	t.Helper()
	if err := sketches.insert(day, account); err != nil {
		t.Fatal(err)
	}
}

func b29Estimate(t *testing.T, sketches *activeDailySketches, day string) activeIdentityEstimate {
	t.Helper()
	got, err := sketches.estimate(day)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

func TestB29SketchRepeatedCanonicalIdentityAcrossDaysCountsOnce(t *testing.T) {
	sketches := b29Sketches(t)
	days, err := activitycalendar.WindowEnding("2026-11-14", 30)
	if err != nil {
		t.Fatal(err)
	}
	for _, day := range days {
		// The account proof layer supplies this same canonical account for linked
		// devices. This unit tests aggregation, not account-proof authentication.
		for range 4 {
			b29Insert(t, sketches, day, "canonical-account-A")
		}
	}
	if got := b29Estimate(t, sketches, "2026-11-14"); got != (activeIdentityEstimate{Day: 1, Week: 1, Month: 1}) {
		t.Fatalf("same account repeated across days/devices=%+v, want1/1/1", got)
	}
}

func TestB29SketchInclusiveSixAndTwentyNineDayBoundaries(t *testing.T) {
	for _, day := range []string{"2026-03-30", "2026-10-26", "2026-01-02"} {
		t.Run(day, func(t *testing.T) {
			sketches := b29Sketches(t)
			at, err := activitycalendar.Parse(day)
			if err != nil {
				t.Fatal(err)
			}
			for _, row := range []struct {
				offset  int
				account string
			}{
				{0, "account-today"}, {-6, "account-six-days-ago"},
				{-7, "account-seven-days-ago"}, {-29, "account-twenty-nine-days-ago"},
				{-30, "account-too-old"}, {1, "account-future"},
			} {
				b29Insert(t, sketches, at.AddDate(0, 0, row.offset).Format("2006-01-02"), row.account)
			}
			if got := b29Estimate(t, sketches, day); got != (activeIdentityEstimate{Day: 1, Week: 2, Month: 4}) {
				t.Fatalf("window=%+v, want1/2/4; closed/future admission is checked by the later store", got)
			}
		})
	}
}

func TestB29SketchUnionsDoNotModifyDailyRegisters(t *testing.T) {
	sketches := b29Sketches(t)
	b29Insert(t, sketches, "2026-11-13", "account-yesterday")
	b29Insert(t, sketches, "2026-11-14", "account-today")
	before, err := sketches.days["2026-11-14"].MarshalBinary()
	if err != nil {
		t.Fatal(err)
	}
	for range 3 {
		if got := b29Estimate(t, sketches, "2026-11-14"); got != (activeIdentityEstimate{Day: 1, Week: 2, Month: 2}) {
			t.Fatalf("estimate mutated daily count: %+v", got)
		}
	}
	after, err := sketches.days["2026-11-14"].MarshalBinary()
	if err != nil || !bytes.Equal(before, after) {
		t.Fatalf("union changed original registers: %v", err)
	}
	if got := b29Estimate(t, sketches, "2026-11-13"); got != (activeIdentityEstimate{Day: 1, Week: 1, Month: 1}) {
		t.Fatalf("later activity changed prior window: %+v", got)
	}
}

func TestB29SketchUsesDenseEncodingFromFirstIdentity(t *testing.T) {
	sketches := b29Sketches(t)
	b29Insert(t, sketches, "2026-11-14", "canonical-account-A")
	raw, err := sketches.days["2026-11-14"].MarshalBinary()
	if err != nil {
		t.Fatal(err)
	}
	prototype, err := hyperloglog.NewNoSparse().MarshalBinary()
	if err != nil {
		t.Fatal(err)
	}
	if len(raw) != len(prototype) || !bytes.Equal(raw[:8], prototype[:8]) {
		t.Fatalf("not the existing fixed dense HLL format: bytes%d want%d", len(raw), len(prototype))
	}
	if bytes.Contains(raw, []byte("canonical-account-A")) {
		t.Fatal("raw canonical account retained in sketch")
	}
}

func TestB29SketchDedicatedStableKeyedAccountDomain(t *testing.T) {
	key := bytes.Repeat([]byte{17}, 32)
	// HMAC-SHA256 golden vector: key=32 bytes0x11, message=the fixed
	// BL-29 account domain followed by canonical-account-A. No day/device salt.
	want, err := hex.DecodeString("3d7a81366f3799a6b3e75a200aa20361559ef2a824f2cf536e3ef6914de3c005")
	if err != nil {
		t.Fatal(err)
	}
	if got := activeIdentityDigest(key, "canonical-account-A"); !bytes.Equal(got, want) {
		t.Fatalf("dedicated account HMAC differs: %x", got)
	}
	if bytes.Equal(activeIdentityDigest(bytes.Repeat([]byte{18}, 32), "canonical-account-A"), want) {
		t.Fatal("different secret did not change keyed account")
	}
	if bytes.Equal(activeIdentityDigest(key, "canonical-account-B"), want) {
		t.Fatal("different canonical account did not change keyed account")
	}
}

func TestB29SketchOwnsKeyBytesAcrossDays(t *testing.T) {
	key := bytes.Repeat([]byte{17}, 32)
	sketches, err := newActiveDailySketches(key)
	if err != nil {
		t.Fatal(err)
	}
	b29Insert(t, sketches, "2026-11-13", "canonical-account-A")
	key[0] ^= 0xff
	b29Insert(t, sketches, "2026-11-14", "canonical-account-A")
	if got := b29Estimate(t, sketches, "2026-11-14"); got != (activeIdentityEstimate{Day: 1, Week: 1, Month: 1}) {
		t.Fatalf("caller mutated the retained key: %+v", got)
	}
}

func TestB29SketchDistinctAccountsStayDistinctWithinApproximation(t *testing.T) {
	sketches := b29Sketches(t)
	for i := range 10000 {
		b29Insert(t, sketches, "2026-11-14", fmt.Sprintf("canonical-account-%d", i))
	}
	got := b29Estimate(t, sketches, "2026-11-14")
	if got.Day < 9500 || got.Day > 10500 || got.Week != got.Day || got.Month != got.Day {
		t.Fatalf("distinct account estimate=%+v; want10000 within5%%, same unions", got)
	}
}

func TestB29SketchRejectsInvalidInputsWithoutMutation(t *testing.T) {
	// A valid constructor, insertion and estimate are controls for each refusal.
	sketches := b29Sketches(t)
	b29Insert(t, sketches, "2026-11-14", "canonical-account-A")
	want := b29Estimate(t, sketches, "2026-11-14")
	for _, key := range [][]byte{nil, {1}, bytes.Repeat([]byte{17}, 31), bytes.Repeat([]byte{17}, 33)} {
		if _, err := newActiveDailySketches(key); !errors.Is(err, errActiveIdentityKey) {
			t.Errorf("key bytes%d error=%v, want specific key refusal", len(key), err)
		}
	}
	if err := sketches.insert("2026-11-14", ""); !errors.Is(err, errActiveIdentityAccount) {
		t.Errorf("empty account error=%v", err)
	}
	for _, day := range []string{"", "2026-02-29", "2026-1-01", "2026-11-14T00:00:00Z"} {
		if err := sketches.insert(day, "canonical-account-B"); !errors.Is(err, activitycalendar.ErrInvalidDay) {
			t.Errorf("insert invalid day %q error=%v", day, err)
		}
		if _, err := sketches.estimate(day); !errors.Is(err, activitycalendar.ErrInvalidDay) {
			t.Errorf("estimate invalid day %q error=%v", day, err)
		}
	}
	if got := b29Estimate(t, sketches, "2026-11-14"); got != want || len(sketches.days) != 1 {
		t.Fatalf("refused input changed state: estimate%+v days%d", got, len(sketches.days))
	}
}
