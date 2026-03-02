import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupsTablesMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeGroupRow({
    String id = 'group-1',
    String name = 'Test Group',
    String type = 'chat',
    String topicName = '/mknoon/groups/group-1',
    String? description = 'A test group',
    String createdAt = '2026-01-15T12:00:00.000Z',
    String createdBy = 'peer-creator',
    String myRole = 'admin',
    int isArchived = 0,
    String? archivedAt,
  }) {
    return {
      'id': id,
      'name': name,
      'type': type,
      'topic_name': topicName,
      'description': description,
      'created_at': createdAt,
      'created_by': createdBy,
      'my_role': myRole,
      'is_archived': isArchived,
      'archived_at': archivedAt,
    };
  }

  group('dbInsertGroup', () {
    test('inserts a new group', () async {
      await dbInsertGroup(db, makeGroupRow());

      final rows = await db.query('groups');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'group-1');
      expect(rows[0]['name'], 'Test Group');
    });
  });

  group('dbLoadAllGroups', () {
    test('returns all groups ordered by created_at DESC', () async {
      await dbInsertGroup(db, makeGroupRow(
        id: 'g1',
        topicName: '/t/1',
        createdAt: '2026-01-01T00:00:00.000Z',
      ));
      await dbInsertGroup(db, makeGroupRow(
        id: 'g2',
        topicName: '/t/2',
        createdAt: '2026-01-02T00:00:00.000Z',
      ));

      final results = await dbLoadAllGroups(db);
      expect(results.length, 2);
      expect(results[0]['id'], 'g2');
      expect(results[1]['id'], 'g1');
    });
  });

  group('dbLoadGroup', () {
    test('returns null for non-existent group', () async {
      final result = await dbLoadGroup(db, 'non-existent');
      expect(result, isNull);
    });

    test('returns group when it exists', () async {
      await dbInsertGroup(db, makeGroupRow());

      final result = await dbLoadGroup(db, 'group-1');
      expect(result, isNotNull);
      expect(result!['name'], 'Test Group');
    });
  });

  group('dbUpdateGroup', () {
    test('updates group fields', () async {
      await dbInsertGroup(db, makeGroupRow());

      await dbUpdateGroup(db, makeGroupRow(name: 'Updated Name'));

      final result = await dbLoadGroup(db, 'group-1');
      expect(result!['name'], 'Updated Name');
    });
  });

  group('dbDeleteGroup', () {
    test('deletes a group', () async {
      await dbInsertGroup(db, makeGroupRow());

      await dbDeleteGroup(db, 'group-1');

      final result = await dbLoadGroup(db, 'group-1');
      expect(result, isNull);
    });
  });

  group('dbCountGroups', () {
    test('returns correct count', () async {
      expect(await dbCountGroups(db), 0);

      await dbInsertGroup(db, makeGroupRow(id: 'g1', topicName: '/t/1'));
      await dbInsertGroup(db, makeGroupRow(id: 'g2', topicName: '/t/2'));

      expect(await dbCountGroups(db), 2);
    });
  });

  group('dbArchiveGroup', () {
    test('sets is_archived to 1 and sets archived_at', () async {
      await dbInsertGroup(db, makeGroupRow());

      await dbArchiveGroup(db, 'group-1');

      final result = await dbLoadGroup(db, 'group-1');
      expect(result!['is_archived'], 1);
      expect(result['archived_at'], isNotNull);
    });
  });

  group('dbUnarchiveGroup', () {
    test('sets is_archived to 0 and clears archived_at', () async {
      await dbInsertGroup(db, makeGroupRow(
        isArchived: 1,
        archivedAt: '2026-01-15T12:00:00.000Z',
      ));

      await dbUnarchiveGroup(db, 'group-1');

      final result = await dbLoadGroup(db, 'group-1');
      expect(result!['is_archived'], 0);
      expect(result['archived_at'], isNull);
    });
  });

  group('dbLoadActiveGroups', () {
    test('returns only non-archived groups', () async {
      await dbInsertGroup(db, makeGroupRow(
        id: 'active',
        topicName: '/t/active',
        isArchived: 0,
      ));
      await dbInsertGroup(db, makeGroupRow(
        id: 'archived',
        topicName: '/t/archived',
        isArchived: 1,
        archivedAt: '2026-01-15T12:00:00.000Z',
      ));

      final results = await dbLoadActiveGroups(db);
      expect(results.length, 1);
      expect(results[0]['id'], 'active');
    });
  });
}
