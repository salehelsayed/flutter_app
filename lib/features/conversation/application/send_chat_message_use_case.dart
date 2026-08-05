import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/chat_console_logger.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/application/outgoing_direct_private_transport_settlement.dart';
import 'package:flutter_app/features/conversation/application/outgoing_live_deadline.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

/// Interactive send budget for local WiFi attempts.
const Duration interactiveLocalBudget = Duration(milliseconds: 1500);

/// Interactive send budget for the overall direct send path.
const Duration interactiveDirectBudget = Duration(seconds: 2);

/// Backwards-compatible name for the ordinary outgoing live-leg deadline.
const Duration interactiveDirectAggregateBudget = outgoingLiveBudget;

/// Interactive send budget for the inbox store fallback path.
const Duration interactiveInboxBudget = Duration(seconds: 3);

/// FDC-08: tight bound on the presence-hint lookup so it stays OFF the
/// send-critical path. In steady state it is a 10–15s-cached read (≈0ms); a cold
/// lookup that exceeds this degrades to `RelayPresence.unknown` (today's full
/// concurrent race) while the underlying lookup still completes and warms the
/// cache for the next send. Consulted ONLY on the not-live-reachable path.
const Duration _presenceHintBudget = Duration(milliseconds: 400);

/// Shared single-attempt cap for the live relay recovery owned by introduction
/// outbound delivery and delete-for-everyone. The conversation send path has no
/// serial probe step: FDC-02 owns its in-race relay-live leg, and an all-fail
/// race proceeds to durable inbox custody.
const int relayProbeSendAttempts = 1;

// FDC-03: the NET-REL-05 P1/P4 `kLowConfidenceWindow` (30s prior-attempt recency
// gate) is RETIRED. The concurrent durable inbox now fires for ALL unknown-
// presence sends (see the `unknownPresence` gate in `sendChatMessage`), not only
// recently-failed peers, so the recency window no longer gates anything.

/// FDC-02 §6.2a / §12 (libp2p DefaultDialRanker `RelayDelay`): the relay-LIVE
/// leg is penalized by this stagger so a viable LAN/direct leg that acks first
/// WINS and the relay-live leg is never started (suppress-on-early-win), instead
/// of relay riding the direct leg with no handicap. A warmed `/p2p-circuit` then
/// races-but-loses to a 30ms LAN hop (§6.1 by priority, not suppression).
/// Ordering invariant (TC-02-08): kRelayLegStagger > kPublicAddrTail >
/// kPrivateAddrTail.
const Duration kRelayLegStagger = Duration(milliseconds: 500);

/// FDC-02 §12 Happy-Eyeballs per-address tails. Pinned here only for the ordering
/// invariant; their PER-ADDRESS application inside a single dial is the Go host's
/// `DefaultDialRanker` (FDC-11, device-only). FDC-02 implements only the
/// leg-granularity [kRelayLegStagger] analog in Dart.
const Duration kPublicAddrTail = Duration(milliseconds: 250);
const Duration kPrivateAddrTail = Duration(milliseconds: 30);

/// FDC-02 §6.2b: a circuit-v2 LIVE relay socket is "limited" (~128KB/direction
/// before reset). Media — and any payload whose ENCRYPTED ENVELOPE
/// (`jsonString.length`) exceeds this ceiling — NEVER traverses the live relay
/// leg: it goes LAN-live, direct-live, or the durable inbox (relay-INBOX) only.
/// Headroom under the 128KB cap. (Invariant 3 / TC-02-03/04/12.)
const int kLiveRelayMaxPayloadBytes = 96 * 1024;

/// Backwards-compatible names for the two capped pre-send phases.
const Duration kDirectDiscoverBudget = outgoingDiscoverPhaseCap;
const Duration kDirectDialBudget = outgoingDialPhaseCap;

/// Legacy constant retained for callers/tests that describe the old ladder.
/// R3 committed sends no longer use this cap; they receive the exact remaining
/// native allocation while preserving the committed-ACK reserve.
const Duration kDirectSendBudget = Duration(milliseconds: 1500);

/// FDC-02 observability seam (C2). Production [P2PService] impls do NOT implement
/// this: the staggered relay-live leg's delivery is an ordinary
/// `sendMessageWithReply`, indistinguishable on the wire from the direct / reuse
/// / probe-tail sends. A host fake implements it so a test can attribute the
/// otherwise-identical circuit send to the relay-LIVE leg specifically — the
/// leg-attributable proof the leg did/did not start, since "sent while only a
/// circuit conn exists" over-counts the direct/reuse/probe sends. Mirrors the
/// existing [ReadinessProofRecorder] capability-interface pattern. Fired only
/// AFTER the suppress-on-early-win guard passes, so a suppressed leg is never
/// counted.
abstract interface class RelayLiveSendObserver {
  void noteRelayLiveSendStart();
}

void _recordSuccessfulSendReadinessProof(
  P2PService p2pService,
  ConversationMessage message,
) {
  // 'inboxed' (relay custody, doc 115) proves transport readiness exactly as
  // the pre-115 'delivered'/'inbox' terminal did: the relay accepted a store.
  if (message.status != 'delivered' && message.status != 'inboxed') {
    return;
  }

  if (p2pService case final ReadinessProofRecorder recorder) {
    final sendPath = switch (message.transport) {
      'local' => 'local',
      'relay' => 'relay',
      'inbox' => 'inbox',
      'reuse' => 'direct',
      _ => 'direct',
    };
    final source = switch (sendPath) {
      'local' => 'chat_send_local',
      'relay' => 'chat_send_relay',
      'inbox' => 'chat_send_inbox',
      _ => 'chat_send_direct',
    };
    recorder.recordSuccessfulSendProof(
      source: source,
      trigger: 'user_action',
      sendPath: sendPath,
    );
  }
}

/// Result of sending a chat message.
enum SendChatMessageResult {
  success,
  nodeNotRunning,
  invalidMessage,
  invalidPrivateMedia,
  encryptionRequired,

  /// 112 G5: an outbound attachment lacks complete blob-encryption
  /// metadata — the media mirror of [encryptionRequired]. Nothing was
  /// persisted or transported.
  mediaEncryptionRequired,
  peerNotFound,
  dialFailed,
  sendFailed,
}

const _uuid = Uuid();

/// 112 G5 fail-closed gate: every outbound 1:1 attachment must be
/// decryptable-with-v1 (key + nonce + whitelisted scheme — the sender
/// always writes the scheme explicitly) and carry the encrypted-blob
/// contentHash. Returns a reason code, or null when the attachments pass.
String? _sanitizeDirectMediaAttachments(List<MediaAttachment>? attachments) {
  if (attachments == null || attachments.isEmpty) {
    return null;
  }
  for (final attachment in attachments) {
    if (attachment.ownerLane != null &&
        attachment.ownerLane != MediaOwnerLane.direct) {
      return 'wrong_media_owner_lane';
    }
    if (!attachment.hasEncryptionMetadata ||
        attachment.encryptionScheme == null) {
      return 'missing_media_encryption_metadata';
    }
    if (attachment.contentHash == null || attachment.contentHash!.isEmpty) {
      return 'missing_media_content_hash';
    }
  }
  return null;
}

/// 301: best-effort inline thumbnail for a protected PHOTO. Photo means the
/// dual check excludes gif (mirror of the eligibility kind fork below — a bare
/// image-mime predicate would wrongly embed thumbs for protected GIFs, which
/// are representable at this seam). Any failure returns null and the send
/// proceeds without the field.
Future<Uint8List?> _generateProtectedPhotoInlineThumbnail(
  MediaAttachment attachment,
) async {
  final mime = attachment.mime.toLowerCase();
  final mediaType = attachment.mediaType.toLowerCase();
  if (mime == 'image/gif' || mediaType == 'gif') return null;
  if (!(mime.startsWith('image/') || mediaType == 'image')) return null;
  final localPath = attachment.localPath;
  if (localPath == null || localPath.isEmpty) return null;
  return ImageProcessor.generateInlineThumbnailBytes(
    inputPath: MediaFileManager.resolveStoredPathSync(localPath),
  );
}

PrivateMediaEligibility _privateMediaEligibilityForSend({
  required String text,
  required String action,
  required bool isForwarded,
  required List<MediaAttachment>? attachments,
}) {
  var kind = PrivateMediaAttachmentKind.unknown;
  if (attachments != null && attachments.length == 1) {
    final attachment = attachments.single;
    final mime = attachment.mime.toLowerCase();
    final mediaType = attachment.mediaType.toLowerCase();
    if (mime == 'image/gif' || mediaType == 'gif') {
      kind = PrivateMediaAttachmentKind.gif;
    } else if (mime.startsWith('image/') || mediaType == 'image') {
      kind = PrivateMediaAttachmentKind.image;
    } else if (mime.startsWith('video/') || mediaType == 'video') {
      kind = PrivateMediaAttachmentKind.video;
    } else if (mime.startsWith('audio/') || mediaType == 'audio') {
      kind = PrivateMediaAttachmentKind.audio;
    } else if (mime.isNotEmpty || mediaType == 'file') {
      kind = PrivateMediaAttachmentKind.file;
    }
  }
  return PrivateMediaEligibility(
    attachmentCount: attachments?.length ?? 0,
    attachmentKind: kind,
    hasTextOrCaption: text.trim().isNotEmpty,
    isEdit: action == MessagePayload.actionEdit,
    isForward: isForwarded,
  );
}

