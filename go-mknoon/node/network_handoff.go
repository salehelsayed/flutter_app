package node

import (
	"context"
	"errors"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	ma "github.com/multiformats/go-multiaddr"
	msmux "github.com/multiformats/go-multistream"
)

// Default-network handoff (SE-42 D27). When the platform reports a new usable
// default network, the node replaces its relay session on that network without
// restarting the host: retire the relay connections born on the old path, dial
// the relay again on a brand-new socket, obtain a new reservation, and prove the
// new connection answers. Readiness is reported per path epoch.

const (
	// NetworkHandoffBudget caps one owned handoff attempt end to end.
	NetworkHandoffBudget = 8 * time.Second
	// NetworkHandoffProbeTimeout bounds the liveness round trip on the new connection.
	NetworkHandoffProbeTimeout = 1 * time.Second
	// networkHandoffRetireWait bounds the wait for the old relay connections to
	// drop out of the node's connection table after they are closed.
	networkHandoffRetireWait = 500 * time.Millisecond
)

// NetworkPathRequest is one default-network observation from the platform
// owner. Epoch increases monotonically per native runtime owner; OwnerGeneration
// is an opaque token the node echoes so the caller can fence stale outcomes.
type NetworkPathRequest struct {
	OwnerGeneration int64
	Epoch           uint64
	Usable          bool
}

// NetworkPathAdmission is the fast answer to a NetworkPathRequest. At most one
// attempt runs per epoch; duplicates and stale epochs are coalesced.
type NetworkPathAdmission struct {
	Accepted     bool   `json:"accepted"`
	Coalesced    bool   `json:"coalesced"`
	Reason       string `json:"reason,omitempty"`
	Epoch        uint64 `json:"epoch"`
	DesiredEpoch uint64 `json:"desiredEpoch"`
	ReadyEpoch   uint64 `json:"readyEpoch"`
}

// NetworkHandoffOutcome is the terminal result of one attempt. Only epochs,
// stages, counts and allow-listed reason codes appear here; never addresses.
type NetworkHandoffOutcome struct {
	Epoch           uint64 `json:"epoch"`
	OwnerGeneration int64  `json:"ownerGeneration"`
	Ready           bool   `json:"ready"`
	Stage           string `json:"stage"`
	ErrorCode       string `json:"errorCode,omitempty"`
	RelayID         string `json:"relayId,omitempty"`
	Transport       string `json:"transport,omitempty"`
	Family          string `json:"family,omitempty"`
	SocketFresh     bool   `json:"socketFresh"`
	DialMs          int64  `json:"dialMs"`
	ReserveMs       int64  `json:"reserveMs"`
	ProbeMs         int64  `json:"probeMs"`
	TotalMs         int64  `json:"totalMs"`
	ReservationTTLS int64  `json:"reservationTtlS,omitempty"`
}

// Handoff stages and reason codes (allow-listed diagnostics vocabulary).
const (
	handoffStageAdmit     = "admit"
	handoffStageOwnership = "ownership"
	handoffStageDial      = "dial"
	handoffStageReserve   = "reserve"
	handoffStageProbe     = "probe"
	handoffStageProbeOK   = "probe_ok"

	handoffReasonNotStarted        = "not_started"
	handoffReasonNotUsable         = "not_usable"
	handoffReasonStaleEpoch        = "stale_epoch"
	handoffReasonDuplicateEpoch    = "duplicate_epoch"
	handoffReasonSupersededRunning = "superseded_running"
	handoffReasonSuperseded        = "superseded"
	handoffReasonHostChanged       = "host_changed"
	handoffReasonRecoveryBusy      = "recovery_busy"
	handoffReasonTimeout           = "timeout"
	handoffReasonCancelled         = "cancelled"
	handoffReasonDialFailed        = "dial_failed"
	handoffReasonNoFreshConnection = "no_fresh_connection"
	handoffReasonReserveFailed     = "reserve_failed"
	handoffReasonProbeFailed       = "probe_failed"
	handoffReasonNoRelays          = "no_relays"
)

var (
	errHandoffSuperseded   = errors.New("network path superseded")
	errNoFreshRelayConn    = errors.New("no fresh relay connection after dial")
	errPinnedConnWrongPeer = errors.New("pinned connection belongs to another peer")
)

