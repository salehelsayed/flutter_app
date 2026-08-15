import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
import 'package:flutter_app/features/groups/application/group_sender_display_name.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const _maxIncomingMessageFutureClockSkew = Duration(minutes: 5);
const _incomingMediaRetrySearchLimit = 200;

/// Durable notification custody seam for one fully authorized incoming group
/// message. The stage callback runs immediately before canonical persistence;
/// the ready callback runs only after the parent and admitted media metadata
/// have committed. Callers that do not project notifications omit both.
typedef IncomingGroupMessageDisplayCustodyCallback =
    Future<void> Function(GroupMessage message);

/// An exceptional local projection policy for an otherwise authenticated
/// incoming group message. Ordinary live/replay callers omit this value.
enum GroupMessageDeliveryDisposition { historyRepair }

sealed class IncomingGroupMessageDetailedOutcome {
  const IncomingGroupMessageDetailedOutcome();

  const factory IncomingGroupMessageDetailedOutcome.delivered(
    GroupMessage message,
  ) = IncomingGroupMessageDelivered;

  factory IncomingGroupMessageDetailedOutcome.duplicateEnriched(
    GroupMessage canonicalMessage,
    Set<String> persistedAttachmentIds,
  ) = IncomingGroupMessageDuplicateEnriched;

  factory IncomingGroupMessageDetailedOutcome.duplicate(
    GroupMessage canonicalMessage,
  ) = IncomingGroupMessageDuplicate;

  const factory IncomingGroupMessageDetailedOutcome.ignored({
    GroupMessage? canonicalMessage,
  }) = IncomingGroupMessageIgnored;
}

final class IncomingGroupMessageDelivered
    extends IncomingGroupMessageDetailedOutcome {
  const IncomingGroupMessageDelivered(this.message);

  final GroupMessage message;
}

base class IncomingGroupMessageDuplicate
    extends IncomingGroupMessageDetailedOutcome {
  IncomingGroupMessageDuplicate(
    this.canonicalMessage, [
    Set<String> persistedAttachmentIds = const <String>{},
  ]) : persistedAttachmentIds = Set<String>.unmodifiable(
         persistedAttachmentIds,
       );

  final GroupMessage canonicalMessage;
  final Set<String> persistedAttachmentIds;
}

final class IncomingGroupMessageDuplicateEnriched
    extends IncomingGroupMessageDuplicate {
  IncomingGroupMessageDuplicateEnriched(
    GroupMessage canonicalMessage,
    Set<String> persistedAttachmentIds,
  ) : super(canonicalMessage, persistedAttachmentIds) {
    if (persistedAttachmentIds.isEmpty) {
      throw ArgumentError.value(
        persistedAttachmentIds,
        'persistedAttachmentIds',
        'must contain at least one committed attachment ID',
      );
    }
  }
}

final class IncomingGroupMessageIgnored
    extends IncomingGroupMessageDetailedOutcome {
  const IncomingGroupMessageIgnored({this.canonicalMessage});

  /// Present only when the event was an authority-exact stable-ID replay.
  /// Rejected/conflicting events deliberately carry no canonical authority.
  final GroupMessage? canonicalMessage;
}

/// Handles an incoming group message.
///
/// Verifies the group exists and the sender is a known member.
/// Checks for duplicates before saving. Returns the persisted [GroupMessage]
/// or null if the message was ignored.
Future<GroupMessage?> handleIncomingGroupMessage({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String senderId,
  required String senderUsername,
  required int keyEpoch,
  required String text,
  required String timestamp,
  String? selfPeerId,
  String? transportPeerId,
  String? senderDeviceId,
  String? messageId,
  String? logicalDeliveryId,
  String? quotedMessageId,
  // 236: exact-bool wire marker — absent/null/non-bool values decode false at
  // every caller, so legacy senders can never mark a row forwarded.
  bool isForwarded = false,
  Map<String, Object?> privateMediaPolicyFields = const <String, Object?>{},
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
  AppendGroupEventLogEntry? appendGroupEventLogEntry,
  bool enforceSelfJoinedAtLowerBound = false,
  String deliverySource = 'direct',
  GroupMessageDeliveryDisposition? deliveryDisposition,
  DateTime Function()? nowUtc,
  IncomingGroupMessageDisplayCustodyCallback? stageNotificationDisplayCustody,
  IncomingGroupMessageDisplayCustodyCallback?
  markNotificationDisplayCustodyReady,
}) async {
  final outcome = await handleIncomingGroupMessageDetailed(
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    groupId: groupId,
    senderId: senderId,
    senderUsername: senderUsername,
    keyEpoch: keyEpoch,
    text: text,
    timestamp: timestamp,
    selfPeerId: selfPeerId,
    transportPeerId: transportPeerId,
    senderDeviceId: senderDeviceId,
    messageId: messageId,
    logicalDeliveryId: logicalDeliveryId,
    quotedMessageId: quotedMessageId,
    isForwarded: isForwarded,
    privateMediaPolicyFields: privateMediaPolicyFields,
    media: media,
    mediaAttachmentRepo: mediaAttachmentRepo,
    appendGroupEventLogEntry: appendGroupEventLogEntry,
    enforceSelfJoinedAtLowerBound: enforceSelfJoinedAtLowerBound,
    deliverySource: deliverySource,
    deliveryDisposition: deliveryDisposition,
    nowUtc: nowUtc,
    stageNotificationDisplayCustody: stageNotificationDisplayCustody,
    markNotificationDisplayCustodyReady: markNotificationDisplayCustodyReady,
  );
  return outcome is IncomingGroupMessageDelivered ? outcome.message : null;
}

