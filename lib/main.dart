import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/settings/application/profile_update_listener.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupTiming.instance.mark('app_start');

  // Initialize Firebase (mobile only — not available on desktop)
  final bool isDesktop = !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
  if (!isDesktop) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    } catch (e) {
      debugPrint('Firebase init skipped: $e');
    }
  }

  // Initialize UserAvatar documents directory for file-based avatar loading
  final appDocDir = await getApplicationDocumentsDirectory();
  UserAvatar.setDocumentsDir(appDocDir.path);

  // Initialize database based on platform
  if (isDesktop) {
    // Desktop platforms need FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 1. Create secure key store
  final secureKeyStore = FlutterSecureKeyStore();

  // 2. Open encrypted database (handles plaintext→encrypted migration)
  final db = await openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: 'identity.db',
    version: 11,
    onCreate: (db, version) async {
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
      await runMlKemKeysMigration(db);
      // Fresh install: skip 004 (nullable) — 005 already has nullable + CHECK
      await runSecretNullChecksMigration(db);
      await runReadAtColumnMigration(db);
      await runArchiveColumnsMigration(db);
      await runBlockColumnsMigration(db);
      await runQuotedMessageIdMigration(db);
      await runMediaAttachmentsMigration(db);
      await runAvatarVersionMigration(db);
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await runMessagesTableMigration(db);
      }
      if (oldVersion < 3) {
        await runMlKemKeysMigration(db);
      }
      if (oldVersion < 4) {
        await runNullifySecretColumnsMigration(db);
      }
      // Migration 005 is deferred — runs after secrets migration below
      if (oldVersion < 6) {
        await runReadAtColumnMigration(db);
      }
      if (oldVersion < 7) {
        await runArchiveColumnsMigration(db);
      }
      if (oldVersion < 8) {
        await runBlockColumnsMigration(db);
      }
      if (oldVersion < 9) {
        await runQuotedMessageIdMigration(db);
      }
      if (oldVersion < 10) {
        await runMediaAttachmentsMigration(db);
      }
      if (oldVersion < 11) {
        await runAvatarVersionMigration(db);
      }
    },
  );

  // 3. Run one-time secrets migration (DB → secure storage)
  //    Must run BEFORE migration 005 so CHECK constraints don't reject
  //    existing non-null secret values during the table rebuild.
  await migrateSecretsToSecureStorage(
    db: db,
    secureKeyStore: secureKeyStore,
  );

  // 4. Apply CHECK constraints now that secret columns are guaranteed NULL
  await runSecretNullChecksMigration(db);

  // 5. Create repository with database helpers + secure key store
  final repository = IdentityRepositoryImpl(
    dbLoadIdentityRow: () => dbLoadIdentityRow(db),
    dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
    secureKeyStore: secureKeyStore,
  );

  // Create contact repository
  final contactRepository = ContactRepositoryImpl(
    dbLoadAllContacts: () => dbLoadAllContacts(db),
    dbLoadContact: (peerId) => dbLoadContact(db, peerId),
    dbUpsertContact: (row) => dbUpsertContact(db, row),
    dbDeleteContact: (peerId) => dbDeleteContact(db, peerId),
    dbGetContactCount: () => dbGetContactCount(db),
    dbContactExists: (peerId) => dbContactExists(db, peerId),
    dbArchiveContact: (peerId) => dbArchiveContact(db, peerId),
    dbUnarchiveContact: (peerId) => dbUnarchiveContact(db, peerId),
    dbLoadActiveContacts: () => dbLoadActiveContacts(db),
    dbLoadArchivedContacts: () => dbLoadArchivedContacts(db),
    dbBlockContact: (peerId) => dbBlockContact(db, peerId),
    dbUnblockContact: (peerId) => dbUnblockContact(db, peerId),
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
    dbCountMessagesForContact: (contactPeerId) =>
        dbCountMessagesForContact(db, contactPeerId),
    dbMarkConversationAsRead: (contactPeerId) =>
        dbMarkConversationAsRead(db, contactPeerId),
    dbCountUnreadForContact: (contactPeerId) =>
        dbCountUnreadForContact(db, contactPeerId),
    dbCountTotalUnread: () => dbCountTotalUnread(db),
    dbCountTotalUnreadExcludingArchived: () =>
        dbCountTotalUnreadExcludingArchived(db),
    dbDeleteMessagesForContact: (contactPeerId) =>
        dbDeleteMessagesForContact(db, contactPeerId),
    dbLoadMessagesPage: (contactPeerId, {limit = 50, beforeTimestamp}) =>
        dbLoadMessagesPage(db, contactPeerId,
            limit: limit, beforeTimestamp: beforeTimestamp),
    dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
  );

  // Create media attachment repository
  final mediaAttachmentRepository = MediaAttachmentRepositoryImpl(
    dbInsertMediaAttachment: (row) => dbInsertMediaAttachment(db, row),
    dbLoadMediaForMessage: (messageId) =>
        dbLoadMediaForMessage(db, messageId),
    dbLoadMediaForMessages: (messageIds) =>
        dbLoadMediaForMessages(db, messageIds),
    dbUpdateMediaLocalPath: (id, localPath, downloadStatus) =>
        dbUpdateMediaLocalPath(db, id, localPath, downloadStatus),
    dbUpdateMediaDownloadStatus: (id, downloadStatus) =>
        dbUpdateMediaDownloadStatus(db, id, downloadStatus),
    dbDeleteMediaForMessage: (messageId) =>
        dbDeleteMediaForMessage(db, messageId),
    dbDeleteMediaForContact: (contactPeerId) =>
        dbDeleteMediaForContact(db, contactPeerId),
    dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
  );

  // Create media file manager
  final mediaFileManager = MediaFileManager();

  // Create image processor (EXIF stripping + quality compression)
  final imageProcessor = ImageProcessor();

  // Create and initialize the bridge (Go native)
  final Bridge bridge = GoBridgeClient();
  await bridge.initialize();
  StartupTiming.instance.mark('bridge_initialized');

  // Create local P2P service for WiFi-first delivery
  final localDiscovery = BonsoirDiscoveryService();
  final localWsServer = LocalWsServer();
  final localP2PService = LocalP2PService(
    discovery: localDiscovery,
    wsServer: localWsServer,
  );

  // Create P2P service (uses the same bridge + local P2P)
  final p2pService = P2PServiceImpl(
    bridge: bridge,
    localP2PService: localP2PService,
  );

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
    bridge: bridge,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
    mediaAttachmentRepo: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
  );

  // Create profile update listener
  final profileUpdateListener = ProfileUpdateListener(
    profileUpdateStream: messageRouter.profileUpdateStream,
    contactRepo: contactRepository,
    bridge: bridge,
  );

  // Create pending message retrier
  final pendingMessageRetrier = PendingMessageRetrier(
    p2pService: p2pService,
    messageRepo: messageRepository,
    identityRepo: repository,
    contactRepo: contactRepository,
    bridge: bridge,
  );

  // Start router first, then listeners, then retrier
  messageRouter.start();
  contactRequestListener.start();
  chatMessageListener.start();
  profileUpdateListener.start();
  pendingMessageRetrier.start();

  // Forward profile avatar updates through chatMessageListener so
  // FeedWired/OrbitWired (which subscribe to contactUpdatedStream) refresh.
  profileUpdateListener.contactUpdatedStream.listen((contact) {
    chatMessageListener.emitContactUpdate(contact);
  });

  runApp(MyApp(
    repository: repository,
    contactRepository: contactRepository,
    contactRequestRepository: contactRequestRepository,
    contactRequestListener: contactRequestListener,
    messageRepository: messageRepository,
    mediaAttachmentRepository: mediaAttachmentRepository,
    chatMessageListener: chatMessageListener,
    profileUpdateListener: profileUpdateListener,
    messageRouter: messageRouter,
    pendingMessageRetrier: pendingMessageRetrier,
    bridge: bridge,
    p2pService: p2pService,
    mediaFileManager: mediaFileManager,
    secureKeyStore: secureKeyStore,
    imageProcessor: imageProcessor,
    isDesktop: isDesktop,
  ));
  StartupTiming.instance.mark('run_app_called');
}

