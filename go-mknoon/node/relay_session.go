package node

import (
	"context"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
)

// --- Per-Relay Session State Machine ---

// RelayConnectionState represents the state of a single relay's reservation session.
type RelayConnectionState string

const (
	RelayStateDisconnected RelayConnectionState = "disconnected"
	RelayStateConnected    RelayConnectionState = "connected"
	RelayStateReserving    RelayConnectionState = "reserving"
	RelayStateReserved     RelayConnectionState = "reserved"
	RelayStateDegraded     RelayConnectionState = "degraded"
	RelayStateCooldown     RelayConnectionState = "cooldown"
)

// RelaySessionState represents one relay peer's session with reservation tracking.
type RelaySessionState struct {
	PeerID         peer.ID              `json:"peerId"`
	State          RelayConnectionState `json:"state"`
	LastReservedAt time.Time            `json:"lastReservedAt,omitempty"`
	LastErrorAt    time.Time            `json:"lastErrorAt,omitempty"`
	LastError      string               `json:"lastError,omitempty"`
	FailCount      int                  `json:"failCount"`

	// ConsecutiveRefreshFailures tracks how many consecutive relay refresh
	// attempts have failed. Reset to 0 on any successful refresh.
	// When this reaches WatchdogMaxConsecutiveFailures, the watchdog triggers.
	ConsecutiveRefreshFailures int `json:"consecutiveRefreshFailures"`

	// ManualReservationExpiry (plan 189 reservation-truth): while set and in
	// the future, this session's Reserved state was proven by an EXPLICIT
	// relayclient.Reserve success and must not be demoted just because no
	// /p2p-circuit address is advertised (in go-libp2p v0.39.1 only autorelay's
	// relayFinder publishes those, and only for public/DNS relay addrs).
	// Cleared on relay disconnect — the relay purges the slot with the conn.
	ManualReservationExpiry time.Time `json:"manualReservationExpiry,omitempty"`
}

// --- Aggregate Relay Session State ---

// AggregateRelayState summarizes the overall relay session health.
type AggregateRelayState string

const (
	AggregateRelayStarting        AggregateRelayState = "starting"
	AggregateRelayOnline          AggregateRelayState = "online"
	AggregateRelayRecovering      AggregateRelayState = "recovering"
	AggregateRelayWatchdogRestart AggregateRelayState = "watchdog_restart"
)

// WatchdogMaxConsecutiveFailures is the number of consecutive relay refresh
// failures that trigger a watchdog restart. After this threshold is crossed,
// the manager sets needsGroupRecovery and transitions to watchdog_restart.
const WatchdogMaxConsecutiveFailures = 5

// RecoveryWaitTimeout bounds the API wait for an owned recovery, measured from
// its start. Owners and joiners share this deadline. A timeout does not release
// mutation ownership: the native operation may still be stopping/replacing a host.
const RecoveryWaitTimeout = 30 * time.Second

// DefaultManualReservationHold bounds a manual-reservation hold when the
// Reserve response carries no expiration (plan 189). Conservative fraction of
// the circuit-v2 default reservation TTL (1h) so a stale hold cannot outlive
// the relay-side slot by much; a fresh hold is re-established by the next
// recovery attempt's explicit Reserve.
const DefaultManualReservationHold = 30 * time.Minute