/// Detailed incoming-message result used by the live listener to distinguish
/// a new delivery from a stable duplicate that committed missing media.
Future<IncomingGroupMessageDetailedOutcome> handleIncomingGroupMessageDetailed({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String senderId,
  required String senderUsername,
  required int keyEpoch,
  required String text,
  required String timestamp,
  String? selfPeerId,
  String? transportPeerId,
  String? senderDeviceId,
  String? messageId,
  String? logicalDeliveryId,
  String? quotedMessageId,
  bool isForwarded = false,
  Map<String, Object?> privateMediaPolicyFields = const <String, Object?>{},
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
  AppendGroupEventLogEntry? appendGroupEventLogEntry,
  bool enforceSelfJoinedAtLowerBound = false,
  String deliverySource = 'direct',
  GroupMessageDeliveryDisposition? deliveryDisposition,
  DateTime Function()? nowUtc,
  IncomingGroupMessageDisplayCustodyCallback? stageNotificationDisplayCustody,
  IncomingGroupMessageDisplayCustodyCallback?
  markNotificationDisplayCustodyReady,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
    },
  );

  final sanitizedText = sanitizeMessageText(text);
  final normalizedMessageId = messageId?.trim();
  final stableMessageId =
      normalizedMessageId != null && normalizedMessageId.isNotEmpty
      ? normalizedMessageId
      : null;
  final stableLogicalDeliveryId =
      logicalDeliveryId != null && logicalDeliveryId.trim().isNotEmpty
      ? logicalDeliveryId.trim()
      : null;
  final normalizedTransportPeerId = transportPeerId?.trim();
  final resolvedTransportPeerId =
      normalizedTransportPeerId != null && normalizedTransportPeerId.isNotEmpty
      ? normalizedTransportPeerId
      : senderId;
  final normalizedSelfPeerId = selfPeerId?.trim();
  final localRecipientPeerId =
      normalizedSelfPeerId != null && normalizedSelfPeerId.isNotEmpty
      ? normalizedSelfPeerId
      : null;
  final hasExplicitPrivateMediaPolicy = GroupPrivateMediaPolicy.wireKeys.any(
    privateMediaPolicyFields.containsKey,
  );
  final mediaValidation = _validateIncomingMediaDescriptors(media);
  final decodedPrivateMediaPolicy = GroupPrivateMediaPolicy.fromWireExtras(
    privateMediaPolicyFields,
    eligibility: _incomingGroupPrivateMediaEligibility(
      text: sanitizedText,
      quotedMessageId: quotedMessageId,
      isForwarded: isForwarded,
      media: media,
    ),
  );
  if (!mediaValidation.isValid && !hasExplicitPrivateMediaPolicy) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_REJECTED_INVALID_MEDIA',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        'messageId': messageId,
        'reason': mediaValidation.reason,
      },
    );
    return const IncomingGroupMessageDetailedOutcome.ignored();
  }
  if (!mediaValidation.isValid) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_PRIVATE_MEDIA_DESCRIPTOR_UNSUPPORTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        'messageId': messageId,
        'reason': mediaValidation.reason,
      },
    );
  }
  final privateMediaPolicy = mediaValidation.isValid
      ? decodedPrivateMediaPolicy
      : GroupPrivateMediaPolicy.unsupported(
          sourceVersion: decodedPrivateMediaPolicy.version,
        );
  final admittedMedia = mediaValidation.isValid ? media : null;

  // Prefer messageId-based dedupe before any group/member lookups when event-log
  // tamper gating is not installed. If DB-002 logging is installed, the log
  // checks replay/tamper before dedupe can silently ignore a changed duplicate.
  if (appendGroupEventLogEntry == null && stableMessageId != null) {
    final existingById = await msgRepo.getMessage(stableMessageId);
    if (existingById != null &&
        _isConflictingDuplicateMessageId(
          existing: existingById,
          groupId: groupId,
          senderId: senderId,
          privateMediaPolicy: privateMediaPolicy,
        )) {
      _emitDuplicateMessageIdConflictRejected(
        messageId: stableMessageId,
        groupId: groupId,
        existing: existingById,
        senderId: senderId,
      );
      return const IncomingGroupMessageDetailedOutcome.ignored();
    }
    if (existingById != null && !_isRepairPlaceholder(existingById)) {
      final reconciledSelfEcho = await _reconcileOutgoingSelfEchoDuplicate(
        msgRepo: msgRepo,
        existing: existingById,
        messageId: stableMessageId,
        groupId: groupId,
        senderId: senderId,
        resolvedTransportPeerId: resolvedTransportPeerId,
        sanitizedText: sanitizedText,
        privateMediaPolicy: privateMediaPolicy,
        selfPeerId: selfPeerId,
        quotedMessageId: quotedMessageId,
        media: admittedMedia,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      if (reconciledSelfEcho != null) {
        return IncomingGroupMessageDetailedOutcome.delivered(
          reconciledSelfEcho,
        );
      }
      final persistedAttachmentIds = await _enrichExistingDuplicateMessage(
        msgRepo: msgRepo,
        groupId: groupId,
        messageId: stableMessageId,
        quotedMessageId: quotedMessageId,
        media: admittedMedia,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      final canonicalMessage =
          await msgRepo.getMessage(stableMessageId) ?? existingById;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        details: _incomingMessageIdentityDetails(
          groupId: groupId,
          senderId: senderId,
          sanitizedText: sanitizedText,
          timestamp: timestamp,
          deliverySource: deliverySource,
          rawMessageId: stableMessageId,
          logicalDeliveryId: stableLogicalDeliveryId,
          candidateLocalRowId: stableMessageId,
          localRow: canonicalMessage,
          dedupeBy: 'messageId',
        ),
      );
      return persistedAttachmentIds.isEmpty
          ? IncomingGroupMessageDetailedOutcome.ignored(
              canonicalMessage: canonicalMessage,
            )
          : IncomingGroupMessageDetailedOutcome.duplicateEnriched(
              canonicalMessage,
              persistedAttachmentIds,
            );
    }
  }

  // 1. Load group from repo (if not found, ignore)
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_UNKNOWN_GROUP',
      details: {},
    );
    return const IncomingGroupMessageDetailedOutcome.ignored();
  }

  // Parse timestamp before applying membership-boundary checks.
  final now = (nowUtc?.call() ?? DateTime.now()).toUtc();

  final normalizedTimestamp = _normalizeIncomingMessageTimestamp(
    timestamp: timestamp,
    receivedAt: now,
    groupId: groupId,
    senderId: senderId,
  );
  final isSystemMessage = text.startsWith('{"__sys":');

  final dissolvedAt = group.dissolvedAt?.toUtc();
  if (group.isDissolved &&
      (dissolvedAt == null || !normalizedTimestamp.isBefore(dissolvedAt))) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_DISSOLVED_AFTER_CUTOFF',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        if (dissolvedAt != null) 'dissolvedAt': dissolvedAt.toIso8601String(),
      },
    );
    return const IncomingGroupMessageDetailedOutcome.ignored();
  }

  GroupMember? localRecipientMember;
  String? localRecipientAccountPeerId = localRecipientPeerId;
  if (localRecipientPeerId != null) {
    localRecipientMember = await groupRepo.getMember(
      groupId,
      localRecipientPeerId,
    );
    if (localRecipientMember == null) {
      localRecipientMember = await _findLocalRecipientMemberByDeviceTransport(
        groupRepo: groupRepo,
        groupId: groupId,
        localTransportPeerId: localRecipientPeerId,
      );
      localRecipientAccountPeerId = localRecipientMember?.peerId;
    }
    if (!isSystemMessage && localRecipientMember == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_LOCAL_MEMBERSHIP_MISSING',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'selfPeerId': localRecipientPeerId.length > 8
              ? localRecipientPeerId.substring(0, 8)
              : localRecipientPeerId,
          'keyEpoch': keyEpoch,
        },
      );
      return const IncomingGroupMessageDetailedOutcome.ignored();
    }

    if (localRecipientMember != null &&
        localRecipientAccountPeerId != null &&
        localRecipientAccountPeerId.isNotEmpty) {
      final localRemovedAt = await msgRepo
          .getLatestSystemEventTimestampForTarget(
            groupId,
            eventType: 'member_removed',
            targetId: localRecipientAccountPeerId,
          );
      final localRejoinedAt = localRecipientMember.joinedAt.toUtc();
      final isReaddedAfterRemoval =
          localRemovedAt != null && localRejoinedAt.isAfter(localRemovedAt);
      final isRemovedIntervalReplay =
          localRemovedAt != null &&
          !normalizedTimestamp.isBefore(localRemovedAt) &&
          normalizedTimestamp.isBefore(localRejoinedAt);
      if (isReaddedAfterRemoval && isRemovedIntervalReplay) {
        emitFlowEvent(
          layer: 'FL',
          event: localRecipientAccountPeerId == localRecipientPeerId
              ? 'GROUP_HANDLE_INCOMING_MSG_SELF_REMOVED_WINDOW_AFTER_REJOIN'
              : 'GROUP_HANDLE_INCOMING_MSG_LOCAL_REMOVED_INTERVAL_REPLAY_REJECTED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'senderId': senderId.length > 8
                ? senderId.substring(0, 8)
                : senderId,
            'selfPeerId': localRecipientPeerId.length > 8
                ? localRecipientPeerId.substring(0, 8)
                : localRecipientPeerId,
            if (localRecipientAccountPeerId != localRecipientPeerId)
              'memberPeerId': localRecipientAccountPeerId.length > 8
                  ? localRecipientAccountPeerId.substring(0, 8)
                  : localRecipientAccountPeerId,
            'cutoffAt': localRemovedAt.toIso8601String(),
            'removedAt': localRemovedAt.toIso8601String(),
            'joinedAt': localRejoinedAt.toIso8601String(),
            'rejoinedAt': localRejoinedAt.toIso8601String(),
            'keyEpoch': keyEpoch,
          },
        );
        return const IncomingGroupMessageDetailedOutcome.ignored();
      }

      if (isReaddedAfterRemoval &&
          keyEpoch > 0 &&
          !normalizedTimestamp.isBefore(localRejoinedAt)) {
        final latestKey = await groupRepo.getLatestKey(groupId);
        final latestEpoch = latestKey?.keyGeneration ?? 0;
        if (latestEpoch > 0 && keyEpoch < latestEpoch) {
          emitFlowEvent(
            layer: 'FL',
            event:
                'GROUP_HANDLE_INCOMING_MSG_LOCAL_STALE_EPOCH_AFTER_READD_REJECTED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'senderId': senderId.length > 8
                  ? senderId.substring(0, 8)
                  : senderId,
              'selfPeerId': localRecipientPeerId.length > 8
                  ? localRecipientPeerId.substring(0, 8)
                  : localRecipientPeerId,
              if (localRecipientAccountPeerId != localRecipientPeerId)
                'memberPeerId': localRecipientAccountPeerId.length > 8
                    ? localRecipientAccountPeerId.substring(0, 8)
                    : localRecipientAccountPeerId,
              'keyEpoch': keyEpoch,
              'latestEpoch': latestEpoch,
              'rejoinedAt': localRejoinedAt.toIso8601String(),
            },
          );
          return const IncomingGroupMessageDetailedOutcome.ignored();
        }
      }
    }
  }

  // 2. Check sender is a member. A persisted pre-removal cutoff can still
  // admit traffic sent before removal; otherwise unknown senders fail closed.
  final member = senderId == localRecipientAccountPeerId
      ? localRecipientMember
      : await groupRepo.getMember(groupId, senderId);
  DateTime? senderRemovalCutoff;
  if (member == null) {
    senderRemovalCutoff = await msgRepo.getLatestRemovalTimestampForSender(
      groupId,
      senderId,
    );
    if (senderRemovalCutoff != null &&
        !normalizedTimestamp.isBefore(senderRemovalCutoff)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'cutoffAt': senderRemovalCutoff.toIso8601String(),
        },
      );
      return const IncomingGroupMessageDetailedOutcome.ignored();
    }

    if (senderRemovalCutoff == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_UNKNOWN_SENDER_REJECTED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'keyEpoch': keyEpoch,
        },
      );
      return const IncomingGroupMessageDetailedOutcome.ignored();
    }

    if (resolvedTransportPeerId != senderId) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_TRANSPORT_SENDER_MISMATCH',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'transportPeerId': resolvedTransportPeerId.length > 8
              ? resolvedTransportPeerId.substring(0, 8)
              : resolvedTransportPeerId,
        },
      );
      return const IncomingGroupMessageDetailedOutcome.ignored();
    }
  } else if (!_isSenderDeviceBound(
    member: member,
    senderDeviceId: senderDeviceId,
    transportPeerId: resolvedTransportPeerId,
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_UNBOUND_DEVICE_REJECTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        'transportPeerId': resolvedTransportPeerId.length > 8
            ? resolvedTransportPeerId.substring(0, 8)
            : resolvedTransportPeerId,
      },
    );
    return const IncomingGroupMessageDetailedOutcome.ignored();
  } else {
    senderRemovalCutoff = await msgRepo.getLatestRemovalTimestampForSender(
      groupId,
      senderId,
    );
    final joinedAt = member.joinedAt.toUtc();
    if (senderRemovalCutoff != null &&
        !normalizedTimestamp.isBefore(senderRemovalCutoff) &&
        normalizedTimestamp.isBefore(joinedAt)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_REMOVED_WINDOW_AFTER_REJOIN',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'cutoffAt': senderRemovalCutoff.toIso8601String(),
          'joinedAt': joinedAt.toIso8601String(),
        },
      );
      return const IncomingGroupMessageDetailedOutcome.ignored();
    }

    if (senderRemovalCutoff != null &&
        keyEpoch > 0 &&
        !joinedAt.isBefore(senderRemovalCutoff) &&
        !normalizedTimestamp.isBefore(joinedAt)) {
      final latestKey = await groupRepo.getLatestKey(groupId);
      final latestEpoch = latestKey?.keyGeneration ?? 0;
      if (latestEpoch > 0 && keyEpoch < latestEpoch) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_HANDLE_INCOMING_MSG_STALE_EPOCH_AFTER_READD_REJECTED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'senderId': senderId.length > 8
                ? senderId.substring(0, 8)
                : senderId,
            'keyEpoch': keyEpoch,
            'latestEpoch': latestEpoch,
            'rejoinedAt': joinedAt.toIso8601String(),
          },
        );
        return const IncomingGroupMessageDetailedOutcome.ignored();
      }
    }
  }

  // Live GossipSub independently enforces announcement writers in Go, but an
  // authenticated offline replay reaches this shared persistence boundary
  // without traversing the topic validator. Re-check the current roster here
  // so a reader, writer, removed member, or demoted former admin cannot persist
  // an ordinary or lifecycle-tagged announcement through that alternate path.
  // System traffic keeps its existing dedicated authorization/replay contract.
  if (!isSystemMessage &&
      group.type == GroupType.announcement &&
      (member == null || member.role != MemberRole.admin)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_ANNOUNCEMENT_NON_ADMIN_REJECTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        'deliverySource': deliverySource,
      },
    );
    return const IncomingGroupMessageDetailedOutcome.ignored();
  }

  if (localRecipientPeerId != null) {
    final selfJoinedAt = localRecipientMember?.joinedAt.toUtc();
    if (!isSystemMessage &&
        enforceSelfJoinedAtLowerBound &&
        selfJoinedAt != null &&
        !normalizedTimestamp.isBefore(group.createdAt.toUtc()) &&
        normalizedTimestamp.isBefore(selfJoinedAt)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_BEFORE_SELF_JOINED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'selfPeerId': localRecipientPeerId.length > 8
              ? localRecipientPeerId.substring(0, 8)
              : localRecipientPeerId,
          'joinedAt': selfJoinedAt.toIso8601String(),
        },
      );
      return const IncomingGroupMessageDetailedOutcome.ignored();
    }
  }
  final sanitizedSenderUsername = sanitizeUsername(senderUsername).trim();
  final preferCurrentMemberUsername = _preferCurrentMemberUsernameAfterReadd(
    member: member,
    removalCutoff: senderRemovalCutoff,
    messageTimestamp: normalizedTimestamp,
  );
  final resolvedSenderUsername = resolveGroupSenderDisplayName(
    senderPeerId: senderId,
    wireSenderUsername: sanitizedSenderUsername,
    member: member,
    preferMemberName: preferCurrentMemberUsername,
  );

  if (appendGroupEventLogEntry != null) {
    final sourceEventId =
        stableMessageId ??
        'message:$groupId:$senderId:${normalizedTimestamp.toIso8601String()}:$sanitizedText';
    await appendGroupEventLogEntry(
      groupId: groupId,
      eventType: 'message',
      sourcePeerId: senderId,
      sourceEventId: sourceEventId,
      sourceTimestamp: normalizedTimestamp.toIso8601String(),
      payload: {
        'messageId': messageId,
        'logicalDeliveryId': stableLogicalDeliveryId,
        'groupId': groupId,
        'senderId': senderId,
        'senderUsername': resolvedSenderUsername,
        'transportPeerId': resolvedTransportPeerId,
        'senderDeviceId': senderDeviceId,
        'text': sanitizedText,
        'timestamp': normalizedTimestamp.toIso8601String(),
        'keyEpoch': keyEpoch,
        'quotedMessageId': quotedMessageId,
        'media': admittedMedia ?? const <Map<String, dynamic>>[],
        ..._presentGroupPrivateMediaPolicyFields(privateMediaPolicyFields),
      },
    );
  }

  if (stableMessageId != null) {
    final existingById = await msgRepo.getMessage(stableMessageId);
    if (existingById != null &&
        _isConflictingDuplicateMessageId(
          existing: existingById,
          groupId: groupId,
          senderId: senderId,
          privateMediaPolicy: privateMediaPolicy,
        )) {
      _emitDuplicateMessageIdConflictRejected(
        messageId: stableMessageId,
        groupId: groupId,
        existing: existingById,
        senderId: senderId,
      );
      return const IncomingGroupMessageDetailedOutcome.ignored();
    }
    if (existingById != null && !_isRepairPlaceholder(existingById)) {
      final reconciledSelfEcho = await _reconcileOutgoingSelfEchoDuplicate(
        msgRepo: msgRepo,
        existing: existingById,
        messageId: stableMessageId,
        groupId: groupId,
        senderId: senderId,
        resolvedTransportPeerId: resolvedTransportPeerId,
        sanitizedText: sanitizedText,
        privateMediaPolicy: privateMediaPolicy,
        selfPeerId: selfPeerId,
        quotedMessageId: quotedMessageId,
        media: admittedMedia,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      if (reconciledSelfEcho != null) {
        return IncomingGroupMessageDetailedOutcome.delivered(
          reconciledSelfEcho,
        );
      }
      final persistedAttachmentIds = await _enrichExistingDuplicateMessage(
        msgRepo: msgRepo,
        groupId: groupId,
        messageId: stableMessageId,
        quotedMessageId: quotedMessageId,
        media: admittedMedia,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      final canonicalMessage =
          await msgRepo.getMessage(stableMessageId) ?? existingById;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        details: _incomingMessageIdentityDetails(
          groupId: groupId,
          senderId: senderId,
          sanitizedText: sanitizedText,
          timestamp: normalizedTimestamp.toIso8601String(),
          deliverySource: deliverySource,
          rawMessageId: stableMessageId,
          logicalDeliveryId: stableLogicalDeliveryId,
          candidateLocalRowId: stableMessageId,
          localRow: canonicalMessage,
          dedupeBy: 'messageId',
        ),
      );
      return persistedAttachmentIds.isEmpty
          ? IncomingGroupMessageDetailedOutcome.ignored(
              canonicalMessage: canonicalMessage,
            )
          : IncomingGroupMessageDetailedOutcome.duplicateEnriched(
              canonicalMessage,
              persistedAttachmentIds,
            );
    }
  }

  if (stableMessageId != null && stableLogicalDeliveryId != null) {
    final existingByLogicalDelivery = await msgRepo
        .getMessageByLogicalDeliveryId(
          groupId,
          senderId,
          stableLogicalDeliveryId,
        );
    if (existingByLogicalDelivery != null &&
        existingByLogicalDelivery.id != stableMessageId &&
        !_isRepairPlaceholder(existingByLogicalDelivery)) {
      // A reminted wire ID acquires its own alias custody before duplicate
      // enrichment mutates canonical media. The listener atomically moves
      // that custody back to the original canonical message afterward.
      await stageNotificationDisplayCustody?.call(
        existingByLogicalDelivery.copyWith(id: stableMessageId),
      );
      final persistedAttachmentIds = await _enrichExistingDuplicateMessage(
        msgRepo: msgRepo,
        groupId: groupId,
        messageId: existingByLogicalDelivery.id,
        quotedMessageId: quotedMessageId,
        media: admittedMedia,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      final canonicalMessage =
          await msgRepo.getMessage(existingByLogicalDelivery.id) ??
          existingByLogicalDelivery;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        details: _incomingMessageIdentityDetails(
          groupId: groupId,
          senderId: senderId,
          sanitizedText: sanitizedText,
          timestamp: normalizedTimestamp.toIso8601String(),
          deliverySource: deliverySource,
          rawMessageId: stableMessageId,
          logicalDeliveryId: stableLogicalDeliveryId,
          candidateLocalRowId: stableMessageId,
          localRow: canonicalMessage,
          dedupeBy: 'logicalDeliveryId',
        ),
      );
      return persistedAttachmentIds.isEmpty
          ? IncomingGroupMessageDetailedOutcome.duplicate(canonicalMessage)
          : IncomingGroupMessageDetailedOutcome.duplicateEnriched(
              canonicalMessage,
              persistedAttachmentIds,
            );
    }
  }

  final isSelfDelivery = _isLocalSelfDelivery(
    senderId: senderId,
    senderTransportPeerId: resolvedTransportPeerId,
    localRecipientPeerId: localRecipientPeerId,
    localRecipientAccountPeerId: localRecipientAccountPeerId,
  );
  if (stableMessageId != null &&
      !isSelfDelivery &&
      admittedMedia != null &&
      admittedMedia.isNotEmpty &&
      mediaAttachmentRepo != null) {
    final canonicalMessageId = await _findCanonicalIncomingMediaRetryMessageId(
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      groupId: groupId,
      senderId: senderId,
      resolvedTransportPeerId: resolvedTransportPeerId,
      sanitizedText: sanitizedText,
      normalizedTimestamp: normalizedTimestamp,
      quotedMessageId: quotedMessageId,
      duplicateMessageId: stableMessageId,
      media: admittedMedia,
      privateMediaPolicy: privateMediaPolicy,
    );
    if (canonicalMessageId != null) {
      final persistedAttachmentIds = await _enrichExistingDuplicateMessage(
        msgRepo: msgRepo,
        groupId: groupId,
        messageId: canonicalMessageId,
        quotedMessageId: quotedMessageId,
        media: admittedMedia,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      final canonicalMessage = await msgRepo.getMessage(canonicalMessageId);
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        details: _incomingMessageIdentityDetails(
          groupId: groupId,
          senderId: senderId,
          sanitizedText: sanitizedText,
          timestamp: normalizedTimestamp.toIso8601String(),
          deliverySource: deliverySource,
          rawMessageId: stableMessageId,
          logicalDeliveryId: stableLogicalDeliveryId,
          candidateLocalRowId: stableMessageId,
          localRow: canonicalMessage,
          dedupeBy: 'logicalMediaRetry',
        ),
      );
      return persistedAttachmentIds.isEmpty || canonicalMessage == null
          ? const IncomingGroupMessageDetailedOutcome.ignored()
          : IncomingGroupMessageDetailedOutcome.duplicateEnriched(
              canonicalMessage,
              persistedAttachmentIds,
            );
    }
  }

  if (member != null &&
      sanitizedSenderUsername.isNotEmpty &&
      member.username?.trim() != sanitizedSenderUsername &&
      !preferCurrentMemberUsername) {
    await groupRepo.saveMember(
      member.copyWith(username: sanitizedSenderUsername),
    );
  }

  // Fallback: content-based dedupe for messages without a messageId.
  if (stableMessageId == null) {
    final isDuplicate = await msgRepo.existsByContent(
      groupId,
      senderId,
      sanitizedText,
      normalizedTimestamp,
    );
    if (isDuplicate) {
      final existingByContent = await _findExistingIncomingContentDuplicate(
        msgRepo: msgRepo,
        groupId: groupId,
        senderId: senderId,
        sanitizedText: sanitizedText,
        normalizedTimestamp: normalizedTimestamp,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        details: _incomingMessageIdentityDetails(
          groupId: groupId,
          senderId: senderId,
          sanitizedText: sanitizedText,
          timestamp: normalizedTimestamp.toIso8601String(),
          deliverySource: deliverySource,
          localRow: existingByContent,
          dedupeBy: 'content',
        ),
      );
      return const IncomingGroupMessageDetailedOutcome.ignored();
    }
  }

  // 4. Use wire messageId if provided, otherwise generate one
  final resolvedMessageId = stableMessageId ?? const Uuid().v4();
  final mediaReceivedAt = privateMediaPolicy.requiresRedaction
      ? now.millisecondsSinceEpoch
      : null;
  final mediaExpiresAt =
      privateMediaPolicy.isPrivate &&
          privateMediaPolicy.lifecycle == GroupMediaLifecycle.disappearing
      ? now
            .add(Duration(seconds: privateMediaPolicy.durationSeconds!))
            .millisecondsSinceEpoch
      : null;

  // 5. Create GroupMessage (isIncoming: true)
  final message = GroupMessage(
    id: resolvedMessageId,
    groupId: groupId,
    senderPeerId: senderId,
    transportPeerId: resolvedTransportPeerId,
    senderUsername: resolvedSenderUsername,
    text: sanitizedText,
    timestamp: normalizedTimestamp,
    quotedMessageId: quotedMessageId,
    logicalDeliveryId: stableLogicalDeliveryId,
    keyGeneration: keyEpoch,
    status: isSelfDelivery ? 'sent' : 'delivered',
    isIncoming: !isSelfDelivery,
    isForwarded: isForwarded,
    readAt: deliveryDisposition == GroupMessageDeliveryDisposition.historyRepair
        ? now
        : null,
    createdAt: now,
    privateMediaPolicy: privateMediaPolicy,
    mediaReceivedAt: mediaReceivedAt,
    mediaExpiresAt: mediaExpiresAt,
    mediaLastCheckedAt: mediaExpiresAt == null ? null : mediaReceivedAt,
    mediaCleanupPending: privateMediaPolicy.isUnsupported,
  );

  // Plan 330: acquire durable, identifier-only display custody before the
  // canonical mutation. If staging fails, propagate the error so the existing
  // live/relay/pending owner can retry and no eligible canonical event can be
  // committed markerless.
  await stageNotificationDisplayCustody?.call(message);

  // 6. Save to repo
  await msgRepo.saveMessage(message);
  if (message.mediaExpiresAt != null) {
    signalGroupPrivateMediaExpiryChanged();
  }

  // 7. Save media attachments (pending for relay download). 235: the final
  // attachment write re-verifies the exact (group_id, message_id) parent and
  // the deletion journal INSIDE its own transaction — a parent silently
  // rejected by the migration-069 tombstone must not acquire attachment rows.
  await _saveIncomingMediaAttachments(
    groupId: groupId,
    messageId: resolvedMessageId,
    media: admittedMedia,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );

  // A not-ready marker must never race projection before all canonical media
  // descriptors have landed. Failure leaves the durable marker not-ready and
  // deliberately propagates so replay can reconcile it.
  await markNotificationDisplayCustodyReady?.call(message);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
    details: _incomingMessageIdentityDetails(
      groupId: groupId,
      senderId: senderId,
      sanitizedText: sanitizedText,
      timestamp: normalizedTimestamp.toIso8601String(),
      deliverySource: deliverySource,
      rawMessageId: stableMessageId,
      logicalDeliveryId: stableLogicalDeliveryId,
      candidateLocalRowId: resolvedMessageId,
      localRow: message,
    ),
  );

  return IncomingGroupMessageDetailedOutcome.delivered(message);
}

