import 'dart:collection';

import 'package:sqflite_sqlcipher/sqflite.dart';

/// The notification lane that owns one canonical unread event.
enum CanonicalNotificationLane { direct, group }

/// Raw domain identity for one unread event.
///
/// These values deliberately remain unhashed in Dart. The native iOS recovery
/// boundary hashes them using the same implementation that owns its ledger.
final class CanonicalNotificationIdentity {
  const CanonicalNotificationIdentity({
    required this.lane,
    required this.conversationId,
    required this.eventId,
  });

  final CanonicalNotificationLane lane;
  final String conversationId;
  final String eventId;

  @override
  bool operator ==(Object other) =>
      other is CanonicalNotificationIdentity &&
      other.lane == lane &&
      other.conversationId == conversationId &&
      other.eventId == eventId;

  @override
  int get hashCode => Object.hash(lane, conversationId, eventId);
}

/// One immutable, absolute view of notification-eligible unread messages.
final class CanonicalNotificationBadgeState {
  CanonicalNotificationBadgeState({
    required this.unreadCount,
    required Iterable<CanonicalNotificationIdentity> identities,
  }) : identities = UnmodifiableListView<CanonicalNotificationIdentity>(
         List<CanonicalNotificationIdentity>.of(identities),
       ) {
    if (unreadCount < 0 || unreadCount != this.identities.length) {
      throw ArgumentError.value(
        unreadCount,
        'unreadCount',
        'must equal the number of canonical identities',
      );
    }
  }

  final int unreadCount;
  final List<CanonicalNotificationIdentity> identities;
}

/// Loads the absolute direct + group notification badge state in one SQLite
/// statement, so the count and identities always describe the same snapshot.
///
/// Reactions live in separate tables and are intentionally absent. The policy
/// predicates mirror the canonical direct/group notification snapshots while
/// additionally joining the current contact/group eligibility rows.
Future<CanonicalNotificationBadgeState> dbLoadCanonicalNotificationBadgeState(
  DatabaseExecutor db,
) async {
  final rows = await db.rawQuery('''
SELECT
  'direct' AS lane,
  m.contact_peer_id AS conversation_id,
  m.id AS event_id
FROM messages AS m
INNER JOIN contacts AS c ON c.peer_id = m.contact_peer_id
WHERE m.is_incoming = 1
  AND m.read_at IS NULL
  AND m.hidden_at IS NULL
  AND m.deleted_at IS NULL
  AND (
    (
      m.private_media_policy_version = 0
      AND m.private_media_mode = 'ordinary'
      AND m.private_media_duration_seconds IS NULL
    )
    OR (
      m.private_media_policy_version = 1
      AND (
        (
          m.private_media_mode IN ('ordinary', 'protected', 'view_once')
          AND m.private_media_duration_seconds IS NULL
        )
        OR (
          m.private_media_mode = 'disappearing'
          AND m.private_media_duration_seconds IN (3600, 86400, 604800)
        )
      )
    )
  )
  AND m.private_media_state NOT IN ('consumed', 'expired', 'unsupported')
  AND c.is_archived = 0
  AND c.is_blocked = 0
UNION ALL
SELECT
  'group' AS lane,
  gm.group_id AS conversation_id,
  gm.id AS event_id
FROM group_messages AS gm
INNER JOIN groups AS g ON g.id = gm.group_id
WHERE gm.is_incoming = 1
  AND gm.read_at IS NULL
  AND gm.id NOT LIKE 'sys-member_removed_cutoff:%'
  AND (
    (
      gm.media_policy_version = 0
      AND gm.media_lifecycle = 'standard'
      AND gm.media_duration_seconds IS NULL
      AND gm.media_protected = 0
      AND gm.media_received_at IS NULL
      AND gm.media_expires_at IS NULL
      AND gm.media_last_checked_at IS NULL
      AND gm.media_cleanup_pending = 0
    )
    OR (
      gm.media_policy_version = 1
      AND gm.media_protected = 1
      AND gm.media_cleanup_pending = 0
      AND (
        (
          gm.media_lifecycle IN ('standard', 'view_once')
          AND gm.media_duration_seconds IS NULL
          AND gm.media_expires_at IS NULL
        )
        OR (
          gm.media_lifecycle = 'disappearing'
          AND gm.media_duration_seconds IN (3600, 86400, 604800)
        )
      )
    )
  )
  AND gm.media_consumed_at IS NULL
  AND gm.media_expired_at IS NULL
  AND g.is_muted = 0
  AND g.is_archived = 0
  AND g.is_dissolved = 0
  AND g.self_removed_at IS NULL
ORDER BY lane, conversation_id, event_id
''');

  final identities = rows
      .map((row) {
        final lane = switch (row['lane']) {
          'direct' => CanonicalNotificationLane.direct,
          'group' => CanonicalNotificationLane.group,
          final value => throw StateError(
            'Unexpected notification lane: $value',
          ),
        };
        return CanonicalNotificationIdentity(
          lane: lane,
          conversationId: row['conversation_id']! as String,
          eventId: row['event_id']! as String,
        );
      })
      .toList(growable: false);

  return CanonicalNotificationBadgeState(
    unreadCount: identities.length,
    identities: identities,
  );
}
