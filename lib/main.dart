import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

// Production JsBridge implementation
class ProductionJsBridge extends JsBridge {
  @override
  Future<String> send(String message) async {
    // In a real app, this would communicate with native platform code
    // For now, we'll simulate responses for demo purposes
    final request = jsonDecode(message);

    if (request['cmd'] == 'identity.generate') {
      // Simulate identity generation
      await Future.delayed(Duration(seconds: 1));
      return jsonEncode({
        'ok': true,
        'identity': {
          'peerId': '12D3KooW${DateTime.now().millisecondsSinceEpoch}Demo',
          'publicKey': 'DEMO_PUBLIC_KEY_BASE64_${DateTime.now().millisecondsSinceEpoch}',
          'privateKey': 'DEMO_PRIVATE_KEY_BASE64_${DateTime.now().millisecondsSinceEpoch}',
          'mnemonic12': 'demo seed phrase twelve words here for testing the app behavior okay now',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }
      });
    }

    if (request['cmd'] == 'identity.restore') {
      // Simulate identity restoration
      await Future.delayed(Duration(seconds: 1));
      final mnemonic = request['payload']['mnemonic12'];

      // Accept any 12-word mnemonic for demo
      if (mnemonic.split(' ').length == 12) {
        return jsonEncode({
          'ok': true,
          'identity': {
            'peerId': '12D3KooWRestored${mnemonic.hashCode}',
            'publicKey': 'RESTORED_PUBLIC_KEY_BASE64_${mnemonic.hashCode}',
            'privateKey': 'RESTORED_PRIVATE_KEY_BASE64_${mnemonic.hashCode}',
            'mnemonic12': mnemonic,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          }
        });
      } else {
        return jsonEncode({
          'ok': false,
          'errorCode': 'INVALID_MNEMONIC',
          'errorMessage': 'Invalid mnemonic phrase'
        });
      }
    }

    return jsonEncode({
      'ok': false,
      'errorCode': 'UNKNOWN_COMMAND',
      'errorMessage': 'Unknown command: ${request['cmd']}'
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database based on platform
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    // Desktop platforms need FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Open or create the database
  final db = await openDatabase(
    'identity.db',
    version: 1,
    onCreate: (db, version) async {
      await runIdentityTableMigration(db);
    },
  );

  // Create repository with database helpers
  final repository = IdentityRepositoryImpl(
    dbLoadIdentityRow: () => dbLoadIdentityRow(db),
    dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
  );

  // Create bridge
  final bridge = ProductionJsBridge();

  runApp(MyApp(
    repository: repository,
    bridge: bridge,
  ));
}

class MyApp extends StatelessWidget {
  final IdentityRepositoryImpl repository;
  final JsBridge bridge;

  const MyApp({
    Key? key,
    required this.repository,
    required this.bridge,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M1 Identity Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: StartupRouter(
        repository: repository,
        bridge: bridge,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}