/// Sends a chat message to a contact via P2P and persists it locally.
///
/// 1. Validates text is non-empty
/// 2. Checks P2P node is running
/// 3. Builds MessagePayload with UUID
/// 4. Serializes to a v2 encrypted JSON envelope
/// 5. Atomically stages the parent/envelope (and ordinary media projection)
/// 6. Reuses an existing connection, races local WiFi with direct relay send,
///    and probes the relay only when discoverability is stale
/// 7. Atomically settles the attempt-owned transport columns
///
/// A live send that writes to the peer but does not receive an ACK attempts an
/// immediate durable inbox handoff. If the inbox handoff also fails, the
/// message is kept as truthful local `sent` state with the wire envelope
/// retained for later retry.
///
/// The wireEnvelope persist at step 5 ensures that if the app crashes during
/// the transport race (step 6), Section 1's PendingMessageRetrier can replay
/// the message without re-serializing or re-encrypting.
///
/// Returns (result, ConversationMessage?) — message is non-null on success or failure (persisted).
Future<(SendChatMessageResult, ConversationMessage?)> sendChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String action = MessagePayload.actionSend,
  String? editedAt,
  String? messageId,
  bool preassignedMessageIdIsFresh = false,
  String? timestamp,
  // F8 tier-2: a normal send stamps `dedupKey = its own id` (the default
  // below); one explicit Forward action passes its random operation token so
  // retry/redelivery dedups without coupling later actions to the source.
  String? dedupKey,
  bool isForwarded = false,
  String? createdAt,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  PrivateMediaPolicy? privateMediaPolicy,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
  StoreInInboxDetailedFn? storeInInboxDetailed,
}) async {
  final sendStopwatch = clock.stopwatch()..start();
  final liveDeadline = OutgoingLiveDeadline(() => sendStopwatch.elapsed);
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;
  final sanitizedText = sanitizeMessageText(text);
  final hasAttachments =
      mediaAttachments != null && mediaAttachments.isNotEmpty;
  final detailedInboxStore = p2pService is DetailedInboxStore
      ? p2pService as DetailedInboxStore
      : null;
  final effectiveStoreInInboxDetailed =
      storeInInboxDetailed ?? detailedInboxStore?.storeInInboxDetailed;
  var connectionReused = false;
  var sendPath = 'unknown';
  Map<String, int> stepTimings = {};
  void emitSendTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    if (!emitTimingEvent) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'hasAttachments': hasAttachments,
        'connectionReused': connectionReused,
        'sendPath': sendPath,
        ...stepTimings,
        ...details,
      },
    );
  }

  // NET-REL-04: record aggregate-only transport diagnostics at each terminal
  // send exit. Called exactly once per invocation (one rung per send).
  void recordMetrics({required String? transport, required String rung}) {
    transportMetrics?.recordRung(rung);
    transportMetrics?.recordSendLatency(
      transport: transport,
      latencyMs: sendStopwatch.elapsedMilliseconds,
    );
    if (transport != null) transportMetrics?.recordTransport(transport);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_START',
    details: {'targetPeerId': targetPrefix},
  );

  // 1. Validate
  if (sanitizedText.trim().isEmpty && !hasAttachments) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'empty_text'},
    );
    emitSendTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }

  final existingOutgoing = messageId == null
      ? null
      : await messageRepo.getMessage(messageId);
  final effectivePrivateMediaPolicy =
      privateMediaPolicy ??
      (existingOutgoing != null && !existingOutgoing.isIncoming
          ? existingOutgoing.privateMediaPolicy
          : const PrivateMediaPolicy.ordinary());
  if (effectivePrivateMediaPolicy.mode != PrivateMediaMode.ordinary) {
    final eligibility = _privateMediaEligibilityForSend(
      text: sanitizedText,
      action: action,
      isForwarded: isForwarded,
      attachments: mediaAttachments,
    );
    final validated = effectivePrivateMediaPolicy.validatedFor(eligibility);
    if (effectivePrivateMediaPolicy.isUnsupported ||
        !effectivePrivateMediaPolicy.isPrivate ||
        validated.isUnsupported) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_INVALID_PRIVATE_MEDIA',
        details: const {'reason': 'ineligible_shape'},
      );
      emitSendTiming(outcome: 'invalid_private_media');
      return (SendChatMessageResult.invalidPrivateMedia, null);
    }
  }

  if (action == MessagePayload.actionEdit &&
      (messageId == null || timestamp == null || createdAt == null)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'edit_requires_existing_message_contract'},
    );
    emitSendTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }

  // 116 EF-2 no-downgrade writer gate: a plain send under a message id whose
  // outgoing row carries editedAt or deletedAt would transmit downgraded
  // content AND poison the stored edit/deletion envelope via pre-race attempt
  // staging below. Fail closed BEFORE encryption and before any
  // persist. All UI retry paths route through retryFailedMessage, so this
  // gate has zero legitimate trips — any field occurrence is a bug detector.
  if (action == MessagePayload.actionSend && messageId != null) {
    final existing = existingOutgoing;
    if (existing != null &&
        !existing.isIncoming &&
        (existing.editedAt != null || existing.isDeleted)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED',
        details: {
          'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
          'reason': existing.isDeleted
              ? 'deleted_row_plain_send'
              : 'edited_row_plain_send',
        },
      );
      emitSendTiming(outcome: 'action_downgrade_blocked');
      return (SendChatMessageResult.invalidMessage, null);
    }
  }

  // 2. Check P2P node
  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_NODE_NOT_RUNNING',
      details: {},
    );
    emitSendTiming(outcome: 'node_not_running');
    return (SendChatMessageResult.nodeNotRunning, null);
  }

  final recipientKey = recipientMlKemPublicKey?.trim();
  if (bridge == null || recipientKey == null || recipientKey.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_ENCRYPTION_REQUIRED',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    emitSendTiming(
      outcome: 'encryption_required',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    return (SendChatMessageResult.encryptionRequired, null);
  }

  // 112 G5: outbound 1:1 media must carry complete blob-encryption
  // metadata — the media mirror of the encryptionRequired gate above
  // (mirror of the group path's _sanitizeGroupMediaAttachments). Fails
  // closed BEFORE any envelope is built or persisted so a plaintext blob
  // reference can never ride a v2 envelope.
  final mediaGateReason = _sanitizeDirectMediaAttachments(mediaAttachments);
  if (mediaGateReason != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DIRECT_MEDIA_ENCRYPTION_REQUIRED',
      details: {'reason': mediaGateReason},
    );
    emitSendTiming(
      outcome: 'media_encryption_required',
      details: {'reason': mediaGateReason},
    );
    return (SendChatMessageResult.mediaEncryptionRequired, null);
  }

  // 3. Build payload
  final resolvedMessageId = messageId ?? _uuid.v4();
  final resolvedTimestamp =
      timestamp ?? DateTime.now().toUtc().toIso8601String();
  // F8 tier-2: default a fresh normal send's dedupKey to its own id; one
  // Forward action keeps its operation token when a destination id/timestamp
  // is re-minted or retried. An existing legacy row may deliberately have a
  // NULL dedup key, which is part of the exact attempt snapshot and must not
  // be silently minted during retry staging.
  final resolvedDedupKey =
      dedupKey ??
      (messageId != null && existingOutgoing != null
          ? existingOutgoing.dedupKey
          : resolvedMessageId);
  final resolvedEditedAt = action == MessagePayload.actionEdit
      ? (editedAt ?? DateTime.now().toUtc().toIso8601String())
      : null;
  final normalizedAttachments = mediaAttachments
      ?.map(
        (attachment) => attachment.copyWith(
          messageId: resolvedMessageId,
          createdAt: attachment.createdAt.isEmpty
              ? resolvedTimestamp
              : attachment.createdAt,
          // This use case is the canonical 1:1 outbound boundary. Upload and
          // share producers intentionally cannot infer a local DB lane, but
          // every attachment leaving this boundary is direct-owned — matching
          // the typed repository write below and the row that rehydrates after
          // restart. Keep this local-only stamp out of the wire via toJson().
          ownerLane: MediaOwnerLane.direct,
        ),
      )
      .toList();

  // 301: a protected PHOTO send embeds one bounded inline thumbnail into the
  // serialized attachment map (the encrypted inner JSON), so the receiver can
  // render a restricted bubble thumbnail without any pre-open blob download.
  // The MediaAttachment model never carries the key; edits never touch it.
  final mediaJson = normalizedAttachments
      ?.map((attachment) => attachment.toJson())
      .toList();
  if (mediaJson != null &&
      effectivePrivateMediaPolicy.mode == PrivateMediaMode.protected &&
      action != MessagePayload.actionEdit &&
      normalizedAttachments!.length == 1) {
    final inlineThumbnail = await _generateProtectedPhotoInlineThumbnail(
      normalizedAttachments.single,
    );
    if (inlineThumbnail != null) {
      mediaJson[0] = {
        ...mediaJson[0],
        kProtectedPhotoInlineThumbnailKey: base64Encode(inlineThumbnail),
      };
    }
  }

  final payload = MessagePayload(
    id: resolvedMessageId,
    text: sanitizedText,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    timestamp: resolvedTimestamp,
    action: action,
    editedAt: resolvedEditedAt,
    quotedMessageId: quotedMessageId,
    media: mediaJson,
    dedupKey: resolvedDedupKey,
    isForwarded: isForwarded,
    privateMediaPolicy: effectivePrivateMediaPolicy,
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'queued',
    text: sanitizedText,
  );

  // 4. Serialize as v2 encrypted envelope.
  String jsonString;
  try {
    final innerJson = payload.toInnerJson();
    final encryptStopwatch = Stopwatch()..start();
    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientKey,
      plaintext: innerJson,
    );
    encryptStopwatch.stop();
    stepTimings['encryptMs'] = encryptStopwatch.elapsedMilliseconds;
    if (encryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ENCRYPT_FAILED',
        details: {
          'errorCode': encryptResult['errorCode'],
          'errorMessage': encryptResult['errorMessage'],
        },
      );
      emitSendTiming(
        outcome: 'encrypt_failed',
        details: {'errorCode': encryptResult['errorCode']},
      );
      return (SendChatMessageResult.sendFailed, null);
    }
    jsonString = MessagePayload.buildEncryptedEnvelope(
      id: resolvedMessageId,
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    emitSendTiming(outcome: 'encrypt_error');
    return (SendChatMessageResult.sendFailed, null);
  }

  logChatWireEnvelope(
    direction: 'OUT',
    messageId: resolvedMessageId,
    wireJson: jsonString,
  );

  // SECTION 4 CONTRACT: the exact attempt and wireEnvelope are persisted
  // BEFORE the transport race. If the app crashes after this point, Section
  // 1's PendingMessageRetrier can replay the attempt without re-serializing or
  // re-encrypting.
  final isOutgoingPrivateOneMoreLook =
      effectivePrivateMediaPolicy.version == 1 &&
      (effectivePrivateMediaPolicy.mode == PrivateMediaMode.protected ||
          effectivePrivateMediaPolicy.mode == PrivateMediaMode.viewOnce);
  final ordinaryMutationRepo =
      messageRepo is OutgoingTransportMutationRepository
      ? messageRepo as OutgoingTransportMutationRepository
      : null;
  if (isOutgoingPrivateOneMoreLook) {
    final handedOff =
        messageId != null &&
        await _commitOutgoingDirectPrivateEnvelopeForTransport(
          messageId: messageId,
          envelope: jsonString,
          attachments: normalizedAttachments,
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );
    if (!handedOff) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_PRIVATE_ENVELOPE_HANDOFF_REFUSED',
        details: {
          'id': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
        },
      );
      emitSendTiming(outcome: 'private_envelope_handoff_refused');
      return (SendChatMessageResult.sendFailed, null);
    }
  } else {
    final hasOrdinaryMedia = normalizedAttachments?.isNotEmpty ?? false;
    if (ordinaryMutationRepo == null ||
        (hasOrdinaryMedia &&
            mediaAttachmentRepo is! OutgoingOrdinaryAttemptStagingRepository)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ATTEMPT_STAGE_REFUSED',
        details: {
          'id': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
          'reason': ordinaryMutationRepo == null
              ? 'missing_message_capability'
              : 'missing_media_capability',
        },
      );
      emitSendTiming(outcome: 'attempt_stage_refused');
      return (SendChatMessageResult.sendFailed, null);
    }

    final attemptKind = action == MessagePayload.actionEdit
        ? OutgoingOrdinaryAttemptKind.edit
        : messageId == null || preassignedMessageIdIsFresh
        ? OutgoingOrdinaryAttemptKind.fresh
        : OutgoingOrdinaryAttemptKind.existing;
    final expectedAttempt = attemptKind == OutgoingOrdinaryAttemptKind.fresh
        ? null
        : existingOutgoing;
    final stagedBase = payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'sending',
      createdAt: attemptKind == OutgoingOrdinaryAttemptKind.fresh
          ? (createdAt ?? resolvedTimestamp)
          : (createdAt ?? existingOutgoing?.createdAt ?? resolvedTimestamp),
      editedAt: resolvedEditedAt,
      wireEnvelope: jsonString,
    );
    // Runtime-only ordinary/disappearing lifecycle fields are not authored by
    // this transport attempt. Preserve the exact observed values so staging's
    // full snapshot CAS detects crossed work without resetting them.
    final stagedAttempt = expectedAttempt == null
        ? stagedBase.copyWith(media: normalizedAttachments ?? const [])
        : stagedBase.copyWith(
            readAt: expectedAttempt.readAt,
            privateMediaState: expectedAttempt.privateMediaState,
            privateMediaReceivedAtMs: expectedAttempt.privateMediaReceivedAtMs,
            privateMediaExpiresAtMs: expectedAttempt.privateMediaExpiresAtMs,
            privateMediaRevealedAtMs: expectedAttempt.privateMediaRevealedAtMs,
            privateMediaTerminalAtMs: expectedAttempt.privateMediaTerminalAtMs,
            privateMediaClockHighWaterMs:
                expectedAttempt.privateMediaClockHighWaterMs,
            media: normalizedAttachments ?? const [],
          );
    try {
      final staged = hasOrdinaryMedia
          ? await (mediaAttachmentRepo
                    as OutgoingOrdinaryAttemptStagingRepository)
                .stageOutgoingOrdinaryAttemptWithMedia(
                  messageMutationRepository: ordinaryMutationRepo,
                  expected: expectedAttempt,
                  staged: stagedAttempt,
                  attachments: normalizedAttachments!,
                  kind: attemptKind,
                )
          : await ordinaryMutationRepo.stageOutgoingOrdinaryAttempt(
              expected: expectedAttempt,
              staged: stagedAttempt,
              kind: attemptKind,
            );
      if (!staged.authorizesTransport) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_ATTEMPT_STAGE_REFUSED',
          details: {
            'id': resolvedMessageId.length > 8
                ? resolvedMessageId.substring(0, 8)
                : resolvedMessageId,
            'reason': staged.outcome.name,
          },
        );
        emitSendTiming(
          outcome: 'attempt_stage_refused',
          details: {'reason': staged.outcome.name},
        );
        return (SendChatMessageResult.sendFailed, null);
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ATTEMPT_STAGE_ERROR',
        details: {
          'id': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
          'error': error.toString(),
        },
      );
      emitSendTiming(outcome: 'attempt_stage_error');
      return (SendChatMessageResult.sendFailed, null);
    }
  }

  // LAN visibility is routing metadata, not delivery authority. Read it once
  // for discovery/inbox scheduling, but never use it to exclude an existing
  // authenticated target-Peer-ID stream from the reuse path below.
  final isLocalPeer = p2pService.isLocalPeer(targetPeerId);

  // 4.5. Check for existing connected peer first (connection reuse).
  // If the peer is already connected, try to send directly without
  // rediscovering — this is the fastest interactive path.
  final isAlreadyConnected = p2pService.currentState.connections.any(
    (c) => c.peerId == targetPeerId,
  );
  // FDC-02 (C1 resolution A): a peer whose ONLY live connection is a
  // `/p2p-circuit` must not reuse-short-circuit ahead of the race. The full race
  // preserves the independently staggered relay-LIVE proof opportunity. A peer
  // with any direct connection still uses the authenticated reuse fast path.
  final isCircuitOnlyConnected = _isCircuitOnlyConnected(
    p2pService,
    targetPeerId,
  );
  _RaceResult? priorWritten;

  if (isAlreadyConnected && !isCircuitOnlyConnected) {
    connectionReused = true;
    sendPath = 'reuse';
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_REUSE_CONNECTION',
      details: {'targetPeerId': targetPrefix},
    );
    var reuseWritten = false;
    try {
      final timeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
      if (timeoutMs != null) {
        final reuseSendStopwatch = Stopwatch()..start();
        final sendResult = await p2pService.sendMessageWithReply(
          targetPeerId,
          jsonString,
          timeoutMs: timeoutMs,
        );
        reuseSendStopwatch.stop();
        stepTimings = {
          'sendMs': reuseSendStopwatch.elapsedMilliseconds,
          if (sendResult.streamOpenMs != null)
            'streamOpenMs': sendResult.streamOpenMs!,
          if (sendResult.writeMs != null) 'writeMs': sendResult.writeMs!,
          if (sendResult.ackWaitMs != null) 'ackWaitMs': sendResult.ackWaitMs!,
        };
        reuseWritten = sendResult.sent;
        if (sendResult.sent) {
          final reuseVia = _resolveGoSendTransport(
            p2pService,
            targetPeerId,
            sendResult,
          );
          final reuseEvidence = _RaceResult.succeeded(
            via: reuseVia,
            explicitAck: sendResult.acked == true,
            authenticated: true,
            stepTimings: stepTimings,
          );
          if (reuseEvidence.provesDeviceDeliveryForCurrentProtocol) {
            transportMetrics?.recordAttempt(leg: 'reuse', succeeded: true);
            recordMetrics(transport: reuseVia, rung: 'reuse');
            return _completeSuccessfulSend(
              p2pService: p2pService,
              messageRepo: messageRepo,
              payload: payload,
              targetPeerId: targetPeerId,
              jsonString: jsonString,
              acknowledged: true,
              via: reuseVia,
              resolvedMessageId: resolvedMessageId,
              text: sanitizedText,
              createdAt: createdAt,
              editedAt: resolvedEditedAt,
              mediaAttachmentRepo: mediaAttachmentRepo,
              attachments: normalizedAttachments,
              isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
              sendStopwatch: sendStopwatch,
              emitTimingEvent: emitTimingEvent,
              extraTimingDetails: {
                'connectionReused': true,
                'sendPath': 'reuse',
                ...stepTimings,
              },
            );
          }
          priorWritten ??= reuseEvidence;
        }
      }
    } catch (_) {
      // Connection reuse failed — fall through to race
    }
    // A completed write remains useful attempt telemetry, but only an explicit
    // affirmative ACK from this authenticated libp2p stream may short-circuit
    // and mint delivery. Written/uncommitted reuse falls through to the race.
    transportMetrics?.recordAttempt(leg: 'reuse', succeeded: reuseWritten);
    connectionReused = false;
    sendPath = 'unknown';
    stepTimings = {};
  }

  // 5. Race: local WiFi and direct discover/dial/send in parallel.
  // The first authenticated commitment settles. Earlier written-only evidence
  // remains available to the inbox/retry funnel if no live leg proves delivery.
  // (`isLocalPeer` is read above the reuse block — FDC-04 RC2 hoist.)

  // NET-REL-05 P3 (sticky transport): the last-known-good LIVE transport for
  // this peer, or null if none/expired/stale. Returning non-null is a VALIDITY
  // guarantee, not a hint: `lastKnownGoodTransport` only survives if the entry
  // is within TTL AND (for 'local') the peer is still LAN-visible, and the
  // P2PServiceImpl invalidation paths (disconnect / relay-health transition /
  // addresses-updated) drop the entry the moment the path could have gone stale
  // (see p2p_service_learned_transport_invalidation_test.dart). That guarantee
  // is what lets the SHORT-CIRCUIT below skip discover/dial entirely. Reading it
  // never blocks: null (expired/stale/absent) degenerates to the full cold race,
  // identical to today, so a stale/dead preference can never trap the send.
  final learned = p2pService.lastKnownGoodTransport(targetPeerId);
  // A learned local label identifies only the unauthenticated WebSocket route,
  // so it may not short-circuit authenticated work. Learned direct/relay paths
  // still reuse a target-Peer-ID stream, including when mDNS also sees the peer.
  if (learned == 'direct' || learned == 'relay') {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_STICKY_TRANSPORT',
      details: {'targetPeerId': targetPrefix, 'learned': learned},
    );

    // NET-REL-05 P3 short-circuit: a fresh+valid learned authenticated transport
    // lets us REUSE the known-good direct/relay path via sendMessageWithReply,
    // WITHOUT re-paying discovery/dial. This is
    // the only place that skips discover/dial on a NON-connected peer; it is
    // gated behind the now-tested invalidation so a stale entry never reaches
    // here. On ANY miss/failure of this attempt we fall THROUGH to today's full
    // PARALLEL race (NOT a serial try-then-timeout-then-race), so the unhappy
    // path is never slower than a cold send.
    final shortCircuit = await _tryLearnedShortCircuit(
      p2pService,
      targetPeerId,
      jsonString,
      learned: learned!,
      liveDeadline: liveDeadline,
      transportMetrics: transportMetrics,
    );
    if (shortCircuit != null &&
        shortCircuit.provesDeviceDeliveryForCurrentProtocol) {
      sendPath = 'sticky';
      stepTimings = shortCircuit.stepTimings;
      // The sticky short-circuit reuses the learned known-good path WITHOUT
      // re-discovery/dial — the same census semantics as connection 'reuse', so
      // it lands in the 'reuse' rung. The 'sticky' label is preserved in the
      // FLOW timing/observability event below (sendPath) for diagnosis.
      recordMetrics(transport: shortCircuit.via, rung: 'reuse');
      return _completeSuccessfulSend(
        p2pService: p2pService,
        messageRepo: messageRepo,
        payload: payload,
        targetPeerId: targetPeerId,
        jsonString: jsonString,
        acknowledged: true,
        via: shortCircuit.via!,
        resolvedMessageId: resolvedMessageId,
        text: sanitizedText,
        createdAt: createdAt,
        editedAt: resolvedEditedAt,
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: normalizedAttachments,
        isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
        sendStopwatch: sendStopwatch,
        emitTimingEvent: emitTimingEvent,
        extraTimingDetails: {
          'connectionReused': false,
          'sendPath': 'sticky',
          'learned': learned,
          ...shortCircuit.stepTimings,
        },
      );
    }
    if (shortCircuit != null && shortCircuit.written) {
      priorWritten ??= shortCircuit;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_STICKY_FALLBACK',
      details: {
        'targetPeerId': targetPrefix,
        'learned': learned,
        'reason': shortCircuit?.reason ?? 'unknown',
      },
    );
  }

  // FDC-03 (R6 / P0-2): fire the durable inbox copy CONCURRENTLY with the live
  // race for ALL "unknown presence" sends — the peer is not already-connected
  // (no reuse path), not on the LAN, AND has no live peer connection. The 30s
  // prior-attempt recency gate (the old NET-REL-05 P1/P4 "low confidence" lookup)
  // is REMOVED: a first-ever / cold notif-tap send is exactly the case that needs
  // fast durable custody, yet it is never "low confidence" (no prior failed
  // attempt exists) and so used to pay the slow serial probe→inbox tail. The
  // three STRUCTURAL guards are KEPT for scheduling/cost: connected and LAN-
  // visible sends use the live race first, and any written-but-uncommitted
  // result still reaches the sequential inbox backstop. Presence-aware
  // reachable→lazy / unreachable→inbox-first emphasis (§6.3) is FDC-08; until
  // then everything non-connected/non-local is treated as UNKNOWN → concurrent
  // inbox. Dropping the recency lookup also removes one DB await from the hot
  // send path.
  final unknownPresence =
      !isAlreadyConnected &&
      !isLocalPeer &&
      !p2pService.isConnectedToPeer(targetPeerId);

  // 187: when the 183 keepalive has latched this ACTIVE peer as dropped, the
  // direct discover/dial WAN leg to it is doomed — it burns ~1.5 s dialing a
  // peer that cannot answer while the concurrent durable inbox (fired below) has
  // already secured custody. Skip ONLY that WAN leg (Option A: the leg stays in
  // raceFutures[1], short-circuited at its top — LAN leg + inbox untouched).
  // Gated on [unknownPresence] so a connected/local/reachable peer (which took
  // the reuse fast path above or has a live conn) is NEVER skipped, keeping the
  // FDC-01/02 budget ladder intact for every non-dropped peer. Consulted via the
  // off-base [PeerDropSignal] capability so the ~31 base-P2PService fakes are
  // untouched; a service that doesn't implement it degrades to "never skip".
  final directSkipForKeepaliveDrop =
      unknownPresence &&
      p2pService is PeerDropSignal &&
      (p2pService as PeerDropSignal).isPeerSuspectedDropped(targetPeerId);

  // Fire the durable inbox copy CONCURRENTLY (fire-and-forget) for unknown-
  // presence sends. This is a parallel durability side-effect, NOT a race
  // participant: it never feeds the transport-label completer and never calls a
  // terminal `recordMetrics(rung:...)` — only `recordAttempt(leg:'inbox')`. The
  // SAME [jsonString] envelope (identical payload.id) is used, so a duplicate
  // arrival is discarded by the receiver's messageId dedup. `concurrentInbox`
  // is awaited later (race-failure tail / unacked handoff) to short-circuit the
  // redundant sequential store and avoid a double relay write.
  // 184 (INV-3): tracks whether the live race has already committed a terminal
  // 'delivered' (acked). The concurrent-inbox custody bump below must NEVER
  // regress a live 'delivered' to 'inboxed' — this flag is captured by the
  // `.then` closure and set at the race-success-acked commit point.
  var liveDelivered = false;
  Future<bool>? concurrentInbox;
  if (unknownPresence) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'targetPeerId': targetPrefix,
      },
    );
    concurrentInbox = p2pService
        .storeInInbox(
          targetPeerId,
          jsonString,
          timeoutMs: interactiveInboxBudget.inMilliseconds,
        )
        .then((ok) async {
          transportMetrics?.recordAttempt(leg: 'inbox', succeeded: ok);
          // 184: surface the custody milestone MID-send. On a successful
          // concurrent-inbox ACK (~110 ms) advance the optimistic row's status to
          // a non-terminal 'inboxed' so the 1:1 bubble shows two ticks instead of
          // resting on the single optimistic tick until the live race resolves
          // (~1.8 s offline). The guarded transport settlement owns only the
          // attempt's transport columns and re-renders via the SAME messageChanges
          // stream the screen already admits for 'inboxed'. Guarded by
          // [liveDelivered] (INV-3) so a live 'delivered' that already won the
          // race is never regressed to 'inboxed'; fires only on ok==true (INV-4:
          // no false two-tick when custody is not secured). Status-surfacing
          // only — it never feeds the race or a terminal recordMetrics.
          if (ok && !liveDelivered) {
            if (isOutgoingPrivateOneMoreLook) {
              await _settleOutgoingDirectPrivateTransportState(
                messageRepo: messageRepo,
                mediaAttachmentRepo: mediaAttachmentRepo,
                attachments: normalizedAttachments,
                messageId: resolvedMessageId,
                expectedEnvelope: jsonString,
                status: 'inboxed',
                transport: 'inbox',
                relayExpiresAt: null,
              );
            } else {
              await ordinaryMutationRepo!.settleOutgoingOrdinaryTransport(
                messageId: resolvedMessageId,
                expectedContactPeerId: targetPeerId,
                expectedEnvelope: jsonString,
                status: 'inboxed',
                transport: 'inbox',
                relayExpiresAt: null,
                mode: OutgoingOrdinarySettlementMode.live,
              );
            }
            emitFlowEvent(
              layer: 'FL',
              event: 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
              details: {
                'id': resolvedMessageId.substring(0, 8),
                'targetPeerId': targetPrefix,
              },
            );
          }
          return ok;
        })
        .catchError((_) => false);

    // FDC-08 (§6.3) presence emphasis — consulted ONLY here on the
    // not-live-reachable path (a connected/local peer is delivered live, fast
    // path untouched). It is a HINT, NEVER a delivery gate: the durable inbox
    // copy above ALWAYS fires regardless of the hint (PRESENCE_NEVER_REPLACES_
    // INBOX / the C7 load-bearing gate). It only biases whether the live race or
    // the durable copy commits first; the FDC-02/03 race ladder below is
    // unchanged. Bounded + cache-served so it stays off the send-critical path,
    // degrading to `unknown` (today's fully-concurrent behavior) on miss/timeout.
    final presenceLookup = p2pService is RelayPresenceLookup
        ? p2pService as RelayPresenceLookup
        : null;
    var presenceEmphasis = RelayPresence.unknown;
    if (presenceLookup != null) {
      presenceEmphasis = await presenceLookup
          .lookupRelayPresence(targetPeerId)
          .timeout(_presenceHintBudget, onTimeout: () => RelayPresence.unknown);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_PRESENCE_EMPHASIS',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'targetPeerId': targetPrefix,
        'presence': presenceEmphasis.name,
      },
    );

    // `unreachable` → commit the durable copy FIRST (custody + the relay's
    // store-triggered push-to-wake) before the live race builds; the live legs
    // still run afterwards (best-effort, NEVER dropped). `reachable`/`unknown`
    // keep today's fully-concurrent behavior (lazy inbox racing the live legs).
    // This is the same single storeInInbox future (non-null here — it was just
    // created above) — awaiting it here and again in the race-failure tail never
    // produces a second relay write.
    if (presenceEmphasis == RelayPresence.unreachable) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_PRESENCE_INBOX_FIRST',
        details: {'id': resolvedMessageId.substring(0, 8)},
      );
      await concurrentInbox;
    }
  }

  // FDC-02 §6.2a/b: the staggered relay-LIVE leg joins the race only when a live
  // `/p2p-circuit` exists for the peer AND the payload may ride a limited live
  // relay socket (not media, not over [kLiveRelayMaxPayloadBytes]). Otherwise the
  // race is the existing LAN+direct pair and an all-fail send falls to the
  // durable inbox (relay-INBOX, FDC-03 territory) — never the live relay socket.
  final liveRelayEligible =
      _hasLiveCircuitConnection(p2pService, targetPeerId) &&
      _liveRelayEligible(hasAttachments, jsonString.length);

  // Build race futures
  final raceFutures = <Future<_RaceResult>>[];

  // Local WiFi path (bounded by interactiveLocalBudget). Added unconditionally:
  // when the peer is not yet in the discovered map we run a bounded
  // discover-on-send resolve first, so a cold-open same-WiFi peer can still
  // join the race within budget. If the peer is genuinely not on the LAN the
  // resolve times out to false and the parallel direct leg carries the message
  // (negative control: transport never becomes 'local').
  raceFutures.add(
    _tryLocalSendWithDiscovery(
      p2pService,
      targetPeerId,
      jsonString,
      senderPeerId,
      alreadyLocal: isLocalPeer,
      budget: interactiveLocalBudget,
      transportMetrics: transportMetrics,
    ).timeout(
      interactiveLocalBudget,
      onTimeout: () => _RaceResult.failed('local_discover_timeout'),
    ),
  );

  // Direct discover/dial/send path (bounded by interactiveDirectBudget).
  // Records its own attempt outcome inside the helper (at each terminal
  // return): the race completes on the first success, so a losing direct leg
  // may still be pending here and the caller cannot observe its result. The
  // outer timeout below does not record — the inner future resolves via its own
  // per-step budgets and records the real outcome exactly once (slightly later
  // on a slow path, which is fine for an aggregate session counter).
  raceFutures.add(
    _tryDirectSend(
      p2pService,
      targetPeerId,
      jsonString,
      liveDeadline: liveDeadline,
      transportMetrics: transportMetrics,
      // 187: when set, the direct leg short-circuits BEFORE discover/dial (the
      // leg stays present so the race's pending-count/failure classification is
      // undisturbed — Option A).
      skipForKeepaliveDrop: directSkipForKeepaliveDrop,
    ).timeout(
      // FDC-01: the OUTER cap is the aggregate (serial) ceiling, decoupled from
      // the per-step budget so a slow-but-progressing step can't be starved.
      // When it does fire the leg is genuinely stuck mid-progress on an online
      // peer, so the aggregate direct_timeout retains relay eligibility as
      // failure-classification plumbing. It does not launch another serial
      // recovery step; FDC-02's relay-live leg already participates in-race.
      liveDeadline.remaining,
      onTimeout: () =>
          _RaceResult.failed('direct_timeout', relayProbeEligible: true),
    ),
  );

  // Delivery authority is independent of route rank. The first result backed
  // by both the target Peer ID's authenticated libp2p stream and an explicit
  // affirmative ACK settles immediately. A WebSocket write (including its
  // nonce-correlated committed ACK) and an unacked libp2p write remain useful
  // transport evidence, but only for the existing inbox/retry funnel after all
  // eligible live legs have had their chance.
  final completer = Completer<_RaceResult>();
  final failures = <_RaceResult>[];
  _RaceResult? firstWritten = priorWritten;

  // FDC-02: the staggered relay-LIVE leg, added as a THIRD race future so it is
  // counted in [pendingCount] below (C4) — a fast LAN+direct DOUBLE failure
  // therefore cannot settle the race as failed before the relay penalty elapses
  // and the leg has had its chance (§6.2a / TC-02-02). It starts kRelayLegStagger
  // behind the LAN/direct legs (the penalty) and is suppressed only after an
  // authenticated explicit ACK has already completed the race. Written-only
  // evidence must not prevent the stronger relay proof from starting.
  if (liveRelayEligible) {
    raceFutures.add(
      Future<_RaceResult>(() async {
        await Future<void>.delayed(kRelayLegStagger);
        if (completer.isCompleted) {
          return _RaceResult.failed('relay_live_suppressed');
        }
        return _tryRelayLiveSend(
          p2pService,
          targetPeerId,
          jsonString,
          liveDeadline: liveDeadline,
          transportMetrics: transportMetrics,
        );
      }),
    );
  }

  var pendingCount = raceFutures.length;

  void completeWithFailure() {
    if (completer.isCompleted) return;
    var failureReason = failures.isNotEmpty
        ? failures.first.reason ?? 'unknown'
        : 'unknown';
    var relayProbeEligible = false;
    for (final failure in failures) {
      if (failure.relayProbeEligible) {
        failureReason = failure.reason ?? failureReason;
        relayProbeEligible = true;
        break;
      }
    }
    completer.complete(
      _RaceResult.failed(failureReason, relayProbeEligible: relayProbeEligible),
    );
  }

  // Wire each leg. A proving result wins immediately. Written-only results are
  // retained without suppressing any remaining authenticated attempt.
  for (final raceFuture in raceFutures) {
    void onResolved(_RaceResult result) {
      pendingCount--;
      if (result.provesDeviceDeliveryForCurrentProtocol) {
        if (!completer.isCompleted) completer.complete(result);
        return;
      }
      if (result.written) {
        firstWritten ??= result;
      } else {
        failures.add(result);
      }
      if (pendingCount <= 0 && !completer.isCompleted) {
        if (firstWritten case final written?) {
          completer.complete(written);
        } else {
          completeWithFailure();
        }
      }
    }

    raceFuture
        .then(onResolved)
        .catchError((Object e) => onResolved(_RaceResult.failed(e.toString())));
  }

  final raceResult = await completer.future;

  if (raceResult.success) {
    // 184 (INV-3): a live ACK commits a terminal 'delivered' below — mark it so
    // a late concurrent-inbox custody bump cannot regress it to 'inboxed'.
    if (raceResult.provesDeviceDeliveryForCurrentProtocol) {
      liveDelivered = true;
    }
    sendPath = raceResult.via == 'local' ? 'local' : 'direct';
    stepTimings = raceResult.stepTimings;
    recordMetrics(transport: raceResult.via, rung: sendPath);
    return _completeSuccessfulSend(
      p2pService: p2pService,
      messageRepo: messageRepo,
      payload: payload,
      targetPeerId: targetPeerId,
      jsonString: jsonString,
      acknowledged: raceResult.provesDeviceDeliveryForCurrentProtocol,
      via: raceResult.via!,
      resolvedMessageId: resolvedMessageId,
      text: sanitizedText,
      createdAt: createdAt,
      editedAt: resolvedEditedAt,
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: normalizedAttachments,
      isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
      sendStopwatch: sendStopwatch,
      emitTimingEvent: emitTimingEvent,
      // A live leg won the transport label. If a concurrent inbox copy was
      // fired for this unknown-presence send, hand its future to the unacked
      // branch so the sequential unacked->inbox handoff is skipped when the
      // durable copy already succeeded (avoids a second relay write for one
      // message). When acked, the future is ignored (no handoff runs).
      concurrentInbox: concurrentInbox,
      extraTimingDetails: {
        'connectionReused': false,
        'sendPath': sendPath,
        ...stepTimings,
      },
    );
  }

  var failureReason = raceResult.reason ?? 'unknown';

  // Persist a durable-custody (inbox) acceptance. Shared by the
  // concurrent-fallback short-circuit below and the sequential inbox tail so
  // the terminal `recordMetrics(rung:'inbox')` and status write stay identical
  // and fire exactly once. Relay-inbox acceptance is CUSTODY, not delivery
  // (doc 115): the row persists non-terminal 'inboxed' with the wire envelope
  // RETAINED so the custody sweep can re-store and a delivery receipt can
  // flip it to 'delivered'.
  Future<(SendChatMessageResult, ConversationMessage?)> persistInboxAccepted({
    required bool recordInboxAttempt,
    int? expiresAtMs,
  }) async {
    sendPath = 'inbox';
    if (recordInboxAttempt) {
      transportMetrics?.recordAttempt(leg: 'inbox', succeeded: true);
    }
    recordMetrics(transport: 'inbox', rung: 'inbox');
    final inboxedMessage = payload
        .toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: 'inboxed',
          createdAt: createdAt,
          editedAt: resolvedEditedAt,
          transport: 'inbox',
          wireEnvelope: jsonString,
        )
        .copyWith(relayExpiresAt: expiresAtMs);
    final persistedMessage = await _persistOutgoingTransportState(
      messageRepo: messageRepo,
      message: inboxedMessage,
      attachments: normalizedAttachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
      isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
      expectedEnvelope: jsonString,
      expectedContactPeerId: targetPeerId,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_SUCCESS',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'status': 'inboxed',
        'via': 'inbox',
      },
    );
    emitSendTiming(
      outcome: 'success',
      details: {'status': 'inboxed', 'via': 'inbox'},
    );
    logChatOutgoing(
      messageId: resolvedMessageId,
      toPeerId: targetPeerId,
      status: 'inboxed',
      text: sanitizedText,
    );
    _recordSuccessfulSendReadinessProof(
      p2pService,
      persistedMessage ?? inboxedMessage,
    );
    return (
      SendChatMessageResult.success,
      isOutgoingPrivateOneMoreLook
          ? persistedMessage?.copyWith(media: normalizedAttachments ?? const [])
          : persistedMessage,
    );
  }

  Future<(SendChatMessageResult, ConversationMessage?)>
  persistInboxRejectedFull() async {
    sendPath = 'inbox';
    transportMetrics?.recordAttempt(leg: 'inbox', succeeded: false);
    recordMetrics(transport: null, rung: 'failed');
    final sentMessage = payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'sent',
      createdAt: createdAt,
      editedAt: resolvedEditedAt,
      transport: 'inbox',
      wireEnvelope: jsonString,
    );
    final persistedMessage = await _persistOutgoingTransportState(
      messageRepo: messageRepo,
      message: sentMessage,
      attachments: normalizedAttachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
      isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
      expectedEnvelope: jsonString,
      expectedContactPeerId: targetPeerId,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INBOX_FULL_RETRYABLE',
      details: {'id': resolvedMessageId.substring(0, 8), 'via': 'inbox'},
    );
    emitSendTiming(
      outcome: 'retryable',
      details: {'status': 'sent', 'via': 'inbox', 'errorCode': 'INBOX_FULL'},
    );
    logChatOutgoing(
      messageId: resolvedMessageId,
      toPeerId: targetPeerId,
      status: 'sent',
      text: sanitizedText,
    );
    return (
      SendChatMessageResult.success,
      isOutgoingPrivateOneMoreLook
          ? persistedMessage?.copyWith(media: normalizedAttachments ?? const [])
          : persistedMessage,
    );
  }

  // NET-REL-05 P1/P4: the live race failed. If a concurrent durable copy was
  // fired for this unknown-presence send, wait for it before the single
  // sequential inbox fallback. If it already took custody, commit
  // 'inboxed'/'inbox' and skip the redundant `storeInInbox`; durable custody
  // lands at about the inbox budget. The inbox `recordAttempt` already fired
  // inside the concurrent future, so do not record it again here.
  if (concurrentInbox != null) {
    final concurrentOk = await concurrentInbox;
    if (concurrentOk) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY',
        details: {
          'id': resolvedMessageId.substring(0, 8),
          'reason': failureReason,
        },
      );
      return persistInboxAccepted(recordInboxAttempt: false);
    }
  }

  // FDC-03 (invariant 4 — "no serial relay-probe carrier"): the SERIAL
  // relay-probe→inbox tail is REMOVED. Live relay recovery is now FDC-02's
  // IN-RACE staggered relay-live leg (it joins the race when a live
  // `/p2p-circuit` already exists for the peer). An all-fail race for an
  // unknown-presence peer takes durable custody via the concurrent inbox copy
  // fired above (already awaited at the `concurrentInbox != null` short-circuit);
  // if that copy was null (the connected/local fall-through) or returned false,
  // the SINGLE sequential `storeInInbox` fallback below is the lone carrier —
  // preserving "exactly one relay write per message". `relayProbeEligible`
  // remains failure-classification plumbing and does not add another carrier.

  // All active paths failed — try offline inbox fallback once.
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_RACE_ALL_FAILED',
    details: {'reason': failureReason},
  );

  try {
    final inboxStopwatch = Stopwatch()..start();
    final detailedStore = effectiveStoreInInboxDetailed;
    final InboxStoreOutcome? outcome;
    final bool storedInInbox;
    if (detailedStore != null) {
      final detailedOutcome = await detailedStore(
        targetPeerId,
        jsonString,
        timeoutMs: interactiveInboxBudget.inMilliseconds,
      );
      outcome = detailedOutcome;
      storedInInbox = detailedOutcome.accepted;
    } else {
      outcome = null;
      storedInInbox = await p2pService.storeInInbox(
        targetPeerId,
        jsonString,
        timeoutMs: interactiveInboxBudget.inMilliseconds,
      );
    }
    inboxStopwatch.stop();
    stepTimings['inboxMs'] = inboxStopwatch.elapsedMilliseconds;
    if (storedInInbox) {
      return persistInboxAccepted(
        recordInboxAttempt: true,
        expiresAtMs: outcome?.expiresAtMs,
      );
    }
    if (outcome?.status == InboxStoreStatus.rejectedFull) {
      return persistInboxRejectedFull();
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INBOX_FALLBACK_ERROR',
      details: {'error': e.toString()},
    );
  }

  // Inbox fallback failed — persist with failed status.
  final failedMessage = payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'failed',
    createdAt: createdAt,
    editedAt: resolvedEditedAt,
    wireEnvelope: jsonString,
  );
  final persistedFailedMessage = await _persistOutgoingTransportState(
    messageRepo: messageRepo,
    message: failedMessage,
    attachments: normalizedAttachments,
    mediaAttachmentRepo: mediaAttachmentRepo,
    isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
    expectedEnvelope: jsonString,
    expectedContactPeerId: targetPeerId,
  );

  // Reached only after an inbox store attempt that did not succeed (returned
  // false or threw): count the failed inbox attempt before the terminal rung.
  transportMetrics?.recordAttempt(leg: 'inbox', succeeded: false);
  recordMetrics(transport: null, rung: 'failed');

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_FAILED',
    details: {'id': resolvedMessageId.substring(0, 8), 'reason': failureReason},
  );
  emitSendTiming(
    outcome: 'failed',
    details: {
      'reason': failureReason,
      'result': _resultForFailureReason(failureReason).name,
    },
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'failed',
    text: sanitizedText,
  );
  return (
    _resultForFailureReason(failureReason),
    isOutgoingPrivateOneMoreLook
        ? persistedFailedMessage?.copyWith(
            media: normalizedAttachments ?? const [],
          )
        : persistedFailedMessage,
  );
}

