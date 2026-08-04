import 'dart:io';

import 'package:flutter_app/core/database/helpers/direct_notification_read_projection_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/106_group_notification_display_outbox.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('same ids remain notification kind and peer scoped', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await _createV105Minimum(db);
    await runGroupNotificationDisplayOutboxMigration(db);
    await runDirectNotificationDurabilityMigration(db);
    const now = '2026-08-03T10:00:00.000Z';

    await db.insert('contacts', const <String, Object?>{
      'peer_id': 'same-owner-id',
      'is_archived': 0,
      'is_blocked': 0,
    });
    await db.insert('contacts', const <String, Object?>{
      'peer_id': 'second-direct-peer',
      'is_archived': 0,
      'is_blocked': 0,
    });
    await db.insert('messages', const <String, Object?>{
      'id': 'same-message-id',
      'contact_peer_id': 'same-owner-id',
      'sender_peer_id': 'same-owner-id',
      'timestamp': now,
      'is_incoming': 1,
      'read_at': null,
      'hidden_at': null,
      'deleted_at': null,
    });
    await db.insert('group_messages', const <String, Object?>{
      'id': 'same-message-id',
      'group_id': 'same-owner-id',
      'is_incoming': 1,
      'read_at': null,
    });
    await db.insert(
      'direct_notification_display_outbox',
      _displayRow(ownerColumn: 'peer_id', ownerId: 'same-owner-id'),
    );
    await db.insert(
      'direct_notification_display_outbox',
      _displayRow(ownerColumn: 'peer_id', ownerId: 'second-direct-peer'),
    );
    await db.insert(
      'group_notification_display_outbox',
      _displayRow(ownerColumn: 'group_id', ownerId: 'same-owner-id'),
    );
    await db.insert(
      'direct_notification_reaction_terminal_events',
      const <String, Object?>{
        'peer_id': 'same-owner-id',
        'message_id': 'same-message-id',
        'actor_peer_id': 'same-actor-id',
        'reaction_id': 'same-reaction-id',
        'terminal_event_id': 'reaction:same-event-id',
        'notification_acknowledged_at': null,
        'updated_at': now,
      },
    );
    await db.insert(
      'direct_notification_reaction_terminal_events',
      const <String, Object?>{
        'peer_id': 'second-direct-peer',
        'message_id': 'same-message-id',
        'actor_peer_id': 'same-actor-id',
        'reaction_id': 'same-reaction-id',
        'terminal_event_id': 'reaction:same-event-id',
        'notification_acknowledged_at': null,
        'updated_at': now,
      },
    );
    await db.insert('message_reactions', const <String, Object?>{
      'id': 'same-reaction-id',
      'message_id': 'same-message-id',
      'sender_peer_id': 'same-actor-id',
      'timestamp': now,
      'removed_at': null,
      'notification_display_terminal_event_id': 'reaction:same-event-id',
      'notification_acknowledged_at': null,
    });
    await db.insert(
      'direct_notification_read_acknowledgements',
      const <String, Object?>{
        'peer_id': 'same-owner-id',
        'content_kind': 'message',
        'event_identity': 'same-message-id',
        'message_id': 'same-message-id',
        'actor_peer_id': null,
        'generation': 'direct-read-generation',
        'acknowledged_at': now,
      },
    );
    await db.insert(
      'direct_notification_read_acknowledgements',
      const <String, Object?>{
        'peer_id': 'second-direct-peer',
        'content_kind': 'message',
        'event_identity': 'same-message-id',
        'message_id': 'same-message-id',
        'actor_peer_id': null,
        'generation': 'direct-read-generation',
        'acknowledged_at': now,
      },
    );
    await db.insert(
      'group_notification_read_acknowledgements',
      const <String, Object?>{
        'group_id': 'same-owner-id',
        'content_kind': 'message',
        'event_identity': 'same-message-id',
        'generation': 'group-read-generation',
        'acknowledged_at': now,
      },
    );

    final directRead = await dbMarkDirectConversationReadAndAcknowledge(
      db,
      peerId: 'same-owner-id',
      metadata: const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.reaction,
        eventIdentity: 'reaction:same-event-id',
        generation: 'direct-card-generation',
      ),
      nowUtc: () => DateTime.utc(2026, 8, 3, 11),
    );

    expect(directRead.notificationAcknowledged, isTrue);
    expect(
      (await db.query(
        'direct_notification_reaction_terminal_events',
        where: 'peer_id = ?',
        whereArgs: const ['same-owner-id'],
      )).single['notification_acknowledged_at'],
      isNotNull,
    );
    expect(
      (await db.query(
        'direct_notification_reaction_terminal_events',
        where: 'peer_id = ?',
        whereArgs: const ['second-direct-peer'],
      )).single['notification_acknowledged_at'],
      isNull,
    );
    expect(
      (await db.query(
        'message_reactions',
      )).single['notification_acknowledged_at'],
      isNull,
      reason: 'direct read must never infer authority from the shared row',
    );
    expect(await db.query('group_notification_display_outbox'), hasLength(1));
    expect(
      await db.query('group_notification_read_acknowledgements'),
      hasLength(1),
    );

    final directory = Directory.systemTemp.createTempSync(
      'direct-group-notification-lanes-',
    );
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final registry = DurableConversationNotificationIdRegistry(
      directory: directory,
      candidateGenerator: (key, probe) => probe == 0
          ? 77
          : key.startsWith('group:')
          ? 79
          : 78,
    );
    final directId = await registry.resolve(
      'same-owner-id',
      activeNotificationIds: () async => const <Object?>[],
    );
    final groupId = await registry.resolve(
      'group:same-owner-id',
      activeNotificationIds: () async => const <Object?>[],
    );
    final secondDirectId = await registry.resolve(
      'second-direct-peer',
      activeNotificationIds: () async => const <Object?>[],
    );
    expect(<int>{directId, secondDirectId, groupId}, hasLength(3));
    await registry.recordContentMetadata(
      conversationKey: 'same-owner-id',
      notificationId: directId,
      metadata: const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.reaction,
        eventIdentity: 'reaction:same-event-id',
        generation: 'direct-card-generation',
      ),
    );
    await registry.recordContentMetadata(
      conversationKey: 'second-direct-peer',
      notificationId: secondDirectId,
      metadata: const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.reaction,
        eventIdentity: 'reaction:same-event-id',
        generation: 'second-direct-card-generation',
      ),
    );
    await registry.recordContentMetadata(
      conversationKey: 'group:same-owner-id',
      notificationId: groupId,
      metadata: const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.reaction,
        eventIdentity: 'reaction:same-event-id',
        generation: 'group-card-generation',
      ),
    );
    final cancelledIds = <int>[];
    expect(
      await registry.cancelContentIfGeneration(
        conversationKey: 'same-owner-id',
        notificationId: directId,
        generation: 'direct-card-generation',
        cancel: () async => cancelledIds.add(directId),
      ),
      isTrue,
    );
    expect(cancelledIds, <int>[directId]);
    expect(
      await registry.lookupContentMetadata(
        conversationKey: 'second-direct-peer',
        notificationId: secondDirectId,
      ),
      const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.reaction,
        eventIdentity: 'reaction:same-event-id',
        generation: 'second-direct-card-generation',
      ),
    );
    expect(
      await registry.lookupContentMetadata(
        conversationKey: 'group:same-owner-id',
        notificationId: groupId,
      ),
      const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.reaction,
        eventIdentity: 'reaction:same-event-id',
        generation: 'group-card-generation',
      ),
    );

    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: const ['same-message-id'],
    );
    expect(await db.query('direct_notification_display_outbox'), hasLength(1));
    expect(
      (await db.query('direct_notification_display_outbox')).single['peer_id'],
      'second-direct-peer',
    );
    expect(
      await db.query('direct_notification_reaction_terminal_events'),
      hasLength(1),
    );
    expect(
      (await db.query(
        'direct_notification_reaction_terminal_events',
      )).single['peer_id'],
      'second-direct-peer',
    );
    expect(
      (await db.query(
        'direct_notification_read_acknowledgements',
      )).single['peer_id'],
      'second-direct-peer',
    );
    expect(await db.query('group_notification_display_outbox'), hasLength(1));
    expect(await db.query('message_reactions'), hasLength(1));
    expect(
      await db.query('group_notification_read_acknowledgements'),
      hasLength(1),
    );
  });

  test(
    'shared canonical reaction key limitation remains explicit and does not type notification authority',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createV105Minimum(db);
      await runGroupNotificationDisplayOutboxMigration(db);
      await runDirectNotificationDurabilityMigration(db);
      const shared = <String, Object?>{
        'id': 'group-reaction',
        'message_id': 'colliding-message',
        'sender_peer_id': 'colliding-actor',
        'timestamp': '2026-08-03T10:00:00.000Z',
        'removed_at': null,
      };
      await db.insert('message_reactions', shared);

      await expectLater(
        db.insert('message_reactions', <String, Object?>{
          ...shared,
          'id': 'direct-reaction',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.insert(
        'direct_notification_reaction_terminal_events',
        const <String, Object?>{
          'peer_id': 'direct-peer',
          'message_id': 'colliding-message',
          'actor_peer_id': 'colliding-actor',
          'reaction_id': 'direct-reaction',
          'terminal_event_id': 'reaction:direct-event',
          'notification_acknowledged_at': null,
          'updated_at': '2026-08-03T10:00:00.000Z',
        },
      );

      expect(await db.query('message_reactions'), hasLength(1));
      expect(
        (await db.query(
          'direct_notification_reaction_terminal_events',
        )).single['peer_id'],
        'direct-peer',
      );
    },
  );
}

Map<String, Object?> _displayRow({
  required String ownerColumn,
  required String ownerId,
}) => <String, Object?>{
  'event_id': 'reaction:same-event-id',
  'event_kind': 'reaction',
  ownerColumn: ownerId,
  'message_id': 'same-message-id',
  'actor_peer_id': 'same-actor-id',
  'event_timestamp': '2026-08-03T10:00:00.000Z',
  'reaction_id': 'same-reaction-id',
  'reaction_action': 'add',
  'reaction_tombstone': 0,
  'readiness': 'ready',
  'revision': 1,
  'retry_count': 0,
  'last_error_code': null,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': '2026-08-03T10:00:00.000Z',
  'updated_at': '2026-08-03T10:00:00.000Z',
};

Future<void> _createV105Minimum(Database db) async {
  await db.execute('''
    CREATE TABLE contacts (
      peer_id TEXT PRIMARY KEY,
      is_archived INTEGER NOT NULL DEFAULT 0,
      is_blocked INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      contact_peer_id TEXT NOT NULL,
      sender_peer_id TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      is_incoming INTEGER NOT NULL,
      read_at TEXT,
      hidden_at TEXT,
      deleted_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE groups (
      id TEXT PRIMARY KEY,
      type TEXT,
      is_muted INTEGER,
      is_archived INTEGER,
      is_dissolved INTEGER,
      dissolved_at TEXT,
      self_removed_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE group_members (
      group_id TEXT NOT NULL,
      peer_id TEXT NOT NULL,
      PRIMARY KEY(group_id, peer_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE group_messages (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      is_incoming INTEGER NOT NULL,
      read_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE message_reactions (
      id TEXT NOT NULL,
      message_id TEXT NOT NULL,
      sender_peer_id TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      removed_at TEXT,
      PRIMARY KEY(message_id, sender_peer_id)
    )
  ''');
}
