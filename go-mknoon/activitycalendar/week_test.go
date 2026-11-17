package activitycalendar

import (
	"errors"
	"reflect"
	"testing"
	"time"
)

func TestB29E1WeekBerlinBoundaryAndISOYear(t *testing.T) {
	for _, row := range []struct{ instant, want string }{
		{"2026-11-15T22:59:59Z", "2026-W46"},
		{"2026-11-15T23:00:00Z", "2026-W47"},
		{"2026-03-29T21:59:59Z", "2026-W13"},
		{"2026-03-29T22:00:00Z", "2026-W14"},
		{"2026-10-25T22:59:59Z", "2026-W43"},
		{"2026-10-25T23:00:00Z", "2026-W44"},
		{"2021-01-01T12:00:00Z", "2020-W53"},
		{"2024-12-30T12:00:00Z", "2025-W01"},
	} {
		t.Run(row.instant, func(t *testing.T) {
			at, err := time.Parse(time.RFC3339, row.instant)
			if err != nil {
				t.Fatal(err)
			}
			for _, zone := range []*time.Location{time.UTC, time.FixedZone("phone west", -10*3600), time.FixedZone("phone east", 14*3600)} {
				if got := Week(at.In(zone)); got != row.want {
					t.Errorf("zone=%s week=%q want=%q", zone, got, row.want)
				}
			}
		})
	}
}

func TestB29E1WeekParseCanonicalMonday(t *testing.T) {
	for _, row := range []struct{ week, monday string }{
		{"2020-W53", "2020-12-28T00:00:00+01:00"},
		{"2025-W01", "2024-12-30T00:00:00+01:00"},
		{"2026-W14", "2026-03-30T00:00:00+02:00"},
		{"2026-W44", "2026-10-26T00:00:00+01:00"},
	} {
		t.Run(row.week, func(t *testing.T) {
			got, err := ParseWeek(row.week)
			if err != nil {
				t.Fatal(err)
			}
			if got.Format(time.RFC3339) != row.monday || got.Weekday() != time.Monday || Week(got) != row.week {
				t.Fatalf("Monday=%s roundtrip=%s want=%s", got, Week(got), row.monday)
			}
		})
	}
}

func TestB29E1WeekRejectsNoncanonicalAndImpossibleWeeks(t *testing.T) {
	if _, err := ParseWeek("2020-W53"); err != nil {
		t.Fatalf("valid control: %v", err)
	}
	for _, value := range []string{"", "2026-W00", "2026-W54", "2021-W53", "2026-W1", "2026-w01", "2026-W001", " 2026-W01", "2026-W01\n", "2026-W01T00:00", "abcd-W01", "2026-01", "2026-W+1"} {
		if _, err := ParseWeek(value); !errors.Is(err, ErrInvalidWeek) {
			t.Errorf("%q error=%v", value, err)
		}
	}
}

func TestB29E1WeekEightCalendarWeeksCrossYear(t *testing.T) {
	got, err := WeekWindowEnding("2021-W02", 8)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"2020-W48", "2020-W49", "2020-W50", "2020-W51", "2020-W52", "2020-W53", "2021-W01", "2021-W02"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("window=%v want=%v", got, want)
	}
	one, err := WeekWindowEnding("2026-W46", 1)
	if err != nil || !reflect.DeepEqual(one, []string{"2026-W46"}) {
		t.Fatalf("one=%v error=%v", one, err)
	}
}

func TestB29E1WeekDSTUsesCalendarNot168Hours(t *testing.T) {
	for _, row := range []struct {
		end   string
		hours time.Duration
		want  []string
	}{
		{"2026-W14", 167, []string{"2026-W13", "2026-W14"}},
		{"2026-W44", 169, []string{"2026-W43", "2026-W44"}},
	} {
		got, err := WeekWindowEnding(row.end, 2)
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, row.want) {
			t.Fatalf("window=%v want=%v", got, row.want)
		}
		start, err := ParseWeek(got[0])
		if err != nil {
			t.Fatal(err)
		}
		end, err := ParseWeek(got[1])
		if err != nil {
			t.Fatal(err)
		}
		if end.Sub(start) != row.hours*time.Hour {
			t.Fatalf("elapsed=%s want=%dh", end.Sub(start), row.hours)
		}
	}
}

func TestB29E1WeekWindowRejectsInvalidBounds(t *testing.T) {
	if _, err := WeekWindowEnding("2026-W46", 8); err != nil {
		t.Fatalf("valid control: %v", err)
	}
	for _, count := range []int{-1, 0, 9, 1000000} {
		if _, err := WeekWindowEnding("2026-W46", count); !errors.Is(err, ErrInvalidWindow) {
			t.Errorf("count=%d error=%v", count, err)
		}
	}
	if _, err := WeekWindowEnding("2021-W53", 8); !errors.Is(err, ErrInvalidWeek) {
		t.Fatalf("invalid week error=%v", err)
	}
}
