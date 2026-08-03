import 'package:flutter_app/core/notifications/group_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'group_notification_read_acknowledgement_db_helpers.dart';

const String _groupRemovalCutoffLike = 'sys-member_removed_cutoff:%';

/// Resolves whether a conversation-read commit durably covered this exact
/// content event. Absence is not treated as acknowledgement.
Future<bool> dbIsGroupNotificationEventAcknowledged(
  DatabaseExecutor db, {
  required String groupId,
  required ConversationNotificationContentKind contentKind,
  required String eventIdentity,
}) async {
  final normalizedGroupId = groupId.trim();
  final normalizedEventIdentity = eventIdentity.trim();
  if (normalizedGroupId.isEmpty || normalizedEventIdentity.isEmpty) {
    return false;
  }
  if (await dbLoadExactGroupNotificationReadAcknowledgement(
        db,
        groupId: normalizedGroupId,
        contentKind: contentKind.name,
        eventIdentity: normalizedEventIdentity,
      ) !=
      null) {
    return true;
  }
  return switch (contentKind) {
    ConversationNotificationContentKind.message => () async {
      final rows = await db.query(
        'group_messages',
        columns: const <String>['id'],
        where:
            'id = ? AND group_id = ? AND is_incoming = 1 '
            'AND read_at IS NOT NULL AND id NOT LIKE ?',
        whereArgs: <Object?>[
          normalizedEventIdentity,
          normalizedGroupId,
          _groupRemovalCutoffLike,
        ],
        limit: 1,
      );
      return rows.isNotEmpty;
    }(),
    ConversationNotificationContentKind.reaction => () async {
      final rows = await db.rawQuery(
        'SELECT 1 FROM message_reactions AS r '
        'INNER JOIN group_messages AS m ON m.id = r.message_id '
        'WHERE m.group_id = ? '
        'AND r.notification_display_terminal_event_id = ? '
        'AND r.notification_acknowledged_at IS NOT NULL LIMIT 1',
        <Object?>[normalizedGroupId, normalizedEventIdentity],
      );
      return rows.isNotEmpty;
    }(),
  };
}

