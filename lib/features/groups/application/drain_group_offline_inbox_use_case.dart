import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Drains offline inboxes for all groups on startup.
///
/// For each group, retrieves stored messages from the relay inbox
/// and processes them as incoming messages. Uses cursor-based pagination
/// to ensure exactly-once delivery across pages. Groups are drained in
/// parallel so one slow relay request does not serially stall every other
/// group on startup or resume.
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
  GroupMessageListener? groupMessageListener,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  final drainStopwatch = Stopwatch()..start();
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_BEGIN',
    details: {},
  );

  final groups = await groupRepo.getAllGroups();

  await Future.wait(
    groups.map((group) async {
      final groupStopwatch = Stopwatch()..start();
      try {
        await _drainGroupInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: group.id,
          mediaAttachmentRepo: mediaAttachmentRepo,
          reactionRepo: reactionRepo,
          groupMessageListener: groupMessageListener,
          drainAllPages: drainAllPages,
          pageSize: pageSize,
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_ERROR',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
            'error': e.toString(),
          },
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
          details: {
            'scope': 'group',
            'elapsedMs': groupStopwatch.elapsedMilliseconds,
            'outcome': 'error',
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
          },
        );
      }
    }),
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_DONE',
    details: {'groupCount': groups.length},
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
    details: {
      'scope': 'batch',
      'elapsedMs': drainStopwatch.elapsedMilliseconds,
      'outcome': 'complete',
      'groupCount': groups.length,
      'drainAllPages': drainAllPages,
      'pageSize': pageSize,
    },
  );
}

