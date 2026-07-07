package node

import (
	"context"
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

func TestGoLibp2pProductionShapeBudget(t *testing.T) {
	budgets := []struct {
		path string
		name string
		max  int
	}{
		{path: "node.go", name: "refreshRelaySessionOwned", max: 190},
		{path: "pubsub.go", name: "discoverAndConnectGroupPeers", max: 145},
		{path: "pubsub.go", name: "dialKnownGroupMembers", max: 130},
		{path: "../bridge/bridge.go", name: "GroupPublish", max: 80},
		{path: "../bridge/bridge.go", name: "GroupSendReliable", max: 85},
	}

	for _, budget := range budgets {
		got := countedFunctionLines(t, budget.path, budget.name)
		if got > budget.max {
			t.Errorf("%s:%s counted lines = %d, want <= %d", budget.path, budget.name, got, budget.max)
		}
	}

	dispatcherSource, err := os.ReadFile("event_dispatcher.go")
	if err != nil {
		t.Fatalf("read event_dispatcher.go: %v", err)
	}
	if strings.Contains(string(dispatcherSource), "messageQueue[1:]") {
		t.Fatal("event dispatcher must not dequeue by reslicing messageQueue[1:]")
	}
}

func TestStartDoesNotHoldNodeLockAcrossHostCreation(t *testing.T) {
	blocked := startNodeWithBlockedHostCreation(t, nil)
	targetPeer := generatePeerIDStr(t)

	statusStart := time.Now()
	statusCh := make(chan map[string]interface{}, 1)
	go func() { statusCh <- blocked.node.Status() }()

	var status map[string]interface{}
	statusFast := false
	select {
	case status = <-statusCh:
		statusFast = time.Since(statusStart) < 50*time.Millisecond
	case <-time.After(50 * time.Millisecond):
	}

	sendErr, sendFast := errorCallReturnsWithin(func() error {
		_, _, err := blocked.node.SendMessage(targetPeer, "hello", 1)
		return err
	}, 50*time.Millisecond)
	dialErr, dialFast := errorCallReturnsWithin(func() error {
		return blocked.node.DialPeer(targetPeer, nil)
	}, 50*time.Millisecond)

	blocked.releaseAndWait(t)
	blocked.stopIfStarted(t)

	if !statusFast {
		t.Fatal("Status blocked behind host creation; Start still holds node lock on the slow host path")
	}
	if status["isStarted"] != false || status["peerId"] != "" {
		t.Fatalf("status during start = %v, want pre-start public state", status)
	}
	if !sendFast || sendErr == nil || !strings.Contains(sendErr.Error(), "node not started") {
		t.Fatalf("SendMessage during start err=%v fast=%t, want fast node-not-started error", sendErr, sendFast)
	}
	if !dialFast || dialErr == nil || !strings.Contains(dialErr.Error(), "node not started") {
		t.Fatalf("DialPeer during start err=%v fast=%t, want fast node-not-started error", dialErr, dialFast)
	}
}

func TestStartRejectsConcurrentStartWhileHostCreationInProgress(t *testing.T) {
	var hostFactoryCalls int64
	blocked := startNodeWithBlockedHostCreation(t, func(n *Node) {
		previousFactory := n.newHost
		n.newHost = func(cfg NodeConfig, opts []libp2p.Option) (host.Host, error) {
			atomic.AddInt64(&hostFactoryCalls, 1)
			return previousFactory(cfg, opts)
		}
	})

	err, fast := errorCallReturnsWithin(func() error {
		_, err := blocked.node.Start(NodeConfig{
			PrivateKeyHex:  generateTestKey(t),
			RelayAddresses: []string{},
			AutoRegister:   false,
		})
		return err
	}, 50*time.Millisecond)

	blocked.releaseAndWait(t)
	blocked.stopIfStarted(t)

	if !fast {
		t.Fatal("second Start blocked behind in-progress host creation")
	}
	if err == nil || !strings.Contains(err.Error(), "node start in progress") {
		t.Fatalf("second Start error = %v, want node start in progress", err)
	}
	if got := atomic.LoadInt64(&hostFactoryCalls); got != 1 {
		t.Fatalf("host factory calls = %d, want 1", got)
	}
}

func TestStartHostCreationFailureRollsBackPublishedState(t *testing.T) {
	n := NewNode()
	relayAddr := generateFakeRelayAddr(t, 21991)
	n.newHost = func(NodeConfig, []libp2p.Option) (host.Host, error) {
		return nil, errors.New("fake host failure")
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{relayAddr},
		AutoRegister:   false,
	})
	if err == nil {
		t.Fatal("Start succeeded, want fake host failure")
	}
	assertNoPartialStartState(t, n)

	n.newHost = defaultNewHost
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	}); err != nil {
		t.Fatalf("retry Start after failed host creation: %v", err)
	}
	n.Stop()
}

