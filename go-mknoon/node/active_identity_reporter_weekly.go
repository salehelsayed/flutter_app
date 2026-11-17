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
)

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
func (r *activeIdentityReporter) weekCandidateLocked(f ActiveIdentityReporterFence, week string) (activeIdentityReporterDisk, string, error) {
	if !r.armedLocked(f) {
		return activeIdentityReporterDisk{}, "", errActiveIdentityReporterStale
	}
	if _, err := activitycalendar.ParseWeek(week); err != nil {
		return activeIdentityReporterDisk{}, "", errActiveIdentityReporterInput
	}
	if activitycalendar.Week(r.deps.now()) != week {
		return activeIdentityReporterDisk{}, "", errActiveIdentityReporterStale
	}
	if r.disk.Weekly != nil && r.disk.Weekly.Week > week {
		return activeIdentityReporterDisk{}, "", errActiveIdentityReporterUnavailable
	}
	candidate := r.disk
	candidate.Weekly = activeIdentityReporterWeekCopy(r.disk.Weekly, week)
	return candidate, r.config.StatePath, nil
}

// Caller owns ioMu. Weekly ACKs have their own current-period guard; daily
// transport construction, retries, proofs and response parsing stay unchanged.
func (r *activeIdentityReporter) writeWeek(f ActiveIdentityReporterFence, path string, candidate activeIdentityReporterDisk) error {
	week := candidate.Weekly.Week
	current := func() bool {
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
	mask |= activeIdentityWeeklyActive
	r.ioMu.Lock()
	defer r.ioMu.Unlock()
	r.stateMu.Lock()
	candidate, path, err := r.weekCandidateLocked(f, week)
	if err != nil {
		r.stateMu.Unlock()
		return err
	}
	if candidate.Weekly.Kinds|mask == candidate.Weekly.Kinds {
		r.stateMu.Unlock()
		return nil
	}
	candidate.Weekly.Kinds |= mask
	r.stateMu.Unlock()
	return r.writeWeek(f, path, candidate)
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
	r.ioMu.Lock()
	defer r.ioMu.Unlock()
	r.stateMu.Lock()
	candidate, path, err := r.weekCandidateLocked(f, week)
	if err != nil {
		r.stateMu.Unlock()
		return err
	}
	if mask&^candidate.Weekly.Kinds != 0 {
		r.stateMu.Unlock()
		return errActiveIdentityReporterInput
	}
	index := -1
	for i, ack := range candidate.Weekly.Acknowledged {
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
		if len(candidate.Weekly.Acknowledged) >= activeIdentityReporterWeeklyRelays {
			r.stateMu.Unlock()
			return errActiveIdentityReporterInput
		}
		candidate.Weekly.Acknowledged = append(candidate.Weekly.Acknowledged, activeIdentityReporterWeeklyACK{RelayPeerID: relay, Kinds: mask})
	} else {
		candidate.Weekly.Acknowledged[index].Kinds |= mask
	}
	sort.Slice(candidate.Weekly.Acknowledged, func(i, j int) bool {
		return candidate.Weekly.Acknowledged[i].RelayPeerID < candidate.Weekly.Acknowledged[j].RelayPeerID
	})
	r.stateMu.Unlock()
	return r.writeWeek(f, path, candidate)
}

func activeIdentityReporterRestoreWeek(raw []byte, today string) (*activeIdentityReporterWeeklyDisk, bool) {
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
	if _, err := activitycalendar.ParseWeek(week); err != nil || week > activitycalendar.Week(day) || mask&^activeIdentityWeeklyAll != 0 || !validActiveEngagementKinds(activeIdentityReporterWeeklyKinds(mask)) {
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