Future<(SendChatMessageResult, ConversationMessage?)> editChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  required String updatedText,
  required String senderUsername,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
}) {
  if (originalMessage.isIncoming) {
    return Future.value((SendChatMessageResult.invalidMessage, null));
  }
  if (originalMessage.status == 'failed') {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_EDIT_INVALID',
      details: {'reason': 'failed_message_requires_retry'},
    );
    return Future.value((SendChatMessageResult.invalidMessage, null));
  }

  return sendChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    targetPeerId: originalMessage.contactPeerId,
    text: updatedText,
    senderPeerId: originalMessage.senderPeerId,
    senderUsername: senderUsername,
    action: MessagePayload.actionEdit,
    messageId: originalMessage.id,
    timestamp: originalMessage.timestamp,
    createdAt: originalMessage.createdAt,
    quotedMessageId: originalMessage.quotedMessageId,
    dedupKey: originalMessage.dedupKey,
    isForwarded: originalMessage.isForwarded,
    mediaAttachments: originalMessage.media,
    privateMediaPolicy: originalMessage.privateMediaPolicy,
    mediaAttachmentRepo: mediaAttachmentRepo,
    bridge: bridge,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    emitTimingEvent: emitTimingEvent,
    transportMetrics: transportMetrics,
  );
}

