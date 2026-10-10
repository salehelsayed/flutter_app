package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
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

// callDiagnosticMaxGlobalBytes bounds CALL_DIAGNOSTICS_MAX_BYTES. The default
// store filled in production and then refused every ordinary event, keeping
// only terminal and first-media records.
const callDiagnosticMaxGlobalBytes = 512 << 20
const callDiagnosticOwnerBytes = 5 << 20

// A joined trace includes two independently bounded endpoint spools plus relay stages.
const callDiagnosticTraceEvents = 3 * 256
const callDiagnosticTraceBytes = 3 * (64 << 10)
const callDiagnosticRecordBytes = 320 << 10
const callDiagnosticDiscardIDLimit = 256

// Ordinary observations leave room for terminal/first-media evidence. These
// reservations do not raise either hard byte ceiling or evict retained records.
const callDiagnosticPriorityBytes = 32 << 10

type callDiagnosticConsent struct {
	// Process-local fence for queued jobs; clear can preserve the wire epoch.
	privacyGeneration uint64
	ErasePending      bool `json:"erasePending,omitempty"`
	// Effective capability is process-local: persisted consent alone never proves the installed push parser.
	PushCapability bool  `json:"-"`
	ConsentEpoch   int64 `json:"consentEpoch"`
	Enabled        bool  `json:"enabled"`
	PushTrace      bool  `json:"pushTrace"`
	UpdatedAtMs    int64 `json:"updatedAtMs"`
}
type callDiagnosticAuthorityChange struct {
	// Captured at lookup, never persisted or exposed in diagnostic events.
	privacyGeneration uint64
	AuthorDigest      string `json:"authorDigest"`
	OperationID       string `json:"operationId"`
	AtMs              int64  `json:"atMs"`
	Reason            string `json:"reason"`
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
	// Operator-only response receipts. Never part of Events/Summaries or the
	// public diagnostic schema. Existing quotas, consent purge and retention apply.
	APNSResponsesPrivate   []apnsVoIPResponseReceipt            `json:"apnsResponsesPrivate,omitempty"`
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
	// Expired records remain charged until removal succeeds, but confer no authority.
	expired      bool
	owner        string
	participants []string
	handleDigest string
	bindings     []string
}
type callDiagnosticStore struct {
	apnsCapture            apnsVoIPCapturePolicy
	apnsCaptured           int
	nextPrivacyGeneration  uint64 // allocated under mu; never reused after consent expiry
	pushGenerations        map[string]uint64
	beforeConfigurePublish func()
	metaMu                 sync.Mutex
	metadata               map[string]*callDiagnosticMetadata
	consentMetadata        map[string]callDiagnosticConsent
	authorityMetadata      map[string]callDiagnosticAuthorityChange

	mu                   sync.Mutex
	dir                  string
	now                  func() time.Time
	quota                int
	ownerQuota           int
	sizes                map[string]int
	ownerSizes           map[string]int
	bindingReserves      map[string]int
	ownerBindingReserves map[string]int
	bindingReserved      int
	usedBytes            int
	write                func(string, []byte) error
	pendingWrite         *diagnosticRepair
	privateRaw           []byte
	remove               func(string) error
	state                callDiagnosticPrivateState
	records              map[string]*callDiagnosticRecord
	bindings             map[string]string
	queue                chan func()
	done                 chan struct{}
	dropped              atomic.Uint64
	runID                string
	sequence             atomic.Uint64
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
	s := &callDiagnosticStore{dir: dir, quota: quota, ownerQuota: callDiagnosticOwnerBytes, write: appDiagnosticAtomicWrite, remove: os.Remove, now: now, records: map[string]*callDiagnosticRecord{}, bindings: map[string]string{}, queue: make(chan func(), 512), done: make(chan struct{}), runID: uuid.NewString(), state: callDiagnosticPrivateState{Consent: map[string]callDiagnosticConsent{}, Authority: map[string]callDiagnosticAuthorityChange{}}}
	raw, err := os.ReadFile(filepath.Join(dir, "private.json"))
	if err == nil {
		s.privateRaw = append([]byte(nil), raw...)
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
		if e != nil || !info.Mode().IsRegular() || info.Size() > callDiagnosticRecordBytes {
			return nil, errors.New("invalid diagnostic file")
		}
		file, e := os.Open(filepath.Join(dir, name))
		if e != nil {
			return nil, e
		}
		// Bound the read itself as well as the stat: a changing file must not
		// allocate beyond one record. Leave invalid/oversized bytes untouched.
		raw, e := io.ReadAll(io.LimitReader(file, callDiagnosticRecordBytes+1))
		_ = file.Close()
		if e != nil {
			return nil, e
		}
		if len(raw) > callDiagnosticRecordBytes {
			return nil, errors.New("invalid diagnostic file")
		}
		var rec callDiagnosticRecord
		if json.Unmarshal(raw, &rec) != nil {
			return nil, errors.New("invalid diagnostic record")
		}
		if rec.Summaries == nil {
			rec.Summaries = map[string]callDiagnosticStoredEvent{}
		}
		if now().UnixMilli()-rec.CreatedAtMs > callDiagnosticRetention.Milliseconds() {
			if err := s.remove(filepath.Join(dir, name)); err != nil && !os.IsNotExist(err) {
				return nil, err
			}
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
		s.nextPrivacyGeneration++
		c.privacyGeneration = s.nextPrivacyGeneration
		s.state.Consent[key] = c
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
	s.rebuildByteIndexesLocked()
	for owner, c := range s.state.Consent {
		if c.ErasePending || !c.Enabled {
			if err := s.purgeDigestLocked(owner, "maintenance"); err != nil {
				return nil, err
			}
		}
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
func (s *callDiagnosticStore) close()             { close(s.queue); <-s.done }
func (s *callDiagnosticStore) enqueue(job func()) { s.enqueueSource("unknown", job) }
func (s *callDiagnosticStore) enqueueSource(source string, job func()) {
	if s == nil {
		return
	}
	select {
	case s.queue <- job:
	default:
		diagnosticRefusal("call", source, "queue_full")
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
func (s *callDiagnosticStore) writePrivateLocked(sources ...string) error {
	raw, err := json.Marshal(s.state)
	if err != nil {
		return err
	}
	err = transactionalDiagnosticWrite(&s.pendingWrite, s.write, s.remove, filepath.Join(s.dir, "private.json"), raw, s.privateRaw)
	if err == nil {
		s.privateRaw = raw
	} else {
		source := "maintenance"
		if len(sources) > 0 {
			source = sources[0]
		}
		diagnosticRefusal("call", source, "persistence")
	}
	return err
}
func (s *callDiagnosticStore) persistLocked(key string) error {
	raw, err := json.Marshal(s.records[key])
	if err != nil {
		return err
	}
	prior, readErr := os.ReadFile(filepath.Join(s.dir, key+".json"))
	if readErr != nil && !os.IsNotExist(readErr) {
		return readErr
	}
	if err = s.writeRecordLocked(key, raw, prior); err != nil {
		return err
	}
	s.indexBytesLocked(key, s.records[key], len(raw))
	return nil
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
		diagnosticRefusal("call", "configure", "record_count")
		return errors.New("diagnostic quota exceeded")
	}
	old := s.state.Consent[key]
	if epoch <= 0 || epoch < old.ConsentEpoch || (epoch == old.ConsentEpoch && (old.Enabled != enabled || old.PushTrace != (enabled && push))) {
		diagnosticRefusal("call", "configure", "epoch")
		return errors.New("stale diagnostic consent")
	}
	s.metaMu.Lock()
	generation := s.pushGenerations[key] + 1
	s.pushGenerations[key] = generation
	s.metaMu.Unlock()
	privacyGeneration := old.privacyGeneration
	if epoch != old.ConsentEpoch {
		s.nextPrivacyGeneration++
		privacyGeneration = s.nextPrivacyGeneration
	}
	s.state.Consent[key] = callDiagnosticConsent{privacyGeneration: privacyGeneration, ConsentEpoch: epoch, Enabled: enabled, PushTrace: enabled && push, UpdatedAtMs: s.now().UnixMilli(), ErasePending: !enabled || old.ErasePending}
	if err := s.writePrivateLocked("configure"); err != nil {
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
	if !enabled || candidate.ErasePending {
		return s.purgeActorLocked(actor, "configure")
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
	if meta == nil || meta.expired {
		return false
	}
	a := diagnosticPrivateKey(actor)
	if s.consentMetadata[meta.owner].ErasePending {
		return false
	}
	for _, p := range meta.participants {
		if s.consentMetadata[p].ErasePending {
			return false
		}
	}
	return meta.owner == a || diagnosticContains(meta.participants, a)
}

func (s *callDiagnosticStore) ensureLocked(actor, key string) bool {
	if s.records[key] != nil {
		return s.authorizedLocked(actor, key)
	}
	if len(s.records) >= 10000 {
		return false
	}
	a := diagnosticPrivateKey(actor)
	now := s.now().UnixMilli()
	s.metaMu.Lock()
	meta := s.metadata[key]
	owner := a
	if meta != nil {
		owner = meta.owner
	}
	if s.usedBytes >= s.quota || s.ownerSizes[owner] >= s.ownerQuota {
		s.metaMu.Unlock()
		return false
	}
	if meta == nil {
		if len(s.metadata) >= 10000 {
			s.metaMu.Unlock()
			return false
		}
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
	if !c.Enabled || c.ErasePending || (len(epochs) > 0 && (epochs[0] <= 0 || epochs[0] != c.ConsentEpoch)) {
		return false
	}
	d.consentEpoch = c.ConsentEpoch
	d.privacyGeneration = c.privacyGeneration
	d.traceLifetime = nil
	if d.TraceID == "" {
		return true
	}
	if s.metadata[d.TraceID] == nil {
		if len(s.metadata) >= 10000 {
			return false
		}
		s.metadata[d.TraceID] = &callDiagnosticMetadata{owner: a}
	}
	if !s.authorizedMetadataLocked(actor, d.TraceID) {
		return false
	}
	d.traceLifetime = s.metadata[d.TraceID]
	return true
}

func (s *callDiagnosticStore) contextAuthorizedLocked(actor string, d *callDiagnosticContext) bool {
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	return s.contextAuthorizedMetadataLocked(actor, d)
}

// A retained metadata identity is a process-local capability for one trace
// lifetime. Deletion/recreation cannot revive it, and expiry quarantines it
// even when removal fails. Only live contexts retain old identities; there is
// no tombstone map or public/persisted generation field.
func (s *callDiagnosticStore) contextAuthorizedMetadataLocked(actor string, d *callDiagnosticContext) bool {
	c := s.consentMetadata[diagnosticPrivateKey(actor)]
	if !c.Enabled || c.ErasePending || c.ConsentEpoch != d.consentEpoch || c.privacyGeneration != d.privacyGeneration {
		return false
	}
	if d.TraceID == "" {
		return d.traceLifetime == nil
	}
	return d.traceLifetime != nil && s.metadata[d.TraceID] == d.traceLifetime && s.authorizedMetadataLocked(actor, d.TraceID)
}

func (s *callDiagnosticStore) bindCommitted(actor, recipient, handle string, d *callDiagnosticContext) {
	if s == nil || d == nil || d.TraceID == "" {
		return
	}
	// Eager metadata and queued persistence use the same admitted context.
	// The caller can reuse its span as soon as this method returns.
	captured := *d
	d = &captured
	s.metaMu.Lock()
	if !s.contextAuthorizedMetadataLocked(actor, d) {
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
	s.enqueueSource("binding", func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		if !s.contextAuthorizedLocked(actor, d) {
			diagnosticRefusal("call", "binding", "epoch")
			return
		}
		prior := s.records[d.TraceID]
		if !s.ensureLocked(actor, d.TraceID) {
			diagnosticRefusal("call", "binding", s.admissionReasonLocked(actor, d.TraceID))
			return
		}
		r := s.records[d.TraceID]
		candidate := *r
		s.metaMu.Lock()
		meta := s.metadata[d.TraceID]
		if meta == nil {
			s.metaMu.Unlock()
			if prior == nil {
				delete(s.records, d.TraceID)
			}
			return
		}
		candidate.Participants = append([]string(nil), meta.participants...)
		candidate.Bindings = append([]string(nil), meta.bindings...)
		candidate.HandleDigest = meta.handleDigest
		s.metaMu.Unlock()
		encoded, _ := json.Marshal(&candidate)
		reason := s.budgetReasonLocked(d.TraceID, &candidate, len(encoded))
		if reason == "" {
			var old []byte
			if prior != nil {
				old = mustDiagnosticJSON(prior)
			}
			if err := s.writeRecordLocked(d.TraceID, encoded, old); err != nil {
				reason = "persistence"
			}
		}
		if reason != "" {
			if prior == nil {
				delete(s.records, d.TraceID)
			}
			diagnosticRefusal("call", "binding", reason)
			s.drop("sink_unavailable")
			return
		}
		*r = candidate
		s.indexBytesLocked(d.TraceID, r, len(encoded))
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
	callDiagnosticAppendConflict
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
	return s.appendEventContext(actor, raw, server, nil, epochs...)
}

// Queued server contexts carry private provenance separately from public JSON.
// Validation and persistence share mu with clear/configure/expiry, so a privacy
// transition cannot slip between checking the origin and publishing its bytes.
func (s *callDiagnosticStore) appendEventContext(actor string, raw json.RawMessage, server bool, d *callDiagnosticContext, epochs ...int64) callDiagnosticAppendResult {
	source := "upload"
	if server {
		source = "span"
	}
	refuse := func(reason string) callDiagnosticAppendResult {
		diagnosticRefusal("call", source, reason)
		return callDiagnosticAppendRetry
	}
	event, err := validateCallDiagnosticEvent(raw, server)
	if err != nil {
		return refuse("invalid")
	}
	raw, _ = json.Marshal(event) // Persist canonical validated fields, never duplicate-key input bytes.
	key, _ := event["traceId"].(string)
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := repairDiagnosticWrite(&s.pendingWrite, s.write, s.remove); err != nil {
		return refuse("persistence")
	}
	consent := s.state.Consent[diagnosticPrivateKey(actor)]
	if consent.ErasePending {
		return refuse("consent")
	}
	if !consent.Enabled {
		return refuse("consent")
	}
	if len(epochs) > 0 && (epochs[0] <= 0 || epochs[0] != consent.ConsentEpoch) {
		return refuse("epoch")
	}
	if d != nil {
		if d.TraceID != key || !s.contextAuthorizedLocked(actor, d) {
			return refuse("consent")
		}
		if origin := d.origin; origin.AuthorDigest != "" {
			c := s.state.Consent[origin.AuthorDigest]
			if !c.Enabled || c.ErasePending || c.privacyGeneration != origin.privacyGeneration {
				delete(event, "parentOperationId")
				raw, _ = json.Marshal(event)
			}
		}
	}
	id := event["eventId"].(string)
	runtimeGroup, runtimePartition := "", 0
	if key == "" {
		key, runtimeGroup, runtimePartition = s.runtimeRecordLocked(actor, event["runId"].(string), id, len(raw))
	}
	prior := s.records[key]
	s.metaMu.Lock()
	hadMetadata := s.metadata[key] != nil
	s.metaMu.Unlock()
	if !s.ensureLocked(actor, key) {
		return refuse(s.admissionReasonLocked(actor, key))
	}
	committed := false
	defer func() {
		if prior == nil && !committed {
			delete(s.records, key)
			if !hadMetadata {
				s.metaMu.Lock()
				// A concurrently committed binding remains authoritative.
				if m := s.metadata[key]; m != nil && len(m.bindings) == 0 && m.handleDigest == "" {
					delete(s.metadata, key)
				}
				s.metaMu.Unlock()
			}
		}
	}()
	rec := s.records[key]
	for _, e := range rec.Events {
		var fields struct {
			EventID string `json:"eventId"`
		}
		_ = json.Unmarshal(e.Event, &fields)
		if fields.EventID == id {
			if bytesEqualJSON(e.Event, raw) {
				return callDiagnosticAppendAccepted
			}
			diagnosticRefusal("call", source, "conflict")
			return callDiagnosticAppendConflict
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
			diagnosticRefusal("call", source, "conflict")
			return callDiagnosticAppendConflict
		}
	}
	if diagnosticContains(rec.DiscardedEventIDs, id) {
		diagnosticRefusal("call", source, "record_capacity")
		return callDiagnosticAppendDiscarded
	}
	copyRec := *rec
	if rec.Events != nil {
		copyRec.Events = make([]callDiagnosticStoredEvent, len(rec.Events))
		copy(copyRec.Events, rec.Events)
	}
	copyRec.DiscardedEventIDs = append([]string(nil), rec.DiscardedEventIDs...)
	copyRec.Summaries = map[string]callDiagnosticStoredEvent{}
	for k, v := range rec.Summaries {
		copyRec.Summaries[k] = v
	}
	s.metaMu.Lock()
	if m := s.metadata[key]; m != nil {
		rec.Participants = append([]string(nil), m.participants...)
		rec.Bindings = append([]string(nil), m.bindings...)
		rec.HandleDigest = m.handleDigest
	}
	s.metaMu.Unlock()
	if runtimeGroup != "" && key == callDiagnosticRuntimePartitionKey(runtimeGroup, runtimePartition) {
		rec.RuntimeGroup, rec.RuntimePartition = runtimeGroup, runtimePartition
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
					*rec = copyRec
					diagnosticRefusal("call", source, "record_capacity")
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
	encoded, _ := json.Marshal(rec)
	reason := s.budgetReasonLocked(key, rec, len(encoded))
	if reason == "" && !terminal && !firstMedia && !discarded {
		delta := len(encoded) - s.sizes[key]
		if s.usedBytes+delta > s.quota-callDiagnosticPriorityBytes {
			reason = "global_bytes"
		} else if s.ownerSizes[rec.Owner]+delta > s.ownerQuota-callDiagnosticPriorityBytes {
			reason = "owner_bytes"
		}
	}
	if reason == "" {
		var old []byte
		if prior != nil {
			old = mustDiagnosticJSON(&copyRec)
		}
		if err := s.writeRecordLocked(key, encoded, old); err != nil {
			reason = "persistence"
		}
	}
	if reason != "" {
		*rec = copyRec
		return refuse(reason)
	}
	committed = true
	s.indexBytesLocked(key, rec, len(encoded))
	if runtimeGroup != "" && key == callDiagnosticRuntimePartitionKey(runtimeGroup, runtimePartition) {
		rec.RuntimeGroup, rec.RuntimePartition = runtimeGroup, runtimePartition
		// A retry can target an older retained partition. It must never move
		// the fresh-write head backward into an already full record.
		previous := s.records[s.runtimeHeads[runtimeGroup]]
		if previous == nil || previous.RuntimePartition < runtimePartition {
			s.runtimeHeads[runtimeGroup] = key
		}
	}
	if runtimeGroup != "" {
		s.runtimeEventRecords[diagnosticPrivateKey(runtimeGroup, id)] = key
	}
	if discarded {
		diagnosticRefusal("call", source, "record_capacity")
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
	// Quarantine before any fallible repair/removal. Preserve metadata membership
	// so the wire boundary can still distinguish participants from foreign actors.
	s.metaMu.Lock()
	for key, r := range s.records {
		if s.now().UnixMilli()-r.CreatedAtMs > callDiagnosticRetention.Milliseconds() {
			if m := s.metadata[key]; m != nil {
				m.expired = true
			}
		}
	}
	s.metaMu.Unlock()
	if err := repairDiagnosticWrite(&s.pendingWrite, s.write, s.remove); err != nil {
		diagnosticRefusal("call", "maintenance", "persistence")
		return
	}
	defer s.rebuildRuntimeIndexesLocked()
	now := s.now().UnixMilli()
	for key, r := range s.records {
		if now-r.CreatedAtMs <= callDiagnosticRetention.Milliseconds() {
			continue
		}
		if err := s.remove(filepath.Join(s.dir, key+".json")); err != nil && !os.IsNotExist(err) {
			diagnosticRefusal("call", "maintenance", "persistence")
			continue
		}
		s.unindexBytesLocked(key, r)
		delete(s.records, key)
		s.metaMu.Lock()
		if m := s.metadata[key]; m != nil {
			for _, b := range m.bindings {
				delete(s.bindings, b)
			}
		}
		delete(s.metadata, key)
		s.metaMu.Unlock()
	}
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	for key, c := range s.state.Consent {
		if now-c.UpdatedAtMs > callDiagnosticRetention.Milliseconds() && !c.ErasePending {
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
}

func (s *callDiagnosticStore) clearActor(actor string, epoch int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	a := diagnosticPrivateKey(actor)
	old := s.state.Consent[a]
	if epoch <= 0 || epoch < old.ConsentEpoch {
		diagnosticRefusal("call", "clear", "epoch")
		return errors.New("stale diagnostic consent")
	}
	c := old
	s.nextPrivacyGeneration++
	c.privacyGeneration = s.nextPrivacyGeneration
	c.ConsentEpoch = epoch
	c.ErasePending = true
	c.UpdatedAtMs = s.now().UnixMilli()
	s.state.Consent[a] = c
	if err := s.writePrivateLocked("clear"); err != nil {
		s.state.Consent[a] = old
		return err
	}
	s.metaMu.Lock()
	c.PushCapability = s.consentMetadata[a].PushCapability
	s.state.Consent[a] = c
	s.consentMetadata[a] = c
	s.metaMu.Unlock()
	return s.purgeActorLocked(actor, "clear")
}

func (s *callDiagnosticStore) purgeActorLocked(actor, source string) error {
	return s.purgeDigestLocked(diagnosticPrivateKey(actor), source)
}
func (s *callDiagnosticStore) purgeDigestLocked(a string, sources ...string) error {
	source := "maintenance"
	if len(sources) > 0 {
		source = sources[0]
	}
	defer s.rebuildRuntimeIndexesLocked()
	keys := map[string]bool{}
	s.metaMu.Lock()
	for key, m := range s.metadata {
		if m.owner == a || diagnosticContains(m.participants, a) {
			keys[key] = true
		}
	}
	s.metaMu.Unlock()
	for key, r := range s.records {
		if r.Owner == a || diagnosticContains(r.Participants, a) {
			keys[key] = true
		}
	}
	for key := range keys {
		if err := s.remove(filepath.Join(s.dir, key+".json")); err != nil && !os.IsNotExist(err) {
			diagnosticRefusal("call", source, "persistence")
			return err
		}
		if r := s.records[key]; r != nil {
			s.unindexBytesLocked(key, r)
			delete(s.records, key)
		}
		s.metaMu.Lock()
		if m := s.metadata[key]; m != nil {
			for _, b := range m.bindings {
				delete(s.bindings, b)
			}
		}
		delete(s.metadata, key)
		s.metaMu.Unlock()
	}
	s.metaMu.Lock()
	for key, change := range s.state.Authority {
		if change.AuthorDigest == a {
			delete(s.state.Authority, key)
			delete(s.authorityMetadata, key)
		}
	}
	c := s.state.Consent[a]
	c.ErasePending = false
	s.state.Consent[a] = c
	s.metaMu.Unlock()
	if err := s.writePrivateLocked(source); err != nil {
		c.ErasePending = true
		s.state.Consent[a] = c
		return err
	}
	s.metaMu.Lock()
	// Legacy token registration may invalidate capability while disk I/O runs.
	c.PushCapability = s.consentMetadata[a].PushCapability
	s.state.Consent[a] = c
	s.consentMetadata[a] = c
	s.metaMu.Unlock()
	return nil
}

func (s *callDiagnosticStore) authorityChange(actor, target string, d *callDiagnosticContext, kind string) {
	if s == nil || d == nil || !diagnosticUUID.MatchString(d.OperationID) {
		return
	}
	// The caller may reuse or mutate its context after enqueueing.
	captured := *d
	s.enqueueSource("authority", func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		if !s.contextAuthorizedLocked(actor, &captured) {
			return
		}
		if len(s.state.Authority) >= 10000 {
			return
		}
		key := diagnosticPrivateKey(target, kind)
		old, exists := s.state.Authority[key]
		s.state.Authority[key] = callDiagnosticAuthorityChange{AuthorDigest: diagnosticPrivateKey(actor), OperationID: captured.OperationID, AtMs: s.now().UnixMilli(), Reason: captured.Reason}
		if s.writePrivateLocked("authority") != nil {
			if exists {
				s.state.Authority[key] = old
			} else {
				delete(s.state.Authority, key)
			}
			s.drop("sink_unavailable")
			return
		}
		s.metaMu.Lock()
		s.authorityMetadata[key] = s.state.Authority[key]
		s.metaMu.Unlock()
	})
}
func (s *callDiagnosticStore) lastAuthority(target string) callDiagnosticAuthorityChange {
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	change := s.authorityMetadata[diagnosticPrivateKey(target, "endpoint")]
	if c := s.consentMetadata[change.AuthorDigest]; !c.Enabled || c.ErasePending {
		return callDiagnosticAuthorityChange{}
	}
	change.privacyGeneration = s.consentMetadata[change.AuthorDigest].privacyGeneration
	return change
}

// callDiagnosticQuotaFromEnvironment keeps the store enabled on a bad value:
// losing every call record is worse than keeping the default ceiling.
func callDiagnosticQuotaFromEnvironment() int {
	raw := os.Getenv("CALL_DIAGNOSTICS_MAX_BYTES")
	if raw == "" {
		return callDiagnosticGlobalBytes
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < 1<<20 || n > callDiagnosticMaxGlobalBytes {
		log.Print("call_diagnostics global_limit=invalid_default_used")
		return callDiagnosticGlobalBytes
	}
	return n
}

func initCallDiagnosticsFromEnvironment() *callDiagnosticStore {
	dir := os.Getenv("CALL_DIAGNOSTICS_DIR")
	if dir == "" {
		return nil
	}
	s, err := newCallDiagnosticStore(dir, callDiagnosticQuotaFromEnvironment(), time.Now)
	if err != nil {
		log.Print("call_diagnostics storage=unavailable")
		return nil
	}
	s.apnsCapture = parseAPNSVoIPCapturePolicy(
		os.Getenv("APNS_VOIP_CAPTURE_OWNER_SHA256"),
		os.Getenv("APNS_VOIP_CAPTURE_UNTIL"), time.Now(),
	)
	s.ownerQuota = diagnosticOwnerQuota("CALL_DIAGNOSTICS_OWNER_MAX_BYTES", callDiagnosticOwnerBytes, s.quota)
	diagnosticOwnerLimit.WithLabelValues("call").Set(float64(s.ownerQuota))
	diagnosticGlobalLimit.WithLabelValues("call").Set(float64(s.quota))
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

// Canonical byte accounting is updated only after durable publication, or once
// while loading retained records. Runtime filenames participate identically.
func (s *callDiagnosticStore) rebuildByteIndexesLocked() {
	s.sizes = map[string]int{}
	s.ownerSizes = map[string]int{}
	s.usedBytes = 0
	s.bindingReserves = map[string]int{}
	s.ownerBindingReserves = map[string]int{}
	s.bindingReserved = 0
	for key, r := range s.records {
		raw, _ := json.Marshal(r)
		s.indexBytesLocked(key, r, len(raw))
	}
}
func (s *callDiagnosticStore) indexBytesLocked(key string, r *callDiagnosticRecord, size int) {
	if s.sizes == nil {
		s.sizes = map[string]int{}
		s.ownerSizes = map[string]int{}
	}
	if s.bindingReserves == nil {
		s.bindingReserves = map[string]int{}
		s.ownerBindingReserves = map[string]int{}
	}
	reserve := callDiagnosticBindingReserve(key, r)
	change := reserve - s.bindingReserves[key]
	s.bindingReserves[key] = reserve
	s.bindingReserved += change
	s.ownerBindingReserves[r.Owner] += change
	delta := size - s.sizes[key]
	s.sizes[key] = size
	s.usedBytes += delta
	s.ownerSizes[r.Owner] += delta
}
func (s *callDiagnosticStore) unindexBytesLocked(key string, r *callDiagnosticRecord) {
	reserve := s.bindingReserves[key]
	s.bindingReserved -= reserve
	s.ownerBindingReserves[r.Owner] -= reserve
	delete(s.bindingReserves, key)
	if s.ownerBindingReserves[r.Owner] == 0 {
		delete(s.ownerBindingReserves, r.Owner)
	}
	size := s.sizes[key]
	s.usedBytes -= size
	s.ownerSizes[r.Owner] -= size
	delete(s.sizes, key)
	if s.ownerSizes[r.Owner] == 0 {
		delete(s.ownerSizes, r.Owner)
	}
}
func (s *callDiagnosticStore) budgetReasonLocked(key string, r *callDiagnosticRecord, size int) string {
	if size > callDiagnosticRecordBytes {
		return "record_bytes"
	}
	delta := size - s.sizes[key]
	if s.usedBytes+delta > s.quota {
		return "global_bytes"
	}
	if s.ownerSizes[r.Owner]+delta > s.ownerQuota {
		return "owner_bytes"
	}
	reserveDelta := callDiagnosticBindingReserve(key, r) - s.bindingReserves[key]
	if s.usedBytes+delta+s.bindingReserved+reserveDelta > s.quota {
		return "global_bytes"
	}
	if s.ownerSizes[r.Owner]+delta+s.ownerBindingReserves[r.Owner]+reserveDelta > s.ownerQuota {
		return "owner_bytes"
	}
	return ""
}
func (s *callDiagnosticStore) admissionReasonLocked(actor, key string) string {
	s.metaMu.Lock()
	defer s.metaMu.Unlock()
	owner := diagnosticPrivateKey(actor)
	if m := s.metadata[key]; m != nil {
		owner = m.owner
	} else if len(s.metadata) >= 10000 {
		return "record_count"
	}
	if len(s.records) >= 10000 {
		return "record_count"
	}
	if s.usedBytes >= s.quota {
		return "global_bytes"
	}
	if s.ownerSizes[owner] >= s.ownerQuota {
		return "owner_bytes"
	}
	return "authority"
}

// Reserve the exact missing encoded binding shape, including field names and
// punctuation. This is private accounting, never additional persisted evidence.
func callDiagnosticBindingReserve(key string, r *callDiagnosticRecord) int {
	if isCallDiagnosticRuntimeKey(key) {
		return 0
	}
	candidate := *r
	candidate.Participants = append([]string(nil), r.Participants...)
	candidate.Bindings = append([]string(nil), r.Bindings...)
	if candidate.HandleDigest == "" {
		candidate.HandleDigest = strings.Repeat("0", 64)
	}
	for len(candidate.Participants) < 1 {
		candidate.Participants = append(candidate.Participants, strings.Repeat("0", 64))
	}
	for len(candidate.Bindings) < 2 {
		candidate.Bindings = append(candidate.Bindings, strings.Repeat("0", 64))
	}
	// Marshal only the small metadata shape, not events or summaries.
	candidate.Events = nil
	candidate.Summaries = nil
	candidate.DiscardedEventIDs = nil
	original := *r
	original.Events = nil
	original.Summaries = nil
	original.DiscardedEventIDs = nil
	return max(0, len(mustDiagnosticJSON(&candidate))-len(mustDiagnosticJSON(&original)))
}
func mustDiagnosticJSON(v any) []byte { raw, _ := json.Marshal(v); return raw }

func (s *callDiagnosticStore) writeRecordLocked(key string, raw, prior []byte) error {
	return transactionalDiagnosticWrite(&s.pendingWrite, s.write, s.remove, filepath.Join(s.dir, key+".json"), raw, prior)
}