Map<String, dynamic> _incomingMessageIdentityDetails({
  required String groupId,
  required String senderId,
  required String sanitizedText,
  required String timestamp,
  required String deliverySource,
  String? rawMessageId,
  String? logicalDeliveryId,
  String? candidateLocalRowId,
  GroupMessage? localRow,
  String? dedupeBy,
}) {
  final details = <String, dynamic>{
    'groupId': groupId,
    'senderId': senderId,
    'text': sanitizedText,
    'timestamp': timestamp,
    'deliverySource': deliverySource,
  };
  if (dedupeBy != null) {
    details['dedupeBy'] = dedupeBy;
  }
  if (rawMessageId != null && rawMessageId.isNotEmpty) {
    details['rawMessageId'] = rawMessageId;
  }
  if (logicalDeliveryId != null && logicalDeliveryId.isNotEmpty) {
    details['logicalDeliveryId'] = logicalDeliveryId;
  }
  if (candidateLocalRowId != null && candidateLocalRowId.isNotEmpty) {
    details['candidateLocalRowId'] = candidateLocalRowId;
  }
  if (localRow != null) {
    details.addAll({
      'messageId': localRow.id,
      'localRowId': localRow.id,
      'createdAt': localRow.createdAt.toUtc().toIso8601String(),
      'incoming': localRow.isIncoming,
      'rowTimestamp': localRow.timestamp.toUtc().toIso8601String(),
    });
    if (dedupeBy != null) {
      details['existingLocalRowId'] = localRow.id;
    }
    final quotedMessageId = localRow.quotedMessageId;
    if (quotedMessageId != null && quotedMessageId.isNotEmpty) {
      details['quotedMessageId'] = quotedMessageId;
    }
  }
  return details;
}