func TestStartHostCreationPanicClearsInProgressAndAllowsRetry(t *testing.T) {
	n := NewNode()
	relayAddr := generateFakeRelayAddr(t, 21992)
	n.newHost = func(NodeConfig, []libp2p.Option) (host.Host, error) {
		panic("fake host panic")
	}

	var startErr error
	var recovered interface{}
	func() {
		defer func() { recovered = recover() }()
		_, startErr = n.Start(NodeConfig{
			PrivateKeyHex:  generateTestKey(t),
			RelayAddresses: []string{relayAddr},
			AutoRegister:   false,
		})
	}()
	if recovered == nil && startErr == nil {
		t.Fatal("Start returned nil error and no panic from fake host panic")
	}
	assertNoPartialStartState(t, n)

	n.newHost = defaultNewHost
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	}); err != nil {
		t.Fatalf("retry Start after panicking host creation: %v", err)
	}
	n.Stop()
}

func TestStopDuringStartInProgressIsExplicitAndNonMutating(t *testing.T) {
	blocked := startNodeWithBlockedHostCreation(t, nil)

	err, fast := errorCallReturnsWithin(blocked.node.Stop, 50*time.Millisecond)
	blocked.releaseAndWait(t)

	if !fast {
		blocked.stopIfStarted(t)
		t.Fatal("Stop blocked behind in-progress host creation")
	}
	if err == nil || !strings.Contains(err.Error(), "node start in progress") {
		blocked.stopIfStarted(t)
		t.Fatalf("Stop during start error = %v, want node start in progress", err)
	}
	if !blocked.started() {
		t.Fatal("Stop during start mutated the pending start; node did not commit")
	}
	if err := blocked.node.Stop(); err != nil {
		t.Fatalf("normal Stop after pending start commits: %v", err)
	}
}

func TestReconnectRelaysDuringStartInProgressFailsFast(t *testing.T) {
	blocked := startNodeWithBlockedHostCreation(t, func(n *Node) {
		n.refreshRelaySessionHook = func() *RecoveryResult {
			return &RecoveryResult{RecoveryMode: "in_place", Success: false, Reason: "forced test failure", ReusedHost: true}
		}
	})

	err, fast := errorCallReturnsWithin(func() error {
		_, err := blocked.node.ReconnectRelays()
		return err
	}, 50*time.Millisecond)

	blocked.releaseAndWait(t)
	blocked.stopIfStarted(t)

	if !fast {
		t.Fatal("ReconnectRelays blocked behind in-progress host creation")
	}
	if err == nil || !strings.Contains(err.Error(), "node start in progress") {
		t.Fatalf("ReconnectRelays during start error = %v, want node start in progress", err)
	}
}

func TestGroupDialKnownMembersRunsBoundedParallel(t *testing.T) {
	stats := newGroupDialStats(100 * time.Millisecond)
	elapsed := medianDuration(3, func() {
		n, groupID := startNodeWithGroupDialTargets(t, 5)
		defer n.Stop()
		n.connectGroupPeerHook = stats.connect
		stats.reset()
		n.dialKnownGroupMembers(groupID, true)
	})

	if elapsed < 90*time.Millisecond || elapsed >= 250*time.Millisecond {
		t.Fatalf("known-member dial elapsed median = %v, want >=90ms and <250ms", elapsed)
	}
	if got, want := stats.maxInFlight(), int64(min(GroupDiscoveryConcurrency, 5)); got != want {
		t.Fatalf("known-member max in-flight = %d, want %d", got, want)
	}
	if peer, max := stats.maxInFlightPerPeer(); max > 1 {
		t.Fatalf("known-member peer %s had %d in-flight dials, want <=1", peer, max)
	}
}