// RelaySessionManager tracks per-relay reservation state and provides
// aggregate health without requiring a full host restart.
type RelaySessionManager struct {
	mu sync.RWMutex

	// Per-relay session state, keyed by peer ID string.
	sessions map[string]*RelaySessionState

	// Aggregate state computed from individual sessions.
	aggregateState AggregateRelayState

	// Singleflight gate for recovery — only one recovery runs at a time.
	recovering bool
	recovery   *recoveryPromise
	// recoveryWaitTimeout defaults to RecoveryWaitTimeout and is adjustable in
	// tests so timeout behavior can be proven without a 30s wall-clock wait.
	recoveryWaitTimeout time.Duration

	// Counts for diagnostics.
	watchdogRestartCount int

	// needsGroupRecovery is set to true when the watchdog triggers,
	// signalling to Flutter that group topics need rejoin.
	needsGroupRecovery bool

	// callMedia is the call-media protection lease (SE-42 D27 lease
	// contract). hostIncarnation moves on every Reset (Stop), so a release
	// from before it is a no-op; hostUp mirrors the node's started state;
	// fullRestartInProgress is set from a lane's decision to Stop/Start the
	// host until that Start returns, and refuses new leases meanwhile. All
	// four are decided under one lock, so a grant and a restart decision can
	// never both win.
	callMedia             callMediaLease
	hostIncarnation       uint64
	hostUp                bool
	fullRestartInProgress bool
}

// callMediaLease is the one holder of call-media protection: while held, no
// recovery lane may fall back to a full host Stop/Start. (generation,
// incarnation) identifies the holder exactly, so a late release from an
// earlier call, or from before a Stop, can never clear a successor.
type callMediaLease struct {
	held        bool
	generation  int64
	incarnation uint64
}

// Reasons a call-media protection acquire is refused.
const (
	CallMediaProtectionRestartInProgress = "restart_in_progress"
	CallMediaProtectionNotStarted        = "not_started"
	CallMediaProtectionSuperseded        = "superseded"
)

// CallMediaProtectionReply is the broker's answer to an acquire or a release.
// A grant carries the incarnation the release must echo.
type CallMediaProtectionReply struct {
	Held        bool
	Generation  int64
	Incarnation uint64
	Reason      string
	Released    bool
}

// RecoveryResult carries the structured result of a relay session refresh.
type RecoveryResult struct {
	RecoveryMode                 string `json:"recoveryMode"` // "in_place" or "watchdog_restart"
	Success                      bool   `json:"success"`
	ErrorCode                    string `json:"errorCode,omitempty"`
	Reason                       string `json:"reason,omitempty"`
	RelayState                   string `json:"relayState"`
	HealthyRelayCount            int    `json:"healthyRelayCount"`
	ReusedHost                   bool   `json:"reusedHost"`
	CoalescedRecoveryRequests    int    `json:"coalescedRecoveryRequests"`
	RelayRefreshMs               int64  `json:"relayRefreshMs"`
	RelayWarmMs                  int64  `json:"relayWarmMs"`
	ReserveRpcMs                 int64  `json:"reserveRpcMs"`
	RelayWarmParallelism         int    `json:"relayWarmParallelism,omitempty"`
	ForegroundRecoveryPath       string `json:"foregroundRecoveryPath,omitempty"`
	ForegroundRelayDialTimeoutMs int64  `json:"foregroundRelayDialTimeoutMs,omitempty"`
	AutorelayRetryCadenceMs      int64  `json:"autorelayRetryCadenceMs,omitempty"`
	CircuitAddressWaitMs         int64  `json:"circuitAddressWaitMs"`
	ReservationPath              string `json:"reservationPath,omitempty"`
	ReservationWinnerPeer        string `json:"reservationWinnerPeer,omitempty"`
	PersonalReregisterMs         int64  `json:"personalReregisterMs"`
}

type recoveryPromise struct {
	done             chan struct{}
	result           *RecoveryResult
	err              error
	deadline         time.Time
	coalescedWaiters int
	// ctx is cancelled when a newer network path supersedes this recovery. The
	// owner keeps ownership until its work really exits; cancellation only
	// tells the work to stop early and forbids the full-restart fallback.
	ctx    context.Context
	cancel context.CancelCauseFunc
}

// Context reports the cancellation signal for this recovery's owned work.
func (p *recoveryPromise) Context() context.Context {
	if p == nil || p.ctx == nil {
		return context.Background()
	}
	return p.ctx
}

