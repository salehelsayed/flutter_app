package node

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"runtime/pprof"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

func TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	exitedPrivB64, exitedPubB64 := generateEd25519KeyPair(t)
	_, remainingPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForUnsubscribeExitPathWithCollector(t, nodeBCapture)
	nodeCCapture := &testEventCollector{}
	nodeC := startLocalNodeForUnsubscribeExitPathWithCollector(t, nodeCCapture)

	groupId := "lp003-leave-stops-live-delivery"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "LP003 Exit Proof",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: exitedPubB64},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: remainingPubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", n.PeerId(), err)
		}
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeC)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)

	preExitMessageId := "lp003-pre-exit-normal"
	if msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"LP003 pre-exit message",
		preExitMessageId,
		nil,
	); err != nil {
		t.Fatalf("pre-exit PublishGroupMessage: %v", err)
	} else if msgID != preExitMessageId || peerCount < 2 {
		t.Fatalf("pre-exit publish result msgID=%q peerCount=%d, want msgID=%q peerCount>=2", msgID, peerCount, preExitMessageId)
	}
	waitForCollectedEventContaining(t, nodeBCapture, preExitMessageId, 5*time.Second)
	waitForCollectedEventContaining(t, nodeCCapture, preExitMessageId, 5*time.Second)

	if err := nodeB.LeaveGroupTopic(groupId); err != nil {
		t.Fatalf("nodeB LeaveGroupTopic: %v", err)
	}
	assertLP003GroupPubSubStateRemoved(t, nodeB, groupId)

	time.Sleep(150 * time.Millisecond)
	nodeBExitedBaseline := len(nodeBCapture.snapshot())

	postExitMessageId := "lp003-post-exit-normal"
	if msgID, _, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"LP003 post-exit normal message",
		postExitMessageId,
		nil,
	); err != nil {
		t.Fatalf("post-exit PublishGroupMessage: %v", err)
	} else if msgID != postExitMessageId {
		t.Fatalf("post-exit message ID = %q, want %q", msgID, postExitMessageId)
	}
	waitForCollectedEventCount(t, nodeCCapture, "group_message:received", 2, 5*time.Second)
	waitForCollectedEventContaining(t, nodeCCapture, postExitMessageId, 5*time.Second)

	reactionJSON := `{"messageId":"` + postExitMessageId + `","action":"add","emoji":"+1","sentinel":"lp003-post-exit-reaction"}`
	if err := nodeA.PublishGroupReaction(groupId, senderPrivB64, nodeA.PeerId(), senderPubB64, reactionJSON); err != nil {
		t.Fatalf("post-exit PublishGroupReaction: %v", err)
	}
	waitForCollectedEventCount(t, nodeCCapture, "group_reaction:received", 1, 5*time.Second)
	waitForCollectedEventContaining(t, nodeCCapture, "lp003-post-exit-reaction", 5*time.Second)

	parseFailureEnvelope := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeA.PeerId(),
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"not-json",
	)
	publishRawGroupEnvelope(t, nodeA, groupId, parseFailureEnvelope)
	waitForCollectedEventCount(t, nodeCCapture, "group:payload_parse_failed", 1, 5*time.Second)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		nodeA.PeerId(),
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"LP003 decrypt failure seed",
	)
	decryptFailureEnvelope := mutateAndResignGroupEnvelope(t, validEnvelope, senderPrivB64, func(env *internal.GroupEnvelope) {
		ciphertextBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Ciphertext)
		if err != nil {
			t.Fatalf("decode ciphertext: %v", err)
		}
		ciphertextBytes[0] ^= 0xFF
		env.Encrypted.Ciphertext = base64.StdEncoding.EncodeToString(ciphertextBytes)
	})
	publishRawGroupEnvelope(t, nodeA, groupId, decryptFailureEnvelope)
	waitForCollectedEventCount(t, nodeCCapture, "group:decryption_failed", 1, 5*time.Second)

	assertLP003NoExitedGroupEventsAfter(t, nodeBCapture, nodeBExitedBaseline, 900*time.Millisecond)

	if _, _, err := nodeB.PublishGroupMessage(
		groupId,
		exitedPrivB64,
		nodeB.PeerId(),
		exitedPubB64,
		"Bob",
		"LP003 exited peer should not publish",
		"",
		nil,
	); err == nil || !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("exited PublishGroupMessage error = %v, want group not joined", err)
	}
	if err := nodeB.PublishGroupReaction(
		groupId,
		exitedPrivB64,
		nodeB.PeerId(),
		exitedPubB64,
		`{"messageId":"lp003-post-exit-normal","action":"add","emoji":"+1"}`,
	); err == nil || !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("exited PublishGroupReaction error = %v, want group not joined", err)
	}
}

func TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	leaverPrivB64, leaverPubB64 := generateEd25519KeyPair(t)
	_, remainingPubB64 := generateEd25519KeyPair(t)
	_, missingPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	leaverEvents := &testEventCollector{}
	nodeB := startLocalNodeForUnsubscribeExitPathWithCollector(t, leaverEvents)
	nodeC := startLocalNodeForMultiRelayTest(t)
	missingMember := startLocalNodeForMultiRelayTest(t)

	groupId := "gl008-leave-stops-discovery-inbound"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GL008 Leave Stops Discovery",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: leaverPubB64},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: remainingPubB64},
			{PeerId: missingMember.PeerId(), Role: GroupRoleWriter, PublicKey: missingPubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}

	nodeB.waitForCircuitAddressHook = func(timeout time.Duration) bool { return true }
	nodeB.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error { return nil }
	nodeB.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		return nil, nil
	}
	nodeB.relayReadyOnce.Do(func() { close(nodeB.relayReady) })

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", n.PeerId(), err)
		}
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeC)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)
	waitForGL008DiscoveryStep(t, leaverEvents, groupId, "discover_result", 6*time.Second)

	preLeaveMessageId := "gl008-pre-leave-live-message"
	if msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"GL008 pre-leave live message",
		preLeaveMessageId,
		nil,
	); err != nil {
		t.Fatalf("pre-leave PublishGroupMessage: %v", err)
	} else if msgID != preLeaveMessageId || peerCount < 2 {
		t.Fatalf("pre-leave publish result msgID=%q peerCount=%d, want msgID=%q peerCount>=2", msgID, peerCount, preLeaveMessageId)
	}
	waitForCollectedEventContaining(t, leaverEvents, preLeaveMessageId, 5*time.Second)

	if err := nodeB.LeaveGroupTopic(groupId); err != nil {
		t.Fatalf("nodeB LeaveGroupTopic: %v", err)
	}
	assertLP003GroupPubSubStateRemoved(t, nodeB, groupId)

	time.Sleep(150 * time.Millisecond)
	postLeaveBaseline := len(leaverEvents.snapshot())

	if _, _, err := nodeB.PublishGroupMessage(
		groupId,
		leaverPrivB64,
		nodeB.PeerId(),
		leaverPubB64,
		"Bob",
		"GL008 leaver should not publish",
		"",
		nil,
	); err == nil || !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("leaver PublishGroupMessage error = %v, want group not joined", err)
	}
	if err := nodeB.PublishGroupReaction(
		groupId,
		leaverPrivB64,
		nodeB.PeerId(),
		leaverPubB64,
		`{"messageId":"gl008-post-leave-live-message","action":"add","emoji":"+1"}`,
	); err == nil || !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("leaver PublishGroupReaction error = %v, want group not joined", err)
	}

	postLeaveMessageId := "gl008-post-leave-live-message"
	if msgID, _, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"GL008 post-leave live message",
		postLeaveMessageId,
		nil,
	); err != nil {
		t.Fatalf("post-leave PublishGroupMessage: %v", err)
	} else if msgID != postLeaveMessageId {
		t.Fatalf("post-leave message ID = %q, want %q", msgID, postLeaveMessageId)
	}
	if err := nodeA.PublishGroupReaction(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		`{"messageId":"gl008-post-leave-live-message","action":"add","emoji":"+1","sentinel":"gl008-post-leave-reaction"}`,
	); err != nil {
		t.Fatalf("post-leave PublishGroupReaction: %v", err)
	}

	parseFailureEnvelope := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeA.PeerId(),
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"not-json",
	)
	publishRawGroupEnvelope(t, nodeA, groupId, parseFailureEnvelope)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		nodeA.PeerId(),
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"GL008 decrypt failure seed",
	)
	decryptFailureEnvelope := mutateAndResignGroupEnvelope(t, validEnvelope, senderPrivB64, func(env *internal.GroupEnvelope) {
		ciphertextBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Ciphertext)
		if err != nil {
			t.Fatalf("decode ciphertext: %v", err)
		}
		ciphertextBytes[0] ^= 0xFF
		env.Encrypted.Ciphertext = base64.StdEncoding.EncodeToString(ciphertextBytes)
	})
	publishRawGroupEnvelope(t, nodeA, groupId, decryptFailureEnvelope)

	assertGL008NoPostLeaveGroupActivity(t, leaverEvents, postLeaveBaseline, groupId, 4*time.Second)
}

