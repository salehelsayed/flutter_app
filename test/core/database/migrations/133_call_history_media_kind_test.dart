// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _legacyCallId = '11111111-1111-4111-8111-111111111111';
const _timestamp = '2026-11-23T10:00:00.000Z';

Map<String, Object?> _missedCall(String id) => {
  'call_id': id,
  'contact_account_peer_id': 'contact-a',
  'direction': 'incoming',
  'terminal_reason': 'no_answer',
  'status': 'missed',
  'started_at': _timestamp,
  'ended_at': _timestamp,
  'created_at': _timestamp,
  'updated_at': _timestamp,
  'read_at': _timestamp,
};

void main() {
  sqfliteFfiInit();
  const deadline = Duration(seconds: 3);

  Future<Database> open(String path, int version) => databaseFactoryFfiNoIsolate
      .openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      )
      .timeout(deadline);

  test('BL61 fresh schema accepts audio, video and unknown media', () async {
    final db = await open(inMemoryDatabasePath, currentIdentityDatabaseVersion);
    addTearDown(() => db.close().timeout(deadline));

    for (final (id, media) in [
      (_legacyCallId, 'audio'),
      ('22222222-2222-4222-8222-222222222222', 'video'),
      ('33333333-3333-4333-8333-333333333333', null),
    ]) {
      await db
          .insert(kCallHistoryTable, {..._missedCall(id), 'media_kind': media})
          .timeout(deadline);
    }

    final rows = await db
        .query(kCallHistoryTable, columns: ['media_kind'], orderBy: 'call_id')
        .timeout(deadline);
    expect(rows.map((row) => row['media_kind']), ['audio', 'video', null]);

    await expectLater(
      db
          .update(
            kCallHistoryTable,
            {'media_kind': 'screen'},
            where: 'call_id = ?',
            whereArgs: [_legacyCallId],
          )
          .timeout(deadline),
      throwsA(isA<DatabaseException>()),
    ).timeout(deadline);
  });

  test(
    'BL61 v132 upgrade preserves the read legacy row without a media type',
    () async {
      final directory = await Directory.systemTemp
          .createTemp('call-history-133-')
          .timeout(deadline);
      addTearDown(() => directory.delete(recursive: true).timeout(deadline));
      final path = '${directory.path}/history.sqlite';
      final prior = await open(path, 132);
      addTearDown(() async {
        if (prior.isOpen) await prior.close().timeout(deadline);
      });
      await prior
          .insert(kCallHistoryTable, _missedCall(_legacyCallId))
          .timeout(deadline);
      final original =
          (await prior.query(kCallHistoryTable).timeout(deadline)).single;
      expect(original.containsKey('media_kind'), isFalse);
      await prior.close().timeout(deadline);

      final upgraded = await open(path, currentIdentityDatabaseVersion);
      addTearDown(() => upgraded.close().timeout(deadline));
      expect(await upgraded.getVersion().timeout(deadline), 134);
      final rows = await upgraded.query(kCallHistoryTable).timeout(deadline);
      expect(rows, [
        {...original, 'media_kind': null},
      ]);

      await runProductionOnUpgrade(upgraded, 132, 133).timeout(deadline);
      expect(await upgraded.query(kCallHistoryTable).timeout(deadline), rows);
    },
  );
}
