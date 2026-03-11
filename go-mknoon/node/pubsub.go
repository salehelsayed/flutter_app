package node

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"strings"
	"time"

	"github.com/google/uuid"
	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"

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
// Returns the message ID (UUID). If messageId is non-empty, it is used instead
// of generating a new one — this allows the sender to reference the same ID locally.
func (n *Node) PublishGroupMessage(groupId, privateKeyB64, senderPeerId, senderPublicKeyB64, senderUsername, text, messageId string, opts map[string]interface{}) (string, error) {
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
	msgId := messageId
	if msgId == "" {
		msgId = uuid.New().String()
	}
	timestamp := time.Now().UTC().Format(time.RFC3339Nano)

	payload := &internal.GroupMessagePayload{
		Text:      text,
		Timestamp: timestamp,
		Username:  senderUsername,
		Extra:     buildGroupMessageExtra(msgId, opts),
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

// PublishGroupReaction encrypts, signs, and publishes a reaction to a group topic.
// The reactionJSON is the raw JSON payload (id, messageId, emoji, action, etc.)
// that gets encrypted inside the v3 group_reaction envelope.
// All members can publish reactions, including non-admins in announcement groups.
func (n *Node) PublishGroupReaction(groupId, privateKeyB64, senderPeerId, senderPublicKeyB64, reactionJSON string) error {
	n.mu.RLock()
	topic, topicOk := n.groupTopics[groupId]
	config, configOk := n.groupConfigs[groupId]
	keyInfo, keyOk := n.groupKeys[groupId]
	n.mu.RUnlock()

	if !topicOk || !configOk || !keyOk {
		return fmt.Errorf("group not joined: %s", groupId)
	}

	// Check membership (any member can react, regardless of group type).
	member := findMember(config, senderPeerId)
	if member == nil {
		return fmt.Errorf("sender %s not a member of group %s", senderPeerId, groupId)
	}

	// Encrypt reaction payload with group key.
	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(keyInfo.Key, reactionJSON)
	if err != nil {
		return fmt.Errorf("encrypt group reaction: %w", err)
	}

	// Build signature and sign.
	sigData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, ctB64)
	signature, err := mcrypto.SignPayload(privateKeyB64, sigData)
	if err != nil {
		return fmt.Errorf("sign group reaction: %w", err)
	}

	// Build GroupEnvelope with type "group_reaction".
	envelope := &internal.GroupEnvelope{
		Version:         "3",
		Type:            "group_reaction",
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
		return fmt.Errorf("marshal reaction envelope: %w", err)
	}

	ctx, cancel := context.WithTimeout(n.ctx, PubSubTimeout)
	defer cancel()

	if err := topic.Publish(ctx, []byte(envelopeJSON)); err != nil {
		return fmt.Errorf("publish reaction to topic: %w", err)
	}

	return nil
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

		// 1. Must be a v3 group envelope (message or reaction).
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

		// 6. For announcement groups: only admin can publish messages.
		//    Reactions are allowed from any member (all members can react).
		if env.Type == "group_message" && !isAllowedWriter(config, env.SenderId) {
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

		// Route by envelope type BEFORE parsing inner payload — reactions
		// have a different inner schema and must not go through ParseGroupPayload.
		if env.Type == "group_reaction" {
			reactionEvent := map[string]interface{}{
				"groupId":  groupId,
				"senderId": env.SenderId,
				"reaction": plaintext,
			}
			n.emitEvent("group_reaction:received", reactionEvent)
			continue
		}

		// Parse inner payload (group_message only).
		payload, err := internal.ParseGroupPayload(plaintext)
		if err != nil {
			log.Printf("[PUBSUB] Failed to parse payload in group %s: %v", groupId, err)
			continue
		}

		n.emitEvent(
			"group_message:received",
			buildGroupMessageReceivedEvent(groupId, env, payload),
		)
	}
}

func buildGroupMessageExtra(messageId string, opts map[string]interface{}) map[string]interface{} {
	if len(opts) == 0 {
		return map[string]interface{}{
			"messageId": messageId,
		}
	}

	extra := make(map[string]interface{}, len(opts)+1)
	for key, value := range opts {
		extra[key] = value
	}
	extra["messageId"] = messageId
	return extra
}

func buildGroupMessageReceivedEvent(groupId string, env *internal.GroupEnvelope, payload *internal.GroupMessagePayload) map[string]interface{} {
	event := map[string]interface{}{
		"groupId":        groupId,
		"senderId":       env.SenderId,
		"senderUsername": payload.Username,
		"keyEpoch":       env.KeyEpoch,
		"text":           payload.Text,
		"timestamp":      payload.Timestamp,
	}
	if payload.Extra == nil {
		return event
	}
	if media, ok := payload.Extra["media"]; ok {
		event["media"] = media
	}
	if msgId, ok := payload.Extra["messageId"]; ok {
		event["messageId"] = msgId
	}
	if quotedMessageId, ok := payload.Extra["quotedMessageId"]; ok {
		event["quotedMessageId"] = quotedMessageId
	}
	return event
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

type groupPeerConnectResult struct {
	Path              string
	DirectAddrCount   int
	AttemptedDirect   bool
	UsedRelayFallback bool
	DirectError       string
	RelayError        string
}

func isRelayCircuitAddr(addr ma.Multiaddr) bool {
	return addr != nil && strings.Contains(addr.String(), "/p2p-circuit")
}

func dedupeDirectMultiaddrs(addrs []ma.Multiaddr) []ma.Multiaddr {
	seen := make(map[string]struct{}, len(addrs))
	result := make([]ma.Multiaddr, 0, len(addrs))
	for _, addr := range addrs {
		if addr == nil || isRelayCircuitAddr(addr) {
			continue
		}
		key := addr.String()
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, addr)
	}
	return result
}

func multiaddrsToStrings(addrs []ma.Multiaddr) []string {
	result := make([]string, 0, len(addrs))
	for _, addr := range addrs {
		if addr == nil {
			continue
		}
		result = append(result, addr.String())
	}
	return result
}

func (n *Node) connectGroupPeerPreferDirect(peerIdStr string, candidateAddrs []ma.Multiaddr) (groupPeerConnectResult, error) {
	result := groupPeerConnectResult{}

	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return result, fmt.Errorf("node not started")
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return result, fmt.Errorf("invalid peer ID: %w", err)
	}

	directAddrs := make([]ma.Multiaddr, 0, len(candidateAddrs)+len(h.Peerstore().Addrs(pid)))
	directAddrs = append(directAddrs, candidateAddrs...)
	directAddrs = append(directAddrs, h.Peerstore().Addrs(pid)...)
	directAddrs = dedupeDirectMultiaddrs(directAddrs)
	result.DirectAddrCount = len(directAddrs)

	if len(directAddrs) > 0 {
		result.AttemptedDirect = true
		if err := n.DialPeerWithTimeout(peerIdStr, multiaddrsToStrings(directAddrs), 0); err == nil {
			result.Path = "direct"
			return result, nil
		} else {
			result.DirectError = err.Error()
		}
	}

	if err := n.DialPeerViaRelay(peerIdStr); err == nil {
		if result.AttemptedDirect {
			result.Path = "relay_fallback"
			result.UsedRelayFallback = true
		} else {
			result.Path = "relay"
		}
		return result, nil
	} else {
		result.RelayError = err.Error()
		if result.AttemptedDirect {
			return result, fmt.Errorf("direct dial failed: %s; relay fallback failed: %w", result.DirectError, err)
		}
		return result, err
	}
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
		"groupId":          groupId,
		"step":             "discover_result",
		"totalFound":       len(peers),
		"newPeers":         len(newPeers),
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

		if allowed, retryIn := n.allowGroupPeerDial(pidStr, time.Now()); !allowed {
			log.Printf(
				"[PUBSUB] Group %s: skipping discovered dial to %s during cooldown (%v remaining)",
				groupId,
				pidShort,
				retryIn.Truncate(time.Second),
			)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId": groupId,
				"step":    "dial_skipped_cooldown",
				"peerId":  pidShort,
				"retryIn": retryIn.String(),
			})
			continue
		}

		connectResult, err := n.connectGroupPeerPreferDirect(pidStr, p.Addrs)
		if err != nil {
			n.recordGroupPeerDialResult(pidStr, false, time.Now())
			log.Printf("[PUBSUB] Group %s: dial %s failed (attemptedDirect=%t, directAddrs=%d): %v",
				groupId, pidShort, connectResult.AttemptedDirect, connectResult.DirectAddrCount, err)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId":           groupId,
				"step":              "dial_failed",
				"peerId":            pidShort,
				"attemptedDirect":   connectResult.AttemptedDirect,
				"directAddrCount":   connectResult.DirectAddrCount,
				"usedRelayFallback": connectResult.UsedRelayFallback,
				"error":             err.Error(),
			})
		} else {
			n.recordGroupPeerDialResult(pidStr, true, time.Now())
			log.Printf("[PUBSUB] Group %s: connected to %s via %s", groupId, pidShort, connectResult.Path)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId":           groupId,
				"step":              "dial_success",
				"peerId":            pidShort,
				"path":              connectResult.Path,
				"attemptedDirect":   connectResult.AttemptedDirect,
				"directAddrCount":   connectResult.DirectAddrCount,
				"usedRelayFallback": connectResult.UsedRelayFallback,
			})
		}
	}
}

