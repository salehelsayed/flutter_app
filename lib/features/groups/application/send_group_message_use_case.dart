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
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
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

  /// 210b: publish "succeeded" locally with ZERO live topic peers AND the
  /// relay-inbox custody attempt failed — the realistic offline-device
  /// geometry (gossipsub reports no error with an empty mesh; only the relay
  /// connect fails). Nothing left the device in any meaningful sense. The
  /// returned [GroupMessage] has the durable status `'queued_offline'`
  /// (clock, offline snackbar) and keeps its `inboxRetryPayload`, so the
  /// repush lane re-stores custody on reconnect and settles it to `'sent'`.
  /// Distinct from [successNoPeers] (custody WAS accepted → tick) and from
  /// the in-doubt `'pending'` (live peers may have received the publish).
  queuedOffline,
}

Future<({List<GroupMember> members, List<String> recipientPeerIds})>
_loadGroupSendMembership({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String senderPeerId,
  String? creatorPeerId,
  GroupRole? senderRole,
  DateTime? membershipCutoff,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
}) async {
  final members = await groupRepo.getMembers(groupId);
  final inviteStatuses = inviteDeliveryAttemptRepo == null
      ? const <String, GroupInviteDeliveryStatus>{}
      : await inviteDeliveryAttemptRepo.getStatusesForGroupMembers(groupId);
  final hasJoinedStatusEvidence = inviteStatuses.values.any(
    (status) => status == GroupInviteDeliveryStatus.joined,
  );
  // The not-yet-joined-invitee exclusion below is only meaningful on a device
  // that actually tracks invites it issued (the inviter/admin). A joiner has no
  // pending-invitee state to protect — its roster came from a signed group
  // config snapshot of confirmed-or-staged members it cannot distinguish — so
  // it must include every deliverable incumbent rather than silently drop the
  // ones it never witnessed joining (REG-119b). Keep the admin branch so the
  // inviter still excludes genuine pending invitees (INV-106).
  final isInviterTrackerDevice =
      inviteStatuses.isNotEmpty || senderRole == GroupRole.admin;
  final joinedTimelinePeerIds = hasJoinedStatusEvidence
      ? const <String>{}
      : await _loadMemberJoinedTimelinePeerIds(
          msgRepo: msgRepo,
          groupId: groupId,
          membershipCutoff: membershipCutoff,
        );
  final hasJoinedInviteEvidence =
      hasJoinedStatusEvidence || joinedTimelinePeerIds.isNotEmpty;
  if (inviteDeliveryAttemptRepo == null && joinedTimelinePeerIds.isNotEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_INVITE_REPO_ABSENT_USING_JOIN_TIMELINE',
      details: {
        'groupId': _diagnosticPrefix(groupId),
        'memberJoinedTimelineCount': joinedTimelinePeerIds.length,
      },
    );
  }
  final normalizedCutoff = membershipCutoff?.toUtc();
  final normalizedSenderPeerId = senderPeerId.trim();
  final normalizedCreatorPeerId = creatorPeerId?.trim();
  final recipientPeerIds = members
      .where((member) {
        final peerId = member.peerId.trim();
        final inviteStatus = inviteStatuses[peerId];
        final hasJoinedTimelineEvidence = joinedTimelinePeerIds.contains(
          peerId,
        );
        final isGroupCreator =
            normalizedCreatorPeerId != null &&
            normalizedCreatorPeerId.isNotEmpty &&
            peerId == normalizedCreatorPeerId;
        return (normalizedCutoff == null ||
                !member.joinedAt.toUtc().isAfter(normalizedCutoff)) &&
            hasDeliverableGroupMemberIdentity(member) &&
            peerId != normalizedSenderPeerId &&
            !_isPersistedNonJoinedInviteStatus(inviteStatus) &&
            !_isMissingInviteStatusInTrackedGroup(
              inviteStatus: inviteStatus,
              isInviterTrackerDevice: isInviterTrackerDevice,
              hasJoinedInviteEvidence: hasJoinedInviteEvidence,
              hasJoinedTimelineEvidence: hasJoinedTimelineEvidence,
              isGroupCreator: isGroupCreator,
            );
      })
      .map((member) => member.peerId.trim())
      .toSet()
      .toList();
  return (members: members, recipientPeerIds: recipientPeerIds);
}