// networkPathHandoff is the per-node state machine. Exactly one runner
// goroutine exists while `running` is non-nil; it serves the latest desired
// epoch after the current attempt retires, so attempts never overlap.
//
// Two kinds of state live here. The observation (desired, usable, ownerGen)
// belongs to the platform owner and outlives the host: a usable path refused
// with not_started while the node is stopped or starting is replayed on the
// next Start, so an internal watchdog Stop/Start loses no path event. The
// readiness (attempted, ready, last) belongs to one host generation and is
// cleared with it. hostUp and hostGen mirror the node's started state and
// host generation, written under the node lock at Start commit and Stop, so
// admission and the runner decide on one consistent view without nesting the
// node lock inside this one.
type networkPathHandoff struct {
	mu        sync.Mutex
	desired   uint64
	usable    bool
	ownerGen  int64
	hostUp    bool
	hostGen   uint64
	attempted uint64
	ready     uint64
	running   *handoffAttempt
	last      *NetworkHandoffOutcome
}

type handoffAttempt struct {
	epoch     uint64
	ownerGen  int64
	hostGen   uint64
	cancel    context.CancelCauseFunc
	published bool
}

// cancelWork stops the attempt's work. A queued attempt (admitted, runner not
// yet scheduled) has no work to stop; the runner re-reads the desired epoch
// when it starts.
func (a *handoffAttempt) cancelWork(cause error) {
	if a != nil && a.cancel != nil {
		a.cancel(cause)
	}
}

func newNetworkPathHandoff() *networkPathHandoff {
	return &networkPathHandoff{}
}

// hostStopped forgets the readiness of the host that is going away and stops
// a running attempt. The owner's latest observation stays for replay. Called
// from Stop under the node lock.
func (h *networkPathHandoff) hostStopped() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.running.cancelWork(errHandoffSuperseded)
	h.hostUp = false
	h.attempted, h.ready, h.last = 0, 0, nil
}

// hostStarted opens the epoch space of a new host generation. Called from
// Start's commit under the node lock. It reports whether a usable observation
// is pending; the caller then starts the runner, which serves that epoch on
// the new host. A runner that is still winding down from the previous host
// re-reads this state and serves the epoch itself.
func (h *networkPathHandoff) hostStarted(hostGen uint64) (replay bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.hostUp = true
	h.hostGen = hostGen
	h.attempted, h.ready, h.last = 0, 0, nil
	if !h.usable || h.desired == 0 || h.running != nil {
		return false
	}
	h.running = &handoffAttempt{}
	return true
}

// NetworkPathChanged admits one default-network observation. It returns
// quickly; the work runs on the node's single handoff runner.
func (n *Node) NetworkPathChanged(req NetworkPathRequest) NetworkPathAdmission {
	h := n.networkPath
	h.mu.Lock()
	defer h.mu.Unlock()

	adm := NetworkPathAdmission{Epoch: req.Epoch}
	finish := func() NetworkPathAdmission {
		adm.DesiredEpoch = h.desired
		adm.ReadyEpoch = h.ready
		return adm
	}
	if req.Epoch == 0 {
		adm.Reason = "invalid_epoch"
		return finish()
	}
	if req.OwnerGeneration != h.ownerGen {
		// Epochs count per platform owner. A new owner numbers from 1 again,
		// so its first observation opens a fresh epoch space.
		h.desired, h.usable, h.attempted, h.ready, h.last = 0, false, 0, 0, nil
	}
	alreadyServed := h.attempted >= req.Epoch || h.running != nil
	switch {
	case req.Epoch < h.desired:
		adm.Coalesced = true
		adm.Reason = handoffReasonStaleEpoch
		return finish()
	case req.Epoch == h.desired && req.Usable == h.usable && (!req.Usable || alreadyServed):
		adm.Coalesced = true
		adm.Reason = handoffReasonDuplicateEpoch
		return finish()
	}
	h.desired = req.Epoch
	h.usable = req.Usable
	h.ownerGen = req.OwnerGeneration

	if !req.Usable {
		// Loss-only period: remember the epoch, do no work, stop work for a
		// path that is gone.
		h.running.cancelWork(errHandoffSuperseded)
		adm.Reason = handoffReasonNotUsable
		return finish()
	}
	if !h.hostUp {
		// Buffered: the next Start replays it. A path event never starts a node.
		adm.Reason = handoffReasonNotStarted
		return finish()
	}
	adm.Accepted = true
	if h.running != nil {
		h.running.cancelWork(errHandoffSuperseded)
		adm.Reason = handoffReasonSupersededRunning
		return finish()
	}
	h.running = &handoffAttempt{}
	go n.runNetworkHandoffs()
	return finish()
}

