package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
)

const (
	directMediaBlobCustodyKind        = "direct_media_blob_v1"
	directMediaBlobCustodyContract    = "ack_or_expiry_v1"
	mediaCustodyUploadAction          = "upload_custody_v1"
	mediaCustodyAckAction             = "ack_custody_v1"
	mediaCustodyAdmissionEnabledEnv   = "DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED"
	mediaCustodyRootName              = ".custody-v1"
	mediaCustodyMarkerSchema          = "mknoon.direct-media-blob-custody.v1"
	mediaCustodyStatePending          = "pending"
	mediaCustodyStateAcked            = "acked"
	mediaCustodyStoreStored           = "stored"
	mediaCustodyStoreDuplicate        = "duplicate"
	mediaCustodyStoreRejectedFull     = "rejected_full"
	mediaCustodyStoreDisabled         = "disabled"
	mediaCustodyStoreAlreadyAcked     = "already_acked"
	mediaCustodyAckAcked              = "acked"
	mediaCustodyAckAlreadyAcked       = "already_acked"
	mediaCustodyErrorAdmissionOff     = "MEDIA_CUSTODY_ADMISSION_DISABLED"
	mediaCustodyErrorFull             = "MEDIA_CUSTODY_FULL"
	mediaCustodyErrorIdentityConflict = "MEDIA_CUSTODY_IDENTITY_CONFLICT"
	mediaCustodyErrorIneligible       = "MEDIA_CUSTODY_INELIGIBLE"
	mediaCustodyErrorNotAuthorized    = "MEDIA_CUSTODY_NOT_AUTHORIZED"
	mediaCustodyErrorHashMismatch     = "MEDIA_CUSTODY_HASH_MISMATCH"
	mediaCustodyErrorAlreadyAcked     = "MEDIA_CUSTODY_ALREADY_ACKED"
	mediaCustodyErrorNotFound         = "MEDIA_CUSTODY_NOT_FOUND"
	mediaCustodyErrorCleanupPending   = "MEDIA_CUSTODY_CLEANUP_PENDING"
	mediaCustodyErrorStorage          = "MEDIA_CUSTODY_STORAGE_ERROR"
	mediaCustodyMaxMIMEBytes          = 255
)

var mediaCustodyBlobIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)
var mediaCustodyHashPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)
var mediaCustodyTempPattern = regexp.MustCompile(`^\.[A-Za-z0-9_-]{1,128}\.(blob|marker)-[0-9]+\.tmp$`)
var errMediaCustodyBlobIntegrity = errors.New("media custody blob integrity mismatch")

type mediaCustodyFailure struct {
	code        string
	storeStatus string
	ackStatus   string
	cause       error
}

func (e *mediaCustodyFailure) Error() string {
	if e == nil {
		return ""
	}
	if e.cause != nil {
		return fmt.Sprintf("%s: %v", e.code, e.cause)
	}
	return e.code
}

type directMediaBlobCustodyMeta struct {
	Schema          string `json:"schema"`
	State           string `json:"state"`
	ID              string `json:"id"`
	To              string `json:"to"`
	Mime            string `json:"mime"`
	Size            int64  `json:"size"`
	ContentHash     string `json:"contentHash"`
	CustodyKind     string `json:"custodyKind"`
	CustodyContract string `json:"custodyContract"`
	CreatedAtMs     int64  `json:"createdAtMs"`
	ExpiresAtMs     int64  `json:"expiresAtMs"`
}

type mediaCustodyReservation struct {
	meta *directMediaBlobCustodyMeta
	done chan struct{}
}

type mediaCustodyPrepareResult struct {
	meta        *directMediaBlobCustodyMeta
	reservation *mediaCustodyReservation
	storeStatus string
}

// directMediaBlobCustodyKey is the internal comparable identity of one
// protected custody row: the exact (recipient, attachment id) target. Disk
// layout has always been recipient-scoped; since Plan 362 the in-memory maps
// share that identity so sibling recipients of one canonical blob ID own
// independent reservation, publication, blocked and ACK-cleanup state. The
// wire grammar, actions and marker schema are unchanged.
type directMediaBlobCustodyKey struct {
	recipient string
	id        string
}

func custodyKeyOf(to, id string) directMediaBlobCustodyKey {
	return directMediaBlobCustodyKey{recipient: to, id: id}
}

func (m *directMediaBlobCustodyMeta) custodyKey() directMediaBlobCustodyKey {
	return directMediaBlobCustodyKey{recipient: m.To, id: m.ID}
}

type directMediaBlobCustodyStore struct {
	mu sync.Mutex

	owner        *MediaStore
	rootDir      string
	entries      map[directMediaBlobCustodyKey]*directMediaBlobCustodyMeta
	reservations map[directMediaBlobCustodyKey]*mediaCustodyReservation
	blocked      map[directMediaBlobCustodyKey]*directMediaBlobCustodyMeta
	// ackCleanupPending keeps ACKed authority suppressed while a tombstone or
	// blob-unlink directory barrier is indeterminate. Its bytes remain charged
	// conservatively until a later access/sweep establishes a durable tombstone
	// with no blob.
	ackCleanupPending map[directMediaBlobCustodyKey]bool
	maxCount          int
	maxBytes          int64
	maxBlobSize       int64
	admission         bool
	now               func() time.Time
	remove            func(string) error
	rename            func(string, string) error
	syncDir           func(string) error
}

type directMediaBlobCustodyStoreConfig struct {
	now     func() time.Time
	remove  func(string) error
	rename  func(string, string) error
	syncDir func(string) error
}

func loadDirectMediaBlobCustodyAdmissionEnabledFromEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(mediaCustodyAdmissionEnabledEnv))) {
	case "1", "true":
		return true
	default:
		return false
	}
}

func newDirectMediaBlobCustodyStore(owner *MediaStore) (*directMediaBlobCustodyStore, error) {
	return newDirectMediaBlobCustodyStoreWithConfig(owner, directMediaBlobCustodyStoreConfig{})
}

// newDirectMediaBlobCustodyStoreWithConfig is the deterministic construction
// seam for reconciliation failure/expiry tests. Production always uses the
// zero config and therefore the real clock and filesystem operations.
func newDirectMediaBlobCustodyStoreWithConfig(
	owner *MediaStore,
	config directMediaBlobCustodyStoreConfig,
) (*directMediaBlobCustodyStore, error) {
	rootDir, err := containedPath(owner.dataDir, mediaCustodyRootName)
	if err != nil {
		return nil, fmt.Errorf("resolve media custody root: %w", err)
	}
	cs := &directMediaBlobCustodyStore{
		owner:             owner,
		rootDir:           rootDir,
		entries:           make(map[directMediaBlobCustodyKey]*directMediaBlobCustodyMeta),
		reservations:      make(map[directMediaBlobCustodyKey]*mediaCustodyReservation),
		blocked:           make(map[directMediaBlobCustodyKey]*directMediaBlobCustodyMeta),
		ackCleanupPending: make(map[directMediaBlobCustodyKey]bool),
		maxCount:          maxMediaPerPeer,
		maxBytes:          maxMediaBytesPerPeer,
		maxBlobSize:       maxMediaSize,
		admission:         loadDirectMediaBlobCustodyAdmissionEnabledFromEnv(),
		now:               time.Now,
		remove:            os.Remove,
		rename:            os.Rename,
		syncDir:           syncMediaCustodyDirectory,
	}
	if config.now != nil {
		cs.now = config.now
	}
	if config.remove != nil {
		cs.remove = config.remove
	}
	if config.rename != nil {
		cs.rename = config.rename
	}
	if config.syncDir != nil {
		cs.syncDir = config.syncDir
	}

	created, err := ensureMediaCustodyDirectory(rootDir)
	if err != nil {
		return nil, fmt.Errorf("create media custody root: %w", err)
	}
	if created {
		if err := cs.syncDir(owner.dataDir); err != nil {
			return nil, fmt.Errorf("sync media root after custody directory creation: %w", err)
		}
	}
	if err := cs.reconcile(); err != nil {
		return nil, err
	}
	setMediaCustodyAdmissionGauge(cs.admission)
	cs.refreshGaugesLocked()
	return cs, nil
}

