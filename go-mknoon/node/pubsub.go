package node

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/peer"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

// initPubSub creates a new GossipSub instance attached to the node's libp2p host.
// Must be called after the host is created in Start().
//
// FloodPublish is enabled so that published messages are sent to ALL connected
// peers interested in a topic, not just the GossipSub mesh subset. This is
// critical for small groups (2–10 members) where mesh formation may be slow
// or incomplete — especially over relay circuit connections.
func (n *Node) initPubSub() error {
	ps, err := pubsub.NewGossipSub(n.ctx, n.host,
		pubsub.WithFloodPublish(true),
	)
	if err != nil {
		return fmt.Errorf("create gossipsub: %w", err)
	}
	n.pubsub = ps
	n.groupTopics = make(map[string]*pubsub.Topic)
	n.groupSubs = make(map[string]*pubsub.Subscription)
	n.groupConfigs = make(map[string]*GroupConfig)
	n.groupKeys = make(map[string]*GroupKeyInfo)
	n.groupSubCtx = make(map[string]context.CancelFunc)
	n.groupDiscoveryCtx = make(map[string]context.CancelFunc)
	return nil
}

// JoinGroupTopic joins the GossipSub topic for a group.
// It stores the config and key info, starts a subscription handler goroutine,
// and registers a topic validator.
func (n *Node) JoinGroupTopic(groupId string, config *GroupConfig, keyInfo *GroupKeyInfo) error {
	n.mu.Lock()
	defer n.mu.Unlock()

	if n.pubsub == nil {
		return fmt.Errorf("pubsub not initialized")
	}

	if _, exists := n.groupTopics[groupId]; exists {
		return fmt.Errorf("already joined group topic: %s", groupId)
	}

	topicName := GroupTopicPrefix + groupId

	// Register topic validator before joining.
	err := n.pubsub.RegisterTopicValidator(topicName, n.groupTopicValidator(groupId))
	if err != nil {
		return fmt.Errorf("register topic validator: %w", err)
	}

	topic, err := n.pubsub.Join(topicName)
	if err != nil {
		return fmt.Errorf("join topic %s: %w", topicName, err)
	}

	sub, err := topic.Subscribe()
	if err != nil {
		topic.Close()
		return fmt.Errorf("subscribe to topic %s: %w", topicName, err)
	}

	// Store config and key.
	n.groupTopics[groupId] = topic
	n.groupSubs[groupId] = sub
	n.groupConfigs[groupId] = config
	n.groupKeys[groupId] = keyInfo

	// Start subscription handler in a cancellable goroutine.
	ctx, cancel := context.WithCancel(n.ctx)
	n.groupSubCtx[groupId] = cancel
	go n.handleGroupSubscription(ctx, groupId, sub)

	// Start group peer discovery in background (register + periodic discover).
	discoveryCtx, discoveryCancel := context.WithCancel(n.ctx)
	n.groupDiscoveryCtx[groupId] = discoveryCancel
	go n.groupPeerDiscoveryLoop(discoveryCtx, groupId)

	log.Printf("[PUBSUB] Joined group topic: %s (%s)", groupId, config.Name)
	return nil
}

// LeaveGroupTopic unsubscribes from a group topic and cleans up resources.
func (n *Node) LeaveGroupTopic(groupId string) error {
	n.mu.Lock()
	defer n.mu.Unlock()

	topicName := GroupTopicPrefix + groupId

	// Cancel discovery loop (triggers rendezvous unregister).
	if cancel, ok := n.groupDiscoveryCtx[groupId]; ok {
		cancel()
		delete(n.groupDiscoveryCtx, groupId)
	}

	// Cancel subscription handler goroutine.
	if cancel, ok := n.groupSubCtx[groupId]; ok {
		cancel()
		delete(n.groupSubCtx, groupId)
	}

	// Cancel subscription.
	if sub, ok := n.groupSubs[groupId]; ok {
		sub.Cancel()
		delete(n.groupSubs, groupId)
	}

	// Close topic.
	if topic, ok := n.groupTopics[groupId]; ok {
		topic.Close()
		delete(n.groupTopics, groupId)
	}

	// Unregister validator.
	_ = n.pubsub.UnregisterTopicValidator(topicName)

	// Remove config and key.
	delete(n.groupConfigs, groupId)
	delete(n.groupKeys, groupId)

	log.Printf("[PUBSUB] Left group topic: %s", groupId)
	return nil
}

