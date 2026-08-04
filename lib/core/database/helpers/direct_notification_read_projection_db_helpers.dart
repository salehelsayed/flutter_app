import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/notifications/direct_notification_read_projector.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Commits canonical direct read state, exact push-before-inbox custody, and
/// peer reconciliation in one SQL transaction.
Future<DirectConversationReadCommit> dbMarkDirectConversationReadAndAcknowledge(
  Database db, {
  required String peerId,
  required ConversationNotificationContentMetadata? metadata,
  DateTime Function()? nowUtc,
}) {
  final normalizedPeerId = peerId.trim();
  if (normalizedPeerId.isEmpty) {
    throw ArgumentError.value(peerId, 'peerId', 'must not be empty');
  }
  final now = (nowUtc ?? DateTime.now)().toUtc().toIso8601String();
  return dbWriteTransaction(db, (txn) async {
    final markedCount = await txn.rawUpdate(
      'UPDATE messages SET read_at = ? '
      'WHERE contact_peer_id = ? AND is_incoming = 1 '
      'AND read_at IS NULL AND hidden_at IS NULL',
      <Object?>[now, normalizedPeerId],
    );

    var acknowledged = metadata == null;
    final generation = metadata?.generation?.trim();
    final eventIdentity = metadata?.eventIdentity?.trim();
    // A live conversation open owns the exact captured peer generation even
    // when an older/generic producer could not attach an event identity. There
    // is no event marker to journal in that case, but the generation CAS still
    // prevents cancelling a later sibling card.
    if (metadata != null &&
        generation != null &&
        generation.isNotEmpty &&
        (eventIdentity == null || eventIdentity.isEmpty)) {
      acknowledged = true;
    }
    if (metadata != null &&
        generation != null &&
        generation.isNotEmpty &&
        eventIdentity != null &&
        eventIdentity.isNotEmpty) {
      switch (metadata.kind) {
        case ConversationNotificationContentKind.message:
          final rows = await txn.query(
            'messages',
            columns: const <String>['id'],
            where:
                'id = ? AND contact_peer_id = ? AND is_incoming = 1 '
                'AND read_at IS NOT NULL',
            whereArgs: <Object?>[eventIdentity, normalizedPeerId],
            limit: 1,
          );
          acknowledged = rows.isNotEmpty;
          if (!acknowledged) {
            acknowledged = await dbRecordDirectNotificationReadAcknowledgement(
              txn,
              peerId: normalizedPeerId,
              contentKind: 'message',
              eventIdentity: eventIdentity,
              messageId: eventIdentity,
              actorPeerId: null,
              generation: generation,
              acknowledgedAt: now,
            );
          }
        case ConversationNotificationContentKind.reaction:
          var tuples = await txn.query(
            'direct_notification_reaction_terminal_events',
            columns: const <String>['message_id', 'actor_peer_id'],
            where: 'peer_id = ? AND terminal_event_id = ?',
            whereArgs: <Object?>[normalizedPeerId, eventIdentity],
            limit: 1,
          );
          if (tuples.isNotEmpty) {
            acknowledged =
                await txn.rawUpdate(
                  'UPDATE direct_notification_reaction_terminal_events '
                  'SET notification_acknowledged_at = ?, updated_at = ? '
                  'WHERE peer_id = ? AND terminal_event_id = ?',
                  <Object?>[now, now, normalizedPeerId, eventIdentity],
                ) ==
                1;
          } else {
            // Push may own the card before canonical reaction materializes.
            // The marker is explicitly direct and carries the full tuple, so
            // no lane is inferred from the shared message_reactions table.
            tuples = await txn.query(
              'direct_notification_display_outbox',
              columns: const <String>['message_id', 'actor_peer_id'],
              where: 'peer_id = ? AND event_kind = ? AND event_id = ?',
              whereArgs: <Object?>[normalizedPeerId, 'reaction', eventIdentity],
              limit: 1,
            );
            if (tuples.isNotEmpty) {
              acknowledged =
                  await dbRecordDirectNotificationReadAcknowledgement(
                    txn,
                    peerId: normalizedPeerId,
                    contentKind: 'reaction',
                    eventIdentity: eventIdentity,
                    messageId: tuples.single['message_id'] as String,
                    actorPeerId: tuples.single['actor_peer_id'] as String,
                    generation: generation,
                    acknowledgedAt: now,
                  );
            }
          }
      }
    }

    // Explicit even when zero message rows changed: opening a conversation is
    // also the reaction-read boundary and can race push-before-inbox.
    await dbEnqueueDirectNotificationReconciliationOutbox(
      txn,
      peerId: normalizedPeerId,
    );
    return DirectConversationReadCommit(
      markedCount: markedCount,
      notificationAcknowledged: acknowledged,
    );
  }, exclusive: true);
}