Future<void> drainGroupOfflineInboxForGroup({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  GroupMessageListener? groupMessageListener,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  final drainStopwatch = Stopwatch()..start();
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_SINGLE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    await _drainGroupInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: groupId,
      mediaAttachmentRepo: mediaAttachmentRepo,
      reactionRepo: reactionRepo,
      groupMessageListener: groupMessageListener,
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
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
      details: {
        'scope': 'single',
        'elapsedMs': drainStopwatch.elapsedMilliseconds,
        'outcome': 'complete',
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'drainAllPages': drainAllPages,
        'pageSize': pageSize,
      },
    );
  } catch (_) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
      details: {
        'scope': 'single',
        'elapsedMs': drainStopwatch.elapsedMilliseconds,
        'outcome': 'error',
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    rethrow;
  }
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
  GroupMessageListener? groupMessageListener,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  final drainStopwatch = Stopwatch()..start();
  final retentionCutoff = groupBacklogRetentionCutoff(DateTime.now().toUtc());
  String cursor = '';
  int totalMessages = 0;
  var pageCount = 0;
  DateTime? latestExpiredBacklogAt;
  DateTime? latestRetainedBacklogAt;
  var sawTimestampedRetentionPayload = false;

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
      Map<String, dynamic> payload;
      try {
        payload = await decodeInboxMessage(bridge, groupRepo, msg, groupId);
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'error': e.toString(),
          },
        );
        continue;
      }
      final text = payload['text'] as String? ?? '';
      final timestamp =
          payload['timestamp'] as String? ??
          DateTime.now().toUtc().toIso8601String();
      final parsedTimestamp = _tryParseUtcTimestamp(timestamp);
      final isSystemPayload = text.startsWith('{"__sys":');

      if (!isSystemPayload && parsedTimestamp != null) {
        sawTimestampedRetentionPayload = true;
        if (parsedTimestamp.isBefore(retentionCutoff)) {
          latestExpiredBacklogAt = _latestTimestamp(
            latestExpiredBacklogAt,
            parsedTimestamp,
          );
          continue;
        }
        latestRetainedBacklogAt = _latestTimestamp(
          latestRetainedBacklogAt,
          parsedTimestamp,
        );
      }

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
      final resolvedGroupId = payload['groupId'] as String? ?? groupId;
      final senderId =
          payload['senderId'] as String? ?? (msg['from'] as String? ?? '');
      final senderUsername = payload['senderUsername'] as String? ?? '';
      final keyEpoch = payload['keyEpoch'] as int? ?? 0;

      if (groupMessageListener != null && text.startsWith('{"__sys":')) {
        await groupMessageListener.handleReplayEnvelope({
          'groupId': resolvedGroupId,
          'senderId': senderId,
          'senderUsername': senderUsername,
          'keyEpoch': keyEpoch,
          'text': text,
          'timestamp': timestamp,
          if (payload['messageId'] is String) 'messageId': payload['messageId'],
          if (payload['quotedMessageId'] is String)
            'quotedMessageId': payload['quotedMessageId'],
          if (media != null) 'media': media,
        });

        if (await groupRepo.getGroup(resolvedGroupId) == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_DRAIN_OFFLINE_INBOX_STOP_GROUP_REMOVED',
            details: {
              'groupId': resolvedGroupId.length > 8
                  ? resolvedGroupId.substring(0, 8)
                  : resolvedGroupId,
            },
          );
          return;
        }
        continue;
      }

      if (groupMessageListener != null) {
        await groupMessageListener.handleReplayEnvelope({
          'groupId': resolvedGroupId,
          'senderId': senderId,
          'senderUsername': senderUsername,
          'keyEpoch': keyEpoch,
          'text': text,
          'timestamp': timestamp,
          if (payload['messageId'] is String) 'messageId': payload['messageId'],
          if (payload['quotedMessageId'] is String)
            'quotedMessageId': payload['quotedMessageId'],
          if (media != null) 'media': media,
        });
        continue;
      }

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: resolvedGroupId,
        senderId: senderId,
        senderUsername: senderUsername,
        keyEpoch: keyEpoch,
        text: text,
        timestamp: timestamp,
        messageId: payload['messageId'] as String?,
        quotedMessageId: payload['quotedMessageId'] as String?,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
    }

    totalMessages += messages.length;
    pageCount++;
    cursor = nextCursor;

    // If caller only wants the first page, stop here.
    if (!drainAllPages && cursor.isNotEmpty) {
      await _persistRetentionState(
        groupRepo: groupRepo,
        groupId: groupId,
        sawTimestampedRetentionPayload: sawTimestampedRetentionPayload,
        latestExpiredBacklogAt: latestExpiredBacklogAt,
        latestRetainedBacklogAt: latestRetainedBacklogAt,
      );
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
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
        details: {
          'scope': 'group',
          'elapsedMs': drainStopwatch.elapsedMilliseconds,
          'outcome': 'first_page_complete',
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'messageCount': totalMessages,
          'pageCount': pageCount,
          'drainAllPages': false,
        },
      );
      return;
    }
  } while (cursor.isNotEmpty);

  await _persistRetentionState(
    groupRepo: groupRepo,
    groupId: groupId,
    sawTimestampedRetentionPayload: sawTimestampedRetentionPayload,
    latestExpiredBacklogAt: latestExpiredBacklogAt,
    latestRetainedBacklogAt: latestRetainedBacklogAt,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'messageCount': totalMessages,
    },
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
    details: {
      'scope': 'group',
      'elapsedMs': drainStopwatch.elapsedMilliseconds,
      'outcome': 'complete',
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'messageCount': totalMessages,
      'pageCount': pageCount,
      'drainAllPages': drainAllPages,
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
Future<Map<String, dynamic>> decodeInboxMessage(
  Bridge bridge,
  GroupRepository groupRepo,
  Map<String, dynamic> envelope,
  String fallbackGroupId,
) async {
  // If the envelope contains a `message` string, decode it.
  final messageStr = envelope['message'];
  if (messageStr is String && messageStr.isNotEmpty) {
    Map<String, dynamic>? decodedMessage;
    try {
      final decoded = jsonDecode(messageStr);
      if (decoded is Map) {
        decodedMessage = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      decodedMessage = null;
    }

    if (decodedMessage != null) {
      if (isGroupOfflineReplayEnvelope(decodedMessage)) {
        final payloadType =
            decodedMessage['payloadType'] as String? ??
            groupOfflineReplayPayloadTypeMessage;
        final plaintext = await decryptGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: fallbackGroupId,
          envelope: decodedMessage,
        );

        if (payloadType == groupOfflineReplayPayloadTypeReaction) {
          return {
            'type': groupOfflineReplayPayloadTypeReaction,
            'reaction': plaintext,
          };
        }

        return Map<String, dynamic>.from(
          jsonDecode(plaintext) as Map<String, dynamic>,
        );
      }

      return decodedMessage;
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

Future<void> _persistRetentionState({
  required GroupRepository groupRepo,
  required String groupId,
  required bool sawTimestampedRetentionPayload,
  required DateTime? latestExpiredBacklogAt,
  required DateTime? latestRetainedBacklogAt,
}) async {
  if (!sawTimestampedRetentionPayload) return;

  final group = await groupRepo.getGroup(groupId);
  if (group == null) return;

  await groupRepo.updateGroup(
    group.copyWith(
      lastBacklogExpiredAt: latestExpiredBacklogAt,
      lastBacklogRetainedAt: latestRetainedBacklogAt,
    ),
  );
}

DateTime? _tryParseUtcTimestamp(String rawTimestamp) {
  try {
    return DateTime.parse(rawTimestamp).toUtc();
  } catch (_) {
    return null;
  }
}

DateTime? _latestTimestamp(DateTime? current, DateTime candidate) {
  if (current == null || candidate.isAfter(current)) {
    return candidate;
  }
  return current;
}
