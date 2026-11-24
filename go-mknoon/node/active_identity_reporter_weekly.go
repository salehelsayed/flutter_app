package node

import (
	"bytes"
	"encoding/json"
	"sort"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

const (
	activeIdentityReporterOccurrenceAge       = 2 * time.Minute
	activeIdentityReporterWeeklyRelays        = 64
	activeIdentityWeeklyActive          uint8 = 1
	activeIdentityWeeklyAll             uint8 = 15
	featureUseWeeklyAll                 uint8 = 63
)

type weeklyReportKind uint8

const (
	engagementWeeklyReport weeklyReportKind = iota
	featureUseWeeklyReport
)

var featureUseKinds = [...]string{"voice_message", "photo_video", "video_call", "translation", "voice_to_text", "view_3d"}

type activeIdentityReporterWeeklyACK struct {
	RelayPeerID string `json:"relay_peer_id"`
	Kinds       uint8  `json:"kinds"`
}

type activeIdentityReporterWeeklyDisk struct {
	Week         string                            `json:"week"`
	Kinds        uint8                             `json:"kinds"`
	Acknowledged []activeIdentityReporterWeeklyACK `json:"acknowledged"`
}

type ActiveIdentityReporterWeeklyACK struct {
	RelayPeerID string   `json:"relayPeerId"`
	Kinds       []string `json:"kinds"`
}

type ActiveIdentityReporterWeeklyProjection struct {
	Week            string                            `json:"week"`
	StartUnixMillis int64                             `json:"startUnixMillis"`
	EndUnixMillis   int64                             `json:"endUnixMillis"`
	Kinds           []string                          `json:"kinds"`
	Acknowledged    []ActiveIdentityReporterWeeklyACK `json:"acknowledged"`
}

func activeIdentityReporterWeeklyMask(kinds []string) (uint8, bool) {
	if len(kinds) < 1 || len(kinds) > 4 {
		return 0, false
	}
	var mask uint8
	for _, kind := range kinds {
		var bit uint8
		switch kind {
		case "active":
			bit = 1
		case "chat":
			bit = 2
		case "call":
			bit = 4
		case "group":
			bit = 8
		default:
			return 0, false
		}
		if mask&bit != 0 {
			return 0, false
		}
		mask |= bit
	}
	return mask, true
}

func activeIdentityReporterWeeklyKinds(mask uint8) []string {
	kinds := make([]string, 0, 4)
	for i, kind := range []string{"active", "chat", "call", "group"} {
		if mask&(1<<i) != 0 {
			kinds = append(kinds, kind)
		}
	}
	return kinds
}

func featureUseMask(kinds []string) (uint8, bool) {
	var mask uint8
	for _, kind := range kinds {
		var bit uint8
		for index, allowed := range featureUseKinds {
			if kind == allowed {
				bit = 1 << index
				break
			}
		}
		if bit == 0 || mask&bit != 0 {
			return 0, false
		}
		mask |= bit
	}
	return mask, mask != 0
}

func featureUseWireKinds(mask uint8) []string {
	kinds := make([]string, 0, len(featureUseKinds))
	for index, kind := range featureUseKinds {
		if mask&(1<<index) != 0 {
			kinds = append(kinds, kind)
		}
	}
	return kinds
}

func (kind weeklyReportKind) validMask(mask uint8) bool {
	if kind == featureUseWeeklyReport {
		return mask != 0 && mask&^featureUseWeeklyAll == 0
	}
	return mask&activeIdentityWeeklyActive != 0 && mask&^activeIdentityWeeklyAll == 0
}

func (d activeIdentityReporterDisk) weeklyReport(kind weeklyReportKind) *activeIdentityReporterWeeklyDisk {
	if kind == featureUseWeeklyReport {
		return d.FeatureUse
	}
	return d.Weekly
}

func activeIdentityReporterWeekCopy(value *activeIdentityReporterWeeklyDisk, week string) *activeIdentityReporterWeeklyDisk {
	copy := &activeIdentityReporterWeeklyDisk{Week: week, Acknowledged: []activeIdentityReporterWeeklyACK{}}
	if value != nil && value.Week == week {
		copy.Kinds = value.Kinds
		copy.Acknowledged = append(copy.Acknowledged, value.Acknowledged...)
	}
	return copy
}

func (r *activeIdentityReporter) weeklyProjection(f ActiveIdentityReporterFence) (*ActiveIdentityReporterWeeklyProjection, error) {
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	if !r.armedLocked(f) {
		return nil, errActiveIdentityReporterStale
	}
	week := activitycalendar.Week(r.deps.now())
	start, err := activitycalendar.ParseWeek(week)
	if err != nil || (r.disk.Weekly != nil && r.disk.Weekly.Week > week) {
		return nil, errActiveIdentityReporterUnavailable
	}
	result := &ActiveIdentityReporterWeeklyProjection{Week: week, StartUnixMillis: start.UnixMilli(), EndUnixMillis: start.AddDate(0, 0, 7).UnixMilli(), Kinds: []string{}, Acknowledged: []ActiveIdentityReporterWeeklyACK{}}
	if r.disk.Weekly != nil && r.disk.Weekly.Week == week {
		result.Kinds = activeIdentityReporterWeeklyKinds(r.disk.Weekly.Kinds)
		for _, ack := range r.disk.Weekly.Acknowledged {
			result.Acknowledged = append(result.Acknowledged, ActiveIdentityReporterWeeklyACK{RelayPeerID: ack.RelayPeerID, Kinds: activeIdentityReporterWeeklyKinds(ack.Kinds)})
		}
	}
	return result, nil
}

// Caller owns stateMu and ioMu. The copy keeps failed writes and late ACKs from
// mutating the last durable state, including its independent daily ACK slice.
func (r *activeIdentityReporter) weekCandidateLocked(f ActiveIdentityReporterFence, week string, kind weeklyReportKind) (activeIdentityReporterDisk, string, error) {
	if !r.armedLocked(f) {
		return activeIdentityReporterDisk{}, "", errActiveIdentityReporterStale
	}
	if _, err := activitycalendar.ParseWeek(week); err != nil {
		return activeIdentityReporterDisk{}, "", errActiveIdentityReporterInput
	}
	if activitycalendar.Week(r.deps.now()) != week {
		return activeIdentityReporterDisk{}, "", errActiveIdentityReporterStale
	}
	candidate := r.disk
	report := candidate.weeklyReport(kind)
	if report != nil && report.Week > week {
		return activeIdentityReporterDisk{}, "", errActiveIdentityReporterUnavailable
	}
	copy := activeIdentityReporterWeekCopy(report, week)
	if kind == featureUseWeeklyReport {
		candidate.FeatureUse = copy
	} else {
		candidate.Weekly = copy
	}
	return candidate, r.config.StatePath, nil
}

// Caller owns ioMu. Weekly ACKs have their own current-period guard; daily
// transport construction, retries, proofs and response parsing stay unchanged.
func (r *activeIdentityReporter) writeWeek(f ActiveIdentityReporterFence, path string, candidate activeIdentityReporterDisk, week string, transportCurrent func() bool) error {
	current := func() bool {
		if transportCurrent != nil && !transportCurrent() {
			return false
		}
		r.stateMu.Lock()
		defer r.stateMu.Unlock()
		return r.armedLocked(f) && activitycalendar.Week(r.deps.now()) == week
	}
	if err := r.writeCurrent(f, path, candidate, current); err != nil {
		return err
	}
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	if !r.armedLocked(f) || activitycalendar.Week(r.deps.now()) != week {
		return errActiveIdentityReporterUnavailable
	}
	r.disk = candidate
	return nil
}

func (r *activeIdentityReporter) markWeekly(f ActiveIdentityReporterFence, week string, kinds []string) error {
	mask, ok := activeIdentityReporterWeeklyMask(kinds)
	if !ok {
		return errActiveIdentityReporterInput
	}
	return r.markWeeklyReport(f, week, engagementWeeklyReport, mask|activeIdentityWeeklyActive)
}

func (r *activeIdentityReporter) markFeatureUse(f ActiveIdentityReporterFence, atMillis int64, kinds []string) error {
	mask, ok := featureUseMask(kinds)
	if !ok {
		return errActiveIdentityReporterInput
	}
	now := r.deps.now().UnixMilli()
	if atMillis > now || atMillis < now-activeIdentityReporterOccurrenceAge.Milliseconds() {
		return errActiveIdentityReporterStale
	}
	return r.markWeeklyReport(f, activitycalendar.Week(time.UnixMilli(atMillis)), featureUseWeeklyReport, mask)
}

func (r *activeIdentityReporter) markWeeklyReport(f ActiveIdentityReporterFence, week string, kind weeklyReportKind, mask uint8) error {
	r.ioMu.Lock()
	defer r.ioMu.Unlock()
	r.stateMu.Lock()
	candidate, path, err := r.weekCandidateLocked(f, week, kind)
	if err != nil {
		r.stateMu.Unlock()
		return err
	}
	report := candidate.weeklyReport(kind)
	if report.Kinds|mask == report.Kinds {
		r.stateMu.Unlock()
		return nil
	}
	report.Kinds |= mask
	r.stateMu.Unlock()
	return r.writeWeek(f, path, candidate, week, nil)
}

func (r *activeIdentityReporter) ackWeekly(f ActiveIdentityReporterFence, week, relay string, kinds []string) error {
	mask, ok := activeIdentityReporterWeeklyMask(kinds)
	if !ok || len(relay) > activeIdentityProtocolLimit {
		return errActiveIdentityReporterInput
	}
	id, err := peer.Decode(relay)
	if err != nil || id.String() != relay {
		return errActiveIdentityReporterInput
	}
	return r.ackWeeklyReport(f, week, engagementWeeklyReport, relay, mask, nil)
}

func (r *activeIdentityReporter) ackWeeklyReport(f ActiveIdentityReporterFence, week string, kind weeklyReportKind, relay string, mask uint8, transportCurrent func() bool) error {
	r.ioMu.Lock()
	defer r.ioMu.Unlock()
	r.stateMu.Lock()
	candidate, path, err := r.weekCandidateLocked(f, week, kind)
	if err != nil {
		r.stateMu.Unlock()
		return err
	}
	report := candidate.weeklyReport(kind)
	if mask&^report.Kinds != 0 {
		r.stateMu.Unlock()
		return errActiveIdentityReporterInput
	}
	index := -1
	for i, ack := range report.Acknowledged {
		if ack.RelayPeerID == relay {
			if ack.Kinds|mask == ack.Kinds {
				r.stateMu.Unlock()
				return nil
			}
			index = i
			break
		}
	}
	if index < 0 {
		if len(report.Acknowledged) >= activeIdentityReporterWeeklyRelays {
			r.stateMu.Unlock()
			return errActiveIdentityReporterInput
		}
		report.Acknowledged = append(report.Acknowledged, activeIdentityReporterWeeklyACK{RelayPeerID: relay, Kinds: mask})
	} else {
		report.Acknowledged[index].Kinds |= mask
	}
	sort.Slice(report.Acknowledged, func(i, j int) bool {
		return report.Acknowledged[i].RelayPeerID < report.Acknowledged[j].RelayPeerID
	})
	r.stateMu.Unlock()
	return r.writeWeek(f, path, candidate, week, transportCurrent)
}

func activeIdentityReporterRestoreWeek(raw []byte, today string, kind weeklyReportKind) (*activeIdentityReporterWeeklyDisk, bool) {
	fields, ok := activeIdentityResponseObject(raw)
	if !ok || len(fields) != 3 {
		return nil, false
	}
	for _, key := range []string{"week", "kinds", "acknowledged"} {
		if value, exists := fields[key]; !exists || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return nil, false
		}
	}
	var week string
	var mask uint8
	day, err := activitycalendar.Parse(today)
	if err != nil || json.Unmarshal(fields["week"], &week) != nil || json.Unmarshal(fields["kinds"], &mask) != nil {
		return nil, false
	}
	if _, err := activitycalendar.ParseWeek(week); err != nil || week > activitycalendar.Week(day) || !kind.validMask(mask) {
		return nil, false
	}
	var acknowledgements []json.RawMessage
	if json.Unmarshal(fields["acknowledged"], &acknowledgements) != nil || len(acknowledgements) > activeIdentityReporterWeeklyRelays {
		return nil, false
	}
	value := &activeIdentityReporterWeeklyDisk{Week: week, Kinds: mask, Acknowledged: []activeIdentityReporterWeeklyACK{}}
	seen := map[string]bool{}
	for _, rawACK := range acknowledgements {
		ackFields, ok := activeIdentityResponseObject(rawACK)
		if !ok || len(ackFields) != 2 {
			return nil, false
		}
		var ack activeIdentityReporterWeeklyACK
		if json.Unmarshal(ackFields["relay_peer_id"], &ack.RelayPeerID) != nil || json.Unmarshal(ackFields["kinds"], &ack.Kinds) != nil || bytes.Equal(bytes.TrimSpace(ackFields["kinds"]), []byte("null")) {
			return nil, false
		}
		id, err := peer.Decode(ack.RelayPeerID)
		if err != nil || id.String() != ack.RelayPeerID || seen[ack.RelayPeerID] || ack.Kinds == 0 || ack.Kinds&^mask != 0 {
			return nil, false
		}
		seen[ack.RelayPeerID] = true
		value.Acknowledged = append(value.Acknowledged, ack)
	}
	sort.Slice(value.Acknowledged, func(i, j int) bool { return value.Acknowledged[i].RelayPeerID < value.Acknowledged[j].RelayPeerID })
	return value, true
}