// runNetworkHandoffs serves desired epochs one at a time until none is pending.
func (n *Node) runNetworkHandoffs() {
	h := n.networkPath
	for {
		n.mu.RLock()
		baseCtx := n.ctx
		hostGen := n.hostGeneration
		n.mu.RUnlock()
		if baseCtx == nil {
			baseCtx = context.Background()
		}

		h.mu.Lock()
		if h.hostUp && h.hostGen != hostGen {
			// A Start committed between the two reads; read the new host.
			h.mu.Unlock()
			continue
		}
		if !h.hostUp || !h.usable || h.desired <= h.attempted {
			h.running = nil
			h.mu.Unlock()
			return
		}
		ctx, cancel := context.WithCancelCause(baseCtx)
		att := &handoffAttempt{epoch: h.desired, ownerGen: h.ownerGen, hostGen: hostGen, cancel: cancel}
		h.running = att
		h.attempted = att.epoch
		previousReady := h.ready
		h.mu.Unlock()

		n.emitEvent("network:path_changing", map[string]interface{}{
			"epoch":              att.epoch,
			"ownerGeneration":    att.ownerGen,
			"previousReadyEpoch": previousReady,
		})
		n.performNetworkHandoff(ctx, att)
		cancel(nil)
	}
}

// performNetworkHandoff is one owned attempt: take the shared recovery gate,
// then do every host mutation and the relay work under it. The attempt
// publishes its own terminal outcome as soon as it is known, then restores
// the existing registration intents while it still holds recovery ownership.
func (n *Node) performNetworkHandoff(ctx context.Context, att *handoffAttempt) {
	start := time.Now()
	ctx, cancelBudget := context.WithTimeout(ctx, NetworkHandoffBudget)
	defer cancelBudget()

	n.mu.RLock()
	mgr := n.relaySessionMgr
	n.mu.RUnlock()

	recovery, err := n.acquireRecoveryForHandoff(ctx, mgr)
	if err != nil {
		n.publishNetworkHandoffOutcome(att, &NetworkHandoffOutcome{
			Epoch: att.epoch, OwnerGeneration: att.ownerGen,
			Stage: handoffStageOwnership, ErrorCode: handoffReasonCode(err, handoffReasonRecoveryBusy),
			TotalMs: time.Since(start).Milliseconds(),
		})
		return
	}
	n.runRelayRecovery(mgr, recovery, func() (*RecoveryResult, error) {
		outcome := n.performOwnedNetworkHandoff(ctx, att, mgr, start)
		result := &RecoveryResult{
			RecoveryMode:           "network_handoff",
			Success:                outcome.Ready,
			RelayState:             string(mgr.AggregateState()),
			HealthyRelayCount:      mgr.HealthyRelayCount(),
			ReusedHost:             true,
			RelayWarmMs:            outcome.DialMs,
			ReserveRpcMs:           outcome.ReserveMs,
			RelayRefreshMs:         outcome.TotalMs,
			ForegroundRecoveryPath: "network_handoff",
		}
		if outcome.Ready {
			result.ReservationPath = "explicit_reserve"
			result.ReservationWinnerPeer = outcome.RelayID
		} else {
			result.ErrorCode = "NETWORK_HANDOFF_FAILED"
			result.Reason = outcome.Stage + ":" + outcome.ErrorCode
		}
		return n.finalizeRelayRecoveryResult(result, "network handoff"), nil
	})
}