// PublishGroupMessage encrypts, signs, and publishes a message to a group topic.
// Returns the message ID (UUID).
func (n *Node) PublishGroupMessage(groupId, privateKeyB64, senderPeerId, senderPublicKeyB64, senderUsername, text string, opts map[string]interface{}) (string, error) {
	n.mu.RLock()
	topic, topicOk := n.groupTopics[groupId]
	config, configOk := n.groupConfigs[groupId]
	keyInfo, keyOk := n.groupKeys[groupId]
	n.mu.RUnlock()

	if !topicOk || !configOk || !keyOk {
		return "", fmt.Errorf("group not joined: %s", groupId)
	}

	// Check write permission.
	if !isAllowedWriter(config, senderPeerId) {
		return "", fmt.Errorf("sender %s not allowed to write in group %s", senderPeerId, groupId)
	}

	// 1. Build GroupMessagePayload.
	msgId := uuid.New().String()
	timestamp := time.Now().UTC().Format(time.RFC3339Nano)

	payload := &internal.GroupMessagePayload{
		Text:      text,
		Timestamp: timestamp,
		Username:  senderUsername,
	}

	payloadJSON, err := internal.MarshalGroupPayload(payload)
	if err != nil {
		return "", fmt.Errorf("marshal payload: %w", err)
	}

	// 2. Encrypt payload with group key.
	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(keyInfo.Key, payloadJSON)
	if err != nil {
		return "", fmt.Errorf("encrypt group message: %w", err)
	}

	// 3. Build signature data and sign.
	sigData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, ctB64)
	signature, err := mcrypto.SignPayload(privateKeyB64, sigData)
	if err != nil {
		return "", fmt.Errorf("sign group message: %w", err)
	}

	// 4. Build GroupEnvelope (v3).
	envelope := &internal.GroupEnvelope{
		Version:         "3",
		Type:            "group_message",
		GroupId:         groupId,
		SenderId:        senderPeerId,
		SenderPublicKey: senderPublicKeyB64,
		Signature:       signature,
		KeyEpoch:        keyInfo.KeyEpoch,
		Encrypted: internal.GroupEncryptedPayload{
			Ciphertext: ctB64,
			Nonce:      nonceB64,
		},
	}

	envelopeJSON, err := internal.MarshalGroupEnvelope(envelope)
	if err != nil {
		return "", fmt.Errorf("marshal envelope: %w", err)
	}

	// 5. Publish to topic.
	ctx, cancel := context.WithTimeout(n.ctx, PubSubTimeout)
	defer cancel()

	// Log peer count for diagnostics — if 0, no peers will receive the message.
	topicPeers := topic.ListPeers()
	log.Printf("[PUBSUB] Publishing message %s to group %s (peers in topic: %d)", msgId, groupId, len(topicPeers))

	if err := topic.Publish(ctx, []byte(envelopeJSON)); err != nil {
		return "", fmt.Errorf("publish to topic: %w", err)
	}

	n.emitEvent("group:publish_debug", map[string]interface{}{
		"groupId":    groupId,
		"messageId":  msgId,
		"topicPeers": len(topicPeers),
	})

	return msgId, nil
}

// UpdateGroupConfig updates the stored group configuration.
func (n *Node) UpdateGroupConfig(groupId string, config *GroupConfig) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.groupConfigs[groupId] = config
}

// UpdateGroupKey updates the stored group encryption key.
func (n *Node) UpdateGroupKey(groupId string, keyInfo *GroupKeyInfo) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.groupKeys[groupId] = keyInfo
}

// GetGroupKeyInfo returns the current key info for a group, or nil if not found.
func (n *Node) GetGroupKeyInfo(groupId string) *GroupKeyInfo {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.groupKeys[groupId]
}

