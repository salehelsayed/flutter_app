package node

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	"math/rand"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

const (
	pubsubAuthorizationRejectDiagnosticWindow = time.Minute
	pubsubAuthorizationRejectHashLength       = 12
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

	if keyInfo == nil {
		return fmt.Errorf("missing group key info for group %s", groupId)
	}

	if config == nil {
		return fmt.Errorf("missing group config for group %s", groupId)
	}

	topicName := GroupTopicPrefix + groupId

	// Register topic validator before joining.
	err := n.pubsub.RegisterTopicValidator(topicName, n.groupTopicValidator(groupId))
	if err != nil {
		return fmt.Errorf("register topic validator: %w", err)
	}

	topic, err := n.pubsub.Join(topicName)
	if err != nil {
		_ = n.pubsub.UnregisterTopicValidator(topicName)
		return fmt.Errorf("join topic %s: %w", topicName, err)
	}

	var sub *pubsub.Subscription
	if n.joinGroupTopicSubscribeHook != nil {
		sub, err = n.joinGroupTopicSubscribeHook(topic)
	} else {
		sub, err = topic.Subscribe()
	}
	if err != nil {
		_ = topic.Close()
		_ = n.pubsub.UnregisterTopicValidator(topicName)
		return fmt.Errorf("subscribe to topic %s: %w", topicName, err)
	}

	// Store config and key.
	n.groupTopics[groupId] = topic
	n.groupSubs[groupId] = sub
	n.groupConfigs[groupId] = cloneGroupConfig(config)
	n.groupKeys[groupId] = joinedGroupKeyInfo(keyInfo)

	// Start subscription handler in a cancellable goroutine.
	ctx, cancel := context.WithCancel(n.ctx)
	n.groupSubCtx[groupId] = cancel
	go n.handleGroupSubscription(ctx, groupId, sub)

	// Start group peer discovery in background (register + periodic discover).
	discoveryCtx, discoveryCancel := context.WithCancel(n.ctx)
	n.groupDiscoveryCtx[groupId] = discoveryCancel
	go n.groupPeerDiscoveryLoop(discoveryCtx, groupId)

	log.Printf("[PUBSUB] Joined group topic: %s", groupId)
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
// Returns the message ID (UUID) and the number of peers subscribed to the topic
// at publish time. If messageId is non-empty, it is used instead of generating
// a new one — this allows the sender to reference the same ID locally.
func (n *Node) PublishGroupMessage(groupId, privateKeyB64, senderPeerId, senderPublicKeyB64, senderUsername, text, messageId string, opts map[string]interface{}) (msgID string, topicPeerCount int, err error) {
	n.mu.RLock()
	topic, topicOk := n.groupTopics[groupId]
	config, configOk := n.groupConfigs[groupId]
	keyInfo, keyOk := n.groupKeys[groupId]
	n.mu.RUnlock()

	if !topicOk || !configOk || config == nil || !keyOk || keyInfo == nil {
		return "", 0, fmt.Errorf("group not joined: %s", groupId)
	}

	// Check write permission.
	if !isAllowedWriter(config, senderPeerId) {
		return "", 0, fmt.Errorf("sender %s not allowed to write in group %s", senderPeerId, groupId)
	}

	// 1. Build GroupMessagePayload.
	msgId := messageId
	if msgId == "" {
		msgId = uuid.New().String()
	}
	timestamp := time.Now().UTC().Format(time.RFC3339Nano)

	extra := buildGroupMessageExtra(msgId, opts)
	extra["publishedAtNano"] = strconv.FormatInt(time.Now().UnixNano(), 10)

	payload := &internal.GroupMessagePayload{
		Text:      text,
		Timestamp: timestamp,
		Username:  senderUsername,
		Extra:     extra,
	}

	payloadJSON, err := internal.MarshalGroupPayload(payload)
	if err != nil {
		return "", 0, fmt.Errorf("marshal payload: %w", err)
	}

	// 2. Encrypt payload with group key.
	encryptStart := time.Now()
	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(keyInfo.Key, payloadJSON)
	encryptMs := time.Since(encryptStart).Milliseconds()
	if err != nil {
		return "", 0, fmt.Errorf("encrypt group message: %w", err)
	}

	// 3. Build signature data and sign.
	signStart := time.Now()
	sigData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, ctB64)
	signature, err := mcrypto.SignPayload(privateKeyB64, sigData)
	signMs := time.Since(signStart).Milliseconds()
	if err != nil {
		return "", 0, fmt.Errorf("sign group message: %w", err)
	}

	// 4. Build GroupEnvelope (v3).
	senderDeviceId := groupPublishStringOpt(opts, "senderDeviceId")
	if senderDeviceId == "" {
		senderDeviceId = senderPeerId
	}
	senderTransportPeerId := groupPublishStringOpt(opts, "senderTransportPeerId")
	if senderTransportPeerId == "" {
		senderTransportPeerId = senderDeviceId
	}
	senderDevicePublicKey := groupPublishStringOpt(opts, "senderDevicePublicKey")
	if senderDevicePublicKey == "" {
		senderDevicePublicKey = senderPublicKeyB64
	}
	envelope := &internal.GroupEnvelope{
		Version:               "3",
		Type:                  "group_message",
		GroupId:               groupId,
		SenderId:              senderPeerId,
		SenderDeviceId:        senderDeviceId,
		SenderTransportPeerId: senderTransportPeerId,
		SenderDevicePublicKey: senderDevicePublicKey,
		SenderKeyPackageId:    groupPublishStringOpt(opts, "senderKeyPackageId"),
		SenderPublicKey:       senderPublicKeyB64,
		Signature:             signature,
		KeyEpoch:              keyInfo.KeyEpoch,
		Encrypted: internal.GroupEncryptedPayload{
			Ciphertext: ctB64,
			Nonce:      nonceB64,
		},
	}

	envelopeJSON, err := internal.MarshalGroupEnvelope(envelope)
	if err != nil {
		return "", 0, fmt.Errorf("marshal envelope: %w", err)
	}

	// 5. Publish to topic.
	ctx, cancel := context.WithTimeout(n.ctx, PubSubTimeout)
	defer cancel()

	peerCount := n.ensureGroupTopicPeersBeforePublish(
		groupId,
		config,
		senderPeerId,
		topic,
	)
	log.Printf("[PUBSUB] Publishing message %s to group %s (peers in topic: %d)", msgId, groupId, peerCount)

	if err := topic.Publish(ctx, []byte(envelopeJSON)); err != nil {
		return "", 0, fmt.Errorf("publish to topic: %w", err)
	}

	n.emitEvent("group:publish_debug", map[string]interface{}{
		"groupId":    groupId,
		"messageId":  msgId,
		"topicPeers": peerCount,
		"encryptMs":  encryptMs,
		"signMs":     signMs,
	})

	return msgId, peerCount, nil
}

