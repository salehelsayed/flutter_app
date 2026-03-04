import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Drains offline inboxes for all active groups on startup.
///
/// For each active group, retrieves stored messages from the relay inbox
/// and processes them as incoming messages. Errors per-group are logged
/// and do not prevent other groups from being drained.
Future<void> drainGroupOfflineInbox({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_BEGIN',
    details: {},
  );

  final groups = await groupRepo.getActiveGroups();

  for (final group in groups) {
    try {
      final messages = await callGroupInboxRetrieve(bridge, group.id, 0);

      for (final msg in messages) {
        // The relay returns {from, message, timestamp} where `message`
        // is a JSON-encoded string with the actual message payload.
        final payload = _decodeInboxMessage(msg, group.id);
        final mediaRaw = payload['media'] as List<dynamic>?;
        final media = mediaRaw?.cast<Map<String, dynamic>>();

        await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: payload['groupId'] as String? ?? group.id,
          senderId: payload['senderId'] as String? ?? '',
          senderUsername: payload['senderUsername'] as String? ?? '',
          keyEpoch: payload['keyEpoch'] as int? ?? 0,
          text: payload['text'] as String? ?? '',
          timestamp: payload['timestamp'] as String? ??
              DateTime.now().toUtc().toIso8601String(),
          media: media,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE',
        details: {
          'groupId':
              group.id.length > 8 ? group.id.substring(0, 8) : group.id,
          'messageCount': messages.length,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_ERROR',
        details: {
          'groupId':
              group.id.length > 8 ? group.id.substring(0, 8) : group.id,
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

/// Decodes an inbox message from the relay's envelope format.
///
/// The relay returns `{from, message, timestamp}` where `message` is a
/// JSON-encoded string containing the actual payload fields (groupId,
/// senderId, senderUsername, keyEpoch, text, timestamp). If `message`
/// is not a valid JSON string, falls back to the raw envelope.
Map<String, dynamic> _decodeInboxMessage(
    Map<String, dynamic> envelope, String fallbackGroupId) {
  final messageStr = envelope['message'];
  if (messageStr is String && messageStr.isNotEmpty) {
    try {
      return jsonDecode(messageStr) as Map<String, dynamic>;
    } catch (_) {
      // Not valid JSON — fall through to use envelope directly
    }
  }
  // Fallback: map envelope fields to expected fields
  return {
    'groupId': fallbackGroupId,
    'senderId': envelope['from'] as String? ?? '',
    'senderUsername': '',
    'keyEpoch': 0,
    'text': messageStr?.toString() ?? '',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };
}
