package node

import (
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/activitycalendar"
)

func TestB29CalendarBerlinDayUsesInstantInsteadOfCallerZone(t *testing.T) {
	for _, tc := range []struct{ instant, day string }{
		{"2026-03-28T22:59:59Z", "2026-03-28"},
		{"2026-03-28T23:00:00Z", "2026-03-29"},
		{"2026-03-29T00:59:59Z", "2026-03-29"},
		{"2026-03-29T01:00:00Z", "2026-03-29"},
		{"2026-03-29T21:59:59Z", "2026-03-29"},
		{"2026-03-29T22:00:00Z", "2026-03-30"},
		{"2026-10-24T22:00:00Z", "2026-10-25"},
		{"2026-10-25T00:59:59Z", "2026-10-25"},
		{"2026-10-25T01:00:00Z", "2026-10-25"},
		{"2026-10-25T22:59:59Z", "2026-10-25"},
		{"2026-10-25T23:00:00Z", "2026-10-26"},
	} {
		t.Run(tc.instant, func(t *testing.T) {
			at, err := time.Parse(time.RFC3339, tc.instant)
			if err != nil {
				t.Fatal(err)
			}
			for _, offset := range []int{-12 * 3600, 0, 14 * 3600} {
				if got := activitycalendar.Day(at.In(time.FixedZone("caller", offset))); got != tc.day {
					t.Fatalf("instant %s caller offset %d: day=%q, want %q", tc.instant, offset, got, tc.day)
				}
			}
		})
	}
}

func TestB29CalendarUsesCalendarDaysAcrossDST(t *testing.T) {
	for _, tc := range []struct {
		day, next string
		hours     time.Duration
	}{
		{"2026-03-29", "2026-03-30", 23 * time.Hour},
		{"2026-10-25", "2026-10-26", 25 * time.Hour},
	} {
		t.Run(tc.day, func(t *testing.T) {
			start, err := activitycalendar.Parse(tc.day)
			if err != nil {
				t.Fatal(err)
			}
			next, err := activitycalendar.Parse(tc.next)
			if err != nil {
				t.Fatal(err)
			}
			if got := next.Sub(start); got != tc.hours {
				t.Fatalf("Berlin day length=%v, want %v", got, tc.hours)
			}
			if start.Hour() != 0 || start.Location().String() != "Europe/Berlin" {
				t.Fatalf("not Berlin midnight: %v", start)
			}
		})
	}
}

func TestB29CalendarWindowsAreInclusiveCalendarDates(t *testing.T) {
	for _, tc := range []struct {
		day         string
		count       int
		first, last string
	}{
		{"2026-03-30", 1, "2026-03-30", "2026-03-30"},
		{"2026-03-30", 7, "2026-03-24", "2026-03-30"},
		{"2026-03-30", 30, "2026-03-01", "2026-03-30"},
		{"2026-10-26", 7, "2026-10-20", "2026-10-26"},
		{"2026-01-01", 7, "2025-12-26", "2026-01-01"},
		{"2024-03-01", 3, "2024-02-28", "2024-03-01"},
		{"2026-11-14", 31, "2026-10-15", "2026-11-14"},
	} {
		t.Run(tc.day+"/"+tc.first, func(t *testing.T) {
			got, err := activitycalendar.WindowEnding(tc.day, tc.count)
			if err != nil {
				t.Fatal(err)
			}
			if len(got) != tc.count || got[0] != tc.first || got[len(got)-1] != tc.last {
				t.Fatalf("window=%v, want %d dates %s..%s", got, tc.count, tc.first, tc.last)
			}
			if tc.count == 3 && !reflect.DeepEqual(got, []string{"2024-02-28", "2024-02-29", "2024-03-01"}) {
				t.Fatalf("leap-day window=%v", got)
			}
			for i := 1; i < len(got); i++ {
				before, err := activitycalendar.Parse(got[i-1])
				if err != nil {
					t.Fatal(err)
				}
				if before.AddDate(0, 0, 1).Format("2006-01-02") != got[i] {
					t.Fatalf("nonconsecutive calendar dates %v", got)
				}
			}
		})
	}
}

func TestB29CalendarRejectsNoncanonicalDaysAndInvalidWindows(t *testing.T) {
	// Positive controls prevent an always-error implementation passing this test.
	if _, err := activitycalendar.Parse("2026-11-14"); err != nil {
		t.Fatal(err)
	}
	if got, err := activitycalendar.WindowEnding("2026-11-14", 7); err != nil || len(got) != 7 {
		t.Fatalf("valid window rejected: %v %v", got, err)
	}
	for _, day := range []string{"", "2026-1-01", "2026-01-1", "2026-02-29", "2026-13-01", "2026-11-14Z", " 2026-11-14", "2026-11-14T00:00:00Z"} {
		if _, err := activitycalendar.Parse(day); !errors.Is(err, activitycalendar.ErrInvalidDay) {
			t.Errorf("Parse(%q) error=%v, want ErrInvalidDay", day, err)
		}
		if _, err := activitycalendar.WindowEnding(day, 7); !errors.Is(err, activitycalendar.ErrInvalidDay) {
			t.Errorf("WindowEnding(%q,7) error=%v, want ErrInvalidDay", day, err)
		}
	}
	for _, count := range []int{-1, 0, 32} {
		if _, err := activitycalendar.WindowEnding("2026-11-14", count); !errors.Is(err, activitycalendar.ErrInvalidWindow) {
			t.Errorf("window count%d error=%v, want ErrInvalidWindow", count, err)
		}
	}
}