func TestDiscoverAndConnectGroupPeersRunsBoundedParallel(t *testing.T) {
	stats := newGroupDialStats(100 * time.Millisecond)
	elapsed := medianDuration(3, func() {
		n, groupID := startNodeWithGroupDialTargets(t, 5)
		defer n.Stop()
		memberPeers := groupMemberAddrInfos(t, n.groupConfigs[groupID])
		nonMember := peer.AddrInfo{ID: decodePeerID(t, generatePeerIDStr(t))}
		n.rendezvousDiscoverHook = func(string, []string) ([]peer.AddrInfo, error) {
			return append(memberPeers, nonMember), nil
		}
		n.connectGroupPeerHook = stats.connect
		stats.reset()
		n.discoverAndConnectGroupPeers(groupID)
	})

	if elapsed < 90*time.Millisecond || elapsed >= 250*time.Millisecond {
		t.Fatalf("discovered-peer dial elapsed median = %v, want >=90ms and <250ms", elapsed)
	}
	if got, want := stats.maxInFlight(), int64(min(GroupDiscoveryConcurrency, 5)); got != want {
		t.Fatalf("discovered-peer max in-flight = %d, want %d", got, want)
	}
	if peer, max := stats.maxInFlightPerPeer(); max > 1 {
		t.Fatalf("discovered-peer %s had %d in-flight dials, want <=1", peer, max)
	}
	if got := stats.totalCalls(); got != 5 {
		t.Fatalf("discovered-peer connect calls = %d, want 5 active members only", got)
	}
}

func TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)
	stats := newGroupDialStats(100 * time.Millisecond)
	stats.reset()
	n.connectGroupPeerHook = stats.connect
	n.rendezvousDiscoverHook = func(string, []string) ([]peer.AddrInfo, error) {
		return nil, nil
	}
	groupIDs := make([]string, 0, GroupDiscoveryConcurrency)
	for i := 0; i < GroupDiscoveryConcurrency; i++ {
		groupID := fmt.Sprintf("global-group-dial-%d", i)
		groupIDs = append(groupIDs, groupID)
		addGroupDialTargets(t, n, groupID, 5)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var wg sync.WaitGroup
	for _, groupID := range groupIDs {
		groupID := groupID
		wg.Add(1)
		go func() {
			defer wg.Done()
			executed, _ := n.runGroupDiscoveryCycle(ctx, groupID, groupRendezvousNamespace(groupID), false, true)
			if !executed {
				t.Errorf("runGroupDiscoveryCycle(%s) did not execute", groupID)
			}
		}()
	}
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-ctx.Done():
		t.Fatal("runGroupDiscoveryCycle deadlocked under global group dial load")
	}
	if got := stats.maxInFlight(); got > int64(GroupDiscoveryConcurrency) {
		t.Fatalf("global group connect in-flight = %d, want <= %d", got, GroupDiscoveryConcurrency)
	}
}

func TestRelaySelectorFanOutRunsDistinctRelaysInParallel(t *testing.T) {
	rs := NewRelaySelector([]string{
		generateFakeRelayAddr(t, 22991),
		generateFakeRelayAddr(t, 22992),
		generateFakeRelayAddr(t, 22993),
	})
	var current int64
	var maxSeen int64
	var calls int64
	start := time.Now()
	err := rs.FanOut(func(RelayInfo) error {
		trackAtomicInFlight(&current, &maxSeen, 1)
		defer trackAtomicInFlight(&current, &maxSeen, -1)
		atomic.AddInt64(&calls, 1)
		time.Sleep(100 * time.Millisecond)
		return nil
	})
	elapsed := time.Since(start)
	if err != nil {
		t.Fatalf("FanOut: %v", err)
	}
	if got := atomic.LoadInt64(&calls); got != 3 {
		t.Fatalf("FanOut calls = %d, want all 3 relays attempted", got)
	}
	if got := atomic.LoadInt64(&maxSeen); got != 3 {
		t.Fatalf("FanOut max in-flight = %d, want 3", got)
	}
	if elapsed >= 180*time.Millisecond {
		t.Fatalf("FanOut elapsed = %v, want <180ms", elapsed)
	}
}

func TestRelaySelectorFanOutAllFailPreservesAggregateError(t *testing.T) {
	rs := NewRelaySelector([]string{
		generateFakeRelayAddr(t, 23991),
		generateFakeRelayAddr(t, 23992),
	})
	err := rs.FanOut(func(RelayInfo) error {
		return errors.New("relay down")
	})
	if err == nil {
		t.Fatal("FanOut all-fail returned nil error")
	}
	if !strings.Contains(err.Error(), "all 2 relays failed") || !strings.Contains(err.Error(), "relay down") {
		t.Fatalf("FanOut all-fail error = %v, want aggregate relay failure context", err)
	}
}

