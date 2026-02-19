import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/chat_message_listener.dart';
import 'package:flutter_app/core/services/contact_request_listener.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Fallback bridge for desktop development (no native Go binary).
class ProductionJsBridge extends JsBridge {
  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message);

    if (request['cmd'] == 'identity.generate') {
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
      await Future.delayed(Duration(seconds: 1));
      final mnemonic = request['payload']['mnemonic12'];

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

  // Create bridge: GoBridgeClient on mobile, ProductionJsBridge on desktop
  final bool isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  final JsBridge bridge;
  GoBridgeClient? goBridgeClient;

  if (isMobile) {
    goBridgeClient = GoBridgeClient();
    bridge = goBridgeClient;
  } else {
    bridge = ProductionJsBridge();
  }

  // Create local P2P service for WiFi peer discovery
  final localDiscovery = BonsoirDiscoveryService();
  final localWsServer = LocalWsServer();
  final localP2PService = LocalP2PService(
    discovery: localDiscovery,
    wsServer: localWsServer,
  );

  // Create P2P service backed by the bridge
  final p2pServiceImpl = P2PServiceImpl(
    bridge: bridge,
    localP2PService: localP2PService,
  );

  // Wire Go push events to P2PServiceImpl (mobile only)
  if (goBridgeClient != null) {
    goBridgeClient.eventStream.listen(p2pServiceImpl.onGoEvent);
  }

  // Create the message routing pipeline
  final messageRouter = IncomingMessageRouter(p2pService: p2pServiceImpl);
  final chatMessageListener = ChatMessageListener(router: messageRouter);
  final contactRequestListener = ContactRequestListener(router: messageRouter);

  runApp(MyApp(
    repository: repository,
    bridge: bridge,
    localP2PService: localP2PService,
    p2pService: p2pServiceImpl,
    chatMessageListener: chatMessageListener,
    contactRequestListener: contactRequestListener,
  ));
}

class MyApp extends StatelessWidget {
  final IdentityRepositoryImpl repository;
  final JsBridge bridge;
  final LocalP2PService localP2PService;
  final P2PService p2pService;
  final ChatMessageListener chatMessageListener;
  final ContactRequestListener contactRequestListener;

  const MyApp({
    Key? key,
    required this.repository,
    required this.bridge,
    required this.localP2PService,
    required this.p2pService,
    required this.chatMessageListener,
    required this.contactRequestListener,
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
        localP2PService: localP2PService,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