func ensureMediaCustodyDirectory(path string) (bool, error) {
	_, err := os.Lstat(path)
	switch {
	case err == nil:
		info, statErr := os.Lstat(path)
		if statErr != nil {
			return false, statErr
		}
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return false, fmt.Errorf("%s is not a real directory", path)
		}
		return false, nil
	case !os.IsNotExist(err):
		return false, err
	}
	if err := os.MkdirAll(path, 0755); err != nil {
		return false, err
	}
	return true, nil
}

func syncMediaCustodyDirectory(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return f.Sync()
}

func containedPath(root string, elements ...string) (string, error) {
	rootAbs, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	parts := append([]string{rootAbs}, elements...)
	candidate := filepath.Join(parts...)
	candidateAbs, err := filepath.Abs(candidate)
	if err != nil {
		return "", err
	}
	rel, err := filepath.Rel(rootAbs, candidateAbs)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		return "", fmt.Errorf("path escapes root")
	}
	return candidateAbs, nil
}

func validLegacyMediaSegment(value string) bool {
	if value == "" || value == "." || value == ".." || value == mediaCustodyRootName {
		return false
	}
	return !filepath.IsAbs(value) && filepath.Base(value) == value &&
		!strings.ContainsAny(value, `/\\`) && !strings.ContainsRune(value, '\x00')
}

func validateDirectMediaBlobCustodyIdentity(req *mediaRequest) *mediaCustodyFailure {
	if req == nil || req.CustodyKind != directMediaBlobCustodyKind ||
		req.CustodyContract != directMediaBlobCustodyContract ||
		!mediaCustodyBlobIDPattern.MatchString(req.ID) ||
		!mediaCustodyHashPattern.MatchString(req.ContentHash) ||
		req.Size <= 0 || req.Size > maxMediaSize ||
		len(req.Mime) == 0 || len(req.Mime) > mediaCustodyMaxMIMEBytes ||
		len(req.AllowedPeers) != 0 {
		return &mediaCustodyFailure{code: mediaCustodyErrorIneligible}
	}
	for _, r := range req.Mime {
		if r < 0x20 || r > 0x7e {
			return &mediaCustodyFailure{code: mediaCustodyErrorIneligible}
		}
	}
	decoded, err := peer.Decode(req.To)
	if err != nil || decoded.String() != req.To {
		return &mediaCustodyFailure{code: mediaCustodyErrorIneligible}
	}
	return nil
}

func validateDirectMediaBlobCustodyExactRequest(req *mediaRequest) *mediaCustodyFailure {
	if failure := validateDirectMediaBlobCustodyIdentity(req); failure != nil {
		return failure
	}
	if req.ExpiresAtMs <= 0 {
		return &mediaCustodyFailure{code: mediaCustodyErrorIneligible}
	}
	return nil
}

func (m *directMediaBlobCustodyMeta) matchesIdentity(req *mediaRequest) bool {
	return m != nil && req != nil && m.ID == req.ID && m.To == req.To &&
		m.Mime == req.Mime && m.Size == req.Size && m.ContentHash == req.ContentHash &&
		m.CustodyKind == req.CustodyKind && m.CustodyContract == req.CustodyContract
}

func (m *directMediaBlobCustodyMeta) matchesExact(req *mediaRequest) bool {
	return m.matchesIdentity(req) && m.ExpiresAtMs == req.ExpiresAtMs
}

func cloneDirectMediaBlobCustodyMeta(meta *directMediaBlobCustodyMeta) *directMediaBlobCustodyMeta {
	if meta == nil {
		return nil
	}
	copy := *meta
	return &copy
}

func (cs *directMediaBlobCustodyStore) blobPath(meta *directMediaBlobCustodyMeta) (string, error) {
	return containedPath(cs.rootDir, meta.To, meta.ID+".blob")
}

func (cs *directMediaBlobCustodyStore) markerPath(meta *directMediaBlobCustodyMeta) (string, error) {
	return containedPath(cs.rootDir, meta.To, meta.ID+".custody")
}

func (cs *directMediaBlobCustodyStore) recipientDir(meta *directMediaBlobCustodyMeta) (string, error) {
	return containedPath(cs.rootDir, meta.To)
}

