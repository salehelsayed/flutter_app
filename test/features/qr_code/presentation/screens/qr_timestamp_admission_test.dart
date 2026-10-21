import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../contact_request/presentation/support/contact_request_sql_fixture.dart';

void main() {
  group('CR-025 QR timestamp admission through the real scanner', () {
    for (final entry in <({String label, String timestamp, String error})>[
      (
        label: 'older than24h',
        timestamp: '2000-01-01T00:00:00.000Z',
        error: 'Expired QR Code',
      ),
      (
        label: 'unreadable timestamp',
        timestamp: 'not-a-time',
        error: 'Invalid QR Code',
      ),
      (
        label: 'future timestamp',
        timestamp: '2099-01-01T00:00:00.000Z',
        error: 'Invalid QR Code',
      ),
    ]) {
      // testWidgets accepts only bool skip; its one-case group retains the exact reason.
      group(entry.label, () {
        testWidgets('is refused without contact or outbound request', (
          tester,
        ) async {
          final h = await _mount(tester);
          await h.scan(tester, entry.timestamp);
          expect(await tester.runAsync(h.contacts.getAllContacts), isEmpty);
          expect(await tester.runAsync(h.requests.getPendingRequests), isEmpty);
          expect(h.network.sendMessageCallCount, 0);
          expect(h.network.storeInInboxCallCount, 0);
          expect(h.bridge.encrypts, isEmpty);
          if (entry.error == 'Expired QR Code') {
            expect(find.text(entry.error), findsOneWidget);
          } else {
            expect(
              find.byWidgetPredicate(
                (w) =>
                    w is Text &&
                    const {
                      'Invalid QR Code',
                      'Expired QR Code',
                    }.contains(w.data),
              ),
              findsOneWidget,
            );
          }
          if (entry.error == 'Expired QR Code') {
            expect(
              find.text(
                'This QR code has expired. Ask your friend for a new one.',
              ),
              findsOneWidget,
            );
          }
        });
      });
    }

    testWidgets('fresh signed control adds one contact and sends one request', (
      tester,
    ) async {
      final h = await _mount(tester);
      await h.scan(tester, DateTime.now().toUtc().toIso8601String());
      expect(find.text('Added to your circle!'), findsOneWidget);
      final contacts = await tester.runAsync(h.contacts.getAllContacts);
      expect(contacts?.map((c) => c.username).toList(), ['Bob']);
      expect(contacts?.single.peerId, h.sender.peerId);
      expect(await tester.runAsync(h.requests.getPendingRequests), isEmpty);
      expect(h.bridge.verifyCalls, 1);
      expect(h.bridge.encrypts, hasLength(1));
      expect(h.bridge.encrypts.single.recipientPublicKey, h.sender.publicKey);
      expect(h.network.sendMessageCallCount, 0);
      expect(h.network.storeInInboxCallCount, 1);
    });
  });
}

Future<_Scanner> _mount(WidgetTester tester) async {
  final db = (await tester.runAsync(openContactWidgetDatabase))!;
  addTearDown(db.close);
  final local = TestEd25519Identity.fromSeedByte(0x41);
  final sender = TestEd25519Identity.fromSeedByte(0x42);
  final crypto = Ed25519ContactRequestCryptoBus()
    ..register(local)
    ..register(sender);
  final bridge = Ed25519ContactRequestBridge(crypto);
  addTearDown(bridge.dispose);
  final keyStore = FakeSecureKeyStore();
  final identities = buildWidgetIdentityRepository(db, keyStore);
  await tester.runAsync(
    () => identities.saveIdentity(
      testIdentityModel(
        local,
        username: 'Alice',
        mlKemPublicKey: 'test-mlkem-local',
      ),
    ),
  );
  final contacts = buildWidgetContactRepository(db);
  final requests = buildWidgetRequestRepository(db);
  final messages = buildWidgetMessageRepository(db);
  final contactListener = ContactRequestListener(
    contactRequestStream: const Stream<ChatMessage>.empty(),
    requestRepo: requests,
    contactRepo: contacts,
    bridge: bridge,
    getOwnPeerId: () => local.peerId,
  );
  addTearDown(contactListener.dispose);
  final chatListener = ChatMessageListener(
    chatMessageStream: const Stream<ChatMessage>.empty(),
    messageRepo: messages,
    contactRepo: contacts,
  );
  addTearDown(chatListener.dispose);
  final network = FakeP2PService(storeInInboxResult: true)
    ..emitState(NodeState(isStarted: true, peerId: local.peerId));
  addTearDown(network.dispose);
  // Unmount before closing the owned listeners/database (tearDown is LIFO).
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: QRScannerWired(
        bridge: bridge,
        contactRepository: contacts,
        contactRequestRepository: requests,
        contactRequestListener: contactListener,
        messageRepository: messages,
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        chatMessageListener: chatListener,
        identityRepository: identities,
        p2pService: network,
        mediaFileManager: FakeMediaFileManager(),
        secureKeyStore: keyStore,
        imageProcessor: ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async => null,
          compressVideo:
              ({required path, required compress, onProgress}) async => null,
        ),
        ownPeerId: local.peerId,
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
              bool retryPendingRequest = false,
            }) async => null,
        shouldMarkContactRequest: (_) async => false,
      ),
    ),
  );
  final sent = (await tester.runAsync(() async => Completer<void>()))!;
  addTearDown(() => debugSetFlowEventSink(null));
  debugSetFlowEventSink((event) {
    if (event['event'] == 'CONTACT_REQUEST_SENT' && !sent.isCompleted) {
      sent.complete();
    }
  });
  return _Scanner(contacts, requests, bridge, network, sender, sent);
}

class _Scanner {
  _Scanner(
    this.contacts,
    this.requests,
    this.bridge,
    this.network,
    this.sender,
    this.sent,
  );
  final ContactRepository contacts;
  final ContactRequestRepository requests;
  final Ed25519ContactRequestBridge bridge;
  final FakeP2PService network;
  final TestEd25519Identity sender;
  final Completer<void> sent;

  Future<void> scan(WidgetTester tester, String timestamp) async {
    final payload = SplayTreeMap<String, dynamic>.from({
      'ns': sender.peerId,
      'pk': sender.publicKey,
      'rv': '/dns4/fixture.invalid/tcp/443/p2p/fixture',
      'ts': timestamp,
      'un': 'Bob',
    });
    payload['sig'] = sender.signBase64(jsonEncode(payload));
    // Use the scanner's production camera callback. All validation and writes remain real.
    await tester.runAsync(() async {
      final callback = tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned;
      // Its public camera type is void; production's arrow callback returns the real handler Future.
      final completion = Function.apply(callback, [jsonEncode(payload)]);
      expect(completion, isA<Future<void>>());
      await (completion as Future<void>);
      if (await contacts.contactExists(sender.peerId)) await sent.future;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}
