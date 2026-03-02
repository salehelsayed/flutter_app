import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupMessagesTablesMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeKeyRow({
    String groupId = 'group-1',
    int keyGeneration = 1,
    String encryptedKey = 'base64-key-gen1',
    String createdAt = '2026-01-15T12:00:00.000Z',
  }) {
    return {
      'group_id': groupId,
      'key_generation': keyGeneration,
      'encrypted_key': encryptedKey,
      'created_at': createdAt,
    };
  }

  group('dbInsertGroupKey', () {
    test('inserts a new key', () async {
      await dbInsertGroupKey(db, makeKeyRow());

      final rows = await db.query('group_keys');
      expect(rows.length, 1);
      expect(rows[0]['key_generation'], 1);
      expect(rows[0]['encrypted_key'], 'base64-key-gen1');
    });
  });

  group('dbLoadLatestGroupKey', () {
    test('returns null when no keys exist', () async {
      final result = await dbLoadLatestGroupKey(db, 'group-1');
      expect(result, isNull);
    });

    test('returns the highest generation key', () async {
      await dbInsertGroupKey(db, makeKeyRow(keyGeneration: 1));
      await dbInsertGroupKey(db, makeKeyRow(
        keyGeneration: 3,
        encryptedKey: 'key-gen3',
      ));
      await dbInsertGroupKey(db, makeKeyRow(
        keyGeneration: 2,
        encryptedKey: 'key-gen2',
      ));

      final result = await dbLoadLatestGroupKey(db, 'group-1');
      expect(result, isNotNull);
      expect(result!['key_generation'], 3);
      expect(result['encrypted_key'], 'key-gen3');
    });
  });

  group('dbLoadGroupKeyByGeneration', () {
    test('returns null for non-existent generation', () async {
      final result = await dbLoadGroupKeyByGeneration(db, 'group-1', 99);
      expect(result, isNull);
    });

    test('returns the key for the given generation', () async {
      await dbInsertGroupKey(db, makeKeyRow(keyGeneration: 1));
      await dbInsertGroupKey(db, makeKeyRow(
        keyGeneration: 2,
        encryptedKey: 'key-gen2',
      ));

      final result = await dbLoadGroupKeyByGeneration(db, 'group-1', 2);
      expect(result, isNotNull);
      expect(result!['encrypted_key'], 'key-gen2');
    });
  });

  group('dbLoadAllGroupKeys', () {
    test('returns all keys ordered by generation ASC', () async {
      await dbInsertGroupKey(db, makeKeyRow(keyGeneration: 3));
      await dbInsertGroupKey(db, makeKeyRow(keyGeneration: 1));
      await dbInsertGroupKey(db, makeKeyRow(keyGeneration: 2));

      final results = await dbLoadAllGroupKeys(db, 'group-1');
      expect(results.length, 3);
      expect(results[0]['key_generation'], 1);
      expect(results[1]['key_generation'], 2);
      expect(results[2]['key_generation'], 3);
    });
  });

  group('dbDeleteAllGroupKeys', () {
    test('deletes all keys for a group', () async {
      await dbInsertGroupKey(db, makeKeyRow(keyGeneration: 1));
      await dbInsertGroupKey(db, makeKeyRow(keyGeneration: 2));
      await dbInsertGroupKey(db, makeKeyRow(
        groupId: 'group-2',
        keyGeneration: 1,
      ));

      await dbDeleteAllGroupKeys(db, 'group-1');

      final g1Keys = await dbLoadAllGroupKeys(db, 'group-1');
      final g2Keys = await dbLoadAllGroupKeys(db, 'group-2');
      expect(g1Keys, isEmpty);
      expect(g2Keys.length, 1);
    });
  });
}
