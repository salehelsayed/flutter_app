import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
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

/// Mirrors the fail-closed normalization of
/// [sameGroupPrivateMediaRecipientPeerIds] (an empty or duplicate entry poisons
/// the whole set) WITHOUT reusing it. That helper has three other production
/// callers — the media-ACL drift check, private requalification, and the
/// capability-fallback path — where EXACT equality is the intended semantics;
/// relaxing it there would widen a blob ACL (plan 323 reviewer finding B4).
Set<String>? _normalizedRetryRecipientSet(Iterable<String> values) {
  final result = <String>{};
  for (final value in values) {
    final peerId = value.trim();
    if (peerId.isEmpty || !result.add(peerId)) return null;
  }
  return result;
}

/// Plan 323 (318 deferral B): a persisted private-media recipient snapshot stays
/// replayable while every peer it names is still qualified today.
///
/// Exact-set equality denied these rows permanently once plan 318 WIDENED the
/// send qualification (`send_group_message_use_case.dart:111-120`) — the frozen
/// pre-318 set can no longer equal the wider current one. The retry replays the
/// FROZEN payload (`storeGroupOfflineReplayFromRetryPayload`), never the current
/// set, so this predicate only decides store-vs-no-store and can never widen the
/// relay ACL.
///
/// SUBSET, not superset: `persisted ⊆ current` is safe because every persisted
/// peer is still entitled today. A persisted peer ABSENT from current (departed,
/// demoted, key-rotated) must still DENY — that direction is a real exposure.
/// An empty persisted set is denied outright: `{} ⊆ anything` would make this a
/// tautology, and the relay rejects empty recipient sets anyway, so allowing it
/// would only buy a doomed bridge round-trip on every retrier tick.
bool _matchesCurrentPrivateRetryRecipients({
  required List<String> persisted,
  required List<String> currentRemoteRecipients,
  required String senderPeerId,
}) {
  final normalizedPersisted = _normalizedRetryRecipientSet(persisted);
  if (normalizedPersisted == null || normalizedPersisted.isEmpty) return false;

  bool contains(List<String> candidate) {
    final normalizedCandidate = _normalizedRetryRecipientSet(candidate);
    return normalizedCandidate != null &&
        normalizedCandidate.containsAll(normalizedPersisted);
  }

  // Second arm: the send lane may omit the sender from the durable recipient
  // set (`includeSenderPeerIdInDurableRecipients` defaults false), so a
  // sender-inclusive persisted set is legitimate and must stay replayable.
  return contains(currentRemoteRecipients) ||
      contains([...currentRemoteRecipients, senderPeerId]);
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
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      identityRepo: identityRepo,
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
  GroupRepository? groupRepo,
  GroupMessageRepository? msgRepo,
  IdentityRepository? identityRepo,
}) async {
  var current = await repository.getEntry(expected.reactionId);
  if (current == null || !_sameReactionReplayCandidate(current, expected)) {
    return false;
  }
  // Plan 319: a needs_build row (or any row left with the sentinel-empty
  // payload by a rolled-back build) carries identity but no envelope — rebuild
  // it here, reusing the ORIGINAL transition id and deterministic reaction id
  // so notification-surface dedupe and receiver idempotency both hold.
  if (current.deliveryStatus == GroupReactionReplayOutboxStatus.needsBuild ||
      current.inboxRetryPayload.isEmpty) {
    final rebuilt = await _rebuildGroupReactionReplayPayload(
      bridge: bridge,
      repository: repository,
      row: current,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      identityRepo: identityRepo,
    );
    if (rebuilt == null) return false;
    current = rebuilt;
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


/// Plan 319: rebuild an abandoned reaction's replay envelope from its durable
/// outbox identity. Fail-soft — any missing dependency leaves the row in
/// `needs_build` with `last_error`, so the next retry pass tries again.
Future<GroupReactionReplayOutboxEntry?> _rebuildGroupReactionReplayPayload({
  required Bridge bridge,
  required GroupReactionReplayOutboxRepository repository,
  required GroupReactionReplayOutboxEntry row,
  required GroupRepository? groupRepo,
  required GroupMessageRepository? msgRepo,
  required IdentityRepository? identityRepo,
}) async {
  Future<GroupReactionReplayOutboxEntry?> failSoft(String reason) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REPLAY_REBUILD_DEFERRED',
      details: {
        'reactionId': row.reactionId.length > 8
            ? row.reactionId.substring(0, 8)
            : row.reactionId,
        'reason': reason,
      },
    );
    await repository.updateEntryStatus(
      row.reactionId,
      deliveryStatus: GroupReactionReplayOutboxStatus.needsBuild,
      lastError: reason,
    );
    return null;
  }

  if (groupRepo == null || msgRepo == null || identityRepo == null) {
    return failSoft('rebuild_dependencies_unavailable');
  }
  try {
    final identity = await identityRepo.loadIdentity();
    if (identity == null) return failSoft('identity_unavailable');
    final member = await groupRepo.getMember(row.groupId, row.senderPeerId);
    final senderDevice = member?.firstActiveDeviceForSigningKey(
      identity.publicKey,
      allowLegacyFallback: true,
    );
    if (senderDevice == null) return failSoft('sender_device_unavailable');
    final target = await msgRepo.getMessage(row.messageId);
    if (target == null) return failSoft('target_message_unavailable');

    final payload = GroupReactionPayload(
      id: row.action == GroupReactionPayload.actionAdd
          ? deterministicGroupAddReactionId(
              groupId: row.groupId,
              messageId: row.messageId,
              senderPeerId: row.senderPeerId,
              emoji: row.emoji,
            )
          : deterministicGroupRemoveReactionId(
              groupId: row.groupId,
              messageId: row.messageId,
              senderPeerId: row.senderPeerId,
            ),
      messageId: row.messageId,
      emoji: row.emoji,
      action: row.action,
      senderPeerId: row.senderPeerId,
      // Anchored to the authored moment, never now(): a rebuilt ADD must not
      // out-time a REMOVE tombstone written while the row waited.
      timestamp: row.createdAt,
      eventId: row.reactionId,
    );
    final recipients = await resolveGroupReactionRecipientsForRebuild(
      groupRepo: groupRepo,
      groupId: row.groupId,
      senderTransportPeerId: senderDevice.transportPeerId,
      reactorPeerId: row.senderPeerId,
      targetAuthorPeerId: target.senderPeerId,
    );
    final inboxRetryPayload = await buildGroupOfflineReplayInboxRetryPayload(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: row.groupId,
      payloadType: groupOfflineReplayPayloadTypeReaction,
      plaintext: payload.toInnerJson(),
      senderPeerId: row.senderPeerId,
      senderPublicKey: senderDevice.deviceSigningPublicKey,
      senderPrivateKey: identity.privateKey,
      messageId: payload.id,
      senderDeviceId: senderDevice.deviceId,
      senderTransportPeerId: senderDevice.transportPeerId,
      senderKeyPackageId: senderDevice.keyPackageId,
      recipientPeerIds: recipients.replayRecipientTransportPeerIds,
      reactionNotificationExtension: GroupReactionNotificationExtensionInput(
        transitionId: row.reactionId,
        action: row.action,
        targetMessageId: row.messageId,
        reactorPeerId: row.senderPeerId,
        reactorTransportPeerId: senderDevice.transportPeerId,
        notificationRecipientTransportPeerIds:
            recipients.notificationRecipientTransportPeerIds,
      ),
    );
    final attached = await repository.attachBuiltPayload(
      reactionId: row.reactionId,
      inboxRetryPayload: inboxRetryPayload,
    );
    if (!attached) return failSoft('row_vanished_during_rebuild');
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REPLAY_REBUILT',
      details: {
        'reactionId': row.reactionId.length > 8
            ? row.reactionId.substring(0, 8)
            : row.reactionId,
      },
    );
    return await repository.getEntry(row.reactionId);
  } catch (e) {
    return failSoft(e.toString());
  }
}