/// Internal result of a single send path in the race.
class _RaceResult {
  /// The complete frame left this sender.
  final bool written;

  /// The native result carried an explicit `acked == true` value.
  ///
  /// This deliberately does not use [SendMessageResult.acknowledged], whose
  /// reply inference remains available to unrelated compatibility callers.
  final bool explicitAck;

  /// The attempt used the target Peer ID's authenticated libp2p stream.
  final bool authenticated;
  final String? via;
  final String? reason;
  final bool relayProbeEligible;
  final Map<String, int> stepTimings;

  bool get success => written;

  /// Delivery proof for current-version peers using the production default-on
  /// deferred-ACK contract. The wire bytes alone cannot distinguish an older or
  /// force-disabled receiver, so this remains a private orchestration claim.
  bool get provesDeviceDeliveryForCurrentProtocol =>
      written && authenticated && explicitAck;

  const _RaceResult._({
    required this.written,
    this.explicitAck = false,
    this.authenticated = false,
    this.via,
    this.reason,
    this.relayProbeEligible = false,
    this.stepTimings = const {},
  });

  factory _RaceResult.succeeded({
    required String via,
    required bool explicitAck,
    required bool authenticated,
    Map<String, int> stepTimings = const {},
  }) => _RaceResult._(
    written: true,
    explicitAck: explicitAck,
    authenticated: authenticated,
    via: via,
    stepTimings: stepTimings,
  );

