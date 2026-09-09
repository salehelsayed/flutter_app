package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/google/uuid"
)

const callDiagnosticRetention = 14 * 24 * time.Hour
const callDiagnosticGlobalBytes = 64 << 20
const callDiagnosticOwnerBytes = 5 << 20

// A joined trace includes two independently bounded endpoint spools plus relay stages.
const callDiagnosticTraceEvents = 3 * 256
const callDiagnosticTraceBytes = 3 * (64 << 10)
const callDiagnosticRecordBytes = 320 << 10
const callDiagnosticDiscardIDLimit = 256

type callDiagnosticConsent struct {
	// Effective capability is process-local: persisted consent alone never proves the installed push parser.
	PushCapability bool  `json:"-"`
	ConsentEpoch   int64 `json:"consentEpoch"`
	Enabled        bool  `json:"enabled"`
	PushTrace      bool  `json:"pushTrace"`
	UpdatedAtMs    int64 `json:"updatedAtMs"`
}
type callDiagnosticAuthorityChange struct {
	AuthorDigest string `json:"authorDigest"`
	OperationID  string `json:"operationId"`
	AtMs         int64  `json:"atMs"`
	Reason       string `json:"reason"`
}
type callDiagnosticPrivateState struct {
	Consent   map[string]callDiagnosticConsent         `json:"consent"`
	Authority map[string]callDiagnosticAuthorityChange `json:"authority"`
}
type callDiagnosticStoredEvent struct {
	ReceivedAtMs int64           `json:"receivedAtMs"`
	Event        json.RawMessage `json:"event"`
}

// Owner, participants and binding digests are private authorization metadata.
// Operator output includes ONLY Events/Summaries and fixed completeness fields.
type callDiagnosticRecord struct {
	Owner                  string                               `json:"owner"`
	Participants           []string                             `json:"participants,omitempty"`
	HandleDigest           string                               `json:"handleDigest,omitempty"`
	Bindings               []string                             `json:"bindings,omitempty"`
	CreatedAtMs            int64                                `json:"createdAtMs"`
	UpdatedAtMs            int64                                `json:"updatedAtMs"`
	Events                 []callDiagnosticStoredEvent          `json:"events"`
	Summaries              map[string]callDiagnosticStoredEvent `json:"summaries,omitempty"`
	Dropped                uint64                               `json:"dropped"`
	DropAccountingVersion  int                                  `json:"dropAccountingVersion,omitempty"`
	DiscardedEventIDs      []string                             `json:"discardedEventIds,omitempty"`
	DiscardLedgerSaturated bool                                 `json:"discardLedgerSaturated,omitempty"`
	LegacyDropAttempts     uint64                               `json:"legacyDropAttempts,omitempty"`
	DroppedFirstAtMs       int64                                `json:"droppedFirstAtMs,omitempty"`
	DroppedUpdatedAtMs     int64                                `json:"droppedUpdatedAtMs,omitempty"`
	RuntimeGroup           string                               `json:"runtimeGroup,omitempty"`
	RuntimePartition       int                                  `json:"runtimePartition,omitempty"`
}
type callDiagnosticMetadata struct {
	owner        string
	participants []string
	handleDigest string
	bindings     []string
}
type callDiagnosticStore struct {
	pushGenerations        map[string]uint64
	beforeConfigurePublish func()
	metaMu                 sync.Mutex
	metadata               map[string]*callDiagnosticMetadata
	consentMetadata        map[string]callDiagnosticConsent
	authorityMetadata      map[string]callDiagnosticAuthorityChange

	mu       sync.Mutex
	dir      string
	now      func() time.Time
	quota    int
	state    callDiagnosticPrivateState
	records  map[string]*callDiagnosticRecord
	bindings map[string]string
	queue    chan func()
	done     chan struct{}
	dropped  atomic.Uint64
	runID    string
	sequence atomic.Uint64
	// Rebuilt from retained records; neither index is diagnostic output.
	runtimeHeads        map[string]string
	runtimeEventRecords map[string]string
}

