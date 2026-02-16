/// Smoke test for identity restore functionality.
/// Run with: flutter run -t lib/smoke_test_restore.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/bridge/webview_js_bridge.dart';
import 'dart:io' show Platform, File;
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('\n========================================');
  print('SMOKE TEST: Restore Identity from Mnemonic');
  print('========================================\n');

  String testResult = 'UNKNOWN';
  String testDetails = '';

  try {
    // Initialize database based on platform
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Use a test-specific database
    final dbPath = 'restore_smoke_test.db';

    // Delete existing test database
    try {
      await databaseFactory.deleteDatabase(dbPath);
      print('[SMOKE] Deleted existing test database');
    } catch (e) {
      print('[SMOKE] No existing database to delete');
    }

    print('[SMOKE] Step 1: Initialize fresh database...');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await runIdentityTableMigration(db);
      },
    );
    print('[SMOKE] Database initialized');

    print('[SMOKE] Step 2: Initialize WebView bridge...');
    final bridge = WebViewJsBridge();
    await bridge.initialize();
    print('[SMOKE] Bridge initialized');

    // Wait for WebView to be fully ready
    await Future.delayed(const Duration(seconds: 2));

    print('[SMOKE] Step 3: Generate a new identity first (to get valid mnemonic)...');
    final generateRequest = jsonEncode({
      'cmd': 'identity.generate',
      'payload': {},
    });

    final generateResponse = await bridge.send(generateRequest);
    final generateData = jsonDecode(generateResponse) as Map<String, dynamic>;

    if (generateData['ok'] != true) {
      throw Exception('Failed to generate identity: ${generateData['errorMessage']}');
    }

    final originalIdentity = generateData['identity'] as Map<String, dynamic>;
    final testMnemonic = originalIdentity['mnemonic12'] as String;
    final originalPeerId = originalIdentity['peerId'] as String;

    print('[SMOKE] Generated identity:');
    print('  Peer ID: $originalPeerId');
    print('  Mnemonic: $testMnemonic');

    print('\n[SMOKE] Step 4: Now restore from the same mnemonic...');
    final restoreRequest = jsonEncode({
      'cmd': 'identity.restore',
      'payload': {'mnemonic12': testMnemonic},
    });

    final restoreResponse = await bridge.send(restoreRequest);
    print('[SMOKE] Restore response: ${restoreResponse.substring(0, 100)}...');

    final restoreData = jsonDecode(restoreResponse) as Map<String, dynamic>;

    if (restoreData['ok'] != true) {
      print('\n========================================');
      print('FAILED! Restore returned error:');
      print('========================================');
      print('Error Code: ${restoreData['errorCode']}');
      print('Error Message: ${restoreData['errorMessage']}');
      testResult = 'FAIL';
      testDetails = 'Restore error: ${restoreData['errorMessage']}';
    } else {
      final restoredIdentity = restoreData['identity'] as Map<String, dynamic>;
      final restoredPeerId = restoredIdentity['peerId'] as String;
      final restoredMnemonic = restoredIdentity['mnemonic12'] as String;

      print('\n[SMOKE] Step 5: Verify restored identity matches original...');
      print('  Original Peer ID: $originalPeerId');
      print('  Restored Peer ID: $restoredPeerId');

      if (restoredPeerId == originalPeerId) {
        print('\n========================================');
        print('SUCCESS! Peer IDs match!');
        print('========================================');
        print('[SMOKE] PASS: Deterministic restoration works!');
        testResult = 'PASS';
        testDetails = 'Peer ID: $restoredPeerId';

        // Also test saving to DB
        print('\n[SMOKE] Step 6: Test saving restored identity to database...');
        final repository = IdentityRepositoryImpl(
          dbLoadIdentityRow: () => dbLoadIdentityRow(db),
          dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
          secureKeyStore: FlutterSecureKeyStore(),
        );

        // Create IdentityModel and save
        await dbUpsertIdentityRow(db, {
          'peer_id': restoredPeerId,
          'public_key': restoredIdentity['publicKey'],
          'private_key': restoredIdentity['privateKey'],
          'mnemonic12': restoredMnemonic,
          'created_at': restoredIdentity['createdAt'],
          'updated_at': restoredIdentity['updatedAt'],
        });

        // Verify saved
        final loaded = await dbLoadIdentityRow(db);
        if (loaded != null && loaded['peer_id'] == restoredPeerId) {
          print('[SMOKE] PASS: Identity saved and loaded from DB!');
        } else {
          print('[SMOKE] WARN: DB save/load verification failed');
        }
      } else {
        print('\n========================================');
        print('FAILED! Peer IDs do not match!');
        print('========================================');
        testResult = 'FAIL';
        testDetails = 'Peer ID mismatch: $originalPeerId vs $restoredPeerId';
      }
    }

    // Test invalid mnemonic handling
    print('\n[SMOKE] Step 7: Test invalid mnemonic handling...');
    final invalidRequest = jsonEncode({
      'cmd': 'identity.restore',
      'payload': {'mnemonic12': 'invalid words that are not a real mnemonic phrase at all'},
    });

    final invalidResponse = await bridge.send(invalidRequest);
    final invalidData = jsonDecode(invalidResponse) as Map<String, dynamic>;

    if (invalidData['ok'] == false && invalidData['errorCode'] == 'INVALID_MNEMONIC') {
      print('[SMOKE] PASS: Invalid mnemonic correctly rejected!');
    } else {
      print('[SMOKE] WARN: Invalid mnemonic was not properly rejected');
    }

    // Cleanup
    await db.close();
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } catch (e) {
      // Ignore cleanup errors
    }

  } catch (e, stack) {
    print('\n========================================');
    print('SMOKE TEST EXCEPTION:');
    print('========================================');
    print('Error: $e');
    print('Stack: $stack');
    testResult = 'ERROR';
    testDetails = e.toString();
  }

  print('\n========================================');
  print('SMOKE TEST COMPLETE: $testResult');
  print('========================================\n');

  runApp(SmokeTestResultApp(result: testResult, details: testDetails));
}

class SmokeTestResultApp extends StatelessWidget {
  final String result;
  final String details;

  const SmokeTestResultApp({
    super.key,
    required this.result,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final isPass = result == 'PASS';
    return MaterialApp(
      home: Scaffold(
        backgroundColor: isPass ? Colors.green.shade900 : Colors.red.shade900,
        appBar: AppBar(
          title: Text('Restore Smoke Test: $result'),
          backgroundColor: isPass ? Colors.green : Colors.red,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isPass ? Icons.check_circle : Icons.error,
                color: Colors.white,
                size: 100,
              ),
              const SizedBox(height: 20),
              Text(
                result,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  details,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Check console for full logs',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