func (cs *directMediaBlobCustodyStore) reconcile() error {
	type diskFiles struct {
		blob   string
		marker string
	}
	filesByKey := make(map[string]*diskFiles)
	dirtyDirs := make(map[string]struct{})

	err := filepath.Walk(cs.rootDir, func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("media custody path is a symlink: %s", path)
		}
		if info.IsDir() {
			if path == cs.rootDir {
				return nil
			}
			rel, relErr := filepath.Rel(cs.rootDir, path)
			if relErr != nil || strings.Contains(rel, string(filepath.Separator)) {
				return fmt.Errorf("unexpected media custody directory: %s", path)
			}
			decoded, decodeErr := peer.Decode(rel)
			if decodeErr != nil || decoded.String() != rel {
				return fmt.Errorf("invalid media custody recipient directory: %s", path)
			}
			return nil
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("media custody artifact is not a regular file: %s", path)
		}

		base := filepath.Base(path)
		if mediaCustodyTempPattern.MatchString(base) {
			// Only our regular temp files directly beneath a validated recipient
			// directory are disposable. A matching name at the custody root (or
			// any special file) is unexpected state and must fail closed.
			if filepath.Dir(path) == cs.rootDir || !info.Mode().IsRegular() {
				return fmt.Errorf("unexpected media custody temp artifact: %s", path)
			}
			if err := cs.remove(path); err != nil && !os.IsNotExist(err) {
				return fmt.Errorf("remove media custody temp %s: %w", path, err)
			}
			dirtyDirs[filepath.Dir(path)] = struct{}{}
			return nil
		}
		ext := filepath.Ext(base)
		if ext != ".blob" && ext != ".custody" {
			return fmt.Errorf("unexpected media custody artifact: %s", path)
		}
		if filepath.Dir(path) == cs.rootDir {
			return fmt.Errorf("media custody final artifact is outside a recipient directory: %s", path)
		}
		id := strings.TrimSuffix(base, ext)
		if !mediaCustodyBlobIDPattern.MatchString(id) {
			return fmt.Errorf("invalid media custody artifact id: %s", path)
		}
		recipient := filepath.Base(filepath.Dir(path))
		key := recipient + "\x00" + id
		pair := filesByKey[key]
		if pair == nil {
			pair = &diskFiles{}
			filesByKey[key] = pair
		}
		if ext == ".blob" {
			pair.blob = path
		} else {
			pair.marker = path
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("reconcile media custody store: %w", err)
	}
	for dir := range dirtyDirs {
		if err := cs.syncDir(dir); err != nil {
			return fmt.Errorf("sync media custody temp cleanup: %w", err)
		}
	}

	for _, pair := range filesByKey {
		if pair.marker == "" {
			if pair.blob != "" {
				if err := cs.remove(pair.blob); err != nil && !os.IsNotExist(err) {
					return fmt.Errorf("remove uncommitted media custody blob %s: %w", pair.blob, err)
				}
				if err := cs.syncDir(filepath.Dir(pair.blob)); err != nil {
					return fmt.Errorf("sync uncommitted media custody cleanup: %w", err)
				}
			}
			continue
		}
		meta, err := readDirectMediaBlobCustodyMarker(pair.marker)
		if err != nil {
			return fmt.Errorf("read committed media custody marker %s: %w", pair.marker, err)
		}
		if err := cs.validateMarkerLocation(meta, pair.marker); err != nil {
			return err
		}
		if _, exists := cs.entries[meta.custodyKey()]; exists {
			return fmt.Errorf(
				"duplicate protected media custody row %q for recipient %q",
				meta.ID, meta.To,
			)
		}
		cs.owner.mu.RLock()
		legacyCollision := cs.owner.index[meta.ID] != nil
		cs.owner.mu.RUnlock()
		if legacyCollision {
			return fmt.Errorf("media id %q exists in both legacy and protected lanes", meta.ID)
		}

		nowMs := cs.now().UnixMilli()
		switch meta.State {
		case mediaCustodyStatePending:
			if pair.blob == "" {
				return fmt.Errorf("committed pending marker has no blob: %s", pair.marker)
			}
			if err := verifyMediaCustodyBlob(pair.blob, meta.Size, meta.ContentHash); err != nil {
				return fmt.Errorf("verify committed media custody blob: %w", err)
			}
			if nowMs >= meta.ExpiresAtMs {
				if err := cs.removeExpiredArtifactsLocked(meta, pair.blob != ""); err != nil {
					return fmt.Errorf("remove expired media custody entry: %w", err)
				}
				recordMediaCustodyOutcome(mediaCustodyMetricExpired)
				continue
			}
			cs.entries[meta.custodyKey()] = meta
		case mediaCustodyStateAcked:
			if pair.blob != "" {
				if err := cs.remove(pair.blob); err != nil && !os.IsNotExist(err) {
					return fmt.Errorf("retire ACKed media custody blob: %w", err)
				}
				if err := cs.syncDir(filepath.Dir(pair.blob)); err != nil {
					return fmt.Errorf("sync ACKed media custody cleanup: %w", err)
				}
			}
			if nowMs >= meta.ExpiresAtMs {
				if err := cs.remove(pair.marker); err != nil && !os.IsNotExist(err) {
					return fmt.Errorf("remove expired ACK tombstone: %w", err)
				}
				if err := cs.syncDir(filepath.Dir(pair.marker)); err != nil {
					return fmt.Errorf("sync expired ACK tombstone cleanup: %w", err)
				}
				recordMediaCustodyOutcome(mediaCustodyMetricExpired)
				continue
			}
			cs.entries[meta.custodyKey()] = meta
		default:
			return fmt.Errorf("invalid media custody state %q", meta.State)
		}
	}
	return nil
}

func readDirectMediaBlobCustodyMarker(path string) (*directMediaBlobCustodyMeta, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var meta directMediaBlobCustodyMeta
	if err := decoder.Decode(&meta); err != nil {
		return nil, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("trailing marker data")
	}
	return &meta, nil
}

func (cs *directMediaBlobCustodyStore) validateMarkerLocation(meta *directMediaBlobCustodyMeta, markerPath string) error {
	if meta == nil || meta.Schema != mediaCustodyMarkerSchema ||
		(meta.State != mediaCustodyStatePending && meta.State != mediaCustodyStateAcked) ||
		meta.CreatedAtMs <= 0 || meta.ExpiresAtMs != meta.CreatedAtMs+mediaTTL.Milliseconds() {
		return fmt.Errorf("invalid committed media custody marker")
	}
	req := &mediaRequest{
		ID:              meta.ID,
		To:              meta.To,
		Mime:            meta.Mime,
		Size:            meta.Size,
		ContentHash:     meta.ContentHash,
		CustodyKind:     meta.CustodyKind,
		CustodyContract: meta.CustodyContract,
	}
	if failure := validateDirectMediaBlobCustodyIdentity(req); failure != nil {
		return fmt.Errorf("invalid committed media custody identity: %s", failure.code)
	}
	want, err := cs.markerPath(meta)
	if err != nil || filepath.Clean(want) != filepath.Clean(markerPath) {
		return fmt.Errorf("media custody marker containment/location mismatch")
	}
	return nil
}

func verifyMediaCustodyBlob(path string, expectedSize int64, expectedHash string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	h := sha256.New()
	written, err := io.Copy(h, f)
	if err != nil {
		return err
	}
	if written != expectedSize {
		return fmt.Errorf("%w: size %d does not match %d", errMediaCustodyBlobIntegrity, written, expectedSize)
	}
	if hex.EncodeToString(h.Sum(nil)) != expectedHash {
		return fmt.Errorf("%w: content hash mismatch", errMediaCustodyBlobIntegrity)
	}
	return nil
}

func (ms *MediaStore) SetDirectMediaBlobCustodyAdmissionEnabled(enabled bool) {
	if ms == nil || ms.custody == nil {
		return
	}
	ms.custody.mu.Lock()
	ms.custody.admission = enabled
	ms.custody.mu.Unlock()
	setMediaCustodyAdmissionGauge(enabled)
}

func (ms *MediaStore) DirectMediaBlobCustodyAdmissionEnabled() bool {
	if ms == nil || ms.custody == nil {
		return false
	}
	ms.custody.mu.Lock()
	defer ms.custody.mu.Unlock()
	return ms.custody.admission
}

// SetDirectMediaBlobCustodyNowForTest supplies the deterministic clock used by
// strict upload, access-time expiry, and cleanup tests. Production never calls it.
func (ms *MediaStore) SetDirectMediaBlobCustodyNowForTest(now func() time.Time) {
	if ms == nil || ms.custody == nil || now == nil {
		return
	}
	ms.custody.mu.Lock()
	ms.custody.now = now
	ms.custody.mu.Unlock()
}

func (cs *directMediaBlobCustodyStore) refreshGaugesLocked() {
	var pending int
	var pendingBytes int64
	var tombstones int
	for key, meta := range cs.entries {
		switch meta.State {
		case mediaCustodyStatePending:
			pending++
			pendingBytes += meta.Size
		case mediaCustodyStateAcked:
			tombstones++
			if cs.ackCleanupPending[key] {
				pending++
				pendingBytes += meta.Size
			}
		}
	}
	// A post-rename durability/cleanup failure is not a custody proof, but its
	// artifact still consumes protected disk and identity capacity until an
	// access/sweep/restart reconciles it. Count it conservatively rather than
	// making the bytes operationally invisible and admitting past the cap.
	for _, meta := range cs.blocked {
		if meta != nil {
			pending++
			pendingBytes += meta.Size
		}
	}
	setMediaCustodyStateGauges(pending, pendingBytes, tombstones)
}