func countedFunctionLines(t *testing.T, path string, funcName string) int {
	t.Helper()
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, path, src, 0)
	if err != nil {
		t.Fatalf("parse %s: %v", path, err)
	}
	var target *ast.FuncDecl
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if ok && fn.Name.Name == funcName {
			target = fn
			break
		}
	}
	if target == nil {
		t.Fatalf("function %s not found in %s", funcName, path)
	}
	lines := strings.Split(string(src), "\n")
	start := fset.Position(target.Pos()).Line
	end := fset.Position(target.End()).Line
	count := 0
	for _, line := range lines[start-1 : end] {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "//") {
			continue
		}
		count++
	}
	return count
}

type blockedHostStart struct {
	node    *Node
	release chan struct{}
	done    chan error
	once    sync.Once
}

func startNodeWithBlockedHostCreation(t *testing.T, configure func(*Node)) *blockedHostStart {
	t.Helper()
	n := NewNode()
	if configure != nil {
		configure(n)
	}
	entered := make(chan struct{})
	release := make(chan struct{})
	done := make(chan error, 1)
	previousFactory := n.newHost
	var enteredOnce sync.Once
	n.newHost = func(cfg NodeConfig, opts []libp2p.Option) (host.Host, error) {
		enteredOnce.Do(func() { close(entered) })
		<-release
		return previousFactory(cfg, opts)
	}

	go func() {
		_, err := n.Start(NodeConfig{
			PrivateKeyHex:  generateTestKey(t),
			RelayAddresses: []string{},
			AutoRegister:   false,
		})
		done <- err
	}()

	select {
	case <-entered:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for fake host factory to be entered")
	}
	return &blockedHostStart{node: n, release: release, done: done}
}

