import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../notifications/deterministic_notification_id.dart';
import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import 'direct_contact_device_bindings_db_helpers.dart';
import 'group_notification_display_outbox_db_helpers.dart';
import 'group_notification_read_acknowledgement_db_helpers.dart';
import 'group_notification_reconciliation_outbox_db_helpers.dart';

/// Mutation kind accepted by [dbApplyIncomingReactionMutation].
enum DbIncomingReactionMutation { add, remove }

/// Result of one transactional incoming-reaction compare/write decision.
enum DbIncomingReactionApplyResult {
  inserted,
  updated,
  removed,
  exactReplay,
  stale,
}

/// Atomically applies an incoming ADD or REMOVE using the sender-authored
/// timestamp as the last-writer-wins comparand.
///
/// The read, comparison, and write intentionally live in one SQL transaction.
/// This makes the decision shared by every repository instance and isolate
/// using the same SQLCipher database instead of relying on an object-local
/// Dart mutex. A REMOVE writes a complete tombstone (including when it arrives
/// before its ADD), so an older delayed ADD cannot resurrect the reaction.
Future<DbIncomingReactionApplyResult> dbApplyIncomingReactionMutation(
  Database db,
  Map<String, Object?> row, {
  required DbIncomingReactionMutation mutation,
  String? groupIdForNotificationCleanup,
  String? notificationEventIdForStaleAddCleanup,
  String? authenticatedTransportPeerId,
}) async {
  final id = _requiredReactionString(row, 'id');
  final messageId = _requiredReactionString(row, 'message_id');
  final senderPeerId = _requiredReactionString(row, 'sender_peer_id');
  final timestamp = _requiredReactionString(row, 'timestamp');
  final normalizedGroupId = groupIdForNotificationCleanup?.trim();
  final normalizedNotificationEventId = notificationEventIdForStaleAddCleanup
      ?.trim();
  final hasGroupCustody =
      normalizedGroupId != null && normalizedGroupId.isNotEmpty;
  final hasAddEventCustody =
      normalizedNotificationEventId != null &&
      normalizedNotificationEventId.isNotEmpty;
  if (hasAddEventCustody &&
      (!hasGroupCustody || mutation != DbIncomingReactionMutation.add)) {
    throw ArgumentError.value(
      notificationEventIdForStaleAddCleanup,
      'notificationEventIdForStaleAddCleanup',
      'requires an explicit group ADD mutation',
    );
  }
  if (hasGroupCustody &&
      mutation == DbIncomingReactionMutation.add &&
      !hasAddEventCustody) {
    throw ArgumentError.value(
      notificationEventIdForStaleAddCleanup,
      'notificationEventIdForStaleAddCleanup',
      'is required for exact stale ADD custody cleanup',
    );
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_ATOMIC_APPLY_START',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'mutation': mutation.name,
    },
  );

  try {
    final result = await dbWriteTransaction(db, (txn) async {
      // 361: a linked physical transport re-authorizes to the reaction's
      // logical sender inside this durable apply transaction; revoke-first is
      // therefore zero-effect (`stale`, nothing written).
      if (authenticatedTransportPeerId != null &&
          authenticatedTransportPeerId != senderPeerId) {
        final authority = await dbResolveDirectTransportToLogicalContact(
          txn,
          transportPeerId: authenticatedTransportPeerId,
        );
        if (!authority.authorized ||
            authority.contactAccountPeerId != senderPeerId) {
          return DbIncomingReactionApplyResult.stale;
        }
      }
      if (hasGroupCustody) {
        final target = await txn.query(
          'group_messages',
          columns: const <String>['id'],
          where: 'id = ? AND group_id = ?',
          whereArgs: <Object?>[messageId, normalizedGroupId],
          limit: 1,
        );
        if (target.isEmpty) {
          throw StateError(
            'group reaction REMOVE target does not belong to explicit group',
          );
        }
      }
      final rows = await txn.query(
        'message_reactions',
        where: 'message_id = ? AND sender_peer_id = ?',
        whereArgs: [messageId, senderPeerId],
        limit: 1,
      );
      final current = rows.isEmpty ? null : rows.single;
      final boundedAddEventIdentity =
          mutation == DbIncomingReactionMutation.add && hasAddEventCustody
          ? boundedReactionEventIdentity(normalizedNotificationEventId)
          : null;
      final pendingReadAcknowledgement =
          boundedAddEventIdentity == null || !hasGroupCustody
          ? null
          : await dbLoadExactGroupNotificationReadAcknowledgement(
              txn,
              groupId: normalizedGroupId,
              contentKind: 'reaction',
              eventIdentity: boundedAddEventIdentity,
            );
      final incomingAt = DateTime.tryParse(timestamp);
      final currentTimestamp = current == null
          ? null
          : (current['removed_at'] as String? ??
                current['timestamp'] as String?);
      final currentAt = currentTimestamp == null
          ? null
          : DateTime.tryParse(currentTimestamp);
      if (incomingAt != null &&
          currentAt != null &&
          incomingAt.isBefore(currentAt)) {
        if (mutation == DbIncomingReactionMutation.add &&
            hasGroupCustody &&
            hasAddEventCustody) {
          await _deleteExactStaleAddNotificationCustody(
            txn,
            eventId: normalizedNotificationEventId,
            groupId: normalizedGroupId,
            messageId: messageId,
            actorPeerId: senderPeerId,
            eventTimestamp: timestamp,
            reactionId: id,
          );
          if (pendingReadAcknowledgement != null) {
            await dbConsumeExactGroupNotificationReadAcknowledgement(
              txn,
              groupId: normalizedGroupId,
              contentKind: 'reaction',
              eventIdentity: boundedAddEventIdentity!,
            );
            await dbEnqueueGroupNotificationReconciliationOutbox(
              txn,
              groupId: normalizedGroupId,
            );
          }
        }
        return DbIncomingReactionApplyResult.stale;
      }

      final currentId = current?['id'] as String?;
      final currentRemovedAt = current?['removed_at'] as String?;
      final currentAddTimestamp = current?['timestamp'] as String?;
      final isExactReplay = mutation == DbIncomingReactionMutation.add
          ? currentId == id &&
                currentRemovedAt == null &&
                currentAddTimestamp == timestamp
          : currentId == id && currentRemovedAt == timestamp;
      if (isExactReplay) {
        if (mutation == DbIncomingReactionMutation.add &&
            hasGroupCustody &&
            pendingReadAcknowledgement != null) {
          await txn.rawUpdate(
            'UPDATE message_reactions '
            'SET notification_acknowledged_at = ?, '
            'notification_display_terminal_event_id = ? '
            'WHERE message_id = ? AND sender_peer_id = ?',
            <Object?>[
              pendingReadAcknowledgement['acknowledged_at'],
              boundedAddEventIdentity,
              messageId,
              senderPeerId,
            ],
          );
          await dbConsumeExactGroupNotificationReadAcknowledgement(
            txn,
            groupId: normalizedGroupId,
            contentKind: 'reaction',
            eventIdentity: boundedAddEventIdentity!,
          );
          await dbEnqueueGroupNotificationReconciliationOutbox(
            txn,
            groupId: normalizedGroupId,
          );
        }
        if (mutation == DbIncomingReactionMutation.add &&
            hasGroupCustody &&
            hasAddEventCustody &&
            (current?['notification_display_terminal_event_id'] as String?)
                    ?.trim()
                    .isNotEmpty ==
                true) {
          // This exact canonical ADD generation was already presented (or
          // terminally suppressed). The bounded filesystem claim may have
          // expired, but the canonical row remains authoritative. Retire only
          // the just-staged exact transition; a crash-before-display row has
          // no terminal marker and deliberately remains retryable.
          await _deleteExactStaleAddNotificationCustody(
            txn,
            eventId: normalizedNotificationEventId,
            groupId: normalizedGroupId,
            messageId: messageId,
            actorPeerId: senderPeerId,
            eventTimestamp: timestamp,
            reactionId: id,
          );
        }
        if (mutation == DbIncomingReactionMutation.remove && hasGroupCustody) {
          await dbDeleteGroupNotificationDisplayOutboxForReactionActor(
            txn,
            groupId: normalizedGroupId,
            messageId: messageId,
            actorPeerId: senderPeerId,
          );
          await dbEnqueueGroupNotificationReconciliationOutbox(
            txn,
            groupId: normalizedGroupId,
          );
        }
        return DbIncomingReactionApplyResult.exactReplay;
      }

      final normalizedRow = Map<String, Object?>.from(row);
      normalizedRow['removed_at'] =
          mutation == DbIncomingReactionMutation.remove ? timestamp : null;
      final currentTerminalIdentity =
          (current?['notification_display_terminal_event_id'] as String?)
              ?.trim();
      final custodyTerminalIdentity =
          mutation == DbIncomingReactionMutation.remove &&
              hasGroupCustody &&
              current != null &&
              currentRemovedAt == null &&
              (currentTerminalIdentity == null ||
                  currentTerminalIdentity.isEmpty)
          ? await _loadExactCurrentAddCustodyTerminalIdentity(
              txn,
              groupId: normalizedGroupId,
              messageId: messageId,
              actorPeerId: senderPeerId,
              eventTimestamp: currentAddTimestamp!,
              reactionId: currentId!,
            )
          : null;
      // A REMOVE is a terminal transition for the currently displayed ADD.
      // Preserve its recorded terminal identity, or transfer the identifier
      // from its exact still-live ADD custody before that custody is retired.
      // The latter closes the background-show -> markerless foreground ADD ->
      // REMOVE race without copying notification text, emoji, or payload.
      // A later ADD deliberately starts without this marker until its own
      // display custody reaches a terminal decision.
      normalizedRow['notification_display_terminal_event_id'] =
          mutation == DbIncomingReactionMutation.remove
          ? currentTerminalIdentity?.isNotEmpty == true
                ? currentTerminalIdentity
                : custodyTerminalIdentity
          : pendingReadAcknowledgement == null
          ? null
          : boundedAddEventIdentity;
      if (mutation == DbIncomingReactionMutation.add &&
          pendingReadAcknowledgement != null) {
        normalizedRow['notification_acknowledged_at'] =
            pendingReadAcknowledgement['acknowledged_at'];
      } else if (current != null &&
          mutation == DbIncomingReactionMutation.remove &&
          current.containsKey('notification_acknowledged_at')) {
        normalizedRow['notification_acknowledged_at'] =
            current['notification_acknowledged_at'];
      }
      await txn.insert(
        'message_reactions',
        normalizedRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (mutation == DbIncomingReactionMutation.add &&
          hasGroupCustody &&
          pendingReadAcknowledgement != null) {
        await dbConsumeExactGroupNotificationReadAcknowledgement(
          txn,
          groupId: normalizedGroupId,
          contentKind: 'reaction',
          eventIdentity: boundedAddEventIdentity!,
        );
        await dbEnqueueGroupNotificationReconciliationOutbox(
          txn,
          groupId: normalizedGroupId,
        );
      }

      if (mutation == DbIncomingReactionMutation.remove) {
        if (hasGroupCustody) {
          await dbDeleteGroupNotificationDisplayOutboxForReactionActor(
            txn,
            groupId: normalizedGroupId,
            messageId: messageId,
            actorPeerId: senderPeerId,
          );
          await dbEnqueueGroupNotificationReconciliationOutbox(
            txn,
            groupId: normalizedGroupId,
          );
          if (currentTerminalIdentity?.isNotEmpty == true) {
            await dbConsumeExactGroupNotificationReadAcknowledgement(
              txn,
              groupId: normalizedGroupId,
              contentKind: 'reaction',
              eventIdentity: currentTerminalIdentity!,
            );
          }
        }
        return DbIncomingReactionApplyResult.removed;
      }
      return current == null
          ? DbIncomingReactionApplyResult.inserted
          : DbIncomingReactionApplyResult.updated;
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_ATOMIC_APPLY_SUCCESS',
      details: {'mutation': mutation.name, 'result': result.name},
    );
    return result;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_ATOMIC_APPLY_ERROR',
      details: {'mutation': mutation.name, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<int> _deleteExactStaleAddNotificationCustody(
  DatabaseExecutor db, {
  required String eventId,
  required String groupId,
  required String messageId,
  required String actorPeerId,
  required String eventTimestamp,
  required String reactionId,
}) async {
  final table = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'group_notification_display_outbox' LIMIT 1",
  );
  if (table.isEmpty) return 0;
  final where =
      'event_id = ? AND event_kind = ? AND group_id = ? '
      'AND message_id = ? AND actor_peer_id = ? AND event_timestamp = ? '
      'AND reaction_id = ? AND reaction_action = ? '
      'AND reaction_tombstone = ?';
  final whereArgs = <Object?>[
    eventId,
    'reaction',
    groupId,
    messageId,
    actorPeerId,
    eventTimestamp,
    reactionId,
    'add',
    0,
  ];
  final exactCustody = await db.query(
    'group_notification_display_outbox',
    columns: const <String>['event_id'],
    where: where,
    whereArgs: whereArgs,
    limit: 1,
  );
  if (exactCustody.isEmpty) return 0;

  // A REMOVE-before-ADD tombstone has no marker to carry forward. When the
  // delayed ADD is proven stale, consuming its exact identifier-only custody
  // is itself the terminal decision for that ADD generation. Bind the event
  // to the tombstone before deleting custody so canonical reconciliation can
  // retire a card that the background isolate may already have published.
  await db.rawUpdate(
    'UPDATE message_reactions '
    'SET notification_display_terminal_event_id = ? '
    'WHERE message_id = ? AND sender_peer_id = ? AND removed_at IS NOT NULL '
    'AND (notification_display_terminal_event_id IS NULL '
    "OR TRIM(notification_display_terminal_event_id) = '')",
    <Object?>[boundedReactionEventIdentity(eventId), messageId, actorPeerId],
  );
  return db.delete(
    'group_notification_display_outbox',
    where: where,
    whereArgs: whereArgs,
  );
}

Future<String?> _loadExactCurrentAddCustodyTerminalIdentity(
  DatabaseExecutor db, {
  required String groupId,
  required String messageId,
  required String actorPeerId,
  required String eventTimestamp,
  required String reactionId,
}) async {
  final table = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'group_notification_display_outbox' LIMIT 1",
  );
  if (table.isEmpty) return null;
  final rows = await db.query(
    'group_notification_display_outbox',
    columns: const <String>['event_id'],
    where:
        'event_kind = ? AND group_id = ? AND message_id = ? '
        'AND actor_peer_id = ? AND event_timestamp = ? AND reaction_id = ? '
        'AND reaction_action = ? AND reaction_tombstone = ?',
    whereArgs: <Object?>[
      'reaction',
      groupId,
      messageId,
      actorPeerId,
      eventTimestamp,
      reactionId,
      'add',
      0,
    ],
    orderBy: 'event_id ASC',
    limit: 2,
  );
  // Multiple different transition identities for one canonical ADD are an
  // authority conflict. Fail unknown instead of binding the card arbitrarily.
  if (rows.length != 1) return null;
  final eventId = (rows.single['event_id'] as String?)?.trim();
  return eventId == null || eventId.isEmpty
      ? null
      : boundedReactionEventIdentity(eventId);
}

String _requiredReactionString(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError.value(value, key, 'must be a non-empty String');
  }
  return value;
}

/// Inserts or replaces a reaction in the database.
///
/// Uses REPLACE conflict algorithm so that re-inserting with the same
/// (message_id, sender_peer_id) pair replaces the existing row.
Future<void> dbInsertReaction(Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.insert(
      'message_reactions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_INSERT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all reactions for a single message, ordered by timestamp ASC.
Future<List<Map<String, Object?>>> dbLoadReactionsForMessage(
  Database db,
  String messageId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_LOAD_FOR_MSG_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  try {
    final results = await db.query(
      'message_reactions',
      where: 'message_id = ? AND removed_at IS NULL',
      whereArgs: [messageId],
      orderBy: 'timestamp ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_LOAD_FOR_MSG_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_LOAD_FOR_MSG_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all reactions for multiple messages in a single query.
Future<List<Map<String, Object?>>> dbLoadReactionsForMessages(
  Database db,
  List<String> messageIds,
) async {
  if (messageIds.isEmpty) return [];

  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_LOAD_FOR_MSGS_START',
    details: {'messageCount': messageIds.length},
  );

  try {
    final placeholders = List.filled(messageIds.length, '?').join(',');
    final results = await db.rawQuery(
      'SELECT * FROM message_reactions WHERE message_id IN ($placeholders) '
      'AND removed_at IS NULL ORDER BY timestamp ASC',
      messageIds,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_LOAD_FOR_MSGS_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_LOAD_FOR_MSGS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Soft-deletes (tombstones) a reaction for a specific message and sender by
/// setting `removed_at` to the remove's sender-authored timestamp instead of
/// hard-deleting the row. The retained tombstone is the last-writer-wins
/// comparand that lets a later *older* add be recognised as stale and dropped
/// (INV-T1). Falls back to the local clock when [removedAtTimestamp] is null.
///
/// Only updates an existing row (the remove-then-stale-add case, where the
/// remove is applied after the add). Returns the number of rows tombstoned.
Future<int> dbDeleteReaction(
  Database db,
  String messageId,
  String senderPeerId, {
  String? removedAtTimestamp,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_TOMBSTONE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  try {
    final removedAt =
        removedAtTimestamp ?? DateTime.now().toUtc().toIso8601String();
    final count = await db.update(
      'message_reactions',
      {'removed_at': removedAt},
      where: 'message_id = ? AND sender_peer_id = ?',
      whereArgs: [messageId, senderPeerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_TOMBSTONE_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_TOMBSTONE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads the single reaction for (message, sender) — including a tombstoned one
/// — for the last-writer-wins comparand. Returns null when no row exists.
Future<Map<String, Object?>?> dbLoadActiveOrTombstonedReactionForSender(
  Database db,
  String messageId,
  String senderPeerId,
) async {
  final rows = await db.query(
    'message_reactions',
    where: 'message_id = ? AND sender_peer_id = ?',
    whereArgs: [messageId, senderPeerId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

/// Loads the bounded latest active/tombstoned reaction state for group
/// messages authored by [accountPeerId]. The shared reaction table also holds
/// direct-message rows, so the join is the causal lane discriminator.
Future<List<Map<String, Object?>>> dbLoadGroupReactionComparandsForProjection(
  Database db,
  String accountPeerId, {
  int limit = 1024,
}) async {
  if (accountPeerId.trim().isEmpty || limit <= 0) return const [];
  return db.rawQuery(
    'SELECT r.* FROM message_reactions AS r '
    'INNER JOIN group_messages AS g ON g.id = r.message_id '
    'WHERE g.sender_peer_id = ? '
    'ORDER BY COALESCE(r.removed_at, r.timestamp) DESC, r.id ASC '
    'LIMIT ?',
    <Object?>[accountPeerId, limit],
  );
}

/// Deletes all reactions for a specific message.
Future<int> dbDeleteReactionsForMessage(Database db, String messageId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_DELETE_FOR_MSG_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  try {
    final count = await db.delete(
      'message_reactions',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_FOR_MSG_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_FOR_MSG_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes all reactions for a contact via subquery on messages table.
///
/// Must be called BEFORE dbDeleteMessagesForContact, because the subquery
/// needs the messages rows to exist.
Future<int> dbDeleteReactionsForContact(
  Database db,
  String contactPeerId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_DELETE_FOR_CONTACT_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final count = await db.rawDelete(
      'DELETE FROM message_reactions WHERE message_id IN '
      '(SELECT id FROM messages WHERE contact_peer_id = ?)',
      [contactPeerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_FOR_CONTACT_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_FOR_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