// groupTopicValidator returns a topic validator function for a group topic.
// It verifies the message is a valid v3 group envelope, the sender is a
// member, and the signature is valid. For announcement groups, only
// admin-role members may publish.
//
// The returned function matches pubsub.ValidatorEx signature:
//
//	func(ctx context.Context, pid peer.ID, msg *pubsub.Message) pubsub.ValidationResult
func (n *Node) groupTopicValidator(groupId string) func(context.Context, peer.ID, *pubsub.Message) pubsub.ValidationResult {
	return func(ctx context.Context, pid peer.ID, msg *pubsub.Message) pubsub.ValidationResult {
		data := string(msg.Data)

		// 1. Must be a v3 group envelope.
		if !internal.IsGroupEnvelope(data) {
			log.Printf("[PUBSUB] Validator: rejecting non-v3 message on group %s", groupId)
			return pubsub.ValidationReject
		}

		// 2. Parse envelope.
		env, err := internal.ParseGroupEnvelope(data)
		if err != nil {
			log.Printf("[PUBSUB] Validator: rejecting invalid envelope on group %s: %v", groupId, err)
			return pubsub.ValidationReject
		}

		// 3. Verify groupId matches.
		if env.GroupId != groupId {
			log.Printf("[PUBSUB] Validator: rejecting mismatched groupId: got %s, want %s", env.GroupId, groupId)
			return pubsub.ValidationReject
		}

		// 4. Look up group config.
		n.mu.RLock()
		config, ok := n.groupConfigs[groupId]
		n.mu.RUnlock()
		if !ok {
			log.Printf("[PUBSUB] Validator: rejecting message for unknown group %s", groupId)
			return pubsub.ValidationReject
		}

		// 5. Find sender in members list.
		member := findMember(config, env.SenderId)
		if member == nil {
			log.Printf("[PUBSUB] Validator: rejecting message from non-member %s in group %s", env.SenderId, groupId)
			return pubsub.ValidationReject
		}

		// 6. For announcement groups: only admin can publish.
		if !isAllowedWriter(config, env.SenderId) {
			log.Printf("[PUBSUB] Validator: rejecting message from non-admin %s in announcement group %s", env.SenderId, groupId)
			return pubsub.ValidationReject
		}

		// 7. Verify signature.
		n.mu.RLock()
		keyInfo, keyOk := n.groupKeys[groupId]
		n.mu.RUnlock()
		if !keyOk {
			log.Printf("[PUBSUB] Validator: no key info for group %s", groupId)
			return pubsub.ValidationReject
		}

		sigData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, env.Encrypted.Ciphertext)
		valid, err := mcrypto.VerifyPayload(member.PublicKey, sigData, env.Signature)
		if err != nil || !valid {
			log.Printf("[PUBSUB] Validator: invalid signature from %s in group %s: %v", env.SenderId, groupId, err)
			return pubsub.ValidationReject
		}

		return pubsub.ValidationAccept
	}
}

// handleGroupSubscription reads messages from the subscription and emits them
// as events to Flutter. Messages from self are skipped.
func (n *Node) handleGroupSubscription(ctx context.Context, groupId string, sub *pubsub.Subscription) {
	for {
		msg, err := sub.Next(ctx)
		if err != nil {
			if ctx.Err() != nil {
				// Context cancelled — normal shutdown.
				return
			}
			log.Printf("[PUBSUB] Subscription error for group %s: %v", groupId, err)
			return
		}

		// Skip messages from self.
		n.mu.RLock()
		selfPeerId := n.peerId
		keyInfo, keyOk := n.groupKeys[groupId]
		n.mu.RUnlock()

		data := string(msg.Data)

		// Parse envelope to get sender.
		env, err := internal.ParseGroupEnvelope(data)
		if err != nil {
			log.Printf("[PUBSUB] Failed to parse envelope from group %s: %v", groupId, err)
			continue
		}

		if env.SenderId == selfPeerId {
			continue
		}

		if !keyOk {
			log.Printf("[PUBSUB] No key info for group %s, skipping message", groupId)
			continue
		}

		// Decrypt the payload.
		plaintext, err := mcrypto.DecryptGroupMessage(keyInfo.Key, env.Encrypted.Ciphertext, env.Encrypted.Nonce)
		if err != nil {
			log.Printf("[PUBSUB] Failed to decrypt message in group %s: %v", groupId, err)
			continue
		}

		// Parse inner payload.
		payload, err := internal.ParseGroupPayload(plaintext)
		if err != nil {
			log.Printf("[PUBSUB] Failed to parse payload in group %s: %v", groupId, err)
			continue
		}

		// Emit event to Flutter.
		n.emitEvent("group_message:received", map[string]interface{}{
			"groupId":        groupId,
			"senderId":       env.SenderId,
			"senderUsername": payload.Username,
			"keyEpoch":       env.KeyEpoch,
			"text":           payload.Text,
			"timestamp":      payload.Timestamp,
		})
	}
}

