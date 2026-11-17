// Package activitycalendar owns the Berlin calendar used by the local activity
// reporter and the relay. Its separate, standard-library-only module avoids
// importing the mobile networking dependency graph into the relay.
package activitycalendar

import (
	"errors"
	"time"
	_ "time/tzdata"
)

const dateLayout = "2006-01-02"

var (
	ErrInvalidDay    = errors.New("invalid Berlin activity day")
	ErrInvalidWindow = errors.New("invalid activity calendar window")
	berlinLocation   = func() *time.Location {
		location, err := time.LoadLocation("Europe/Berlin")
		if err != nil {
			panic(err)
		}
		return location
	}()
)

// Day returns the Berlin calendar date of the instant, regardless of caller zone.
func Day(at time.Time) string { return at.In(berlinLocation).Format(dateLayout) }

// Parse accepts only a canonical date and returns its Berlin midnight.
func Parse(day string) (time.Time, error) {
	if len(day) != len(dateLayout) {
		return time.Time{}, ErrInvalidDay
	}
	parsed, err := time.ParseInLocation(dateLayout, day, berlinLocation)
	if err != nil || parsed.Format(dateLayout) != day {
		return time.Time{}, ErrInvalidDay
	}
	return parsed, nil
}

// WindowEnding returns ascending calendar dates, including the final day.
func WindowEnding(day string, count int) ([]string, error) {
	if count < 1 || count > 31 {
		return nil, ErrInvalidWindow
	}
	end, err := Parse(day)
	if err != nil {
		return nil, err
	}
	days := make([]string, count)
	start := end.AddDate(0, 0, 1-count)
	for i := range days {
		days[i] = start.AddDate(0, 0, i).Format(dateLayout)
	}
	return days, nil
}