// refreshLocalNetworkIdentity runs once per usable path epoch, under recovery
// ownership, before any relay work and whether or not relays are configured.
// It snapshots the interfaces so the advertised addresses follow the new
// network at once instead of after libp2p's one-minute interface cache, then
// moves the QUIC listeners to sockets born on the new network so every later
// dial, relay or direct, stops depending on the old network's socket. The
// re-listen also makes libp2p recompute and announce the addresses
// immediately.
func (n *Node) refreshLocalNetworkIdentity(h host.Host, epoch uint64, listenPort int) {
	count, err := n.addrOverlay.refresh(time.Now())
	if err != nil {
		log.Printf("[NODE] network handoff epoch %d: interface snapshot failed, advertised addresses follow libp2p's cache: %v", epoch, err)
	} else {
		log.Printf("[NODE] network handoff epoch %d: interface snapshot has %d addresses", epoch, count)
	}
	if n.freshRelayDial.plainRedialForTests() {
		return
	}
	t := n.freshRelayDial.transport.Load()
	sw, ok := h.Network().(*swarm.Swarm)
	if t == nil || !ok {
		log.Printf("[NODE] network handoff epoch %d: QUIC listeners kept (no node-owned QUIC transport)", epoch)
		return
	}
	moved, err := t.rebindListeners(sw, listenPort, epoch)
	if err != nil {
		log.Printf("[NODE] network handoff epoch %d: QUIC listeners kept: %v", epoch, err)
		return
	}
	log.Printf("[NODE] network handoff epoch %d: %d QUIC listeners moved to new sockets", epoch, moved)
}