func TestGP010DiscoveryLoopUnregistersOnceAndStopsAfterLeave(t *testing.T) {
	selfPrivB64, selfPubB64 := generateEd25519KeyPair(t)
	_, otherPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	collector := &testEventCollector{}
	n := startLocalNodeForUnsubscribeExitPathWithCollector(t, collector)
	other := startLocalNodeForMultiRelayTest(t)

	groupId := "gp010-discovery-unregisters-on-leave"
	expectedNamespace := groupRendezvousNamespace(groupId)
	registeredNamespaces := make(chan string, 2)
	unregisteredNamespaces := make(chan string, 2)
	var discoverCalls atomic.Int32

	n.waitForCircuitAddressHook = func(timeout time.Duration) bool { return true }
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registeredNamespaces <- namespace
		return nil
	}
	n.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		discoverCalls.Add(1)
		return nil, nil
	}
	n.rendezvousUnregisterHook = func(namespace string, serverAddresses []string) error {
		unregisteredNamespaces <- namespace
		return nil
	}
	n.relayReadyOnce.Do(func() { close(n.relayReady) })

	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GP010 Unregister Proof",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: selfPubB64},
			{PeerId: other.PeerId(), Role: GroupRoleWriter, PublicKey: otherPubB64},
		},
		CreatedBy: n.PeerId(),
	}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	select {
	case namespace := <-registeredNamespaces:
		if namespace != expectedNamespace {
			t.Fatalf("registered namespace = %q, want %q", namespace, expectedNamespace)
		}
	case <-time.After(6 * time.Second):
		t.Fatalf("timed out waiting for GP-010 group rendezvous register; events=%v", collector.snapshot())
	}
	waitForCollectedEventContaining(t, collector, `"step":"registered"`, time.Second)
	if got := discoverCalls.Load(); got == 0 {
		t.Fatal("expected discovery loop to execute at least one discover before leave")
	}

	if _, _, err := n.PublishGroupMessage(
		groupId,
		selfPrivB64,
		n.PeerId(),
		selfPubB64,
		"Alice",
		"GP010 pre-leave sanity publish",
		"gp010-pre-leave-sanity",
		nil,
	); err != nil {
		t.Fatalf("pre-leave PublishGroupMessage should still be allowed before leave: %v", err)
	}

	if err := n.LeaveGroupTopic(groupId); err != nil {
		t.Fatalf("LeaveGroupTopic: %v", err)
	}
	assertLP003GroupPubSubStateRemoved(t, n, groupId)

	select {
	case namespace := <-unregisteredNamespaces:
		if namespace != expectedNamespace {
			t.Fatalf("unregistered namespace = %q, want %q", namespace, expectedNamespace)
		}
	case <-time.After(time.Second):
		t.Fatalf("timed out waiting for GP-010 rendezvous unregister; events=%v", collector.snapshot())
	}

	select {
	case namespace := <-unregisteredNamespaces:
		t.Fatalf("RendezvousUnregister called more than once; second namespace=%q", namespace)
	case <-time.After(250 * time.Millisecond):
	}

	postLeaveDiscoverCalls := discoverCalls.Load()
	postLeaveBaseline := len(collector.snapshot())
	assertGL008NoPostLeaveGroupActivity(t, collector, postLeaveBaseline, groupId, 750*time.Millisecond)
	if got := discoverCalls.Load(); got != postLeaveDiscoverCalls {
		t.Fatalf("discovery continued after leave: discover calls before=%d after=%d", postLeaveDiscoverCalls, got)
	}
}