// NewRelaySessionManager creates a new relay session manager.
func NewRelaySessionManager() *RelaySessionManager {
	return &RelaySessionManager{
		sessions:            make(map[string]*RelaySessionState),
		aggregateState:      AggregateRelayStarting,
		recoveryWaitTimeout: RecoveryWaitTimeout,
		// 1, so a release that omits the incarnation (0) never matches.
		hostIncarnation: 1,
	}
}

// GetSession returns the session state for a relay peer, or nil if not tracked.
func (m *RelaySessionManager) GetSession(peerID peer.ID) *RelaySessionState {
	m.mu.RLock()
	defer m.mu.RUnlock()
	s := m.sessions[peerID.String()]
	if s == nil {
		return nil
	}
	// Return a copy.
	copy := *s
	return &copy
}

// AggregateState returns the current aggregate relay health state.
func (m *RelaySessionManager) AggregateState() AggregateRelayState {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.aggregateState
}

// HealthyRelayCount returns how many relays are in the "reserved" state.
func (m *RelaySessionManager) HealthyRelayCount() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.healthyRelayCountLocked()
}

func (m *RelaySessionManager) healthyRelayCountLocked() int {
	count := 0
	for _, s := range m.sessions {
		if s.State == RelayStateReserved {
			count++
		}
	}
	return count
}

// AllSessions returns a copy of all relay session states.
func (m *RelaySessionManager) AllSessions() []RelaySessionState {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]RelaySessionState, 0, len(m.sessions))
	for _, s := range m.sessions {
		out = append(out, *s)
	}
	return out
}

// WatchdogRestartCount returns how many watchdog restarts have been performed.
func (m *RelaySessionManager) WatchdogRestartCount() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.watchdogRestartCount
}

// --- State Transitions (called from autorelay metrics tracer hooks) ---

// OnReservationOpened transitions a relay to the "reserved" state.
func (m *RelaySessionManager) OnReservationOpened(peerID peer.ID) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	s, ok := m.sessions[pidStr]
	if !ok {
		s = &RelaySessionState{PeerID: peerID, State: RelayStateDisconnected}
		m.sessions[pidStr] = s
	}

	s.State = RelayStateReserved
	s.LastReservedAt = time.Now()
	s.FailCount = 0
	s.LastError = ""

	log.Printf("[RELAY_SESSION] Reservation opened for %s", pidStr[:min(20, len(pidStr))])
	m.recomputeAggregateLocked()
}

// OnReservationEnded transitions a relay to "degraded" when the reservation ends.
func (m *RelaySessionManager) OnReservationEnded(peerID peer.ID) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	s, ok := m.sessions[pidStr]
	if !ok {
		s = &RelaySessionState{PeerID: peerID, State: RelayStateDisconnected}
		m.sessions[pidStr] = s
	}

	s.State = RelayStateDegraded
	s.LastErrorAt = time.Now()
	s.ManualReservationExpiry = time.Time{}

	log.Printf("[RELAY_SESSION] Reservation ended for %s", pidStr[:min(20, len(pidStr))])
	m.recomputeAggregateLocked()
}

// OnManualReservationOpened records a successful EXPLICIT relayclient.Reserve
// (plan 189 reservation-truth). The relay now holds a live slot for this node
// even if autorelay never advertises a /p2p-circuit address, so the session
// counts as reserved until the reservation's own expiration.
func (m *RelaySessionManager) OnManualReservationOpened(peerID peer.ID, expiration time.Time) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	s, ok := m.sessions[pidStr]
	if !ok {
		s = &RelaySessionState{PeerID: peerID, State: RelayStateDisconnected}
		m.sessions[pidStr] = s
	}

	if expiration.IsZero() {
		expiration = time.Now().Add(DefaultManualReservationHold)
	}
	s.State = RelayStateReserved
	s.LastReservedAt = time.Now()
	s.ManualReservationExpiry = expiration
	s.FailCount = 0
	s.LastError = ""

	log.Printf("[RELAY_SESSION] Manual reservation opened for %s (hold until %s)",
		pidStr[:min(20, len(pidStr))], expiration.Format(time.RFC3339))
	m.recomputeAggregateLocked()
}

