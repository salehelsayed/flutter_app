package node

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/activitycalendar"
	ma "github.com/multiformats/go-multiaddr"
	"time"
)

const (
	activeIdentityReporterVersion       = 1
	activeIdentityReporterSnapshotLimit = 64 << 10
	activeIdentityReporterFlushBudget   = 2 * time.Second
	activeIdentityReporterRetryDelay    = time.Minute
	activeIdentityReporterUnsupported   = time.Hour
)

var (
	errActiveIdentityReporterInput       = errors.New("invalid activity reporter configuration")
	errActiveIdentityReporterStale       = errors.New("activity reporter owner is not current")
	errActiveIdentityReporterStorage     = errors.New("activity reporter storage unavailable")
	errActiveIdentityReporterUnavailable = errors.New("activity reporter unavailable")
)

type ActiveIdentityReporterFence struct {
	Revision       int64  `json:"revision"`
	ConsentEpoch   int64  `json:"consentEpoch"`
	ProfileBinding string `json:"profileBinding"`
	AccountPeerID  string `json:"accountPeerId"`
}

type ActiveIdentityReporterConfig struct {
	Fence                  ActiveIdentityReporterFence `json:"fence"`
	StatePath              string                      `json:"statePath"`
	RootPrivateKeyBase64   string                      `json:"rootPrivateKeyBase64"`
	PreservePendingOnUnarm bool                        `json:"preservePendingOnUnarm,omitempty"`
}

// The supplied transport describes a captured host; this engine does not create
// hosts or authenticate a connection. The eventual Node adapter owns that proof.
type activeIdentityReporterTransport struct {
	peerID         string
	generation     uint64
	relayAddresses []string
	ctx            context.Context
	current        func() bool
	exchange       func(context.Context, RelayInfo, []byte) ([]byte, error)
}

type activeIdentityReporterDeps struct {
	now               func() time.Time
	read              func(string) ([]byte, error)
	write             func(string, []byte) error
	transportSnapshot func() (activeIdentityReporterTransport, bool)
}

type activeIdentityReporterDisk struct {
	Version      int                               `json:"version"`
	ScopeID      string                            `json:"scope_id"`
	ConsentEpoch int64                             `json:"consent_epoch"`
	Day          string                            `json:"day"`
	Marked       bool                              `json:"marked"`
	Acknowledged []string                          `json:"acknowledged"`
	Weekly       *activeIdentityReporterWeeklyDisk `json:"weekly,omitempty"`
	FeatureUse   *activeIdentityReporterWeeklyDisk `json:"feature_use,omitempty"`
}

// stateMu owns the desired fence and the last durable value; ioMu orders
// replacements without blocking synchronous desired publication on filesystem I/O.
type activeIdentityReporter struct {
	deps                               activeIdentityReporterDeps
	stateMu, ioMu                      sync.Mutex
	desired                            ActiveIdentityReporterFence
	preservedOwner                     ActiveIdentityReporterFence
	enabled, preserve, closed, retired bool
	config                             *ActiveIdentityReporterConfig
	disk                               activeIdentityReporterDisk
	cancel                             context.CancelFunc
	ctx                                context.Context
	attempts                           map[string]*activeIdentityReporterAttempt
	weeklyAttempts                     map[weeklyReporterAttemptKey]*weeklyReporterAttempt
	weeklyWake                         chan struct{}
}

type activeIdentityReporterAttempt struct {
	day      string
	fence    ActiveIdentityReporterFence
	next     time.Time
	inFlight bool
}

func newActiveIdentityReporter(deps activeIdentityReporterDeps) *activeIdentityReporter {
	if deps.now == nil {
		deps.now = time.Now
	}
	if deps.read == nil {
		deps.read = activeIdentityReporterRead
	}
	if deps.write == nil {
		deps.write = activeIdentityReporterAtomicWrite
	}
	return &activeIdentityReporter{deps: deps, attempts: make(map[string]*activeIdentityReporterAttempt),
		weeklyAttempts: make(map[weeklyReporterAttemptKey]*weeklyReporterAttempt)}
}

