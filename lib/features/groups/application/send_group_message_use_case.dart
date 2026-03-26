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
enum SendGroupMessageResult {
  success,
  groupNotFound,
  unauthorized,
  error,

  /// Publish succeeded but 0 peers were connected to the topic.
  /// The message was stored in the relay inbox as a fallback.
  /// The returned [GroupMessage] has status `'pending'`.
  successNoPeers,
}

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

/// Wraps [callGroupInboxStore] in try/catch — returns true on success.
///
/// Never throws. The caller observes the outcome via the return value.
Future<bool> _tryInboxStore({
  required Bridge bridge,
  required String groupId,
  required String inboxPayload,
  List<String>? recipientPeerIds,
  String? pushTitle,
  String? pushBody,
}) async {
  try {
    await callGroupInboxStore(
      bridge,
      groupId,
      inboxPayload,
      recipientPeerIds: recipientPeerIds,
      pushTitle: pushTitle,
      pushBody: pushBody,
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

/// Sends a message to a group.
///
/// Owns optimistic persistence for ALL production callers:
/// 1. Validates group exists + sender authorized
/// 2. Pre-persists row with status `'sending'` + wireEnvelope + inboxRetryPayload
/// 3. Kicks off publish + inbox store concurrently
/// 4. Reads topicPeers from publish result
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
  String? messageId,
  DateTime? timestamp,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
}) async {
  final sendStopwatch = Stopwatch()..start();
  final sanitizedText = sanitizeMessageText(text);
  final hasMedia = mediaAttachments != null && mediaAttachments.isNotEmpty;
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

  // 3. Prepare all parameters
  final now = timestamp ?? DateTime.now().toUtc();
  final latestKeyFuture = groupRepo.getLatestKey(groupId);
  final recipientPeerIdsFuture = _loadGroupPushRecipients(
    groupRepo: groupRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
  );
  final latestKey = await latestKeyFuture;
  final resolvedMessageId = messageId ?? const Uuid().v4();
  final keyEpoch = latestKey?.keyGeneration ?? 0;

  final mediaJson = mediaAttachments?.map((a) => a.toJson()).toList();
  final recipientPeerIds = await recipientPeerIdsFuture;
  final pushTitle = _buildGroupPushTitle(group);
  final pushBody = _buildGroupPushBody(
    senderUsername: senderUsername,
    text: sanitizedText,
    mediaAttachments: mediaAttachments,
  );

  // 3b. Build wireEnvelope (plaintext publish params for retry — NO senderPrivateKey)
  final wireEnvelope = jsonEncode({
    'groupId': groupId,
    'text': sanitizedText,
    'senderPeerId': senderPeerId,
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
    'senderUsername': senderUsername,
    'keyEpoch': keyEpoch,
    'text': sanitizedText,
    'timestamp': now.toIso8601String(),
    'messageId': resolvedMessageId,
    if (quotedMessageId != null && quotedMessageId.isNotEmpty)
      'quotedMessageId': quotedMessageId,
    if (mediaJson != null && mediaJson.isNotEmpty) 'media': mediaJson,
  });
  final inboxRetryPayload = jsonEncode({
    'groupId': groupId,
    'message': inboxPayload,
    if (recipientPeerIds.isNotEmpty) 'recipientPeerIds': recipientPeerIds,
    if (pushTitle.isNotEmpty) 'pushTitle': pushTitle,
    if (pushBody.isNotEmpty) 'pushBody': pushBody,
  });

  // 4. Pre-persist outgoing row with status 'sending' BEFORE bridge call
  final prePersistMessage = GroupMessage(
    id: resolvedMessageId,
    groupId: groupId,
    senderPeerId: senderPeerId,
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

  // 5. Start publish + inbox store concurrently
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
  final inboxFuture = _tryInboxStore(
    bridge: bridge,
    groupId: groupId,
    inboxPayload: inboxPayload,
    recipientPeerIds: recipientPeerIds.isNotEmpty ? recipientPeerIds : null,
    pushTitle: pushTitle,
    pushBody: pushBody,
  );

  // 6. Await publish — determines success/failure
  Map<String, dynamic>? publishResult;
  bool publishOk = false;

  try {
    publishResult = await publishFuture;
    publishOk = publishResult['ok'] == true;

    if (!publishOk) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_PUBLISH_ERROR',
        details: {'errorCode': publishResult['errorCode']},
      );
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_ERROR',
      details: {'error': e.toString()},
    );
  }

  // 7. Await inbox result
  final inboxOk = await inboxFuture;

  // 8. Apply 4-way result matrix
  if (!publishOk) {
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
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        'inboxOk': inboxOk,
      },
    );
    emitGroupSendTiming(
      outcome: 'publish_failed',
      details: {'inboxStored': inboxOk},
    );
    return (SendGroupMessageResult.error, failedMessage);
  }

  // Publish succeeded — read topicPeers
  final topicPeers = publishResult?.containsKey('topicPeers') == true
      ? publishResult!['topicPeers'] as int?
      : null;

  if (topicPeers == null) {
    // Missing topicPeers key — legacy success (backward compat, assume peers > 0)
    final finalMessage = prePersistMessage.copyWith(
      status: 'sent',
      wireEnvelope: null,
      inboxStored: inboxOk,
      inboxRetryPayload: inboxOk ? null : prePersistMessage.inboxRetryPayload,
    );
    await msgRepo.saveMessage(finalMessage);

    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: mediaAttachments
          ?.map(
            (attachment) => attachment.copyWith(messageId: resolvedMessageId),
          )
          .toList(growable: false),
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        'legacy': true,
      },
    );
    emitGroupSendTiming(
      outcome: 'success',
      details: {'status': finalMessage.status, 'legacy': true},
    );
    return (SendGroupMessageResult.success, finalMessage);
  }

  if (topicPeers > 0) {
    // Normal success: peers > 0
    final finalMessage = prePersistMessage.copyWith(
      status: 'sent',
      wireEnvelope: null,
      inboxStored: inboxOk,
      inboxRetryPayload: inboxOk ? null : prePersistMessage.inboxRetryPayload,
    );
    await msgRepo.saveMessage(finalMessage);

    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: mediaAttachments
          ?.map(
            (attachment) => attachment.copyWith(messageId: resolvedMessageId),
          )
          .toList(growable: false),
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        'topicPeers': topicPeers,
        'inboxOk': inboxOk,
      },
    );
    emitGroupSendTiming(
      outcome: 'success',
      details: {
        'status': finalMessage.status,
        'topicPeers': topicPeers,
        'inboxStored': inboxOk,
      },
    );
    return (SendGroupMessageResult.success, finalMessage);
  }

  // topicPeers == 0
  if (inboxOk) {
    // 0-peer + inbox OK → successNoPeers, status 'pending'
    final pendingMessage = prePersistMessage.copyWith(
      status: 'pending',
      wireEnvelope: null,
      inboxStored: true,
      inboxRetryPayload: null,
    );
    await msgRepo.saveMessage(pendingMessage);

    // Save media attachments
    if (mediaAttachments != null && mediaAttachmentRepo != null) {
      for (final a in mediaAttachments) {
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
      },
    );
    emitGroupSendTiming(
      outcome: 'success_no_peers',
      details: {'status': pendingMessage.status, 'topicPeers': 0},
    );
    return (SendGroupMessageResult.successNoPeers, pendingMessage);
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
      },
    );
    emitGroupSendTiming(
      outcome: 'zero_peers_inbox_failed',
      details: {'topicPeers': 0},
    );
    return (SendGroupMessageResult.error, failedMessage);
  }
}
