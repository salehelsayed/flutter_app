import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/041_group_message_reliability_columns.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupMessagesTablesMigration(db);
    await runGroupQuotedMessageIdMigration(db);
    await runGroupMessageReliabilityColumnsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeRow({
    required String id,
    required String status,
    required int isIncoming,
    required String timestamp,
  }) {
    return {
      'id': id,
      'group_id': 'group-1',
      'sender_peer_id': 'peer-me',
      'sender_username': 'Alice',
      'text': 'Hello group',
      'timestamp': timestamp,
      'quoted_message_id': null,
      'key_generation': 0,
      'status': status,
      'is_incoming': isIncoming,
      'read_at': null,
      'created_at': timestamp,
      'wire_envelope': null,
      'inbox_stored': 0,
      'inbox_retry_payload': null,
    };
  }

  test('dbTransitionGroupSendingToFailed bulk transitions outgoing rows', () async {
    final oldTs = '2026-01-01T00:00:00.000Z';
    await dbInsertGroupMessage(
      db,
      makeRow(
        id: 'sending-1',
        status: 'sending',
        isIncoming: 0,
        timestamp: oldTs,
      ),
    );
    await dbInsertGroupMessage(
      db,
      makeRow(
        id: 'sending-2',
        status: 'sending',
        isIncoming: 0,
        timestamp: oldTs,
      ),
    );
    await dbInsertGroupMessage(
      db,
      makeRow(
        id: 'sending-3',
        status: 'sending',
        isIncoming: 0,
        timestamp: oldTs,
      ),
    );
    await dbInsertGroupMessage(
      db,
      makeRow(
        id: 'sent-1',
        status: 'sent',
        isIncoming: 0,
        timestamp: oldTs,
      ),
    );
    await dbInsertGroupMessage(
      db,
      makeRow(
        id: 'sent-2',
        status: 'sent',
        isIncoming: 0,
        timestamp: oldTs,
      ),
    );
    await dbInsertGroupMessage(
      db,
      makeRow(
        id: 'incoming-sending',
        status: 'sending',
        isIncoming: 1,
        timestamp: oldTs,
      ),
    );

    final count = await dbTransitionGroupSendingToFailed(db);

    expect(count, 3);
    final rows = await db.query(
      'group_messages',
      where: 'id IN (?, ?, ?, ?, ?, ?)',
      whereArgs: [
        'sending-1',
        'sending-2',
        'sending-3',
        'sent-1',
        'sent-2',
        'incoming-sending',
      ],
      orderBy: 'id ASC',
    );
    final statusesById = {
      for (final row in rows) row['id'] as String: row['status'] as String,
    };
    expect(statusesById['sending-1'], 'failed');
    expect(statusesById['sending-2'], 'failed');
    expect(statusesById['sending-3'], 'failed');
    expect(statusesById['sent-1'], 'sent');
    expect(statusesById['sent-2'], 'sent');
    expect(statusesById['incoming-sending'], 'sending');
  });
}
