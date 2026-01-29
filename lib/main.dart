import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/core/bridge/webview_js_bridge.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

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

  // Create and initialize the WebView JS bridge
  final bridge = WebViewJsBridge();
  await bridge.initialize();

  runApp(MyApp(
    repository: repository,
    bridge: bridge,
  ));
}

class MyApp extends StatelessWidget {
  final IdentityRepositoryImpl repository;
  final WebViewJsBridge bridge;

  const MyApp({
    Key? key,
    required this.repository,
    required this.bridge,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mknoon',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: StartupRouter(
        repository: repository,
        bridge: bridge,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}