// isAllowedWriter checks whether a peer is allowed to publish messages
// in the group based on the group type and the member's role.
// For chat/qa groups: any member can write.
// For announcement groups: only admin-role members can write.
func isAllowedWriter(config *GroupConfig, senderId string) bool {
	member := findMember(config, senderId)
	if member == nil {
		return false
	}

	if config.GroupType == GroupTypeAnnouncement {
		return member.Role == GroupRoleAdmin
	}

	// chat and qa: any member can write
	return true
}

// groupRendezvousNamespace returns the rendezvous namespace for a group.
// Group members register/discover each other on this namespace so that
// GossipSub can form a mesh for the group topic.
func groupRendezvousNamespace(groupId string) string {
	return GroupTopicPrefix + groupId
}

// filterDiscoveredPeers returns peers that are not self and not already connected.
func filterDiscoveredPeers(discovered []peer.AddrInfo, selfId peer.ID, connectedPeers map[peer.ID]struct{}) []peer.AddrInfo {
	var result []peer.AddrInfo
	for _, p := range discovered {
		if p.ID == selfId {
			continue
		}
		if _, connected := connectedPeers[p.ID]; connected {
			continue
		}
		result = append(result, p)
	}
	return result
}

// discoverAndConnectGroupPeers discovers peers on the group rendezvous namespace
// and dials any that are not already connected. For each new peer, it first adds
// the discovered addresses to the peerstore (so h.Connect has more options), then
// dials via relay circuit. Errors are logged and emitted as events, not returned,
// because discovery is best-effort.
func (n *Node) discoverAndConnectGroupPeers(groupId string) {
	ns := groupRendezvousNamespace(groupId)
	peers, err := n.RendezvousDiscover(ns, nil)
	if err != nil {
		log.Printf("[PUBSUB] Group %s discover failed: %v", groupId, err)
		n.emitEvent("group:discovery", map[string]interface{}{
			"groupId": groupId,
			"step":    "discover_failed",
			"error":   err.Error(),
		})
		return
	}

	// Build set of already-connected peers.
	n.mu.RLock()
	h := n.host
	selfId := n.host.ID()
	n.mu.RUnlock()

	connectedSet := make(map[peer.ID]struct{})
	for _, pid := range h.Network().Peers() {
		connectedSet[pid] = struct{}{}
	}

	newPeers := filterDiscoveredPeers(peers, selfId, connectedSet)

	n.emitEvent("group:discovery", map[string]interface{}{
		"groupId":       groupId,
		"step":          "discover_result",
		"totalFound":    len(peers),
		"newPeers":      len(newPeers),
		"alreadyConnected": len(peers) - len(newPeers),
	})

	if len(newPeers) == 0 {
		return
	}

	log.Printf("[PUBSUB] Group %s: discovered %d peers, %d new — dialing", groupId, len(peers), len(newPeers))

	for _, p := range newPeers {
		pidStr := p.ID.String()
		pidShort := pidStr
		if len(pidShort) > 16 {
			pidShort = pidShort[:16]
		}

		// Add discovered addresses to peerstore so h.Connect can use them.
		if len(p.Addrs) > 0 {
			h.Peerstore().AddAddrs(p.ID, p.Addrs, time.Hour)
			log.Printf("[PUBSUB] Group %s: added %d discovered addrs for %s", groupId, len(p.Addrs), pidShort)
		}

		// Dial via relay circuit — this is the primary path for mobile peers.
		if err := n.DialPeerViaRelay(pidStr); err != nil {
			log.Printf("[PUBSUB] Group %s: relay dial %s failed: %v", groupId, pidShort, err)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId": groupId,
				"step":    "dial_failed",
				"peerId":  pidShort,
				"error":   err.Error(),
			})
		} else {
			log.Printf("[PUBSUB] Group %s: connected to %s via relay", groupId, pidShort)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId": groupId,
				"step":    "dial_success",
				"peerId":  pidShort,
			})
		}
	}
}