// HasActiveManualReservation reports whether this relay session is reserved
// under a live manual-reservation hold (explicit Reserve, not yet expired).
func (m *RelaySessionManager) HasActiveManualReservation(peerID peer.ID) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()

	s := m.sessions[peerID.String()]
	return s != nil && s.State == RelayStateReserved &&
		!s.ManualReservationExpiry.IsZero() &&
		time.Now().Before(s.ManualReservationExpiry)
}

// OnRequestFailed records a reservation request failure without triggering host restart.
func (m *RelaySessionManager) OnRequestFailed(peerID peer.ID, err error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	s, ok := m.sessions[pidStr]
	if !ok {
		s = &RelaySessionState{PeerID: peerID, State: RelayStateDisconnected}
		m.sessions[pidStr] = s
	}

	s.FailCount++
	s.LastErrorAt = time.Now()
	if err != nil {
		s.LastError = err.Error()
	}

	// Do NOT set state to degraded on a single request failure —
	// AutoRelay will retry with its own backoff. Only move to degraded
	// if we were previously reserved and the reservation actually ended.
	if s.State == RelayStateReserving {
		s.State = RelayStateCooldown
	}

	log.Printf("[RELAY_SESSION] Request failed for %s (count=%d): %v",
		pidStr[:min(20, len(pidStr))], s.FailCount, err)
	m.recomputeAggregateLocked()
}

// OnRelayAddressUpdated notes that an address update came through.
// This is used to validate that circuit addresses match reservation state.
func (m *RelaySessionManager) OnRelayAddressUpdated(peerID peer.ID, hasCircuitAddr bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	s, ok := m.sessions[pidStr]
	if !ok {
		s = &RelaySessionState{PeerID: peerID, State: RelayStateDisconnected}
		m.sessions[pidStr] = s
	}

	// If we have a circuit address but no reservation, this is stale.
	// The reservation is the source of truth.
	if hasCircuitAddr && s.State != RelayStateReserved {
		log.Printf("[RELAY_SESSION] Ignoring stale circuit address for %s (state=%s)",
			pidStr[:min(20, len(pidStr))], s.State)
	}
}

// OnConnected marks a relay peer as connected (transport layer only, not reserved).
func (m *RelaySessionManager) OnConnected(peerID peer.ID) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	s, ok := m.sessions[pidStr]
	if !ok {
		s = &RelaySessionState{PeerID: peerID, State: RelayStateDisconnected}
		m.sessions[pidStr] = s
	}

	if s.State == RelayStateDisconnected {
		s.State = RelayStateConnected
	}
	m.recomputeAggregateLocked()
}

// OnDisconnected marks a relay peer as disconnected.
func (m *RelaySessionManager) OnDisconnected(peerID peer.ID) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	s, ok := m.sessions[pidStr]
	if !ok {
		return
	}

	s.State = RelayStateDegraded
	// 189: the relay purges its reservation slot with the connection, so a
	// manual-reservation hold must die here too.
	s.ManualReservationExpiry = time.Time{}
	m.recomputeAggregateLocked()
}

// --- Health Queries ---

// IsHealthy returns true if at least one relay has an active reservation
// and the node's reported connectedness is consistent.
func (m *RelaySessionManager) IsHealthy() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.aggregateState == AggregateRelayOnline
}

// HasReservation returns true if any relay is in "reserved" state.
func (m *RelaySessionManager) HasReservation() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	for _, s := range m.sessions {
		if s.State == RelayStateReserved {
			return true
		}
	}
	return false
}

// --- Recovery Coalescing ---

