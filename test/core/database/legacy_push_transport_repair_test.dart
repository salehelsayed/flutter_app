import 'dart:io';

import 'package:flutter_app/core/database/legacy_push_transport_repair.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
CREATE TABLE messages (
  id TEXT NOT NULL PRIMARY KEY,
  is_incoming INTEGER NOT NULL,
  transport TEXT
)
''');
  });

  tearDown(() => database.close());

  test('repairs only legacy incoming push rows and is idempotent', () async {
    for (final row in const <Map<String, Object?>>[
      <String, Object?>{
        'id': 'incoming-push',
        'is_incoming': 1,
        'transport': 'push',
      },
      <String, Object?>{
        'id': 'outgoing-push',
        'is_incoming': 0,
        'transport': 'push',
      },
      <String, Object?>{
        'id': 'incoming-inbox',
        'is_incoming': 1,
        'transport': 'inbox',
      },
      <String, Object?>{
        'id': 'incoming-direct',
        'is_incoming': 1,
        'transport': 'direct',
      },
    ]) {
      await database.insert('messages', row);
    }

    expect(await repairLegacyPushMessageTransports(database), 1);
    expect(await repairLegacyPushMessageTransports(database), 0);

    final rows = await database.query('messages', orderBy: 'id');
    expect(
      <String, Object?>{
        for (final row in rows) row['id']! as String: row['transport'],
      },
      <String, Object?>{
        'incoming-direct': 'direct',
        'incoming-inbox': 'inbox',
        'incoming-push': 'inbox',
        'outgoing-push': 'push',
      },
    );
  });

  test('foreground and headless writable opens both invoke the repair', () {
    final foreground = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final headless = File(
      'lib/app/bootstrap/production_headless_canonical_recovery.dart',
    ).readAsStringSync();

    for (final source in <String>[foreground, headless]) {
      expect(source, contains('await repairLegacyPushMessageTransports('));
    }
  });
}
