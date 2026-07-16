/// Plan 257 device-lab SQLCipher observer.
///
/// The host capture controller runs this test after the OS notification/tap
/// journey. The query/mutation logic lives in the E2E-only production helper so
/// the same operations can be dispatched by an already installed `$sims` app
/// without launching another Flutter build.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/debug/group_reaction_e2e_probe.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';

const _scenario = String.fromEnvironment('MKNOON_257_PROBE_SCENARIO');
const _groupName = String.fromEnvironment('MKNOON_257_PROBE_GROUP_NAME');
const _firstMarker = String.fromEnvironment('MKNOON_257_PROBE_FIRST_MARKER');
const _secondMarker = String.fromEnvironment('MKNOON_257_PROBE_SECOND_MARKER');
const _targetMarker = String.fromEnvironment('MKNOON_257_PROBE_TARGET_MARKER');
const _duplicateRedrivePrefix = 'MKNOON_257_DUPLICATE_REDRIVE_OBSERVATION ';

GroupReactionE2EProbeRequest _request() => GroupReactionE2EProbeRequest(
  scenario: _scenario,
  groupName: _groupName,
  firstMarker: _firstMarker,
  secondMarker: _secondMarker,
  targetMarker: _targetMarker,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Plan 257 reads the installed app SQLCipher state', (
    tester,
  ) async {
    expect(_scenario, isNotEmpty);
    expect(_groupName, isNotEmpty);

    final secureKeyStore = FlutterSecureKeyStore();
    final database = await openEncryptedDatabase(
      secureKeyStore: secureKeyStore,
      dbName: 'identity.db',
      version: currentIdentityDatabaseVersion,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    );
    try {
      final observation = await observeGroupReactionE2EState(
        database: database,
        secureKeyStore: secureKeyStore,
        request: _request(),
      );
      // Raw peer IDs, keys, ciphertext, and message text never cross this
      // prefix-matched boundary.
      // ignore: avoid_print
      print('MKNOON_257_SQLCIPHER_OBSERVATION ${jsonEncode(observation)}');
    } finally {
      await database.close();
    }
  });

  testWidgets('Plan 257 prepares the exact stored ADD retry', (tester) async {
    expect(_scenario, isNotEmpty);
    expect(_groupName, isNotEmpty);
    expect(_targetMarker, isNotEmpty);

    final secureKeyStore = FlutterSecureKeyStore();
    final database = await openEncryptedDatabase(
      secureKeyStore: secureKeyStore,
      dbName: 'identity.db',
      version: currentIdentityDatabaseVersion,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    );
    try {
      final observation = await prepareExactGroupReactionAddRedrive(
        database: database,
        secureKeyStore: secureKeyStore,
        request: _request(),
      );
      // Only hashes and the prior status cross the host boundary. The exact
      // signed/ciphertext retry bytes stay inside SQLCipher.
      // ignore: avoid_print
      print('$_duplicateRedrivePrefix${jsonEncode(observation)}');
    } finally {
      await database.close();
    }
  });
}
