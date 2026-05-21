import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

typedef GroupMessageIdFactory = String Function();

String _diagnosticPrefix(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;

/// Result of sending a group message.
enum SendGroupMessageResult {
  success,
  groupNotFound,
  groupDissolved,
  unauthorized,
  error,

  /// Publish succeeded but 0 peers were connected to the topic.
  /// The message was stored in the relay inbox as a fallback. This is live
  /// fanout evidence only, not recipient delivered/read receipt evidence.
  /// The returned [GroupMessage] still has status `'sent'` because the
  /// relay inbox accepted custody for offline delivery.
  successNoPeers,
}

Future<({List<GroupMember> members, List<String> recipientPeerIds})>
_loadGroupSendMembership({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderPeerId,
  DateTime? membershipCutoff,
}) async {
  final members = await groupRepo.getMembers(groupId);
  final normalizedCutoff = membershipCutoff?.toUtc();
  final recipientPeerIds = members
      .where(
        (member) =>
            (normalizedCutoff == null ||
                !member.joinedAt.toUtc().isAfter(normalizedCutoff)) &&
            hasDeliverableGroupMemberIdentity(member) &&
            member.peerId.trim() != senderPeerId,
      )
      .map((member) => member.peerId.trim())
      .toSet()
      .toList();
  return (members: members, recipientPeerIds: recipientPeerIds);
}

String _classifyGroupPublishLiveFanout({
  required int? topicPeers,
  required int expectedRecipientCount,
}) {
  if (topicPeers == null) return 'legacy_unknown';
  if (topicPeers <= 0) return 'zero_peers';
  if (topicPeers < expectedRecipientCount) return 'partial_peers';
  return 'full_peers';
}

Map<String, dynamic> _groupPublishFanoutEvidence({
  required int? topicPeers,
  required int expectedRecipientCount,
  required bool? inboxOk,
}) {
  final evidence = <String, dynamic>{
    'expectedRecipientCount': expectedRecipientCount,
    'liveFanoutState': _classifyGroupPublishLiveFanout(
      topicPeers: topicPeers,
      expectedRecipientCount: expectedRecipientCount,
    ),
    'inboxStored': inboxOk ?? false,
    'inboxPending': inboxOk == null,
    'recipientReceiptClaimed': false,
  };
  if (topicPeers != null) {
    evidence['topicPeers'] = topicPeers;
  }
  return evidence;
}

String _defaultGroupMessageIdFactory() => const Uuid().v4();

GroupMemberDeviceIdentity? _resolveOutgoingSenderDevice({
  required GroupMember? senderMember,
  required String senderPublicKey,
  String? requestedDeviceId,
  String? requestedTransportPeerId,
}) {
  if (senderMember == null || senderMember.devices.isEmpty) {
    return null;
  }

  final normalizedDeviceId = requestedDeviceId?.trim();
  final normalizedTransportPeerId = requestedTransportPeerId?.trim();

  for (final device in senderMember.activeDevices) {
    if (normalizedDeviceId != null &&
        normalizedDeviceId.isNotEmpty &&
        device.deviceId != normalizedDeviceId) {
      continue;
    }
    if (normalizedTransportPeerId != null &&
        normalizedTransportPeerId.isNotEmpty &&
        device.transportPeerId != normalizedTransportPeerId) {
      continue;
    }
    if (device.deviceSigningPublicKey == senderPublicKey) {
      return device;
    }
  }
  return null;
}

bool _sameOptionalString(String? left, String? right) =>
    (left == null || left.isEmpty ? null : left) ==
    (right == null || right.isEmpty ? null : right);

bool _canReuseOutgoingMessageId({
  required GroupMessage existing,
  required String groupId,
  required String senderPeerId,
  required String text,
  required DateTime timestamp,
  String? quotedMessageId,
}) {
  if (existing.isIncoming) return false;
  if (existing.status != 'sending' && existing.status != 'failed') {
    return false;
  }
  if (existing.groupId != groupId || existing.senderPeerId != senderPeerId) {
    return false;
  }
  if (existing.text != text) return false;
  if (!_sameOptionalString(existing.quotedMessageId, quotedMessageId)) {
    return false;
  }
  return existing.timestamp.toUtc().isAtSameMomentAs(timestamp.toUtc());
}

Future<String?> _resolveOutgoingMessageId({
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String senderPeerId,
  required String text,
  required DateTime timestamp,
  required GroupMessageIdFactory messageIdFactory,
  String? requestedMessageId,
  String? quotedMessageId,
}) async {
  String nextCandidate() => messageIdFactory().trim();
  var candidate = requestedMessageId?.trim().isNotEmpty == true
      ? requestedMessageId!.trim()
      : nextCandidate();

  for (var attempt = 0; attempt < 8; attempt++) {
    if (candidate.isEmpty) {
      candidate = nextCandidate();
      continue;
    }

    final existing = await msgRepo.getMessage(candidate);
    if (existing == null) return candidate;

    if (_canReuseOutgoingMessageId(
      existing: existing,
      groupId: groupId,
      senderPeerId: senderPeerId,
      text: text,
      timestamp: timestamp,
      quotedMessageId: quotedMessageId,
    )) {
      return candidate;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_ID_COLLISION',
      details: {
        'messageId': candidate.length > 8
            ? candidate.substring(0, 8)
            : candidate,
        'attempt': attempt + 1,
      },
    );
    candidate = nextCandidate();
  }

  return null;
}

/// Wraps [callGroupInboxStore] in try/catch — returns true on success.
///
/// Never throws. The caller observes the outcome via the return value.
Future<bool> _tryInboxStore({
  required Bridge bridge,
  required String groupId,
  required String inboxPayload,
  List<String>? recipientPeerIds,
}) async {
  try {
    await callGroupInboxStore(
      bridge,
      groupId,
      inboxPayload,
      recipientPeerIds: recipientPeerIds,
    );
    return true;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_INBOX_STORE_FAILED',
      details: {'error': e.toString()},
    );
    return false;
  }
}