// PublishGroupReaction encrypts, signs, and publishes a reaction to a group topic.
// The reactionJSON is the raw JSON payload (id, messageId, emoji, action, etc.)
// that gets encrypted inside the v3 group_reaction envelope.
// All members can publish reactions, including non-admins in announcement groups.
func (n *Node) PublishGroupReaction(groupId, privateKeyB64, senderPeerId, senderPublicKeyB64, reactionJSON string, opts ...map[string]interface{}) error {
	n.mu.RLock()
	topic, topicOk := n.groupTopics[groupId]
	config, configOk := n.groupConfigs[groupId]
	keyInfo, keyOk := n.groupKeys[groupId]
	n.mu.RUnlock()

	if !topicOk || !configOk || config == nil || !keyOk || keyInfo == nil {
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
	reactionOpts := map[string]interface{}(nil)
	if len(opts) > 0 {
		reactionOpts = opts[0]
	}
	senderDeviceId := groupPublishStringOpt(reactionOpts, "senderDeviceId")
	if senderDeviceId == "" {
		senderDeviceId = senderPeerId
	}
	senderTransportPeerId := groupPublishStringOpt(reactionOpts, "senderTransportPeerId")
	if senderTransportPeerId == "" {
		senderTransportPeerId = senderDeviceId
	}
	senderDevicePublicKey := groupPublishStringOpt(reactionOpts, "senderDevicePublicKey")
	if senderDevicePublicKey == "" {
		senderDevicePublicKey = senderPublicKeyB64
	}
	envelope := &internal.GroupEnvelope{
		Version:               "3",
		Type:                  "group_reaction",
		GroupId:               groupId,
		SenderId:              senderPeerId,
		SenderDeviceId:        senderDeviceId,
		SenderTransportPeerId: senderTransportPeerId,
		SenderDevicePublicKey: senderDevicePublicKey,
		SenderKeyPackageId:    groupPublishStringOpt(reactionOpts, "senderKeyPackageId"),
		SenderPublicKey:       senderPublicKeyB64,
		Signature:             signature,
		KeyEpoch:              keyInfo.KeyEpoch,
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

	if config == nil {
		delete(n.groupConfigs, groupId)
		return
	}

	n.groupConfigs[groupId] = cloneGroupConfig(config)
}

// UpdateGroupKey updates the stored group encryption key.
func (n *Node) UpdateGroupKey(groupId string, keyInfo *GroupKeyInfo) {
	n.mu.Lock()
	defer n.mu.Unlock()

	if keyInfo == nil {
		delete(n.groupKeys, groupId)
		return
	}

	current := n.groupKeys[groupId]
	switch {
	case current == nil:
		n.groupKeys[groupId] = joinedGroupKeyInfo(keyInfo)
	case keyInfo.KeyEpoch <= current.KeyEpoch:
		return
	default:
		n.groupKeys[groupId] = &GroupKeyInfo{
			Key:           keyInfo.Key,
			KeyEpoch:      keyInfo.KeyEpoch,
			PrevKey:       current.Key,
			PrevKeyEpoch:  current.KeyEpoch,
			GraceDeadline: time.Now().Add(KeyRotationGracePeriod),
		}
	}
}

// GetGroupKeyInfo returns the current key info for a group, or nil if not found.
func (n *Node) GetGroupKeyInfo(groupId string) *GroupKeyInfo {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return cloneGroupKeyInfo(n.groupKeys[groupId])
}

func cloneGroupKeyInfo(keyInfo *GroupKeyInfo) *GroupKeyInfo {
	if keyInfo == nil {
		return nil
	}
	cloned := *keyInfo
	return &cloned
}

func cloneGroupConfig(config *GroupConfig) *GroupConfig {
	if config == nil {
		return nil
	}

	cloned := *config
	if config.Members != nil {
		cloned.Members = make([]GroupMember, len(config.Members))
		copy(cloned.Members, config.Members)
		for i := range config.Members {
			if config.Members[i].Devices != nil {
				cloned.Members[i].Devices = make([]GroupMemberDevice, len(config.Members[i].Devices))
				copy(cloned.Members[i].Devices, config.Members[i].Devices)
			}
		}
	}
	return &cloned
}

func joinedGroupKeyInfo(keyInfo *GroupKeyInfo) *GroupKeyInfo {
	if keyInfo == nil {
		return nil
	}
	return &GroupKeyInfo{
		Key:      keyInfo.Key,
		KeyEpoch: keyInfo.KeyEpoch,
	}
}

func hasKeyRotationGrace(keyInfo *GroupKeyInfo, now time.Time) bool {
	return keyInfo != nil &&
		keyInfo.PrevKey != "" &&
		keyInfo.PrevKeyEpoch > 0 &&
		!keyInfo.GraceDeadline.IsZero() &&
		now.Before(keyInfo.GraceDeadline)
}

func verifyGroupEnvelopeSignature(groupId string, memberPublicKey string, env *internal.GroupEnvelope, keyInfo *GroupKeyInfo, now time.Time) bool {
	if keyInfo == nil || env == nil {
		return false
	}

	if env.KeyEpoch == keyInfo.KeyEpoch {
		sigData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, env.Encrypted.Ciphertext)
		valid, err := mcrypto.VerifyPayload(memberPublicKey, sigData, env.Signature)
		return err == nil && valid
	}

	if env.KeyEpoch == keyInfo.PrevKeyEpoch && hasKeyRotationGrace(keyInfo, now) {
		sigData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.PrevKeyEpoch, env.Encrypted.Ciphertext)
		valid, err := mcrypto.VerifyPayload(memberPublicKey, sigData, env.Signature)
		return err == nil && valid
	}

	return false
}

