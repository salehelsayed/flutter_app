import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

List<String>? _privateRetryRecipientPeerIds(String retryPayload) {
  try {
    final payload = jsonDecode(retryPayload) as Map<String, dynamic>;
    if (!payload.containsKey('recipientPeerIds')) return null;
    final rawRecipients = payload['recipientPeerIds'];
    if (rawRecipients is! List) return null;
    final recipients = <String>[];
    final seen = <String>{};
    for (final raw in rawRecipients) {
      if (raw is! String) return null;
      final peerId = raw.trim();
      if (peerId.isEmpty || !seen.add(peerId)) return null;
      recipients.add(peerId);
    }
    return recipients;
  } catch (_) {
    return null;
  }
}

bool _matchesCurrentPrivateRetryRecipients({
  required List<String> persisted,
  required List<String> currentRemoteRecipients,
  required String senderPeerId,
}) {
  if (sameGroupPrivateMediaRecipientPeerIds(
    persisted,
    currentRemoteRecipients,
  )) {
    return true;
  }
  return sameGroupPrivateMediaRecipientPeerIds(persisted, [
    ...currentRemoteRecipients,
    senderPeerId,
  ]);
}

/// Retries inbox store for outgoing group messages where the initial
/// inbox store failed.
///
/// Queries rows where:
///   - `is_incoming = 0`
///   - `status IN ('sent', 'pending', 'queued_offline')`
///   - `inbox_stored = 0`
///   - `inbox_retry_payload IS NOT NULL`
///
/// For each, reconstructs the inbox store call from persisted JSON payload,
/// calls `callGroupInboxStore`, and closes the row as fully sent on success —
/// for a 210b `queued_offline` row this IS the reconnect self-heal (the
/// on-screen clock settles to a tick).
///
/// When [reactionReplayOutboxRepo] is provided, the same retry pass also
/// drains retryable sender-owned reaction replay rows after message rows.
///
/// Returns the number of successfully retried entries across both owners.
Future<int> retryFailedGroupInboxStores({
  required Bridge bridge,
  required GroupMessageRepository msgRepo,
  GroupRepository? groupRepo,
  IdentityRepository? identityRepo,
  GroupPrivateMediaAvailability privateMediaAvailability =
      productionGroupPrivateMediaAvailability,
  GroupReactionReplayOutboxRepository? reactionReplayOutboxRepo,
  int limit = 20,
  int Function()? privateMediaNowMs,
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
      GroupPrivateMediaLifecycleRepository? privateLifecycleRepository;
      if (msg.privateMediaPolicy.isUnsupported) {
        continue;
      }
      if (msg.privateMediaPolicy.isPrivate) {
        if (!privateMediaAvailability.isEnabled) {
          continue;
        }
        if (groupRepo == null || identityRepo == null) {
          continue;
        }
        if (msgRepo is GroupPrivateMediaLifecycleRepository) {
          privateLifecycleRepository =
              msgRepo as GroupPrivateMediaLifecycleRepository;
        }
        final identity = await identityRepo.loadIdentity();
        if (identity == null || identity.peerId != msg.senderPeerId) {
          continue;
        }
        final qualification = await qualifyCurrentPrivateGroupMediaSend(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          expectedParent: msg,
          senderPeerId: identity.peerId,
        );
        final persistedRecipients = _privateRetryRecipientPeerIds(
          msg.inboxRetryPayload!,
        );
        if (qualification == null ||
            persistedRecipients == null ||
            !_matchesCurrentPrivateRetryRecipients(
              persisted: persistedRecipients,
              currentRemoteRecipients: qualification.recipientPeerIds,
              senderPeerId: identity.peerId,
            )) {
          continue;
        }
      }

      await storeGroupOfflineReplayFromRetryPayload(
        bridge: bridge,
        inboxRetryPayload: msg.inboxRetryPayload!,
      );

      if (msg.privateMediaPolicy.isPrivate) {
        final anchoredAt =
            privateMediaNowMs?.call() ??
            DateTime.now().toUtc().millisecondsSinceEpoch;
        var anchored = false;
        if (privateLifecycleRepository != null) {
          anchored = await privateLifecycleRepository
              .anchorOutgoingGroupPrivateMediaCustody(
                msg.id,
                nowMs: anchoredAt,
              );
        } else {
          // Lightweight repositories used outside production do not expose
          // the atomic lifecycle capability. Preserve their behavior without
          // ever recreating a deleted or drifted row; production always takes
          // the guarded branch above.
          final current = await msgRepo.getMessage(msg.id);
          if (current != null &&
              current.mediaReceivedAt == null &&
              sameExactGroupPrivateMediaDispatchParent(current, msg)) {
            final expiresAt =
                current.privateMediaPolicy.lifecycle ==
                    GroupMediaLifecycle.disappearing
                ? anchoredAt +
                      (current.privateMediaPolicy.durationSeconds! * 1000)
                : null;
            await msgRepo.saveMessage(
              current.copyWith(
                mediaReceivedAt: anchoredAt,
                mediaExpiresAt: expiresAt,
                mediaLastCheckedAt: expiresAt == null ? null : anchoredAt,
              ),
            );
            anchored = true;
          }
        }
        if (anchored &&
            msg.privateMediaPolicy.lifecycle ==
                GroupMediaLifecycle.disappearing) {
          signalGroupPrivateMediaExpiryChanged();
        }
      }

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