Future<GroupMessage?> _findExistingIncomingContentDuplicate({
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String senderId,
  required String sanitizedText,
  required DateTime normalizedTimestamp,
}) async {
  const pageSize = 500;
  var offset = 0;
  while (true) {
    final page = await msgRepo.getMessagesPage(
      groupId,
      limit: pageSize,
      offset: offset,
    );
    for (final message in page) {
      if (message.groupId == groupId &&
          message.senderPeerId == senderId &&
          message.text == sanitizedText &&
          message.timestamp.toUtc().isAtSameMomentAs(
            normalizedTimestamp.toUtc(),
          )) {
        return message;
      }
    }
    if (page.length < pageSize) {
      return null;
    }
    offset += page.length;
  }
}

bool _isRepairPlaceholder(GroupMessage message) {
  return message.isIncoming &&
      (message.status == groupPendingKeyRepairStatusPendingKey ||
          message.status == groupPendingKeyRepairStatusUndecryptable);
}

bool _isConflictingDuplicateMessageId({
  required GroupMessage existing,
  required String groupId,
  required String senderId,
  required GroupPrivateMediaPolicy privateMediaPolicy,
}) {
  return existing.groupId != groupId ||
      existing.senderPeerId != senderId ||
      existing.privateMediaPolicy != privateMediaPolicy;
}