func activeIdentityReporterFenceValid(f ActiveIdentityReporterFence) bool {
	if f.Revision <= 0 || f.Revision > 9007199254740991 || f.ConsentEpoch <= 0 || f.ConsentEpoch > 9007199254740991 {
		return false
	}
	if f.ProfileBinding == "" || f.AccountPeerID == "" {
		return f.ProfileBinding == "" && f.AccountPeerID == ""
	}
	if len(f.AccountPeerID) > activeIdentityProtocolLimit || len(f.ProfileBinding) != 67 || !strings.HasPrefix(f.ProfileBinding, "v1:") {
		return false
	}
	raw, err := hex.DecodeString(f.ProfileBinding[3:])
	if err != nil || hex.EncodeToString(raw) != f.ProfileBinding[3:] {
		return false
	}
	id, err := peer.Decode(f.AccountPeerID)
	return err == nil && id.String() == f.AccountPeerID
}

func activeIdentityReporterScope(f ActiveIdentityReporterFence) string {
	sum := sha256.Sum256([]byte("mknoon/activity-reporter/scope/v1\x00" + f.ProfileBinding + "\x00" + f.AccountPeerID))
	return hex.EncodeToString(sum[:])
}

func (r *activeIdentityReporter) publishDesired(f ActiveIdentityReporterFence, enabled, preserve bool) (ActiveIdentityReporterFence, error) {
	if !activeIdentityReporterFenceValid(f) || (preserve && (!enabled || f.AccountPeerID != "")) {
		return ActiveIdentityReporterFence{}, errActiveIdentityReporterInput
	}
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	if r.closed || f.Revision < r.desired.Revision || f.ConsentEpoch < r.desired.ConsentEpoch {
		return ActiveIdentityReporterFence{}, errActiveIdentityReporterStale
	}
	if f.Revision == r.desired.Revision {
		if f != r.desired || enabled != r.enabled || preserve != r.preserve {
			return ActiveIdentityReporterFence{}, errActiveIdentityReporterInput
		}
		return f, nil
	}
	if r.desired.Revision != 0 && enabled && !r.enabled && f.ConsentEpoch == r.desired.ConsentEpoch {
		return ActiveIdentityReporterFence{}, errActiveIdentityReporterInput
	}
	if preserve && !r.preserve {
		r.preservedOwner = r.desired
	}
	// Retirement is remembered at publication, even when its background configure
	// is overtaken by a later A→empty→A publication. Disposal alone preserves.
	if r.desired.Revision != 0 && (!enabled || (!preserve && (f.ProfileBinding != r.desired.ProfileBinding || f.AccountPeerID != r.desired.AccountPeerID || f.ConsentEpoch != r.desired.ConsentEpoch))) {
		// Returning from a preserving empty owner may recover the inert disk value.
		if !(r.preserve && enabled && f.ConsentEpoch == r.preservedOwner.ConsentEpoch && f.ProfileBinding == r.preservedOwner.ProfileBinding && f.AccountPeerID == r.preservedOwner.AccountPeerID) {
			r.retired = true
		}
	}
	if r.cancel != nil {
		r.cancel()
	}
	r.ctx, r.cancel = context.WithCancel(context.Background())
	r.desired, r.enabled, r.preserve = f, enabled, preserve
	r.config = nil
	r.attempts = make(map[string]*activeIdentityReporterAttempt)
	r.weeklyAttempts = make(map[weeklyReporterAttemptKey]*weeklyReporterAttempt)
	r.weeklyWake = nil
	return f, nil
}

func (r *activeIdentityReporter) desiredLocked(f ActiveIdentityReporterFence) bool {
	return !r.closed && r.desired == f && f.Revision != 0
}
func (r *activeIdentityReporter) armedLocked(f ActiveIdentityReporterFence) bool {
	return r.desiredLocked(f) && r.enabled && !r.preserve && r.config != nil && r.config.Fence == f && f.AccountPeerID != ""
}

