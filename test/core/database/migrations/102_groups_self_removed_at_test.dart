// ignore_for_file: file_names

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/102_groups_self_removed_at.dart';
import 'package:flutter_app/core/database/migrations/104_group_exit_diagnostics.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _at = '2026-07-20T12:00:00.000Z';

Map<String, Object?> _group(
  String id, {
  bool dissolved = false,
  String? membershipAt,
}) => <String, Object?>{
  'id': id,
  'name': id,
  'type': 'chat',
  'topic_name': 'topic-$id',
  'created_at': _at,
  'created_by': 'peer-admin',
  'my_role': 'member',
  'is_dissolved': dissolved ? 1 : 0,
  'last_membership_event_at': membershipAt,
};

Map<String, Object?> _member(String groupId, String peerId) =>
    <String, Object?>{
      'group_id': groupId,
      'peer_id': peerId,
      'username': peerId,
      'role': 'writer',
      'joined_at': _at,
    };

Future<void> _seedPendingWork(Database db, String groupId) async {
  await db.insert('group_rejoin_state', {
    'group_id': groupId,
    'rejoin_attempt_count': 2,
    'next_eligible_at': 123,
  });
  await db.insert('pending_group_broadcasts', {
    'id': 'broadcast-$groupId',
    'group_id': groupId,
    'kind': 'member_role_updated',
    'sys_text': '{}',
    'recipient_peer_ids': '[]',
    'event_at': _at,
    'source_message_id': 'source-$groupId',
    'created_at': _at,
    'updated_at': _at,
  });
  await db.insert('group_pending_key_repairs', {
    'id': 'repair-$groupId',
    'group_id': groupId,
    'message_id': 'repair-message-$groupId',
    'payload_type': 'group_message',
    'key_epoch': 1,
    'created_at': _at,
    'updated_at': _at,
  });
  await db.insert('group_pending_key_distributions', {
    'id': 'distribution-$groupId',
    'group_id': groupId,
    'peer_id': 'peer-member',
    'key_epoch': 1,
    'created_at': _at,
    'updated_at': _at,
  });
  await db.insert('group_pending_membership_messages', {
    'id': 'membership-$groupId',
    'group_id': groupId,
    'sender_peer_id': 'peer-admin',
    'message_id': 'membership-message-$groupId',
    'payload_json': '{}',
    'received_at': _at,
    'created_at': _at,
    'updated_at': _at,
  });
  await db.insert('group_history_gap_repairs', {
    'group_id': groupId,
    'gap_id': 'gap-$groupId',
    'missing_after_message_id': 'before',
    'missing_before_message_id': 'after',
    'expected_range_hash': 'hash',
    'expected_head_message_id': 'head',
    'created_at': _at,
    'updated_at': _at,
  });
  await db.insert('group_pending_reactions', {
    'id': 'pending-reaction-$groupId',
    'group_id': groupId,
    'message_id': 'reaction-parent-$groupId',
    'sender_peer_id': 'peer-member',
    'reaction_json': '{}',
    'received_at': _at,
    'created_at': _at,
    'updated_at': _at,
  });
  await db.insert('pending_sibling_devices', {
    'group_id': groupId,
    'member_peer_id': 'peer-self',
    'device_id': 'device-2',
    'transport_peer_id': 'transport-2',
    'device_signing_public_key': 'signing-key',
    'verified_account_signing_public_key': 'account-key',
    'announced_at': _at,
  });
  await db.insert('group_reaction_replay_outbox', {
    'reaction_id': 'replay-$groupId',
    'group_id': groupId,
    'message_id': 'reaction-parent-$groupId',
    'sender_peer_id': 'peer-member',
    'emoji': '👍',
    'action': 'add',
    'inbox_retry_payload': '{}',
    'delivery_status': 'failed',
    'created_at': _at,
    'updated_at': _at,
  });
}

