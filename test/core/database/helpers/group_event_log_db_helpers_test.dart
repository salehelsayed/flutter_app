import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/060_group_event_log.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupEventLogMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('canonical payload ordering is deterministic', () {
    final first = canonicalizeGroupEventLogPayload({
      'z': 1,
      'a': {'b': 2, 'a': 1},
    });
    final second = canonicalizeGroupEventLogPayload({
      'a': {'a': 1, 'b': 2},
      'z': 1,
    });

    expect(first, second);
    expect(jsonDecode(first), {
      'a': {'a': 1, 'b': 2},
      'z': 1,
    });
  });

  test('appends entries with per-group hash chain', () async {
    final first = await dbAppendGroupEventLogEntry(
      db,
      groupId: 'group-1',
      eventType: 'message',
      sourcePeerId: 'peer-a',
      sourceEventId: 'msg-1',
      sourceTimestamp: '2026-04-30T12:00:00.000Z',
      payload: {'messageId': 'msg-1', 'text': 'hello'},
      createdAt: DateTime.utc(2026, 4, 30, 12, 0, 1),
    );
    final second = await dbAppendGroupEventLogEntry(
      db,
      groupId: 'group-1',
      eventType: 'member_removed',
      sourcePeerId: 'peer-admin',
      sourceEventId: 'sys-1',
      sourceTimestamp: '2026-04-30T12:01:00.000Z',
      payload: {'removedPeerId': 'peer-b'},
      createdAt: DateTime.utc(2026, 4, 30, 12, 1, 1),
    );

    expect(first['sequence'], 1);
    expect(first['previous_entry_hash'], isNull);
    expect(second['sequence'], 2);
    expect(second['previous_entry_hash'], first['entry_hash']);
    expect(await dbVerifyGroupEventLogChain(db), isEmpty);
  });

  test(
    'exact duplicate replay is idempotent but changed replay fails',
    () async {
      final first = await dbAppendGroupEventLogEntry(
        db,
        groupId: 'group-1',
        eventType: 'message',
        sourcePeerId: 'peer-a',
        sourceEventId: 'msg-1',
        sourceTimestamp: '2026-04-30T12:00:00.000Z',
        payload: {'messageId': 'msg-1', 'text': 'hello'},
        createdAt: DateTime.utc(2026, 4, 30, 12),
      );
      final duplicate = await dbAppendGroupEventLogEntry(
        db,
        groupId: 'group-1',
        eventType: 'message',
        sourcePeerId: 'peer-a',
        sourceEventId: 'msg-1',
        sourceTimestamp: '2026-04-30T12:00:00.000Z',
        payload: {'text': 'hello', 'messageId': 'msg-1'},
        createdAt: DateTime.utc(2026, 4, 30, 13),
      );

      expect(duplicate['id'], first['id']);
      expect(await dbLoadGroupEventLogEntries(db, 'group-1'), hasLength(1));

      expect(
        () => dbAppendGroupEventLogEntry(
          db,
          groupId: 'group-1',
          eventType: 'message',
          sourcePeerId: 'peer-a',
          sourceEventId: 'msg-1',
          sourceTimestamp: '2026-04-30T12:00:00.000Z',
          payload: {'messageId': 'msg-1', 'text': 'tampered'},
        ),
        throwsA(isA<GroupEventLogTamperException>()),
      );
    },
  );

  test('chain verification detects row tampering', () async {
    await dbAppendGroupEventLogEntry(
      db,
      groupId: 'group-1',
      eventType: 'message',
      sourcePeerId: 'peer-a',
      sourceEventId: 'msg-1',
      sourceTimestamp: '2026-04-30T12:00:00.000Z',
      payload: {'messageId': 'msg-1', 'text': 'hello'},
      createdAt: DateTime.utc(2026, 4, 30, 12),
    );

    await db.update(
      'group_event_log',
      {'canonical_payload': '{"messageId":"msg-1","text":"changed"}'},
      where: 'source_event_id = ?',
      whereArgs: ['msg-1'],
    );

    final violations = await dbVerifyGroupEventLogChain(db);
    expect(violations, hasLength(1));
    expect(violations.single.reason, 'entry_hash_mismatch');
  });

  test(
    'PREREQ-SIGNED-COMMIT-AUDIT detects conflicting signed transition forks without leaking secrets',
    () async {
      final signedPayload = canonicalizeGroupEventLogPayload({
        'schemaVersion': 1,
        'transitionType': 'member_role_updated',
        'groupId': 'group-1',
        'sourceEventId': 'role-transition-1',
        'eventAt': '2026-05-01T12:00:00.000Z',
        'actor': {'peerId': 'peer-admin', 'signingPublicKey': 'pk-admin'},
        'transitionSubject': {
          'member': {'peerId': 'peer-bob', 'role': 'admin'},
        },
        'preTransitionStateHash': 'pre-state-hash',
        'transitionOutputHash': 'post-state-hash',
      });
      final audit = {
        'schemaVersion': 1,
        'transitionType': 'member_role_updated',
        'groupId': 'group-1',
        'sourceEventId': 'role-transition-1',
        'eventAt': '2026-05-01T12:00:00.000Z',
        'signatureAlgorithm': 'ed25519',
        'signedPayload': signedPayload,
        'signature': 'raw-signature-secret',
      };

      await dbAppendGroupEventLogEntry(
        db,
        groupId: 'group-1',
        eventType: 'member_role_updated',
        sourcePeerId: 'peer-admin',
        sourceEventId: 'role-transition-1',
        sourceTimestamp: '2026-05-01T12:00:00.000Z',
        payload: {'groupId': 'group-1', 'signedTransitionAudit': audit},
      );

      await expectLater(
        () => dbAppendGroupEventLogEntry(
          db,
          groupId: 'group-1',
          eventType: 'member_role_updated',
          sourcePeerId: 'peer-admin',
          sourceEventId: 'role-transition-1',
          sourceTimestamp: '2026-05-01T12:00:00.000Z',
          payload: {
            'groupId': 'group-1',
            'signedTransitionAudit': {
              ...audit,
              'signedPayload': signedPayload.replaceAll(
                'peer-bob',
                'peer-carol',
              ),
            },
          },
        ),
        throwsA(
          isA<GroupEventLogTamperException>()
              .having(
                (error) => error.message,
                'message',
                contains('conflicting_replay'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('raw-signature-secret')),
              ),
        ),
      );
    },
  );

  test(
    'Plan 363 audit exact and bounded authority loaders preserve microsecond order',
    () async {
      for (final (id, timestamp) in <(String, String)>[
        ('pga1:c:a', '2026-08-13T12:00:00.000000Z'),
        ('pga1:c:b', '2026-08-13T12:00:00.000001Z'),
        ('pga1:c:c', '2026-08-13T12:00:00.001000Z'),
      ]) {
        await dbAppendGroupEventLogEntry(
          db,
          groupId: 'group-authority-history',
          eventType: 'protected_authority_complete',
          sourcePeerId: 'peer-admin',
          sourceEventId: id,
          sourceTimestamp: timestamp,
          payload: <String, Object?>{'proof': id},
        );
      }

      expect(
        (await dbLoadGroupEventLogEntryExact(
          db,
          groupId: 'group-authority-history',
          sourceEventId: 'pga1:c:b',
        ))?['source_timestamp'],
        '2026-08-13T12:00:00.000001Z',
      );
      final firstPage = await dbLoadGroupEventLogTypePage(
        db,
        groupId: 'group-authority-history',
        eventType: 'protected_authority_complete',
        limit: 2,
      );
      expect(firstPage.map((row) => row['source_event_id']), <Object?>[
        'pga1:c:a',
        'pga1:c:b',
      ]);
      final secondPage = await dbLoadGroupEventLogTypePage(
        db,
        groupId: 'group-authority-history',
        eventType: 'protected_authority_complete',
        afterSourceTimestamp: firstPage.last['source_timestamp'] as String,
        afterSourceEventId: firstPage.last['source_event_id'] as String,
        limit: 2,
      );
      expect(secondPage.map((row) => row['source_event_id']), <Object?>[
        'pga1:c:c',
      ]);
    },
  );
}