func (r *activeIdentityReporter) configure(c ActiveIdentityReporterConfig) error {
	if !activeIdentityReporterFenceValid(c.Fence) || c.StatePath == "" || !filepath.IsAbs(c.StatePath) || filepath.Clean(c.StatePath) != c.StatePath || strings.ContainsRune(c.StatePath, '\x00') || filepath.Base(c.StatePath) == "." || c.StatePath == string(filepath.Separator) {
		return errActiveIdentityReporterInput
	}
	r.stateMu.Lock()
	if !r.desiredLocked(c.Fence) {
		r.stateMu.Unlock()
		return errActiveIdentityReporterStale
	}
	enabled, preserve := r.enabled, r.preserve
	r.stateMu.Unlock()
	if c.PreservePendingOnUnarm != preserve {
		return errActiveIdentityReporterInput
	}
	armed := enabled && c.Fence.AccountPeerID != "" && !preserve
	if armed {
		if _, err := buildActiveIdentityRequest(activitycalendar.Day(r.deps.now()), c.Fence.AccountPeerID, c.Fence.AccountPeerID, c.RootPrivateKeyBase64); err != nil {
			return errActiveIdentityReporterInput
		}
	} else if c.RootPrivateKeyBase64 != "" {
		return errActiveIdentityReporterInput
	}
	r.stateMu.Lock()
	if !r.desiredLocked(c.Fence) {
		r.stateMu.Unlock()
		return errActiveIdentityReporterStale
	}
	if r.config != nil && *r.config == c {
		r.stateMu.Unlock()
		return nil
	}
	r.stateMu.Unlock()
	if preserve {
		r.stateMu.Lock()
		defer r.stateMu.Unlock()
		if !r.desiredLocked(c.Fence) {
			return errActiveIdentityReporterStale
		}
		r.config = &c
		return nil
	}
	// Reads do not occupy the writer lane: a replacement owner must be able to
	// configure while an earlier read is stalled. Recheck after acquiring ioMu.
	raw, err := r.deps.read(c.StatePath)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return errActiveIdentityReporterStorage
	}
	day := activitycalendar.Day(r.deps.now())
	var restored activeIdentityReporterDisk
	if err == nil {
		var ok bool
		restored, ok = activeIdentityReporterRestore(raw, day)
		if !ok {
			return errActiveIdentityReporterStorage
		}
	}
	r.ioMu.Lock()
	defer r.ioMu.Unlock()
	r.stateMu.Lock()
	if !r.desiredLocked(c.Fence) {
		r.stateMu.Unlock()
		return errActiveIdentityReporterStale
	}
	if r.config != nil && *r.config == c {
		r.stateMu.Unlock()
		return nil
	}
	candidate := activeIdentityReporterDisk{Version: 1, ScopeID: activeIdentityReporterScope(c.Fence), ConsentEpoch: c.Fence.ConsentEpoch, Day: day, Acknowledged: []string{}}
	if armed && !r.retired && restored.ScopeID == candidate.ScopeID && restored.ConsentEpoch == candidate.ConsentEpoch {
		if restored.Day == day {
			candidate.Marked, candidate.Acknowledged = restored.Marked, restored.Acknowledged
		}
		if restored.Weekly != nil && restored.Weekly.Week == activitycalendar.Week(r.deps.now()) {
			candidate.Weekly = restored.Weekly
		}
		if restored.FeatureUse != nil && restored.FeatureUse.Week == activitycalendar.Week(r.deps.now()) {
			candidate.FeatureUse = restored.FeatureUse
		}
	}
	r.stateMu.Unlock()
	if err := r.writeCurrent(c.Fence, c.StatePath, candidate, nil); err != nil {
		return err
	}
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	if !r.desiredLocked(c.Fence) {
		return errActiveIdentityReporterStale
	}
	r.config, r.disk, r.retired = &c, candidate, false
	return nil
}

// Caller owns ioMu. Every write carries the exact desired owner; optional host
// validation also fences ACK persistence. No external callback holds stateMu.
func (r *activeIdentityReporter) writeCurrent(f ActiveIdentityReporterFence, path string, disk activeIdentityReporterDisk, current func() bool) error {
	if current != nil && !current() {
		return errActiveIdentityReporterUnavailable
	}
	r.stateMu.Lock()
	valid := r.desiredLocked(f)
	r.stateMu.Unlock()
	if !valid {
		return errActiveIdentityReporterStale
	}
	raw, err := json.Marshal(disk)
	if err != nil || len(raw) > activeIdentityReporterSnapshotLimit {
		return errActiveIdentityReporterStorage
	}
	if err := r.deps.write(path, raw); err != nil {
		return errActiveIdentityReporterStorage
	}
	if current != nil && !current() {
		return errActiveIdentityReporterUnavailable
	}
	r.stateMu.Lock()
	valid = r.desiredLocked(f)
	r.stateMu.Unlock()
	if !valid {
		return errActiveIdentityReporterStale
	}
	return nil
}

func (r *activeIdentityReporter) updateDay(f ActiveIdentityReporterFence, mark bool) error {
	_, err := r.updateActivity(f, mark, nil)
	return err
}

