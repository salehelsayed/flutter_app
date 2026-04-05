import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

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
  String? messageId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
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

  // Prefer messageId-based dedupe before any group/member lookups. Replay
  // batches can contain large numbers of already-processed messages, and we do
  // not need to re-check membership or group state just to ignore a duplicate.
  if (messageId != null && messageId.isNotEmpty) {
    final existsById = await msgRepo.existsByMessageId(messageId);
    if (existsById) {
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

  DateTime parsedTimestamp;
  try {
    parsedTimestamp = DateTime.parse(timestamp);
  } catch (_) {
    parsedTimestamp = now;
  }
  final normalizedTimestamp = parsedTimestamp.toUtc();

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

  // 2. Check sender is a member (optional: allow messages from non-members
  //    in case member list is stale; log a warning)
  final member = await groupRepo.getMember(groupId, senderId);
  if (member == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_UNKNOWN_SENDER',
      details: {
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      },
    );

    final removalCutoff = await msgRepo.getLatestRemovalTimestampForSender(
      groupId,
      senderId,
    );
    if (removalCutoff != null && !normalizedTimestamp.isBefore(removalCutoff)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'cutoffAt': removalCutoff.toIso8601String(),
        },
      );
      return null;
    }

    // Still process the message — member list may be stale or the message
    // crossed the accepted removal boundary before the persisted cutoff.
  }

  // Fallback: content-based dedupe for messages without a messageId.
  final isDuplicate = await msgRepo.existsByContent(
    groupId,
    senderId,
    sanitizedText,
    parsedTimestamp,
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
  final isSelfDelivery = selfPeerId != null && senderId == selfPeerId;

  // 5. Create GroupMessage (isIncoming: true)
  final message = GroupMessage(
    id: resolvedMessageId,
    groupId: groupId,
    senderPeerId: senderId,
    senderUsername: senderUsername,
    text: sanitizedText,
    timestamp: parsedTimestamp,
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
    final attachment = MediaAttachment.fromJson(
      rawAttachment,
    ).copyWith(messageId: messageId);
    if (!existingIds.add(attachment.id)) continue;
    await mediaAttachmentRepo.saveAttachment(attachment);
  }
}