Future<void> _insertMessage(
  Database db, {
  required String id,
  required String groupId,
  required String status,
  bool incoming = false,
  String? wireEnvelope,
  String? inboxRetryPayload,
  int? nextEligibleAt,
}) => db.insert('group_messages', {
  'id': id,
  'group_id': groupId,
  'sender_peer_id': incoming ? 'peer-admin' : 'peer-self',
  'text': 'visible-$id',
  'timestamp': _at,
  'status': status,
  'is_incoming': incoming ? 1 : 0,
  'created_at': _at,
  'wire_envelope': wireEnvelope,
  'inbox_stored': 0,
  'inbox_retry_payload': inboxRetryPayload,
  'retry_attempt_count': 2,
  'next_eligible_at': nextEligibleAt,
});

Future<void> _insertPendingUpload(
  Database db, {
  required String id,
  required String messageId,
  String ownerLane = 'group',
}) => db.insert('media_attachments', {
  'id': id,
  'message_id': messageId,
  'mime': 'image/jpeg',
  'size': 1,
  'media_type': 'image',
  'download_status': 'upload_pending',
  'created_at': _at,
  'owner_lane': ownerLane,
});

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'v102 adds nullable authority and null-only backfills structural shells including preserved pending invites',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await runProductionOnCreate(db, 101);
      await db.insert('identity', {
        'id': 1,
        'peer_id': 'peer-self',
        'public_key': '',
        'private_key': null,
        'mnemonic12': null,
        'username': 'Self',
        'created_at': _at,
        'updated_at': _at,
      });

      await db.insert(
        'groups',
        _group('shell', membershipAt: '2026-07-20T13:00:00.000Z'),
      );
      await db.insert('groups', _group('self-present'));
      await db.insert('group_members', _member('self-present', 'peer-self'));
      await db.insert('groups', _group('key-present'));
      await db.insert('group_keys', {
        'group_id': 'key-present',
        'key_generation': 1,
        'encrypted_key': 'key',
        'created_at': _at,
      });
      await db.insert('groups', _group('dissolved', dissolved: true));

      await db.insert('pending_group_invites', {
        'group_id': 'shell',
        'invite_id': 'invite-shell',
        'payload_json': '{"preserve":true}',
        'group_name': 'Shell',
        'group_type': 'chat',
        'sender_peer_id': 'peer-admin',
        'sender_username': 'Admin',
        'created_by': 'peer-admin',
        'created_at': _at,
        'received_at': _at,
        'expires_at': '2026-08-20T12:00:00.000Z',
      });
      await db.insert('group_event_log', {
        'id': 'evidence-shell',
        'group_id': 'shell',
        'sequence': 1,
        'event_type': 'member_removed',
        'source_peer_id': 'peer-admin',
        'source_event_id': 'removal-shell',
        'source_timestamp': _at,
        'canonical_payload': '{}',
        'entry_hash': 'evidence-hash',
        'created_at': _at,
      });
      const terminalMessageIds = <String>[
        'outgoing-sending',
        'outgoing-pending',
        'outgoing-failed',
        'outgoing-queued-offline',
        'outgoing-send-failed-payload',
        'outgoing-sent-repush',
      ];
      const terminalStatuses = <String>[
        'sending',
        'pending',
        'failed',
        'queued_offline',
        'send_failed',
        'sent',
      ];
      for (var index = 0; index < terminalMessageIds.length; index++) {
        final id = terminalMessageIds[index];
        await _insertMessage(
          db,
          id: id,
          groupId: 'shell',
          status: terminalStatuses[index],
          wireEnvelope: index == 5 ? null : '{"wire":"$id"}',
          inboxRetryPayload: index == 0 ? null : '{"retry":"$id"}',
          nextEligibleAt: 900 + index,
        );
        await _insertPendingUpload(db, id: 'upload-$id', messageId: id);
      }

      // These rows deliberately look similar but are outside the outgoing
      // membership-instance work predicate and must remain byte-identical.
      await _insertMessage(
        db,
        id: 'outgoing-sent-clean',
        groupId: 'shell',
        status: 'sent',
      );
      await _insertPendingUpload(
        db,
        id: 'upload-outgoing-sent-clean',
        messageId: 'outgoing-sent-clean',
      );
      await _insertMessage(
        db,
        id: 'incoming-pending',
        groupId: 'shell',
        status: 'pending',
        incoming: true,
        wireEnvelope: '{"incoming":true}',
        inboxRetryPayload: '{"incomingRetry":true}',
        nextEligibleAt: 111,
      );
      await _insertPendingUpload(
        db,
        id: 'upload-incoming-pending',
        messageId: 'incoming-pending',
      );
      await _insertMessage(
        db,
        id: 'active-outgoing',
        groupId: 'self-present',
        status: 'queued_offline',
        wireEnvelope: '{"active":true}',
        inboxRetryPayload: '{"activeRetry":true}',
        nextEligibleAt: 222,
      );
      await _insertPendingUpload(
        db,
        id: 'upload-active-outgoing',
        messageId: 'active-outgoing',
      );
      final preservedMessagesBefore = <String, Map<String, Object?>>{
        for (final id in const [
          'outgoing-sent-clean',
          'incoming-pending',
          'active-outgoing',
        ])
          id: (await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: [id],
          )).single,
      };
      final preservedUploadsBefore = <String, Map<String, Object?>>{
        for (final id in const [
          'upload-incoming-pending',
          'upload-active-outgoing',
        ])
          id: (await db.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: [id],
          )).single,
      };
      await _seedPendingWork(db, 'shell');
      await db.insert('group_reaction_replay_outbox', {
        'reaction_id': 'stored-replay-shell',
        'group_id': 'shell',
        'message_id': 'reaction-parent-shell',
        'sender_peer_id': 'peer-member',
        'emoji': '👍',
        'action': 'add',
        'inbox_retry_payload': '{}',
        'delivery_status': 'stored',
        'created_at': _at,
        'updated_at': _at,
      });

      await runProductionOnUpgrade(db, 101, 102);

      expect(currentIdentityDatabaseVersion, 104);
      for (final registry in <List<ProductionMigrationEntry>>[
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        final index101 = registry.indexWhere((entry) => entry.version == 101);
        final index102 = registry.indexWhere((entry) => entry.version == 102);
        final index103 = registry.indexWhere((entry) => entry.version == 103);
        final index104 = registry.indexWhere((entry) => entry.version == 104);
        expect(index102, index101 + 1);
        expect(index103, index102 + 1);
        expect(index104, index103 + 1);
        expect(index104, registry.length - 1);
        expect(registry[index102].name, '102_groups_self_removed_at');
        expect(registry[index102].run, same(runGroupsSelfRemovedAtMigration));
        expect(registry[index104].name, '104_group_exit_diagnostics');
        expect(registry[index104].run, same(runGroupExitDiagnosticsMigration));
      }

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final markerColumn = columns.singleWhere(
        (row) => row['name'] == 'self_removed_at',
      );
      expect(markerColumn['type'], 'TEXT');
      expect(markerColumn['notnull'], 0);
      expect(markerColumn['dflt_value'], isNull);

      Future<Object?> marker(String id) async => (await db.query(
        'groups',
        columns: const ['self_removed_at'],
        where: 'id = ?',
        whereArgs: [id],
      )).single['self_removed_at'];
      expect(await marker('shell'), '2026-07-20T13:00:00.000Z');
      expect(await marker('self-present'), isNull);
      expect(await marker('key-present'), isNull);
      expect(await marker('dissolved'), isNull);

      expect(
        (await db.query('pending_group_invites')).single['payload_json'],
        '{"preserve":true}',
      );
      expect(await db.query('group_event_log'), hasLength(1));
      for (final id in terminalMessageIds) {
        final outgoing = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: [id],
        )).single;
        expect(outgoing['text'], 'visible-$id', reason: id);
        expect(outgoing['status'], 'send_failed', reason: id);
        expect(outgoing['wire_envelope'], isNull, reason: id);
        expect(outgoing['inbox_retry_payload'], isNull, reason: id);
        expect(outgoing['next_eligible_at'], isNull, reason: id);
        expect(outgoing['retry_attempt_count'], 2, reason: id);
        expect(
          (await db.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: ['upload-$id'],
          )).single['download_status'],
          'upload_failed',
          reason: id,
        );
      }
      // Upload work belongs to the old outgoing membership instance even
      // when its otherwise-clean visible parent is already `sent`.
      expect(
        (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['upload-outgoing-sent-clean'],
        )).single['download_status'],
        'upload_failed',
      );
      for (final entry in preservedMessagesBefore.entries) {
        expect(
          (await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: [entry.key],
          )).single,
          entry.value,
          reason: entry.key,
        );
      }
      for (final entry in preservedUploadsBefore.entries) {
        expect(
          (await db.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: [entry.key],
          )).single,
          entry.value,
          reason: entry.key,
        );
      }
      for (final table in const [
        'group_rejoin_state',
        'pending_group_broadcasts',
        'group_pending_key_repairs',
        'group_pending_key_distributions',
        'group_pending_membership_messages',
        'group_history_gap_repairs',
        'group_pending_reactions',
        'pending_sibling_devices',
      ]) {
        expect(
          await db.query(table, where: 'group_id = ?', whereArgs: ['shell']),
          isEmpty,
          reason: table,
        );
      }
      expect(
        await db.query(
          'group_reaction_replay_outbox',
          where: 'group_id = ?',
          whereArgs: ['shell'],
        ),
        [containsPair('delivery_status', 'stored')],
      );

      const protectedMarker = '2026-07-19T10:00:00.000Z';
      await db.update(
        'groups',
        const {'self_removed_at': protectedMarker},
        where: 'id = ?',
        whereArgs: ['shell'],
      );
      await _seedPendingWork(db, 'shell');
      await runGroupsSelfRemovedAtMigration(db);
      await runGroupsSelfRemovedAtMigration(db);
      expect(await marker('shell'), protectedMarker);
      expect(
        await db.query(
          'group_rejoin_state',
          where: 'group_id = ?',
          whereArgs: ['shell'],
        ),
        isEmpty,
      );

      await db.delete('identity', where: 'id = 1');
      await db.insert('groups', _group('missing-identity'));
      await runGroupsSelfRemovedAtMigration(db);
      expect(await marker('missing-identity'), isNull);
      await db.insert('identity', {
        'id': 1,
        'peer_id': '   ',
        'public_key': '',
        'private_key': null,
        'mnemonic12': null,
        'username': 'Self',
        'created_at': _at,
        'updated_at': _at,
      });
      await db.insert('groups', _group('blank-identity'));
      await runGroupsSelfRemovedAtMigration(db);
      expect(await marker('blank-identity'), isNull);
    },
  );

  test(
    'v102 rerun preserves a distinct premarked authority while terminalizing its old work',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await runProductionOnCreate(db, 101);
      await db.execute('ALTER TABLE groups ADD COLUMN self_removed_at TEXT');
      await db.insert('identity', {
        'id': 1,
        'peer_id': 'peer-self',
        'public_key': '',
        'private_key': null,
        'mnemonic12': null,
        'username': 'Self',
        'created_at': _at,
        'updated_at': _at,
      });
      const protectedMarker = '2026-07-19T10:00:00.000Z';
      await db.insert('groups', {
        ..._group('premarked'),
        'self_removed_at': protectedMarker,
      });
      await _insertMessage(
        db,
        id: 'premarked-repush',
        groupId: 'premarked',
        status: 'sent',
        inboxRetryPayload: '{"retry":true}',
        nextEligibleAt: 777,
      );
      await _insertPendingUpload(
        db,
        id: 'premarked-upload',
        messageId: 'premarked-repush',
      );
      await _seedPendingWork(db, 'premarked');

      await runGroupsSelfRemovedAtMigration(db);
      await runGroupsSelfRemovedAtMigration(db);

      final group = (await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['premarked'],
      )).single;
      expect(group['self_removed_at'], protectedMarker);
      final message = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['premarked-repush'],
      )).single;
      expect(message['status'], 'send_failed');
      expect(message['wire_envelope'], isNull);
      expect(message['inbox_retry_payload'], isNull);
      expect(message['next_eligible_at'], isNull);
      expect(
        (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['premarked-upload'],
        )).single['download_status'],
        'upload_failed',
      );
      for (final table in const [
        'group_rejoin_state',
        'pending_group_broadcasts',
        'group_pending_key_repairs',
        'group_pending_key_distributions',
        'group_pending_membership_messages',
        'group_history_gap_repairs',
        'group_pending_reactions',
        'pending_sibling_devices',
        'group_reaction_replay_outbox',
      ]) {
        expect(
          await db.query(
            table,
            where: 'group_id = ?',
            whereArgs: ['premarked'],
          ),
          isEmpty,
          reason: table,
        );
      }
    },
  );
}