func (r *activeIdentityReporter) updateActivity(f ActiveIdentityReporterFence, mark bool, occurredAt *int64) (bool, error) {
	r.ioMu.Lock()
	defer r.ioMu.Unlock()
	r.stateMu.Lock()
	if !r.armedLocked(f) {
		r.stateMu.Unlock()
		return false, errActiveIdentityReporterStale
	}
	candidate := r.disk
	now := r.deps.now()
	day, week := activitycalendar.Day(now), activitycalendar.Week(now)
	markDay, markWeek := mark, mark
	if occurredAt != nil {
		if *occurredAt > now.UnixMilli() || *occurredAt < now.UnixMilli()-activeIdentityReporterOccurrenceAge.Milliseconds() {
			r.stateMu.Unlock()
			return false, errActiveIdentityReporterInput
		}
		at := time.UnixMilli(*occurredAt)
		markDay = mark && activitycalendar.Day(at) == day
		markWeek = mark && activitycalendar.Week(at) == week
		if !markDay && !markWeek {
			r.stateMu.Unlock()
			return false, nil
		}
	}
	if _, err := activitycalendar.Parse(day); err != nil || day < candidate.Day {
		r.stateMu.Unlock()
		return false, errActiveIdentityReporterUnavailable
	}
	if candidate.Weekly != nil {
		if week < candidate.Weekly.Week {
			r.stateMu.Unlock()
			return false, errActiveIdentityReporterUnavailable
		}
		if week != candidate.Weekly.Week {
			candidate.Weekly = nil
		}
	}
	if candidate.FeatureUse != nil && candidate.FeatureUse.Week < week {
		candidate.FeatureUse = nil
	}
	if day != candidate.Day {
		candidate.Day, candidate.Marked, candidate.Acknowledged = day, false, []string{}
	}
	if markDay {
		candidate.Marked = true
	}
	if markWeek && (candidate.Weekly == nil || candidate.Weekly.Kinds&activeIdentityWeeklyActive == 0) {
		candidate.Weekly = activeIdentityReporterWeekCopy(candidate.Weekly, week)
		candidate.Weekly.Kinds |= activeIdentityWeeklyActive
	}
	if candidate.Day == r.disk.Day && candidate.Marked == r.disk.Marked &&
		candidate.Weekly == r.disk.Weekly && candidate.FeatureUse == r.disk.FeatureUse {
		r.stateMu.Unlock()
		return markDay || markWeek, nil
	}
	path := r.config.StatePath
	r.stateMu.Unlock()
	if err := r.writeCurrent(f, path, candidate, nil); err != nil {
		return false, err
	}
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	if !r.armedLocked(f) {
		return false, errActiveIdentityReporterStale
	}
	if r.disk.Day != candidate.Day {
		r.attempts = make(map[string]*activeIdentityReporterAttempt)
	}
	r.disk = candidate
	return markDay || markWeek, nil
}

func (r *activeIdentityReporter) mark(f ActiveIdentityReporterFence) error {
	return r.updateDay(f, true)
}

func (r *activeIdentityReporter) flush(f ActiveIdentityReporterFence) error {
	if err := r.updateDay(f, false); err != nil {
		return err
	}
	r.stateMu.Lock()
	if !r.armedLocked(f) {
		r.stateMu.Unlock()
		return errActiveIdentityReporterStale
	}
	if !r.disk.Marked {
		r.stateMu.Unlock()
		return nil
	}
	ownerContext := r.ctx
	r.stateMu.Unlock()
	if r.deps.transportSnapshot == nil {
		return errActiveIdentityReporterUnavailable
	}
	transport, ok := r.deps.transportSnapshot()
	if !ok || transport.ctx == nil || transport.current == nil || transport.exchange == nil || !transport.current() {
		return errActiveIdentityReporterUnavailable
	}
	relays, _ := activeIdentityReporterRelays(transport.relayAddresses)
	ctx, cancel := context.WithTimeout(ownerContext, activeIdentityReporterFlushBudget)
	defer cancel()
	stop := context.AfterFunc(transport.ctx, cancel)
	defer stop()
	results := make(chan error, len(relays))
	count := 0
	for _, relay := range relays {
		id := relay.ID.String()
		r.stateMu.Lock()
		if !r.armedLocked(f) {
			r.stateMu.Unlock()
			return errActiveIdentityReporterStale
		}
		day := r.disk.Day
		acked := false
		for _, ack := range r.disk.Acknowledged {
			if ack == id {
				acked = true
				break
			}
		}
		attempt := r.attempts[id]
		if acked || (attempt != nil && (attempt.inFlight || r.deps.now().Before(attempt.next))) {
			r.stateMu.Unlock()
			continue
		}
		attempt = &activeIdentityReporterAttempt{day: day, fence: f, inFlight: true}
		r.attempts[id] = attempt
		root := r.config.RootPrivateKeyBase64
		r.stateMu.Unlock()
		count++
		go func(relay RelayInfo, a *activeIdentityReporterAttempt, root string) {
			results <- r.attempt(ctx, transport, relay, a, root)
		}(relay, attempt, root)
	}
	var result error
	for range count {
		select {
		case err := <-results:
			if err != nil {
				result = err
			}
		case <-ctx.Done():
			return errActiveIdentityReporterUnavailable
		}
	}
	return result
}