func diagnosticPrivateKey(parts ...string) string {
	h := sha256.New()
	for _, p := range parts {
		_, _ = h.Write([]byte(p))
		_, _ = h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil))
}
func newCallDiagnosticStore(dir string, quota int, now func() time.Time) (*callDiagnosticStore, error) {
	if dir == "" {
		return nil, errors.New("diagnostic storage disabled")
	}
	if now == nil {
		now = time.Now
	}
	if quota <= 0 {
		quota = callDiagnosticGlobalBytes
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	if err := os.Chmod(dir, 0700); err != nil {
		return nil, err
	}
	s := &callDiagnosticStore{dir: dir, quota: quota, now: now, records: map[string]*callDiagnosticRecord{}, bindings: map[string]string{}, queue: make(chan func(), 512), done: make(chan struct{}), runID: uuid.NewString(), state: callDiagnosticPrivateState{Consent: map[string]callDiagnosticConsent{}, Authority: map[string]callDiagnosticAuthorityChange{}}}
	raw, err := os.ReadFile(filepath.Join(dir, "private.json"))
	if err == nil {
		if json.Unmarshal(raw, &s.state) != nil {
			return nil, errors.New("invalid diagnostic storage")
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	if s.state.Consent == nil {
		s.state.Consent = map[string]callDiagnosticConsent{}
	}
	if s.state.Authority == nil {
		s.state.Authority = map[string]callDiagnosticAuthorityChange{}
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	total := 0
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || len(name) < 6 || filepath.Ext(name) != ".json" || name == "private.json" {
			continue
		}
		key := name[:len(name)-5]
		if !diagnosticUUID.MatchString(key) && !isCallDiagnosticRuntimeKey(key) {
			continue
		}
		info, e := entry.Info()
		if e != nil || info.Size() > callDiagnosticRecordBytes {
			continue
		}
		total += int(info.Size())
		if total > quota+callDiagnosticRecordBytes {
			return nil, errors.New("diagnostic quota exceeded")
		}
		raw, e := os.ReadFile(filepath.Join(dir, name))
		if e != nil {
			return nil, e
		}
		var rec callDiagnosticRecord
		if json.Unmarshal(raw, &rec) != nil {
			return nil, errors.New("invalid diagnostic record")
		}
		if rec.Summaries == nil {
			rec.Summaries = map[string]callDiagnosticStoredEvent{}
		}
		if now().UnixMilli()-rec.CreatedAtMs > callDiagnosticRetention.Milliseconds() {
			_ = os.Remove(filepath.Join(dir, name))
			continue
		}
		s.records[key] = &rec
		if rec.DropAccountingVersion == 0 {
			// Old Dropped counted quota refusals, including repeated uploads of
			// the same event. Preserve that evidence without inventing unique loss.
			rec.LegacyDropAttempts += rec.Dropped
			rec.Dropped = 0
			rec.DropAccountingVersion = 1
			if err := s.persistLocked(key); err != nil {
				return nil, err
			}
		}
		for _, b := range rec.Bindings {
			s.bindings[b] = key
		}
	}
	s.pushGenerations = map[string]uint64{}
	s.metadata = map[string]*callDiagnosticMetadata{}
	s.consentMetadata = map[string]callDiagnosticConsent{}
	s.authorityMetadata = map[string]callDiagnosticAuthorityChange{}
	for key, c := range s.state.Consent {
		s.consentMetadata[key] = c
	}
	for key, c := range s.state.Authority {
		if len(c.AuthorDigest) != 64 {
			delete(s.state.Authority, key)
			continue
		}
		s.authorityMetadata[key] = c
	}
	for key, r := range s.records {
		s.metadata[key] = &callDiagnosticMetadata{owner: r.Owner, participants: append([]string(nil), r.Participants...), bindings: append([]string(nil), r.Bindings...), handleDigest: r.HandleDigest}
	}
	s.expireLocked()
	if err := s.writePrivateLocked(); err != nil {
		return nil, err
	}
	go s.work()
	return s, nil
}
func (s *callDiagnosticStore) work() {
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	defer close(s.done)
	for {
		select {
		case job, ok := <-s.queue:
			if !ok {
				return
			}
			job()
		case <-ticker.C:
			s.mu.Lock()
			s.expireLocked()
			_ = s.writePrivateLocked()
			s.mu.Unlock()
		}
	}
}
func (s *callDiagnosticStore) close() { close(s.queue); <-s.done }
func (s *callDiagnosticStore) enqueue(job func()) {
	if s == nil {
		return
	}
	select {
	case s.queue <- job:
	default:
		s.drop("queue_full")
	}
}
func (s *callDiagnosticStore) flush() {
	done := make(chan struct{})
	s.queue <- func() { close(done) }
	<-done
}
func diagnosticAtomicJSON(path string, value any) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(path+".tmp", os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	if _, err = f.Write(raw); err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		_ = os.Remove(path + ".tmp")
		return err
	}
	if err = os.Rename(path+".tmp", path); err != nil {
		return err
	}
	d, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer d.Close()
	return d.Sync()
}
func (s *callDiagnosticStore) writePrivateLocked() error {
	return diagnosticAtomicJSON(filepath.Join(s.dir, "private.json"), s.state)
}
func (s *callDiagnosticStore) persistLocked(key string) error {
	return diagnosticAtomicJSON(filepath.Join(s.dir, key+".json"), s.records[key])
}
func (s *callDiagnosticStore) enabled(actor string) bool {
	if s == nil {
		return false
	}
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	return s.consentMetadata[diagnosticPrivateKey(actor)].Enabled
}

func (s *callDiagnosticStore) configure(actor string, enabled, push bool, epoch int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := diagnosticPrivateKey(actor)
	if _, ok := s.state.Consent[key]; !ok && len(s.state.Consent) >= 10000 {
		return errors.New("diagnostic quota exceeded")
	}
	old := s.state.Consent[key]
	if epoch <= 0 || epoch < old.ConsentEpoch || (epoch == old.ConsentEpoch && (old.Enabled != enabled || old.PushTrace != (enabled && push))) {
		return errors.New("stale diagnostic consent")
	}
	s.metaMu.Lock()
	generation := s.pushGenerations[key] + 1
	s.pushGenerations[key] = generation
	s.metaMu.Unlock()
	s.state.Consent[key] = callDiagnosticConsent{ConsentEpoch: epoch, Enabled: enabled, PushTrace: enabled && push, UpdatedAtMs: s.now().UnixMilli()}
	if err := s.writePrivateLocked(); err != nil {
		s.state.Consent[key] = old
		return err
	}
	if s.beforeConfigurePublish != nil {
		s.beforeConfigurePublish()
	}
	s.metaMu.Lock()
	candidate := s.state.Consent[key]
	candidate.PushCapability = enabled && push && s.pushGenerations[key] == generation
	s.state.Consent[key] = candidate
	s.consentMetadata[key] = candidate
	s.metaMu.Unlock()
	if !enabled {
		return s.purgeActorLocked(actor)
	}
	return nil
}
func (s *callDiagnosticStore) authorizedLocked(actor, key string) bool {
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	return s.authorizedMetadataLocked(actor, key)
}
func (s *callDiagnosticStore) authorizedMetadataLocked(actor, key string) bool {
	meta := s.metadata[key]
	if meta == nil {
		return false
	}
	a := diagnosticPrivateKey(actor)
	return meta.owner == a || diagnosticContains(meta.participants, a)
}

func (s *callDiagnosticStore) ensureLocked(actor, key string) bool {
	if s.records[key] != nil {
		return s.authorizedLocked(actor, key)
	}
	if len(s.records) >= 10000 {
		return false
	}
	total, owner := 0, 0
	a := diagnosticPrivateKey(actor)
	for _, r := range s.records {
		raw, _ := json.Marshal(r)
		total += len(raw)
		if r.Owner == a {
			owner += len(raw)
		}
	}
	if total >= s.quota || owner >= callDiagnosticOwnerBytes {
		return false
	}
	now := s.now().UnixMilli()
	s.metaMu.Lock()
	meta := s.metadata[key]
	if meta == nil {
		meta = &callDiagnosticMetadata{owner: a}
		s.metadata[key] = meta
	}
	if !s.authorizedMetadataLocked(actor, key) {
		s.metaMu.Unlock()
		return false
	}
	s.records[key] = &callDiagnosticRecord{Owner: meta.owner, Participants: append([]string(nil), meta.participants...), Bindings: append([]string(nil), meta.bindings...), HandleDigest: meta.handleDigest, CreatedAtMs: now, UpdatedAtMs: now, Events: []callDiagnosticStoredEvent{}, Summaries: map[string]callDiagnosticStoredEvent{}, DropAccountingVersion: 1}
	s.metaMu.Unlock()
	return true
}
func (s *callDiagnosticStore) prepare(actor string, d *callDiagnosticContext, epochs ...int64) bool {
	if s == nil || !d.valid() {
		return false
	}
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	a := diagnosticPrivateKey(actor)
	c := s.consentMetadata[a]
	if !c.Enabled || (len(epochs) > 0 && (epochs[0] <= 0 || epochs[0] != c.ConsentEpoch)) {
		return false
	}
	d.consentEpoch = c.ConsentEpoch
	if d.TraceID == "" {
		return true
	}
	if s.metadata[d.TraceID] == nil {
		if len(s.metadata) >= 10000 {
			return false
		}
		s.metadata[d.TraceID] = &callDiagnosticMetadata{owner: a}
	}
	return s.authorizedMetadataLocked(actor, d.TraceID)
}

func (s *callDiagnosticStore) bindCommitted(actor, recipient, handle string, d *callDiagnosticContext) {
	if s == nil || d == nil || d.TraceID == "" {
		return
	}
	s.metaMu.Lock()
	if !s.authorizedMetadataLocked(actor, d.TraceID) || s.consentMetadata[diagnosticPrivateKey(actor)].ConsentEpoch != d.consentEpoch {
		s.metaMu.Unlock()
		return
	}
	meta := s.metadata[d.TraceID]
	handleDigest := diagnosticPrivateKey(handle)
	if meta.handleDigest != "" && meta.handleDigest != handleDigest {
		s.metaMu.Unlock()
		return
	}
	a := diagnosticPrivateKey(recipient)
	if meta.handleDigest != "" && a != meta.owner && !diagnosticContains(meta.participants, a) {
		s.metaMu.Unlock()
		return
	}
	meta.handleDigest = handleDigest
	if a != meta.owner && !diagnosticContains(meta.participants, a) && len(meta.participants) < 1 {
		meta.participants = append(meta.participants, a)
	}
	for _, p := range []string{actor, recipient} {
		b := diagnosticPrivateKey(p, handle)
		if existing := s.bindings[b]; existing != "" && existing != d.TraceID {
			continue
		}
		if !diagnosticContains(meta.bindings, b) && len(meta.bindings) < 2 {
			meta.bindings = append(meta.bindings, b)
			s.bindings[b] = d.TraceID
		}
	}
	s.metaMu.Unlock()
	s.enqueue(func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		c := s.state.Consent[diagnosticPrivateKey(actor)]
		if !c.Enabled || c.ConsentEpoch != d.consentEpoch {
			return
		}
		if !s.ensureLocked(actor, d.TraceID) {
			return
		}
		s.metaMu.Lock()
		meta := s.metadata[d.TraceID]
		if meta == nil {
			s.metaMu.Unlock()
			return
		}
		r := s.records[d.TraceID]
		r.Participants = append([]string(nil), meta.participants...)
		r.Bindings = append([]string(nil), meta.bindings...)
		r.HandleDigest = meta.handleDigest
		s.metaMu.Unlock()
		if s.persistLocked(d.TraceID) != nil {
			s.drop("sink_unavailable")
		}
	})
}

func (s *callDiagnosticStore) resolve(actor, handle string) string {
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	if !s.consentMetadata[diagnosticPrivateKey(actor)].Enabled {
		return ""
	}
	key := s.bindings[diagnosticPrivateKey(actor, handle)]
	if !s.authorizedMetadataLocked(actor, key) {
		return ""
	}
	return key
}

func (s *callDiagnosticStore) pushTrace(actor, handle string) *callDiagnosticPush {
	if s == nil {
		return nil
	}
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	c := s.consentMetadata[diagnosticPrivateKey(actor)]
	if !c.Enabled || !c.PushTrace || !c.PushCapability {
		return nil
	}
	key := s.bindings[diagnosticPrivateKey(actor, handle)]
	if !diagnosticUUID.MatchString(key) || !s.authorizedMetadataLocked(actor, key) {
		return nil
	}
	return &callDiagnosticPush{SchemaVersion: 1, TraceID: key}
}

type callDiagnosticPush struct {
	SchemaVersion int    `json:"schemaVersion"`
	TraceID       string `json:"traceId"`
}

type callDiagnosticAppendResult int

const (
	callDiagnosticAppendRetry callDiagnosticAppendResult = iota
	callDiagnosticAppendAccepted
	callDiagnosticAppendDiscarded
)

func (s *callDiagnosticStore) appendEvent(actor string, raw json.RawMessage, server bool, epochs ...int64) bool {
	return s.appendEventResult(actor, raw, server, epochs...) == callDiagnosticAppendAccepted
}

func isCallDiagnosticRuntimeKey(key string) bool {
	if !strings.HasPrefix(key, "runtime-") {
		return false
	}
	suffix := strings.TrimPrefix(key, "runtime-")
	if len(suffix) == 64 {
		_, err := hex.DecodeString(suffix)
		return err == nil
	}
	// Older runtime records used UUIDv5; event UUID validation stays UUIDv4.
	id, err := uuid.Parse(suffix)
	return err == nil && id.String() == suffix && (id.Version() == 4 || id.Version() == 5)
}

func callDiagnosticRuntimeGroup(owner, runID string) string {
	return diagnosticPrivateKey("runtime-partitions-v1", owner, runID)
}

func callDiagnosticRuntimePartitionKey(group string, partition int) string {
	return "runtime-" + diagnosticPrivateKey(group, strconv.Itoa(partition))
}

// All entries are backed by already bounded retained records. Legacy records
// participate in retry deduplication but are never selected for fresh writes.
func (s *callDiagnosticStore) rebuildRuntimeIndexesLocked() {
	s.runtimeHeads = map[string]string{}
	s.runtimeEventRecords = map[string]string{}
	for key, rec := range s.records {
		if !isCallDiagnosticRuntimeKey(key) {
			continue
		}
		groups := map[string]bool{}
		index := func(entry callDiagnosticStoredEvent) {
			var fields struct {
				EventID string `json:"eventId"`
				RunID   string `json:"runId"`
			}
			if json.Unmarshal(entry.Event, &fields) != nil || !diagnosticUUID.MatchString(fields.EventID) || !diagnosticUUID.MatchString(fields.RunID) {
				return
			}
			group := callDiagnosticRuntimeGroup(rec.Owner, fields.RunID)
			groups[group] = true
			s.runtimeEventRecords[diagnosticPrivateKey(group, fields.EventID)] = key
		}
		for _, entry := range rec.Events {
			index(entry)
		}
		for _, entry := range rec.Summaries {
			index(entry)
		}
		for group := range groups {
			for _, id := range rec.DiscardedEventIDs {
				s.runtimeEventRecords[diagnosticPrivateKey(group, id)] = key
			}
		}
		if len(rec.RuntimeGroup) == 64 && rec.RuntimePartition >= 0 && key == callDiagnosticRuntimePartitionKey(rec.RuntimeGroup, rec.RuntimePartition) {
			previous := s.records[s.runtimeHeads[rec.RuntimeGroup]]
			if previous == nil || previous.RuntimePartition < rec.RuntimePartition {
				s.runtimeHeads[rec.RuntimeGroup] = key
			}
		}
	}
}

func (s *callDiagnosticStore) runtimeRecordLocked(actor, runID, eventID string, eventBytes int) (key, group string, partition int) {
	if s.runtimeHeads == nil {
		s.rebuildRuntimeIndexesLocked()
	}
	group = callDiagnosticRuntimeGroup(diagnosticPrivateKey(actor), runID)
	if existing := s.runtimeEventRecords[diagnosticPrivateKey(group, eventID)]; s.records[existing] != nil {
		return existing, group, s.records[existing].RuntimePartition
	}
	key = s.runtimeHeads[group]
	if rec := s.records[key]; rec != nil {
		partition = rec.RuntimePartition
		bytes := 0
		for _, entry := range rec.Events {
			bytes += len(entry.Event)
		}
		if len(rec.Events) < callDiagnosticTraceEvents && bytes+eventBytes <= callDiagnosticTraceBytes {
			return key, group, partition
		}
		partition++
	}
	return callDiagnosticRuntimePartitionKey(group, partition), group, partition
}

func (s *callDiagnosticStore) appendEventResult(actor string, raw json.RawMessage, server bool, epochs ...int64) callDiagnosticAppendResult {
	event, err := validateCallDiagnosticEvent(raw, server)
	if err != nil {
		return callDiagnosticAppendRetry
	}
	raw, _ = json.Marshal(event) // Persist canonical validated fields, never duplicate-key input bytes.
	key, _ := event["traceId"].(string)
	s.mu.Lock()
	defer s.mu.Unlock()
	consent := s.state.Consent[diagnosticPrivateKey(actor)]
	if !consent.Enabled || (len(epochs) > 0 && (epochs[0] <= 0 || epochs[0] != consent.ConsentEpoch)) {
		return callDiagnosticAppendRetry
	}
	id := event["eventId"].(string)
	runtimeGroup, runtimePartition := "", 0
	if key == "" {
		key, runtimeGroup, runtimePartition = s.runtimeRecordLocked(actor, event["runId"].(string), id, len(raw))
	}
	if !s.ensureLocked(actor, key) {
		return callDiagnosticAppendRetry
	}
	rec := s.records[key]
	if runtimeGroup != "" && key == callDiagnosticRuntimePartitionKey(runtimeGroup, runtimePartition) {
		rec.RuntimeGroup, rec.RuntimePartition = runtimeGroup, runtimePartition
		// A retry can target an older retained partition. It must never move
		// the fresh-write head backward into an already full record.
		previous := s.records[s.runtimeHeads[runtimeGroup]]
		if previous == nil || previous.RuntimePartition < runtimePartition {
			s.runtimeHeads[runtimeGroup] = key
		}
	}
	for _, e := range rec.Events {
		var fields struct {
			EventID string `json:"eventId"`
		}
		_ = json.Unmarshal(e.Event, &fields)
		if fields.EventID == id {
			if bytesEqualJSON(e.Event, raw) {
				return callDiagnosticAppendAccepted
			}
			return callDiagnosticAppendRetry
		}
	}
	for _, e := range rec.Summaries {
		var fields struct {
			EventID string `json:"eventId"`
		}
		_ = json.Unmarshal(e.Event, &fields)
		if fields.EventID == id {
			if bytesEqualJSON(e.Event, raw) {
				return callDiagnosticAppendAccepted
			}
			return callDiagnosticAppendRetry
		}
	}
	if diagnosticContains(rec.DiscardedEventIDs, id) {
		return callDiagnosticAppendDiscarded
	}
	copyRec := *rec
	copyRec.Events = append([]callDiagnosticStoredEvent(nil), rec.Events...)
	copyRec.DiscardedEventIDs = append([]string(nil), rec.DiscardedEventIDs...)
	copyRec.Summaries = map[string]callDiagnosticStoredEvent{}
	for k, v := range rec.Summaries {
		copyRec.Summaries[k] = v
	}
	entry := callDiagnosticStoredEvent{s.now().UnixMilli(), append(json.RawMessage(nil), raw...)}
	eventBytes := 0
	for _, e := range rec.Events {
		eventBytes += len(e.Event)
	}
	terminal := event["stage"] == "terminal" && event["action"] == "finish"
	values, _ := event["values"].(map[string]any)
	role, _ := event["role"].(string)
	mediaKey := diagnosticPrivateKey(actor, "first-verified-media")
	_, hasMedia := rec.Summaries[mediaKey]
	firstMedia := !server && !hasMedia && (role == "caller" || role == "callee") && event["stage"] == "media" && (event["outcome"] == "media_flow_verified" || values["mediaFlowVerified"] == true)
	discarded := false
	if len(rec.Events) >= callDiagnosticTraceEvents || eventBytes+len(raw) > callDiagnosticTraceBytes {
		if !terminal && !firstMedia {
			discarded = true
			if len(rec.DiscardedEventIDs) < callDiagnosticDiscardIDLimit {
				if rec.Dropped == 0 && rec.LegacyDropAttempts == 0 {
					rec.DroppedFirstAtMs = entry.ReceivedAtMs
				}
				rec.DiscardedEventIDs = append(rec.DiscardedEventIDs, id)
				rec.Dropped++
				rec.DroppedUpdatedAtMs = entry.ReceivedAtMs
			} else {
				if rec.DiscardLedgerSaturated {
					return callDiagnosticAppendDiscarded
				}
				// Keep a lower bound rather than count unknown retry multiplicity.
				rec.DiscardLedgerSaturated = true
				rec.DroppedUpdatedAtMs = entry.ReceivedAtMs
			}
		}
	} else {
		rec.Events = append(rec.Events, entry)
	}
	if terminal {
		rec.Summaries[diagnosticPrivateKey(actor, event["source"].(string))] = entry
	}
	if firstMedia {
		rec.Summaries[mediaKey] = entry
	}
	rec.UpdatedAtMs = s.now().UnixMilli()
	total, owner := 0, 0
	for _, r := range s.records {
		b, _ := json.Marshal(r)
		total += len(b)
		if r.Owner == rec.Owner {
			owner += len(b)
		}
	}
	encoded, _ := json.Marshal(rec)
	if total > s.quota || owner > callDiagnosticOwnerBytes || len(encoded) > callDiagnosticRecordBytes || s.persistLocked(key) != nil {
		*rec = copyRec
		return callDiagnosticAppendRetry
	}
	if runtimeGroup != "" {
		s.runtimeEventRecords[diagnosticPrivateKey(runtimeGroup, id)] = key
	}
	if discarded {
		return callDiagnosticAppendDiscarded
	}
	return callDiagnosticAppendAccepted
}
func bytesEqualJSON(a, b []byte) bool {
	var x, y any
	_ = json.Unmarshal(a, &x)
	_ = json.Unmarshal(b, &y)
	cx, _ := json.Marshal(x)
	cy, _ := json.Marshal(y)
	return string(cx) == string(cy)
}
func (s *callDiagnosticStore) expireLocked() {
	defer s.rebuildRuntimeIndexesLocked()
	now := s.now().UnixMilli()
	expired := []string{}
	s.metaMu.Lock()
	for key, r := range s.records {
		if now-r.CreatedAtMs > callDiagnosticRetention.Milliseconds() {
			for _, b := range r.Bindings {
				delete(s.bindings, b)
			}
			delete(s.records, key)
			delete(s.metadata, key)
			expired = append(expired, key)
		}
	}
	for key, c := range s.state.Consent {
		if now-c.UpdatedAtMs > callDiagnosticRetention.Milliseconds() {
			delete(s.state.Consent, key)
			delete(s.consentMetadata, key)
			delete(s.pushGenerations, key)
		}
	}
	for key, c := range s.state.Authority {
		if now-c.AtMs > callDiagnosticRetention.Milliseconds() {
			delete(s.state.Authority, key)
			delete(s.authorityMetadata, key)
		}
	}
	s.metaMu.Unlock()
	for _, key := range expired {
		_ = os.Remove(filepath.Join(s.dir, key+".json"))
	}
}

func (s *callDiagnosticStore) clearActor(actor string, epoch int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	a := diagnosticPrivateKey(actor)
	old := s.state.Consent[a]
	if epoch <= 0 || epoch < old.ConsentEpoch {
		return errors.New("stale diagnostic consent")
	}
	c := old
	c.ConsentEpoch = epoch
	c.UpdatedAtMs = s.now().UnixMilli()
	s.state.Consent[a] = c
	if err := s.writePrivateLocked(); err != nil {
		s.state.Consent[a] = old
		return err
	}
	s.metaMu.Lock()
	c.PushCapability = s.consentMetadata[a].PushCapability
	s.state.Consent[a] = c
	s.consentMetadata[a] = c
	s.metaMu.Unlock()
	return s.purgeActorLocked(actor)
}

func (s *callDiagnosticStore) purgeActorLocked(actor string) error {
	defer s.rebuildRuntimeIndexesLocked()
	a := diagnosticPrivateKey(actor)
	s.metaMu.Lock()
	for key, m := range s.metadata {
		if m.owner == a || diagnosticContains(m.participants, a) {
			for _, b := range m.bindings {
				delete(s.bindings, b)
			}
			delete(s.metadata, key)
		}
	}
	for key, change := range s.state.Authority {
		if change.AuthorDigest == a {
			delete(s.state.Authority, key)
			delete(s.authorityMetadata, key)
		}
	}
	s.metaMu.Unlock()
	for key, r := range s.records {
		if r.Owner == a || diagnosticContains(r.Participants, a) {
			delete(s.records, key)
			if err := os.Remove(filepath.Join(s.dir, key+".json")); err != nil && !os.IsNotExist(err) {
				return err
			}
		}
	}
	return s.writePrivateLocked()
}

func (s *callDiagnosticStore) authorityChange(actor, target string, d *callDiagnosticContext, kind string) {
	if s == nil || d == nil || !diagnosticUUID.MatchString(d.OperationID) {
		return
	}
	s.enqueue(func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		if c := s.state.Consent[diagnosticPrivateKey(actor)]; !c.Enabled || c.ConsentEpoch != d.consentEpoch {
			return
		}
		if len(s.state.Authority) >= 10000 {
			return
		}
		s.state.Authority[diagnosticPrivateKey(target, kind)] = callDiagnosticAuthorityChange{AuthorDigest: diagnosticPrivateKey(actor), OperationID: d.OperationID, AtMs: s.now().UnixMilli(), Reason: d.Reason}
		s.metaMu.Lock()
		s.authorityMetadata[diagnosticPrivateKey(target, kind)] = s.state.Authority[diagnosticPrivateKey(target, kind)]
		s.metaMu.Unlock()
		if s.writePrivateLocked() != nil {
			s.drop("sink_unavailable")
		}
	})
}
func (s *callDiagnosticStore) lastAuthority(target string) callDiagnosticAuthorityChange {
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	return s.authorityMetadata[diagnosticPrivateKey(target, "endpoint")]
}