Future<String?> _findCanonicalIncomingMediaRetryMessageId({
  required GroupMessageRepository msgRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required String groupId,
  required String senderId,
  required String resolvedTransportPeerId,
  required String sanitizedText,
  required DateTime normalizedTimestamp,
  required String? quotedMessageId,
  required String duplicateMessageId,
  required List<Map<String, dynamic>> media,
  required GroupPrivateMediaPolicy privateMediaPolicy,
}) async {
  final incomingMediaIdentity = _strictMediaIdentityFromWireDescriptors(media);
  if (incomingMediaIdentity == null) {
    return null;
  }

  final candidates = await msgRepo.getMessagesPage(
    groupId,
    limit: _incomingMediaRetrySearchLimit,
  );
  final candidateIds = <String>[];
  for (final candidate in candidates) {
    if (_isSameLogicalIncomingMediaRetryEnvelope(
      existing: candidate,
      groupId: groupId,
      senderId: senderId,
      resolvedTransportPeerId: resolvedTransportPeerId,
      sanitizedText: sanitizedText,
      normalizedTimestamp: normalizedTimestamp,
      quotedMessageId: quotedMessageId,
      duplicateMessageId: duplicateMessageId,
      privateMediaPolicy: privateMediaPolicy,
    )) {
      candidateIds.add(candidate.id);
    }
  }
  if (candidateIds.isEmpty) {
    return null;
  }

  final attachmentsByMessage = await mediaAttachmentRepo
      .getAttachmentsForMessages(candidateIds, owner: MediaOwnerLane.group);
  for (final candidateId in candidateIds) {
    final candidateMediaIdentity = _strictMediaIdentityFromSavedAttachments(
      attachmentsByMessage[candidateId],
    );
    if (_sameStrictMediaIdentity(
      incomingMediaIdentity,
      candidateMediaIdentity,
    )) {
      return candidateId;
    }
  }
  return null;
}