// protectedIDLocked answers the GLOBAL legacy/protected ID fence: the bare
// blob ID is owned by the protected lane while ANY recipient holds an entry,
// reservation or blocked row for it. A bounded scan of the composite keys is
// sufficient at the store's per-peer scale; no second index is kept.
func (cs *directMediaBlobCustodyStore) protectedIDLocked(id string) bool {
	for key := range cs.entries {
		if key.id == id {
			return true
		}
	}
	for key := range cs.reservations {
		if key.id == id {
			return true
		}
	}
	for key := range cs.blocked {
		if key.id == id {
			return true
		}
	}
	return false
}

func (ms *MediaStore) hasProtectedMediaID(id string) bool {
	if ms == nil || ms.custody == nil {
		return false
	}
	ms.laneMu.Lock()
	defer ms.laneMu.Unlock()
	ms.custody.mu.Lock()
	defer ms.custody.mu.Unlock()
	return ms.custody.protectedIDLocked(id)
}

func (ms *MediaStore) reserveLegacyMediaID(id string) error {
	ms.laneMu.Lock()
	defer ms.laneMu.Unlock()
	if ms.custody != nil {
		ms.custody.mu.Lock()
		protected := ms.custody.protectedIDLocked(id)
		ms.custody.mu.Unlock()
		if protected {
			return fmt.Errorf("media id is reserved by protected custody")
		}
	}
	ms.legacyReservations[id]++
	return nil
}

func (ms *MediaStore) releaseLegacyMediaID(id string) {
	ms.laneMu.Lock()
	defer ms.laneMu.Unlock()
	if ms.legacyReservations[id] <= 1 {
		delete(ms.legacyReservations, id)
		return
	}
	ms.legacyReservations[id]--
}

func (cs *directMediaBlobCustodyStore) prepareUpload(req *mediaRequest) (*mediaCustodyPrepareResult, *mediaCustodyFailure) {
	if failure := validateDirectMediaBlobCustodyIdentity(req); failure != nil {
		recordMediaCustodyOutcome(mediaCustodyMetricIneligible)
		return nil, failure
	}
	if req.ExpiresAtMs != 0 {
		recordMediaCustodyOutcome(mediaCustodyMetricIneligible)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorIneligible}
	}

	for {
		key := custodyKeyOf(req.To, req.ID)
		cs.owner.laneMu.Lock()
		cs.mu.Lock()
		if reservation := cs.reservations[key]; reservation != nil {
			done := reservation.done
			cs.mu.Unlock()
			cs.owner.laneMu.Unlock()
			<-done
			continue
		}
		if blocked := cs.blocked[key]; blocked != nil {
			if failure := cs.retryBlockedLocked(blocked); failure != nil {
				cs.mu.Unlock()
				cs.owner.laneMu.Unlock()
				return nil, failure
			}
		}
		if failure := cs.normalizeExpiredKeyLocked(key); failure != nil {
			cs.mu.Unlock()
			cs.owner.laneMu.Unlock()
			return nil, failure
		}
		if existing := cs.entries[key]; existing != nil {
			if !existing.matchesIdentity(req) {
				recordMediaCustodyOutcome(mediaCustodyMetricIdentityConflict)
				cs.mu.Unlock()
				cs.owner.laneMu.Unlock()
				return nil, &mediaCustodyFailure{code: mediaCustodyErrorIdentityConflict}
			}
			if existing.State == mediaCustodyStateAcked {
				// Re-upload remains terminal already_acked even if opportunistic
				// physical cleanup still needs the recipient to retry exact ACK.
				_ = cs.retryAckCleanupLocked(existing)
				cs.mu.Unlock()
				cs.owner.laneMu.Unlock()
				return nil, &mediaCustodyFailure{
					code:        mediaCustodyErrorAlreadyAcked,
					storeStatus: mediaCustodyStoreAlreadyAcked,
				}
			}
			blobPath, pathErr := cs.blobPath(existing)
			if pathErr != nil {
				cs.mu.Unlock()
				cs.owner.laneMu.Unlock()
				return nil, &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: pathErr}
			}
			if verifyErr := verifyMediaCustodyBlob(blobPath, existing.Size, existing.ContentHash); verifyErr != nil {
				if errors.Is(verifyErr, errMediaCustodyBlobIntegrity) {
					recordMediaCustodyOutcome(mediaCustodyMetricHashMismatch)
					cs.mu.Unlock()
					cs.owner.laneMu.Unlock()
					return nil, &mediaCustodyFailure{code: mediaCustodyErrorHashMismatch, cause: verifyErr}
				}
				recordMediaCustodyOutcome(mediaCustodyMetricCleanupPending)
				cs.mu.Unlock()
				cs.owner.laneMu.Unlock()
				return nil, &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: verifyErr}
			}
			recordMediaCustodyOutcome(mediaCustodyMetricDuplicate)
			result := &mediaCustodyPrepareResult{
				meta:        cloneDirectMediaBlobCustodyMeta(existing),
				storeStatus: mediaCustodyStoreDuplicate,
			}
			cs.mu.Unlock()
			cs.owner.laneMu.Unlock()
			return result, nil
		}

		cs.owner.mu.RLock()
		legacyCollision := cs.owner.index[req.ID] != nil || cs.owner.legacyReservations[req.ID] > 0
		cs.owner.mu.RUnlock()
		if legacyCollision {
			recordMediaCustodyOutcome(mediaCustodyMetricIdentityConflict)
			cs.mu.Unlock()
			cs.owner.laneMu.Unlock()
			return nil, &mediaCustodyFailure{code: mediaCustodyErrorIdentityConflict}
		}
		if !cs.admission {
			recordMediaCustodyOutcome(mediaCustodyMetricDisabled)
			cs.mu.Unlock()
			cs.owner.laneMu.Unlock()
			return nil, &mediaCustodyFailure{
				code:        mediaCustodyErrorAdmissionOff,
				storeStatus: mediaCustodyStoreDisabled,
			}
		}
		if failure := cs.normalizeExpiredPeerLocked(req.To); failure != nil {
			cs.mu.Unlock()
			cs.owner.laneMu.Unlock()
			return nil, failure
		}
		if !cs.hasCapacityLocked(req.To, req.Size) {
			recordMediaCustodyOutcome(mediaCustodyMetricRejectedFull)
			cs.mu.Unlock()
			cs.owner.laneMu.Unlock()
			return nil, &mediaCustodyFailure{
				code:        mediaCustodyErrorFull,
				storeStatus: mediaCustodyStoreRejectedFull,
			}
		}

		meta := &directMediaBlobCustodyMeta{
			Schema:          mediaCustodyMarkerSchema,
			State:           mediaCustodyStatePending,
			ID:              req.ID,
			To:              req.To,
			Mime:            req.Mime,
			Size:            req.Size,
			ContentHash:     req.ContentHash,
			CustodyKind:     req.CustodyKind,
			CustodyContract: req.CustodyContract,
			// The custody clock starts only after the complete body has been
			// hashed and accepted for commit, never while a slow sender is still
			// transferring under READY.
			CreatedAtMs: 0,
			ExpiresAtMs: 0,
		}
		reservation := &mediaCustodyReservation{meta: meta, done: make(chan struct{})}
		cs.reservations[key] = reservation
		cs.mu.Unlock()
		cs.owner.laneMu.Unlock()

		dir, err := cs.recipientDir(meta)
		if err != nil {
			cs.abortReservation(reservation)
			return nil, &mediaCustodyFailure{code: mediaCustodyErrorIneligible, cause: err}
		}
		created, err := ensureMediaCustodyDirectory(dir)
		if err != nil {
			cs.abortReservation(reservation)
			return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
		}
		if created {
			if err := cs.syncDir(cs.rootDir); err != nil {
				cs.abortReservation(reservation)
				return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
			}
		}
		return &mediaCustodyPrepareResult{
			meta:        cloneDirectMediaBlobCustodyMeta(meta),
			reservation: reservation,
		}, nil
	}
}