  factory _RaceResult.failed(
    String reason, {
    bool relayProbeEligible = false,
    Map<String, int> stepTimings = const {},
  }) => _RaceResult._(
    written: false,
    reason: reason,
    relayProbeEligible: relayProbeEligible,
    stepTimings: stepTimings,
  );
}

String _inferDirectVsRelayForConnectedPeer(
  P2PService p2pService,
  String peerId,
) {
  final hasRelayConnection = p2pService.currentState.connections.any(
    (connection) =>
        connection.peerId == peerId &&
        connection.multiaddrs.any(
          (multiaddr) => multiaddr.contains('/p2p-circuit'),
        ),
  );
  return hasRelayConnection ? 'relay' : 'direct';
}

String _resolveGoSendTransport(
  P2PService p2pService,
  String peerId,
  SendMessageResult sendResult,
) {
  final actualTransport = sendResult.transport;
  if (actualTransport != null && actualTransport.isNotEmpty) {
    return actualTransport;
  }

  return _inferDirectVsRelayForConnectedPeer(p2pService, peerId);
}

/// FDC-02: true when the peer has at least one live `/p2p-circuit` connection —
/// the relay-LIVE leg's eligibility precondition.
bool _hasLiveCircuitConnection(P2PService p2pService, String peerId) {
  return p2pService.currentState.connections.any(
    (c) =>
        c.peerId == peerId &&
        c.multiaddrs.any((m) => m.contains('/p2p-circuit')),
  );
}

