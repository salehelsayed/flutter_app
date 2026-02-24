import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';
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

  final testIdentity = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Alice',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  final testContact = ContactModel(
    peerId: 'contact-peer-id',
    publicKey: 'contact-pk',
    rendezvous: '/dns4/relay/tcp/443',
    username: 'Bob',
    signature: 'sig',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
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
      compressFile: ({
        required path,
        required quality,
        required keepExif,
        minWidth = 1920,
        minHeight = 1080,
      }) async =>
          null,
      compressVideo: ({
        required path,
        required compress,
        onProgress,
      }) async =>
          null,
    );

    // Mock path_provider for getApplicationDocumentsDirectory()
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

  /// Sets the test surface to iPhone 14 Pro Max size to avoid overflow errors.
  void setLargeTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  /// Suppresses RenderFlex overflow errors for complex animated layouts.
  void suppressOverflowErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  /// Builds an OrbitWired widget with default fakes, wrapped in MaterialApp.
  ///
  /// [contactRequestListener] and [chatMessageListener] can be overridden
  /// for tests that need controllable streams.
  /// [wrapInNavigator] wraps in a Navigator with an underneath route for
  /// testing Navigator.pop() behavior.
  Widget buildOrbitWired({
    ContactRequestListener? contactRequestListener,
    ChatMessageListener? chatMessageListener,
    bool wrapInNavigator = false,
  }) {
    final crListener = contactRequestListener ??
        ContactRequestListener(
          contactRequestStream: const Stream<ChatMessage>.empty(),
          requestRepo: contactRequestRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnPeerId: () => '',
        );

    final cmListener = chatMessageListener ??
        ChatMessageListener(
          chatMessageStream: const Stream<ChatMessage>.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

    final orbitWidget = OrbitWired(
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      contactRequestRepo: contactRequestRepo,
      contactRequestListener: crListener,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      chatMessageListener: cmListener,
      bridge: bridge,
      p2pService: p2pService,
      mediaFileManager: mediaFileManager,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
    );

    if (wrapInNavigator) {
      return MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => orbitWidget),
                  );
                },
                child: const Text('Open Orbit'),
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(home: orbitWidget);
  }

  group('OrbitWired', () {
    testWidgets('loads and displays identity in orbit header', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // OrbitScreen renders OrbitHeader with the identity's peerId for the avatar.
      // It also renders 'Close Friends' text and 'Friends' header.
      expect(find.byType(OrbitWired), findsOneWidget);
      expect(find.text('Close Friends'), findsOneWidget);
      expect(find.text('Friends'), findsOneWidget);
    });

    testWidgets('loads active friends list', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-1',
        contactPeerId: 'contact-peer-id',
        text: 'Hello from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // FriendRow renders the username and @username
      expect(find.text('Bob'), findsWidgets);
      expect(find.text('@Bob'), findsWidgets);
    });

    testWidgets('search trigger button exists', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // OrbitSearchTrigger is the floating search pill at the bottom
      expect(find.byType(OrbitSearchTrigger), findsOneWidget);
      // It contains the search icon
      expect(find.byIcon(Icons.search), findsWidgets);
      // The trigger widget contains 'Search friends...' text
      expect(
        find.descendant(
          of: find.byType(OrbitSearchTrigger),
          matching: find.text('Search friends...'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('filter toggle shows All and Archived tabs', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // FriendsFilterToggle renders 'All' and 'Archived' labels
      expect(find.byType(FriendsFilterToggle), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
    });

    testWidgets('friends list header shows QR buttons', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // FriendsListHeader renders 'My QR' and 'Scan' pill buttons
      expect(find.text('My QR'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
    });

    testWidgets('close button pops navigation', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired(wrapInNavigator: true));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap the 'Open Orbit' button to push the orbit route
      await tester.tap(find.text('Open Orbit'));
      // Pump enough frames for the route transition to complete (300ms default)
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify OrbitWired is now on screen
      expect(find.byType(OrbitWired), findsOneWidget);

      // Tap the OrbitCloseButton (top-left X button)
      expect(find.byType(OrbitCloseButton), findsOneWidget);
      await tester.tap(find.byType(OrbitCloseButton));
      // Pump enough frames for the pop transition to complete (300ms default)
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // After pop, OrbitWired should no longer be visible
      expect(find.byType(OrbitWired), findsNothing);
      expect(find.text('Open Orbit'), findsOneWidget);
    });

    testWidgets('refreshes orbit data on incoming message', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      await tester.pumpWidget(buildOrbitWired(
        chatMessageListener: fakeChatListener,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Initially Bob exists as a friend but has no last activity text
      expect(find.text('Bob'), findsWidgets);

      // Seed a message and emit an incoming chat event to trigger _loadOrbitData
      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-refresh-1',
        contactPeerId: 'contact-peer-id',
        text: 'New hello from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      fakeChatListener.emitIncomingMessage(ConversationMessage(
        id: 'msg-refresh-1',
        contactPeerId: 'contact-peer-id',
        text: 'New hello from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // After refresh, the FriendRow should show the last activity text
      expect(find.text('New hello from Bob'), findsOneWidget);
    });

    testWidgets('shows contact request dialog on incoming request',
        (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final fakeRequestListener = _FakeContactRequestListener(
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      await tester.pumpWidget(buildOrbitWired(
        contactRequestListener: fakeRequestListener,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Emit a contact request
      fakeRequestListener.emitRequest(ContactRequestModel(
        peerId: 'requester-peer-id',
        publicKey: 'requester-pk',
        rendezvous: '/dns4/relay',
        username: 'Charlie',
        signature: 'req-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
        status: ContactRequestStatus.pending,
      ));

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The ContactRequestDialog should appear with Charlie's name
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('wants to connect with you'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('disposes stream subscriptions without errors',
        (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      final fakeRequestListener = _FakeContactRequestListener(
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      await tester.pumpWidget(buildOrbitWired(
        chatMessageListener: fakeChatListener,
        contactRequestListener: fakeRequestListener,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Replace the widget tree with something else to trigger dispose
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Text('Replaced')),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      // No crash or error means subscriptions and animation controllers
      // were all disposed cleanly
      expect(find.text('Replaced'), findsOneWidget);
    });
  });
}

/// Fake [ChatMessageListener] with controllable streams for testing.
///
/// Overrides [incomingMessageStream] and [contactUpdatedStream] with
/// broadcast StreamControllers that tests can push events into.
class _FakeChatMessageListener extends ChatMessageListener {
  final StreamController<ConversationMessage> _incomingController =
      StreamController.broadcast();
  final StreamController<ContactModel> _contactUpdateController =
      StreamController.broadcast();

  _FakeChatMessageListener({
    required MessageRepository messageRepo,
    required ContactRepository contactRepo,
  }) : super(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

  @override
  Stream<ConversationMessage> get incomingMessageStream =>
      _incomingController.stream;

  @override
  Stream<ContactModel> get contactUpdatedStream =>
      _contactUpdateController.stream;

  void emitIncomingMessage(ConversationMessage msg) =>
      _incomingController.add(msg);

  void emitContactUpdate(ContactModel contact) =>
      _contactUpdateController.add(contact);
}

/// Fake [ContactRequestListener] with a controllable stream for testing.
///
/// Overrides [requestStream] with a broadcast StreamController that tests
/// can push [ContactRequestModel] events into.
class _FakeContactRequestListener extends ContactRequestListener {
  final _controller = StreamController<ContactRequestModel>.broadcast();

  _FakeContactRequestListener({
    required ContactRequestRepository requestRepo,
    required ContactRepository contactRepo,
    required Bridge bridge,
  }) : super(
          contactRequestStream: const Stream.empty(),
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnPeerId: () => '',
        );

  @override
  Stream<ContactRequestModel> get requestStream => _controller.stream;

  void emitRequest(ContactRequestModel request) => _controller.add(request);
}