// dialKnownGroupMembers dials all group members, preferring existing direct or
// peerstore addresses before falling back to relay circuit dialing.
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
	cooldownSkipped := 0
	directConnected := 0
	relayFallbackConnected := 0
	relayOnlyConnected := 0
	for _, member := range config.Members {
		if member.PeerId == selfId {
			continue
		}
		if _, alreadyConnected := connectedSet[member.PeerId]; alreadyConnected {
			connected++
			n.recordGroupPeerDialResult(member.PeerId, true, time.Now())
			continue
		}

		pidShort := member.PeerId
		if len(pidShort) > 16 {
			pidShort = pidShort[:16]
		}

		if allowed, retryIn := n.allowGroupPeerDial(member.PeerId, time.Now()); !allowed {
			cooldownSkipped++
			log.Printf(
				"[PUBSUB] Group %s: skipping direct dial to %s during cooldown (%v remaining)",
				groupId,
				pidShort,
				retryIn.Truncate(time.Second),
			)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId": groupId,
				"step":    "direct_dial_skipped_cooldown",
				"peerId":  pidShort,
				"retryIn": retryIn.String(),
			})
			continue
		}

		dialed++
		connectResult, err := n.connectGroupPeerPreferDirect(member.PeerId, nil)
		if err != nil {
			n.recordGroupPeerDialResult(member.PeerId, false, time.Now())
			log.Printf("[PUBSUB] Group %s: dial %s (%s) failed (attemptedDirect=%t, directAddrs=%d): %v",
				groupId, member.Username, pidShort, connectResult.AttemptedDirect, connectResult.DirectAddrCount, err)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId":           groupId,
				"step":              "known_member_dial_failed",
				"peerId":            pidShort,
				"attemptedDirect":   connectResult.AttemptedDirect,
				"directAddrCount":   connectResult.DirectAddrCount,
				"usedRelayFallback": connectResult.UsedRelayFallback,
				"error":             err.Error(),
			})
		} else {
			n.recordGroupPeerDialResult(member.PeerId, true, time.Now())
			connected++
			switch connectResult.Path {
			case "direct":
				directConnected++
			case "relay_fallback":
				relayFallbackConnected++
			default:
				relayOnlyConnected++
			}
			log.Printf("[PUBSUB] Group %s: connected to %s (%s) via %s",
				groupId, member.Username, pidShort, connectResult.Path)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId":           groupId,
				"step":              "known_member_dial_success",
				"peerId":            pidShort,
				"path":              connectResult.Path,
				"attemptedDirect":   connectResult.AttemptedDirect,
				"directAddrCount":   connectResult.DirectAddrCount,
				"usedRelayFallback": connectResult.UsedRelayFallback,
			})
		}
	}

	n.emitEvent("group:discovery", map[string]interface{}{
		"groupId":                groupId,
		"step":                   "direct_dial",
		"membersDialed":          dialed,
		"membersConnected":       connected,
		"cooldownSkipped":        cooldownSkipped,
		"directConnected":        directConnected,
		"relayFallbackConnected": relayFallbackConnected,
		"relayOnlyConnected":     relayOnlyConnected,
		"totalMembers":           len(config.Members),
	})
}