bool _isSameLogicalIncomingMediaRetryEnvelope({
  required GroupMessage existing,
  required String groupId,
  required String senderId,
  required String resolvedTransportPeerId,
  required String sanitizedText,
  required DateTime normalizedTimestamp,
  required String? quotedMessageId,
  required String duplicateMessageId,
  required GroupPrivateMediaPolicy privateMediaPolicy,
}) {
  final existingTransportPeerId =
      existing.transportPeerId?.trim().isNotEmpty == true
      ? existing.transportPeerId!.trim()
      : existing.senderPeerId;
  return existing.id != duplicateMessageId &&
      existing.groupId == groupId &&
      existing.senderPeerId == senderId &&
      existingTransportPeerId == resolvedTransportPeerId &&
      existing.isIncoming &&
      existing.status == 'delivered' &&
      existing.privateMediaPolicy == privateMediaPolicy &&
      existing.text == sanitizedText &&
      existing.timestamp.toUtc().isAtSameMomentAs(
        normalizedTimestamp.toUtc(),
      ) &&
      _normalizedOptionalIdentityString(existing.quotedMessageId) ==
          _normalizedOptionalIdentityString(quotedMessageId);
}

List<String>? _strictMediaIdentityFromWireDescriptors(
  List<Map<String, dynamic>> media,
) {
  if (media.isEmpty) {
    return null;
  }
  final signatures = <String>[];
  for (final rawAttachment in media) {
    final attachment =
        GroupMediaMimePolicy.sanitizeWireAttachment(
          rawAttachment,
          messageId: '',
        ).copyWith(
          contentHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            _optionalString(rawAttachment, 'contentHash'),
          ),
          thumbnailHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            _optionalString(rawAttachment, 'thumbnailHash'),
          ),
        );
    final signature = _strictMediaAttachmentSignature(attachment);
    if (signature == null) {
      return null;
    }
    signatures.add(signature);
  }
  signatures.sort();
  return signatures;
}

List<String>? _strictMediaIdentityFromSavedAttachments(
  List<MediaAttachment>? attachments,
) {
  if (attachments == null || attachments.isEmpty) {
    return null;
  }
  final signatures = <String>[];
  for (final rawAttachment in attachments) {
    final attachment = GroupMediaMimePolicy.sanitizeAttachment(
      rawAttachment.copyWith(
        contentHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
          rawAttachment.contentHash,
        ),
        thumbnailHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
          rawAttachment.thumbnailHash,
        ),
      ),
    );
    final signature = _strictMediaAttachmentSignature(attachment);
    if (signature == null) {
      return null;
    }
    signatures.add(signature);
  }
  signatures.sort();
  return signatures;
}

String? _strictMediaAttachmentSignature(MediaAttachment attachment) {
  final id = attachment.id.trim();
  final contentHash = attachment.contentHash?.trim().toLowerCase();
  final encryptionKeyBase64 = attachment.encryptionKeyBase64?.trim();
  final encryptionNonce = attachment.encryptionNonce?.trim();
  final encryptionScheme = attachment.encryptionScheme?.trim();
  if (id.isEmpty ||
      contentHash == null ||
      contentHash.isEmpty ||
      encryptionKeyBase64 == null ||
      encryptionKeyBase64.isEmpty ||
      encryptionNonce == null ||
      encryptionNonce.isEmpty ||
      (encryptionScheme != null &&
          encryptionScheme.isNotEmpty &&
          encryptionScheme != kMediaAttachmentEncryptionSchemeBlobAesGcmV1)) {
    return null;
  }

  final mime = GroupMediaMimePolicy.normalizeMime(attachment.mime);
  if (mime == null) {
    return null;
  }
  return [
    id,
    mime,
    attachment.mediaType.trim().toLowerCase(),
    attachment.size.toString(),
    contentHash,
    attachment.thumbnailHash?.trim().toLowerCase() ?? '',
    encryptionKeyBase64,
    encryptionNonce,
    encryptionScheme ?? '',
    attachment.width?.toString() ?? '',
    attachment.height?.toString() ?? '',
    attachment.durationMs?.toString() ?? '',
  ].join('|');
}