/// FDC-02 (C1 resolution A): true when EVERY live connection to the peer is a
/// `/p2p-circuit` (relay-backed). Such a peer must not take the reuse fast path,
/// so the complete proof race, including the staggered relay-LIVE leg, remains
/// available. A peer with any direct (non-circuit) connection keeps the reuse
/// short-circuit; an ambiguous empty-multiaddr connection is treated as direct.
bool _isCircuitOnlyConnected(P2PService p2pService, String peerId) {
  final peerConns = p2pService.currentState.connections
      .where((c) => c.peerId == peerId)
      .toList();
  if (peerConns.isEmpty) return false;
  return peerConns.every(
    (c) =>
        c.multiaddrs.isNotEmpty &&
        c.multiaddrs.any((m) => m.contains('/p2p-circuit')),
  );
}

/// FDC-02 §6.2b: media and oversized (encrypted envelope > [kLiveRelayMaxPayloadBytes])
/// payloads NEVER traverse the live relay leg (the circuit-v2 socket is
/// ~128KB-limited). They fall to LAN-live / direct-live / the durable inbox.
bool _liveRelayEligible(bool hasAttachments, int payloadBytes) =>
    !hasAttachments && payloadBytes <= kLiveRelayMaxPayloadBytes;

/// FDC-02: the staggered relay-LIVE leg. Sends over the existing live connection
/// — Go selects the path (normally the `/p2p-circuit`, since this leg runs only
/// when one exists and no better leg has committed) and LABELS the result
/// (relay-opportunistic, not relay-forced). Fires the [RelayLiveSendObserver]
/// seam (no-op in production) right before the send so a host test can attribute
/// this otherwise-identical `sendMessageWithReply` to the relay-live leg (C2).
/// Reaching here means the suppress-on-early-win guard already passed, so the
/// leg actually sends.
Future<_RaceResult> _tryRelayLiveSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required OutgoingLiveDeadline liveDeadline,
  TransportMetrics? transportMetrics,
}) async {
  final timeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
  if (timeoutMs == null) {
    return _RaceResult.failed('relay_live_deadline_exhausted');
  }
  if (p2pService case final RelayLiveSendObserver observer) {
    observer.noteRelayLiveSendStart();
  }
  try {
    final sendResult = await p2pService.sendMessageWithReply(
      targetPeerId,
      jsonString,
      timeoutMs: timeoutMs,
    );
    if (!sendResult.sent) {
      return _RaceResult.failed('relay_live_send_failed');
    }
    return _RaceResult.succeeded(
      via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
      explicitAck: sendResult.acked == true,
      authenticated: true,
    );
  } on TimeoutException {
    return _RaceResult.failed('relay_live_timeout');
  } catch (e) {
    return _RaceResult.failed('relay_live_error:$e');
  }
}

