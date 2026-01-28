import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/core/bridge/webview_js_bridge.dart';
import 'dart:io';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for desktop testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('Smoke test: New user generates identity', (WidgetTester tester) async {
    print('\n========================================');
    print('SMOKE TEST: New User Identity Generation');
    print('========================================\n');

    // Delete existing database to simulate fresh start
    final dbPath = '${Directory.current.path}/test_identity.db';
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
      print('[TEST] Deleted existing test database');
    }

    print('[TEST] Step 1: Initialize database...');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        print('[TEST] Running identity table migration...');
        await runIdentityTableMigration(db);
      },
    );
    print('[TEST] Database initialized at: $dbPath');

    print('[TEST] Step 2: Create repository...');
    final repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
    );

    print('[TEST] Step 3: Initialize WebView bridge...');
    final bridge = WebViewJsBridge();
    try {
      await bridge.initialize();
      print('[TEST] Bridge initialized successfully');
    } catch (e) {
      print('[TEST] ERROR: Bridge initialization failed: $e');
      rethrow;
    }

    print('[TEST] Step 4: Build app widget...');
    await tester.pumpWidget(
      MaterialApp(
        home: StartupRouter(
          repository: repository,
          bridge: bridge,
        ),
      ),
    );

    // Wait for initial load
    print('[TEST] Step 5: Wait for app to load...');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Look for "I'm new here" button
    print('[TEST] Step 6: Looking for "I\'m new here" button...');
    final newUserButton = find.text("I'm new here");

    if (newUserButton.evaluate().isEmpty) {
      print('[TEST] ERROR: Could not find "I\'m new here" button');
      print('[TEST] Current widget tree:');
      debugDumpApp();
      fail('Button not found');
    }

    print('[TEST] Found button, tapping...');
    await tester.tap(newUserButton);
    await tester.pump();

    print('[TEST] Step 7: Waiting for identity generation...');
    // Wait for async operations
    await tester.pumpAndSettle(const Duration(seconds: 10));

    print('[TEST] Step 8: Checking results...');

    // Query the database to see if identity was created
    final identityRow = await dbLoadIdentityRow(db);

    if (identityRow != null) {
      print('\n========================================');
      print('SUCCESS! Identity generated:');
      print('========================================');
      print('Peer ID: ${identityRow['peer_id']}');
      print('Mnemonic: ${identityRow['mnemonic12']}');
      print('Public Key: ${identityRow['public_key']?.toString().substring(0, 20)}...');
      print('Created At: ${identityRow['created_at']}');
      print('========================================\n');

      // Verify it's a real mnemonic (not the fake demo one)
      final mnemonic = identityRow['mnemonic12'] as String;
      expect(mnemonic, isNot(contains('demo seed phrase')));
      expect(mnemonic.split(' ').length, equals(12));

      print('[TEST] PASS: Real BIP39 mnemonic generated!');
    } else {
      print('[TEST] ERROR: No identity found in database');
      fail('Identity not created');
    }

    // Cleanup
    await db.close();
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  });
}