func (cs *directMediaBlobCustodyStore) hasCapacityLocked(to string, size int64) bool {
	count := 0
	var bytes int64
	for key, meta := range cs.entries {
		if meta.To != to {
			continue
		}
		count++
		if meta.State == mediaCustodyStatePending || cs.ackCleanupPending[key] {
			bytes += meta.Size
		}
	}
	for _, reservation := range cs.reservations {
		if reservation.meta.To == to {
			count++
			bytes += reservation.meta.Size
		}
	}
	for _, meta := range cs.blocked {
		if meta != nil && meta.To == to {
			count++
			bytes += meta.Size
		}
	}
	return count < cs.maxCount && size <= cs.maxBytes-bytes
}

func (cs *directMediaBlobCustodyStore) abortReservation(reservation *mediaCustodyReservation) {
	if reservation == nil {
		return
	}
	cs.mu.Lock()
	defer cs.mu.Unlock()
	key := reservation.meta.custodyKey()
	if cs.reservations[key] != reservation {
		return
	}
	delete(cs.reservations, key)
	close(reservation.done)
}

func (cs *directMediaBlobCustodyStore) finishReservation(reservation *mediaCustodyReservation, publish bool) {
	cs.mu.Lock()
	defer cs.mu.Unlock()
	key := reservation.meta.custodyKey()
	if cs.reservations[key] != reservation {
		return
	}
	if publish {
		cs.entries[key] = cloneDirectMediaBlobCustodyMeta(reservation.meta)
	}
	delete(cs.reservations, key)
	close(reservation.done)
	cs.refreshGaugesLocked()
}

func (cs *directMediaBlobCustodyStore) commitUpload(reservation *mediaCustodyReservation, reader io.Reader) (*directMediaBlobCustodyMeta, *mediaCustodyFailure) {
	if reservation == nil || reader == nil {
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage}
	}
	meta := reservation.meta
	dir, err := cs.recipientDir(meta)
	if err != nil {
		cs.abortReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}
	blobPath, err := cs.blobPath(meta)
	if err != nil {
		cs.abortReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}
	markerPath, err := cs.markerPath(meta)
	if err != nil {
		cs.abortReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}

	blobTemp, err := os.CreateTemp(dir, "."+meta.ID+".blob-*.tmp")
	if err != nil {
		cs.abortReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}
	blobTempPath := blobTemp.Name()
	hasher := sha256.New()
	written, copyErr := io.CopyN(io.MultiWriter(blobTemp, hasher), reader, meta.Size)
	if copyErr == nil {
		copyErr = blobTemp.Sync()
	}
	closeErr := blobTemp.Close()
	if copyErr == nil {
		copyErr = closeErr
	}
	if copyErr != nil || written != meta.Size {
		_ = cs.remove(blobTempPath)
		cs.abortReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: fmt.Errorf("incomplete body %d/%d: %w", written, meta.Size, copyErr)}
	}
	if actualHash := hex.EncodeToString(hasher.Sum(nil)); actualHash != meta.ContentHash {
		_ = cs.remove(blobTempPath)
		cs.abortReservation(reservation)
		recordMediaCustodyOutcome(mediaCustodyMetricHashMismatch)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorHashMismatch}
	}
	// Acceptance begins only after the declared bytes are complete and their
	// exact ciphertext hash is verified. This prevents a slow transfer from
	// receiving a success proof whose lifetime already elapsed under READY.
	nowMs := cs.now().UnixMilli()
	meta.CreatedAtMs = nowMs
	meta.ExpiresAtMs = nowMs + mediaTTL.Milliseconds()

	markerTempPath, err := cs.writeMarkerTemp(meta, dir)
	if err != nil {
		_ = cs.remove(blobTempPath)
		cs.abortReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}
	cleanupTemps := func() {
		_ = cs.remove(blobTempPath)
		_ = cs.remove(markerTempPath)
	}
	if err := cs.rename(blobTempPath, blobPath); err != nil {
		cleanupTemps()
		cs.abortReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}
	if err := cs.syncDir(dir); err != nil {
		cleanupTemps()
		if removeErr := cs.remove(blobPath); removeErr != nil && !os.IsNotExist(removeErr) {
			cs.blockReservation(reservation)
			return nil, &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: removeErr}
		}
		if syncErr := cs.syncDir(dir); syncErr != nil {
			cs.blockReservation(reservation)
			return nil, &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: syncErr}
		}
		cs.abortReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}
	if err := cs.rename(markerTempPath, markerPath); err != nil {
		cleanupTemps()
		if removeErr := cs.remove(blobPath); removeErr != nil && !os.IsNotExist(removeErr) {
			cs.blockReservation(reservation)
			return nil, &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: removeErr}
		}
		if syncErr := cs.syncDir(dir); syncErr != nil {
			cs.blockReservation(reservation)
			return nil, &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: syncErr}
		}
		cs.abortReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}
	if err := cs.syncDir(dir); err != nil {
		cs.blockReservation(reservation)
		return nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}

	cs.finishReservation(reservation, true)
	recordMediaCustodyOutcome(mediaCustodyMetricStored)
	return cloneDirectMediaBlobCustodyMeta(meta), nil
}

func (cs *directMediaBlobCustodyStore) blockReservation(reservation *mediaCustodyReservation) {
	cs.mu.Lock()
	defer cs.mu.Unlock()
	key := reservation.meta.custodyKey()
	if cs.reservations[key] == reservation {
		delete(cs.reservations, key)
		cs.blocked[key] = cloneDirectMediaBlobCustodyMeta(reservation.meta)
		close(reservation.done)
		cs.refreshGaugesLocked()
		recordMediaCustodyOutcome(mediaCustodyMetricCleanupPending)
	}
}

func (cs *directMediaBlobCustodyStore) writeMarkerTemp(meta *directMediaBlobCustodyMeta, dir string) (string, error) {
	data, err := json.Marshal(meta)
	if err != nil {
		return "", err
	}
	f, err := os.CreateTemp(dir, "."+meta.ID+".marker-*.tmp")
	if err != nil {
		return "", err
	}
	path := f.Name()
	if _, err := f.Write(data); err != nil {
		f.Close()
		_ = cs.remove(path)
		return "", err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		_ = cs.remove(path)
		return "", err
	}
	if err := f.Close(); err != nil {
		_ = cs.remove(path)
		return "", err
	}
	return path, nil
}