/// Try sending via local WiFi, running a bounded discover-on-send resolve first
/// when the peer was not already in the discovered map.
///
/// Self-bounded to [budget] (the caller also `.timeout`-wraps it), so this leg
/// can never delay the unconditional direct leg beyond the local budget. A peer
/// genuinely not on the LAN resolves to false and returns a failed result —
/// the direct leg then wins and transport is never `local`.
Future<_RaceResult> _tryLocalSendWithDiscovery(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required bool alreadyLocal,
  required Duration budget,
  TransportMetrics? transportMetrics,
}) async {
  final sw = Stopwatch()..start();
  if (!alreadyLocal) {
    final found = await p2pService.discoverLocalPeer(
      targetPeerId,
      timeout: budget,
    );
    if (!found) {
      transportMetrics?.recordAttempt(leg: 'local', succeeded: false);
      return _RaceResult.failed(
        'local_not_discovered',
        stepTimings: {'localDiscoverMs': sw.elapsedMilliseconds},
      );
    }
  }
  final remaining = budget.inMilliseconds - sw.elapsedMilliseconds;
  return _tryLocalSend(
    p2pService,
    targetPeerId,
    jsonString,
    senderPeerId,
    timeoutMs: remaining > 0 ? remaining : 1,
    transportMetrics: transportMetrics,
  );
}

/// Try sending via local WiFi.
Future<_RaceResult> _tryLocalSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required int timeoutMs,
  TransportMetrics? transportMetrics,
}) async {
  final localStopwatch = Stopwatch()..start();
  final durableLanSender = p2pService is DurableLanSender
      ? p2pService as DurableLanSender
      : null;
  final (localSent, acknowledged, ackKind) = durableLanSender != null
      ? switch (await durableLanSender.sendLocalMessageDurable(
          targetPeerId,
          jsonString,
          senderPeerId,
          timeoutMs: timeoutMs,
        )) {
          LanSendAck.committed => (true, true, 'committed'),
          LanSendAck.legacyAck => (true, false, 'legacy'),
          LanSendAck.failed => (false, false, 'failed'),
        }
      : await () async {
          final sent = await p2pService.sendLocalMessage(
            targetPeerId,
            jsonString,
            senderPeerId,
            timeoutMs: timeoutMs,
          );
          return sent
              ? (true, false, 'bool_legacy')
              : (false, false, 'bool_failed');
        }();
  localStopwatch.stop();
  final timings = {'localSendMs': localStopwatch.elapsedMilliseconds};
  transportMetrics?.recordAttempt(leg: 'local', succeeded: localSent);
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_LAN_ACK',
    details: {
      'targetPeerId': targetPeerId.length > 8
          ? targetPeerId.substring(0, 8)
          : targetPeerId,
      'kind': ackKind,
    },
  );
  if (localSent) {
    return _RaceResult.succeeded(
      via: 'local',
      explicitAck: acknowledged,
      authenticated: false,
      stepTimings: timings,
    );
  }
  return _RaceResult.failed('local_send_failed', stepTimings: timings);
}

/// NET-REL-05 P3 short-circuit: attempt the LEARNED transport directly, WITHOUT
/// re-paying discovery/dial, reusing the known-good path.
///
/// - `'direct'` / `'relay'`: send via [sendMessageWithReply] over the existing
///   known-good connection (no `discoverPeer` / `dialPeer`).
///
/// A learned `'local'` label is intentionally ineligible: it cannot distinguish
/// an authenticated libp2p path from the unauthenticated WebSocket transport.
/// Returns written/proof evidence for a reached authenticated attempt, or null
/// for an unrecognized/ineligible label. Self-bounded so a stalled learned path
/// cannot make the fallback slower than a cold send.
Future<_RaceResult?> _tryLearnedShortCircuit(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required String learned,
  required OutgoingLiveDeadline liveDeadline,
  TransportMetrics? transportMetrics,
}) async {
  if (learned == 'direct' || learned == 'relay') {
    try {
      final timeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
      if (timeoutMs == null) {
        return _RaceResult.failed('sticky_deadline_exhausted');
      }
      final sw = Stopwatch()..start();
      final sendResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
        timeoutMs: timeoutMs,
      );
      sw.stop();
      final timings = {
        'stickySendMs': sw.elapsedMilliseconds,
        if (sendResult.streamOpenMs != null)
          'streamOpenMs': sendResult.streamOpenMs!,
        if (sendResult.writeMs != null) 'writeMs': sendResult.writeMs!,
        if (sendResult.ackWaitMs != null) 'ackWaitMs': sendResult.ackWaitMs!,
      };
      // Sticky short-circuit = reuse of the learned known-good authenticated
      // path; censused under the 'reuse' leg (no separate sticky leg exists).
      transportMetrics?.recordAttempt(leg: 'reuse', succeeded: sendResult.sent);
      if (sendResult.sent) {
        return _RaceResult.succeeded(
          via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
          explicitAck: sendResult.acked == true,
          authenticated: true,
          stepTimings: timings,
        );
      }
      return _RaceResult.failed('sticky_send_failed', stepTimings: timings);
    } catch (e) {
      transportMetrics?.recordAttempt(leg: 'reuse', succeeded: false);
      return _RaceResult.failed('sticky_send_error:$e');
    }
  }

  return null;
}

/// Try direct discover → dial → send path, recording one `direct` attempt
/// outcome for the transport census regardless of which leg ultimately wins the
/// race. Records exactly once, on the real outcome of the inner attempt.
Future<_RaceResult> _tryDirectSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required OutgoingLiveDeadline liveDeadline,
  TransportMetrics? transportMetrics,
  bool skipForKeepaliveDrop = false,
}) async {
  // 187 (Option A): the 183 keepalive has latched this active peer as dropped —
  // the direct discover/dial leg would burn ~1.5 s on a peer that cannot answer
  // while the concurrent durable inbox already holds custody. Short-circuit
  // BEFORE any discover/dial AND before recording a 'direct' attempt (the leg
  // never actually attempted). The leg stays PRESENT in raceFutures[1], so the
  // pending-count/failure classification is untouched; it simply resolves fast
  // to a NON-eligible failure.
  // `relayProbeEligible:false` classifies a keepalive-dropped peer for durable
  // inbox custody; there is no separate conversation probe step. The distinct
  // discriminator event proves the skip fired for the KEEPALIVE-DROP reason
  // (not presence, not a budget timeout).
  if (skipForKeepaliveDrop) {
    final shortTarget = targetPeerId.length > 10
        ? '${targetPeerId.substring(0, 10)}…'
        : targetPeerId;
    emitFlowEvent(
      layer: 'FL',
      event: 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
      details: {'targetPeerId': shortTarget},
    );
    return _RaceResult.failed(
      'direct_skipped_keepalive_drop',
      relayProbeEligible: false,
    );
  }
  final result = await _tryDirectSendInner(
    p2pService,
    targetPeerId,
    jsonString,
    liveDeadline: liveDeadline,
  );
  transportMetrics?.recordAttempt(leg: 'direct', succeeded: result.success);
  return result;
}

