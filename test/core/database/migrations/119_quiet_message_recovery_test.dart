import 'dart:io';

import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/045_inbox_staging_entries.dart';
import 'package:flutter_app/core/database/migrations/119_quiet_message_recovery.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late Database database;
  const timestamp = '2026-09-09T09:28:00.000Z';
  const row = <String, Object?>{
    'id': 'old-pending',
    'contact_peer_id': 'friend',
    'sender_peer_id': 'friend',
    'text': 'original content',
    'timestamp': timestamp,
    'created_at': timestamp,
    'is_incoming': 1,
    'status': 'delivered',
    'read_at': null,
  };
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quiet-recovery-');
    database = await databaseFactoryFfi.openDatabase('${directory.path}/db');
    await database.execute('''CREATE TABLE messages (
      id TEXT PRIMARY KEY, contact_peer_id TEXT, sender_peer_id TEXT,
      text TEXT, timestamp TEXT, created_at TEXT, is_incoming INTEGER,
      status TEXT, read_at TEXT
    )''');
    await runInboxStagingEntriesMigration(database);
    await database.insert('messages', row);
    await runQuietMessageRecoveryMigration(database);
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'upgrade preserves existing unread state and quiet staging survives restart',
    () async {
      await runQuietMessageRecoveryMigration(database);
      final old = (await database.query('messages')).single;
      expect(old, {...row, 'quiet_recovery': 0});
      const entry = InboxStagingEntry(
        entryId: 'relay-entry',
        ownerPeerId: 'self',
        senderPeerId: 'friend',
        relayTimestamp: '2026-09-12T09:50:27.000Z',
        envelope: 'exact original encrypted bytes',
        stagedAt: timestamp,
        quietRecovery: true,
      );
      await dbInsertInboxStagingEntry(database, entry.toMap());
      await dbInsertInboxStagingEntry(
        database,
        entry
            .copyWith(
              entryId: 'fresh-entry',
              envelope: 'fresh encrypted bytes',
              quietRecovery: false,
            )
            .toMap(),
      );
      await dbMarkIncomingQuietRecovery(database, row);
      await database.close();
      database = await databaseFactoryFfi.openDatabase('${directory.path}/db');
      final restored = (await dbLoadRecoverableInboxStagingEntries(
        database,
      )).map(InboxStagingEntry.fromMap).toList();
      expect(restored, hasLength(2));
      expect(
        restored
            .singleWhere((row) => row.entryId == 'fresh-entry')
            .quietRecovery,
        isFalse,
      );
      final recovered = restored
          .singleWhere((row) => row.entryId == entry.entryId)
          .toChatMessage()
          .copyWith(predecryptedText: 'plaintext');
      expect(recovered.quietRecovery, isTrue);
      expect(recovered.content, entry.envelope);
      final message = ConversationMessage.fromMap(
        (await database.query('messages')).single,
      );
      expect(message.quietRecovery, isTrue);
      expect(message.readAt, isNull);
      expect(message.timestamp, timestamp);
      expect(message.text, row['text']);
      expect(message.status, row['status']);
      // A delayed normal replica after process death retains both the staged
      // ACK owner and the canonical quiet disposition.
      await dbInsertInboxStagingEntry(
        database,
        entry.copyWith(quietRecovery: false).toMap(),
      );
      expect(
        (await dbLoadInboxStagingEntry(
          database,
          entry.entryId,
        ))!['quiet_recovery'],
        1,
      );
      expect((await database.query('messages')).single['quiet_recovery'], 1);
    },
  );

  test('quiet duplicate changes only exact staging authority', () async {
    const entry = InboxStagingEntry(
      entryId: 'relay-entry',
      ownerPeerId: 'self',
      senderPeerId: 'friend',
      relayTimestamp: timestamp,
      envelope: 'immutable',
      stagedAt: timestamp,
    );
    await dbInsertInboxStagingEntry(database, entry.toMap());
    await dbInsertInboxStagingEntry(
      database,
      entry.copyWith(senderPeerId: 'other', quietRecovery: true).toMap(),
    );
    expect(
      (await dbLoadInboxStagingEntry(
        database,
        entry.entryId,
      ))!['quiet_recovery'],
      0,
    );
    await dbInsertInboxStagingEntry(
      database,
      entry.copyWith(quietRecovery: true).toMap(),
    );
    final stored = (await dbLoadInboxStagingEntry(database, entry.entryId))!;
    expect(stored['quiet_recovery'], 1);
    expect(stored['envelope'], 'immutable');
    expect(stored['attempt_count'], 0);
    // A delayed normal copy cannot revoke the later quiet intent or change
    // the original row/ACK authority.
    await dbInsertInboxStagingEntry(database, entry.toMap());
    expect(await dbLoadInboxStagingEntry(database, entry.entryId), stored);
    await dbMarkIncomingQuietRecovery(database, {
      ...row,
      'sender_peer_id': 'other',
    });
    expect((await database.query('messages')).single['quiet_recovery'], 0);
  });
}