// retryBlockedLocked resolves a post-rename durability/cleanup ambiguity while
// the lane and custody locks are held. A complete marker+blob pair is made
// durable and published; a pre-marker blob is durably discarded. Anything
// unreadable or structurally impossible remains fail-closed for restart or
// operator repair.
func (cs *directMediaBlobCustodyStore) retryBlockedLocked(blocked *directMediaBlobCustodyMeta) *mediaCustodyFailure {
	if blocked == nil {
		return nil
	}
	dir, err := cs.recipientDir(blocked)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	blobPath, err := cs.blobPath(blocked)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	markerPath, err := cs.markerPath(blocked)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	markerExists, err := mediaCustodyArtifactExists(markerPath)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	blobExists, err := mediaCustodyArtifactExists(blobPath)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}

	if markerExists {
		committed, readErr := readDirectMediaBlobCustodyMarker(markerPath)
		if readErr != nil {
			return cs.cleanupPendingFailure(readErr)
		}
		if locationErr := cs.validateMarkerLocation(committed, markerPath); locationErr != nil {
			return cs.cleanupPendingFailure(locationErr)
		}
		if committed.State != mediaCustodyStatePending || *committed != *blocked || !blobExists {
			return cs.cleanupPendingFailure(fmt.Errorf("blocked media custody pair is inconsistent"))
		}
		if verifyErr := verifyMediaCustodyBlob(blobPath, committed.Size, committed.ContentHash); verifyErr != nil {
			return cs.cleanupPendingFailure(verifyErr)
		}
		if syncErr := cs.syncDir(dir); syncErr != nil {
			return cs.cleanupPendingFailure(syncErr)
		}
		cs.entries[committed.custodyKey()] = committed
		delete(cs.blocked, committed.custodyKey())
		cs.refreshGaugesLocked()
		return nil
	}

	if blobExists {
		if removeErr := cs.remove(blobPath); removeErr != nil && !os.IsNotExist(removeErr) {
			return cs.cleanupPendingFailure(removeErr)
		}
	}
	// Sync even when the path is currently absent: a previous attempt may have
	// unlinked it but failed the directory durability barrier.
	if syncErr := cs.syncDir(dir); syncErr != nil {
		return cs.cleanupPendingFailure(syncErr)
	}
	delete(cs.blocked, blocked.custodyKey())
	cs.refreshGaugesLocked()
	return nil
}

func (cs *directMediaBlobCustodyStore) cleanupPendingFailure(err error) *mediaCustodyFailure {
	recordMediaCustodyOutcome(mediaCustodyMetricCleanupPending)
	return &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: err}
}

// retryAckCleanupLocked completes an ACK whose marker/blob directory barrier
// was previously indeterminate. The ACKed marker remains the authority fence;
// bytes stay capacity-accounted until this method verifies that marker, removes
// any leftover blob, and durably syncs the directory.
func (cs *directMediaBlobCustodyStore) retryAckCleanupLocked(meta *directMediaBlobCustodyMeta) *mediaCustodyFailure {
	if meta == nil || !cs.ackCleanupPending[meta.custodyKey()] {
		return nil
	}
	dir, err := cs.recipientDir(meta)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	markerPath, err := cs.markerPath(meta)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	markerExists, err := mediaCustodyArtifactExists(markerPath)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	if !markerExists {
		return cs.cleanupPendingFailure(fmt.Errorf("ACK tombstone is missing"))
	}
	committed, err := readDirectMediaBlobCustodyMarker(markerPath)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	if err := cs.validateMarkerLocation(committed, markerPath); err != nil {
		return cs.cleanupPendingFailure(err)
	}
	if committed.State != mediaCustodyStateAcked || *committed != *meta {
		return cs.cleanupPendingFailure(fmt.Errorf("ACK tombstone does not match protected identity"))
	}
	blobPath, err := cs.blobPath(meta)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	blobExists, err := mediaCustodyArtifactExists(blobPath)
	if err != nil {
		return cs.cleanupPendingFailure(err)
	}
	if blobExists {
		if err := cs.remove(blobPath); err != nil && !os.IsNotExist(err) {
			return cs.cleanupPendingFailure(err)
		}
	}
	// This one barrier makes both a previous tombstone rename and any blob
	// unlink durable, even when the blob is already absent in this process.
	if err := cs.syncDir(dir); err != nil {
		return cs.cleanupPendingFailure(err)
	}
	delete(cs.ackCleanupPending, meta.custodyKey())
	cs.refreshGaugesLocked()
	return nil
}

func (cs *directMediaBlobCustodyStore) openDownload(req *mediaRequest, remotePeer string) (*directMediaBlobCustodyMeta, *os.File, *mediaCustodyFailure) {
	if failure := validateDirectMediaBlobCustodyExactRequest(req); failure != nil {
		return nil, nil, failure
	}
	if req.To != remotePeer {
		return nil, nil, &mediaCustodyFailure{code: mediaCustodyErrorNotAuthorized}
	}
	key := custodyKeyOf(req.To, req.ID)
	cs.owner.laneMu.Lock()
	defer cs.owner.laneMu.Unlock()
	cs.mu.Lock()
	defer cs.mu.Unlock()
	if blocked := cs.blocked[key]; blocked != nil {
		if failure := cs.retryBlockedLocked(blocked); failure != nil {
			return nil, nil, failure
		}
	}
	if failure := cs.normalizeExpiredKeyLocked(key); failure != nil {
		return nil, nil, failure
	}
	meta := cs.entries[key]
	if meta != nil && meta.State == mediaCustodyStateAcked {
		if failure := cs.retryAckCleanupLocked(meta); failure != nil {
			return nil, nil, failure
		}
	}
	if meta == nil || meta.State != mediaCustodyStatePending {
		return nil, nil, &mediaCustodyFailure{code: mediaCustodyErrorNotFound}
	}
	if !meta.matchesExact(req) {
		recordMediaCustodyOutcome(mediaCustodyMetricIdentityConflict)
		return nil, nil, &mediaCustodyFailure{code: mediaCustodyErrorIdentityConflict}
	}
	path, err := cs.blobPath(meta)
	if err != nil {
		return nil, nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}
	if err := verifyMediaCustodyBlob(path, meta.Size, meta.ContentHash); err != nil {
		if errors.Is(err, errMediaCustodyBlobIntegrity) {
			recordMediaCustodyOutcome(mediaCustodyMetricHashMismatch)
			return nil, nil, &mediaCustodyFailure{code: mediaCustodyErrorHashMismatch, cause: err}
		}
		recordMediaCustodyOutcome(mediaCustodyMetricCleanupPending)
		return nil, nil, &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: err}
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, nil, &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
	}
	return cloneDirectMediaBlobCustodyMeta(meta), f, nil
}

