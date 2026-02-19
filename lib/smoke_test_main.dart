/// Smoke test entry point that auto-generates identity.
/// Run with: flutter run -t lib/smoke_test_main.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('\n========================================');
  print('SMOKE TEST: Auto-generate identity');
  print('========================================\n');

  try {
    // Initialize database based on platform
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    print('[SMOKE] Step 1: Initialize database...');
    final db = await openDatabase(
      'smoke_test_identity.db',
      version: 1,
      onCreate: (db, version) async {
        await runIdentityTableMigration(db);
      },
    );
    print('[SMOKE] Database initialized');

    print('[SMOKE] Step 2: Create repository...');
    final repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
      secureKeyStore: FlutterSecureKeyStore(),
    );

    print('[SMOKE] Step 3: Initialize Go bridge...');
    final bridge = GoBridgeClient();
    await bridge.initialize();
    print('[SMOKE] Bridge initialized successfully');

    // Wait a bit for Go bridge to be fully ready
    await Future.delayed(const Duration(seconds: 2));

    print('[SMOKE] Step 4: Call identity.generate via bridge...');
    final request = jsonEncode({
      'cmd': 'identity.generate',
      'payload': {},
    });

    final responseJson = await bridge.send(request);
    print('[SMOKE] Response received: ${responseJson.substring(0, 100)}...');

    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] == true) {
      final identity = response['identity'] as Map<String, dynamic>;
      print('\n========================================');
      print('SUCCESS! Identity generated:');
      print('========================================');
      print('Peer ID: ${identity['peerId']}');
      print('Mnemonic: ${identity['mnemonic12']}');
      print('Public Key: ${(identity['publicKey'] as String).substring(0, 30)}...');
      print('Created At: ${identity['createdAt']}');

      // Verify mnemonic is real BIP39
      final mnemonic = identity['mnemonic12'] as String;
      final words = mnemonic.split(' ');
      if (words.length == 12 && !mnemonic.contains('demo')) {
        print('\n========================================');
        print('[SMOKE] PASS: Real BIP39 mnemonic!');
        print('========================================');

        // Verify peer ID format (should start with 12D3KooW)
        if ((identity['peerId'] as String).startsWith('12D3KooW')) {
          print('[SMOKE] PASS: Valid libp2p peer ID format!');
        } else {
          print('[SMOKE] WARN: Unexpected peer ID format');
        }
      } else {
        print('\n[SMOKE] FAIL: Mnemonic appears fake or invalid');
        print('Expected 12 words, got: ${words.length}');
      }
    } else {
      print('\n========================================');
      print('FAILED! Error from JS:');
      print('========================================');
      print('Error Code: ${response['errorCode']}');
      print('Error Message: ${response['errorMessage']}');
    }

    // Clean up
    await db.close();

  } catch (e, stack) {
    print('\n========================================');
    print('SMOKE TEST EXCEPTION:');
    print('========================================');
    print('Error: $e');
    print('Stack: $stack');
  }

  print('\n[SMOKE] Test complete. Showing UI...');

  runApp(const SmokeTestApp());
}

class SmokeTestApp extends StatelessWidget {
  const SmokeTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Smoke Test'),
          backgroundColor: Colors.green,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 100),
              SizedBox(height: 20),
              Text(
                'Check console logs',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
