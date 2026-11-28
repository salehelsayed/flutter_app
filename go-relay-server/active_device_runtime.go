package main

import "github.com/prometheus/client_golang/prometheus"

var (
	activeDeviceEstimateDesc = prometheus.NewDesc("relay_active_devices_estimated", "Estimated transport devices with qualifying relay admissions in observed Berlin calendar windows.", []string{"window", "day"}, nil)
	activeDeviceCoverageDesc = prometheus.NewDesc("relay_active_devices_coverage_partial", "Whether observation of the closed Berlin day for relay active devices was partial or unknown.", []string{"day"}, nil)
)

func collectActiveDevices(ch chan<- prometheus.Metric, store *activeIdentityStore) {
	days, ready := store.finalized()
	if !ready {
		return
	}
	for _, day := range days {
		partial := 0.
		if day.Partial {
			partial = 1
		}
		ch <- prometheus.MustNewConstMetric(activeDeviceCoverageDesc, prometheus.GaugeValue, partial, day.Day)
		counts := [3]uint64{day.Counts.Day, day.Counts.Week, day.Counts.Month}
		for index, window := range []string{"1d", "7d", "30d"} {
			ch <- prometheus.MustNewConstMetric(activeDeviceEstimateDesc, prometheus.GaugeValue, float64(counts[index]), window, day.Day)
		}
	}
}