func (cs *directMediaBlobCustodyStore) ack(req *mediaRequest, remotePeer string) (*directMediaBlobCustodyMeta, string, *mediaCustodyFailure) {
	if failure := validateDirectMediaBlobCustodyExactRequest(req); failure != nil {
		return nil, "", failure
	}
	if req.To != remotePeer {
		return nil, "", &mediaCustodyFailure{code: mediaCustodyErrorNotAuthorized}
	}
	key := custodyKeyOf(req.To, req.ID)
	cs.owner.laneMu.Lock()
	defer cs.owner.laneMu.Unlock()
	cs.mu.Lock()
	defer cs.mu.Unlock()
	if blocked := cs.blocked[key]; blocked != nil {
		if failure := cs.retryBlockedLocked(blocked); failure != nil {
			return nil, "", failure
		}
	}
	if failure := cs.normalizeExpiredKeyLocked(key); failure != nil {
		return nil, "", failure
	}
	meta := cs.entries[key]
	if meta == nil {
		return nil, "", &mediaCustodyFailure{code: mediaCustodyErrorNotFound}
	}
	if !meta.matchesExact(req) {
		recordMediaCustodyOutcome(mediaCustodyMetricIdentityConflict)
		return nil, "", &mediaCustodyFailure{code: mediaCustodyErrorIdentityConflict}
	}
	if meta.State == mediaCustodyStateAcked {
		if failure := cs.retryAckCleanupLocked(meta); failure != nil {
			return nil, "", failure
		}
	}

	ackStatus := mediaCustodyAckAlreadyAcked
	if meta.State == mediaCustodyStatePending {
		acked := cloneDirectMediaBlobCustodyMeta(meta)
		acked.State = mediaCustodyStateAcked
		dir, err := cs.recipientDir(acked)
		if err != nil {
			return nil, "", &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
		}
		markerTemp, err := cs.writeMarkerTemp(acked, dir)
		if err != nil {
			return nil, "", &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
		}
		markerPath, _ := cs.markerPath(acked)
		if err := cs.rename(markerTemp, markerPath); err != nil {
			_ = cs.remove(markerTemp)
			return nil, "", &mediaCustodyFailure{code: mediaCustodyErrorStorage, cause: err}
		}
		if err := cs.syncDir(dir); err != nil {
			cs.entries[acked.custodyKey()] = acked
			cs.ackCleanupPending[acked.custodyKey()] = true
			cs.refreshGaugesLocked()
			recordMediaCustodyOutcome(mediaCustodyMetricCleanupPending)
			return nil, "", &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: err}
		}
		cs.entries[acked.custodyKey()] = acked
		cs.ackCleanupPending[acked.custodyKey()] = true
		meta = acked
		ackStatus = mediaCustodyAckAcked
		cs.refreshGaugesLocked()
	}

	blobPath, _ := cs.blobPath(meta)
	dir, _ := cs.recipientDir(meta)
	cs.ackCleanupPending[meta.custodyKey()] = true
	cs.refreshGaugesLocked()
	if err := cs.remove(blobPath); err != nil && !os.IsNotExist(err) {
		recordMediaCustodyOutcome(mediaCustodyMetricCleanupPending)
		return nil, "", &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: err}
	}
	if err := cs.syncDir(dir); err != nil {
		recordMediaCustodyOutcome(mediaCustodyMetricCleanupPending)
		return nil, "", &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: err}
	}
	delete(cs.ackCleanupPending, meta.custodyKey())
	cs.refreshGaugesLocked()
	if ackStatus == mediaCustodyAckAcked {
		recordMediaCustodyOutcome(mediaCustodyMetricAcked)
	} else {
		recordMediaCustodyOutcome(mediaCustodyMetricAlreadyAcked)
	}
	return cloneDirectMediaBlobCustodyMeta(meta), ackStatus, nil
}

func (cs *directMediaBlobCustodyStore) normalizeExpiredKeyLocked(key directMediaBlobCustodyKey) *mediaCustodyFailure {
	meta := cs.entries[key]
	if meta == nil || cs.now().UnixMilli() < meta.ExpiresAtMs {
		return nil
	}
	if meta.State == mediaCustodyStateAcked {
		if failure := cs.retryAckCleanupLocked(meta); failure != nil {
			return failure
		}
	}
	blobPath, _ := cs.blobPath(meta)
	hasBlob, presenceErr := mediaCustodyArtifactExists(blobPath)
	if presenceErr != nil {
		recordMediaCustodyOutcome(mediaCustodyMetricCleanupPending)
		return &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: presenceErr}
	}
	if err := cs.removeExpiredArtifactsLocked(meta, hasBlob); err != nil {
		recordMediaCustodyOutcome(mediaCustodyMetricCleanupPending)
		return &mediaCustodyFailure{code: mediaCustodyErrorCleanupPending, cause: err}
	}
	delete(cs.entries, key)
	delete(cs.ackCleanupPending, key)
	cs.refreshGaugesLocked()
	recordMediaCustodyOutcome(mediaCustodyMetricExpired)
	return nil
}

func (cs *directMediaBlobCustodyStore) normalizeExpiredPeerLocked(to string) *mediaCustodyFailure {
	// A previous post-rename failure still consumes identity, count, and bytes.
	// Resolve it before deciding that the peer is full; otherwise a recoverable
	// ambiguous commit can strand capacity until the periodic sweep or restart.
	blockedKeys := make([]directMediaBlobCustodyKey, 0)
	for key, meta := range cs.blocked {
		if meta != nil && meta.To == to {
			blockedKeys = append(blockedKeys, key)
		}
	}
	for _, key := range blockedKeys {
		if blocked := cs.blocked[key]; blocked != nil {
			if failure := cs.retryBlockedLocked(blocked); failure != nil {
				return failure
			}
		}
	}
	ackCleanupKeys := make([]directMediaBlobCustodyKey, 0)
	for key := range cs.ackCleanupPending {
		if meta := cs.entries[key]; meta != nil && meta.To == to {
			ackCleanupKeys = append(ackCleanupKeys, key)
		}
	}
	for _, key := range ackCleanupKeys {
		if meta := cs.entries[key]; meta != nil {
			if failure := cs.retryAckCleanupLocked(meta); failure != nil {
				return failure
			}
		}
	}

	nowMs := cs.now().UnixMilli()
	keys := make([]directMediaBlobCustodyKey, 0)
	for key, meta := range cs.entries {
		if meta != nil && meta.To == to && nowMs >= meta.ExpiresAtMs {
			keys = append(keys, key)
		}
	}
	for _, key := range keys {
		if failure := cs.normalizeExpiredKeyLocked(key); failure != nil {
			return failure
		}
	}
	return nil
}

func (cs *directMediaBlobCustodyStore) removeExpiredArtifactsLocked(meta *directMediaBlobCustodyMeta, hasBlob bool) error {
	dir, err := cs.recipientDir(meta)
	if err != nil {
		return err
	}
	blobPath, _ := cs.blobPath(meta)
	markerPath, _ := cs.markerPath(meta)
	if meta.State == mediaCustodyStateAcked && hasBlob {
		if err := cs.remove(blobPath); err != nil && !os.IsNotExist(err) {
			return err
		}
		if err := cs.syncDir(dir); err != nil {
			return err
		}
	}
	if err := cs.remove(markerPath); err != nil && !os.IsNotExist(err) {
		return err
	}
	if err := cs.syncDir(dir); err != nil {
		return err
	}
	if meta.State == mediaCustodyStatePending && hasBlob {
		if err := cs.remove(blobPath); err != nil && !os.IsNotExist(err) {
			return err
		}
		if err := cs.syncDir(dir); err != nil {
			return err
		}
	}
	return nil
}