Future<_RaceResult> _tryDirectSendInner(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required OutgoingLiveDeadline liveDeadline,
}) async {
  final timings = <String, int>{};

  // Every native phase is allocated from the original send-entry T0. Discovery
  // and dial retain their caps; the committed send receives all usable
  // remaining time so the receiver's deferred ACK still has its reserve.
  final discoverTimeoutMs = liveDeadline.allocatePhaseTimeoutMs(
    outgoingDiscoverPhaseCap,
  );
  if (discoverTimeoutMs == null) {
    return _RaceResult.failed(
      'peer_not_found',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }
  final discoverStopwatch = Stopwatch()..start();
  final peer = await p2pService.discoverPeer(
    targetPeerId,
    timeoutMs: discoverTimeoutMs,
  );
  discoverStopwatch.stop();
  timings['discoverMs'] = discoverStopwatch.elapsedMilliseconds;
  if (peer == null) {
    return _RaceResult.failed(
      'peer_not_found',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  final dialTimeoutMs = liveDeadline.allocatePhaseTimeoutMs(
    outgoingDialPhaseCap,
  );
  if (dialTimeoutMs == null) {
    return _RaceResult.failed(
      'dial_failed',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }
  final dialStopwatch = Stopwatch()..start();
  final dialed = await p2pService.dialPeer(
    targetPeerId,
    addresses: peer.addresses,
    timeoutMs: dialTimeoutMs,
  );
  dialStopwatch.stop();
  timings['dialMs'] = dialStopwatch.elapsedMilliseconds;
  if (!dialed) {
    return _RaceResult.failed(
      'dial_failed',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  final sendTimeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
  if (sendTimeoutMs == null) {
    return _RaceResult.failed(
      'direct_timeout',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }
  final sendStepStopwatch = Stopwatch()..start();
  SendMessageResult? sendResult;
  var sendTimedOut = false;
  try {
    sendResult = await p2pService.sendMessageWithReply(
      targetPeerId,
      jsonString,
      timeoutMs: sendTimeoutMs,
    );
  } on TimeoutException {
    sendTimedOut = true;
  }
  sendStepStopwatch.stop();
  timings['sendMs'] = sendStepStopwatch.elapsedMilliseconds;
  if (sendTimedOut || sendResult == null) {
    return _RaceResult.failed(
      sendTimedOut ? 'direct_timeout' : 'send_failed',
      relayProbeEligible: sendTimedOut,
      stepTimings: timings,
    );
  }
  if (sendResult.streamOpenMs != null) {
    timings['streamOpenMs'] = sendResult.streamOpenMs!;
  }
  if (sendResult.writeMs != null) {
    timings['writeMs'] = sendResult.writeMs!;
  }
  if (sendResult.ackWaitMs != null) {
    timings['ackWaitMs'] = sendResult.ackWaitMs!;
  }
  if (!sendResult.sent) {
    return _RaceResult.failed('send_failed', stepTimings: timings);
  }

  return _RaceResult.succeeded(
    via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
    explicitAck: sendResult.acked == true,
    authenticated: true,
    stepTimings: timings,
  );
}

/// Persists the only durable custody marker for a freshly rebuilt outgoing
/// protected/view-once envelope.
///
/// A canonical attachment can authorize a restart-shaped handoff directly.
/// A still-pending row can authorize it only while the shared mutation
/// coordinator owns the exact full completion fingerprint. The lifecycle lock
/// keeps that process-local ownership from being discarded between the check
/// and the DB helper's exact parent/attachment compare-and-set.
Future<bool> _commitOutgoingDirectPrivateEnvelopeForTransport({
  required String messageId,
  required String envelope,
  required List<MediaAttachment>? attachments,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (messageId.isEmpty ||
      envelope.isEmpty ||
      attachments == null ||
      attachments.length != 1 ||
      messageRepo is! OutgoingDirectPrivateEnvelopeCustodyRepository ||
      mediaAttachmentRepo is! OutgoingDirectPrivateMutationRepository) {
    return false;
  }

  final completed = attachments.single.copyWith(
    messageId: messageId,
    ownerLane: MediaOwnerLane.direct,
  );
  late final String expectedPendingLocalPath;
  try {
    expectedPendingLocalPath =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: messageId,
          attachmentId: completed.id,
          mime: completed.mime,
        );
  } catch (_) {
    return false;
  }
  final fingerprint = OutgoingDirectPrivateCompletionFingerprint.fromAttachment(
    completed,
    expectedPendingLocalPath: expectedPendingLocalPath,
  );
  if (!fingerprint.isStructurallyComplete) return false;

  final attachmentRepository = mediaAttachmentRepo!;
  final mutationRepository =
      mediaAttachmentRepo as OutgoingDirectPrivateMutationRepository;
  final coordinator =
      mutationRepository.outgoingDirectPrivateMutationCoordinator;
  final envelopeRepository =
      messageRepo as OutgoingDirectPrivateEnvelopeCustodyRepository;
  return coordinator.lifecycleLock.synchronized(completed.id, () async {
    final owned = await coordinator.loadOwnedCompletionFingerprint(
      messageId: messageId,
      attachmentId: completed.id,
      expectedPendingLocalPath: expectedPendingLocalPath,
    );
    final hasOwnedPendingCompletion = owned == fingerprint;

    if (!hasOwnedPendingCompletion) {
      // Restart recovery has no process token. It is safe only when the
      // hydrated durable row already carries the exact canonical fingerprint;
      // the DB compare-and-set repeats the same persisted-field check.
      final durable = await attachmentRepository.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      if (durable.length != 1 ||
          !fingerprint.matchesHydratedAttachment(durable.single)) {
        return false;
      }
    }

    final outcome = await envelopeRepository
        .commitOutgoingDirectPrivateWireEnvelope(
          messageId: messageId,
          completedAttachment: completed,
          expectedPendingLocalPath: expectedPendingLocalPath,
          envelope: envelope,
          hasOwnedPendingCompletion: hasOwnedPendingCompletion,
        );
    return outcome.authorizesTransport;
  });
}

Future<ConversationMessage?> _settleOutgoingDirectPrivateTransportState({
  required MessageRepository messageRepo,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
  required String messageId,
  required String expectedEnvelope,
  required String status,
  required String? transport,
  required int? relayExpiresAt,
}) async {
  final outcome = await settleOutgoingDirectPrivateTransportUnderLifecycleLock(
    messageRepository: messageRepo,
    mediaAttachmentRepository: mediaAttachmentRepo,
    attachments: attachments,
    messageId: messageId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
  );
  if (!outcome.accepted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_PRIVATE_TRANSPORT_SETTLEMENT_REFUSED',
      details: {
        'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
        'status': status,
      },
    );
  }
  return messageRepo.getMessage(messageId);
}

Future<ConversationMessage?> _persistOutgoingTransportState({
  required MessageRepository messageRepo,
  required ConversationMessage message,
  required List<MediaAttachment>? attachments,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required bool isOutgoingPrivateOneMoreLook,
  required String expectedEnvelope,
  required String expectedContactPeerId,
}) async {
  if (isOutgoingPrivateOneMoreLook) {
    // Completion persistence was already authorized by the outgoing-private
    // coordinator. Post-network work owns message transport columns only.
    return _settleOutgoingDirectPrivateTransportState(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: attachments,
      messageId: message.id,
      expectedEnvelope: expectedEnvelope,
      status: message.status,
      transport: message.transport,
      relayExpiresAt: message.relayExpiresAt,
    );
  }
  if (messageRepo is! OutgoingTransportMutationRepository) return null;
  final mutationRepo = messageRepo as OutgoingTransportMutationRepository;
  final settled = await mutationRepo.settleOutgoingOrdinaryTransport(
    messageId: message.id,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: message.status,
    transport: message.transport,
    relayExpiresAt: message.relayExpiresAt,
    mode: OutgoingOrdinarySettlementMode.live,
  );
  return settled.message;
}

Future<(SendChatMessageResult, ConversationMessage?)> _completeSuccessfulSend({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required MessagePayload payload,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required String via,
  required String resolvedMessageId,
  required String text,
  required String? createdAt,
  required String? editedAt,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
  required bool isOutgoingPrivateOneMoreLook,
  required Stopwatch sendStopwatch,
  required bool emitTimingEvent,
  Future<bool>? concurrentInbox,
  Map<String, dynamic> extraTimingDetails = const {},
}) async {
  final message = await _persistOutgoingSendResult(
    p2pService: p2pService,
    payload: payload,
    targetPeerId: targetPeerId,
    jsonString: jsonString,
    acknowledged: acknowledged,
    createdAt: createdAt,
    editedAt: editedAt,
    via: via,
    concurrentInbox: concurrentInbox,
  );
  final persistedMessage = await _persistOutgoingTransportState(
    messageRepo: messageRepo,
    message: message,
    attachments: attachments,
    mediaAttachmentRepo: mediaAttachmentRepo,
    isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
    expectedEnvelope: jsonString,
    expectedContactPeerId: targetPeerId,
  );
  final observedMessage = persistedMessage ?? message;
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_SUCCESS',
    details: {
      'id': resolvedMessageId.substring(0, 8),
      'status': observedMessage.status,
      'via': observedMessage.transport,
    },
  );
  if (emitTimingEvent) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': 'success',
        'messageId': resolvedMessageId.substring(0, 8),
        'hasAttachments': attachments != null && attachments.isNotEmpty,
        'status': observedMessage.status,
        'via': observedMessage.transport,
        ...extraTimingDetails,
      },
    );
  }
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: observedMessage.status,
    text: text,
  );
  _recordSuccessfulSendReadinessProof(p2pService, observedMessage);
  // NET-REL-05 P3 (sticky transport): remember the LIVE transport that just
  // delivered so a repeat send to this peer can be weighted toward it (head-
  // start consumed in U-P2). Only acked LIVE deliveries qualify — 'inbox' is a
  // custody handoff, not a live transport, and `recordSuccessfulTransport`
  // ignores it anyway. This single success funnel covers connection reuse,
  // direct/local wins, and relay-live race wins; the inbox custody path and
  // unacked->inbox handoff intentionally do not record.
  if (observedMessage.status == 'delivered' &&
      observedMessage.transport != 'inbox') {
    p2pService.recordSuccessfulTransport(
      targetPeerId,
      observedMessage.transport ?? '',
    );
  }
  return (
    SendChatMessageResult.success,
    isOutgoingPrivateOneMoreLook
        ? persistedMessage?.copyWith(media: attachments ?? const [])
        : persistedMessage,
  );
}

SendChatMessageResult _resultForFailureReason(String? reason) {
  return switch (reason) {
    'peer_not_found' => SendChatMessageResult.peerNotFound,
    'dial_failed' => SendChatMessageResult.dialFailed,
    _ => SendChatMessageResult.sendFailed,
  };
}

Future<ConversationMessage> _persistOutgoingSendResult({
  required P2PService p2pService,
  required MessagePayload payload,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required String? createdAt,
  required String? editedAt,
  required String via,
  Future<bool>? concurrentInbox,
}) async {
  if (acknowledged) {
    return payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'delivered',
      createdAt: createdAt,
      editedAt: editedAt,
      transport: via,
    );
  }

  // NET-REL-05 P1/P4: the live write was unacked. If a concurrent durable copy
  // was fired for this unknown-presence send and already took custody, settle as
  // 'inboxed'/'inbox' WITHOUT a second sequential `storeInInbox` — one message
  // must never produce two relay writes (R1 guard). `concurrentInbox` resolves
  // to false on failure/timeout, in which case we fall through to the normal
  // sequential handoff below. Inbox acceptance is custody, not delivery
  // (doc 115): keep the envelope for the custody sweep / receipt flip.
  if (concurrentInbox != null) {
    final concurrentOk = await concurrentInbox;
    if (concurrentOk) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_UNACKED_CONCURRENT_INBOX_CUSTODY',
        details: {'via': via},
      );
      return payload.toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: 'inboxed',
        createdAt: createdAt,
        editedAt: editedAt,
        transport: 'inbox',
        wireEnvelope: jsonString,
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_BEGIN',
    details: {'via': via},
  );
  try {
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      jsonString,
      timeoutMs: interactiveInboxBudget.inMilliseconds,
    );
    if (storedInInbox) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_SUCCESS',
        details: {'via': via},
      );
      return payload.toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: 'inboxed',
        createdAt: createdAt,
        editedAt: editedAt,
        transport: 'inbox',
        wireEnvelope: jsonString,
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_FAILED',
      details: {'via': via, 'reason': 'store_returned_false'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_ERROR',
      details: {'via': via, 'error': e.toString()},
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_UNACKED_PENDING_RETRY',
    details: {'via': via},
  );
  return payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'sent',
    createdAt: createdAt,
    editedAt: editedAt,
    transport: via,
    wireEnvelope: jsonString,
  );
}
