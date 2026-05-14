package node

import (
	"context"
	"encoding/json"
	"log"
	"strings"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"

	"github.com/mknoon/go-mknoon/internal"
)

type groupValidationFeedbackPayload struct {
	Type            string `json:"type"`
	GroupId         string `json:"groupId"`
	MessageId       string `json:"messageId"`
	Reason          string `json:"reason"`
	EnvelopeType    string `json:"envelopeType"`
	KeyEpoch        int    `json:"keyEpoch"`
	RecipientPeerId string `json:"recipientPeerId,omitempty"`
}

func (n *Node) sendGroupValidationRejectFeedback(groupId, reason string, pid peer.ID, env *internal.GroupEnvelope, keyEpoch int) {
	if n == nil || env == nil || env.Type != "group_message" {
		return
	}
	messageId := strings.TrimSpace(env.MessageId)
	if messageId == "" {
		return
	}
	if transportPeerId := strings.TrimSpace(env.SenderTransportPeerId); transportPeerId != "" && transportPeerId != pid.String() {
		return
	}

	n.mu.RLock()
	h := n.host
	ctx := n.ctx
	localPeerId := n.peerId
	n.mu.RUnlock()
	if h == nil || ctx == nil || pid.String() == localPeerId {
		return
	}

	payload := groupValidationFeedbackPayload{
		Type:            "group_validation_rejected",
		GroupId:         groupId,
		MessageId:       messageId,
		Reason:          reason,
		EnvelopeType:    env.Type,
		KeyEpoch:        keyEpoch,
		RecipientPeerId: localPeerId,
	}

	go func() {
		openStream := func() (network.Stream, error) {
			streamCtx, cancel := context.WithTimeout(ctx, InteractiveSendTimeout)
			defer cancel()
			streamCtx = network.WithDialPeerTimeout(streamCtx, InteractiveSendTimeout)
			streamCtx = network.WithAllowLimitedConn(streamCtx, "group-validation-feedback")
			return h.NewStream(streamCtx, pid, GroupValidationFeedbackProtocol)
		}

		s, err := openStream()
		if err != nil && isRetryableChatStreamOpenError(err) {
			if healErr := n.recoverPeerForSend(h, pid, pid.String(), InteractiveSendTimeout); healErr != nil {
				log.Printf("[PUBSUB] validation feedback peer self-heal failed: %v", healErr)
			} else {
				s, err = openStream()
			}
		}
		if err != nil {
			log.Printf("[PUBSUB] validation feedback stream open failed: %v", err)
			return
		}
		defer s.Close()

		_ = s.SetWriteDeadline(time.Now().Add(StreamWriteDeadline))
		data, err := json.Marshal(payload)
		if err != nil {
			log.Printf("[PUBSUB] validation feedback marshal failed: %v", err)
			return
		}
		if err := writeFrame(s, data); err != nil {
			log.Printf("[PUBSUB] validation feedback write failed: %v", err)
		}
	}()
}

func (n *Node) handleGroupValidationFeedback(s network.Stream) {
	defer s.Close()
	_ = s.SetReadDeadline(time.Now().Add(InboundReadDeadline))

	data, err := readFrame(s)
	if err != nil {
		log.Printf("[PUBSUB] validation feedback read failed: %v", err)
		return
	}

	var payload groupValidationFeedbackPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		log.Printf("[PUBSUB] validation feedback parse failed: %v", err)
		return
	}
	if payload.Type != "group_validation_rejected" ||
		strings.TrimSpace(payload.GroupId) == "" ||
		strings.TrimSpace(payload.MessageId) == "" ||
		strings.TrimSpace(payload.Reason) == "" {
		log.Printf("[PUBSUB] validation feedback invalid payload")
		return
	}

	remotePeerId := s.Conn().RemotePeer().String()
	n.mu.RLock()
	_, joined := n.groupConfigs[payload.GroupId]
	n.mu.RUnlock()
	if !joined {
		return
	}

	n.emitEvent("group:publish_validation_rejected", map[string]interface{}{
		"groupId":           payload.GroupId,
		"messageId":         payload.MessageId,
		"reason":            payload.Reason,
		"envelopeType":      payload.EnvelopeType,
		"keyEpoch":          payload.KeyEpoch,
		"recipientPeerId":   remotePeerId,
		"recipientPeerHash": pubsubAuthorizationRejectHash(remotePeerId),
	})
}
