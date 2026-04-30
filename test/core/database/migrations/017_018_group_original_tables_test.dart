import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> runOriginalGroupMigrations() async {
    await runGroupsTablesMigration(db);
    await runGroupMessagesTablesMigration(db);
  }

  Future<List<String>> tableNames() async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    return rows.map((row) => row['name'] as String).toList()..sort();
  }

  Future<List<String>> columnNames(String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toList();
  }

  Future<List<String>> indexNames(String table) async {
    final rows = await db.rawQuery('PRAGMA index_list($table)');
    return rows.map((row) => row['name'] as String).toList();
  }

  Map<String, Object?> baselineGroupRow({
    String id = 'group-1',
    String name = 'DB baseline',
    String type = 'chat',
    String topicName = '/mknoon/group/group-1',
    String myRole = 'admin',
  }) {
    return {
      'id': id,
      'name': name,
      'type': type,
      'topic_name': topicName,
      'created_at': '2026-04-30T10:00:00.000Z',
      'created_by': 'peer-a',
      'my_role': myRole,
    };
  }

  group('Migrations 017/018: original group tables', () {
    test('create baseline group tables, columns, defaults, and indexes',
        () async {
      await runOriginalGroupMigrations();

      expect(
        await tableNames(),
        containsAll([
          'groups',
          'group_members',
          'group_keys',
          'group_messages',
        ]),
      );

      expect(
        await columnNames('groups'),
        containsAll([
          'id',
          'name',
          'type',
          'topic_name',
          'description',
          'avatar_blob_id',
          'avatar_mime',
          'avatar_path',
          'created_at',
          'created_by',
          'my_role',
          'is_muted',
          'is_dissolved',
          'is_archived',
        ]),
      );
      expect(
        await columnNames('group_members'),
        containsAll([
          'group_id',
          'peer_id',
          'username',
          'role',
          'public_key',
          'ml_kem_public_key',
          'joined_at',
        ]),
      );
      expect(
        await columnNames('group_keys'),
        containsAll([
          'group_id',
          'key_generation',
          'encrypted_key',
          'created_at',
        ]),
      );
      expect(
        await columnNames('group_messages'),
        containsAll([
          'id',
          'group_id',
          'sender_peer_id',
          'sender_username',
          'text',
          'timestamp',
          'key_generation',
          'status',
          'is_incoming',
          'read_at',
          'created_at',
        ]),
      );

      expect(await indexNames('group_members'), contains('idx_group_members_group'));
      expect(
        await indexNames('group_messages'),
        containsAll(['idx_group_messages_group', 'idx_group_messages_ts']),
      );

      await db.insert('groups', baselineGroupRow());

      final groups = await db.query('groups', where: 'id = ?', whereArgs: ['group-1']);
      expect(groups.single['is_muted'], 0);
      expect(groups.single['is_dissolved'], 0);
      expect(groups.single['is_archived'], 0);
    });

    test('stores and reads baseline member, key, and message rows', () async {
      await runOriginalGroupMigrations();
      await db.insert('groups', baselineGroupRow());

      await db.insert('group_members', {
        'group_id': 'group-1',
        'peer_id': 'peer-a',
        'username': 'Alice',
        'role': 'admin',
        'public_key': 'ed25519-public',
        'ml_kem_public_key': 'mlkem-public',
        'joined_at': '2026-04-30T10:00:01.000Z',
      });
      await db.insert('group_keys', {
        'group_id': 'group-1',
        'key_generation': 1,
        'encrypted_key': 'encrypted-key',
        'created_at': '2026-04-30T10:00:02.000Z',
      });
      await db.insert('group_messages', {
        'id': 'msg-1',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-a',
        'sender_username': 'Alice',
        'text': 'hello',
        'timestamp': '2026-04-30T10:00:03.000Z',
        'created_at': '2026-04-30T10:00:03.000Z',
      });

      expect(
        (await db.query('group_members', where: 'peer_id = ?', whereArgs: ['peer-a']))
            .single['role'],
        'admin',
      );
      expect(
        (await db.query('group_keys', where: 'group_id = ?', whereArgs: ['group-1']))
            .single['key_generation'],
        1,
      );

      final messages = await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['msg-1'],
      );
      expect(messages.single['status'], 'sent');
      expect(messages.single['key_generation'], 0);
      expect(messages.single['is_incoming'], 1);
    });

    test('enforces original constraints and remains idempotent', () async {
      await runOriginalGroupMigrations();
      await db.insert('groups', baselineGroupRow());

      await expectLater(
        db.insert(
          'groups',
          baselineGroupRow(id: 'group-2', topicName: '/mknoon/group/group-1'),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert(
          'groups',
          baselineGroupRow(
            id: 'group-bad-type',
            topicName: '/mknoon/group/group-bad-type',
            type: 'broadcast',
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert(
          'groups',
          baselineGroupRow(
            id: 'group-bad-role',
            topicName: '/mknoon/group/group-bad-role',
            myRole: 'owner',
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );

      await db.insert('group_members', {
        'group_id': 'group-1',
        'peer_id': 'peer-a',
        'role': 'writer',
        'joined_at': '2026-04-30T10:01:00.000Z',
      });
      await expectLater(
        db.insert('group_members', {
          'group_id': 'group-1',
          'peer_id': 'peer-bad-role',
          'role': 'owner',
          'joined_at': '2026-04-30T10:01:01.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('group_members', {
          'group_id': 'group-1',
          'peer_id': 'peer-a',
          'role': 'reader',
          'joined_at': '2026-04-30T10:01:02.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );

      await db.insert('group_keys', {
        'group_id': 'group-1',
        'key_generation': 1,
        'encrypted_key': 'encrypted-key',
        'created_at': '2026-04-30T10:02:00.000Z',
      });
      await expectLater(
        db.insert('group_keys', {
          'group_id': 'group-1',
          'key_generation': 1,
          'encrypted_key': 'duplicate-key',
          'created_at': '2026-04-30T10:02:01.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );

      await runOriginalGroupMigrations();
      expect(await tableNames(), containsAll(['groups', 'group_members']));
      expect(await indexNames('group_messages'), contains('idx_group_messages_ts'));
    });
  });
}
