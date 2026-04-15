package node

import (
	"encoding/json"
	"sort"
	"testing"
)

// --- Benchmark helpers (test-only, not shipped) ---

// collectEvents filters collected events by event name, returning the data map
// from each matching event.
func (c *testEventCollector) collectEvents(eventName string) []map[string]interface{} {
	var result []map[string]interface{}
	for _, raw := range c.snapshot() {
		var ev map[string]interface{}
		if err := json.Unmarshal([]byte(raw), &ev); err != nil {
			continue
		}
		if evName, _ := ev["event"].(string); evName == eventName {
			if data, ok := ev["data"].(map[string]interface{}); ok {
				result = append(result, data)
			}
		}
	}
	return result
}

// extractElapsedMs extracts and sorts the elapsedMs field from event data maps.
func extractElapsedMs(events []map[string]interface{}) []int {
	var result []int
	for _, ev := range events {
		if ms, ok := ev["elapsedMs"].(float64); ok {
			result = append(result, int(ms))
		}
	}
	sort.Ints(result)
	return result
}

// benchmarkPercentile computes the p-th percentile from a sorted slice using
// linear interpolation between adjacent ranks.
func benchmarkPercentile(sorted []int, p int) int {
	if len(sorted) == 0 {
		return 0
	}
	if len(sorted) == 1 {
		return sorted[0]
	}
	rank := float64(p) / 100.0 * float64(len(sorted)-1)
	lower := int(rank)
	upper := lower + 1
	if upper >= len(sorted) {
		upper = len(sorted) - 1
	}
	return (sorted[lower] + sorted[upper]) / 2
}

// --- Tests ---

func TestBenchmarkCollectEvents_FiltersByEventName(t *testing.T) {
	collector := &testEventCollector{}
	// Emit 5 events: 3 "stream:open_timing", 2 "relay:state"
	for i := 0; i < 3; i++ {
		ev, _ := json.Marshal(map[string]interface{}{
			"event": "stream:open_timing",
			"data":  map[string]interface{}{"elapsedMs": float64(i * 10)},
		})
		collector.OnEvent(string(ev))
	}
	for i := 0; i < 2; i++ {
		ev, _ := json.Marshal(map[string]interface{}{
			"event": "relay:state",
			"data":  map[string]interface{}{"state": "online"},
		})
		collector.OnEvent(string(ev))
	}

	result := collector.collectEvents("stream:open_timing")
	if len(result) != 3 {
		t.Fatalf("expected 3 events, got %d", len(result))
	}
}

func TestBenchmarkExtractElapsedMs_ParsesAndSorts(t *testing.T) {
	events := []map[string]interface{}{
		{"elapsedMs": float64(200)},
		{"elapsedMs": float64(42)},
		{"elapsedMs": float64(100)},
	}

	result := extractElapsedMs(events)
	if len(result) != 3 {
		t.Fatalf("expected 3 values, got %d", len(result))
	}
	if result[0] != 42 || result[1] != 100 || result[2] != 200 {
		t.Fatalf("expected [42, 100, 200], got %v", result)
	}
}

func TestBenchmarkPercentile_ComputesCorrectly(t *testing.T) {
	values := []int{10, 20, 30, 40, 50, 60, 70, 80, 90, 100}

	p50 := benchmarkPercentile(values, 50)
	// rank = 0.50 * 9 = 4.5 → avg(values[4], values[5]) = avg(50, 60) = 55
	if p50 != 55 {
		t.Fatalf("expected p50=55, got %d", p50)
	}

	p95 := benchmarkPercentile(values, 95)
	// rank = 0.95 * 9 = 8.55 → avg(values[8], values[9]) = avg(90, 100) = 95
	if p95 != 95 {
		t.Fatalf("expected p95=95, got %d", p95)
	}

	// Single value
	single := benchmarkPercentile([]int{42}, 50)
	if single != 42 {
		t.Fatalf("expected single=42, got %d", single)
	}

	// Empty
	empty := benchmarkPercentile([]int{}, 50)
	if empty != 0 {
		t.Fatalf("expected empty=0, got %d", empty)
	}
}
