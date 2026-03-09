import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryContactRepository contactRepository;
  late FakeContactRequestRepository contactRequestRepository;
  late ContactRequestListener contactRequestListener;
  late InMemoryMessageRepository messageRepository;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepository;
  late ChatMessageListener chatMessageListener;
  late FakeIdentityRepository identityRepository;
  late FakeP2PService p2pService;
  late FakeMediaFileManager mediaFileManager;
  late FakeSecureKeyStore secureKeyStore;
  late ImageProcessor imageProcessor;

  const ownPeerId = 'own-peer-id-12345';

  final identity = IdentityModel(
    peerId: ownPeerId,
    publicKey: 'own-public-key',
    privateKey: 'own-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Alice',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  setUp(() {
    bridge = FakeBridge();
    bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
    bridge.responses['payload.sign'] = {'ok': true, 'signature': 'fakeSig'};
    bridge.responses['contactrequest.encrypt'] = {
      'ok': true,
      'ephemeralPublicKey': 'ephPubBase64',
      'ciphertext': 'ctBase64',
      'nonce': 'nonceBase64',
    };
    contactRepository = InMemoryContactRepository();
    contactRequestRepository = FakeContactRequestRepository();
    contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnPeerId: () => ownPeerId,
    );
    messageRepository = InMemoryMessageRepository();
    mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => null,
    );
    identityRepository = FakeIdentityRepository()..seed(identity);
    p2pService = FakeP2PService();
    mediaFileManager = FakeMediaFileManager();
    secureKeyStore = FakeSecureKeyStore();
    imageProcessor = ImageProcessor(
      compressFile:
          ({
            required path,
            required quality,
            required keepExif,
            minWidth = 1920,
            minHeight = 1080,
          }) async => null,
      compressVideo: ({required path, required compress, onProgress}) async =>
          null,
    );
  });

  Widget buildScanner({ShareIntentService? shareIntentService}) {
    return MaterialApp(
      home: QRScannerWired(
        bridge: bridge,
        contactRepository: contactRepository,
        contactRequestRepository: contactRequestRepository,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        chatMessageListener: chatMessageListener,
        identityRepository: identityRepository,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        ownPeerId: ownPeerId,
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
            }) async => null,
        shareIntentService: shareIntentService,
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    '5p: QR scan success with buffered intent navigates to feed and pushes picker',
    (tester) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'from qr'),
      );

      await tester.pumpWidget(
        buildScanner(shareIntentService: shareIntentService),
      );
      await pumpFrames(tester);

      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(_buildValidQrData());
      await pumpFrames(tester);

      expect(find.text('Added to your circle!'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await pumpFrames(tester, count: 20);

      expect(shareIntentService.isSettled, isTrue);
      expect(shareIntentService.hasPendingIntent, isFalse);
      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('from qr'), findsOneWidget);
    },
  );

  testWidgets(
    '5q: QR scan success without buffered intent navigates to feed only',
    (tester) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});

      await tester.pumpWidget(
        buildScanner(shareIntentService: shareIntentService),
      );
      await pumpFrames(tester);

      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(
        _buildValidQrData(peerId: 'new-peer-12345', username: 'Bob'),
      );
      await pumpFrames(tester);

      expect(find.text('Added to your circle!'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await pumpFrames(tester, count: 20);

      expect(shareIntentService.isSettled, isTrue);
      expect(shareIntentService.hasPendingIntent, isFalse);
      expect(find.byType(FeedWired), findsOneWidget);
      expect(find.text('Share with...'), findsNothing);
    },
  );
}

String _buildValidQrData({
  String peerId = 'scanned-peer-id',
  String publicKey = 'scanned-pk',
  String username = 'Bob',
}) {
  final payload = SplayTreeMap<String, dynamic>.from({
    'ns': peerId,
    'pk': publicKey,
    'rv': '/dns4/relay/tcp/443/p2p/relay',
    'ts': DateTime.now().toUtc().toIso8601String(),
    'un': username,
  });
  payload['sig'] = 'valid-sig';
  return jsonEncode(payload);
}
