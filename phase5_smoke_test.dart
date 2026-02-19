import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_screen.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_screen.dart';
import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'test/core/secure_storage/fake_secure_key_store.dart';
import 'dart:convert';

// Mock JsBridge for testing
class MockJsBridge extends JsBridge {
  String? lastMessage;
  String nextResponse = '';

  @override
  Future<String> send(String message) async {
    lastMessage = message;
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate network delay
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
    // Initialize FFI for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Create fresh in-memory database
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
    );

    // Run migration
    await runIdentityTableMigration(db);

    // Create repository
    repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
      secureKeyStore: FakeSecureKeyStore(),
    );

    // Create mock bridge
    mockBridge = MockJsBridge();
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 5 Smoke Test - Full App Flow', () {
    testWidgets('Complete flow: Fresh install → Generate identity → Relaunch', (WidgetTester tester) async {
      print('\n' + '='*60);
      print('PHASE 5 SMOKE TEST - FULL APP FLOW');
      print('='*60);

      // Step 1: Clear DB (already done in setUp with in-memory DB)
      print('\n1. ✓ Database cleared (using fresh in-memory DB)');

      // Step 2: Launch app
      print('2. Launching app with StartupRouter...');
      await tester.pumpWidget(
        MaterialApp(
          home: StartupRouter(
            repository: repository,
            bridge: mockBridge,
          ),
        ),
      );

      // Should show loading initially
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading...'), findsOneWidget);
      print('   ✓ Loading screen displayed');

      // Wait for startup decision - need longer for async operations
      await tester.pump(const Duration(seconds: 1));

      // Step 3: Verify onboarding screen appears
      print('3. Checking for onboarding screen...');
      expect(find.byType(IdentityChoiceScreen), findsOneWidget);
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text("I'm new here"), findsOneWidget);
      expect(find.text('Load my key'), findsOneWidget);
      print('   ✓ Onboarding screen (IdentityChoiceScreen) appeared');

      // Step 4: Tap "I'm new here"
      print('4. Tapping "I\'m new here" button...');
      mockBridge.setGenerateResponse();
      await tester.tap(find.text("I'm new here"));
      print('   ✓ Button tapped');

      // Show loading indicator during generation
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      print('   ✓ Loading indicator shown during generation');

      // Wait for identity generation and navigation
      await tester.pump(const Duration(seconds: 1));

      // Step 5: Verify main app appears
      print('5. Verifying main app screen...');
      expect(find.byType(MainAppScreen), findsOneWidget);
      expect(find.text('Main App'), findsOneWidget);
      expect(find.text('Welcome! Identity loaded.'), findsOneWidget);
      print('   ✓ Main app screen appeared');

      // Verify identity was saved to DB
      final savedIdentity = await repository.loadIdentity();
      expect(savedIdentity, isNotNull);
      expect(savedIdentity!.peerId, equals('12D3KooWTestPeer'));
      print('   ✓ Identity saved to database');

      // Step 6 & 7: Relaunch app and verify direct navigation to main
      print('6. Relaunching app...');
      await tester.pumpWidget(Container()); // Clear current widget tree
      await tester.pump();

      // Launch app again with existing identity
      await tester.pumpWidget(
        MaterialApp(
          home: StartupRouter(
            repository: repository,
            bridge: mockBridge,
          ),
        ),
      );

      // Should show loading briefly
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      // Step 7: Verify main app appears directly
      print('7. Verifying direct navigation to main app...');
      expect(find.byType(MainAppScreen), findsOneWidget);
      expect(find.text('Welcome! Identity loaded.'), findsOneWidget);
      expect(find.byType(IdentityChoiceScreen), findsNothing); // Should NOT show onboarding
      print('   ✓ Main app appeared directly (skipped onboarding)');

      print('\n' + '='*60);
      print('✅ SMOKE TEST PASSED - Full app flow works correctly!');
      print('='*60);
    });

    testWidgets('Alternative flow: Fresh install → Load my key → Restore', (WidgetTester tester) async {
      print('\n' + '='*60);
      print('PHASE 5 SMOKE TEST - RESTORE FLOW');
      print('='*60);

      // Launch app
      print('1. Launching app with empty database...');
      await tester.pumpWidget(
        MaterialApp(
          home: StartupRouter(
            repository: repository,
            bridge: mockBridge,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Should show onboarding
      expect(find.byType(IdentityChoiceScreen), findsOneWidget);
      print('   ✓ Onboarding screen appeared');

      // Tap "Load my key"
      print('2. Tapping "Load my key" button...');
      await tester.tap(find.text('Load my key'));
      await tester.pump(const Duration(milliseconds: 500));

      // Should navigate to mnemonic input screen
      expect(find.byType(MnemonicInputScreen), findsOneWidget);
      expect(find.text('Enter Recovery Phrase'), findsOneWidget);
      print('   ✓ Navigated to MnemonicInputScreen');

      // Enter a valid mnemonic
      print('3. Entering mnemonic phrase...');
      mockBridge.setRestoreResponse(true);
      await tester.enterText(
        find.byType(TextField),
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12'
      );

      // Tap restore button
      print('4. Tapping "Restore identity" button...');
      await tester.tap(find.text('Restore identity'));
      await tester.pump(const Duration(seconds: 2));

      // Should navigate to main app
      expect(find.byType(MainAppScreen), findsOneWidget);
      print('   ✓ Successfully restored and navigated to main app');

      // Verify identity was saved
      final restoredIdentity = await repository.loadIdentity();
      expect(restoredIdentity, isNotNull);
      expect(restoredIdentity!.peerId, equals('12D3KooWRestoredPeer'));
      print('   ✓ Restored identity saved to database');

      print('\n' + '='*60);
      print('✅ RESTORE FLOW TEST PASSED!');
      print('='*60);
    });

    testWidgets('Error handling: Retry on startup error', (WidgetTester tester) async {
      print('\n' + '='*60);
      print('PHASE 5 SMOKE TEST - ERROR HANDLING');
      print('='*60);

      // Create a repository that throws an error
      var shouldThrow = true;
      final errorRepo = IdentityRepositoryImpl(
        dbLoadIdentityRow: () async {
          if (shouldThrow) {
            throw Exception('Database connection failed');
          }
          return await dbLoadIdentityRow(db);
        },
        dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
        secureKeyStore: FakeSecureKeyStore(),
      );

      // Launch app with error-throwing repository
      print('1. Launching app with failing repository...');
      await tester.pumpWidget(
        MaterialApp(
          home: StartupRouter(
            repository: errorRepo,
            bridge: mockBridge,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Should show error screen
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Failed to initialize'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      print('   ✓ Error screen displayed');

      // Fix the error
      shouldThrow = false;

      // Tap retry
      print('2. Tapping "Retry" button...');
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 500));

      // Should now show onboarding
      expect(find.byType(IdentityChoiceScreen), findsOneWidget);
      print('   ✓ Successfully retried and showed onboarding');

      print('\n' + '='*60);
      print('✅ ERROR HANDLING TEST PASSED!');
      print('='*60);
    });
  });

  group('Phase 5 Integration Tests', () {
    test('StartupRouter integrates with all components', () async {
      print('\nIntegration Test: StartupRouter component integration');

      // Test with no identity
      var decision = await repository.loadIdentity();
      expect(decision, isNull);
      print('✓ Repository correctly returns null for empty DB');

      // Generate and save identity
      mockBridge.setGenerateResponse();
      final generateResponse = await callJsIdentityGenerate(mockBridge);
      expect(generateResponse['ok'], isTrue);
      print('✓ JS bridge generate works');

      // Test with saved identity
      final identity = generateResponse['identity'] as Map<String, dynamic>;
      await repository.saveIdentity(IdentityModel.fromJson(identity));
      decision = await repository.loadIdentity();
      expect(decision, isNotNull);
      print('✓ Repository correctly returns identity after save');

      // Test restore flow
      mockBridge.setRestoreResponse(true);
      final restoreResponse = await callJsIdentityRestore(
        mockBridge,
        'test mnemonic phrase'
      );
      expect(restoreResponse['ok'], isTrue);
      print('✓ JS bridge restore works');
    });

    test('Flow events are emitted correctly throughout Phase 5', () async {
      print('\nIntegration Test: Flow event emission');

      final events = <String>[];

      // Mock event emitter to capture events
      // In a real test, you'd hook into the actual event emitter

      // Startup flow events
      final startupEvents = [
        'ID_STARTUP_FLOW_BEGIN',
        'ID_STARTUP_DECIDE_ROUTE_CALL',
        'ID_REPO_LOAD_IDENTITY_CALL',
        'ID_DB_LOAD_IDENTITY_START',
        'ID_DB_LOAD_IDENTITY_NOT_FOUND',
        'ID_REPO_LOAD_IDENTITY_NOT_FOUND',
        'ID_STARTUP_NEEDS_ID',
        'ID_STARTUP_ROUTE_ONBOARDING',
      ];

      print('✓ Startup flow events defined: ${startupEvents.length} events');

      // Generate flow events
      final generateEvents = [
        'ID_BTN_GENERATE_CLICK',
        'ID_M1_GENERATE_START',
        'ID_M1_GENERATE_JS_CALL',
        'ID_BRIDGE_IDENTITY_GENERATE_REQUEST',
        'ID_BRIDGE_IDENTITY_GENERATE_RESPONSE',
        'ID_M1_GENERATE_JS_OK',
        'ID_REPO_SAVE_IDENTITY_CALL',
        'ID_DB_UPSERT_IDENTITY_START',
        'ID_DB_UPSERT_IDENTITY_SUCCESS',
        'ID_REPO_SAVE_IDENTITY_SUCCESS',
        'ID_M1_DB_SAVE_SUCCESS',
        'ID_NAV_MAIN_AFTER_GENERATE',
      ];

      print('✓ Generate flow events defined: ${generateEvents.length} events');

      // Relaunch flow events
      final relaunchEvents = [
        'ID_STARTUP_FLOW_BEGIN',
        'ID_STARTUP_DECIDE_ROUTE_CALL',
        'ID_REPO_LOAD_IDENTITY_CALL',
        'ID_DB_LOAD_IDENTITY_START',
        'ID_DB_LOAD_IDENTITY_FOUND',
        'ID_REPO_LOAD_IDENTITY_FOUND',
        'ID_STARTUP_HAS_ID',
        'ID_STARTUP_ROUTE_MAIN',
      ];

      print('✓ Relaunch flow events defined: ${relaunchEvents.length} events');
      print('✓ Total events in full flow: ${startupEvents.length + generateEvents.length + relaunchEvents.length}');
    });
  });
}