// acquireRecoveryForHandoff takes the shared recovery gate. A running owner is
// asked to stop early and the handoff waits for it to really finish; it never
// starts a second host mutation beside it.
func (n *Node) acquireRecoveryForHandoff(ctx context.Context, mgr *RelaySessionManager) (*recoveryPromise, error) {
	for {
		recovery, isNew := mgr.BeginRecovery()
		if isNew {
			return recovery, nil
		}
		mgr.CancelRecovery(errHandoffSuperseded)
		select {
		case <-recovery.done:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
}

// performOwnedNetworkHandoff runs while the node owns recovery. Every host
// mutation of the handoff happens here, after the host captured at admission
// is revalidated: the listeners move to the new network, fresh dials are
// armed, the old relay connections are retired, then the configured relays
// race to a proven new session. The first proven relay publishes readiness.
func (n *Node) performOwnedNetworkHandoff(ctx context.Context, att *handoffAttempt, mgr *RelaySessionManager, start time.Time) *NetworkHandoffOutcome {
	n.mu.RLock()
	h := n.host
	hostCurrent := n.isStarted && h != nil && n.hostGeneration == att.hostGen
	relayAddrs := n.relayAddresses
	order := append([]peer.ID(nil), n.relayPeerOrder...)
	listenPort := 0
	if n.lastConfig != nil {
		listenPort = n.lastConfig.ListenPort
	}
	n.mu.RUnlock()

	fail := func(stage, code string) *NetworkHandoffOutcome {
		outcome := &NetworkHandoffOutcome{
			Epoch: att.epoch, OwnerGeneration: att.ownerGen, Stage: stage, ErrorCode: code,
			TotalMs: time.Since(start).Milliseconds(),
		}
		n.publishNetworkHandoffOutcome(att, outcome)
		return outcome
	}
	if !hostCurrent {
		return fail(handoffStageOwnership, handoffReasonHostChanged)
	}
	n.refreshLocalNetworkIdentity(h, att.epoch, listenPort)
	_, infoMap := relayWarmPlan(relayAddrs, order)
	relays := make([]peer.AddrInfo, 0, len(order))
	for _, pid := range order {
		if info, ok := infoMap[pid]; ok {
			relays = append(relays, *info)
		}
	}
	if len(relays) == 0 {
		return fail(handoffStageAdmit, handoffReasonNoRelays)
	}

	policy := n.freshRelayDial
	peers := make([]peer.ID, 0, len(relays))
	for _, r := range relays {
		peers = append(peers, r.ID)
	}
	policy.arm(att.epoch, peers)
	defer policy.disarm(att.epoch)

	n.retireRelayConnections(ctx, h, relays)

	results := make(chan *NetworkHandoffOutcome, len(relays))
	for _, relay := range relays {
		relay := relay
		go func() {
			results <- n.handoffOneRelay(ctx, att, h, mgr, relay, start)
		}()
	}
	var ready, failed *NetworkHandoffOutcome
	for range relays {
		outcome := <-results
		switch {
		case outcome.Ready && ready == nil:
			ready = outcome
			if n.publishNetworkHandoffOutcome(att, outcome) {
				continue
			}
			// Discarded as stale: keep waiting for the others only to drain.
		case !outcome.Ready && (failed == nil || handoffStageRank(outcome.Stage) > handoffStageRank(failed.Stage)):
			failed = outcome
		}
	}
	if ready != nil {
		return ready
	}
	if failed == nil {
		failed = &NetworkHandoffOutcome{Epoch: att.epoch, OwnerGeneration: att.ownerGen, Stage: handoffStageDial, ErrorCode: handoffReasonDialFailed, TotalMs: time.Since(start).Milliseconds()}
	}
	n.publishNetworkHandoffOutcome(att, failed)
	return failed
}

func handoffStageRank(stage string) int {
	switch stage {
	case handoffStageDial:
		return 1
	case handoffStageReserve:
		return 2
	case handoffStageProbe:
		return 3
	}
	return 0
}

// retireRelayConnections closes the configured relays' current connections
// (captured now, so a successor dialed later is never touched), waits briefly
// for the node to observe the disconnect, and drops the per-relay dial state
// derived on the old path. Configured addresses are re-added permanently so
// the next dial resolves them fresh.
func (n *Node) retireRelayConnections(ctx context.Context, h host.Host, relays []peer.AddrInfo) {
	var obsolete []network.Conn
	for _, relay := range relays {
		obsolete = append(obsolete, h.Network().ConnsToPeer(relay.ID)...)
	}
	for _, c := range obsolete {
		_ = c.Close()
	}
	deadline := time.Now().Add(networkHandoffRetireWait)
	for time.Now().Before(deadline) && ctx.Err() == nil {
		if n.relaysRetired(h, relays) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	sw, _ := h.Network().(*swarm.Swarm)
	for _, relay := range relays {
		h.Peerstore().ClearAddrs(relay.ID)
		h.Peerstore().AddAddrs(relay.ID, relay.Addrs, peerstore.PermanentAddrTTL)
		if sw != nil {
			sw.Backoff().Clear(relay.ID)
		}
	}
}

func (n *Node) relaysRetired(h host.Host, relays []peer.AddrInfo) bool {
	n.mu.RLock()
	defer n.mu.RUnlock()
	for _, relay := range relays {
		if _, tracked := n.connections[relay.ID.String()]; tracked {
			return false
		}
		if h.Network().Connectedness(relay.ID) != network.NotConnected {
			return false
		}
	}
	return true
}

// handoffOneRelay proves one relay on the new path: fresh dial, explicit
// reservation and a bounded liveness round trip, all pinned to the one new
// connection.
func (n *Node) handoffOneRelay(ctx context.Context, att *handoffAttempt, h host.Host, mgr *RelaySessionManager, relay peer.AddrInfo, start time.Time) *NetworkHandoffOutcome {
	outcome := &NetworkHandoffOutcome{Epoch: att.epoch, OwnerGeneration: att.ownerGen, RelayID: shortPeer(relay.ID)}
	finish := func(stage, code string) *NetworkHandoffOutcome {
		outcome.Stage, outcome.ErrorCode = stage, code
		outcome.TotalMs = time.Since(start).Milliseconds()
		return outcome
	}

	dialStart := time.Now()
	conn, err := n.dialFreshRelay(ctx, h, relay, att.epoch)
	outcome.DialMs = time.Since(dialStart).Milliseconds()
	if err != nil {
		log.Printf("[NODE] network handoff epoch %d: relay %s dial failed: %v", att.epoch, outcome.RelayID, err)
		return finish(handoffStageDial, handoffReasonCode(err, handoffReasonDialFailed))
	}
	family, proto, _, _ := diagnosticAddress(conn.LocalMultiaddr())
	outcome.Family, outcome.Transport, outcome.SocketFresh = family, proto, true
	pinned := pinnedConnHost{Host: h, conn: conn}

	reserveStart := time.Now()
	reserveCtx, cancelReserve := context.WithTimeout(ctx, ForegroundRelayReserveTimeout)
	reservation, err := n.reserveRelaySlot(reserveCtx, pinned, peer.AddrInfo{ID: relay.ID})
	cancelReserve()
	outcome.ReserveMs = time.Since(reserveStart).Milliseconds()
	if err != nil {
		mgr.OnRequestFailed(relay.ID, err)
		log.Printf("[NODE] network handoff epoch %d: relay %s reserve failed: %v", att.epoch, outcome.RelayID, err)
		return finish(handoffStageReserve, handoffReasonCode(err, handoffReasonReserveFailed))
	}
	var expiry time.Time
	if reservation != nil {
		expiry = reservation.Expiration
	}
	mgr.OnManualReservationOpened(relay.ID, expiry)
	if !expiry.IsZero() {
		outcome.ReservationTTLS = int64(time.Until(expiry).Seconds())
	}

	probeStart := time.Now()
	probeCtx, cancelProbe := context.WithTimeout(ctx, NetworkHandoffProbeTimeout)
	err = probePinnedRelay(probeCtx, pinned, relay.ID)
	cancelProbe()
	outcome.ProbeMs = time.Since(probeStart).Milliseconds()
	if err != nil {
		log.Printf("[NODE] network handoff epoch %d: relay %s probe failed: %v", att.epoch, outcome.RelayID, err)
		return finish(handoffStageProbe, handoffReasonCode(err, handoffReasonProbeFailed))
	}
	if conn.IsClosed() {
		return finish(handoffStageProbe, handoffReasonNoFreshConnection)
	}
	outcome.Ready = true
	return finish(handoffStageProbeOK, "")
}

// dialFreshRelay connects to the relay through the host's normal dial path
// and returns the connection that rides a new socket. If the swarm handed back
// an in-flight old-socket dial instead, that connection is retired and the
// dial is repeated once within the budget.
func (n *Node) dialFreshRelay(ctx context.Context, h host.Host, relay peer.AddrInfo, epoch uint64) (network.Conn, error) {
	for attempt := 0; attempt < 2; attempt++ {
		dialCtx, cancel := context.WithTimeout(ctx, ForegroundRelayDialTimeout)
		dialCtx = network.WithDialPeerTimeout(dialCtx, ForegroundRelayDialTimeout)
		err := n.connectRelay(dialCtx, relay)
		cancel()
		if err != nil {
			return nil, err
		}
		var stale []network.Conn
		for _, c := range h.Network().ConnsToPeer(relay.ID) {
			if c.IsClosed() {
				continue
			}
			if n.freshRelayDial.isFreshFor(c, epoch) {
				return c, nil
			}
			stale = append(stale, c)
		}
		if len(stale) == 0 {
			return nil, errNoFreshRelayConn
		}
		for _, c := range stale {
			_ = c.Close()
		}
	}
	return nil, errNoFreshRelayConn
}

// isFreshFor reports whether a connection was born on this epoch's new path:
// a QUIC connection recorded by the fresh dial seam, or any non-QUIC
// connection (TCP and WebSocket always open a new socket per connection).
func (p *freshQUICDialPolicy) isFreshFor(c network.Conn, epoch uint64) bool {
	if _, err := c.LocalMultiaddr().ValueForProtocol(ma.P_QUIC_V1); err != nil {
		return true
	}
	e, ok := p.freshEpoch(c)
	return ok && e == epoch
}

func probePinnedRelay(ctx context.Context, h host.Host, relay peer.ID) error {
	select {
	case res := <-ping.Ping(ctx, h, relay):
		return res.Error
	case <-ctx.Done():
		return ctx.Err()
	}
}

// publishNetworkHandoffOutcome records the outcome and emits exactly one
// terminal event for the attempt. Ready is accepted only while the attempt's
// epoch is still the desired one and the host it worked on is still current.
// It returns whether the outcome stood as ready.
func (n *Node) publishNetworkHandoffOutcome(att *handoffAttempt, outcome *NetworkHandoffOutcome) bool {
	if n.beforePublishNetworkHandoffHook != nil {
		n.beforePublishNetworkHandoffHook(att.epoch)
	}
	n.mu.RLock()
	hostCurrent := n.isStarted && n.hostGeneration == att.hostGen
	n.mu.RUnlock()

	h := n.networkPath
	h.mu.Lock()
	if att.published {
		h.mu.Unlock()
		return false
	}
	att.published = true
	epochCurrent := att.epoch == h.desired && h.usable
	if outcome.Ready {
		switch {
		case !epochCurrent:
			outcome.Ready = false
			outcome.ErrorCode = handoffReasonSuperseded
		case !hostCurrent:
			outcome.Ready = false
			outcome.ErrorCode = handoffReasonHostChanged
		default:
			h.ready = att.epoch
		}
	}
	if epochCurrent {
		h.last = outcome
	}
	h.mu.Unlock()

	data := map[string]interface{}{
		"epoch":           outcome.Epoch,
		"ownerGeneration": outcome.OwnerGeneration,
		"stage":           outcome.Stage,
		"totalMs":         outcome.TotalMs,
	}
	if outcome.Ready {
		data["relayId"] = outcome.RelayID
		data["transport"] = outcome.Transport
		data["family"] = outcome.Family
		data["socketFresh"] = outcome.SocketFresh
		data["dialMs"] = outcome.DialMs
		data["reserveMs"] = outcome.ReserveMs
		data["probeMs"] = outcome.ProbeMs
		data["reservationTtlS"] = outcome.ReservationTTLS
		n.emitEvent("network:relay_ready", data)
		return true
	}
	data["errorCode"] = outcome.ErrorCode
	n.emitEvent("network:relay_failed", data)
	return false
}

// NetworkPathStatus is merged into node:status so a late subscriber can read
// the latest epoch outcome instead of depending on event timing.
func (n *Node) NetworkPathStatus() map[string]interface{} {
	h := n.networkPath
	h.mu.Lock()
	defer h.mu.Unlock()
	status := map[string]interface{}{
		"desiredEpoch": h.desired,
		"readyEpoch":   h.ready,
		"usable":       h.usable,
		"running":      h.running != nil,
	}
	if h.last != nil {
		last := *h.last
		status["last"] = last
	}
	return status
}

func handoffReasonCode(err error, fallback string) string {
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		return handoffReasonTimeout
	case errors.Is(err, errHandoffSuperseded):
		return handoffReasonSuperseded
	case errors.Is(err, context.Canceled):
		return handoffReasonCancelled
	case errors.Is(err, errNoFreshRelayConn):
		return handoffReasonNoFreshConnection
	}
	return fallback
}

func shortPeer(p peer.ID) string {
	s := p.String()
	return s[:min(20, len(s))]
}

// pinnedConnHost is a host.Host whose NewStream opens on one chosen
// connection, so a reservation or probe proves that exact connection and not
// whichever one the swarm would pick. The stream is reset when ctx ends, which
// bounds callers that set their own long stream deadlines.
type pinnedConnHost struct {
	host.Host
	conn network.Conn
}

func (p pinnedConnHost) NewStream(ctx context.Context, pid peer.ID, pids ...protocol.ID) (network.Stream, error) {
	if pid != p.conn.RemotePeer() {
		return nil, errPinnedConnWrongPeer
	}
	raw, err := p.conn.NewStream(ctx)
	if err != nil {
		return nil, err
	}
	stop := context.AfterFunc(ctx, func() { _ = raw.Reset() })
	s := &ctxBoundStream{Stream: raw, stop: stop}

	var selected protocol.ID
	errCh := make(chan error, 1)
	go func() {
		var negErr error
		selected, negErr = msmux.SelectOneOf(pids, s)
		errCh <- negErr
	}()
	select {
	case err = <-errCh:
	case <-ctx.Done():
		_ = s.Reset()
		<-errCh
		err = ctx.Err()
	}
	if err != nil {
		_ = s.Reset()
		return nil, fmt.Errorf("pinned stream negotiation: %w", err)
	}
	if err := s.SetProtocol(selected); err != nil {
		_ = s.Reset()
		return nil, err
	}
	return s, nil
}

// ctxBoundStream is reset when its context ends, unless the caller already
// closed or reset it. That bounds library calls that set their own long
// stream deadlines without sending a stray reset after a clean close.
type ctxBoundStream struct {
	network.Stream
	stop func() bool
}

func (s *ctxBoundStream) Close() error {
	s.stop()
	return s.Stream.Close()
}

func (s *ctxBoundStream) Reset() error {
	s.stop()
	return s.Stream.Reset()
}

func (s *ctxBoundStream) ResetWithError(code network.StreamErrorCode) error {
	s.stop()
	return s.Stream.ResetWithError(code)
}
