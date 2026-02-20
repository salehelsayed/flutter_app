/// Smoke test entry point that auto-generates identity.
/// Run with: flutter run -t lib/smoke_test_main.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> _store = {};
  @override
  Future<String?> read(String key) async => _store[key];
  @override
  Future<void> write(String key, String value) async => _store[key] = value;
  @override
  Future<void> delete(String key) async => _store.remove(key);
  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('\n========================================');
  print('SMOKE TEST: Auto-generate identity');
  print('========================================\n');

  try {
    // Desktop platforms need FFI; on mobile, sqflite_sqlcipher has native plugins.
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final secureKeyStore = _FakeSecureKeyStore();

    print('[SMOKE] Step 1: Initialize database...');
    final db = await openEncryptedDatabase(
      secureKeyStore: secureKeyStore,
      dbName: 'smoke_test_identity.db',
      version: 8,
      onCreate: (db, version) async {
        await runIdentityTableMigration(db);
        await runMessagesTableMigration(db);
        await runMlKemKeysMigration(db);
        await runSecretNullChecksMigration(db);
        await runReadAtColumnMigration(db);
        await runArchiveColumnsMigration(db);
        await runBlockColumnsMigration(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await runMessagesTableMigration(db);
        if (oldVersion < 3) await runMlKemKeysMigration(db);
        if (oldVersion < 5) await runSecretNullChecksMigration(db);
        if (oldVersion < 6) await runReadAtColumnMigration(db);
        if (oldVersion < 7) await runArchiveColumnsMigration(db);
        if (oldVersion < 8) await runBlockColumnsMigration(db);
      },
    );
    print('[SMOKE] Database initialized');

    print('[SMOKE] Step 2: Create repository...');
    final repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
      secureKeyStore: secureKeyStore,
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
      print('FAILED! Error from bridge:');
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