func TestGO010JoinLeaveRecoveryCyclesDoNotLeakGroupGoroutines(t *testing.T) {
	selfPrivB64, selfPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	collector := &testEventCollector{}
	n := startLocalNodeForUnsubscribeExitPathWithCollector(t, collector)

	baseline, baselineStacks := go010GroupRuntimeGoroutineSnapshot()
	if baseline != 0 {
		t.Logf("GO-010 baseline group runtime goroutines=%d:\n%s", baseline, baselineStacks)
	}

	var registered atomic.Int32
	var discovered atomic.Int32
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registered.Add(1)
		return nil
	}
	n.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		discovered.Add(1)
		return nil, nil
	}
	n.rendezvousUnregisterHook = func(namespace string, serverAddresses []string) error {
		return nil
	}

	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	for i := 0; i < 4; i++ {
		groupId := fmt.Sprintf("go010-join-leave-recovery-%02d", i)
		config := &GroupConfig{
			Name:      "GO010 Leak Check",
			GroupType: GroupTypeChat,
			Members: []GroupMember{
				{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: selfPubB64},
			},
			CreatedBy: n.PeerId(),
		}

		if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
			t.Fatalf("JoinGroupTopic(%s): %v", groupId, err)
		}

		executed, cycleRegistered := n.runGroupDiscoveryCycle(
			n.ctx,
			groupId,
			groupRendezvousNamespace(groupId),
			true,
			false,
		)
		if !executed || !cycleRegistered {
			t.Fatalf("GO-010 recovery cycle %s executed=%t registered=%t, want true/true", groupId, executed, cycleRegistered)
		}

		if _, _, err := n.PublishGroupMessage(
			groupId,
			selfPrivB64,
			n.PeerId(),
			selfPubB64,
			"Alice",
			"GO-010 pre-leave sanity publish",
			fmt.Sprintf("go010-pre-leave-%02d", i),
			nil,
		); err != nil {
			t.Fatalf("PublishGroupMessage(%s) before leave: %v", groupId, err)
		}

		if err := n.LeaveGroupTopic(groupId); err != nil {
			t.Fatalf("LeaveGroupTopic(%s): %v", groupId, err)
		}
		assertLP003GroupPubSubStateRemoved(t, n, groupId)
		waitForGO010GroupRuntimeGoroutinesAtMost(t, baseline, 2*time.Second)

		n.mu.RLock()
		heldRecoverySlots := len(n.groupRecoverySem)
		n.mu.RUnlock()
		if heldRecoverySlots != 0 {
			t.Fatalf("group recovery slots held after cycle %d = %d, want 0", i, heldRecoverySlots)
		}
	}

	if got := registered.Load(); got != 4 {
		t.Fatalf("registered recovery cycles = %d, want 4", got)
	}
	if got := discovered.Load(); got != 4 {
		t.Fatalf("discovered recovery cycles = %d, want 4", got)
	}

	if err := n.Stop(); err != nil {
		t.Fatalf("Stop after GO-010 cycles: %v", err)
	}
	waitForGO010GroupRuntimeGoroutinesAtMost(t, baseline, 2*time.Second)
}

func waitForGO010GroupRuntimeGoroutinesAtMost(t *testing.T, max int, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	lastCount := 0
	lastStacks := ""
	for {
		lastCount, lastStacks = go010GroupRuntimeGoroutineSnapshot()
		if lastCount <= max {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("GO-010 group runtime goroutines = %d, want <= %d after %v\n%s", lastCount, max, timeout, lastStacks)
		}
		time.Sleep(25 * time.Millisecond)
	}
}

func go010GroupRuntimeGoroutineSnapshot() (int, string) {
	var buf bytes.Buffer
	if err := pprof.Lookup("goroutine").WriteTo(&buf, 2); err != nil {
		return 0, fmt.Sprintf("goroutine profile failed: %v", err)
	}

	var matches []string
	for _, block := range strings.Split(buf.String(), "\n\n") {
		if strings.Contains(block, "github.com/mknoon/go-mknoon/node.(*Node).handleGroupSubscription") ||
			strings.Contains(block, "github.com/mknoon/go-mknoon/node.(*Node).groupPeerDiscoveryLoop") ||
			strings.Contains(block, "github.com/mknoon/go-mknoon/node.(*Node).runGroupDiscoveryCycle") ||
			strings.Contains(block, "github.com/mknoon/go-mknoon/node.(*Node).discoverAndConnectGroupPeers") {
			matches = append(matches, strings.TrimSpace(block))
		}
	}

	return len(matches), strings.Join(matches, "\n\n")
}

