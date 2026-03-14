import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_screen.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeContactRequestRepository contactRequestRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeSecureKeyStore secureKeyStore;
  late InMemoryMessageRepository messageRepo;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;
  late ImageProcessor imageProcessor;
  late ContactRequestListener contactRequestListener;
  late ChatMessageListener chatMessageListener;

  final testIdentity = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Alice',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  setUp(() {
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    contactRequestRepo = FakeContactRequestRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService();
    secureKeyStore = FakeSecureKeyStore();
    messageRepo = InMemoryMessageRepository();
    mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();
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

    contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => '',
    );

    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => null,
    );

    // Mock path_provider channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return '/tmp/test_docs';
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  Widget buildFTE({
    ContactRequestListener? overrideListener,
    ShareIntentService? shareIntentService,
  }) {
    return MaterialApp(
      home: FirstTimeExperienceWired(
        repository: identityRepo,
        contactRepository: contactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: overrideListener ?? contactRequestListener,
        messageRepository: messageRepo,
        mediaAttachmentRepository: mediaAttachmentRepo,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        imageProcessor: imageProcessor,
        secureKeyStore: secureKeyStore,
        shareIntentService: shareIntentService,
      ),
    );
  }

  group('FirstTimeExperienceWired', () {
    testWidgets('shows QR shimmer before post-frame QR generation completes', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());

      expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('loads identity and generates QR data after first frame', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump(); // trigger post-frame callback
      await tester.pump(); // let async resolve

      // Identity was loaded
      expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
      // Bridge was called for signing
      expect(bridge.sendCallCount, greaterThanOrEqualTo(1));
      expect(bridge.lastCommand, 'payload.sign');

      // The widget rendered without errors — find the screen
      expect(find.byType(FirstTimeExperienceScreen), findsOneWidget);
    });

    testWidgets('replaces shimmer with QR image after QR data loads', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsOneWidget);

      await tester.pump();
      await tester.pump();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsNothing);
    });

    testWidgets('displays username from loaded identity', (tester) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // The EditableUsernameWidget shows 'mknoon/' prefix and '@Alice'
      expect(find.textContaining('Alice'), findsOneWidget);
    });

    testWidgets('updates username and regenerates QR', (tester) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // Verify initial username is displayed
      expect(find.textContaining('Alice'), findsOneWidget);

      // Tap on the username area to start editing (GestureDetector wrapping the username row)
      await tester.tap(find.textContaining('Alice'));
      await tester.pump();

      // Now a TextField should be visible for editing
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      // Clear and type new username
      await tester.enterText(textFieldFinder, 'Bob');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      // Identity should have been saved with new username
      expect(identityRepo.saveIdentityCallCount, greaterThanOrEqualTo(1));
      expect(identityRepo.lastSavedIdentity?.username, 'Bob');

      // Bridge should be called again for QR regeneration (2 total: initial + after rename)
      expect(bridge.sendCallCount, greaterThanOrEqualTo(2));
    });

    testWidgets('scan button exists and is tappable', (tester) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // The ScanFriendCard contains the text "Scan a friend's code"
      final scanCardFinder = find.text("Scan a friend's code");
      expect(scanCardFinder, findsOneWidget);

      // Also verify the arrow icon exists (part of ScanFriendCard)
      expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);

      // Verify the crop_free icon (the scan icon) is present
      expect(find.byIcon(Icons.crop_free), findsOneWidget);
    });

    testWidgets('does not crash when contact request stream emits', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      // Create a controllable request stream that emits ContactRequestModel directly
      final requestController =
          StreamController<ContactRequestModel>.broadcast();

      // Build a custom ContactRequestListener that we can emit on.
      // Instead of going through the raw ChatMessage processing pipeline,
      // we directly test the widget's subscription by using a listener
      // whose requestStream we control.
      final customListener = _FakeContactRequestListener(
        requestStream: requestController.stream,
      );

      await tester.pumpWidget(buildFTE(overrideListener: customListener));
      await tester.pump();
      await tester.pump();

      // Emit a contact request on the stream
      final request = ContactRequestModel(
        peerId: 'sender-peer-id-1234567890',
        publicKey: 'sender-pub-key',
        rendezvous: '/p2p-circuit/relay',
        username: 'Charlie',
        signature: 'sender-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
      );

      requestController.add(request);
      await tester.pump();
      await tester.pump();

      // The ContactRequestDialog should appear with the username
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('wants to connect with you'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      await requestController.close();
    });

    testWidgets('handles missing identity gracefully', (tester) async {
      // Do NOT seed any identity — loadIdentity will return null
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // Should not crash — screen renders with default state
      expect(find.byType(FirstTimeExperienceScreen), findsOneWidget);

      // Identity was attempted to be loaded
      expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));

      // Bridge should NOT have been called (no identity => no signing needed)
      expect(bridge.sendCallCount, 0);

      // Username should be the default 'Username'
      expect(find.textContaining('Username'), findsOneWidget);
    });

    testWidgets('displays QR data in screen after payload build', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // After successful build, the FirstTimeExperienceScreen should have
      // non-null qrData. We can verify this by checking that the QrImageView
      // widget is present (it's rendered when qrData is non-null).
      // The QRCodeSection shows a QrImageView when data is provided.
      expect(find.byType(FirstTimeExperienceScreen), findsOneWidget);

      // When qrData is null, a shimmer/loading is shown.
      // When qrData is non-null, a QrImageView is rendered.
      // Find the QrImageView widget from qr_flutter package.
      // Since the import is from qr_flutter, let's look for it by type name.
      final qrImageFinder = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'QrImageView',
      );
      expect(qrImageFinder, findsOneWidget);
    });

    testWidgets('disposes subscription without errors', (tester) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // Now replace the widget to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('replaced'))),
      );
      await tester.pump();

      // If dispose throws, the test would fail. Reaching here means success.
      expect(find.text('replaced'), findsOneWidget);
    });

    testWidgets('accept success settles and replays a buffered share', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
      bridge.responses['contactrequest.encrypt'] = {
        'ok': true,
        'ephemeralPublicKey': 'ephemeral-pk',
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
      };

      final request = ContactRequestModel(
        peerId: 'sender-peer-id-1234567890',
        publicKey: 'sender-pub-key',
        rendezvous: '/p2p-circuit/relay',
        username: 'Charlie',
        signature: 'sender-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
      );
      contactRequestRepo.seed([request]);

      final requestController =
          StreamController<ContactRequestModel>.broadcast();
      final customListener = _FakeContactRequestListener(
        requestStream: requestController.stream,
      );
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'from onboarding'),
      );

      await tester.pumpWidget(
        buildFTE(
          overrideListener: customListener,
          shareIntentService: shareIntentService,
        ),
      );
      await tester.pump();
      await tester.pump();

      requestController.add(request);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(shareIntentService.isSettled, isTrue);
      expect(shareIntentService.hasPendingIntent, isFalse);
      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('from onboarding'), findsOneWidget);

      await requestController.close();
    });

    testWidgets('notPending still settles and replays a buffered share', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      final acceptedRequest = ContactRequestModel(
        peerId: 'sender-peer-id-accepted',
        publicKey: 'sender-pub-key',
        rendezvous: '/p2p-circuit/relay',
        username: 'Charlie',
        signature: 'sender-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
        status: ContactRequestStatus.accepted,
      );
      contactRequestRepo.seed([acceptedRequest]);
      await contactRepo.addContact(acceptedRequest.toContactModel());

      final requestController =
          StreamController<ContactRequestModel>.broadcast();
      final customListener = _FakeContactRequestListener(
        requestStream: requestController.stream,
      );
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'already added'),
      );

      await tester.pumpWidget(
        buildFTE(
          overrideListener: customListener,
          shareIntentService: shareIntentService,
        ),
      );
      await tester.pump();
      await tester.pump();

      requestController.add(acceptedRequest);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(shareIntentService.isSettled, isTrue);
      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('already added'), findsOneWidget);

      await requestController.close();
    });

    testWidgets(
      '5o: accept success without buffered intent navigates to feed only',
      (tester) async {
        identityRepo.seed(testIdentity);
        bridge.responses['payload.sign'] = {
          'ok': true,
          'signature': 'test-sig',
        };
        bridge.responses['contactrequest.encrypt'] = {
          'ok': true,
          'ephemeralPublicKey': 'ephemeral-pk',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        };

        final request = ContactRequestModel(
          peerId: 'sender-peer-id-feed-only',
          publicKey: 'sender-pub-key',
          rendezvous: '/p2p-circuit/relay',
          username: 'Charlie',
          signature: 'sender-sig',
          receivedAt: DateTime.now().toUtc().toIso8601String(),
        );
        contactRequestRepo.seed([request]);

        final requestController =
            StreamController<ContactRequestModel>.broadcast();
        final customListener = _FakeContactRequestListener(
          requestStream: requestController.stream,
        );
        final shareIntentService = ShareIntentService(resetShareIntent: () {});

        await tester.pumpWidget(
          buildFTE(
            overrideListener: customListener,
            shareIntentService: shareIntentService,
          ),
        );
        await tester.pump();
        await tester.pump();

        requestController.add(request);
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Accept'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        expect(shareIntentService.isSettled, isTrue);
        expect(shareIntentService.hasPendingIntent, isFalse);
        expect(find.text('Feed'), findsOneWidget);
        expect(find.text('Share with...'), findsNothing);

        await requestController.close();
      },
    );
  });
}

/// A minimal fake that exposes a controllable [requestStream] without
/// needing to process raw ChatMessages through the real listener pipeline.
class _FakeContactRequestListener extends ContactRequestListener {
  final Stream<ContactRequestModel> _overrideStream;

  _FakeContactRequestListener({
    required Stream<ContactRequestModel> requestStream,
  }) : _overrideStream = requestStream,
       super(
         contactRequestStream: const Stream<ChatMessage>.empty(),
         requestRepo: _NoOpContactRequestRepo(),
         contactRepo: _NoOpContactRepo(),
         bridge: FakeBridge(),
         getOwnPeerId: () => '',
       );

  @override
  Stream<ContactRequestModel> get requestStream => _overrideStream;
}

/// Minimal no-op repos for the fake listener constructor.
class _NoOpContactRequestRepo extends FakeContactRequestRepository {}

class _NoOpContactRepo extends FakeContactRepository {}