List<String> _durableGroupRecipientPeerIds({
  required List<String> remoteRecipientPeerIds,
  required String senderPeerId,
  bool includeSenderPeerId = false,
}) {
  final recipients = <String>[];
  final seen = <String>{};
  void addRecipient(String peerId) {
    final normalized = peerId.trim();
    if (normalized.isEmpty || seen.contains(normalized)) return;
    seen.add(normalized);
    recipients.add(normalized);
  }

  for (final peerId in remoteRecipientPeerIds) {
    addRecipient(peerId);
  }

  if (includeSenderPeerId) {
    addRecipient(senderPeerId);
  }

  return recipients;
}

Future<Set<String>> _loadMemberJoinedTimelinePeerIds({
  required GroupMessageRepository msgRepo,
  required String groupId,
  DateTime? membershipCutoff,
}) async {
  const pageSize = 500;
  final joinedPeerIds = <String>{};
  final normalizedCutoff = membershipCutoff?.toUtc();
  var offset = 0;
  while (true) {
    final page = await msgRepo.getMessagesPage(
      groupId,
      limit: pageSize,
      offset: offset,
    );
    for (final message in page) {
      if (normalizedCutoff != null &&
          message.timestamp.toUtc().isAfter(normalizedCutoff)) {
        continue;
      }
      final peerId = _memberJoinedTimelinePeerId(
        messageId: message.id,
        groupId: groupId,
      );
      if (peerId != null) {
        joinedPeerIds.add(peerId);
      }
    }
    if (page.length < pageSize) {
      break;
    }
    offset += page.length;
  }
  return joinedPeerIds;
}

String? _memberJoinedTimelinePeerId({
  required String messageId,
  required String groupId,
}) {
  final prefix = 'sys-member_joined:$groupId:';
  if (!messageId.startsWith(prefix)) {
    return null;
  }
  final suffix = messageId.substring(prefix.length);
  final timestampSeparator = suffix.lastIndexOf(':');
  if (timestampSeparator <= 0) {
    return null;
  }
  final peerId = suffix.substring(0, timestampSeparator).trim();
  return peerId.isEmpty || peerId == 'unknown' ? null : peerId;
}

bool _isPersistedNonJoinedInviteStatus(GroupInviteDeliveryStatus? status) {
  return status == GroupInviteDeliveryStatus.sent ||
      status == GroupInviteDeliveryStatus.queued ||
      status == GroupInviteDeliveryStatus.needsResend ||
      status == GroupInviteDeliveryStatus.cannotSend;
}