bool _sameStrictMediaIdentity(List<String> left, List<String>? right) {
  if (right == null || left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

String? _normalizedOptionalIdentityString(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

Future<GroupMember?> _findLocalRecipientMemberByDeviceTransport({
  required GroupRepository groupRepo,
  required String groupId,
  required String localTransportPeerId,
}) async {
  final members = await groupRepo.getMembers(groupId);
  for (final member in members) {
    final device = member.findDeviceByTransportPeerId(localTransportPeerId);
    if (device != null && device.isActive) {
      return member;
    }
  }
  return null;
}

bool _isLocalSelfDelivery({
  required String senderId,
  required String senderTransportPeerId,
  required String? localRecipientPeerId,
  required String? localRecipientAccountPeerId,
}) {
  if (localRecipientPeerId == null) return false;
  if (senderId == localRecipientPeerId) return true;
  return localRecipientAccountPeerId != null &&
      senderId == localRecipientAccountPeerId &&
      senderTransportPeerId == localRecipientPeerId;
}

bool _isSenderDeviceBound({
  required GroupMember member,
  required String? senderDeviceId,
  required String transportPeerId,
}) {
  if (member.devices.isEmpty) {
    return transportPeerId == member.peerId;
  }
  GroupMemberDeviceIdentity? device;
  if (senderDeviceId?.trim().isNotEmpty == true) {
    device = member.findDeviceById(senderDeviceId);
  } else {
    device = member.findDeviceByTransportPeerId(transportPeerId);
  }
  return device != null &&
      device.isActive &&
      device.transportPeerId == transportPeerId;
}

bool _canReconcileOutgoingSelfEchoStatus(GroupMessage existing) {
  // 210b: 'queued_offline' included — a self echo is positive proof the
  // message reached the network (e.g. a peer subscribed during the publish
  // settle window echoes back before the repush pass settles the row), so the
  // clock must yield to the tick instead of the echo being rejected.
  if (existing.status == 'sending' ||
      existing.status == 'pending' ||
      existing.status == GroupMessage.statusQueuedOffline) {
    return true;
  }
  if (existing.status != 'failed') {
    return false;
  }
  return existing.wireEnvelope?.isNotEmpty == true ||
      existing.inboxRetryPayload?.isNotEmpty == true;
}

void _emitDuplicateMessageIdConflictRejected({
  required String messageId,
  required String groupId,
  required GroupMessage existing,
  required String senderId,
}) {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE_ID_CONFLICT_REJECTED',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'existingGroupId': existing.groupId.length > 8
          ? existing.groupId.substring(0, 8)
          : existing.groupId,
      'existingSenderId': existing.senderPeerId.length > 8
          ? existing.senderPeerId.substring(0, 8)
          : existing.senderPeerId,
      'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
    },
  );
}

Future<GroupMessage?> _reconcileOutgoingSelfEchoDuplicate({
  required GroupMessageRepository msgRepo,
  required GroupMessage existing,
  required String messageId,
  required String groupId,
  required String senderId,
  required String resolvedTransportPeerId,
  required String sanitizedText,
  required GroupPrivateMediaPolicy privateMediaPolicy,
  required String? selfPeerId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  final normalizedSelfPeerId = selfPeerId?.trim();
  if (normalizedSelfPeerId == null || normalizedSelfPeerId.isEmpty) {
    return null;
  }
  if (senderId != normalizedSelfPeerId &&
      resolvedTransportPeerId != normalizedSelfPeerId) {
    return null;
  }
  if (existing.id != messageId ||
      existing.groupId != groupId ||
      existing.senderPeerId != senderId ||
      existing.privateMediaPolicy != privateMediaPolicy ||
      (existing.transportPeerId?.isNotEmpty == true &&
          existing.transportPeerId != resolvedTransportPeerId) ||
      existing.isIncoming) {
    return null;
  }
  if (!_canReconcileOutgoingSelfEchoStatus(existing)) {
    return null;
  }
  if (existing.text != sanitizedText) {
    return null;
  }

  final reconciled = existing.copyWith(
    status: 'sent',
    isIncoming: false,
    quotedMessageId: _reconciledQuotedMessageId(
      existing.quotedMessageId,
      quotedMessageId,
    ),
    wireEnvelope: null,
  );
  await msgRepo.saveMessage(reconciled);
  await _saveIncomingMediaAttachments(
    groupId: groupId,
    messageId: messageId,
    media: media,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_SELF_ECHO_RECONCILED',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );
  return reconciled;
}

String? _reconciledQuotedMessageId(
  String? existingQuotedMessageId,
  String? incomingQuotedMessageId,
) {
  if (existingQuotedMessageId != null && existingQuotedMessageId.isNotEmpty) {
    return existingQuotedMessageId;
  }
  if (incomingQuotedMessageId != null && incomingQuotedMessageId.isNotEmpty) {
    return incomingQuotedMessageId;
  }
  return existingQuotedMessageId;
}

DateTime _normalizeIncomingMessageTimestamp({
  required String timestamp,
  required DateTime receivedAt,
  required String groupId,
  required String senderId,
}) {
  final parsedTimestamp = DateTime.tryParse(timestamp)?.toUtc();
  if (parsedTimestamp == null) {
    return receivedAt;
  }

  final latestAllowed = receivedAt.add(_maxIncomingMessageFutureClockSkew);
  if (!parsedTimestamp.isAfter(latestAllowed)) {
    return parsedTimestamp;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_FUTURE_TIMESTAMP_CLAMPED',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      'timestamp': parsedTimestamp.toIso8601String(),
    },
  );
  return receivedAt;
}

Future<Set<String>> _enrichExistingDuplicateMessage({
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String messageId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  final existing = await msgRepo.getMessage(messageId);
  final mediaSave = await _saveIncomingMediaAttachmentsWithOutcome(
    groupId: groupId,
    messageId: messageId,
    media: media,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );
  final allMissingMediaWasRefused =
      mediaSave.hadMissingAttachments &&
      mediaSave.persistedAttachmentIds.isEmpty;
  // A guarded refusal is one zero-write outcome: it must not leak a quote-only
  // mutation. Quote-only and already-complete stable replays keep their
  // existing repair behavior because they had no missing media to refuse.
  if (!allMissingMediaWasRefused &&
      existing != null &&
      (existing.quotedMessageId == null || existing.quotedMessageId!.isEmpty) &&
      quotedMessageId != null &&
      quotedMessageId.isNotEmpty) {
    await msgRepo.saveMessage(
      existing.copyWith(quotedMessageId: quotedMessageId),
    );
  }

  return mediaSave.persistedAttachmentIds;
}

Future<Set<String>> _saveIncomingMediaAttachments({
  required String groupId,
  required String messageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  final outcome = await _saveIncomingMediaAttachmentsWithOutcome(
    groupId: groupId,
    messageId: messageId,
    media: media,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );
  return outcome.persistedAttachmentIds;
}

Future<({Set<String> persistedAttachmentIds, bool hadMissingAttachments})>
_saveIncomingMediaAttachmentsWithOutcome({
  required String groupId,
  required String messageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (media == null || mediaAttachmentRepo == null) {
    return (
      persistedAttachmentIds: const <String>{},
      hadMissingAttachments: false,
    );
  }
  // 235: prefer the guarded final write (exact-parent + deletion-journal
  // check inside the row-write transaction). A repository without the
  // capability keeps the legacy behavior.
  final guardedRepo = mediaAttachmentRepo is GroupGuardedMediaAttachmentSave
      ? mediaAttachmentRepo as GroupGuardedMediaAttachmentSave
      : null;

  final existingAttachments = await mediaAttachmentRepo
      .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
  final existingIds = existingAttachments
      .map((attachment) => attachment.id)
      .toSet();
  final persistedAttachmentIds = <String>{};
  var hadMissingAttachments = false;

  for (final rawAttachment in media) {
    final attachment =
        GroupMediaMimePolicy.sanitizeWireAttachment(
          rawAttachment,
          messageId: messageId,
        ).copyWith(
          contentHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            _optionalString(rawAttachment, 'contentHash'),
          ),
          thumbnailHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            _optionalString(rawAttachment, 'thumbnailHash'),
          ),
        );
    if (!existingIds.add(attachment.id)) continue;
    hadMissingAttachments = true;
    var committed = false;
    if (guardedRepo != null) {
      committed = await guardedRepo.saveGroupAttachmentGuarded(
        attachment,
        groupId: groupId,
      );
    } else {
      await mediaAttachmentRepo.saveAttachment(
        attachment,
        owner: MediaOwnerLane.group,
      );
      committed = true;
    }
    if (committed) {
      persistedAttachmentIds.add(attachment.id);
    }
  }
  return (
    persistedAttachmentIds: Set<String>.unmodifiable(persistedAttachmentIds),
    hadMissingAttachments: hadMissingAttachments,
  );
}

GroupPrivateMediaEligibility _incomingGroupPrivateMediaEligibility({
  required String text,
  required String? quotedMessageId,
  required bool isForwarded,
  required List<Map<String, dynamic>>? media,
}) {
  final attachments = media ?? const <Map<String, dynamic>>[];
  return GroupPrivateMediaEligibility(
    attachmentCount: attachments.length,
    attachmentKind: attachments.length == 1
        ? _incomingGroupPrivateMediaAttachmentKind(attachments.single)
        : GroupPrivateMediaAttachmentKind.unknown,
    hasTextOrCaption: text.trim().isNotEmpty,
    hasQuote: quotedMessageId?.trim().isNotEmpty == true,
    isForward: isForwarded,
  );
}

GroupPrivateMediaAttachmentKind _incomingGroupPrivateMediaAttachmentKind(
  Map<String, dynamic> attachment,
) {
  final mediaType = attachment['mediaType'] is String
      ? (attachment['mediaType'] as String).trim().toLowerCase()
      : '';
  final mime = attachment['mime'] is String
      ? (attachment['mime'] as String).trim().toLowerCase()
      : '';
  if (mediaType == 'gif' || mime == 'image/gif') {
    return GroupPrivateMediaAttachmentKind.gif;
  }
  if (mediaType == 'image' || mime.startsWith('image/')) {
    return GroupPrivateMediaAttachmentKind.image;
  }
  if (mediaType == 'video' || mime.startsWith('video/')) {
    return GroupPrivateMediaAttachmentKind.video;
  }
  if (mediaType == 'audio' || mime.startsWith('audio/')) {
    return GroupPrivateMediaAttachmentKind.audio;
  }
  if (mediaType == 'file' || mime.isNotEmpty) {
    return GroupPrivateMediaAttachmentKind.file;
  }
  return GroupPrivateMediaAttachmentKind.unknown;
}

Map<String, Object?> _presentGroupPrivateMediaPolicyFields(
  Map<String, Object?> fields,
) {
  final present = <String, Object?>{};
  for (final key in GroupPrivateMediaPolicy.wireKeys) {
    if (fields.containsKey(key)) {
      present[key] = fields[key];
    }
  }
  return present;
}

GroupMediaValidationResult _validateIncomingMediaDescriptors(
  List<Map<String, dynamic>>? media,
) {
  if (media == null || media.isEmpty) {
    return const GroupMediaValidationResult.valid();
  }

  for (final rawAttachment in media) {
    final rawMime = rawAttachment['mime'];
    final rawMediaType = rawAttachment['mediaType'];
    final mime = rawMime is String ? rawMime : null;
    final mediaType = rawMediaType is String ? rawMediaType : null;
    final validation = GroupMediaMimePolicy.validateDescriptor(
      mime: mime,
      mediaType: mediaType,
    );
    if (!validation.isValid) return validation;

    final contentHashValidation = _validateRequiredStringDigestField(
      rawAttachment,
      'contentHash',
      malformedReason: 'malformed_content_hash',
    );
    if (!contentHashValidation.isValid) return contentHashValidation;

    final encryptionKeyValidation = _validateRequiredStringField(
      rawAttachment,
      'encryptionKeyBase64',
      missingReason: 'missing_media_encryption_metadata',
      malformedReason: 'malformed_media_encryption_metadata',
    );
    if (!encryptionKeyValidation.isValid) return encryptionKeyValidation;

    final encryptionNonceValidation = _validateRequiredStringField(
      rawAttachment,
      'encryptionNonce',
      missingReason: 'missing_media_encryption_metadata',
      malformedReason: 'malformed_media_encryption_metadata',
    );
    if (!encryptionNonceValidation.isValid) return encryptionNonceValidation;

    final rawEncryptionScheme = rawAttachment['encryptionScheme'];
    if (rawEncryptionScheme != null &&
        rawEncryptionScheme != kMediaAttachmentEncryptionSchemeBlobAesGcmV1) {
      return const GroupMediaValidationResult.invalid(
        'unsupported_media_encryption_scheme',
      );
    }

    final thumbnailHashValidation = _validateOptionalStringDigestField(
      rawAttachment,
      'thumbnailHash',
      malformedReason: 'malformed_thumbnail_hash',
    );
    if (!thumbnailHashValidation.isValid) return thumbnailHashValidation;
  }

  // Receive side: a permissive cross-type backstop (DoS ceiling), NOT the
  // per-type SEND caps — a compliant sender already gated per-type, and we must
  // not reject media that is legitimately within the cross-type maximum.
  final sizeValidation = GroupMediaSizePolicy.validateRawDescriptors(
    media,
    perMediaLimitBytes: kGroupMediaPerAttachmentLimitBytes,
  );
  if (!sizeValidation.isValid) return sizeValidation;

  return const GroupMediaValidationResult.valid();
}

String? _optionalString(Map<String, dynamic> value, String key) {
  final raw = value[key];
  return raw is String ? raw : null;
}

bool _preferCurrentMemberUsernameAfterReadd({
  required GroupMember? member,
  required DateTime? removalCutoff,
  required DateTime messageTimestamp,
}) {
  if (member == null || removalCutoff == null) {
    return false;
  }
  final memberName = member.username?.trim();
  if (memberName == null || memberName.isEmpty) {
    return false;
  }
  final rejoinedAt = member.joinedAt.toUtc();
  return !rejoinedAt.isBefore(removalCutoff) &&
      !messageTimestamp.isBefore(rejoinedAt);
}

GroupMediaValidationResult _validateRequiredStringDigestField(
  Map<String, dynamic> value,
  String key, {
  required String malformedReason,
}) {
  final raw = value[key];
  if (raw != null && raw is! String) {
    return GroupMediaValidationResult.invalid(malformedReason);
  }
  return GroupMediaIntegrityPolicy.validateRequiredContentHash(raw as String?);
}

GroupMediaValidationResult _validateRequiredStringField(
  Map<String, dynamic> value,
  String key, {
  required String missingReason,
  required String malformedReason,
}) {
  final raw = value[key];
  if (raw == null) {
    return GroupMediaValidationResult.invalid(missingReason);
  }
  if (raw is! String || raw.trim().isEmpty) {
    return GroupMediaValidationResult.invalid(malformedReason);
  }
  return const GroupMediaValidationResult.valid();
}

GroupMediaValidationResult _validateOptionalStringDigestField(
  Map<String, dynamic> value,
  String key, {
  required String malformedReason,
}) {
  final raw = value[key];
  if (raw != null && raw is! String) {
    return GroupMediaValidationResult.invalid(malformedReason);
  }
  return GroupMediaIntegrityPolicy.validateOptionalThumbnailHash(
    raw as String?,
  );
}
