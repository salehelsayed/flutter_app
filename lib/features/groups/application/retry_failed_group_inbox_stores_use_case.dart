import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
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

bool _hasNoGroupReactionReplayRecipients(String inboxRetryPayload) {
  try {
    final decoded = jsonDecode(inboxRetryPayload);
    if (decoded is! Map) return false;
    if (!decoded.containsKey('recipientPeerIds')) return true;
    final recipients = decoded['recipientPeerIds'];
    return recipients == null || (recipients is List && recipients.isEmpty);
  } catch (_) {
    return false;
  }
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
    Future<bool> retryCandidate() => _retryFailedGroupInboxMessageCandidate(
      bridge: bridge,
      msgRepo: msgRepo,
      groupRepo: groupRepo,
      identityRepo: identityRepo,
      privateMediaAvailability: privateMediaAvailability,
      privateMediaNowMs: privateMediaNowMs,
      expected: msg,
    );
    final retried = groupRepo == null
        ? await retryCandidate()
        : (await runSelfRemovedGroupLifecycleLeaf<bool>(
                groupRepo: groupRepo,
                groupId: msg.groupId,
                action: (_) => retryCandidate(),
              )).value ==
              true;
    if (retried) retriedCount++;
  }

  for (final entry in reactionEntries) {
    Future<bool> retryCandidate() => _retryGroupReactionReplayCandidate(
      bridge: bridge,
      repository: reactionReplayOutboxRepo!,
      expected: entry,
    );
    final retried = groupRepo == null
        ? await retryCandidate()
        : (await runSelfRemovedGroupLifecycleLeaf<bool>(
                groupRepo: groupRepo,
                groupId: entry.groupId,
                action: (_) => retryCandidate(),
              )).value ==
              true;
    if (retried) retriedCount++;
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

Future<bool> _retryFailedGroupInboxMessageCandidate({
  required Bridge bridge,
  required GroupMessageRepository msgRepo,
  required GroupRepository? groupRepo,
  required IdentityRepository? identityRepo,
  required GroupPrivateMediaAvailability privateMediaAvailability,
  required int Function()? privateMediaNowMs,
  required GroupMessage expected,
}) async {
  try {
    final current = await msgRepo.getMessage(expected.id);
    if (current == null ||
        !sameExactGroupPrivateMediaDispatchParent(current, expected)) {
      return false;
    }

    GroupPrivateMediaLifecycleRepository? privateLifecycleRepository;
    if (current.privateMediaPolicy.isUnsupported) return false;
    if (current.privateMediaPolicy.isPrivate) {
      if (!privateMediaAvailability.isEnabled ||
          groupRepo == null ||
          identityRepo == null) {
        return false;
      }
      if (msgRepo is GroupPrivateMediaLifecycleRepository) {
        privateLifecycleRepository =
            msgRepo as GroupPrivateMediaLifecycleRepository;
      }
      final identity = await identityRepo.loadIdentity();
      if (identity == null || identity.peerId != current.senderPeerId) {
        return false;
      }
      final qualification = await qualifyCurrentPrivateGroupMediaSend(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        expectedParent: current,
        senderPeerId: identity.peerId,
      );
      final persistedRecipients = _privateRetryRecipientPeerIds(
        current.inboxRetryPayload!,
      );
      if (qualification == null ||
          persistedRecipients == null ||
          !_matchesCurrentPrivateRetryRecipients(
            persisted: persistedRecipients,
            currentRemoteRecipients: qualification.recipientPeerIds,
            senderPeerId: identity.peerId,
          )) {
        return false;
      }
    }

    await storeGroupOfflineReplayFromRetryPayload(
      bridge: bridge,
      inboxRetryPayload: current.inboxRetryPayload!,
    );

    final exactCompletion = msgRepo is GroupInboxStoreRetryCompletionRepository
        ? msgRepo as GroupInboxStoreRetryCompletionRepository
        : null;
    final applied = exactCompletion != null
        ? await exactCompletion.completeInboxStoreRetry(current)
        : await _completeLegacyInboxStoreRetry(msgRepo, current);
    if (!applied) return false;

    if (current.privateMediaPolicy.isPrivate) {
      final anchoredAt =
          privateMediaNowMs?.call() ??
          DateTime.now().toUtc().millisecondsSinceEpoch;
      var anchored = false;
      if (privateLifecycleRepository != null) {
        anchored = await privateLifecycleRepository
            .anchorOutgoingGroupPrivateMediaCustody(
              current.id,
              nowMs: anchoredAt,
            );
      } else {
        final completed = current.copyWith(
          status: 'sent',
          inboxStored: true,
          inboxRetryPayload: null,
        );
        final latest = await msgRepo.getMessage(current.id);
        if (latest != null &&
            latest.mediaReceivedAt == null &&
            sameExactGroupPrivateMediaDispatchParent(latest, completed)) {
          final expiresAt =
              latest.privateMediaPolicy.lifecycle ==
                  GroupMediaLifecycle.disappearing
              ? anchoredAt + (latest.privateMediaPolicy.durationSeconds! * 1000)
              : null;
          await msgRepo.saveMessage(
            latest.copyWith(
              mediaReceivedAt: anchoredAt,
              mediaExpiresAt: expiresAt,
              mediaLastCheckedAt: expiresAt == null ? null : anchoredAt,
            ),
          );
          anchored = true;
        }
      }
      if (anchored &&
          current.privateMediaPolicy.lifecycle ==
              GroupMediaLifecycle.disappearing) {
        signalGroupPrivateMediaExpiryChanged();
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_INBOX_STORE_OK',
      details: {
        'messageId': current.id.length > 8
            ? current.id.substring(0, 8)
            : current.id,
      },
    );
    return true;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_INBOX_STORE_ERROR',
      details: {
        'messageId': expected.id.length > 8
            ? expected.id.substring(0, 8)
            : expected.id,
        'error': e.toString(),
      },
    );
    return false;
  }
}

Future<bool> _completeLegacyInboxStoreRetry(
  GroupMessageRepository repository,
  GroupMessage expected,
) async {
  final current = await repository.getMessage(expected.id);
  if (current == null ||
      !sameExactGroupPrivateMediaDispatchParent(current, expected)) {
    return false;
  }
  await repository.updateInboxStored(expected.id, stored: true);
  await repository.updateInboxRetryPayload(expected.id, null);
  await repository.updateMessageStatus(expected.id, 'sent');
  return true;
}

bool _sameReactionReplayCandidate(
  GroupReactionReplayOutboxEntry current,
  GroupReactionReplayOutboxEntry expected,
) =>
    current.reactionId == expected.reactionId &&
    current.groupId == expected.groupId &&
    current.messageId == expected.messageId &&
    current.senderPeerId == expected.senderPeerId &&
    current.emoji == expected.emoji &&
    current.action == expected.action &&
    current.inboxRetryPayload == expected.inboxRetryPayload &&
    current.deliveryStatus == expected.deliveryStatus &&
    current.lastError == expected.lastError &&
    current.createdAt == expected.createdAt &&
    current.updatedAt == expected.updatedAt;

Future<bool> _retryGroupReactionReplayCandidate({
  required Bridge bridge,
  required GroupReactionReplayOutboxRepository repository,
  required GroupReactionReplayOutboxEntry expected,
}) async {
  final current = await repository.getEntry(expected.reactionId);
  if (current == null || !_sameReactionReplayCandidate(current, expected)) {
    return false;
  }
  if (_hasNoGroupReactionReplayRecipients(current.inboxRetryPayload)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_CUSTODY_UNROUTABLE',
      details: {
        'reactionId': current.reactionId.length > 8
            ? current.reactionId.substring(0, 8)
            : current.reactionId,
        'reason': 'empty_recipients',
      },
    );
    await repository.deleteEntry(current.reactionId);
    return false;
  }
  try {
    await storeGroupOfflineReplayFromRetryPayload(
      bridge: bridge,
      inboxRetryPayload: current.inboxRetryPayload,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_REACTION_REPLAY_ERROR',
      details: {
        'reactionId': current.reactionId.length > 8
            ? current.reactionId.substring(0, 8)
            : current.reactionId,
        'error': e.toString(),
      },
    );
    try {
      await repository.updateEntryStatusIfExact(
        current,
        deliveryStatus: GroupReactionReplayOutboxStatus.failed,
        lastError: e.toString(),
      );
    } catch (statusError) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_REACTION_REPLAY_MARK_FAILED_ERROR',
        details: {
          'reactionId': current.reactionId.length > 8
              ? current.reactionId.substring(0, 8)
              : current.reactionId,
          'error': statusError.toString(),
        },
      );
    }
    return false;
  }

  try {
    final completed = await repository.updateEntryStatusIfExact(
      current,
      deliveryStatus: GroupReactionReplayOutboxStatus.stored,
    );
    if (!completed) return false;
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_REACTION_REPLAY_OK',
      details: {
        'reactionId': current.reactionId.length > 8
            ? current.reactionId.substring(0, 8)
            : current.reactionId,
        'action': current.action,
      },
    );
    return true;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_REACTION_REPLAY_MARK_STORED_ERROR',
      details: {
        'reactionId': current.reactionId.length > 8
            ? current.reactionId.substring(0, 8)
            : current.reactionId,
        'error': e.toString(),
      },
    );
    return false;
  }
}