/// Whether a roster member should be excluded from the recipient set as a
/// not-yet-joined invitee: in a group where we have joined-evidence (an
/// invite-attempt `joined` status, or — when the invite repo is absent — a
/// member-joined timeline entry), a member with no invite status and no
/// join-timeline entry is treated as still pending and dropped (INV-106, to
/// avoid sending/notifying invitees who never accepted).
///
/// GATE — [isInviterTrackerDevice]: this inference is only valid on a device
/// that actually tracks invites it issued (it holds invite-attempt rows, or the
/// sender is an admin). On a joiner there is no pending-invitee state to protect
/// — its roster came from a signed config snapshot of confirmed-or-staged
/// members it cannot distinguish — so it must include every deliverable
/// incumbent, never silently drop one it didn't witness joining (REG-119b).
///
/// EXCEPTION — the group creator ([isGroupCreator]) is definitionally a joined
/// member and is NEVER dropped here. A freshly joined member holds no invite
/// record and no join-timeline entry for the creator (the creator never emits a
/// `sys-member_joined` entry), yet its OWN join sets [hasJoinedInviteEvidence];
/// without this exception the creator was excluded from every send by a joiner,
/// yielding expectedRecipientCount:0, no relay custody, and a vacuous "sent"
/// while the message was silently lost if the creator was offline (REG-119).
bool _isMissingInviteStatusInTrackedGroup({
  required GroupInviteDeliveryStatus? inviteStatus,
  required bool isInviterTrackerDevice,
  required bool hasJoinedInviteEvidence,
  required bool hasJoinedTimelineEvidence,
  required bool isGroupCreator,
}) {
  if (!isInviterTrackerDevice) {
    return false;
  }
  if (isGroupCreator) {
    return false;
  }
  if (inviteStatus == GroupInviteDeliveryStatus.unknown) {
    return true;
  }
  return inviteStatus == null &&
      hasJoinedInviteEvidence &&
      !hasJoinedTimelineEvidence;
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

bool _hasReliableGroupSendContract(Map<String, dynamic>? result) {
  if (result == null || result['ok'] != true) return false;
  return result.containsKey('publishSucceeded') &&
      result.containsKey('inboxStored') &&
      result.containsKey('expectedRecipientCount') &&
      (result.containsKey('topicPeerCount') ||
          result.containsKey('topicPeers'));
}

bool _reliableGroupSendUnavailable(Map<String, dynamic>? result) {
  if (result == null) return false;
  if (result['ok'] == true) return !_hasReliableGroupSendContract(result);
  final code = result['errorCode']?.toString();
  return code == 'UNKNOWN_COMMAND' ||
      code == 'MISSING_PLUGIN' ||
      code == 'NOT_IMPLEMENTED' ||
      code == 'UNIMPLEMENTED';
}

bool _reliableGroupSendTimedOut(Map<String, dynamic> result) {
  return result['ok'] != true &&
      result['errorCode']?.toString() == 'BRIDGE_TIMEOUT';
}

bool _reliablePublishSucceededWithoutCustody({
  required bool reliableOk,
  required bool publishSucceeded,
  required bool inboxOk,
  required int? topicPeers,
  required int expectedRecipientCount,
}) {
  return reliableOk &&
      publishSucceeded &&
      !inboxOk &&
      expectedRecipientCount > 0 &&
      topicPeers != null &&
      topicPeers <= 0;
}

int? _intResultField(Map<String, dynamic> result, String key) {
  final value = result[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

List<String> _stringListResultField(Map<String, dynamic> result, String key) {
  final value = result[key];
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

String? _nativeReliableInboxRetryPayload({
  required String groupId,
  required Map<String, dynamic> result,
  required String? fallback,
}) {
  final envelope = result['envelope'];
  if (envelope is! String || envelope.trim().isEmpty) return fallback;
  final recipientPeerIds = _stringListResultField(result, 'recipientPeerIds');
  return jsonEncode({
    'groupId': groupId,
    'message': envelope,
    if (result.containsKey('recipientPeerIds'))
      'recipientPeerIds': recipientPeerIds,
  });
}

String _defaultGroupMessageIdFactory() => const Uuid().v4();

String? _normalizeLogicalDeliveryId(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

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
  String? logicalDeliveryId,
}) {
  if (existing.isIncoming) return false;
  // 210: 'queued_offline' is a live re-usable optimistic row too — the
  // media/voice paths pre-persist the optimistic message before calling this use
  // case, so an offline pre-save must be reused (not treated as a collision that
  // mints a duplicate row with a fresh id).
  if (existing.status != 'sending' &&
      existing.status != 'failed' &&
      existing.status != 'pending' &&
      existing.status != GroupMessage.statusQueuedOffline) {
    return false;
  }
  if (existing.groupId != groupId || existing.senderPeerId != senderPeerId) {
    return false;
  }
  if (existing.text != text) return false;
  if (!_sameOptionalString(existing.quotedMessageId, quotedMessageId)) {
    return false;
  }
  final existingLogicalDeliveryId = _normalizeLogicalDeliveryId(
    existing.logicalDeliveryId,
  );
  final requestedLogicalDeliveryId = _normalizeLogicalDeliveryId(
    logicalDeliveryId,
  );
  if (existingLogicalDeliveryId != null &&
      requestedLogicalDeliveryId != null &&
      existingLogicalDeliveryId != requestedLogicalDeliveryId) {
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
  String? logicalDeliveryId,
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
      logicalDeliveryId: logicalDeliveryId,
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
  bool preserveRecipientPeerIds = false,
}) async {
  try {
    await callGroupInboxStore(
      bridge,
      groupId,
      inboxPayload,
      recipientPeerIds: recipientPeerIds,
      preserveRecipientPeerIds: preserveRecipientPeerIds,
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
  String? logicalDeliveryId,
  GroupMessageIdFactory? messageIdFactory,
  DateTime? timestamp,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  bool emitTimingEvent = true,
  bool includeSenderPeerIdInDurableRecipients = false,
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
  final sendAttemptAt = DateTime.now().toUtc();
  final membershipCutoff =
      timestamp != null && !timestamp.toUtc().isBefore(group.createdAt.toUtc())
      ? timestamp
      : null;
  final latestKeyFuture = groupRepo.getLatestKey(groupId);
  final sendMembershipFuture = _loadGroupSendMembership(
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    creatorPeerId: group.createdBy,
    senderRole: group.myRole,
    membershipCutoff: membershipCutoff,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
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
    logicalDeliveryId: logicalDeliveryId,
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
  final resolvedLogicalDeliveryId =
      _normalizeLogicalDeliveryId(logicalDeliveryId) ?? resolvedMessageId;
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
  final recipientPeerIds = _durableGroupRecipientPeerIds(
    remoteRecipientPeerIds: sendMembership.recipientPeerIds,
    senderPeerId: senderPeerId,
    includeSenderPeerId: includeSenderPeerIdInDurableRecipients,
  );
  final expectedRecipientCount = recipientPeerIds.length;
  final resolvedGroupName = group.name.trim();
  // 3b. Build wireEnvelope (plaintext publish params for retry - NO senderPrivateKey)
  final wireEnvelope = jsonEncode({
    'groupId': groupId,
    'text': sanitizedText,
    'senderPeerId': senderPeerId,
    'senderDeviceId': resolvedSenderDeviceId,
    'transportPeerId': resolvedSenderTransportPeerId,
    'senderPublicKey': senderPublicKey,
    'senderUsername': senderUsername,
    'messageId': resolvedMessageId,
    'logicalDeliveryId': resolvedLogicalDeliveryId,
    if (quotedMessageId != null && quotedMessageId.isNotEmpty)
      'quotedMessageId': quotedMessageId,
    if (mediaJson != null && mediaJson.isNotEmpty) 'media': mediaJson,
  });

  // 3c. Build inboxRetryPayload (exact inputs for callGroupInboxStore)
  final inboxPayload = jsonEncode({
    'groupId': groupId,
    if (resolvedGroupName.isNotEmpty) 'groupName': resolvedGroupName,
    'senderId': senderPeerId,
    'senderDeviceId': resolvedSenderDeviceId,
    'transportPeerId': resolvedSenderTransportPeerId,
    'senderUsername': senderUsername,
    'keyEpoch': keyEpoch,
    'text': sanitizedText,
    'timestamp': now.toIso8601String(),
    'messageId': resolvedMessageId,
    'logicalDeliveryId': resolvedLogicalDeliveryId,
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
      'recipientPeerIds': recipientPeerIds,
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
    lastSendAttemptAt: sendAttemptAt,
    quotedMessageId: quotedMessageId,
    logicalDeliveryId: resolvedLogicalDeliveryId,
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

  final reliableStopwatch = Stopwatch()..start();
  Map<String, dynamic> reliableResult;
  try {
    reliableResult = await callGroupSendReliable(
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
      logicalDeliveryId: resolvedLogicalDeliveryId,
      groupName: resolvedGroupName,
      timestamp: now,
      quotedMessageId: quotedMessageId,
      media: mediaJson,
      recipientPeerIds: recipientPeerIds,
      preserveRecipientPeerIds: true,
    );
  } catch (e) {
    reliableResult = {
      'ok': false,
      'errorCode': 'RELIABLE_SEND_FAILED',
      'errorMessage': e.toString(),
    };
  }
  reliableStopwatch.stop();
  if (!_reliableGroupSendUnavailable(reliableResult)) {
    publishMs = reliableStopwatch.elapsedMilliseconds;
    final reliableOk = reliableResult['ok'] == true;
    final publishSucceeded = reliableResult['publishSucceeded'] == true;
    final inboxOk = reliableResult['inboxStored'] == true;
    final topicPeers =
        _intResultField(reliableResult, 'topicPeerCount') ??
        _intResultField(reliableResult, 'topicPeers');
    // GAP 2: prefer the post-publish connected-topic-peer count (the Go recount
    // that captures peers which subscribed during the pre-publish settle window
    // and were delivered to by floodPublish) as the delivery signal; fall back
    // to the pre-publish mesh snapshot when the field is absent (older Go
    // binary) — byte-equivalent to today until the Go half ships.
    final connectedTopicPeers = _intResultField(
      reliableResult,
      'connectedTopicPeerCount',
    );
    final effectiveTopicPeers = connectedTopicPeers ?? topicPeers;
    final reliableExpectedRecipientCount =
        _intResultField(reliableResult, 'expectedRecipientCount') ??
        expectedRecipientCount;
    final retryPayload = inboxOk
        ? null
        : _nativeReliableInboxRetryPayload(
            groupId: groupId,
            result: reliableResult,
            fallback: prePersistMessage.inboxRetryPayload,
          );
    final reliableTimedOut = _reliableGroupSendTimedOut(reliableResult);
    final publishWithoutCustody = _reliablePublishSucceededWithoutCustody(
      reliableOk: reliableOk,
      publishSucceeded: publishSucceeded,
      inboxOk: inboxOk,
      topicPeers: effectiveTopicPeers,
      expectedRecipientCount: reliableExpectedRecipientCount,
    );

    if (reliableTimedOut || publishWithoutCustody) {
      // 210b: the two shapes are NOT the same lane. A bridge timeout is
      // genuinely in-doubt (the publish may have gone out) → 'pending' (amber
      // tick). Publish-without-custody is definitive — zero live topic peers
      // AND no relay custody, i.e. the realistic offline-device geometry —
      // → durable 'queued_offline' (clock + offline snackbar), self-healed by
      // the repush lane on reconnect. The shapes are mutually exclusive
      // (timeout ⇒ ok:false; without-custody ⇒ ok:true).
      final inDoubtMessage = prePersistMessage.copyWith(
        status: publishWithoutCustody
            ? GroupMessage.statusQueuedOffline
            : 'pending',
        wireEnvelope: reliableTimedOut ? prePersistMessage.wireEnvelope : null,
        inboxStored: inboxOk,
        inboxRetryPayload: retryPayload,
      );
      await msgRepo.saveMessage(inDoubtMessage);
      await _persistOutgoingMedia(
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: groupMediaAttachments
            ?.map(
              (attachment) => attachment.copyWith(messageId: resolvedMessageId),
            )
            .toList(growable: false),
      );

      final reason = reliableTimedOut
          ? 'bridge_timeout'
          : 'live_publish_without_custody';
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_RELIABLE_IN_DOUBT',
        details: {
          'messageId': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
          'reason': reason,
          'deliveryMode': reliableResult['deliveryMode'],
          ..._groupPublishFanoutEvidence(
            topicPeers: topicPeers,
            expectedRecipientCount: reliableExpectedRecipientCount,
            inboxOk: inboxOk,
          ),
        },
      );
      emitGroupSendTiming(
        outcome: 'reliable_in_doubt',
        details: {
          'status': inDoubtMessage.status,
          'reason': reason,
          'deliveryMode': reliableResult['deliveryMode'],
          ..._groupPublishFanoutEvidence(
            topicPeers: topicPeers,
            expectedRecipientCount: reliableExpectedRecipientCount,
            inboxOk: inboxOk,
          ),
        },
      );
      return (
        publishWithoutCustody
            ? SendGroupMessageResult.queuedOffline
            : SendGroupMessageResult.success,
        inDoubtMessage,
      );
    }

    if (!reliableOk || (!publishSucceeded && !inboxOk)) {
      await msgRepo.updateMessageStatus(resolvedMessageId, 'failed');
      await msgRepo.updateInboxStored(resolvedMessageId, stored: inboxOk);
      final failedMessage = prePersistMessage.copyWith(
        status: 'failed',
        inboxStored: inboxOk,
        inboxRetryPayload: retryPayload,
      );
      emitGroupSendTiming(
        outcome: 'reliable_failed',
        details: {
          'deliveryMode': reliableResult['deliveryMode'],
          ..._groupPublishFanoutEvidence(
            topicPeers: topicPeers,
            expectedRecipientCount: reliableExpectedRecipientCount,
            inboxOk: inboxOk,
          ),
        },
      );
      return (SendGroupMessageResult.error, failedMessage);
    }

    final canMarkSent =
        reliableExpectedRecipientCount <= 0 ||
        inboxOk ||
        (publishSucceeded && (effectiveTopicPeers ?? 0) > 0);
    if (!canMarkSent && (effectiveTopicPeers ?? 0) <= 0) {
      await msgRepo.updateMessageStatus(resolvedMessageId, 'failed');
      final failedMessage = prePersistMessage.copyWith(
        status: 'failed',
        inboxStored: false,
        inboxRetryPayload: retryPayload,
      );
      emitGroupSendTiming(
        outcome: 'zero_peers_inbox_failed',
        details: _groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: reliableExpectedRecipientCount,
          inboxOk: false,
        ),
      );
      return (SendGroupMessageResult.error, failedMessage);
    }

    final finalMessage = prePersistMessage.copyWith(
      status: canMarkSent ? 'sent' : 'pending',
      wireEnvelope: null,
      inboxStored: inboxOk,
      inboxRetryPayload: retryPayload,
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
    emitFlowEvent(
      layer: 'FL',
      event: topicPeers == 0 && inboxOk
          ? 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS'
          : 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        'deliveryMode': reliableResult['deliveryMode'],
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: reliableExpectedRecipientCount,
          inboxOk: inboxOk,
        ),
      },
    );
    emitGroupSendTiming(
      outcome: topicPeers == 0 && inboxOk ? 'success_no_peers' : 'success',
      details: {
        'status': finalMessage.status,
        'deliveryMode': reliableResult['deliveryMode'],
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: reliableExpectedRecipientCount,
          inboxOk: inboxOk,
        ),
      },
    );
    return (
      topicPeers == 0 && inboxOk
          ? SendGroupMessageResult.successNoPeers
          : SendGroupMessageResult.success,
      finalMessage,
    );
  }

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
    logicalDeliveryId: resolvedLogicalDeliveryId,
    groupName: resolvedGroupName,
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
                  recipientPeerIds: recipientPeerIds,
                  preserveRecipientPeerIds: true,
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
    // Normal success: explicit live peers make the message visibly sent.
    // Offline inbox custody remains tracked separately for retry.
    if (inboxResult == null) {
      await Future<void>.value();
    }
    final resolvedInboxOk = inboxResult;
    final finalMessage = prePersistMessage.copyWith(
      status: 'sent',
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
