import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';

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
/// When [reactionReplayOutboxRepo] is provided, the same retry pass also
/// drains retryable sender-owned reaction replay rows after message rows.
///
/// Returns the number of successfully retried entries across both owners.
Future<int> retryFailedGroupInboxStores({
  required Bridge bridge,
  required GroupMessageRepository msgRepo,
  GroupReactionReplayOutboxRepository? reactionReplayOutboxRepo,
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
  final remainingReactionSlots = limit - messages.length;
  final reactionEntries =
      reactionReplayOutboxRepo == null || remainingReactionSlots <= 0
      ? const <GroupReactionReplayOutboxEntry>[]
      : await reactionReplayOutboxRepo.loadRetryableEntries(
          limit: remainingReactionSlots,
        );

  if (messages.isEmpty && reactionEntries.isEmpty) {
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
      await storeGroupOfflineReplayFromRetryPayload(
        bridge: bridge,
        inboxRetryPayload: msg.inboxRetryPayload!,
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

  for (final entry in reactionEntries) {
    try {
      await storeGroupOfflineReplayFromRetryPayload(
        bridge: bridge,
        inboxRetryPayload: entry.inboxRetryPayload,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_REACTION_REPLAY_ERROR',
        details: {
          'reactionId': entry.reactionId.length > 8
              ? entry.reactionId.substring(0, 8)
              : entry.reactionId,
          'error': e.toString(),
        },
      );
      try {
        await reactionReplayOutboxRepo!.updateEntryStatus(
          entry.reactionId,
          deliveryStatus: GroupReactionReplayOutboxStatus.failed,
          lastError: e.toString(),
        );
      } catch (statusError) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_GROUP_REACTION_REPLAY_MARK_FAILED_ERROR',
          details: {
            'reactionId': entry.reactionId.length > 8
                ? entry.reactionId.substring(0, 8)
                : entry.reactionId,
            'error': statusError.toString(),
          },
        );
      }
      continue;
    }

    try {
      await reactionReplayOutboxRepo!.updateEntryStatus(
        entry.reactionId,
        deliveryStatus: GroupReactionReplayOutboxStatus.stored,
      );
      retriedCount++;

      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_REACTION_REPLAY_OK',
        details: {
          'reactionId': entry.reactionId.length > 8
              ? entry.reactionId.substring(0, 8)
              : entry.reactionId,
          'action': entry.action,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_REACTION_REPLAY_MARK_STORED_ERROR',
        details: {
          'reactionId': entry.reactionId.length > 8
              ? entry.reactionId.substring(0, 8)
              : entry.reactionId,
          'error': e.toString(),
        },
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_GROUP_INBOX_STORES_DONE',
    details: {
      'retried': retriedCount,
      'total': messages.length + reactionEntries.length,
      'messageTotal': messages.length,
      'reactionTotal': reactionEntries.length,
    },
  );
  emitRetryTiming(
    outcome: 'complete',
    total: messages.length + reactionEntries.length,
    retried: retriedCount,
  );

  return retriedCount;
}