func startLocalNodeForUnsubscribeExitPathWithCollector(t *testing.T, collector *testEventCollector) *Node {
	t.Helper()

	hexKey := generateTestKey(t)
	n := New(collector)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { n.Stop() })
	return n
}

func assertLP003GroupPubSubStateRemoved(t *testing.T, n *Node, groupId string) {
	t.Helper()

	n.mu.RLock()
	_, hasTopic := n.groupTopics[groupId]
	_, hasSub := n.groupSubs[groupId]
	_, hasSubCtx := n.groupSubCtx[groupId]
	_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupId]
	_, hasConfig := n.groupConfigs[groupId]
	_, hasKey := n.groupKeys[groupId]
	n.mu.RUnlock()

	if hasTopic || hasSub || hasSubCtx || hasDiscoveryCtx || hasConfig || hasKey {
		t.Fatalf(
			"leave should remove all pubsub state, got topic=%t sub=%t subCtx=%t discoveryCtx=%t config=%t key=%t",
			hasTopic,
			hasSub,
			hasSubCtx,
			hasDiscoveryCtx,
			hasConfig,
			hasKey,
		)
	}
}

func waitForGL008DiscoveryStep(t *testing.T, collector *testEventCollector, groupId, step string, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		for _, event := range collector.collectEvents("group:discovery") {
			if event["groupId"] == groupId && event["step"] == step {
				return
			}
		}
		time.Sleep(25 * time.Millisecond)
	}

	t.Fatalf("timed out waiting for GL-008 discovery step %q for group %s; events=%v", step, groupId, collector.snapshot())
}

func assertGL008NoPostLeaveGroupActivity(t *testing.T, collector *testEventCollector, baseline int, groupId string, timeout time.Duration) {
	t.Helper()

	disallowedInboundEvents := map[string]struct{}{
		"group_message:received":     {},
		"group_reaction:received":    {},
		"group:payload_parse_failed": {},
		"group:decryption_failed":    {},
	}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		events := collector.snapshot()
		for _, raw := range events[baseline:] {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &payload); err != nil {
				continue
			}
			data, _ := payload["data"].(map[string]interface{})
			if data["groupId"] != groupId {
				continue
			}
			eventName, _ := payload["event"].(string)
			if _, disallowed := disallowedInboundEvents[eventName]; disallowed {
				t.Fatalf("leaver received disallowed post-leave inbound event %q after baseline %d: %s", eventName, baseline, raw)
			}
			if eventName == "group:discovery" {
				step, _ := data["step"].(string)
				if gl008DiscoveryStepRepresentsWork(step) {
					t.Fatalf("leaver emitted disallowed post-leave discovery step %q after baseline %d: %s", step, baseline, raw)
				}
			}
		}
		time.Sleep(25 * time.Millisecond)
	}
}

func gl008DiscoveryStepRepresentsWork(step string) bool {
	switch step {
	case "registered",
		"register_failed",
		"discover_failed",
		"discover_result",
		"direct_dial",
		"pre_relay_direct_dial",
		"initial_jitter",
		"backoff",
		"publish_peer_refresh_begin",
		"publish_peer_refresh_done":
		return true
	}
	return strings.HasPrefix(step, "known_member_") ||
		strings.HasPrefix(step, "dial_") ||
		strings.HasPrefix(step, "direct_dial_")
}

func assertLP003NoExitedGroupEventsAfter(t *testing.T, collector *testEventCollector, baseline int, timeout time.Duration) {
	t.Helper()

	disallowed := []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:payload_parse_failed"`,
		`"event":"group:decryption_failed"`,
	}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		events := collector.snapshot()
		for _, raw := range events[baseline:] {
			for _, marker := range disallowed {
				if strings.Contains(raw, marker) {
					t.Fatalf("exited peer received disallowed post-exit event %s after baseline %d: %s", marker, baseline, raw)
				}
			}
		}
		time.Sleep(25 * time.Millisecond)
	}
}