func (r *activeIdentityReporter) attempt(ctx context.Context, t activeIdentityReporterTransport, relay RelayInfo, a *activeIdentityReporterAttempt, root string) error {
	id := relay.ID.String()
	result, failure := activeIdentityRetryable, error(nil)
	defer func() {
		r.stateMu.Lock()
		defer r.stateMu.Unlock()
		if r.attempts[id] == a {
			a.inFlight = false
			delay := activeIdentityReporterRetryDelay
			if result == activeIdentityUnsupported {
				delay = activeIdentityReporterUnsupported
			}
			a.next = r.deps.now().Add(delay)
		}
	}()
	current := func() bool {
		if ctx.Err() != nil || !t.current() {
			return false
		}
		r.stateMu.Lock()
		defer r.stateMu.Unlock()
		return r.armedLocked(a.fence) && r.disk.Day == a.day && activitycalendar.Day(r.deps.now()) == a.day
	}
	if !current() {
		return errActiveIdentityReporterUnavailable
	}
	raw, err := buildActiveIdentityRequest(a.day, a.fence.AccountPeerID, t.peerID, root)
	if err != nil {
		return errActiveIdentityReporterInput
	}
	if !current() {
		return errActiveIdentityReporterUnavailable
	}
	response, err := t.exchange(ctx, relay, raw)
	if err != nil || !current() {
		return errActiveIdentityReporterUnavailable
	}
	result, failure = parseActiveIdentityResponse(response)
	if failure != nil || result == activeIdentityRetryable {
		return errActiveIdentityReporterUnavailable
	}
	if result == activeIdentityUnsupported {
		return nil
	}
	r.ioMu.Lock()
	defer r.ioMu.Unlock()
	if !current() {
		return errActiveIdentityReporterUnavailable
	}
	r.stateMu.Lock()
	if !r.armedLocked(a.fence) || r.disk.Day != a.day {
		r.stateMu.Unlock()
		return errActiveIdentityReporterUnavailable
	}
	candidate, path := r.disk, r.config.StatePath
	candidate.Acknowledged = append(append([]string{}, candidate.Acknowledged...), id)
	sort.Strings(candidate.Acknowledged)
	r.stateMu.Unlock()
	if err := r.writeCurrent(a.fence, path, candidate, current); err != nil {
		return err
	}
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	if !r.armedLocked(a.fence) || r.disk.Day != a.day {
		return errActiveIdentityReporterUnavailable
	}
	r.disk = candidate
	return nil
}

func (r *activeIdentityReporter) close() {
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	r.closed = true
	if r.cancel != nil {
		r.cancel()
	}
	r.config = nil
	r.weeklyWake = nil
}