func decryptGroupEnvelopePayload(env *internal.GroupEnvelope, keyInfo *GroupKeyInfo, now time.Time) (string, error) {
	if keyInfo == nil || env == nil {
		return "", fmt.Errorf("missing group key info")
	}

	switch {
	case env.KeyEpoch == keyInfo.KeyEpoch:
		return mcrypto.DecryptGroupMessage(keyInfo.Key, env.Encrypted.Ciphertext, env.Encrypted.Nonce)
	case env.KeyEpoch == keyInfo.PrevKeyEpoch && hasKeyRotationGrace(keyInfo, now):
		return mcrypto.DecryptGroupMessage(keyInfo.PrevKey, env.Encrypted.Ciphertext, env.Encrypted.Nonce)
	default:
		return "", fmt.Errorf("no group key available for epoch %d", env.KeyEpoch)
	}
}

func groupEnvelopeMatchesTransportPeer(env *internal.GroupEnvelope, transportPeerId string) bool {
	if env == nil || transportPeerId == "" {
		return true
	}
	expectedTransportPeerId := env.SenderTransportPeerId
	if expectedTransportPeerId == "" {
		expectedTransportPeerId = env.SenderId
	}
	return expectedTransportPeerId == transportPeerId
}

func activeMemberDeviceForEnvelope(member *GroupMember, env *internal.GroupEnvelope, transportPeerId string) *GroupMemberDevice {
	if member == nil || env == nil {
		return nil
	}

	if len(member.Devices) == 0 {
		if env.SenderDeviceId != "" && env.SenderDeviceId != member.PeerId {
			return nil
		}
		if env.SenderTransportPeerId != "" && env.SenderTransportPeerId != member.PeerId {
			return nil
		}
		if transportPeerId != "" && transportPeerId != member.PeerId {
			return nil
		}
		if env.SenderDevicePublicKey != "" && env.SenderDevicePublicKey != member.PublicKey {
			return nil
		}
		return &GroupMemberDevice{
			DeviceId:               member.PeerId,
			TransportPeerId:        member.PeerId,
			DeviceSigningPublicKey: member.PublicKey,
			MlKemPublicKey:         member.MlKemPublicKey,
			Status:                 "active",
		}
	}

	expectedDeviceId := env.SenderDeviceId
	expectedTransportPeerId := env.SenderTransportPeerId
	if expectedTransportPeerId == "" {
		expectedTransportPeerId = transportPeerId
	}
	if expectedDeviceId == "" || expectedTransportPeerId == "" {
		return nil
	}

	for i := range member.Devices {
		device := &member.Devices[i]
		if device.DeviceId != expectedDeviceId {
			continue
		}
		if device.Status != "" && device.Status != "active" {
			continue
		}
		if device.RevokedAt != "" {
			continue
		}
		if device.TransportPeerId != expectedTransportPeerId {
			return nil
		}
		if transportPeerId != "" && device.TransportPeerId != transportPeerId {
			return nil
		}
		if env.SenderDevicePublicKey != "" && env.SenderDevicePublicKey != device.DeviceSigningPublicKey {
			return nil
		}
		if env.SenderKeyPackageId != "" && env.SenderKeyPackageId != device.KeyPackageId {
			return nil
		}
		return device
	}
	return nil
}

func pubsubAuthorizationRejectHash(value string) string {
	if value == "" {
		return "none"
	}
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])[:pubsubAuthorizationRejectHashLength]
}

