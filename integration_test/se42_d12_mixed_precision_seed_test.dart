import 'dart:convert';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '_support/se42_d12_mixed_precision_fixture.dart';

/// SE-42 D12 device helper. TEST-ONLY, for a disposable Android emulator whose
/// app already holds an onboarded identity. `D12_MODE=seed` writes the
/// synthetic fixture into that identity database; `D12_MODE=snapshot` only
/// reads it. Both print one `D12_SNAPSHOT` line for before/after comparison.
const _mode = String.fromEnvironment('D12_MODE');

/// Optional paired disposable peer. Empty seeds the uncallable synthetic contact.
const _peer = String.fromEnvironment('D12_PEER');
const _round = int.fromEnvironment('D12_ROUND', defaultValue: 1);
final _fixture = _peer.isEmpty
    ? D12Fixture.synthetic
    : D12Fixture.pairedPeer(_peer, round: _round);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SE-42 D12 mixed-precision fixture ($_mode)', (tester) async {
    expect(_mode, anyOf('seed', 'snapshot'), reason: 'set D12_MODE');
    final gateway = MethodChannelCanonicalRuntimeLeaseGateway();
    final session = CanonicalWritableRuntimeSession(gateway: gateway);
    final db = await session.acquireThenOpen<Database>(
      binding: 'se42-d12-mixed-precision-fixture',
      openDatabase: () => openEncryptedDatabase(
        secureKeyStore: FlutterSecureKeyStore(),
        dbName: 'identity.db',
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        requireExisting: true,
      ),
      closeDatabaseOnRuntimeAttachFailure: (database) async {
        await database.close();
        return true;
      },
    );
    try {
      final identityRows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM identity',
      );
      expect(identityRows.single['n'], 1, reason: 'needs an onboarded app');
      if (_mode == 'seed') {
        await seedD12Fixture(
          db,
          base: DateTime.now().toUtc(),
          fixture: _fixture,
        );
      }
      final snapshot = await d12Snapshot(db, fixture: _fixture);
      // ignore: avoid_print
      print('D12_SNAPSHOT ${jsonEncode(snapshot.toJson())}');
      expect(
        snapshot.rows.map((row) => row['call_id']),
        containsAll(<String>[_fixture.olderCallId, _fixture.newerCallId]),
      );
    } finally {
      await session.drainCloseRelease(
        stopRuntime: () async {
          if (!await gateway.quiesceRuntime()) {
            throw StateError('D12 helper Go runtime did not quiesce');
          }
        },
        closeDatabase: () async {
          if (db.isOpen) await db.close();
        },
      );
    }
  });
}