// BeginRecovery attempts to start a recovery operation. If one is already in
// progress, it returns the existing promise to wait on (singleflight pattern).
// Returns (promise, isNew). If isNew is true, the caller owns the recovery and
// must eventually call CompleteRecovery with the same promise.
func (m *RelaySessionManager) BeginRecovery() (*recoveryPromise, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.recovering {
		if m.recovery != nil {
			m.recovery.coalescedWaiters++
		}
		return m.recovery, false
	}

	m.recovering = true
	waitTimeout := m.recoveryWaitTimeout
	if waitTimeout <= 0 {
		waitTimeout = RecoveryWaitTimeout
	}
	ctx, cancel := context.WithCancelCause(context.Background())
	m.recovery = &recoveryPromise{done: make(chan struct{}), deadline: time.Now().Add(waitTimeout), ctx: ctx, cancel: cancel}
	m.aggregateState = AggregateRelayRecovering

	return m.recovery, true
}

// CancelRecovery asks the running recovery, if any, to stop early and returns
// its promise so the caller can wait for the owner to actually finish.
// Ownership is not released here; CompleteRecovery still does that.
func (m *RelaySessionManager) CancelRecovery(cause error) *recoveryPromise {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.recovering || m.recovery == nil {
		return nil
	}
	if m.recovery.cancel != nil {
		m.recovery.cancel(cause)
	}
	return m.recovery
}

// AcquireCallMediaProtection grants the lease to generation unless a full
// restart has been decided and its Start has not returned
// (restart_in_progress), the host is not up (not_started), or a newer
// generation holds it (superseded). A generation at least as new as the
// holder takes over. The answer is immediate; it never waits for a restart.
func (m *RelaySessionManager) AcquireCallMediaProtection(generation int64) CallMediaProtectionReply {
	m.mu.Lock()
	defer m.mu.Unlock()
	reply := CallMediaProtectionReply{Generation: generation}
	switch {
	case m.fullRestartInProgress:
		reply.Reason = CallMediaProtectionRestartInProgress
	case !m.hostUp:
		reply.Reason = CallMediaProtectionNotStarted
	case m.callMedia.held && m.callMedia.generation > generation:
		reply.Reason = CallMediaProtectionSuperseded
	default:
		m.callMedia = callMediaLease{held: true, generation: generation, incarnation: m.hostIncarnation}
		reply.Held, reply.Incarnation = true, m.hostIncarnation
	}
	return reply
}

// ReleaseCallMediaProtection clears the lease only when (generation,
// incarnation) is exactly the holder. A stale terminal callback, a late grant
// settled by a caller that timed out, or a release from before a Stop is a
// no-op and reports Released=false.
func (m *RelaySessionManager) ReleaseCallMediaProtection(generation int64, incarnation uint64) CallMediaProtectionReply {
	m.mu.Lock()
	defer m.mu.Unlock()
	reply := CallMediaProtectionReply{Generation: generation}
	if m.callMedia.held && m.callMedia.generation == generation && m.callMedia.incarnation == incarnation {
		m.callMedia = callMediaLease{}
		reply.Released = true
	}
	return reply
}

// CallMediaProtected reports whether a live call currently forbids a full
// host restart.
func (m *RelaySessionManager) CallMediaProtected() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.callMedia.held
}

// hostStarted opens lease admission for the host that just committed. Called
// from Start under the node lock.
func (m *RelaySessionManager) hostStarted() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.hostUp = true
}

// beginFullRestart is the one place a recovery lane decides to fall back to a
// full host Stop/Start. Under the broker lock it refuses when the work was
// cancelled or superseded by a newer network path, or when a live call holds
// protection; otherwise it marks the restart in progress, which makes every
// lease acquire answer restart_in_progress until endFullRestart. nil means
// go ahead.
func (m *RelaySessionManager) beginFullRestart(ctx context.Context, recovery *recoveryPromise) *RecoveryResult {
	m.mu.Lock()
	defer m.mu.Unlock()
	code, reason := "", ""
	switch {
	case ctx.Err() != nil || recovery.Context().Err() != nil:
		code, reason = "RECOVERY_SUPERSEDED", "recovery superseded by a newer network path; full restart skipped"
	case m.callMedia.held:
		code, reason = "CALL_MEDIA_PROTECTED", "a live call owns native media; full restart skipped"
	default:
		m.fullRestartInProgress = true
		return nil
	}
	return &RecoveryResult{
		RecoveryMode:      "in_place",
		Success:           false,
		ErrorCode:         code,
		Reason:            reason,
		ReusedHost:        true,
		RelayState:        string(m.aggregateState),
		HealthyRelayCount: m.healthyRelayCountLocked(),
	}
}

