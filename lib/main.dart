import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/core/bridge/webview_js_bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
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
    version: 2,
    onCreate: (db, version) async {
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await runMessagesTableMigration(db);
      }
    },
  );

  // Create repository with database helpers
  final repository = IdentityRepositoryImpl(
    dbLoadIdentityRow: () => dbLoadIdentityRow(db),
    dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
  );

  // Create contact repository
  final contactRepository = ContactRepositoryImpl(
    dbLoadAllContacts: () => dbLoadAllContacts(db),
    dbLoadContact: (peerId) => dbLoadContact(db, peerId),
    dbUpsertContact: (row) => dbUpsertContact(db, row),
    dbDeleteContact: (peerId) => dbDeleteContact(db, peerId),
    dbGetContactCount: () => dbGetContactCount(db),
    dbContactExists: (peerId) => dbContactExists(db, peerId),
  );

  // Create contact request repository
  final contactRequestRepository = ContactRequestRepositoryImpl(
    dbLoadPendingRequests: () => dbLoadPendingRequests(db),
    dbLoadRequest: (peerId) => dbLoadRequest(db, peerId),
    dbUpsertRequest: (row) => dbUpsertRequest(db, row),
    dbUpdateRequestStatus: (peerId, status) =>
        dbUpdateRequestStatus(db, peerId, status),
    dbDeleteRequest: (peerId) => dbDeleteRequest(db, peerId),
    dbRequestExists: (peerId) => dbRequestExists(db, peerId),
  );

  // Create message repository
  final messageRepository = MessageRepositoryImpl(
    dbInsertMessage: (row) => dbInsertMessage(db, row),
    dbLoadMessagesForContact: (contactPeerId) =>
        dbLoadMessagesForContact(db, contactPeerId),
    dbLoadLatestMessageForContact: (contactPeerId) =>
        dbLoadLatestMessageForContact(db, contactPeerId),
    dbUpdateMessageStatus: (id, status) =>
        dbUpdateMessageStatus(db, id, status),
    dbLoadMessage: (id) => dbLoadMessage(db, id),
  );

  // Create and initialize the WebView JS bridge
  final bridge = WebViewJsBridge();
  await bridge.initialize();

  // Create P2P service (uses the same bridge)
  final p2pService = P2PServiceImpl(bridge: bridge);

  // Create message router — single subscription, routes by type
  final messageRouter = IncomingMessageRouter(p2pService: p2pService);

  // Create contact request listener
  // The getOwnPeerId function gets the peerId from the P2P service's current state.
  // This is populated when the node starts, so it will be empty before that.
  final contactRequestListener = ContactRequestListener(
    contactRequestStream: messageRouter.contactRequestStream,
    requestRepo: contactRequestRepository,
    contactRepo: contactRepository,
    bridge: bridge,
    getOwnPeerId: () => p2pService.currentState.peerId ?? '',
  );

  // Create chat message listener
  final chatMessageListener = ChatMessageListener(
    chatMessageStream: messageRouter.chatMessageStream,
    messageRepo: messageRepository,
    contactRepo: contactRepository,
  );

  // Start router first, then listeners
  messageRouter.start();
  contactRequestListener.start();
  chatMessageListener.start();

  runApp(MyApp(
    repository: repository,
    contactRepository: contactRepository,
    contactRequestRepository: contactRequestRepository,
    contactRequestListener: contactRequestListener,
    messageRepository: messageRepository,
    chatMessageListener: chatMessageListener,
    bridge: bridge,
    p2pService: p2pService,
  ));
}

class MyApp extends StatelessWidget {
  final IdentityRepositoryImpl repository;
  final ContactRepositoryImpl contactRepository;
  final ContactRequestRepositoryImpl contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final MessageRepositoryImpl messageRepository;
  final ChatMessageListener chatMessageListener;
  final WebViewJsBridge bridge;
  final P2PServiceImpl p2pService;

  const MyApp({
    Key? key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.messageRepository,
    required this.chatMessageListener,
    required this.bridge,
    required this.p2pService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mknoon',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: StartupRouter(
        repository: repository,
        contactRepository: contactRepository,
        contactRequestRepository: contactRequestRepository,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepository,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
