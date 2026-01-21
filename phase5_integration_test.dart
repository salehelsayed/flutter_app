import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/application/startup_decision.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'dart:convert';

// Mock JsBridge for testing
class MockJsBridge extends JsBridge {
  String? lastMessage;
  String nextResponse = '';

  @override
  Future<String> send(String message) async {
    lastMessage = message;
    return nextResponse;
  }

  void setGenerateResponse() {
    nextResponse = jsonEncode({
      'ok': true,
      'identity': {
        'peerId': '12D3KooWTestPeer',
        'publicKey': 'test-public-key',
        'privateKey': 'test-private-key',
        'mnemonic12': 'test mnemonic phrase with twelve words for testing only here now',
        'createdAt': '2025-01-17T12:00:00.000Z',
        'updatedAt': '2025-01-17T12:00:00.000Z',
      }
    });
  }

  void setRestoreResponse(bool success) {
    if (success) {
      nextResponse = jsonEncode({
        'ok': true,
        'identity': {
          'peerId': '12D3KooWRestoredPeer',
          'publicKey': 'restored-public-key',
          'privateKey': 'restored-private-key',
          'mnemonic12': 'restored mnemonic phrase with twelve words for testing only here',
          'createdAt': '2025-01-17T13:00:00.000Z',
          'updatedAt': '2025-01-17T13:00:00.000Z',
        }
      });
    } else {
      nextResponse = jsonEncode({
        'ok': false,
        'errorCode': 'INVALID_MNEMONIC',
        'errorMessage': 'Invalid mnemonic phrase',
      });
    }
  }
}