Future<void> _persistOutgoingMedia({
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
}) async {
  if (mediaAttachmentRepo == null ||
      attachments == null ||
      attachments.isEmpty) {
    return;
  }

  final messageIds = attachments
      .map((attachment) => attachment.messageId)
      .where((messageId) => messageId.isNotEmpty)
      .toSet();
  if (messageIds.length == 1) {
    final messageId = messageIds.first;
    final expectedIds = attachments.map((attachment) => attachment.id).toSet();
    final existing = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
    );
    final hasStaleUploadPending = existing.any(
      (attachment) =>
          attachment.downloadStatus == 'upload_pending' &&
          !expectedIds.contains(attachment.id),
    );
    if (hasStaleUploadPending) {
      await mediaAttachmentRepo.deleteAttachmentsForMessage(messageId);
    }
  }

  for (final attachment in attachments) {
    await mediaAttachmentRepo.saveAttachment(attachment);
  }
}

List<MediaAttachment>? _sanitizeGroupMediaAttachments(
  List<MediaAttachment>? attachments,
) {
  if (attachments == null || attachments.isEmpty) return attachments;
  final sanitized = <MediaAttachment>[];
  for (final attachment in attachments) {
    try {
      final mimeSanitized = GroupMediaMimePolicy.sanitizeAttachment(attachment);
      final contentHashValidation =
          GroupMediaIntegrityPolicy.validateRequiredContentHash(
            mimeSanitized.contentHash,
          );
      if (!contentHashValidation.isValid) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
          details: {
            'blobId': attachment.id.length > 8
                ? attachment.id.substring(0, 8)
                : attachment.id,
            'reason': contentHashValidation.reason,
          },
        );
        return null;
      }
      if (!mimeSanitized.hasEncryptionMetadata) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
          details: {
            'blobId': attachment.id.length > 8
                ? attachment.id.substring(0, 8)
                : attachment.id,
            'reason': 'missing_media_encryption_metadata',
          },
        );
        return null;
      }
      final thumbnailHashValidation =
          GroupMediaIntegrityPolicy.validateOptionalThumbnailHash(
            mimeSanitized.thumbnailHash,
          );
      if (!thumbnailHashValidation.isValid) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
          details: {
            'blobId': attachment.id.length > 8
                ? attachment.id.substring(0, 8)
                : attachment.id,
            'reason': thumbnailHashValidation.reason,
          },
        );
        return null;
      }
      sanitized.add(
        mimeSanitized.copyWith(
          contentHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            mimeSanitized.contentHash,
          ),
          thumbnailHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            mimeSanitized.thumbnailHash,
          ),
        ),
      );
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
        details: {
          'blobId': attachment.id.length > 8
              ? attachment.id.substring(0, 8)
              : attachment.id,
          'mime': attachment.mime,
          'mediaType': attachment.mediaType,
        },
      );
      return null;
    }
  }

  final sizeValidation = GroupMediaSizePolicy.validateAttachments(sanitized);
  if (!sizeValidation.isValid) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
      details: {'reason': sizeValidation.reason},
    );
    return null;
  }
  return sanitized;
}

