import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Drains offline inboxes for all groups on startup.
///
/// For each group, retrieves stored messages from the relay inbox
/// and processes them as incoming messages. Uses cursor-based pagination
/// to ensure exactly-once delivery across pages. Errors per-group are
/// logged and do not prevent other groups from being drained.
///
/// The first page is fetched synchronously (on the resume budget).
/// If [drainAllPages] is true (default), remaining pages are fetched
/// in the same call. Callers can set it to false and use
/// [drainGroupOfflineInboxContinuation] for background continuation.
Future<void> drainGroupOfflineInbox({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_BEGIN',
    details: {},
  );

  final groups = await groupRepo.getAllGroups();

  for (final group in groups) {
    try {
      await _drainGroupInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: group.id,
        mediaAttachmentRepo: mediaAttachmentRepo,
        reactionRepo: reactionRepo,
        drainAllPages: drainAllPages,
        pageSize: pageSize,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_ERROR',
        details: {
          'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
          'error': e.toString(),
        },
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_DONE',
    details: {'groupCount': groups.length},
  );
}

Future<void> drainGroupOfflineInboxForGroup({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_SINGLE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  await _drainGroupInbox(
    bridge: bridge,
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    groupId: groupId,
    mediaAttachmentRepo: mediaAttachmentRepo,
    reactionRepo: reactionRepo,
    drainAllPages: drainAllPages,
    pageSize: pageSize,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_SINGLE_DONE',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );
}

/// Drains a single group's offline inbox using cursor-based pagination.
///
/// If a cursor is returned by the bridge, fetches subsequent pages until
/// no more messages are available (or [drainAllPages] is false for the
/// first-page-only path).
Future<void> _drainGroupInbox({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  String cursor = '';
  int totalMessages = 0;

  do {
    final result = await callGroupInboxRetrieveWithCursor(
      bridge,
      groupId,
      cursor,
      pageSize,
    );

    final messages = result.messages;
    final nextCursor = result.cursor;

    for (final msg in messages) {
      final payload = decodeInboxMessage(msg, groupId);

      // Route by type: group_reaction payloads are handled separately.
      if (payload['type'] == 'group_reaction' && reactionRepo != null) {
        final reactionJson = payload['reaction'] as String? ?? '';
        if (reactionJson.isNotEmpty) {
          await handleIncomingGroupReaction(
            groupRepo: groupRepo,
            reactionRepo: reactionRepo,
            groupId: groupId,
            senderId:
                payload['senderId'] as String? ??
                (msg['from'] as String? ?? ''),
            reactionJson: reactionJson,
          );
        }
        continue;
      }

      final mediaRaw = payload['media'] as List<dynamic>?;
      final media = mediaRaw?.cast<Map<String, dynamic>>();

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: payload['groupId'] as String? ?? groupId,
        senderId: payload['senderId'] as String? ?? '',
        senderUsername: payload['senderUsername'] as String? ?? '',
        keyEpoch: payload['keyEpoch'] as int? ?? 0,
        text: payload['text'] as String? ?? '',
        timestamp:
            payload['timestamp'] as String? ??
            DateTime.now().toUtc().toIso8601String(),
        messageId: payload['messageId'] as String?,
        quotedMessageId: payload['quotedMessageId'] as String?,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
    }

    totalMessages += messages.length;
    cursor = nextCursor;

    // If caller only wants the first page, stop here.
    if (!drainAllPages && cursor.isNotEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DRAIN_OFFLINE_INBOX_FIRST_PAGE_DONE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'messageCount': totalMessages,
          'hasMore': true,
          'nextCursor': cursor.length > 8 ? cursor.substring(0, 8) : cursor,
        },
      );
      return;
    }
  } while (cursor.isNotEmpty);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'messageCount': totalMessages,
    },
  );
}

/// Decodes an inbox message from the relay's envelope format.
///
/// The relay returns `{from, message, timestamp}` where `message` is a
/// JSON-encoded string containing the actual payload fields (groupId,
/// senderId, senderUsername, keyEpoch, text, timestamp). If `message`
/// is not a valid JSON string, falls back to the raw envelope.
///
/// Also handles the case where the map IS the payload directly (has
/// `senderId` key), which happens when the bridge returns pre-decoded
/// messages or in test scenarios.
Map<String, dynamic> decodeInboxMessage(
  Map<String, dynamic> envelope,
  String fallbackGroupId,
) {
  // If the envelope contains a `message` string, decode it.
  final messageStr = envelope['message'];
  if (messageStr is String && messageStr.isNotEmpty) {
    try {
      return jsonDecode(messageStr) as Map<String, dynamic>;
    } catch (_) {
      // Not valid JSON — fall through
    }
  }

  // If the map already looks like a decoded payload (has senderId),
  // return it as-is.
  if (envelope.containsKey('senderId')) {
    return envelope;
  }

  // Fallback: map relay envelope fields to expected fields.
  return {
    'groupId': fallbackGroupId,
    'senderId': envelope['from'] as String? ?? '',
    'senderUsername': '',
    'keyEpoch': 0,
    'text': messageStr?.toString() ?? '',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };
}
