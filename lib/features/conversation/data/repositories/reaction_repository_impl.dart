import 'dart:async';

import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/group_notification_reconciliation_signal.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../domain/models/message_reaction.dart';
import '../../domain/repositories/reaction_repository.dart';

/// Implementation of ReactionRepository using database helper functions.
class ReactionRepositoryImpl
    implements
        ReactionRepository,
        AtomicIncomingReactionMutationRepository,
        AtomicGroupReactionAdditionRepository,
        AtomicGroupReactionRemovalRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsertReaction;
  final Future<ReactionAddApplyResult> Function(Map<String, Object?> row)?
  dbApplyIncomingAdd;
  final Future<ReactionAddApplyResult> Function({
    required String groupId,
    required String notificationEventId,
    required Map<String, Object?> row,
  })?
  dbApplyGroupAdd;
  final Future<ReactionRemoveApplyResult> Function(Map<String, Object?> row)?
  dbApplyIncomingRemove;
  final Future<ReactionRemoveApplyResult> Function({
    required String groupId,
    required Map<String, Object?> row,
  })?
  dbApplyGroupRemove;
  final Future<List<Map<String, Object?>>> Function(String messageId)
  dbLoadReactionsForMessage;
  final Future<List<Map<String, Object?>>> Function(List<String> messageIds)
  dbLoadReactionsForMessages;
  final Future<Map<String, Object?>?> Function(
    String messageId,
    String senderPeerId,
  )
  dbLoadActiveOrTombstonedReactionForSender;
  final Future<int> Function(
    String messageId,
    String senderPeerId, {
    String? removedAtTimestamp,
  })
  dbDeleteReaction;
  final Future<int> Function(String messageId) dbDeleteReactionsForMessage;
  final Future<int> Function(String contactPeerId) dbDeleteReactionsForContact;
  final GroupReactionNotificationProjection? groupReactionProjection;
  final Future<List<Map<String, Object?>>> Function(
    String accountPeerId, {
    int limit,
  })?
  dbLoadGroupReactionComparandsForProjection;
  Future<void> _incomingMutationTail = Future<void>.value();

  ReactionRepositoryImpl({
    required this.dbInsertReaction,
    this.dbApplyIncomingAdd,
    this.dbApplyGroupAdd,
    this.dbApplyIncomingRemove,
    this.dbApplyGroupRemove,
    required this.dbLoadReactionsForMessage,
    required this.dbLoadReactionsForMessages,
    required this.dbLoadActiveOrTombstonedReactionForSender,
    required this.dbDeleteReaction,
    required this.dbDeleteReactionsForMessage,
    required this.dbDeleteReactionsForContact,
    this.groupReactionProjection,
    this.dbLoadGroupReactionComparandsForProjection,
  });

  @override
  Future<void> saveReaction(MessageReaction reaction) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_REPO_SAVE_START',
      details: {
        'id': reaction.id.length > 8
            ? reaction.id.substring(0, 8)
            : reaction.id,
      },
    );

    try {
      await dbInsertReaction(reaction.toMap());
      await groupReactionProjection?.upsertReactionComparand(reaction);

      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_REPO_SAVE_SUCCESS',
        details: {
          'id': reaction.id.length > 8
              ? reaction.id.substring(0, 8)
              : reaction.id,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<ReactionAddApplyResult> applyGroupAdd({
    required String groupId,
    required String notificationEventId,
    required MessageReaction reaction,
  }) async {
    final atomicApply = dbApplyGroupAdd;
    final result = atomicApply == null
        ? await applyIncomingAdd(reaction)
        : await atomicApply(
            groupId: groupId,
            notificationEventId: notificationEventId,
            row: reaction.toMap(),
          );
    if (atomicApply != null && result != ReactionAddApplyResult.stale) {
      await groupReactionProjection?.upsertReactionComparand(reaction);
    }
    return result;
  }

  @override
  Future<ReactionAddApplyResult> applyIncomingAdd(MessageReaction reaction) {
    final atomicApply = dbApplyIncomingAdd;
    if (atomicApply != null) {
      return () async {
        final result = await atomicApply(reaction.toMap());
        if (result != ReactionAddApplyResult.stale) {
          await groupReactionProjection?.upsertReactionComparand(reaction);
        }
        return result;
      }();
    }
    return _serializeIncomingMutation(() async {
      final current = await getReactionForSenderIncludingRemoved(
        messageId: reaction.messageId,
        senderPeerId: reaction.senderPeerId,
      );
      final incomingAt = DateTime.tryParse(reaction.timestamp);
      final currentAt = current == null
          ? null
          : DateTime.tryParse(current.removedAt ?? current.timestamp);
      if (incomingAt != null &&
          currentAt != null &&
          incomingAt.isBefore(currentAt)) {
        return ReactionAddApplyResult.stale;
      }
      if (current?.id == reaction.id &&
          current?.isRemoved == false &&
          current?.timestamp == reaction.timestamp) {
        return ReactionAddApplyResult.exactReplay;
      }

      await saveReaction(reaction);
      return current == null
          ? ReactionAddApplyResult.inserted
          : ReactionAddApplyResult.updated;
    });
  }

  @override
  Future<ReactionRemoveApplyResult> applyIncomingRemove(
    MessageReaction reaction,
  ) {
    final atomicApply = dbApplyIncomingRemove;
    if (atomicApply != null) {
      return () async {
        final result = await atomicApply(reaction.toMap());
        if (result != ReactionRemoveApplyResult.stale) {
          await groupReactionProjection?.upsertReactionComparand(
            reaction.copyWith(removedAt: reaction.timestamp),
          );
        }
        return result;
      }();
    }
    return _serializeIncomingMutation(() async {
      final current = await getReactionForSenderIncludingRemoved(
        messageId: reaction.messageId,
        senderPeerId: reaction.senderPeerId,
      );
      final incomingAt = DateTime.tryParse(reaction.timestamp);
      final currentAt = current == null
          ? null
          : DateTime.tryParse(current.removedAt ?? current.timestamp);
      if (incomingAt != null &&
          currentAt != null &&
          incomingAt.isBefore(currentAt)) {
        return ReactionRemoveApplyResult.stale;
      }
      if (current?.isRemoved == true &&
          current?.id == reaction.id &&
          current?.removedAt == reaction.timestamp) {
        return ReactionRemoveApplyResult.exactReplay;
      }

      await removeReaction(
        reaction.messageId,
        reaction.senderPeerId,
        removedAtTimestamp: reaction.timestamp,
      );
      return ReactionRemoveApplyResult.applied;
    });
  }

  @override
  Future<ReactionRemoveApplyResult> applyGroupRemove({
    required String groupId,
    required MessageReaction reaction,
  }) async {
    final atomicApply = dbApplyGroupRemove;
    final result = atomicApply == null
        ? await applyIncomingRemove(reaction)
        : await atomicApply(groupId: groupId, row: reaction.toMap());
    if (atomicApply != null && result != ReactionRemoveApplyResult.stale) {
      await groupReactionProjection?.upsertReactionComparand(
        reaction.copyWith(removedAt: reaction.timestamp),
      );
    }
    if (result != ReactionRemoveApplyResult.stale) {
      emitGroupNotificationReconciliationSignal(groupId);
    }
    return result;
  }

  Future<T> _serializeIncomingMutation<T>(Future<T> Function() action) async {
    final previous = _incomingMutationTail;
    final release = Completer<void>();
    _incomingMutationTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  @override
  Future<List<MessageReaction>> getReactionsForMessage(String messageId) async {
    final rows = await dbLoadReactionsForMessage(messageId);
    return rows.map((row) => MessageReaction.fromMap(row)).toList();
  }

  @override
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadReactionsForMessages(messageIds);
    final Map<String, List<MessageReaction>> result = {};
    for (final row in rows) {
      final reaction = MessageReaction.fromMap(row);
      result.putIfAbsent(reaction.messageId, () => []).add(reaction);
    }
    return result;
  }

  @override
  Future<MessageReaction?> getReactionForSenderIncludingRemoved({
    required String messageId,
    required String senderPeerId,
  }) async {
    final row = await dbLoadActiveOrTombstonedReactionForSender(
      messageId,
      senderPeerId,
    );
    return row == null ? null : MessageReaction.fromMap(row);
  }

  @override
  Future<int> removeReaction(
    String messageId,
    String senderPeerId, {
    String? removedAtTimestamp,
  }) async {
    final count = await dbDeleteReaction(
      messageId,
      senderPeerId,
      removedAtTimestamp: removedAtTimestamp,
    );
    if (count > 0) {
      final current = await getReactionForSenderIncludingRemoved(
        messageId: messageId,
        senderPeerId: senderPeerId,
      );
      if (current != null) {
        await groupReactionProjection?.upsertReactionComparand(current);
      }
    }
    return count;
  }

  @override
  Future<int> deleteReactionsForMessage(String messageId) async {
    final count = await dbDeleteReactionsForMessage(messageId);
    await groupReactionProjection?.removeReactionComparandsForMessage(
      messageId,
    );
    return count;
  }

  @override
  Future<int> deleteReactionsForContact(String contactPeerId) async {
    return await dbDeleteReactionsForContact(contactPeerId);
  }

  /// Launch/migration self-heal for the bounded iOS reaction comparand mirror.
  Future<void> mirrorAllGroupReactionNotificationComparands({
    bool rethrowOnError = false,
  }) async {
    final projection = groupReactionProjection;
    final loadRows = dbLoadGroupReactionComparandsForProjection;
    if (projection == null || loadRows == null) return;
    try {
      final accountPeerId = await projection.readLocalAccountPeerId();
      if (accountPeerId == null) return;
      final rows = await loadRows(
        accountPeerId,
        limit: projection.maxReactionComparands,
      );
      await projection.replaceReactionComparands(
        rows.map((row) => MessageReaction.fromMap(row)),
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_REPO_GROUP_PUSH_PROJECTION_BACKFILL_ERROR',
        details: {'error': error.toString()},
      );
      if (rethrowOnError) rethrow;
    }
  }
}
