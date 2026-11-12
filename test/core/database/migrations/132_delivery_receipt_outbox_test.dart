// ignore_for_file: file_names
import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test(
    'BL24D1 real v131 upgrade preserves rows and creates only receipt custody',
    () async {
      final directory = await Directory.systemTemp.createTemp('receipts-132-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/db.sqlite';
      Future<Database> open(int version) =>
          databaseFactoryFfiNoIsolate.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: version,
              singleInstance: false,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
            ),
          );
      final prior = await open(131);
      final originalTables = (await prior.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((row) => row['name']).toSet();
      await prior.insert('messages', {
        'id': 'keep-terminal-row',
        'contact_peer_id': 'peer',
        'sender_peer_id': 'self',
        'text': '',
        'timestamp': '2026-11-12T00:00:00.000Z',
        'created_at': '2026-11-12T00:00:00.000Z',
        'status': 'failed',
        'is_incoming': 0,
        'auto_retry_terminal_reason': 'invalid_message',
      });
      final original = (await prior.query('messages')).single;
      await prior.close();
      final upgraded = await open(currentIdentityDatabaseVersion);
      addTearDown(upgraded.close);
      expect(await upgraded.getVersion(), 132);
      expect((await upgraded.query('messages')).single, original);
      final nextTables = (await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((row) => row['name']).toSet();
      expect(nextTables.difference(originalTables), {
        'delivery_receipt_outbox',
      });
      expect(
        (await upgraded.rawQuery(
          'PRAGMA table_info(delivery_receipt_outbox)',
        )).map((row) => row['name']),
        [
          'receipt_key',
          'recipient_peer_id',
          'receipt_payload',
          'created_at_ms',
          'expires_at_ms',
          'next_attempt_at_ms',
          'attempt_count',
        ],
      );
      await runProductionOnUpgrade(upgraded, 131, 132);
      expect(await upgraded.query('delivery_receipt_outbox'), isEmpty);
    },
  );
}
