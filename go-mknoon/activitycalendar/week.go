package activitycalendar

import (
	"errors"
	"fmt"
	"strconv"
	"time"
)

var ErrInvalidWeek = errors.New("invalid Berlin activity week")

// Week returns the Berlin ISO week-year and week of the instant.
func Week(at time.Time) string {
	year, week := at.In(berlinLocation).ISOWeek()
	return fmt.Sprintf("%04d-W%02d", year, week)
}

// ParseWeek accepts only a canonical ISO week and returns its Berlin Monday.
func ParseWeek(week string) (time.Time, error) {
	if len(week) != 8 || week[4:6] != "-W" {
		return time.Time{}, ErrInvalidWeek
	}
	for _, i := range []int{0, 1, 2, 3, 6, 7} {
		if week[i] < '0' || week[i] > '9' {
			return time.Time{}, ErrInvalidWeek
		}
	}
	year, _ := strconv.Atoi(week[:4])
	number, _ := strconv.Atoi(week[6:])
	if number < 1 || number > 53 {
		return time.Time{}, ErrInvalidWeek
	}
	// January 4 always belongs to ISO week 1; move to its Monday by calendar days.
	fourth := time.Date(year, time.January, 4, 0, 0, 0, 0, berlinLocation)
	monday := fourth.AddDate(0, 0, -(int(fourth.Weekday())+6)%7+(number-1)*7)
	if Week(monday) != week {
		return time.Time{}, ErrInvalidWeek
	}
	return monday, nil
}

// WeekWindowEnding returns up to eight ascending calendar weeks, including end.
func WeekWindowEnding(week string, count int) ([]string, error) {
	if count < 1 || count > 8 {
		return nil, ErrInvalidWindow
	}
	end, err := ParseWeek(week)
	if err != nil {
		return nil, err
	}
	weeks := make([]string, count)
	start := end.AddDate(0, 0, 7*(1-count))
	for i := range weeks {
		weeks[i] = Week(start.AddDate(0, 0, 7*i))
	}
	return weeks, nil
}