func (n *Node) logPubSubValidationReject(reason, groupId string, pid peer.ID, env *internal.GroupEnvelope) {
	senderId := ""
	envelopeType := "unknown"
	keyEpoch := 0
	if env != nil {
		senderId = env.SenderId
		if env.Type != "" {
			envelopeType = env.Type
		}
		keyEpoch = env.KeyEpoch
	}

	localPeerId := ""
	if n != nil {
		n.mu.RLock()
		localPeerId = n.peerId
		n.mu.RUnlock()
	}

	now := time.Now()
	diagKey := strings.Join([]string{reason, groupId, senderId, pid.String()}, "|")
	if n != nil {
		n.pubsubRejectDiagMu.Lock()
		if n.pubsubRejectDiagLast == nil {
			n.pubsubRejectDiagLast = make(map[string]time.Time)
		}
		if n.pubsubRejectDiagNow != nil {
			now = n.pubsubRejectDiagNow()
		}
		if last, ok := n.pubsubRejectDiagLast[diagKey]; ok && now.Sub(last) < pubsubAuthorizationRejectDiagnosticWindow {
			n.pubsubRejectDiagMu.Unlock()
			return
		}
		n.pubsubRejectDiagLast[diagKey] = now
		n.pubsubRejectDiagMu.Unlock()
	}

	groupHash := pubsubAuthorizationRejectHash(groupId)
	senderHash := pubsubAuthorizationRejectHash(senderId)
	transportPeerHash := pubsubAuthorizationRejectHash(pid.String())
	localPeerHash := pubsubAuthorizationRejectHash(localPeerId)

	log.Printf(
		"[PUBSUB] Validator: authorization reject reason=%s groupHash=%s senderHash=%s transportPeerHash=%s localPeerHash=%s envelopeType=%s keyEpoch=%d",
		reason,
		groupHash,
		senderHash,
		transportPeerHash,
		localPeerHash,
		envelopeType,
		keyEpoch,
	)
	if n != nil {
		n.emitEvent("group:validation_rejected", map[string]interface{}{
			"reason":            reason,
			"groupHash":         groupHash,
			"senderHash":        senderHash,
			"transportPeerHash": transportPeerHash,
			"localPeerHash":     localPeerHash,
			"envelopeType":      envelopeType,
			"keyEpoch":          keyEpoch,
		})
	}
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
			n.logPubSubValidationReject("not_v3_envelope", groupId, pid, nil)
			return pubsub.ValidationReject
		}

		// 2. Parse envelope.
		env, err := internal.ParseGroupEnvelope(data)
		if err != nil {
			n.logPubSubValidationReject("invalid_envelope", groupId, pid, nil)
			return pubsub.ValidationReject
		}

		// 3. Verify groupId matches.
		if env.GroupId != groupId {
			n.logPubSubValidationReject("group_mismatch", groupId, pid, env)
			return pubsub.ValidationReject
		}

		// 4. Bind the claimed sender to the libp2p transport peer id.
		if !groupEnvelopeMatchesTransportPeer(env, pid.String()) {
			n.logPubSubValidationReject("peer_mismatch", groupId, pid, env)
			return pubsub.ValidationReject
		}

		// 5. Look up group config.
		n.mu.RLock()
		config, ok := n.groupConfigs[groupId]
		n.mu.RUnlock()
		if !ok || config == nil {
			n.logPubSubValidationReject("unknown_group", groupId, pid, env)
			return pubsub.ValidationReject
		}

		// 6. Find sender in members list.
		member := findMember(config, env.SenderId)
		if member == nil {
			n.logPubSubValidationReject("non_member", groupId, pid, env)
			return pubsub.ValidationReject
		}
		sourceDevice := activeMemberDeviceForEnvelope(member, env, pid.String())
		if sourceDevice == nil {
			n.logPubSubValidationReject("unbound_device", groupId, pid, env)
			return pubsub.ValidationReject
		}

		// 7. For announcement groups: only admin can publish messages.
		//    Reactions are allowed from any member (all members can react).
		if env.Type == "group_message" && !isAllowedWriter(config, env.SenderId) {
			n.logPubSubValidationReject("unauthorized_writer", groupId, pid, env)
			return pubsub.ValidationReject
		}

		// 8. Verify signature.
		n.mu.RLock()
		keyInfo, keyOk := n.groupKeys[groupId]
		n.mu.RUnlock()
		if !keyOk || keyInfo == nil {
			n.logPubSubValidationReject("missing_key", groupId, pid, env)
			return pubsub.ValidationReject
		}

		if !verifyGroupEnvelopeSignature(groupId, sourceDevice.DeviceSigningPublicKey, env, keyInfo, time.Now()) {
			n.logPubSubValidationReject("bad_signature_or_epoch", groupId, pid, env)
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

		if !keyOk || keyInfo == nil {
			log.Printf("[PUBSUB] No key info for group %s, skipping message", groupId)
			n.emitGroupDecryptionFailed(groupId, env, nil, fmt.Errorf("missing group key info"), 0)
			continue
		}

		// Decrypt the payload.
		decryptStart := time.Now()
		plaintext, err := decryptGroupEnvelopePayload(env, keyInfo, time.Now())
		decryptMs := time.Since(decryptStart).Milliseconds()
		if err != nil {
			log.Printf("[PUBSUB] Failed to decrypt message in group %s: %v", groupId, err)
			n.emitGroupDecryptionFailed(groupId, env, keyInfo, err, decryptMs)
			continue
		}

		// Route by envelope type BEFORE parsing inner payload — reactions
		// have a different inner schema and must not go through ParseGroupPayload.
		if env.Type == "group_reaction" {
			transportPeerId := env.SenderTransportPeerId
			if transportPeerId == "" {
				transportPeerId = env.SenderId
			}
			reactionEvent := map[string]interface{}{
				"groupId":         groupId,
				"senderId":        env.SenderId,
				"senderDeviceId":  env.SenderDeviceId,
				"transportPeerId": transportPeerId,
				"reaction":        plaintext,
			}
			n.emitEvent("group_reaction:received", reactionEvent)
			continue
		}

		// Parse inner payload (group_message only).
		payload, err := internal.ParseGroupPayload(plaintext)
		if err != nil {
			log.Printf("[PUBSUB] Failed to parse payload in group %s: %v", groupId, err)
			n.emitEvent("group:payload_parse_failed", map[string]interface{}{
				"groupId":      groupId,
				"senderId":     env.SenderId,
				"envelopeType": env.Type,
			})
			continue
		}

		receivedEvent := buildGroupMessageReceivedEvent(groupId, env, payload)
		receivedEvent["decryptMs"] = decryptMs
		if payload.Extra != nil {
			if pubNanoStr, ok := payload.Extra["publishedAtNano"].(string); ok {
				if pubNano, err := strconv.ParseInt(pubNanoStr, 10, 64); err == nil {
					deliveryMs := (time.Now().UnixNano() - pubNano) / 1e6
					receivedEvent["deliveryMs"] = deliveryMs
				}
			}
		}
		n.emitEvent("group_message:received", receivedEvent)
	}
}