// countConnectedGroupMembers returns the number of group members currently
// connected to this node (excluding self). This is used by the discovery
// loop to determine whether to back off or reset the interval.
func (n *Node) countConnectedGroupMembers(groupId string) int {
	n.mu.RLock()
	config, ok := n.groupConfigs[groupId]
	h := n.host
	selfId := ""
	if h != nil {
		selfId = h.ID().String()
	}
	n.mu.RUnlock()

	if !ok || h == nil {
		return 0
	}

	count := 0
	for _, pid := range h.Network().Peers() {
		pidStr := pid.String()
		if pidStr == selfId {
			continue
		}
		if findMember(config, pidStr) != nil {
			count++
		}
	}
	return count
}

type groupPeerDialState struct {
	failureCount int
	nextAllowed  time.Time
}

func jitterDuration(base time.Duration, factor int, pick func(int64) int64) time.Duration {
	if base <= 0 {
		return time.Second
	}
	if factor <= 0 {
		factor = 1
	}

	spread := int64(base) / int64(factor)
	if spread <= 0 {
		if base < time.Second {
			return time.Second
		}
		return base
	}

	width := spread*2 + 1
	offset := pick(width) - spread
	wait := base + time.Duration(offset)
	if wait < time.Second {
		return time.Second
	}
	return wait
}