void _finalizeSuccessfulPublishInboxStoreInBackground({
  required Future<bool> inboxFuture,
  required GroupMessageRepository msgRepo,
  required String messageId,
}) {
  unawaited(() async {
    try {
      final inboxOk = await inboxFuture;
      if (inboxOk) {
        await msgRepo.updateInboxStored(messageId, stored: true);
        await msgRepo.updateInboxRetryPayload(messageId, null);
        await msgRepo.updateMessageStatus(messageId, 'sent');
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_INBOX_STORE_BACKGROUND_RESULT',
        details: {
          'messageId': messageId.length > 8
              ? messageId.substring(0, 8)
              : messageId,
          'inboxOk': inboxOk,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_INBOX_STORE_BACKGROUND_ERROR',
        details: {
          'messageId': messageId.length > 8
              ? messageId.substring(0, 8)
              : messageId,
          'error': e.toString(),
        },
      );
    }
  }());
}

/// Sends a message to a group.
///
/// Owns optimistic persistence for ALL production callers:
/// 1. Validates group exists + sender authorized
/// 2. Pre-persists row with status `'sending'` + wireEnvelope + inboxRetryPayload
/// 3. Kicks off publish + inbox store concurrently
/// 4. Reads topicPeers from publish result as live fanout, not delivery ACK
/// 5. Applies 4-way result matrix to determine final status
///
/// Go's GroupPublish handles encryption and signing internally,
/// so it needs the sender's public and private keys.
Future<(SendGroupMessageResult, GroupMessage?)> sendGroupMessage({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String text,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? messageId,
  GroupMessageIdFactory? messageIdFactory,
  DateTime? timestamp,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
}) async {
  final sendStopwatch = Stopwatch()..start();
  final sanitizedText = sanitizeMessageText(text);
  final hasMedia = mediaAttachments != null && mediaAttachments.isNotEmpty;
  int? prepareMs;
  int? publishMs;
  int? inboxMs;
  void emitGroupSendTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    if (!emitTimingEvent) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'hasMedia': hasMedia,
        'prepareMs': ?prepareMs,
        'publishMs': ?publishMs,
        'inboxMs': ?inboxMs,
        ...details,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SEND_MSG_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'textLength': sanitizedText.length,
    },
  );

  // 1. Load group from repo (verify exists)
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_NOT_FOUND',
      details: {},
    );
    emitGroupSendTiming(outcome: 'group_not_found');
    return (SendGroupMessageResult.groupNotFound, null);
  }

  if (group.isDissolved) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        if (group.dissolvedAt != null)
          'dissolvedAt': group.dissolvedAt!.toUtc().toIso8601String(),
      },
    );
    emitGroupSendTiming(outcome: 'group_dissolved');
    return (SendGroupMessageResult.groupDissolved, null);
  }

  if (group.type == GroupType.announcement && isGroupRecoveryInProgress()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_RECOVERY_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'groupType': group.type.toValue(),
      },
    );
    emitGroupSendTiming(outcome: 'group_recovery_pending');
    return (SendGroupMessageResult.error, null);
  }

  // 2. Check role authorization (announcement: only admin can send)
  if (group.type == GroupType.announcement && group.myRole != GroupRole.admin) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNAUTHORIZED',
      details: {'type': group.type.toValue(), 'role': group.myRole.toValue()},
    );
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {
        'groupType': group.type.toValue(),
        'role': group.myRole.toValue(),
      },
    );
    return (SendGroupMessageResult.unauthorized, null);
  }

  // 2b. Reject empty messages (no text and no media)
  if (sanitizedText.trim().isEmpty && !hasMedia) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_EMPTY',
      details: {},
    );
    emitGroupSendTiming(outcome: 'empty');
    return (SendGroupMessageResult.error, null);
  }

  final groupMediaAttachments = _sanitizeGroupMediaAttachments(
    mediaAttachments,
  );
  if (hasMedia && groupMediaAttachments == null) {
    emitGroupSendTiming(outcome: 'invalid_media');
    return (SendGroupMessageResult.error, null);
  }

  // 3. Prepare all parameters
  final prepareStopwatch = Stopwatch()..start();
  final now = timestamp ?? DateTime.now().toUtc();
  final membershipCutoff =
      timestamp != null && !timestamp.toUtc().isBefore(group.createdAt.toUtc())
      ? timestamp
      : null;
  final latestKeyFuture = groupRepo.getLatestKey(groupId);
  final sendMembershipFuture = _loadGroupSendMembership(
    groupRepo: groupRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    membershipCutoff: membershipCutoff,
  );
  final sendMembership = await sendMembershipFuture;
  final members = sendMembership.members;
  final senderConfigured = members.any(
    (member) => member.peerId == senderPeerId,
  );
  if (!senderConfigured &&
      (members.isNotEmpty || group.myRole != GroupRole.admin)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNAUTHORIZED',
      details: {'reason': 'sender_not_member'},
    );
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'sender_not_member'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final latestKey = await latestKeyFuture;
  if (!senderConfigured && latestKey == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNAUTHORIZED',
      details: {'reason': 'sender_not_member'},
    );
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'sender_not_member'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  if (latestKey == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_BOOTSTRAP_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'role': group.myRole.toValue(),
      },
    );
    emitGroupSendTiming(
      outcome: 'bootstrap_pending',
      details: {'role': group.myRole.toValue()},
    );
    return (SendGroupMessageResult.error, null);
  }
  if (group.type == GroupType.chat && members.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    emitGroupSendTiming(
      outcome: 'group_dissolved',
      details: {'reason': 'empty_membership'},
    );
    return (SendGroupMessageResult.groupDissolved, null);
  }
  final resolvedMessageId = await _resolveOutgoingMessageId(
    msgRepo: msgRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    text: sanitizedText,
    timestamp: now,
    quotedMessageId: quotedMessageId,
    requestedMessageId: messageId,
    messageIdFactory: messageIdFactory ?? _defaultGroupMessageIdFactory,
  );
  if (resolvedMessageId == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_ID_COLLISION_UNRESOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    emitGroupSendTiming(outcome: 'message_id_collision');
    return (SendGroupMessageResult.error, null);
  }
  final keyEpoch = latestKey.keyGeneration;
  GroupMember? senderMember;
  for (final member in members) {
    if (member.peerId == senderPeerId) {
      senderMember = member;
      break;
    }
  }
  final resolvedSenderDevice = _resolveOutgoingSenderDevice(
    senderMember: senderMember,
    senderPublicKey: senderPublicKey,
    requestedDeviceId: senderDeviceId,
    requestedTransportPeerId: senderTransportPeerId,
  );
  if (senderMember?.devices.isNotEmpty == true &&
      resolvedSenderDevice == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNBOUND_DEVICE',
      details: {'reason': 'sender_device_not_registered'},
    );
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'sender_device_not_registered'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final resolvedSenderDeviceId = senderDeviceId?.trim().isNotEmpty == true
      ? senderDeviceId!.trim()
      : resolvedSenderDevice?.deviceId ?? senderPeerId;
  final resolvedSenderTransportPeerId =
      senderTransportPeerId?.trim().isNotEmpty == true
      ? senderTransportPeerId!.trim()
      : resolvedSenderDevice?.transportPeerId ?? resolvedSenderDeviceId;
  final resolvedSenderDevicePublicKey =
      resolvedSenderDevice?.deviceSigningPublicKey ?? senderPublicKey;

  final mediaJson = groupMediaAttachments?.map((a) => a.toJson()).toList();
  final recipientPeerIds = sendMembership.recipientPeerIds;
  final expectedRecipientCount = recipientPeerIds.length;
  // 3b. Build wireEnvelope (plaintext publish params for retry — NO senderPrivateKey)
  final wireEnvelope = jsonEncode({
    'groupId': groupId,
    'text': sanitizedText,
    'senderPeerId': senderPeerId,
    'senderDeviceId': resolvedSenderDeviceId,
    'transportPeerId': resolvedSenderTransportPeerId,
    'senderPublicKey': senderPublicKey,
    'senderUsername': senderUsername,
    'messageId': resolvedMessageId,
    if (quotedMessageId != null && quotedMessageId.isNotEmpty)
      'quotedMessageId': quotedMessageId,
    if (mediaJson != null && mediaJson.isNotEmpty) 'media': mediaJson,
  });

  // 3c. Build inboxRetryPayload (exact inputs for callGroupInboxStore)
  final inboxPayload = jsonEncode({
    'groupId': groupId,
    'senderId': senderPeerId,
    'senderDeviceId': resolvedSenderDeviceId,
    'transportPeerId': resolvedSenderTransportPeerId,
    'senderUsername': senderUsername,
    'keyEpoch': keyEpoch,
    'text': sanitizedText,
    'timestamp': now.toIso8601String(),
    'messageId': resolvedMessageId,
    if (quotedMessageId != null && quotedMessageId.isNotEmpty)
      'quotedMessageId': quotedMessageId,
    if (mediaJson != null && mediaJson.isNotEmpty) 'media': mediaJson,
  });
  String? replayEnvelope;
  String? inboxRetryPayload;
  try {
    replayEnvelope = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: inboxPayload,
      senderPeerId: senderPeerId,
      senderPublicKey: resolvedSenderDevicePublicKey,
      senderPrivateKey: senderPrivateKey,
      keyInfo: latestKey,
      messageId: resolvedMessageId,
      senderDeviceId: resolvedSenderDeviceId,
      senderTransportPeerId: resolvedSenderTransportPeerId,
      senderKeyPackageId: resolvedSenderDevice?.keyPackageId,
      recipientPeerIds: recipientPeerIds,
    );
    inboxRetryPayload = jsonEncode({
      'groupId': groupId,
      'message': replayEnvelope,
      if (recipientPeerIds.isNotEmpty) 'recipientPeerIds': recipientPeerIds,
    });
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_REPLAY_ENVELOPE_FAILED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'error': e.toString(),
      },
    );
  }

  // 4. Pre-persist outgoing row with status 'sending' BEFORE bridge call
  final prePersistMessage = GroupMessage(
    id: resolvedMessageId,
    groupId: groupId,
    senderPeerId: senderPeerId,
    transportPeerId: resolvedSenderTransportPeerId,
    senderUsername: senderUsername,
    text: sanitizedText,
    timestamp: now,
    quotedMessageId: quotedMessageId,
    keyGeneration: keyEpoch,
    status: 'sending',
    isIncoming: false,
    createdAt: now,
    wireEnvelope: wireEnvelope,
    inboxStored: false,
    inboxRetryPayload: inboxRetryPayload,
  );

  await msgRepo.saveMessage(prePersistMessage);
  prepareStopwatch.stop();
  prepareMs = prepareStopwatch.elapsedMilliseconds;

  // 5. Start publish + inbox store concurrently
  final publishStopwatch = Stopwatch()..start();
  final publishFuture = callGroupPublish(
    bridge,
    groupId: groupId,
    text: sanitizedText,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    senderUsername: senderUsername,
    senderDeviceId: resolvedSenderDeviceId,
    senderTransportPeerId: resolvedSenderTransportPeerId,
    senderDevicePublicKey: resolvedSenderDevicePublicKey,
    senderKeyPackageId: resolvedSenderDevice?.keyPackageId,
    messageId: resolvedMessageId,
    timestamp: now,
    quotedMessageId: quotedMessageId,
    media: mediaJson,
  );
  bool? inboxResult;
  final inboxStopwatch = Stopwatch()..start();
  final inboxFuture =
      (replayEnvelope == null
              ? Future<bool>.value(false)
              : _tryInboxStore(
                  bridge: bridge,
                  groupId: groupId,
                  inboxPayload: replayEnvelope,
                  recipientPeerIds: recipientPeerIds.isNotEmpty
                      ? recipientPeerIds
                      : null,
                ))
          .then((value) {
            inboxStopwatch.stop();
            inboxMs = inboxStopwatch.elapsedMilliseconds;
            inboxResult = value;
            return value;
          });

  // 6. Await publish — determines success/failure
  Map<String, dynamic>? publishResult;
  bool publishOk = false;
  String? publishErrorCode;

  try {
    publishResult = await publishFuture;
    publishStopwatch.stop();
    publishMs = publishStopwatch.elapsedMilliseconds;
    publishOk = publishResult['ok'] == true;
    publishErrorCode = publishResult['errorCode']?.toString();

    if (!publishOk) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_PUBLISH_ERROR',
        details: {
          'groupId': _diagnosticPrefix(groupId),
          'keyEpoch': keyEpoch,
          'messageId': _diagnosticPrefix(resolvedMessageId),
          'errorCode': publishErrorCode,
        },
      );
    }
  } catch (e) {
    publishStopwatch.stop();
    publishMs = publishStopwatch.elapsedMilliseconds;
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_ERROR',
      details: {'error': e.toString()},
    );
  }

  // 7. Apply result matrix. Only block on durable inbox when live publish
  // cannot confirm delivery.
  if (!publishOk) {
    final inboxOk = await inboxFuture;
    if (publishErrorCode == 'BRIDGE_TIMEOUT' && inboxOk) {
      // The foreground publish confirmation timed out, but the relay inbox
      // accepted custody for delivery. Surface this as a successful durable
      // send instead of a false failure on the sender.
      final sentMessage = prePersistMessage.copyWith(
        status: 'sent',
        wireEnvelope: null,
        inboxStored: true,
        inboxRetryPayload: null,
      );
      await msgRepo.saveMessage(sentMessage);

      await _persistOutgoingMedia(
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: groupMediaAttachments
            ?.map(
              (attachment) => attachment.copyWith(messageId: resolvedMessageId),
            )
            .toList(growable: false),
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_TIMEOUT_INBOX_FALLBACK',
        details: {
          'messageId': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
        },
      );
      emitGroupSendTiming(
        outcome: 'success',
        details: {
          'status': sentMessage.status,
          'via': 'inbox_timeout_fallback',
        },
      );
      return (SendGroupMessageResult.success, sentMessage);
    }

    // Publish failed — preserve publish retry inputs while persisting the
    // observed inbox outcome from the same in-flight inbox future.
    final failedMessage = prePersistMessage.copyWith(
      status: 'failed',
      inboxStored: inboxOk,
      inboxRetryPayload: inboxOk ? null : prePersistMessage.inboxRetryPayload,
    );
    await msgRepo.updateMessageStatus(resolvedMessageId, 'failed');
    await msgRepo.updateInboxStored(resolvedMessageId, stored: inboxOk);
    if (inboxOk) {
      await msgRepo.updateInboxRetryPayload(resolvedMessageId, null);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_PUBLISH_FAILED',
      details: {
        'groupId': _diagnosticPrefix(groupId),
        'keyEpoch': keyEpoch,
        'messageId': _diagnosticPrefix(resolvedMessageId),
        'errorCode': publishErrorCode,
        'inboxOk': inboxOk,
      },
    );
    emitGroupSendTiming(
      outcome: 'publish_failed',
      details: {'inboxStored': inboxOk},
    );
    return (SendGroupMessageResult.error, failedMessage);
  }

  // Publish succeeded — read topicPeers as live topic fanout only.
  final topicPeers = publishResult?.containsKey('topicPeers') == true
      ? publishResult!['topicPeers'] as int?
      : null;

  if (topicPeers == null) {
    // Missing topicPeers key — legacy success (backward compat, assume peers > 0)
    if (inboxResult == null) {
      await Future<void>.value();
    }
    final resolvedInboxOk = inboxResult;
    final finalMessage = prePersistMessage.copyWith(
      status: resolvedInboxOk == true ? 'sent' : 'pending',
      wireEnvelope: null,
      inboxStored: resolvedInboxOk == true,
      inboxRetryPayload: resolvedInboxOk == true
          ? null
          : prePersistMessage.inboxRetryPayload,
    );
    await msgRepo.saveMessage(finalMessage);

    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: groupMediaAttachments
          ?.map(
            (attachment) => attachment.copyWith(messageId: resolvedMessageId),
          )
          .toList(growable: false),
    );

    if (resolvedInboxOk == null) {
      _finalizeSuccessfulPublishInboxStoreInBackground(
        inboxFuture: inboxFuture,
        msgRepo: msgRepo,
        messageId: resolvedMessageId,
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        'legacy': true,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: resolvedInboxOk,
        ),
        'inboxOk': resolvedInboxOk,
      },
    );
    emitGroupSendTiming(
      outcome: 'success',
      details: {
        'status': finalMessage.status,
        'legacy': true,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: resolvedInboxOk,
        ),
      },
    );
    return (SendGroupMessageResult.success, finalMessage);
  }

  if (topicPeers > 0) {
    // Normal success: peers > 0
    if (inboxResult == null) {
      await Future<void>.value();
    }
    final resolvedInboxOk = inboxResult;
    final finalMessage = prePersistMessage.copyWith(
      status: resolvedInboxOk == true ? 'sent' : 'pending',
      wireEnvelope: null,
      inboxStored: resolvedInboxOk == true,
      inboxRetryPayload: resolvedInboxOk == true
          ? null
          : prePersistMessage.inboxRetryPayload,
    );
    await msgRepo.saveMessage(finalMessage);

    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: groupMediaAttachments
          ?.map(
            (attachment) => attachment.copyWith(messageId: resolvedMessageId),
          )
          .toList(growable: false),
    );

    if (resolvedInboxOk == null) {
      _finalizeSuccessfulPublishInboxStoreInBackground(
        inboxFuture: inboxFuture,
        msgRepo: msgRepo,
        messageId: resolvedMessageId,
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: resolvedInboxOk,
        ),
        'inboxOk': resolvedInboxOk,
      },
    );
    emitGroupSendTiming(
      outcome: 'success',
      details: {
        'status': finalMessage.status,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: resolvedInboxOk,
        ),
      },
    );
    return (SendGroupMessageResult.success, finalMessage);
  }

  // topicPeers == 0
  final inboxOk = await inboxFuture;
  if (inboxOk) {
    // 0-peer + inbox OK → successNoPeers, but persist as a successful send.
    // The relay inbox has already accepted durable delivery for offline peers,
    // so a permanent "pending" clock is misleading in the UI.
    final sentMessage = prePersistMessage.copyWith(
      status: 'sent',
      wireEnvelope: null,
      inboxStored: true,
      inboxRetryPayload: null,
    );
    await msgRepo.saveMessage(sentMessage);

    // Save media attachments
    if (groupMediaAttachments != null && mediaAttachmentRepo != null) {
      for (final a in groupMediaAttachments) {
        await mediaAttachmentRepo.saveAttachment(
          a.copyWith(messageId: resolvedMessageId),
        );
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        'status': sentMessage.status,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: true,
        ),
      },
    );
    emitGroupSendTiming(
      outcome: 'success_no_peers',
      details: {
        'status': sentMessage.status,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: true,
        ),
      },
    );
    return (SendGroupMessageResult.successNoPeers, sentMessage);
  } else {
    // 0-peer + inbox fail → error
    await msgRepo.updateMessageStatus(resolvedMessageId, 'failed');
    final failedMessage = prePersistMessage.copyWith(status: 'failed');

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_ZERO_PEERS_INBOX_FAILED',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: false,
        ),
      },
    );
    emitGroupSendTiming(
      outcome: 'zero_peers_inbox_failed',
      details: _groupPublishFanoutEvidence(
        topicPeers: topicPeers,
        expectedRecipientCount: expectedRecipientCount,
        inboxOk: false,
      ),
    );
    return (SendGroupMessageResult.error, failedMessage);
  }
}
