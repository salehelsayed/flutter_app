import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';

/// Retries inbox store for outgoing group messages where the initial
/// inbox store failed.
///
/// Queries rows where:
///   - `is_incoming = 0`
///   - `status IN ('sent', 'pending')`
///   - `inbox_stored = 0`
///   - `inbox_retry_payload IS NOT NULL`
///
/// For each, reconstructs the inbox store call from persisted JSON payload,
/// calls `callGroupInboxStore`, and closes the row as fully sent on success.
///
/// Returns the number of successfully retried messages.
Future<int> retryFailedGroupInboxStores({
  required Bridge bridge,
  required GroupMessageRepository msgRepo,
  int limit = 20,
}) async {
  final retryStopwatch = Stopwatch()..start();
  void emitRetryTiming({
    required String outcome,
    required int total,
    required int retried,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_INBOX_STORES_TIMING',
      details: {
        'elapsedMs': retryStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'total': total,
        'retried': retried,
        'limit': limit,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_GROUP_INBOX_STORES_BEGIN',
    details: {'limit': limit},
  );

  final messages = await msgRepo.getMessagesWithFailedInboxStore(limit: limit);
  if (messages.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_INBOX_STORES_NONE',
      details: {},
    );
    emitRetryTiming(outcome: 'none', total: 0, retried: 0);
    return 0;
  }

  int retriedCount = 0;

  for (final msg in messages) {
    try {
      final retryPayload =
          jsonDecode(msg.inboxRetryPayload!) as Map<String, dynamic>;
      final groupId = retryPayload['groupId'] as String;
      final inboxMessage = retryPayload['message'] as String;
      final recipientPeerIds =
          (retryPayload['recipientPeerIds'] as List<dynamic>?)?.cast<String>();
      final pushTitle = retryPayload['pushTitle'] as String?;
      final pushBody = retryPayload['pushBody'] as String?;

      await callGroupInboxStore(
        bridge,
        groupId,
        inboxMessage,
        recipientPeerIds: recipientPeerIds,
        pushTitle: pushTitle,
        pushBody: pushBody,
      );

      await msgRepo.updateInboxStored(msg.id, stored: true);
      await msgRepo.updateInboxRetryPayload(msg.id, null);
      await msgRepo.updateMessageStatus(msg.id, 'sent');
      retriedCount++;

      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_INBOX_STORE_OK',
        details: {
          'messageId': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_INBOX_STORE_ERROR',
        details: {
          'messageId': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
          'error': e.toString(),
        },
      );
      // Non-fatal: continue to next message
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_GROUP_INBOX_STORES_DONE',
    details: {'retried': retriedCount, 'total': messages.length},
  );
  emitRetryTiming(
    outcome: 'complete',
    total: messages.length,
    retried: retriedCount,
  );

  return retriedCount;
}