func positiveJitter(maxDelay time.Duration, pick func(int64) int64) time.Duration {
	if maxDelay <= 0 {
		return 0
	}
	return time.Duration(pick(int64(maxDelay)))
}

func groupPeerDialBackoff(failureCount int) time.Duration {
	if failureCount <= 0 {
		return 0
	}

	backoff := GroupDiscoveryInterval
	for i := 1; i < failureCount; i++ {
		backoff *= 2
		if backoff >= MaxGroupDiscoveryBackoff {
			return MaxGroupDiscoveryBackoff
		}
	}
	if backoff > MaxGroupDiscoveryBackoff {
		return MaxGroupDiscoveryBackoff
	}
	return backoff
}

func (n *Node) acquireGroupRecoverySlot(ctx context.Context) (func(), error) {
	n.mu.Lock()
	sem := n.groupRecoverySem
	if sem == nil {
		sem = make(chan struct{}, GroupDiscoveryConcurrency)
		n.groupRecoverySem = sem
	}
	n.mu.Unlock()

	select {
	case sem <- struct{}{}:
		return func() { <-sem }, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func (n *Node) allowGroupPeerDial(peerId string, now time.Time) (bool, time.Duration) {
	n.mu.Lock()
	defer n.mu.Unlock()

	if n.groupDialBackoff == nil {
		n.groupDialBackoff = make(map[string]groupPeerDialState)
	}

	state, ok := n.groupDialBackoff[peerId]
	if !ok || !now.Before(state.nextAllowed) {
		return true, 0
	}
	return false, state.nextAllowed.Sub(now)
}

func (n *Node) recordGroupPeerDialResult(peerId string, success bool, now time.Time) {
	n.mu.Lock()
	defer n.mu.Unlock()

	if n.groupDialBackoff == nil {
		n.groupDialBackoff = make(map[string]groupPeerDialState)
	}

	if success {
		delete(n.groupDialBackoff, peerId)
		return
	}

	state := n.groupDialBackoff[peerId]
	state.failureCount++
	state.nextAllowed = now.Add(groupPeerDialBackoff(state.failureCount))
	n.groupDialBackoff[peerId] = state
}

func sleepWithContext(ctx context.Context, wait time.Duration) bool {
	if wait <= 0 {
		return true
	}

	timer := time.NewTimer(wait)
	defer timer.Stop()

	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

func (n *Node) runGroupDiscoveryCycle(
	ctx context.Context,
	groupId string,
	ns string,
	registerNamespace bool,
) (executed bool, registered bool) {
	release, err := n.acquireGroupRecoverySlot(ctx)
	if err != nil {
		return false, false
	}
	defer release()

	n.dialKnownGroupMembers(groupId)

	if registerNamespace {
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
			registered = true
		}
	}

	n.discoverAndConnectGroupPeers(groupId)
	return true, registered
}

// groupPeerDiscoveryLoop runs periodic peer discovery for a group.
// It waits for a circuit relay address to appear (so the peer record includes
// the relay address), then uses two strategies to connect to group peers:
// 1. Direct relay dialing: dials known group members by peer ID via relay circuit
// 2. Rendezvous: registers/discovers on group namespace (backup for unknown peers)
//
// Direct dialing is the primary path since all member peer IDs are in the config.
// On context cancellation it unregisters from the namespace (best-effort).
//
// The loop uses exponential backoff with jitter when all dials fail
// consecutively, capping at MaxGroupDiscoveryBackoff. The interval resets
// to GroupDiscoveryInterval when any peer is connected or progress is made.
func (n *Node) groupPeerDiscoveryLoop(ctx context.Context, groupId string) {
	ns := groupRendezvousNamespace(groupId)
	registered := false

	// Wait for relay to be ready before dialing/registering.
	select {
	case <-n.relayReady:
	case <-ctx.Done():
		return
	}

	// Wait for circuit address so peer record includes relay address.
	n.waitForCircuitAddress(10 * time.Second)

	initialDelay := positiveJitter(GroupRecoveryInitialJitter, rand.Int63n)
	if initialDelay > 0 {
		n.emitEvent("group:discovery", map[string]interface{}{
			"groupId": groupId,
			"step":    "initial_jitter",
			"delayMs": initialDelay.Milliseconds(),
		})
		if !sleepWithContext(ctx, initialDelay) {
			return
		}
	}

	// Initial recovery cycle: stagger the burst, cap cross-group concurrency,
	// then register/discover after known-member dials.
	executed, registeredNow := n.runGroupDiscoveryCycle(ctx, groupId, ns, true)
	if !executed {
		return
	}
	registered = registeredNow

	interval := GroupDiscoveryInterval
	consecutiveFailures := 0

	for {
		wait := jitterDuration(interval, GroupDiscoveryJitterFactor, rand.Int63n)
		if !sleepWithContext(ctx, wait) {
			if registered {
				// Best-effort unregister.
				if err := n.RendezvousUnregister(ns, nil); err != nil {
					log.Printf("[PUBSUB] Group %s: rendezvous unregister failed: %v", groupId, err)
				}
			}
			return
		}

		// Check how many peers are connected for this group BEFORE dialing.
		beforeConnected := n.countConnectedGroupMembers(groupId)

		// Re-dial known members (handles reconnection after disconnect)
		// and rendezvous discover (handles new members).
		if executed, _ := n.runGroupDiscoveryCycle(ctx, groupId, ns, false); !executed {
			if registered {
				if err := n.RendezvousUnregister(ns, nil); err != nil {
					log.Printf("[PUBSUB] Group %s: rendezvous unregister failed: %v", groupId, err)
				}
			}
			return
		}

		// Check AFTER dialing.
		afterConnected := n.countConnectedGroupMembers(groupId)

		if afterConnected > beforeConnected || afterConnected > 0 {
			// At least one peer is connected or we made progress — reset.
			consecutiveFailures = 0
			interval = GroupDiscoveryInterval
		} else {
			// All dials failed — exponential backoff.
			consecutiveFailures++
			interval = interval * 2
			if interval > MaxGroupDiscoveryBackoff {
				interval = MaxGroupDiscoveryBackoff
			}
			log.Printf("[PUBSUB] Group %s: all dials failed (streak=%d), backing off to %v",
				groupId, consecutiveFailures, interval)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId":             groupId,
				"step":                "backoff",
				"consecutiveFailures": consecutiveFailures,
				"nextInterval":        interval.String(),
			})
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