// dialKnownGroupMembers dials all group members directly via relay circuit.
// This is the primary connectivity path: since group configs contain all member
// peer IDs, we can dial them directly without depending on rendezvous discovery.
// Already-connected peers are skipped. Errors are logged per-member and do not
// prevent dialing other members.
func (n *Node) dialKnownGroupMembers(groupId string) {
	n.mu.RLock()
	config, ok := n.groupConfigs[groupId]
	h := n.host
	selfId := ""
	if h != nil {
		selfId = h.ID().String()
	}
	n.mu.RUnlock()

	if !ok || h == nil {
		return
	}

	// Build set of already-connected peers.
	connectedSet := make(map[string]struct{})
	for _, pid := range h.Network().Peers() {
		connectedSet[pid.String()] = struct{}{}
	}

	dialed := 0
	connected := 0
	for _, member := range config.Members {
		if member.PeerId == selfId {
			continue
		}
		if _, alreadyConnected := connectedSet[member.PeerId]; alreadyConnected {
			connected++
			continue
		}

		pidShort := member.PeerId
		if len(pidShort) > 16 {
			pidShort = pidShort[:16]
		}

		dialed++
		if err := n.DialPeerViaRelay(member.PeerId); err != nil {
			log.Printf("[PUBSUB] Group %s: direct dial %s (%s) failed: %v", groupId, member.Username, pidShort, err)
		} else {
			connected++
			log.Printf("[PUBSUB] Group %s: connected to %s (%s) via relay", groupId, member.Username, pidShort)
		}
	}

	n.emitEvent("group:discovery", map[string]interface{}{
		"groupId":          groupId,
		"step":             "direct_dial",
		"membersDialed":    dialed,
		"membersConnected": connected,
		"totalMembers":     len(config.Members),
	})
}

// groupPeerDiscoveryLoop runs periodic peer discovery for a group.
// It waits for a circuit relay address to appear (so the peer record includes
// the relay address), then uses two strategies to connect to group peers:
// 1. Direct relay dialing: dials known group members by peer ID via relay circuit
// 2. Rendezvous: registers/discovers on group namespace (backup for unknown peers)
//
// Direct dialing is the primary path since all member peer IDs are in the config.
// On context cancellation it unregisters from the namespace (best-effort).
func (n *Node) groupPeerDiscoveryLoop(ctx context.Context, groupId string) {
	ns := groupRendezvousNamespace(groupId)

	// Wait for relay to be ready before dialing/registering.
	select {
	case <-n.relayReady:
	case <-ctx.Done():
		return
	}

	// Wait for circuit address so peer record includes relay address.
	n.waitForCircuitAddress(10 * time.Second)

	// Primary strategy: dial known group members directly via relay.
	n.dialKnownGroupMembers(groupId)

	// Secondary strategy: register on rendezvous for discoverability.
	if err := n.RendezvousRegister(ns, nil); err != nil {
		log.Printf("[PUBSUB] Group %s: rendezvous register failed: %v", groupId, err)
		n.emitEvent("group:discovery", map[string]interface{}{
			"groupId": groupId,
			"step":    "register_failed",
			"error":   err.Error(),
		})
	} else {
		log.Printf("[PUBSUB] Group %s: registered on rendezvous ns=%s", groupId, ns)
		n.emitEvent("group:discovery", map[string]interface{}{
			"groupId": groupId,
			"step":    "registered",
		})
	}

	// Initial rendezvous discovery (may find peers that joined after config was set).
	n.discoverAndConnectGroupPeers(groupId)

	ticker := time.NewTicker(GroupDiscoveryInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			// Best-effort unregister.
			if err := n.RendezvousUnregister(ns, nil); err != nil {
				log.Printf("[PUBSUB] Group %s: rendezvous unregister failed: %v", groupId, err)
			}
			return
		case <-ticker.C:
			// Re-dial known members (handles reconnection after disconnect)
			// and rendezvous discover (handles new members).
			n.dialKnownGroupMembers(groupId)
			n.discoverAndConnectGroupPeers(groupId)
		}
	}
}

// findMember returns the GroupMember with the given peerId, or nil if not found.
func findMember(config *GroupConfig, peerId string) *GroupMember {
	for i := range config.Members {
		if config.Members[i].PeerId == peerId {
			return &config.Members[i]
		}
	}
	return nil
}