func activeIdentityReporterRestore(raw []byte, today string) (activeIdentityReporterDisk, bool) {
	var disk activeIdentityReporterDisk
	if len(raw) > activeIdentityReporterSnapshotLimit {
		return disk, false
	}
	fields, ok := activeIdentityResponseObject(raw)
	if !ok {
		return disk, false
	}
	const required = 6
	fieldCount := required
	for _, field := range []string{"weekly", "feature_use"} {
		if _, exists := fields[field]; exists {
			fieldCount++
		}
	}
	if len(fields) != fieldCount {
		return disk, false
	}
	for _, key := range []string{"version", "scope_id", "consent_epoch", "day", "marked", "acknowledged"} {
		value, exists := fields[key]
		if !exists || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return disk, false
		}
	}
	if json.Unmarshal(raw, &disk) != nil || !bytes.Equal(bytes.TrimSpace(fields["version"]), []byte("1")) || disk.ConsentEpoch <= 0 || disk.ConsentEpoch > 9007199254740991 {
		return disk, false
	}
	scope, err := hex.DecodeString(disk.ScopeID)
	if err != nil || len(scope) != sha256.Size || hex.EncodeToString(scope) != disk.ScopeID {
		return disk, false
	}
	if _, err := activitycalendar.Parse(disk.Day); err != nil || disk.Day > today {
		return disk, false
	}
	if !bytes.Equal(bytes.TrimSpace(fields["marked"]), []byte("true")) && !bytes.Equal(bytes.TrimSpace(fields["marked"]), []byte("false")) {
		return disk, false
	}
	seen := make(map[string]bool)
	for _, ack := range disk.Acknowledged {
		id, err := peer.Decode(ack)
		if err != nil || id.String() != ack || seen[ack] || !disk.Marked {
			return disk, false
		}
		seen[ack] = true
	}
	sort.Strings(disk.Acknowledged)
	if rawWeek, exists := fields["weekly"]; exists {
		weekly, ok := activeIdentityReporterRestoreWeek(rawWeek, today, engagementWeeklyReport)
		if !ok {
			return activeIdentityReporterDisk{}, false
		}
		disk.Weekly = weekly
	}
	if rawWeek, exists := fields["feature_use"]; exists {
		weekly, ok := activeIdentityReporterRestoreWeek(rawWeek, today, featureUseWeeklyReport)
		if !ok {
			return activeIdentityReporterDisk{}, false
		}
		disk.FeatureUse = weekly
	}
	return disk, true
}

func activeIdentityReporterParent(path string) error {
	parent := filepath.Dir(path)
	if err := os.MkdirAll(parent, 0700); err != nil {
		return errActiveIdentityReporterStorage
	}
	info, err := os.Lstat(parent)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return errActiveIdentityReporterStorage
	}
	if os.Chmod(parent, 0700) != nil {
		return errActiveIdentityReporterStorage
	}
	return nil
}

func activeIdentityReporterRead(path string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > activeIdentityReporterSnapshotLimit {
		return nil, errActiveIdentityReporterStorage
	}
	if activeIdentityReporterParent(path) != nil || os.Chmod(path, 0600) != nil {
		return nil, errActiveIdentityReporterStorage
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, errActiveIdentityReporterStorage
	}
	defer file.Close()
	raw, err := io.ReadAll(io.LimitReader(file, activeIdentityReporterSnapshotLimit+1))
	if err != nil || len(raw) > activeIdentityReporterSnapshotLimit {
		return nil, errActiveIdentityReporterStorage
	}
	return raw, nil
}

func activeIdentityReporterAtomicWrite(path string, raw []byte) error {
	if len(raw) > activeIdentityReporterSnapshotLimit || activeIdentityReporterParent(path) != nil {
		return errActiveIdentityReporterStorage
	}
	if info, err := os.Lstat(path); err == nil && !info.Mode().IsRegular() {
		return errActiveIdentityReporterStorage
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return errActiveIdentityReporterStorage
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".activity-*")
	if err != nil {
		return errActiveIdentityReporterStorage
	}
	defer os.Remove(file.Name())
	if err = file.Chmod(0600); err == nil {
		_, err = file.Write(raw)
	}
	if err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil || closeErr != nil {
		return errActiveIdentityReporterStorage
	}
	if os.Rename(file.Name(), path) != nil {
		return errActiveIdentityReporterStorage
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return errActiveIdentityReporterStorage
	}
	defer dir.Close()
	if dir.Sync() != nil {
		return errActiveIdentityReporterStorage
	}
	return nil
}

// Nil means the shipped defaults; explicit empty never falls back. Parsing is
// deliberately separate from RelaySelector, whose diagnostics echo raw input.
func activeIdentityReporterRelays(raw []string) ([]RelayInfo, error) {
	if raw == nil {
		raw = DefaultRelayAddresses()
	}
	relays := []RelayInfo{}
	indexes := make(map[peer.ID]int)
	for _, address := range raw {
		parsed, err := ma.NewMultiaddr(address)
		if err != nil {
			continue
		}
		info, err := peer.AddrInfoFromP2pAddr(parsed)
		if err != nil {
			continue
		}
		if i, ok := indexes[info.ID]; ok {
			relays[i].Addrs = append(relays[i].Addrs, info.Addrs...)
			continue
		}
		indexes[info.ID] = len(relays)
		relays = append(relays, RelayInfo{ID: info.ID, Addrs: info.Addrs})
	}
	return relays, nil
}
