import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Result of sending a group message.
enum SendGroupMessageResult { success, groupNotFound, unauthorized, error }

String _buildGroupPushTitle(GroupModel group) => group.name;

String _buildGroupPushBody({
  required String senderUsername,
  required String text,
  List<MediaAttachment>? mediaAttachments,
}) {
  final trimmedText = text.trim();
  if (trimmedText.isNotEmpty) {
    return '$senderUsername: $trimmedText';
  }

  final primaryType = mediaAttachments != null && mediaAttachments.isNotEmpty
      ? mediaAttachments.first.mediaType
      : null;
  final descriptor = switch (primaryType) {
    'audio' => 'a voice message',
    'image' => 'a photo',
    'video' => 'a video',
    'file' => 'an attachment',
    _ => 'an attachment',
  };
  return '$senderUsername sent $descriptor';
}

Future<List<String>> _loadGroupPushRecipients({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderPeerId,
}) async {
  final members = await groupRepo.getMembers(groupId);
  return members
      .map((member) => member.peerId)
      .where((peerId) => peerId.isNotEmpty && peerId != senderPeerId)
      .toSet()
      .toList();
}

/// Sends a message to a group.
///
/// Verifies the group exists and the sender has write permission.
/// Publishes via the bridge and saves locally.
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
  String? messageId,
  DateTime? timestamp,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  final sanitizedText = sanitizeMessageText(text);
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
    return (SendGroupMessageResult.groupNotFound, null);
  }

  // 2. Check role authorization (announcement: only admin can send)
  if (group.type == GroupType.announcement && group.myRole != GroupRole.admin) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNAUTHORIZED',
      details: {'type': group.type.toValue(), 'role': group.myRole.toValue()},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }

  // 2b. Reject empty messages (no text and no media)
  final hasMedia = mediaAttachments != null && mediaAttachments.isNotEmpty;
  if (sanitizedText.trim().isEmpty && !hasMedia) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_EMPTY',
      details: {},
    );
    return (SendGroupMessageResult.error, null);
  }

  // 3. Publish + inbox store run concurrently (independent operations)
  final now = timestamp ?? DateTime.now().toUtc();
  final latestKey = await groupRepo.getLatestKey(groupId);
  final resolvedMessageId = messageId ?? const Uuid().v4();

  final mediaJson = mediaAttachments?.map((a) => a.toJson()).toList();
  final recipientPeerIds = await _loadGroupPushRecipients(
    groupRepo: groupRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
  );
  final pushTitle = _buildGroupPushTitle(group);
  final pushBody = _buildGroupPushBody(
    senderUsername: senderUsername,
    text: sanitizedText,
    mediaAttachments: mediaAttachments,
  );

  // Start both operations concurrently
  final publishFuture = callGroupPublish(
    bridge,
    groupId: groupId,
    text: sanitizedText,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    senderUsername: senderUsername,
    messageId: resolvedMessageId,
    quotedMessageId: quotedMessageId,
    media: mediaJson,
  );
  final inboxFuture = _safeInboxStore(
    bridge: bridge,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    keyEpoch: latestKey?.keyGeneration ?? 0,
    text: sanitizedText,
    timestamp: now,
    messageId: resolvedMessageId,
    quotedMessageId: quotedMessageId,
    media: mediaJson,
    recipientPeerIds: recipientPeerIds,
    pushTitle: pushTitle,
    pushBody: pushBody,
  );

  // Await publish — determines success/failure
  try {
    final result = await publishFuture;

    if (result['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_PUBLISH_ERROR',
        details: {'errorCode': result['errorCode']},
      );
      await inboxFuture;
      return (SendGroupMessageResult.error, null);
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_ERROR',
      details: {'error': e.toString()},
    );
    await inboxFuture;
    return (SendGroupMessageResult.error, null);
  }

  // Await inbox store (already completed or nearly done)
  await inboxFuture;

  // 5. Create GroupMessage (isIncoming: false, status: 'sent')
  final message = GroupMessage(
    id: resolvedMessageId,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    text: sanitizedText,
    timestamp: now,
    quotedMessageId: quotedMessageId,
    keyGeneration: latestKey?.keyGeneration ?? 0,
    status: 'sent',
    isIncoming: false,
    createdAt: now,
  );

  // 6. Save to repo
  await msgRepo.saveMessage(message);

  // 7. Save media attachments with resolved messageId
  if (mediaAttachments != null && mediaAttachmentRepo != null) {
    for (final a in mediaAttachments) {
      await mediaAttachmentRepo.saveAttachment(
        a.copyWith(messageId: resolvedMessageId),
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
    details: {
      'messageId': resolvedMessageId.length > 8
          ? resolvedMessageId.substring(0, 8)
          : resolvedMessageId,
    },
  );

  return (SendGroupMessageResult.success, message);
}

/// Wraps [callGroupInboxStore] in try/catch so failures don't propagate.
Future<void> _safeInboxStore({
  required Bridge bridge,
  required String groupId,
  required String senderPeerId,
  required String senderUsername,
  required int keyEpoch,
  required String text,
  required DateTime timestamp,
  required String messageId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  List<String>? recipientPeerIds,
  String? pushTitle,
  String? pushBody,
}) async {
  try {
    final inboxPayload = jsonEncode({
      'groupId': groupId,
      'senderId': senderPeerId,
      'senderUsername': senderUsername,
      'keyEpoch': keyEpoch,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'messageId': messageId,
      if (quotedMessageId != null && quotedMessageId.isNotEmpty)
        'quotedMessageId': quotedMessageId,
      if (media != null && media.isNotEmpty) 'media': media,
    });
    await callGroupInboxStore(
      bridge,
      groupId,
      inboxPayload,
      recipientPeerIds: recipientPeerIds,
      pushTitle: pushTitle,
      pushBody: pushBody,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_INBOX_STORE_FAILED',
      details: {'error': e.toString()},
    );
  }
}