func (b *blockedHostStart) releaseAndWait(t *testing.T) {
	t.Helper()
	b.once.Do(func() { close(b.release) })
	select {
	case err := <-b.done:
		if err != nil {
			t.Fatalf("blocked Start returned error after release: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("blocked Start did not finish after release")
	}
}

func (b *blockedHostStart) started() bool {
	b.node.mu.RLock()
	defer b.node.mu.RUnlock()
	return b.node.isStarted
}

func (b *blockedHostStart) stopIfStarted(t *testing.T) {
	t.Helper()
	if b.started() {
		if err := b.node.Stop(); err != nil {
			t.Fatalf("Stop cleanup: %v", err)
		}
	}
}

func errorCallReturnsWithin(call func() error, timeout time.Duration) (error, bool) {
	ch := make(chan error, 1)
	go func() { ch <- call() }()
	select {
	case err := <-ch:
		return err, true
	case <-time.After(timeout):
		return nil, false
	}
}

func assertNoPartialStartState(t *testing.T, n *Node) {
	t.Helper()
	n.mu.RLock()
	defer n.mu.RUnlock()
	if n.startInProgress {
		t.Fatal("startInProgress left set after failed start")
	}
	if n.isStarted || n.host != nil || n.peerId != "" {
		t.Fatalf("published start state after failed start: started=%t hostNil=%t peerId=%q", n.isStarted, n.host == nil, n.peerId)
	}
	if n.ctx != nil || n.cancel != nil {
		t.Fatal("context/cancel left published after failed start")
	}
	if n.lastConfig != nil || n.featureFlags != nil || n.namespace != "" {
		t.Fatal("config, feature flags, or namespace left published after failed start")
	}
	if len(n.relayAddresses) != 0 || len(n.relayPeerOrder) != 0 {
		t.Fatalf("relay state left published after failed start: addrs=%v order=%v", n.relayAddresses, n.relayPeerOrder)
	}
	if n.pubsub != nil || n.peerSession != nil || n.lanDialHandler != nil || n.eventSub != nil {
		t.Fatal("host-dependent state left published after failed start")
	}
	if got := len(n.relaySessionMgr.AllSessions()); got != 0 {
		t.Fatalf("relay session manager initialized %d sessions before commit, want 0", got)
	}
}

func medianDuration(count int, run func()) time.Duration {
	values := make([]time.Duration, 0, count)
	for i := 0; i < count; i++ {
		start := time.Now()
		run()
		values = append(values, time.Since(start))
	}
	sort.Slice(values, func(i, j int) bool { return values[i] < values[j] })
	return values[len(values)/2]
}

type groupDialStats struct {
	delay time.Duration

	current int64
	maxSeen int64
	total   int64

	mu              sync.Mutex
	currentByPeer   map[string]int
	maxSeenByPeer   map[string]int
	connectedByPeer map[string]int
}

func newGroupDialStats(delay time.Duration) *groupDialStats {
	return &groupDialStats{delay: delay}
}

func (s *groupDialStats) reset() {
	atomic.StoreInt64(&s.current, 0)
	atomic.StoreInt64(&s.maxSeen, 0)
	atomic.StoreInt64(&s.total, 0)
	s.mu.Lock()
	s.currentByPeer = make(map[string]int)
	s.maxSeenByPeer = make(map[string]int)
	s.connectedByPeer = make(map[string]int)
	s.mu.Unlock()
}

func (s *groupDialStats) connect(peerID string, candidateAddrs []ma.Multiaddr, allowRelayFallback bool) (groupPeerConnectResult, error) {
	trackAtomicInFlight(&s.current, &s.maxSeen, 1)
	atomic.AddInt64(&s.total, 1)
	s.mu.Lock()
	s.currentByPeer[peerID]++
	if s.currentByPeer[peerID] > s.maxSeenByPeer[peerID] {
		s.maxSeenByPeer[peerID] = s.currentByPeer[peerID]
	}
	s.mu.Unlock()

	time.Sleep(s.delay)

	s.mu.Lock()
	s.currentByPeer[peerID]--
	s.connectedByPeer[peerID]++
	s.mu.Unlock()
	trackAtomicInFlight(&s.current, &s.maxSeen, -1)
	return groupPeerConnectResult{Path: "relay"}, errors.New("fake group connect failure")
}

func (s *groupDialStats) maxInFlight() int64 {
	return atomic.LoadInt64(&s.maxSeen)
}

func (s *groupDialStats) totalCalls() int64 {
	return atomic.LoadInt64(&s.total)
}

func (s *groupDialStats) maxInFlightPerPeer() (string, int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var worstPeer string
	var worst int
	for peerID, maxSeen := range s.maxSeenByPeer {
		if maxSeen > worst {
			worst = maxSeen
			worstPeer = peerID
		}
	}
	return worstPeer, worst
}

func trackAtomicInFlight(current *int64, maxSeen *int64, delta int64) {
	next := atomic.AddInt64(current, delta)
	if delta < 0 {
		return
	}
	for {
		prev := atomic.LoadInt64(maxSeen)
		if next <= prev || atomic.CompareAndSwapInt64(maxSeen, prev, next) {
			return
		}
	}
}

func startNodeWithGroupDialTargets(t *testing.T, targetCount int) (*Node, string) {
	t.Helper()
	n := startLocalNodeForMultiRelayTest(t)
	groupID := fmt.Sprintf("libp2p-refactor-group-%d", time.Now().UnixNano())
	addGroupDialTargets(t, n, groupID, targetCount)
	return n, groupID
}

func addGroupDialTargets(t *testing.T, n *Node, groupID string, targetCount int) {
	t.Helper()
	selfID := n.PeerId()
	members := []GroupMember{
		{PeerId: selfID, Username: "self", Role: GroupRoleAdmin, PublicKey: "self-pk"},
	}
	for i := 0; i < targetCount; i++ {
		members = append(members, GroupMember{
			PeerId:    generatePeerIDStr(t),
			Username:  fmt.Sprintf("peer-%d", i),
			Role:      GroupRoleWriter,
			PublicKey: fmt.Sprintf("pk-%d", i),
		})
	}
	n.mu.Lock()
	if n.groupConfigs == nil {
		n.groupConfigs = make(map[string]*GroupConfig)
	}
	n.groupConfigs[groupID] = &GroupConfig{
		Name:      groupID,
		GroupType: GroupTypeChat,
		Members:   members,
		CreatedBy: selfID,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	}
	n.mu.Unlock()
}

func groupMemberAddrInfos(t *testing.T, config *GroupConfig) []peer.AddrInfo {
	t.Helper()
	infos := make([]peer.AddrInfo, 0, len(config.Members))
	for _, member := range config.Members {
		if member.Username == "self" {
			continue
		}
		infos = append(infos, peer.AddrInfo{ID: decodePeerID(t, member.PeerId)})
	}
	return infos
}

func decodePeerID(t *testing.T, value string) peer.ID {
	t.Helper()
	pid, err := peer.Decode(value)
	if err != nil {
		t.Fatalf("peer.Decode(%q): %v", value, err)
	}
	return pid
}