class MyApp extends StatefulWidget {
  final IdentityRepositoryImpl repository;
  final ContactRepositoryImpl contactRepository;
  final ContactRequestRepositoryImpl contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final MessageRepositoryImpl messageRepository;
  final MediaAttachmentRepositoryImpl mediaAttachmentRepository;
  final ChatMessageListener chatMessageListener;
  final ProfileUpdateListener profileUpdateListener;
  final IncomingMessageRouter messageRouter;
  final PendingMessageRetrier pendingMessageRetrier;
  final Bridge bridge;
  final P2PServiceImpl p2pService;
  final MediaFileManager mediaFileManager;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final bool isDesktop;

  const MyApp({
    Key? key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.chatMessageListener,
    required this.profileUpdateListener,
    required this.messageRouter,
    required this.pendingMessageRetrier,
    required this.bridge,
    required this.p2pService,
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
    required this.isDesktop,
  }) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isResuming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupForegroundPushListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Orderly teardown: retrier → listeners → router → service → bridge
    widget.pendingMessageRetrier.dispose();
    widget.profileUpdateListener.dispose();
    widget.chatMessageListener.dispose();
    widget.contactRequestListener.dispose();
    widget.messageRouter.dispose();
    widget.p2pService.dispose();
    widget.bridge.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_STATE_CHANGED',
      details: {'state': state.name},
    );

    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  Future<void> _onResumed() async {
    if (_isResuming) return;
    _isResuming = true;

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_RESUME_BEGIN',
      details: {},
    );

    try {
      // 1. Check bridge health — reinitialize if dead
      final bridgeOk = await widget.bridge.checkHealth();
      if (!bridgeOk) {
        await widget.bridge.reinitialize();
      }

      // 2. Immediate health check (re-dials relay, re-registers FCM)
      await widget.p2pService.performImmediateHealthCheck();

      // 3. Drain offline inbox (messages queued while backgrounded)
      await widget.p2pService.drainOfflineInbox();

      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_RESUME_COMPLETE',
        details: {'bridgeWasHealthy': bridgeOk},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_RESUME_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      _isResuming = false;
    }
  }

  void _setupForegroundPushListener() {
    if (widget.isDesktop) return;

    try {
      FirebaseMessaging.onMessage.listen((message) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_FOREGROUND_MESSAGE_RECEIVED',
          details: {'messageId': message.messageId},
        );
        widget.p2pService.drainOfflineInbox();
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_MESSAGE_OPENED_APP',
          details: {'messageId': message.messageId},
        );
        widget.p2pService.drainOfflineInbox();
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_FOREGROUND_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mknoon',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: StartupRouter(
        repository: widget.repository,
        contactRepository: widget.contactRepository,
        contactRequestRepository: widget.contactRequestRepository,
        contactRequestListener: widget.contactRequestListener,
        messageRepository: widget.messageRepository,
        mediaAttachmentRepository: widget.mediaAttachmentRepository,
        chatMessageListener: widget.chatMessageListener,
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        mediaFileManager: widget.mediaFileManager,
        secureKeyStore: widget.secureKeyStore,
        imageProcessor: widget.imageProcessor,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
