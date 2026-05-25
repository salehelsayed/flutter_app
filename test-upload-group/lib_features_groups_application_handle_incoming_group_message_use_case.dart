import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_sender_display_name.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const _maxIncomingMessageFutureClockSkew = Duration(minutes: 5);

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
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
  AppendGroupEventLogEntry? appendGroupEventLogEntry,
  bool enforceSelfJoinedAtLowerBound = false,
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
  final mediaValidation = _validateIncomingMediaDescriptors(media);
  if (!mediaValidation.isValid) {
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
    return null;
  }

  // Prefer messageId-based dedupe before any group/member lookups when event-log
  // tamper gating is not installed. If DB-002 logging is installed, the log
  // checks replay/tamper before dedupe can silently ignore a changed duplicate.
  if (appendGroupEventLogEntry == null &&
      messageId != null &&
      messageId.isNotEmpty) {
    final existingById = await msgRepo.getMessage(messageId);
    if (existingById != null &&
        _isConflictingDuplicateMessageId(
          existing: existingById,
          groupId: groupId,
          senderId: senderId,
        )) {
      _emitDuplicateMessageIdConflictRejected(
        messageId: messageId,
        groupId: groupId,
        existing: existingById,
        senderId: senderId,
      );
      return null;
    }
    if (existingById != null && !_isRepairPlaceholder(existingById)) {
      final reconciledSelfEcho = await _reconcileOutgoingSelfEchoDuplicate(
        msgRepo: msgRepo,
        existing: existingById,
        messageId: messageId,
        groupId: groupId,
        senderId: senderId,
        resolvedTransportPeerId: resolvedTransportPeerId,
        sanitizedText: sanitizedText,
        selfPeerId: selfPeerId,
        quotedMessageId: quotedMessageId,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      if (reconciledSelfEcho != null) {
        return reconciledSelfEcho;
      }
      await _enrichExistingDuplicateMessage(
        msgRepo: msgRepo,
        messageId: messageId,
        quotedMessageId: quotedMessageId,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'dedupeBy': 'messageId',
        },
      );
      return null;
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
    return null;
  }

  // Parse timestamp before applying membership-boundary checks.
  final now = DateTime.now().toUtc();

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
    return null;
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
      return null;
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
        return null;
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
      return null;
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
      return null;
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
      return null;
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
    return null;
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
      return null;
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
        return null;
      }
    }
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
      return null;
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
    final sourceEventId = messageId != null && messageId.isNotEmpty
        ? messageId
        : 'message:$groupId:$senderId:${normalizedTimestamp.toIso8601String()}:$sanitizedText';
    await appendGroupEventLogEntry(
      groupId: groupId,
      eventType: 'message',
      sourcePeerId: senderId,
      sourceEventId: sourceEventId,
      sourceTimestamp: normalizedTimestamp.toIso8601String(),
      payload: {
        'messageId': messageId,
        'groupId': groupId,
        'senderId': senderId,
        'senderUsername': resolvedSenderUsername,
        'transportPeerId': resolvedTransportPeerId,
        'senderDeviceId': senderDeviceId,
        'text': sanitizedText,
        'timestamp': normalizedTimestamp.toIso8601String(),
        'keyEpoch': keyEpoch,
        'quotedMessageId': quotedMessageId,
        'media': media ?? const <Map<String, dynamic>>[],
      },
    );
  }

  if (messageId != null && messageId.isNotEmpty) {
    final existingById = await msgRepo.getMessage(messageId);
    if (existingById != null &&
        _isConflictingDuplicateMessageId(
          existing: existingById,
          groupId: groupId,
          senderId: senderId,
        )) {
      _emitDuplicateMessageIdConflictRejected(
        messageId: messageId,
        groupId: groupId,
        existing: existingById,
        senderId: senderId,
      );
      return null;
    }
    if (existingById != null && !_isRepairPlaceholder(existingById)) {
      final reconciledSelfEcho = await _reconcileOutgoingSelfEchoDuplicate(
        msgRepo: msgRepo,
        existing: existingById,
        messageId: messageId,
        groupId: groupId,
        senderId: senderId,
        resolvedTransportPeerId: resolvedTransportPeerId,
        sanitizedText: sanitizedText,
        selfPeerId: selfPeerId,
        quotedMessageId: quotedMessageId,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      if (reconciledSelfEcho != null) {
        return reconciledSelfEcho;
      }
      await _enrichExistingDuplicateMessage(
        msgRepo: msgRepo,
        messageId: messageId,
        quotedMessageId: quotedMessageId,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'dedupeBy': 'messageId',
        },
      );
      return null;
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
  final isDuplicate = await msgRepo.existsByContent(
    groupId,
    senderId,
    sanitizedText,
    normalizedTimestamp,
  );
  if (isDuplicate) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        'dedupeBy': 'content',
      },
    );
    return null;
  }

  // 4. Use wire messageId if provided, otherwise generate one
  final resolvedMessageId = (messageId != null && messageId.isNotEmpty)
      ? messageId
      : const Uuid().v4();
  final isSelfDelivery = _isLocalSelfDelivery(
    senderId: senderId,
    senderTransportPeerId: resolvedTransportPeerId,
    localRecipientPeerId: localRecipientPeerId,
    localRecipientAccountPeerId: localRecipientAccountPeerId,
  );

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
    keyGeneration: keyEpoch,
    status: isSelfDelivery ? 'sent' : 'delivered',
    isIncoming: !isSelfDelivery,
    createdAt: now,
  );

  // 6. Save to repo
  await msgRepo.saveMessage(message);

  // 7. Save media attachments (pending for relay download)
  await _saveIncomingMediaAttachments(
    messageId: resolvedMessageId,
    media: media,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
    details: {
      'messageId': resolvedMessageId.length > 8
          ? resolvedMessageId.substring(0, 8)
          : resolvedMessageId,
    },
  );

  return message;
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
}) {
  return existing.groupId != groupId || existing.senderPeerId != senderId;
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
      (existing.transportPeerId?.isNotEmpty == true &&
          existing.transportPeerId != resolvedTransportPeerId) ||
      existing.isIncoming) {
    return null;
  }
  if (existing.status != 'sending' && existing.status != 'pending') {
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

Future<void> _enrichExistingDuplicateMessage({
  required GroupMessageRepository msgRepo,
  required String messageId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  final existing = await msgRepo.getMessage(messageId);
  if (existing != null &&
      (existing.quotedMessageId == null || existing.quotedMessageId!.isEmpty) &&
      quotedMessageId != null &&
      quotedMessageId.isNotEmpty) {
    await msgRepo.saveMessage(
      existing.copyWith(quotedMessageId: quotedMessageId),
    );
  }

  await _saveIncomingMediaAttachments(
    messageId: messageId,
    media: media,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );
}

Future<void> _saveIncomingMediaAttachments({
  required String messageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (media == null || mediaAttachmentRepo == null) return;

  final existingAttachments = await mediaAttachmentRepo
      .getAttachmentsForMessage(messageId);
  final existingIds = existingAttachments
      .map((attachment) => attachment.id)
      .toSet();

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
    await mediaAttachmentRepo.saveAttachment(attachment);
  }
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

  final sizeValidation = GroupMediaSizePolicy.validateRawDescriptors(media);
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