func mediaCustodyArtifactExists(path string) (bool, error) {
	info, err := os.Lstat(path)
	if os.IsNotExist(err) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return false, fmt.Errorf("media custody artifact is not a regular file: %s", path)
	}
	return true, nil
}

func fileExists(path string) bool {
	exists, err := mediaCustodyArtifactExists(path)
	return err == nil && exists
}

func (cs *directMediaBlobCustodyStore) cleanupExpired() {
	cs.owner.laneMu.Lock()
	defer cs.owner.laneMu.Unlock()
	cs.mu.Lock()
	defer cs.mu.Unlock()
	blockedKeys := make([]directMediaBlobCustodyKey, 0, len(cs.blocked))
	for key := range cs.blocked {
		blockedKeys = append(blockedKeys, key)
	}
	for _, key := range blockedKeys {
		if blocked := cs.blocked[key]; blocked != nil {
			_ = cs.retryBlockedLocked(blocked)
		}
	}
	ackCleanupKeys := make([]directMediaBlobCustodyKey, 0, len(cs.ackCleanupPending))
	for key := range cs.ackCleanupPending {
		ackCleanupKeys = append(ackCleanupKeys, key)
	}
	for _, key := range ackCleanupKeys {
		if meta := cs.entries[key]; meta != nil {
			_ = cs.retryAckCleanupLocked(meta)
		}
	}
	keys := make([]directMediaBlobCustodyKey, 0, len(cs.entries))
	for key := range cs.entries {
		keys = append(keys, key)
	}
	for _, key := range keys {
		_ = cs.normalizeExpiredKeyLocked(key)
	}
}

func hasDirectMediaBlobCustodyFields(req *mediaRequest) bool {
	return req != nil && (req.CustodyKind != "" || req.CustodyContract != "" ||
		req.ContentHash != "" || req.ExpiresAtMs != 0)
}

func directMediaBlobCustodyResponse(
	meta *directMediaBlobCustodyMeta,
	storeStatus string,
	ackStatus string,
) mediaResponse {
	if meta == nil {
		return mediaResponse{Status: "ERROR"}
	}
	return mediaResponse{
		Status:          "OK",
		ID:              meta.ID,
		Mime:            meta.Mime,
		Size:            meta.Size,
		StoreStatus:     storeStatus,
		AckStatus:       ackStatus,
		CustodyKind:     meta.CustodyKind,
		CustodyContract: meta.CustodyContract,
		ContentHash:     meta.ContentHash,
		ExpiresAtMs:     meta.ExpiresAtMs,
	}
}

func writeDirectMediaBlobCustodyFailure(s io.Writer, failure *mediaCustodyFailure) {
	if failure == nil {
		failure = &mediaCustodyFailure{code: mediaCustodyErrorStorage}
	}
	if failure.code == mediaCustodyErrorStorage {
		recordMediaCustodyOutcome(mediaCustodyMetricFailed)
	}
	writeMediaResponse(s, mediaResponse{
		Status:      "ERROR",
		Error:       failure.code,
		ErrorCode:   failure.code,
		StoreStatus: failure.storeStatus,
		AckStatus:   failure.ackStatus,
	})
}

func handleDirectMediaBlobCustodyUpload(
	s io.ReadWriter,
	media *MediaStore,
	_ string,
	req *mediaRequest,
) {
	if media == nil || media.custody == nil {
		writeDirectMediaBlobCustodyFailure(s, &mediaCustodyFailure{code: mediaCustodyErrorStorage})
		return
	}
	prepared, failure := media.custody.prepareUpload(req)
	if failure != nil {
		writeDirectMediaBlobCustodyFailure(s, failure)
		return
	}
	if prepared.storeStatus == mediaCustodyStoreDuplicate {
		writeMediaResponse(s, directMediaBlobCustodyResponse(
			prepared.meta,
			mediaCustodyStoreDuplicate,
			"",
		))
		return
	}

	// READY only authorizes the declared body transfer. It is deliberately not
	// a custody proof; the final exact response follows both directory barriers.
	writeMediaResponse(s, mediaResponse{Status: "READY"})
	meta, failure := media.custody.commitUpload(prepared.reservation, s)
	if failure != nil {
		writeDirectMediaBlobCustodyFailure(s, failure)
		return
	}
	mediaUploadedCounter.Inc()
	mediaUploadedBytesCounter.Add(float64(meta.Size))
	if biz != nil {
		biz.RecordMediaUploaded()
	}
	writeMediaResponse(s, directMediaBlobCustodyResponse(meta, mediaCustodyStoreStored, ""))
	log.Printf("[MEDIA_CUSTODY] stored blob %s (%d bytes) for %s",
		meta.ID, meta.Size, shortPeerIdString(meta.To))
}

func handleDirectMediaBlobCustodyDownload(
	s io.ReadWriter,
	media *MediaStore,
	remotePeer string,
	req *mediaRequest,
) {
	if media == nil || media.custody == nil {
		writeDirectMediaBlobCustodyFailure(s, &mediaCustodyFailure{code: mediaCustodyErrorStorage})
		return
	}
	if req.To != "" && req.To != remotePeer {
		writeDirectMediaBlobCustodyFailure(s, &mediaCustodyFailure{code: mediaCustodyErrorNotAuthorized})
		return
	}
	exactReq := *req
	exactReq.To = remotePeer
	meta, f, failure := media.custody.openDownload(&exactReq, remotePeer)
	if failure != nil {
		writeDirectMediaBlobCustodyFailure(s, failure)
		return
	}
	defer f.Close()
	writeMediaResponse(s, directMediaBlobCustodyResponse(meta, "", ""))
	written, err := io.CopyN(s, f, meta.Size)
	if err != nil || written != meta.Size {
		log.Printf("[MEDIA_CUSTODY] strict download stream failed for %s: wrote %d/%d: %v",
			meta.ID, written, meta.Size, err)
		return
	}
	mediaDownloadedCounter.Inc()
	mediaDownloadedBytesCounter.Add(float64(written))
}

func handleDirectMediaBlobCustodyAck(
	s io.ReadWriter,
	media *MediaStore,
	remotePeer string,
	req *mediaRequest,
) {
	if media == nil || media.custody == nil {
		writeDirectMediaBlobCustodyFailure(s, &mediaCustodyFailure{code: mediaCustodyErrorStorage})
		return
	}
	if req.To != "" && req.To != remotePeer {
		writeDirectMediaBlobCustodyFailure(s, &mediaCustodyFailure{code: mediaCustodyErrorNotAuthorized})
		return
	}
	exactReq := *req
	exactReq.To = remotePeer
	meta, ackStatus, failure := media.custody.ack(&exactReq, remotePeer)
	if failure != nil {
		writeDirectMediaBlobCustodyFailure(s, failure)
		return
	}
	writeMediaResponse(s, directMediaBlobCustodyResponse(meta, "", ackStatus))
}

func shortPeerIdString(value string) string {
	if len(value) <= 20 {
		return value
	}
	return value[:20]
}