// endFullRestart reopens lease admission once the restart's Start returned.
func (m *RelaySessionManager) endFullRestart() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.fullRestartInProgress = false
}

// Wait blocks until the shared recovery completes and returns the final
// structured outcome to every waiter. If the recovery does not complete
// by its original deadline, returns a timeout error without allowing another
// owner to overlap the still-running native operation.
func (p *recoveryPromise) Wait() (*RecoveryResult, error) {
	if p == nil {
		return nil, nil
	}
	// Prefer an already completed outcome even when its deadline has elapsed.
	select {
	case <-p.done:
		return p.result, p.err
	default:
	}
	timer := time.NewTimer(time.Until(p.deadline))
	defer timer.Stop()
	select {
	case <-p.done:
		return p.result, p.err
	case <-timer.C:
		return &RecoveryResult{
			RecoveryMode: "timeout",
			ErrorCode:    "RECOVERY_TIMEOUT",
			Reason:       "relay recovery exceeded its shared deadline; native operation still owns recovery",
			RelayState:   string(AggregateRelayRecovering),
		}, fmt.Errorf("RECOVERY_TIMEOUT")
	}
}

// CompleteRecovery signals that recovery is done and publishes the result to
// all waiting callers.
func (m *RelaySessionManager) CompleteRecovery(recovery *recoveryPromise, result *RecoveryResult, err error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if recovery == nil || m.recovery != recovery {
		return
	}
	m.recovering = false
	if result != nil && recovery != nil {
		result.CoalescedRecoveryRequests = recovery.coalescedWaiters
	}
	if result != nil && result.RecoveryMode == "watchdog_restart" {
		m.watchdogRestartCount++
		m.needsGroupRecovery = true
	}
	m.recomputeAggregateLocked()
	m.recovery = nil
	recovery.result = result
	recovery.err = err
	if recovery.cancel != nil {
		recovery.cancel(nil)
	}
	close(recovery.done)
}

// IsRecovering returns whether a recovery is currently in progress.
func (m *RelaySessionManager) IsRecovering() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.recovering
}

// SetAggregateState overrides the aggregate state (for testing or manual control).
func (m *RelaySessionManager) SetAggregateState(state AggregateRelayState) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.aggregateState = state
}

// --- Internal ---

// recomputeAggregateLocked updates the aggregate state from per-relay states.
// Caller must hold m.mu write lock.
func (m *RelaySessionManager) recomputeAggregateLocked() {
	if m.recovering {
		m.aggregateState = AggregateRelayRecovering
		return
	}

	hasReserved := false
	allDegraded := true
	for _, s := range m.sessions {
		if s.State == RelayStateReserved {
			hasReserved = true
			allDegraded = false
		}
		if s.State != RelayStateDegraded && s.State != RelayStateDisconnected && s.State != RelayStateCooldown {
			allDegraded = false
		}
	}

	if hasReserved {
		m.aggregateState = AggregateRelayOnline
	} else if len(m.sessions) == 0 {
		m.aggregateState = AggregateRelayStarting
	} else if allDegraded {
		m.aggregateState = AggregateRelayRecovering
	} else {
		m.aggregateState = AggregateRelayStarting
	}
}

