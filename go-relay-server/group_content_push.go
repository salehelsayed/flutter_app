package main

import (
	"context"
	"os"
	"strings"

	"firebase.google.com/go/v4/messaging"
)

// G26: strict-authority group content is the only group traffic that never
// reaches the group topic.
//
// A Plan-377 strict/fresh-authority group send does NOT publish through the Go
// group pubsub path. It signs one `group_offline_replay` envelope and stores it
// per recipient into the DIRECT inbox under the `group_content_v1` ack-custody
// namespace. The relay admits and stores that envelope
// (`extractAckCustodyGroupContentDedupeKey`), but the direct push seam only
// recognized two shapes: a `type: message_reaction` direct reaction, and the
// `envelope["type"]` switch in `extractChatPushMetadata`. A replay envelope has
// NO `type` field at all, so it fell to that switch's default and produced
// `ShouldNotify: false`.
//
// The consequence was total: a strict group's messages were delivered to
// custody and then sat there silently. A killed or backgrounded recipient got
// no card, no wake, and no counter — §1.3's `Suspended/killed → FCM wake → Card`
// row was unreachable on that lane by construction.
//
// The envelope already carries every field the ordinary group push needs
// (`groupId`, `keyEpoch`, top-level `ciphertext`/`nonce`, `messageId`,
// `senderTransportPeerId`), and `addGroupEncryptedPushData` already reads that
// exact shape — so this file routes it through the SAME `buildGroupPushMessage`
// the group topic lane uses. The recipient needs no change: it routes on the
// `type: group_message` data key it already handles, and the envelope's
// plaintext is the id-complete inbox payload, so the recipient-side plaintext
// parity check agrees with the outer push.
const (
	groupContentPushEnabledEnv = "GROUP_CONTENT_PUSH_ENABLED"

	groupContentPayloadTypeMessage  = "group_message"
	groupContentPayloadTypeReaction = "group_reaction"
)

// groupContentPushMetadata is the relay-visible, content-free subset of a
// strict-authority group content envelope. Text, media, sender display name and
// group name all stay inside the ciphertext; the relay forwards only routing.
type groupContentPushMetadata struct {
	GroupID               string
	SenderTransportPeerID string
	MessageID             string
	PayloadType           string
}

// extractGroupContentPushMetadata classifies a stored direct-inbox envelope.
//
// `recognized` means the envelope IS strict group content, so the caller must
// not fall through to the ordinary chat-metadata switch. `eligible` means it is
// additionally a wake-able group MESSAGE with every routing field present.
//
// Reactions are deliberately recognized-but-not-eligible: they carry their own
// audience rule (author-only alerting, PRD §6.5) and a separate notification
// extension grammar, and routing them through the group-message push would
// alert the wrong people. They stay silent custody until that lane is built.
func extractGroupContentPushMetadata(message string) (
	metadata groupContentPushMetadata,
	recognized bool,
	eligible bool,
) {
	envelope, ok := decodeJSONObjectPreservingNumbers(message)
	if !ok {
		return groupContentPushMetadata{}, false, false
	}
	if exactString(envelope["kind"]) != groupOfflineReplayEnvelopeKind ||
		exactString(envelope["custodyKind"]) != ackCustodyGroupContentKind {
		return groupContentPushMetadata{}, false, false
	}

	metadata = groupContentPushMetadata{
		GroupID:               exactString(envelope["groupId"]),
		SenderTransportPeerID: exactString(envelope["senderTransportPeerId"]),
		MessageID:             exactString(envelope["messageId"]),
		PayloadType:           exactString(envelope["payloadType"]),
	}
	if metadata.PayloadType != groupContentPayloadTypeMessage {
		return metadata, true, false
	}
	// Every field below is one the push cannot route without. A missing one is
	// silent custody, never a partially-addressed wake.
	if !exactJSONInteger(envelope["version"], 1) ||
		metadata.GroupID == "" ||
		metadata.SenderTransportPeerID == "" ||
		metadata.MessageID == "" ||
		exactString(envelope["ciphertext"]) == "" ||
		exactString(envelope["nonce"]) == "" {
		return metadata, true, false
	}
	return metadata, true, true
}

// sendGroupContentNotificationForRoute forwards the already-selected route to
// the shared gateway, building the same group push the topic lane builds.
//
// Reusing `buildGroupPushMessage` is the point: its oversized-envelope and
// unusable-envelope fallbacks (which degrade to a routing-only
// `preview_unavailable` push rather than dropping the wake) apply here
// unchanged, so a strict group behaves exactly like an ordinary one.
func (ps *PushService) sendGroupContentNotificationForRoute(
	ctx context.Context,
	toPeerID string,
	route pushRouteLease,
	metadata groupContentPushMetadata,
	message string,
) {
	ps.sendSelectedPushThroughGateway(
		ctx,
		toPeerID,
		route,
		"",
		func() *messaging.Message {
			return buildGroupPushMessage(
				"",
				metadata.GroupID,
				metadata.SenderTransportPeerID,
				metadata.MessageID,
				message,
			)
		},
	)
}

func loadGroupContentPushEnabledFromEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(groupContentPushEnabledEnv))) {
	case "1", "true":
		return true
	default:
		return false
	}
}
