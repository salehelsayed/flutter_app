package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/mknoon/go-mknoon/activitycalendar"
	"github.com/prometheus/client_golang/prometheus"
)

func newConfiguredActiveIdentityStore() (*activeIdentityStore, error) {
	enabled := strings.ToLower(strings.TrimSpace(os.Getenv("MKNOON_RELAY_ACTIVE_IDENTITIES_ENABLED")))
	if enabled == "" || enabled == "false" {
		return nil, nil
	}
	weekly := strings.ToLower(strings.TrimSpace(os.Getenv("MKNOON_RELAY_ENGAGEMENT_ENABLED")))
	path := os.Getenv("MKNOON_RELAY_ACTIVE_IDENTITIES_SNAPSHOT_PATH")
	if enabled != "true" || (weekly != "" && weekly != "false" && weekly != "true") || !filepath.IsAbs(path) {
		return nil, errors.New("invalid active counter configuration")
	}
	// The dedicated BL29 key is never inherited from other analytics counters.
	return newActiveIdentityStoreWithEngagement(path, []byte(os.Getenv("MKNOON_RELAY_ACTIVE_IDENTITIES_KEY")), time.Now, weekly == "true")
}

var (
	activeIdentityReadyDesc      = prometheus.NewDesc("relay_active_identities_storage_ready", "Whether durable consented active identity aggregates are available.", nil, nil)
	activeIdentityEstimateDesc   = prometheus.NewDesc("relay_active_identities_estimated", "Estimated consenting app identities in observed Berlin calendar windows; coverage is incomplete.", []string{"window", "day"}, nil)
	activeIdentityCoverageDesc   = prometheus.NewDesc("relay_active_identities_coverage_partial", "Whether observation of the closed Berlin day was partial or unknown. Counts on those days estimate observed marks only.", []string{"day"}, nil)
	activeEngagementReadyDesc    = prometheus.NewDesc("relay_engagement_storage_ready", "Whether durable consented weekly engagement aggregates are available.", nil, nil)
	activeEngagementEstimateDesc = prometheus.NewDesc("relay_engagement_weekly_estimated", "Estimated consenting app identities by Berlin ISO week and engagement kind; reciprocal is the chat/call union. Coverage is incomplete.", []string{"week", "kind"}, nil)
	featureUseReadyDesc          = prometheus.NewDesc("relay_feature_use_storage_ready", "Whether durable consented weekly feature use estimates are available.", nil, nil)
	featureUseEstimateDesc       = prometheus.NewDesc("relay_feature_use_weekly_estimated", "Estimated consenting app identities by Berlin ISO week and feature. Coverage is incomplete.", []string{"week", "feature"}, nil)
)

func (s *InboxStore) Describe(ch chan<- *prometheus.Desc) {
	ch <- activeIdentityReadyDesc
	ch <- activeIdentityEstimateDesc
	ch <- activeIdentityCoverageDesc
	ch <- activeDeviceEstimateDesc
	ch <- activeDeviceCoverageDesc
	ch <- activeEngagementReadyDesc
	ch <- activeEngagementEstimateDesc
	ch <- featureUseReadyDesc
	ch <- featureUseEstimateDesc
}

func (s *InboxStore) Collect(ch chan<- prometheus.Metric) {
	if s != nil && s.activeDevices != nil {
		collectActiveDevices(ch, s.activeDevices)
	}
	var daily []activeIdentityFinalized
	var weekly []activeEngagementWeek
	var dailyReady, weeklyReady bool
	if s != nil && s.activeIdentities != nil {
		store := s.activeIdentities
		// Capture both families from one durable generation. Scraping never waits
		// for the snapshot writer or publishes in-memory, unacknowledged changes.
		store.mu.Lock()
		at := store.now()
		dailyReady = store.healthy && !at.IsZero() && activitycalendar.Day(at) >= store.openDay.Day && !at.Before(store.openDay.ObservingFrom)
		weeklyReady = dailyReady && store.engagementEnabled
		if dailyReady {
			today := activitycalendar.Day(at)
			midnight, err := activitycalendar.Parse(today)
			if err == nil {
				first := midnight.AddDate(0, 0, -7).Format("2006-01-02")
				for _, value := range store.durableFinals {
					if value.Day >= first && value.Day < today {
						daily = append(daily, value)
					}
				}
			}
		}
		if weeklyReady {
			week := activitycalendar.Week(at)
			window, err := activitycalendar.WeekWindowEnding(week, 8)
			if err == nil {
				for _, value := range store.durableEngagement {
					if value.Week >= window[0] && value.Week <= week {
						weekly = append(weekly, value)
					}
				}
			}
		}
		store.mu.Unlock()
	}
	dailyFlag, weeklyFlag := 0., 0.
	if dailyReady {
		dailyFlag = 1
	}
	if weeklyReady {
		weeklyFlag = 1
	}
	ch <- prometheus.MustNewConstMetric(activeIdentityReadyDesc, prometheus.GaugeValue, dailyFlag)
	ch <- prometheus.MustNewConstMetric(activeEngagementReadyDesc, prometheus.GaugeValue, weeklyFlag)
	for _, value := range daily {
		partial := 0.
		if value.Partial {
			partial = 1
		}
		ch <- prometheus.MustNewConstMetric(activeIdentityCoverageDesc, prometheus.GaugeValue, partial, value.Day)
		for i, window := range []string{"1d", "7d", "30d"} {
			counts := [3]uint64{value.Counts.Day, value.Counts.Week, value.Counts.Month}
			ch <- prometheus.MustNewConstMetric(activeIdentityEstimateDesc, prometheus.GaugeValue, float64(counts[i]), window, value.Day)
		}
	}
	for _, value := range weekly {
		counts := [5]uint64{value.Counts.Active, value.Counts.Chat, value.Counts.Call, value.Counts.Group, value.Counts.Reciprocal}
		for i, kind := range []string{"active", "chat", "call", "group", "reciprocal"} {
			ch <- prometheus.MustNewConstMetric(activeEngagementEstimateDesc, prometheus.GaugeValue, float64(counts[i]), value.Week, kind)
		}
	}
	var featureWeeks []featureUseEstimate
	var featureReady bool
	if s != nil && s.featureUse != nil {
		featureWeeks, featureReady = s.featureUse.estimates()
	}
	featureFlag := 0.
	if featureReady {
		featureFlag = 1
	}
	ch <- prometheus.MustNewConstMetric(featureUseReadyDesc, prometheus.GaugeValue, featureFlag)
	for _, week := range featureWeeks {
		for i, name := range featureUseNames {
			ch <- prometheus.MustNewConstMetric(featureUseEstimateDesc, prometheus.GaugeValue, float64(week.Counts[i]), week.Week, name)
		}
	}
}