// StatusFields returns a map of relay-session fields suitable for merging
// into the node:status response. All fields are additive.
func (m *RelaySessionManager) StatusFields() map[string]interface{} {
	m.mu.RLock()
	defer m.mu.RUnlock()

	relayStates := make([]map[string]interface{}, 0, len(m.sessions))
	for _, s := range m.sessions {
		pidStr := s.PeerID.String()
		entry := map[string]interface{}{
			"peerId": pidStr,
			"state":  string(s.State),
		}
		if !s.LastReservedAt.IsZero() {
			entry["lastReservedAt"] = s.LastReservedAt.Format(time.RFC3339)
		}
		if s.LastError != "" {
			entry["lastError"] = s.LastError
		}
		relayStates = append(relayStates, entry)
	}

	healthyCount := 0
	for _, s := range m.sessions {
		if s.State == RelayStateReserved {
			healthyCount++
		}
	}

	var lastReservationAt string
	for _, s := range m.sessions {
		if s.State == RelayStateReserved && !s.LastReservedAt.IsZero() {
			if lastReservationAt == "" || s.LastReservedAt.Format(time.RFC3339) > lastReservationAt {
				lastReservationAt = s.LastReservedAt.Format(time.RFC3339)
			}
		}
	}

	result := map[string]interface{}{
		"relayState":           string(m.aggregateState),
		"relayStates":          relayStates,
		"healthyRelayCount":    healthyCount,
		"watchdogRestartCount": m.watchdogRestartCount,
		"needsGroupRecovery":   m.needsGroupRecovery,
	}

	if lastReservationAt != "" {
		result["lastReservationAt"] = lastReservationAt
	}

	return result
}

// --- Helpers used by node for circuit address validation ---

// CircuitAddressesAreStale returns true if there are circuit addresses in
// the host's address set but no relay has an active reservation.
func (m *RelaySessionManager) CircuitAddressesAreStale(hostAddrs []string) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()

	hasCircuit := false
	for _, addr := range hostAddrs {
		if strings.Contains(addr, "/p2p-circuit") {
			hasCircuit = true
			break
		}
	}

	if !hasCircuit {
		return false // No circuit addresses to be stale
	}

	for _, s := range m.sessions {
		if s.State == RelayStateReserved {
			return false // At least one reservation is active
		}
	}

	return true // Has circuit addresses but no reservation
}

// ReportsHealthyWithReservation returns true when at least one relay is
// reserved and the host reports circuit addresses — i.e., reservation truth
// and circuit addresses agree.
func (m *RelaySessionManager) ReportsHealthyWithReservation(hostAddrs []string) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()

	hasCircuit := false
	for _, addr := range hostAddrs {
		if strings.Contains(addr, "/p2p-circuit") {
			hasCircuit = true
			break
		}
	}

	hasReservation := false
	for _, s := range m.sessions {
		if s.State == RelayStateReserved {
			hasReservation = true
			break
		}
	}

	return hasCircuit && hasReservation
}

// --- Watchdog Policy ---

// OnRefreshFailed records a relay refresh failure and checks the watchdog threshold.
// When consecutive failures reach WatchdogMaxConsecutiveFailures, the watchdog
// triggers: needsGroupRecovery is set and the aggregate state becomes watchdog_restart.
func (m *RelaySessionManager) OnRefreshFailed(peerID peer.ID, err error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	s, ok := m.sessions[pidStr]
	if !ok {
		s = &RelaySessionState{PeerID: peerID, State: RelayStateDisconnected}
		m.sessions[pidStr] = s
	}

	s.ConsecutiveRefreshFailures++
	s.FailCount++
	s.LastErrorAt = time.Now()
	if err != nil {
		s.LastError = err.Error()
	}

	log.Printf("[RELAY_SESSION] Refresh failed for %s (consecutive=%d, total=%d): %v",
		pidStr[:min(20, len(pidStr))], s.ConsecutiveRefreshFailures, s.FailCount, err)

	// Check if ALL tracked relays have exceeded the watchdog threshold.
	allExceeded := true
	for _, sess := range m.sessions {
		if sess.ConsecutiveRefreshFailures < WatchdogMaxConsecutiveFailures &&
			sess.State == RelayStateReserved {
			allExceeded = false
			break
		}
	}

	// Only trigger watchdog if ALL relays are failing.
	if s.ConsecutiveRefreshFailures >= WatchdogMaxConsecutiveFailures && allExceeded {
		m.needsGroupRecovery = true
		m.aggregateState = AggregateRelayWatchdogRestart
		log.Printf("[RELAY_SESSION] Watchdog triggered: %d consecutive failures for %s",
			s.ConsecutiveRefreshFailures, pidStr[:min(20, len(pidStr))])
	} else {
		m.recomputeAggregateLocked()
	}
}