func initCallDiagnosticsFromEnvironment() *callDiagnosticStore {
	dir := os.Getenv("CALL_DIAGNOSTICS_DIR")
	if dir == "" {
		return nil
	}
	s, err := newCallDiagnosticStore(dir, callDiagnosticGlobalBytes, time.Now)
	if err != nil {
		log.Print("call_diagnostics storage=unavailable")
		return nil
	}
	callDiagnosticStorageReady.Set(1)
	log.Print("call_diagnostics storage=ready")
	return s
}

// Only used by focused tests; sorting never exports private authorization keys.
func (s *callDiagnosticStore) sortedKeys() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	keys := make([]string, 0, len(s.records))
	for key := range s.records {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

// A legacy token registration proves that this registration did not negotiate
// the additive push parser. Invalidate only effective capability, preserving
// desired consent/high-water epoch. A later same-epoch configure can restore it.
func (s *callDiagnosticStore) invalidateLegacyPushCapability(actor string) {
	if s == nil {
		return
	}
	key := diagnosticPrivateKey(actor)
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	_, consenting := s.consentMetadata[key]
	_, configuring := s.pushGenerations[key]
	if !consenting && !configuring {
		return
	}
	s.pushGenerations[key]++
	c := s.consentMetadata[key]
	c.PushCapability = false
	s.consentMetadata[key] = c
}