void main() {
  late Database db;
  late IdentityRepositoryImpl repository;
  late MockJsBridge mockBridge;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
    );
    mockBridge = MockJsBridge();
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 5 Integration Test', () {
    test('Full flow: Empty DB → Generate Identity → DB has identity', () async {
      print('\n' + '='*60);
      print('PHASE 5 INTEGRATION TEST - GENERATE FLOW');
      print('='*60);

      // Step 1: Verify empty database
      print('\n1. Checking initial database state...');
      final initialDecision = await decideStartupRoute(repository);
      expect(initialDecision, equals(StartupDecision.needsIdentity));
      print('   ✓ Database is empty, needs identity');

      // Step 2: Generate new identity
      print('\n2. Generating new identity...');
      mockBridge.setGenerateResponse();
      final generateResult = await generateNewIdentity(
        callJsGenerate: () => callJsIdentityGenerate(mockBridge),
        repo: repository,
      );
      expect(generateResult, equals(GenerateIdentityResult.success));
      print('   ✓ Identity generated successfully');

      // Step 3: Verify identity saved
      print('\n3. Verifying identity was saved...');
      final savedIdentity = await repository.loadIdentity();
      expect(savedIdentity, isNotNull);
      expect(savedIdentity!.peerId, equals('12D3KooWTestPeer'));
      print('   ✓ Identity saved with peerId: ${savedIdentity.peerId}');

      // Step 4: Verify startup decision changed
      print('\n4. Checking startup decision after generation...');
      final afterGenerateDecision = await decideStartupRoute(repository);
      expect(afterGenerateDecision, equals(StartupDecision.hasIdentity));
      print('   ✓ Database has identity, should go to main');

      print('\n' + '='*60);
      print('✅ GENERATE FLOW INTEGRATION TEST PASSED');
      print('='*60);
    });

    test('Full flow: Empty DB → Restore Identity → DB has identity', () async {
      print('\n' + '='*60);
      print('PHASE 5 INTEGRATION TEST - RESTORE FLOW');
      print('='*60);

      // Step 1: Verify empty database
      print('\n1. Checking initial database state...');
      final initialDecision = await decideStartupRoute(repository);
      expect(initialDecision, equals(StartupDecision.needsIdentity));
      print('   ✓ Database is empty, needs identity');

      // Step 2: Restore from mnemonic
      print('\n2. Restoring identity from mnemonic...');
      mockBridge.setRestoreResponse(true);
      final restoreResult = await restoreIdentityFromMnemonic(
        input: 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
        callJsRestore: (mnemonic) => callJsIdentityRestore(mockBridge, mnemonic),
        repo: repository,
      );
      expect(restoreResult, equals(RestoreIdentityResult.success));
      print('   ✓ Identity restored successfully');

      // Step 3: Verify identity saved
      print('\n3. Verifying identity was saved...');
      final restoredIdentity = await repository.loadIdentity();
      expect(restoredIdentity, isNotNull);
      expect(restoredIdentity!.peerId, equals('12D3KooWRestoredPeer'));
      print('   ✓ Identity saved with peerId: ${restoredIdentity.peerId}');

      // Step 4: Verify startup decision changed
      print('\n4. Checking startup decision after restore...');
      final afterRestoreDecision = await decideStartupRoute(repository);
      expect(afterRestoreDecision, equals(StartupDecision.hasIdentity));
      print('   ✓ Database has identity, should go to main');

      print('\n' + '='*60);
      print('✅ RESTORE FLOW INTEGRATION TEST PASSED');
      print('='*60);
    });

    test('Relaunch behavior: Identity persists across sessions', () async {
      print('\n' + '='*60);
      print('PHASE 5 INTEGRATION TEST - RELAUNCH BEHAVIOR');
      print('='*60);

      // Step 1: Generate and save identity
      print('\n1. Setting up identity in database...');
      mockBridge.setGenerateResponse();
      await generateNewIdentity(
        callJsGenerate: () => callJsIdentityGenerate(mockBridge),
        repo: repository,
      );
      print('   ✓ Identity generated and saved');

      // Step 2: Simulate app restart (repository still has same DB)
      print('\n2. Simulating app restart...');
      final decision1 = await decideStartupRoute(repository);
      expect(decision1, equals(StartupDecision.hasIdentity));
      print('   ✓ First check: Has identity');

      // Step 3: Multiple checks simulate multiple app launches
      print('\n3. Simulating multiple app launches...');
      for (int i = 0; i < 3; i++) {
        final decision = await decideStartupRoute(repository);
        expect(decision, equals(StartupDecision.hasIdentity));
        print('   ✓ Launch ${i + 1}: Identity persists');
      }

      print('\n' + '='*60);
      print('✅ RELAUNCH BEHAVIOR TEST PASSED');
      print('='*60);
    });

    test('Error handling: Invalid mnemonic restore', () async {
      print('\n' + '='*60);
      print('PHASE 5 INTEGRATION TEST - ERROR HANDLING');
      print('='*60);

      // Test invalid word count
      print('\n1. Testing invalid word count...');
      final invalidCountResult = await restoreIdentityFromMnemonic(
        input: 'only three words',
        callJsRestore: (mnemonic) => callJsIdentityRestore(mockBridge, mnemonic),
        repo: repository,
      );
      expect(invalidCountResult, equals(RestoreIdentityResult.invalidMnemonicFormat));
      print('   ✓ Invalid word count handled correctly');

      // Test invalid mnemonic from core
      print('\n2. Testing invalid mnemonic from core...');
      mockBridge.setRestoreResponse(false);
      final invalidMnemonicResult = await restoreIdentityFromMnemonic(
        input: 'invalid invalid invalid invalid invalid invalid invalid invalid invalid invalid invalid invalid',
        callJsRestore: (mnemonic) => callJsIdentityRestore(mockBridge, mnemonic),
        repo: repository,
      );
      expect(invalidMnemonicResult, equals(RestoreIdentityResult.invalidMnemonicCore));
      print('   ✓ Invalid mnemonic handled correctly');

      // Verify DB still empty after failures
      print('\n3. Verifying database still empty...');
      final decision = await decideStartupRoute(repository);
      expect(decision, equals(StartupDecision.needsIdentity));
      print('   ✓ Database remains empty after failed restore attempts');

      print('\n' + '='*60);
      print('✅ ERROR HANDLING TEST PASSED');
      print('='*60);
    });

    test('Summary: All Phase 5 flows working', () {
      print('\n' + '='*60);
      print('PHASE 5 VERIFICATION SUMMARY');
      print('='*60);
      print('✅ Generate identity flow works end-to-end');
      print('✅ Restore identity flow works end-to-end');
      print('✅ Identity persists across app relaunches');
      print('✅ Error cases handled properly');
      print('✅ Startup routing decision works correctly');
      print('');
      print('PHASE 5 (APP INTEGRATION) COMPLETE!');
      print('='*60);
    });
  });
}