/// Returns whether the exact message represented by a managed card remains an
/// unread incoming row in this group.
Future<bool> dbIsUnreadGroupNotificationMessage(
  DatabaseExecutor db, {
  required String groupId,
  required String eventIdentity,
}) async {
  final rows = await db.query(
    'group_messages',
    columns: const <String>['id'],
    where:
        'id = ? AND group_id = ? AND is_incoming = 1 AND read_at IS NULL '
        'AND id NOT LIKE ?',
    whereArgs: <Object?>[eventIdentity, groupId, _groupRemovalCutoffLike],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// Resolves whether the exact reaction event still has an active canonical ADD
/// on a locally-authored target in this group.
///
/// The terminal event id was recorded atomically when its display outbox
/// completed. Its retained row distinguishes an exact REMOVE or a target that
/// was deleted after display from an ADD whose push arrived before canonical
/// reaction persistence. Absence of the matching reaction row is therefore
/// [GroupNotificationCanonicalContentDecision.unknown], never blind retire.
Future<GroupNotificationCanonicalContentDecision>
dbIsActiveGroupNotificationReaction(
  DatabaseExecutor db, {
  required String groupId,
  required String selfPeerId,
  required String eventIdentity,
}) async {
  final normalizedGroupId = groupId.trim();
  final normalizedSelfPeerId = selfPeerId.trim();
  final normalizedEventIdentity = eventIdentity.trim();
  if (normalizedGroupId.isEmpty ||
      normalizedSelfPeerId.isEmpty ||
      normalizedEventIdentity.isEmpty) {
    return GroupNotificationCanonicalContentDecision.unknown;
  }
  final rows = await db.rawQuery(
    'SELECT r.message_id, r.removed_at, r.notification_acknowledged_at, '
    'm.id AS target_id, m.group_id AS target_group_id, '
    'm.sender_peer_id AS target_sender_peer_id, '
    'm.is_incoming AS target_is_incoming, '
    'm.media_policy_version, m.media_lifecycle, '
    'm.media_duration_seconds, m.media_protected, '
    'deleted.group_id AS deletion_group_id '
    'FROM message_reactions AS r '
    'LEFT JOIN group_messages AS m ON m.id = r.message_id '
    'LEFT JOIN group_message_local_deletions AS deleted '
    'ON deleted.message_id = r.message_id '
    'WHERE r.notification_display_terminal_event_id = ? '
    'ORDER BY julianday(r.timestamp) DESC, r.timestamp DESC, r.id DESC '
    'LIMIT 1',
    <Object?>[normalizedEventIdentity],
  );
  if (rows.isEmpty) {
    return GroupNotificationCanonicalContentDecision.unknown;
  }
  final row = rows.single;
  if (row['removed_at'] != null ||
      row['notification_acknowledged_at'] != null) {
    return GroupNotificationCanonicalContentDecision.retire;
  }
  if (row['deletion_group_id'] == normalizedGroupId) {
    return GroupNotificationCanonicalContentDecision.retire;
  }
  if (row['target_id'] == null) {
    // The exact reaction row and its terminal display identity are present,
    // so this is not push-before-inbox uncertainty. The target existed when
    // that identity was committed and has since been hard-deleted. Retaining
    // the identifier-only binding is the terminal evidence required to retire
    // the old managed card, including membership-repair deletes that
    // intentionally do not write a user-local deletion tombstone.
    return GroupNotificationCanonicalContentDecision.retire;
  }
  if (row['target_group_id'] != normalizedGroupId ||
      row['target_sender_peer_id'] != normalizedSelfPeerId ||
      (row['target_is_incoming'] as num?)?.toInt() != 0 ||
      (row['message_id'] as String?)?.startsWith('sys-') == true ||
      !_isOrdinaryGroupMediaPolicy(row)) {
    return GroupNotificationCanonicalContentDecision.retire;
  }
  return GroupNotificationCanonicalContentDecision.keep;
}

/// Mirrors the durable ordinary-policy tuples without importing a feature
/// model into `lib/core`. Missing columns identify a legacy ordinary row; an
/// explicit tuple is ordinary only when all four values are canonical.
bool _isOrdinaryGroupMediaPolicy(Map<String, Object?> row) {
  final version = row['media_policy_version'];
  final lifecycle = row['media_lifecycle'];
  final durationSeconds = row['media_duration_seconds'];
  final protected = row['media_protected'];
  if (version == null &&
      lifecycle == null &&
      durationSeconds == null &&
      protected == null) {
    return true;
  }
  return version == 0 &&
      lifecycle == 'standard' &&
      durationSeconds == null &&
      protected == 0;
}

/// Loads the newest active reaction ADD that previously reached a terminal
/// notification decision and still targets an ordinary locally-authored group
/// message. The returned fields are identifier/timestamp-only; UI copy remains
/// derived from canonical target media and never includes target text/emoji.
Future<Map<String, Object?>?> dbLoadLatestActiveGroupNotificationReaction(
  DatabaseExecutor db, {
  required String groupId,
  required String selfPeerId,
}) async {
  final rows = await db.rawQuery(
    'SELECT r.id, r.message_id, r.sender_peer_id, r.timestamp, '
    'r.notification_display_terminal_event_id '
    'FROM message_reactions AS r '
    'INNER JOIN group_messages AS m ON m.id = r.message_id '
    'WHERE m.group_id = ? AND m.sender_peer_id = ? '
    'AND m.is_incoming = 0 AND m.id NOT LIKE ? '
    'AND r.sender_peer_id != ? AND r.removed_at IS NULL '
    'AND r.notification_acknowledged_at IS NULL '
    'AND r.notification_display_terminal_event_id IS NOT NULL '
    "AND TRIM(r.notification_display_terminal_event_id) != '' "
    'AND NOT EXISTS (SELECT 1 FROM group_message_local_deletions AS deleted '
    'WHERE deleted.message_id = m.id AND deleted.group_id = m.group_id) '
    'AND ((m.media_policy_version IS NULL '
    'AND m.media_lifecycle IS NULL '
    'AND m.media_duration_seconds IS NULL '
    'AND m.media_protected IS NULL) '
    'OR (m.media_policy_version = 0 '
    "AND m.media_lifecycle = 'standard' "
    'AND m.media_duration_seconds IS NULL '
    'AND m.media_protected = 0)) ',
    <Object?>[groupId, selfPeerId, _groupRemovalCutoffLike, selfPeerId],
  );
  // Dart accepts a wider ISO-8601 grammar than SQLite's julianday(), including
  // compact dates and offsets without a colon. Reaction ingress validates with
  // DateTime.tryParse and retains that authenticated wire text, so selecting a
  // SQL LIMIT before Dart comparison can discard the actual newest instant.
  return _newestCanonicalTimestampedRow(rows);
}

/// Loads the newest unread incoming message that previously reached a terminal
/// notification decision and can therefore safely replace invalid card
/// content. Synthetic system rows never own this terminal marker.
Future<Map<String, Object?>?> dbLoadLatestUnreadGroupNotificationMessage(
  DatabaseExecutor db,
  String groupId,
) async {
  final rows = await db.query(
    'group_messages',
    where:
        'group_id = ? AND is_incoming = 1 AND read_at IS NULL '
        'AND notification_display_terminal_event_id IS NOT NULL '
        'AND id NOT LIKE ?',
    whereArgs: <Object?>[groupId, _groupRemovalCutoffLike],
  );
  return _newestCanonicalTimestampedRow(rows);
}

Map<String, Object?>? _newestCanonicalTimestampedRow(
  List<Map<String, Object?>> rows,
) {
  Map<String, Object?>? newest;
  DateTime? newestAt;
  String? newestTimestamp;
  String? newestId;
  for (final row in rows) {
    final timestamp = (row['timestamp'] as String?)?.trim();
    if (timestamp == null) continue;
    final at = DateTime.tryParse(timestamp)?.toUtc();
    if (at == null) continue;
    final id = (row['id'] as String?)?.trim() ?? '';
    final timeOrder = newestAt == null ? 1 : at.compareTo(newestAt);
    final textOrder = timestamp.compareTo(newestTimestamp ?? '');
    final idOrder = id.compareTo(newestId ?? '');
    if (newest == null ||
        timeOrder > 0 ||
        (timeOrder == 0 && textOrder > 0) ||
        (timeOrder == 0 && textOrder == 0 && idOrder > 0)) {
      newest = row;
      newestAt = at;
      newestTimestamp = timestamp;
      newestId = id;
    }
  }
  return newest;
}