// OnRefreshSucceeded records a successful relay refresh and resets the
// consecutive failure counter for that peer.
func (m *RelaySessionManager) OnRefreshSucceeded(peerID peer.ID) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	s, ok := m.sessions[pidStr]
	if !ok {
		s = &RelaySessionState{PeerID: peerID, State: RelayStateDisconnected}
		m.sessions[pidStr] = s
	}

	s.ConsecutiveRefreshFailures = 0
	s.State = RelayStateReserved
	s.LastReservedAt = time.Now()
	s.LastError = ""

	log.Printf("[RELAY_SESSION] Refresh succeeded for %s", pidStr[:min(20, len(pidStr))])
	m.recomputeAggregateLocked()
}

// NeedsGroupRecovery returns true when the watchdog has triggered and Flutter
// should rejoin group topics.
func (m *RelaySessionManager) NeedsGroupRecovery() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.needsGroupRecovery
}

// AcknowledgeGroupRecovery clears the needsGroupRecovery flag after Flutter
// has completed group topic rejoin.
func (m *RelaySessionManager) AcknowledgeGroupRecovery() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.needsGroupRecovery = false
}

// RecordWatchdogRestart tracks an actual full watchdog restart on the live
// node. This preserves restart telemetry and the follow-up group recovery
// signal across Stop()+Start() recovery cycles.
func (m *RelaySessionManager) RecordWatchdogRestart() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.watchdogRestartCount++
	m.needsGroupRecovery = true
}

// Reset clears all session state. Called from Stop under the node lock, so
// also when a full host restart stops the host. The host's lease holders go
// with it: the lease is cleared and the incarnation moves, so a release they
// send later can never clear a lease granted on the next host.
func (m *RelaySessionManager) Reset() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.sessions = make(map[string]*RelaySessionState)
	m.callMedia = callMediaLease{}
	m.hostIncarnation++
	m.hostUp = false
	if m.recovering {
		m.aggregateState = AggregateRelayRecovering
		return
	}
	m.aggregateState = AggregateRelayStarting
	m.recovery = nil
}

// --- Placeholder for autorelay metrics tracer hook ---

// InitRelayPeer initializes tracking for a known relay peer ID.
func (m *RelaySessionManager) InitRelayPeer(peerID peer.ID) {
	m.mu.Lock()
	defer m.mu.Unlock()

	pidStr := peerID.String()
	if _, ok := m.sessions[pidStr]; !ok {
		m.sessions[pidStr] = &RelaySessionState{
			PeerID: peerID,
			State:  RelayStateDisconnected,
		}
	}
}

// --- Helper for stale address detection ---

// IgnoresStaleCircuitAddresses returns a filtered list of circuit addresses,
// removing any that don't belong to a relay with an active reservation.
func (m *RelaySessionManager) IgnoresStaleCircuitAddresses(circuitAddrs []string) []string {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var valid []string
	for _, addr := range circuitAddrs {
		// Check if this circuit address belongs to a reserved relay.
		for _, s := range m.sessions {
			if s.State == RelayStateReserved {
				pidStr := s.PeerID.String()
				if strings.Contains(addr, pidStr) || strings.Contains(addr, fmt.Sprintf("/p2p/%s/", pidStr)) {
					valid = append(valid, addr)
					break
				}
			}
		}
	}

	return valid
}