func (n *Node) emitGroupDecryptionFailed(groupId string, env *internal.GroupEnvelope, keyInfo *GroupKeyInfo, decryptErr error, decryptMs int64) {
	data := map[string]interface{}{
		"groupId":   groupId,
		"senderId":  env.SenderId,
		"keyEpoch":  env.KeyEpoch,
		"error":     decryptErr.Error(),
		"decryptMs": decryptMs,
	}
	if keyInfo != nil {
		data["localKeyEpoch"] = keyInfo.KeyEpoch
	}
	n.emitEvent("group:decryption_failed", data)
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

func groupPublishStringOpt(opts map[string]interface{}, key string) string {
	if opts == nil {
		return ""
	}
	value, ok := opts[key]
	if !ok {
		return ""
	}
	str, ok := value.(string)
	if !ok {
		return ""
	}
	return str
}

func buildGroupMessageReceivedEvent(groupId string, env *internal.GroupEnvelope, payload *internal.GroupMessagePayload) map[string]interface{} {
	transportPeerId := env.SenderTransportPeerId
	if transportPeerId == "" {
		transportPeerId = env.SenderId
	}
	event := map[string]interface{}{
		"groupId":         groupId,
		"senderId":        env.SenderId,
		"senderDeviceId":  env.SenderDeviceId,
		"transportPeerId": transportPeerId,
		"senderUsername":  payload.Username,
		"keyEpoch":        env.KeyEpoch,
		"text":            payload.Text,
		"timestamp":       payload.Timestamp,
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

func filterDiscoveredGroupMembers(discovered []peer.AddrInfo, allowedMembers map[peer.ID]struct{}) ([]peer.AddrInfo, int) {
	if len(allowedMembers) == 0 {
		return discovered, 0
	}

	var result []peer.AddrInfo
	ignored := 0
	for _, p := range discovered {
		if _, ok := allowedMembers[p.ID]; !ok {
			ignored++
			continue
		}
		result = append(result, p)
	}
	return result, ignored
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

func collectDirectMultiaddrs(h host.Host, pid peer.ID, candidateAddrs []ma.Multiaddr) []ma.Multiaddr {
	directAddrs := make([]ma.Multiaddr, 0, len(candidateAddrs)+len(h.Peerstore().Addrs(pid)))
	directAddrs = append(directAddrs, candidateAddrs...)
	directAddrs = append(directAddrs, h.Peerstore().Addrs(pid)...)
	return dedupeDirectMultiaddrs(directAddrs)
}

func (n *Node) connectGroupPeerPreferDirect(
	peerIdStr string,
	candidateAddrs []ma.Multiaddr,
	allowRelayFallback bool,
) (groupPeerConnectResult, error) {
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

	directAddrs := collectDirectMultiaddrs(h, pid, candidateAddrs)
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

	if !allowRelayFallback {
		if result.AttemptedDirect {
			return result, fmt.Errorf("direct dial failed: %s", result.DirectError)
		}
		return result, fmt.Errorf("no direct addresses")
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

	// Build set of peers already visible in the topic mesh. A plain host
	// connection is not enough for live delivery if the topic still has zero
	// peers for this group.
	n.mu.RLock()
	h := n.host
	config := n.groupConfigs[groupId]
	n.mu.RUnlock()
	if h == nil {
		return
	}
	selfId := h.ID()

	connectedSet := make(map[peer.ID]struct{})
	for pid := range n.liveGroupTopicPeerSet(groupId) {
		peerID, err := peer.Decode(pid)
		if err != nil {
			continue
		}
		connectedSet[peerID] = struct{}{}
	}

	newPeers := filterDiscoveredPeers(peers, selfId, connectedSet)
	alreadyConnected := len(peers) - len(newPeers)
	allowedMembers := make(map[peer.ID]struct{})
	if config != nil {
		for _, member := range config.Members {
			if len(member.Devices) == 0 {
				if member.PeerId == "" || member.PeerId == selfId.String() {
					continue
				}
				memberID, err := peer.Decode(member.PeerId)
				if err != nil {
					continue
				}
				allowedMembers[memberID] = struct{}{}
				continue
			}
			for _, device := range member.Devices {
				if device.Status != "" && device.Status != "active" {
					continue
				}
				if device.RevokedAt != "" ||
					device.TransportPeerId == "" ||
					device.TransportPeerId == selfId.String() {
					continue
				}
				deviceID, err := peer.Decode(device.TransportPeerId)
				if err != nil {
					continue
				}
				allowedMembers[deviceID] = struct{}{}
			}
		}
	}
	newPeers, ignoredNonMembers := filterDiscoveredGroupMembers(newPeers, allowedMembers)

	n.emitEvent("group:discovery", map[string]interface{}{
		"groupId":           groupId,
		"step":              "discover_result",
		"totalFound":        len(peers),
		"newPeers":          len(newPeers),
		"alreadyConnected":  alreadyConnected,
		"ignoredNonMembers": ignoredNonMembers,
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

		if allowed, retryIn, blockedByInFlight := n.beginGroupPeerDial(pidStr, time.Now()); !allowed {
			if blockedByInFlight {
				log.Printf("[PUBSUB] Group %s: skipping discovered dial to %s while another group dial is in flight",
					groupId, pidShort)
				n.emitEvent("group:discovery", map[string]interface{}{
					"groupId": groupId,
					"step":    "dial_skipped_inflight",
					"peerId":  pidShort,
				})
			} else {
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
			}
			continue
		}

		connectResult, err := n.connectGroupPeerPreferDirect(pidStr, p.Addrs, true)
		if err != nil {
			n.finishGroupPeerDial(pidStr, false, time.Now())
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
			livePeerReady := n.waitForLiveGroupTopicPeer(groupId, pidStr, GroupPublishPartialPeerSettleWait)
			if !livePeerReady && connectResult.Path == "direct" {
				if relayErr := n.DialPeerViaRelay(pidStr); relayErr != nil {
					connectResult.RelayError = relayErr.Error()
				} else {
					connectResult.Path = "relay_fallback"
					connectResult.UsedRelayFallback = true
					livePeerReady = n.waitForLiveGroupTopicPeer(groupId, pidStr, GroupPublishPartialPeerSettleWait)
				}
			}
			if !livePeerReady {
				n.finishGroupPeerDial(pidStr, false, time.Now())
				log.Printf(
					"[PUBSUB] Group %s: dial %s connected via %s but did not become a live topic peer",
					groupId,
					pidShort,
					connectResult.Path,
				)
				n.emitEvent("group:discovery", map[string]interface{}{
					"groupId":           groupId,
					"step":              "dial_connected_but_topic_missing",
					"peerId":            pidShort,
					"path":              connectResult.Path,
					"attemptedDirect":   connectResult.AttemptedDirect,
					"directAddrCount":   connectResult.DirectAddrCount,
					"usedRelayFallback": connectResult.UsedRelayFallback,
					"relayError":        connectResult.RelayError,
				})
				continue
			}

			n.finishGroupPeerDial(pidStr, true, time.Now())
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
func (n *Node) dialKnownGroupMembers(groupId string, ignoreCooldown bool) {
	n.mu.RLock()
	config, ok := n.groupConfigs[groupId]
	h := n.host
	selfId := ""
	if h != nil {
		selfId = h.ID().String()
	}
	n.mu.RUnlock()

	if !ok || config == nil || h == nil {
		return
	}

	// Build set of peers already visible in the topic. A plain host connection
	// is not enough if the peer has not become a live topic peer yet.
	connectedSet := n.liveGroupTopicPeerSet(groupId)

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
			n.finishGroupPeerDial(member.PeerId, true, time.Now())
			continue
		}

		pidShort := member.PeerId
		if len(pidShort) > 16 {
			pidShort = pidShort[:16]
		}

		if allowed, retryIn, blockedByInFlight := n.beginGroupPeerDialWithMode(member.PeerId, time.Now(), ignoreCooldown); !allowed {
			if blockedByInFlight {
				log.Printf("[PUBSUB] Group %s: skipping direct dial to %s while another group dial is in flight",
					groupId, pidShort)
				n.emitEvent("group:discovery", map[string]interface{}{
					"groupId": groupId,
					"step":    "direct_dial_skipped_inflight",
					"peerId":  pidShort,
				})
			} else {
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
			}
			continue
		}

		dialed++
		connectResult, err := n.connectGroupPeerPreferDirect(member.PeerId, nil, true)
		if err != nil {
			n.finishGroupPeerDial(member.PeerId, false, time.Now())
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
			livePeerReady := n.waitForLiveGroupTopicPeer(groupId, member.PeerId, GroupPublishPartialPeerSettleWait)
			if !livePeerReady && connectResult.Path == "direct" {
				if relayErr := n.DialPeerViaRelay(member.PeerId); relayErr != nil {
					connectResult.RelayError = relayErr.Error()
				} else {
					connectResult.Path = "relay_fallback"
					connectResult.UsedRelayFallback = true
					livePeerReady = n.waitForLiveGroupTopicPeer(groupId, member.PeerId, GroupPublishPartialPeerSettleWait)
				}
			}
			if !livePeerReady {
				n.finishGroupPeerDial(member.PeerId, false, time.Now())
				log.Printf(
					"[PUBSUB] Group %s: dial %s (%s) connected via %s but did not become a live topic peer",
					groupId,
					member.Username,
					pidShort,
					connectResult.Path,
				)
				n.emitEvent("group:discovery", map[string]interface{}{
					"groupId":           groupId,
					"step":              "known_member_topic_missing",
					"peerId":            pidShort,
					"path":              connectResult.Path,
					"attemptedDirect":   connectResult.AttemptedDirect,
					"directAddrCount":   connectResult.DirectAddrCount,
					"usedRelayFallback": connectResult.UsedRelayFallback,
					"relayError":        connectResult.RelayError,
				})
				continue
			}

			n.finishGroupPeerDial(member.PeerId, true, time.Now())
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

// dialKnownGroupMembersDirectOnly attempts direct member recovery using only
// already-known non-relay addresses. This avoids stranding foreground peers on
// the relay warm-up path when direct addresses are already available.
func (n *Node) dialKnownGroupMembersDirectOnly(groupId string) {
	n.mu.RLock()
	config, ok := n.groupConfigs[groupId]
	h := n.host
	selfId := ""
	if h != nil {
		selfId = h.ID().String()
	}
	n.mu.RUnlock()

	if !ok || config == nil || h == nil {
		return
	}

	connectedSet := make(map[string]struct{})
	for _, pid := range h.Network().Peers() {
		connectedSet[pid.String()] = struct{}{}
	}

	dialed := 0
	connected := 0
	noDirectAddr := 0
	for _, member := range config.Members {
		if member.PeerId == selfId {
			continue
		}
		if _, alreadyConnected := connectedSet[member.PeerId]; alreadyConnected {
			connected++
			continue
		}

		connectResult, err := n.connectGroupPeerPreferDirect(member.PeerId, nil, false)
		if !connectResult.AttemptedDirect {
			noDirectAddr++
			continue
		}

		dialed++
		pidShort := member.PeerId
		if len(pidShort) > 16 {
			pidShort = pidShort[:16]
		}

		if err != nil {
			log.Printf("[PUBSUB] Group %s: pre-relay direct dial %s (%s) failed (directAddrs=%d): %v",
				groupId, member.Username, pidShort, connectResult.DirectAddrCount, err)
			n.emitEvent("group:discovery", map[string]interface{}{
				"groupId":         groupId,
				"step":            "known_member_pre_relay_direct_failed",
				"peerId":          pidShort,
				"directAddrCount": connectResult.DirectAddrCount,
				"error":           err.Error(),
			})
			continue
		}

		connected++
		log.Printf("[PUBSUB] Group %s: pre-relay direct connected to %s (%s)",
			groupId, member.Username, pidShort)
		n.emitEvent("group:discovery", map[string]interface{}{
			"groupId":         groupId,
			"step":            "known_member_pre_relay_direct_success",
			"peerId":          pidShort,
			"path":            "direct_pre_relay",
			"directAddrCount": connectResult.DirectAddrCount,
		})
	}

	n.emitEvent("group:discovery", map[string]interface{}{
		"groupId":          groupId,
		"step":             "pre_relay_direct_dial",
		"membersDialed":    dialed,
		"membersConnected": connected,
		"noDirectAddr":     noDirectAddr,
		"totalMembers":     len(config.Members),
	})
}

// countConnectedGroupMembers returns the number of group members currently
// visible in the live topic peer set. This is used by the discovery loop to
// determine whether to stay in the warm retry cadence or back off.
func (n *Node) countConnectedGroupMembers(groupId string) int {
	n.mu.RLock()
	config, ok := n.groupConfigs[groupId]
	n.mu.RUnlock()

	if !ok || config == nil {
		return 0
	}

	liveTopicPeers := n.liveGroupTopicPeerSet(groupId)
	count := 0
	for pidStr := range liveTopicPeers {
		if findMember(config, pidStr) != nil {
			count++
		}
	}
	return count
}

func (n *Node) liveGroupTopicPeerSet(groupId string) map[string]struct{} {
	n.mu.RLock()
	topic := n.groupTopics[groupId]
	n.mu.RUnlock()

	livePeers := make(map[string]struct{})
	if topic == nil {
		return livePeers
	}

	for _, pid := range topic.ListPeers() {
		livePeers[pid.String()] = struct{}{}
	}
	return livePeers
}

func topicHasPeer(topic *pubsub.Topic, peerId string) bool {
	if topic == nil || peerId == "" {
		return false
	}

	for _, pid := range topic.ListPeers() {
		if pid.String() == peerId {
			return true
		}
	}
	return false
}

func waitForTopicPeer(topic *pubsub.Topic, peerId string, timeout time.Duration) bool {
	if topicHasPeer(topic, peerId) {
		return true
	}
	if topic == nil || peerId == "" || timeout <= 0 {
		return false
	}

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		time.Sleep(GroupPublishPeerPoll)
		if topicHasPeer(topic, peerId) {
			return true
		}
	}
	return topicHasPeer(topic, peerId)
}

func (n *Node) waitForLiveGroupTopicPeer(groupId, peerId string, timeout time.Duration) bool {
	n.mu.RLock()
	topic := n.groupTopics[groupId]
	n.mu.RUnlock()
	return waitForTopicPeer(topic, peerId, timeout)
}

func (n *Node) expectedConnectedGroupMembers(groupId string) int {
	n.mu.RLock()
	config := n.groupConfigs[groupId]
	h := n.host
	selfId := ""
	if h != nil {
		selfId = h.ID().String()
	}
	n.mu.RUnlock()

	if config == nil {
		return 0
	}

	expected := 0
	for _, member := range config.Members {
		if member.PeerId == selfId {
			continue
		}
		expected++
	}
	return expected
}

func countRemoteGroupMembers(config *GroupConfig, selfId string) int {
	if config == nil {
		return 0
	}

	count := 0
	for _, member := range config.Members {
		if member.PeerId == "" || member.PeerId == selfId {
			continue
		}
		count++
	}
	return count
}

type groupPeerDialState struct {
	failureCount int
	nextAllowed  time.Time
	inFlight     bool
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

	backoff := GroupDiscoveryWarmInterval
	for i := 1; i < failureCount-1; i++ {
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

func (n *Node) beginGroupPeerDial(peerId string, now time.Time) (bool, time.Duration, bool) {
	return n.beginGroupPeerDialWithMode(peerId, now, false)
}

func (n *Node) beginGroupPeerDialWithMode(peerId string, now time.Time, ignoreCooldown bool) (bool, time.Duration, bool) {
	n.mu.Lock()
	defer n.mu.Unlock()

	if n.groupDialBackoff == nil {
		n.groupDialBackoff = make(map[string]groupPeerDialState)
	}

	state := n.groupDialBackoff[peerId]
	if state.inFlight {
		return false, 0, true
	}
	if !ignoreCooldown && now.Before(state.nextAllowed) {
		return false, state.nextAllowed.Sub(now), false
	}

	state.inFlight = true
	n.groupDialBackoff[peerId] = state
	return true, 0, false
}

func waitForTopicPeerCount(topic *pubsub.Topic, baseline, wantAtLeast int, timeout time.Duration) int {
	if topic == nil {
		return 0
	}

	best := len(topic.ListPeers())
	if best < baseline {
		best = baseline
	}
	if best >= wantAtLeast || timeout <= 0 {
		return best
	}

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		time.Sleep(GroupPublishPeerPoll)
		current := len(topic.ListPeers())
		if current > best {
			best = current
		}
		if current >= wantAtLeast {
			return current
		}
	}

	return best
}

func (n *Node) ensureGroupTopicPeersBeforePublish(
	groupId string,
	config *GroupConfig,
	senderPeerId string,
	topic *pubsub.Topic,
) int {
	if topic == nil {
		return 0
	}

	initialPeers := len(topic.ListPeers())
	expectedPeers := countRemoteGroupMembers(config, senderPeerId)
	if expectedPeers <= 0 || initialPeers >= expectedPeers {
		return initialPeers
	}

	n.emitEvent("group:discovery", map[string]interface{}{
		"groupId":       groupId,
		"step":          "publish_peer_refresh_begin",
		"topicPeers":    initialPeers,
		"expectedPeers": expectedPeers,
	})

	settleWait := GroupPublishPartialPeerSettleWait
	if initialPeers == 0 {
		// When there are no live topic peers at all, keep only a tiny foreground
		// promotion window. Durable inbox fallback is already racing in parallel,
		// so user-tapped sends should not sit on a long pubsub preflight.
		settleWait = GroupPublishZeroPeerSettleWait
	}

	n.dialKnownGroupMembers(groupId, true)
	peerCount := waitForTopicPeerCount(
		topic,
		initialPeers,
		expectedPeers,
		settleWait,
	)

	n.emitEvent("group:discovery", map[string]interface{}{
		"groupId":       groupId,
		"step":          "publish_peer_refresh_done",
		"topicPeers":    peerCount,
		"expectedPeers": expectedPeers,
		"promoted":      peerCount > initialPeers,
		"settleWaitMs":  settleWait.Milliseconds(),
	})

	return peerCount
}

func (n *Node) finishGroupPeerDial(peerId string, success bool, now time.Time) {
	n.mu.Lock()
	defer n.mu.Unlock()

	if n.groupDialBackoff == nil {
		n.groupDialBackoff = make(map[string]groupPeerDialState)
	}

	state := n.groupDialBackoff[peerId]

	if success {
		delete(n.groupDialBackoff, peerId)
		return
	}

	state.failureCount++
	state.nextAllowed = now.Add(groupPeerDialBackoff(state.failureCount))
	state.inFlight = false
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
	dialKnownMembers bool,
) (executed bool, registered bool) {
	release, err := n.acquireGroupRecoverySlot(ctx)
	if err != nil {
		return false, false
	}
	defer release()

	if dialKnownMembers {
		n.dialKnownGroupMembers(groupId, false)
	}

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
	warmRetriesRemaining := GroupDiscoveryWarmRetries

	// Try direct recovery immediately using already-known non-relay addresses.
	// Foreground peers on the same network should not wait for relay warm-up
	// before attempting to become live topic peers.
	n.dialKnownGroupMembersDirectOnly(groupId)

	// Wait for relay to be ready before relay-assisted dialing/registering.
	select {
	case <-n.relayReady:
	case <-ctx.Done():
		return
	}

	// Recover live member-to-member connectivity immediately once a relay path
	// exists. Waiting on our own circuit address here strands active groups in
	// the "success_no_peers" path even though the members are online.
	if executed, _ := n.runGroupDiscoveryCycle(ctx, groupId, ns, false, true); !executed {
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
	// then re-dial known members and register/discover. The second known-member
	// pass is what lets a late foreground peer join during the warm retry window
	// instead of waiting for the next periodic tick.
	executed, registeredNow := n.runGroupDiscoveryCycle(ctx, groupId, ns, true, true)
	if !executed {
		return
	}
	registered = registeredNow

	interval := GroupDiscoveryInterval
	consecutiveFailures := 0
	afterInitialConnected := n.countConnectedGroupMembers(groupId)
	expectedInitialConnected := n.expectedConnectedGroupMembers(groupId)
	if expectedInitialConnected > 0 && afterInitialConnected < expectedInitialConnected {
		interval = GroupDiscoveryWarmInterval
	}

	for {
		wait := interval
		if interval > GroupDiscoveryWarmInterval {
			wait = jitterDuration(interval, GroupDiscoveryJitterFactor, rand.Int63n)
		}
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
		if executed, _ := n.runGroupDiscoveryCycle(ctx, groupId, ns, false, true); !executed {
			if registered {
				if err := n.RendezvousUnregister(ns, nil); err != nil {
					log.Printf("[PUBSUB] Group %s: rendezvous unregister failed: %v", groupId, err)
				}
			}
			return
		}

		// Check AFTER dialing.
		afterConnected := n.countConnectedGroupMembers(groupId)
		expectedConnected := n.expectedConnectedGroupMembers(groupId)

		if expectedConnected == 0 || afterConnected >= expectedConnected {
			// All currently-known members are connected — return to the slower
			// maintenance cadence and reset the fast foreground catch-up window.
			consecutiveFailures = 0
			warmRetriesRemaining = GroupDiscoveryWarmRetries
			interval = GroupDiscoveryInterval
			continue
		}

		if afterConnected > beforeConnected {
			// We made partial progress but still have missing members. Keep a
			// short retry cadence so a late foreground peer can join promptly.
			consecutiveFailures = 0
			warmRetriesRemaining = GroupDiscoveryWarmRetries
			interval = GroupDiscoveryWarmInterval
			continue
		}

		if warmRetriesRemaining > 0 {
			warmRetriesRemaining--
			interval = GroupDiscoveryWarmInterval
			continue
		}

		// Missing peers are still not reachable after the warm retry window.
		// Back off, but start from the short warm interval rather than jumping
		// straight to the full 30 s cadence after the first failure.
		if interval < GroupDiscoveryWarmInterval {
			interval = GroupDiscoveryWarmInterval
		}
		consecutiveFailures++
		interval = interval * 2
		if interval > MaxGroupDiscoveryBackoff {
			interval = MaxGroupDiscoveryBackoff
		}
		log.Printf("[PUBSUB] Group %s: discovery still missing peers (connected=%d/%d, streak=%d), backing off to %v",
			groupId, afterConnected, expectedConnected, consecutiveFailures, interval)
		n.emitEvent("group:discovery", map[string]interface{}{
			"groupId":             groupId,
			"step":                "backoff",
			"connectedMembers":    afterConnected,
			"expectedMembers":     expectedConnected,
			"consecutiveFailures": consecutiveFailures,
			"nextInterval":        interval.String(),
		})
	}
}

// findMember returns the GroupMember with the given peerId, or nil if not found.
func findMember(config *GroupConfig, peerId string) *GroupMember {
	if config == nil {
		return nil
	}

	for i := range config.Members {
		if config.Members[i].PeerId == peerId {
			return &config.Members[i]
		}
	}
	return nil
}
