import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';

/// Acquires the Android runtime/SQLCipher ownership boundary before a device
/// integration test touches the process-global Go bridge.
///
/// Test entrypoints do not execute the production bootstrap. A real encrypted
/// sentinel database keeps the required order honest: lease -> SQLCipher -> Go.
final class CanonicalRuntimeDeviceTestLease {
  CanonicalRuntimeDeviceTestLease({required this.binding});

  final String binding;
  final CanonicalRuntimeLeaseGateway _gateway =
      MethodChannelCanonicalRuntimeLeaseGateway();
  late final CanonicalWritableRuntimeSession _session =
      CanonicalWritableRuntimeSession(gateway: _gateway);
  Database? _database;
  String? _databasePath;

  Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    if (_database != null) {
      throw StateError('canonical runtime device-test lease is already active');
    }
    final databasePath = p.join(
      await getDatabasesPath(),
      'canonical_runtime_device_test_lease.db',
    );
    await deleteDatabase(databasePath);
    _databasePath = databasePath;
    _database = await _session.acquireThenOpen<Database>(
      binding: binding,
      openDatabase: () => openDatabase(
        databasePath,
        password: 'mknoon-canonical-runtime-device-test-v1',
        version: 1,
        onCreate: (database, _) => database.execute(
          'CREATE TABLE runtime_lease_probe ('
          'id INTEGER PRIMARY KEY NOT NULL, '
          'opened_at TEXT NOT NULL'
          ')',
        ),
      ),
      closeDatabaseOnRuntimeAttachFailure: (database) async {
        await database.close();
        return true;
      },
    );
  }

  Future<void> release() async {
    if (!Platform.isAndroid) return;
    final database = _database;
    if (database == null) return;
    await _session.drainCloseRelease(
      stopRuntime: () async {
        if (!await _gateway.quiesceRuntime()) {
          throw StateError('device-test Go runtime did not quiesce');
        }
      },
      closeDatabase: () async {
        if (database.isOpen) await database.close();
      },
    );
    _database = null;
    final databasePath = _databasePath;
    _databasePath = null;
    if (databasePath != null) await deleteDatabase(databasePath);
  }
}
