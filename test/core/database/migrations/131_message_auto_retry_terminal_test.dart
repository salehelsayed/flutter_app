// ignore_for_file: file_names
import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  Future<Database> open(int version) => databaseFactoryFfiNoIsolate.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('message-retry-131-');
    path = '${directory.path}/db.sqlite';
  });
  tearDown(() => directory.delete(recursive: true));

  test('BL-24(C) v130 upgrade retains rows and durable terminal retry exclusion', () async {
    final old = await open(130);
    await old.insert('messages', {
      'id': 'invalid-empty',
      'contact_peer_id': 'peer-target',
      'sender_peer_id': 'my-peer-id',
      'text': '',
      'timestamp': '2026-01-01T00:00:00.000Z',
      'created_at': '2026-01-01T00:00:00.000Z',
      'status': 'failed',
      'is_incoming': 0,
    });
    final original = (await old.query('messages')).single;
    await old.close();
    final upgraded = await open(currentIdentityDatabaseVersion);
    final columns = await upgraded.rawQuery('PRAGMA table_info(messages)');
    expect(columns.map((c) => c['name']), contains('auto_retry_terminal_reason'));
    final row = (await upgraded.query('messages')).single;
    expect({...row}..remove('auto_retry_terminal_reason'), original);
    expect(row['auto_retry_terminal_reason'], isNull);
    expect(await dbLoadFailedOutgoingMessages(upgraded), hasLength(1));
    await upgraded.update('messages', {'auto_retry_terminal_reason': 'invalid_message'});
    await upgraded.close();

    final reopened = await open(currentIdentityDatabaseVersion);
    addTearDown(reopened.close);
    expect(await dbLoadFailedOutgoingMessages(reopened), isEmpty);
    final retained = (await reopened.query('messages')).single;
    expect(retained['status'], 'failed');
    expect({...retained}..remove('auto_retry_terminal_reason'), original);
  });
}
