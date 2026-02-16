import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/core/bridge/webview_js_bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'dart:io';

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI only on desktop platforms.
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('Smoke test: New user generates identity', (
    WidgetTester tester,
  ) async {
    print('\n========================================');
    print('SMOKE TEST: New User Identity Generation');
    print('========================================\n');

    // Use in-memory database for cross-platform integration test stability.
    const dbPath = inMemoryDatabasePath;

    print('[TEST] Step 1: Initialize database...');
    final db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        print('[TEST] Running identity table migration...');
        await runIdentityTableMigration(db);
        print('[TEST] Running messages table migration...');
        await runMessagesTableMigration(db);
        print('[TEST] Running ML-KEM keys migration...');
        await runMlKemKeysMigration(db);
      },
    );
    print('[TEST] Database initialized at: $dbPath');

    print('[TEST] Step 2: Create repository...');
    final repository = IdentityRepositoryImpl(
      dbLoadIdentityRow: () => dbLoadIdentityRow(db),
      dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
      secureKeyStore: _FakeSecureKeyStore(),
    );
    final contactRepository = ContactRepositoryImpl(
      dbLoadAllContacts: () => dbLoadAllContacts(db),
      dbLoadContact: (peerId) => dbLoadContact(db, peerId),
      dbUpsertContact: (row) => dbUpsertContact(db, row),
      dbDeleteContact: (peerId) => dbDeleteContact(db, peerId),
      dbGetContactCount: () => dbGetContactCount(db),
      dbContactExists: (peerId) => dbContactExists(db, peerId),
    );
    final contactRequestRepository = ContactRequestRepositoryImpl(
      dbLoadPendingRequests: () => dbLoadPendingRequests(db),
      dbLoadRequest: (peerId) => dbLoadRequest(db, peerId),
      dbUpsertRequest: (row) => dbUpsertRequest(db, row),
      dbUpdateRequestStatus: (peerId, status) =>
          dbUpdateRequestStatus(db, peerId, status),
      dbDeleteRequest: (peerId) => dbDeleteRequest(db, peerId),
      dbRequestExists: (peerId) => dbRequestExists(db, peerId),
    );
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

    final p2pService = P2PServiceImpl(bridge: bridge);
    final contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnPeerId: () => '',
    );
    final chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async {
        final identity = await repository.loadIdentity();
        return identity?.mlKemSecretKey;
      },
    );

    print('[TEST] Step 4: Build app widget...');
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );

    // Wait for initial load with a bounded loop (screen has ongoing animations).
    print('[TEST] Step 5: Wait for app to load...');
    final newUserButton = find.text("I'm new here");
    for (var i = 0; i < 20 && newUserButton.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // Look for "I'm new here" button
    print('[TEST] Step 6: Looking for "I\'m new here" button...');

    if (newUserButton.evaluate().isEmpty) {
      print('[TEST] ERROR: Could not find "I\'m new here" button');
      print('[TEST] Current widget tree:');
      debugDumpApp();
      fail('Button not found');
    }

    print('[TEST] Found button, tapping...');
    await tester.ensureVisible(newUserButton.first);
    await tester.tap(newUserButton.first, warnIfMissed: false);
    await tester.pump();

    print('[TEST] Step 7: Waiting for identity generation...');
    // Wait for async operations with a hard timeout.
    Map<String, Object?>? identityRow;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      identityRow = await dbLoadIdentityRow(db);
      if (identityRow != null) {
        break;
      }
    }

    print('[TEST] Step 8: Checking results...');

    if (identityRow != null) {
      print('\n========================================');
      print('SUCCESS! Identity generated:');
      print('========================================');
      print('Peer ID: ${identityRow['peer_id']}');
      print('Mnemonic: ${identityRow['mnemonic12']}');
      print(
        'Public Key: ${identityRow['public_key']?.toString().substring(0, 20)}...',
      );
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
    contactRequestListener.dispose();
    chatMessageListener.dispose();
    p2pService.dispose();
    bridge.dispose();
    await db.close();
  });
}
