import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_thread_summary.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
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
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
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
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMsgRepo;
  late StreamController<GroupMessage> groupMessageStreamController;

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
    groupRepo = InMemoryGroupRepository();
    groupMsgRepo = InMemoryGroupMessageRepository();
    groupMessageStreamController = StreamController<GroupMessage>.broadcast();
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
    groupMessageStreamController.close();
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
    _FakeGroupMessageListener? groupMessageListener,
    FakeContactRepository? contactRepository,
    InMemoryMessageRepository? messageRepository,
    InMemoryGroupRepository? groupRepository,
    InMemoryGroupMessageRepository? groupMessageRepository,
    bool wrapInNavigator = false,
    String? initialFilterTab,
    VoidCallback? onHeaderBuild,
    VoidCallback? onListBuild,
    List<NavigatorObserver>? navigatorObservers,
  }) {
    final effectiveContactRepo = contactRepository ?? contactRepo;
    final effectiveMessageRepo = messageRepository ?? messageRepo;
    final effectiveGroupRepo = groupRepository ?? groupRepo;
    final effectiveGroupMessageRepo = groupMessageRepository ?? groupMsgRepo;

    final crListener =
        contactRequestListener ??
        ContactRequestListener(
          contactRequestStream: const Stream<ChatMessage>.empty(),
          requestRepo: contactRequestRepo,
          contactRepo: effectiveContactRepo,
          bridge: bridge,
          getOwnPeerId: () => '',
        );

    final cmListener =
        chatMessageListener ??
        ChatMessageListener(
          chatMessageStream: const Stream<ChatMessage>.empty(),
          messageRepo: effectiveMessageRepo,
          contactRepo: effectiveContactRepo,
        );

    final gmListener =
        groupMessageListener ??
        _FakeGroupMessageListener(groupMessageStreamController.stream);

    final orbitWidget = OrbitWired(
      identityRepo: identityRepo,
      contactRepo: effectiveContactRepo,
      contactRequestRepo: contactRequestRepo,
      contactRequestListener: crListener,
      messageRepo: effectiveMessageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      chatMessageListener: cmListener,
      bridge: bridge,
      p2pService: p2pService,
      mediaFileManager: mediaFileManager,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      groupRepository: effectiveGroupRepo,
      groupMessageRepository: effectiveGroupMessageRepo,
      groupMessageListener: gmListener,
      initialFilterTab: initialFilterTab,
      debugOnHeaderBuild: onHeaderBuild,
      debugOnListBuild: onListBuild,
    );

    if (wrapInNavigator) {
      return MaterialApp(
        navigatorObservers: navigatorObservers ?? const <NavigatorObserver>[],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => orbitWidget));
                },
                child: const Text('Open Orbit'),
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      navigatorObservers: navigatorObservers ?? const <NavigatorObserver>[],
      home: orbitWidget,
    );
  }

  Future<void> pumpOrbitFrames(WidgetTester tester, {int count = 3}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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

      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-1',
          contactPeerId: 'contact-peer-id',
          text: 'Hello from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // FriendRow renders the current display name
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets('cold load batches friend thread summaries', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final spyContactRepo = _SpyContactRepository();
      final spyMessageRepo = _SpyMessageRepository();
      spyContactRepo.seed([
        testContact,
        testContact.copyWith(peerId: 'contact-peer-id-2', username: 'Cara'),
      ]);

      await tester.pumpWidget(
        buildOrbitWired(
          contactRepository: spyContactRepo,
          messageRepository: spyMessageRepo,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(spyContactRepo.getActiveContactsCallCount, 1);
      expect(spyContactRepo.getArchivedContactsCallCount, 1);
      expect(spyMessageRepo.getConversationThreadSummariesCallCount, 1);
      expect(
        spyMessageRepo.getConversationThreadSummaryCallCountByPeerId,
        isEmpty,
      );
      expect(
        spyMessageRepo.getMessageCountForContactCallCountByPeerId,
        isEmpty,
      );
      expect(
        spyMessageRepo.getLatestMessageForContactCallCountByPeerId,
        isEmpty,
      );
      expect(spyMessageRepo.getUnreadCountForContactCallCountByPeerId, isEmpty);
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
      // The trigger itself is icon-only; the placeholder lives in the dock.
      expect(
        find.descendant(
          of: find.byType(OrbitSearchTrigger),
          matching: find.byIcon(Icons.search),
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

    testWidgets('refreshes only the affected friend on incoming message', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);
      final spyContactRepo = _SpyContactRepository();
      final spyMessageRepo = _SpyMessageRepository();
      spyContactRepo.seed([
        testContact,
        testContact.copyWith(peerId: 'contact-peer-id-2', username: 'Cara'),
      ]);

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: spyMessageRepo,
        contactRepo: spyContactRepo,
      );

      await tester.pumpWidget(
        buildOrbitWired(
          chatMessageListener: fakeChatListener,
          contactRepository: spyContactRepo,
          messageRepository: spyMessageRepo,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Initially Bob exists as a friend but has no last activity text
      expect(find.text('Bob'), findsWidgets);

      spyContactRepo.resetTracking();
      spyMessageRepo.resetTracking();

      // Seed a message and emit an incoming chat event to trigger a
      // single-friend refresh, not a full Orbit reload.
      await spyMessageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-refresh-1',
          contactPeerId: 'contact-peer-id',
          text: 'New hello from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      fakeChatListener.emitIncomingMessage(
        ConversationMessage(
          id: 'msg-refresh-1',
          contactPeerId: 'contact-peer-id',
          text: 'New hello from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // After refresh, the FriendRow should show the last activity text
      expect(find.text('New hello from Bob'), findsOneWidget);
      expect(spyContactRepo.getActiveContactsCallCount, 0);
      expect(spyContactRepo.getArchivedContactsCallCount, 0);
      expect(spyContactRepo.getContactCallCountByPeerId, {
        'contact-peer-id': 1,
      });
      expect(spyMessageRepo.getConversationThreadSummaryCallCountByPeerId, {
        'contact-peer-id': 1,
      });
      expect(spyMessageRepo.getConversationThreadSummariesCallCount, 0);
      expect(
        spyMessageRepo.getMessageCountForContactCallCountByPeerId,
        isEmpty,
      );
      expect(
        spyMessageRepo.getLatestMessageForContactCallCountByPeerId,
        isEmpty,
      );
      expect(spyMessageRepo.getUnreadCountForContactCallCountByPeerId, isEmpty);
    });

    testWidgets(
      'search context is preserved while unrelated friend updates arrive',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final spyContactRepo = _SpyContactRepository();
        final spyMessageRepo = _SpyMessageRepository();
        spyContactRepo.seed([
          testContact,
          testContact.copyWith(peerId: 'contact-peer-id-2', username: 'Cara'),
        ]);

        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: spyMessageRepo,
          contactRepo: spyContactRepo,
        );

        await tester.pumpWidget(
          buildOrbitWired(
            chatMessageListener: fakeChatListener,
            contactRepository: spyContactRepo,
            messageRepository: spyMessageRepo,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.byType(OrbitSearchTrigger));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.enterText(find.byType(TextField), 'Bo');
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Bob'), findsWidgets);
        expect(find.text('Cara'), findsNothing);

        await spyMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-refresh-cara',
            contactPeerId: 'contact-peer-id-2',
            text: 'Cara says hi',
            senderPeerId: 'contact-peer-id-2',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        fakeChatListener.emitIncomingMessage(
          ConversationMessage(
            id: 'msg-refresh-cara',
            contactPeerId: 'contact-peer-id-2',
            text: 'Cara says hi',
            senderPeerId: 'contact-peer-id-2',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Bob'), findsWidgets);
        expect(find.text('Cara'), findsNothing);
        final searchField = tester.widget<TextField>(find.byType(TextField));
        expect(searchField.controller!.text, 'Bo');
      },
    );

    testWidgets(
      'typing search updates the list without rebuilding the header',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([
          testContact,
          testContact.copyWith(peerId: 'contact-peer-id-2', username: 'Cara'),
        ]);

        var headerBuildCount = 0;
        var listBuildCount = 0;

        await tester.pumpWidget(
          buildOrbitWired(
            onHeaderBuild: () => headerBuildCount++,
            onListBuild: () => listBuildCount++,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.byType(OrbitSearchTrigger));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        final headerBuildsBeforeTyping = headerBuildCount;
        final listBuildsBeforeTyping = listBuildCount;

        await tester.enterText(find.byType(TextField), 'Bo');
        await tester.pump(const Duration(milliseconds: 100));

        expect(headerBuildCount, headerBuildsBeforeTyping);
        expect(listBuildCount, greaterThan(listBuildsBeforeTyping));
        expect(find.text('Bob'), findsWidgets);
        expect(find.text('Cara'), findsNothing);
      },
    );

    testWidgets('shows contact request dialog on incoming request', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final fakeRequestListener = _FakeContactRequestListener(
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      await tester.pumpWidget(
        buildOrbitWired(contactRequestListener: fakeRequestListener),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Emit a contact request
      fakeRequestListener.emitRequest(
        ContactRequestModel(
          peerId: 'requester-peer-id',
          publicKey: 'requester-pk',
          rendezvous: '/dns4/relay',
          username: 'Charlie',
          signature: 'req-sig',
          receivedAt: DateTime.now().toUtc().toIso8601String(),
          status: ContactRequestStatus.pending,
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The ContactRequestDialog should appear with Charlie's name
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('wants to connect with you'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('disposes stream subscriptions without errors', (tester) async {
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

      await tester.pumpWidget(
        buildOrbitWired(
          chatMessageListener: fakeChatListener,
          contactRequestListener: fakeRequestListener,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Replace the widget tree with something else to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Replaced'))),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // No crash or error means subscriptions and animation controllers
      // were all disposed cleanly
      expect(find.text('Replaced'), findsOneWidget);
    });

    testWidgets('shows ExpandableFab with + icon', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // ExpandableFab is now in OrbitScreen
      expect(find.byType(ExpandableFab), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets(
      'tapping FAB opens menu with New Group and New Announce',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildOrbitWired());
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('New Group'), findsOneWidget);
        expect(find.text('New Announce'), findsOneWidget);
      },
    );

    testWidgets('displays group rows when groups exist', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Group name should appear in the list
      expect(find.text('Alpha Group'), findsOneWidget);
    });

    testWidgets('displays group rows with latest message preview', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );

      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          text: 'Hello group!',
          timestamp: DateTime.utc(2026, 3, 1),
          isIncoming: true,
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      );

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.text('Alice: Hello group!'), findsOneWidget);
    });

    testWidgets('refreshes only the affected group on incoming group message', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);
      final spyContactRepo = _SpyContactRepository();
      final spyMessageRepo = _SpyMessageRepository();
      final spyGroupRepo = _SpyGroupRepository();
      final spyGroupMsgRepo = _SpyGroupMessageRepository();

      await spyGroupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );

      await tester.pumpWidget(
        buildOrbitWired(
          contactRepository: spyContactRepo,
          messageRepository: spyMessageRepo,
          groupRepository: spyGroupRepo,
          groupMessageRepository: spyGroupMsgRepo,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Initially group shows with no message preview
      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.text('Bob: New group msg'), findsNothing);

      spyContactRepo.resetTracking();
      spyMessageRepo.resetTracking();
      spyGroupRepo.resetTracking();
      spyGroupMsgRepo.resetTracking();

      // Seed a group message and emit on the group message stream
      final newMsg = GroupMessage(
        id: 'gm-new',
        groupId: 'g-1',
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        text: 'New group msg',
        timestamp: DateTime.utc(2026, 3, 2),
        isIncoming: true,
        createdAt: DateTime.utc(2026, 3, 2),
      );
      await spyGroupMsgRepo.saveMessage(newMsg);
      groupMessageStreamController.add(newMsg);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Bob: New group msg'), findsOneWidget);
      expect(spyContactRepo.getActiveContactsCallCount, 0);
      expect(spyContactRepo.getArchivedContactsCallCount, 0);
      expect(spyGroupRepo.getActiveGroupsCallCount, 0);
      expect(spyGroupRepo.getAllGroupsCallCount, 0);
      expect(spyGroupRepo.getGroupCallCountById, {'g-1': 1});
      expect(spyGroupMsgRepo.getGroupThreadSummaryCallCountByGroupId, {
        'g-1': 1,
      });
      expect(spyGroupMsgRepo.getGroupThreadSummariesCallCount, 0);
      expect(spyGroupMsgRepo.getLatestMessageCallCountByGroupId, isEmpty);
      expect(spyGroupMsgRepo.getUnreadCountCallCountByGroupId, isEmpty);
    });

    testWidgets('create-group route result refreshes only the affected group', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final spyGroupRepo = _SpyGroupRepository();
      final spyGroupMsgRepo = _SpyGroupMessageRepository();
      await spyGroupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );

      await tester.pumpWidget(
        buildOrbitWired(
          groupRepository: spyGroupRepo,
          groupMessageRepository: spyGroupMsgRepo,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      spyGroupRepo.resetTracking();
      spyGroupMsgRepo.resetTracking();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('New Group'));
      await tester.pump(const Duration(milliseconds: 300));

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop(const FeedRouteChanges(changedGroupIds: {'g-1'}));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(spyGroupRepo.getActiveGroupsCallCount, 0);
      expect(spyGroupRepo.getAllGroupsCallCount, 0);
      expect(spyGroupRepo.getGroupCallCountById, {'g-1': 1});
      expect(spyGroupMsgRepo.getGroupThreadSummariesCallCount, 0);
      expect(spyGroupMsgRepo.getGroupThreadSummaryCallCountByGroupId, {
        'g-1': 1,
      });
    });

    testWidgets('interleaves groups and friends sorted by last activity', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      // Add a friend with an older message
      contactRepo.seed([testContact]);
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-old',
          contactPeerId: 'contact-peer-id',
          text: 'Old message from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: '2026-01-01T00:00:00.000Z',
          isIncoming: true,
          status: 'delivered',
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
      );

      // Add a group with a newer message
      await groupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Newer Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          text: 'Recent group msg',
          timestamp: DateTime.utc(2026, 3, 1),
          isIncoming: true,
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      );

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Both should appear
      expect(find.text('Newer Group'), findsOneWidget);
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets(
      'friend tap pushes conversation route before read marking completes',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([testContact]);
        final delayedMessageRepo = _DelayedSpyMessageRepository()
          ..markConversationAsReadGate = Completer<void>();
        final observer = _RecordingNavigatorObserver();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            messageRepository: delayedMessageRepo,
            navigatorObservers: [observer],
          ),
        );
        await pumpOrbitFrames(tester);

        observer.reset();

        await tester.tap(find.text('Bob').first);
        await tester.pump();

        expect(observer.pushCount, 1);
        expect(observer.lastPushedRoute, isNotNull);

        delayedMessageRepo.markConversationAsReadGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );

    testWidgets(
      'pushed conversation route shows loading shell before delayed initial page resolves',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([testContact]);
        final delayedMessageRepo = _DelayedSpyMessageRepository()
          ..markConversationAsReadGate = Completer<void>()
          ..getMessagesPageGate = Completer<void>();
        final observer = _RecordingNavigatorObserver();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            messageRepository: delayedMessageRepo,
            navigatorObservers: [observer],
          ),
        );
        await pumpOrbitFrames(tester);

        observer.reset();

        await tester.tap(find.text('Bob').first);
        await tester.pump();
        await pumpOrbitFrames(tester, count: 2);

        expect(observer.pushCount, 1);
        expect(
          find.byKey(const ValueKey('conversation-loading-shell')),
          findsOneWidget,
        );
        expect(find.byType(ConversationHeader), findsOneWidget);
        expect(find.text('Write something...'), findsOneWidget);

        delayedMessageRepo.markConversationAsReadGate!.complete();
        delayedMessageRepo.getMessagesPageGate!.complete();
        await pumpOrbitFrames(tester, count: 6);
      },
    );

    testWidgets(
      'all tab renders active friends before archived hydration completes',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([testContact]);
        delayedContactRepo.archivedContactsGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(contactRepository: delayedContactRepo),
        );
        await pumpOrbitFrames(tester);

        expect(find.text('Bob'), findsWidgets);

        delayedContactRepo.archivedContactsGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );

    testWidgets(
      'all tab renders active groups before archived hydration completes',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedGroupRepo = _DelayedSpyGroupRepository()
          ..allGroupsGate = Completer<void>();
        await delayedGroupRepo.saveGroup(
          GroupModel(
            id: 'g-active',
            name: 'Alpha Group',
            type: GroupType.chat,
            topicName: 'topic-g-active',
            createdAt: DateTime.utc(2026, 3, 1),
            createdBy: 'peer-admin',
            myRole: GroupRole.admin,
          ),
        );

        await tester.pumpWidget(
          buildOrbitWired(groupRepository: delayedGroupRepo),
        );
        await pumpOrbitFrames(tester);

        expect(find.text('Alpha Group'), findsOneWidget);

        delayedGroupRepo.allGroupsGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );

    testWidgets(
      'archived tab shows loading placeholders before archived data resolves',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([
            testContact.copyWith(
              isArchived: true,
              archivedAt: DateTime.utc(2026, 3, 1).toIso8601String(),
            ),
          ])
          ..archivedContactsGate = Completer<void>();
        final delayedGroupRepo = _DelayedSpyGroupRepository()
          ..allGroupsGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            groupRepository: delayedGroupRepo,
            initialFilterTab: 'archived',
          ),
        );
        await pumpOrbitFrames(tester);

        expect(
          find.byKey(const ValueKey('orbit-loading-row-0')),
          findsOneWidget,
        );
        expect(find.text('No archived friends yet'), findsNothing);

        delayedContactRepo.archivedContactsGate!.complete();
        delayedGroupRepo.allGroupsGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );

    testWidgets(
      'archived tab swaps placeholders for archived rows when archived hydration completes',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([
            testContact.copyWith(
              isArchived: true,
              archivedAt: DateTime.utc(2026, 3, 1).toIso8601String(),
            ),
          ])
          ..archivedContactsGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            initialFilterTab: 'archived',
          ),
        );
        await pumpOrbitFrames(tester);

        expect(
          find.byKey(const ValueKey('orbit-loading-row-0')),
          findsOneWidget,
        );

        delayedContactRepo.archivedContactsGate!.complete();
        await pumpOrbitFrames(tester, count: 6);

        expect(find.byKey(const ValueKey('orbit-loading-row-0')), findsNothing);
        expect(find.text('Bob'), findsWidgets);
      },
    );

    testWidgets(
      'background archived hydration does not replace visible all-tab rows with placeholders',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([testContact])
          ..archivedContactsGate = Completer<void>();
        final delayedGroupRepo = _DelayedSpyGroupRepository()
          ..allGroupsGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            groupRepository: delayedGroupRepo,
          ),
        );
        await pumpOrbitFrames(tester);

        expect(find.text('Bob'), findsWidgets);
        expect(find.byKey(const ValueKey('orbit-loading-row-0')), findsNothing);

        delayedContactRepo.archivedContactsGate!.complete();
        delayedGroupRepo.allGroupsGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    pushCount++;
    lastPushedRoute = route;
  }

  void reset() {
    lastPushedRoute = null;
    pushCount = 0;
  }
}

class _SpyContactRepository extends FakeContactRepository {
  int getActiveContactsCallCount = 0;
  int getArchivedContactsCallCount = 0;
  final Map<String, int> getContactCallCountByPeerId = {};

  @override
  Future<ContactModel?> getContact(String peerId) async {
    getContactCallCountByPeerId.update(
      peerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getContact(peerId);
  }

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    getActiveContactsCallCount++;
    return super.getActiveContacts();
  }

  @override
  Future<List<ContactModel>> getArchivedContacts() async {
    getArchivedContactsCallCount++;
    return super.getArchivedContacts();
  }

  void resetTracking() {
    getActiveContactsCallCount = 0;
    getArchivedContactsCallCount = 0;
    getContactCallCountByPeerId.clear();
  }
}

class _SpyMessageRepository extends InMemoryMessageRepository {
  final Map<String, int> getMessageCountForContactCallCountByPeerId = {};
  final Map<String, int> getLatestMessageForContactCallCountByPeerId = {};
  final Map<String, int> getUnreadCountForContactCallCountByPeerId = {};
  int getConversationThreadSummariesCallCount = 0;
  final Map<String, int> getConversationThreadSummaryCallCountByPeerId = {};

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async {
    getMessageCountForContactCallCountByPeerId.update(
      contactPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getMessageCountForContact(contactPeerId);
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    getLatestMessageForContactCallCountByPeerId.update(
      contactPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getLatestMessageForContact(contactPeerId);
  }

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async {
    getUnreadCountForContactCallCountByPeerId.update(
      contactPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getUnreadCountForContact(contactPeerId);
  }

  @override
  Future<ConversationThreadSummary> getConversationThreadSummary(
    String contactPeerId,
  ) {
    getConversationThreadSummaryCallCountByPeerId.update(
      contactPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getConversationThreadSummary(contactPeerId);
  }

  @override
  Future<Map<String, ConversationThreadSummary>> getConversationThreadSummaries(
    Iterable<String> contactPeerIds,
  ) {
    getConversationThreadSummariesCallCount++;
    return super.getConversationThreadSummaries(contactPeerIds);
  }

  void resetTracking() {
    getMessageCountForContactCallCountByPeerId.clear();
    getLatestMessageForContactCallCountByPeerId.clear();
    getUnreadCountForContactCallCountByPeerId.clear();
    getConversationThreadSummariesCallCount = 0;
    getConversationThreadSummaryCallCountByPeerId.clear();
  }
}

class _SpyGroupRepository extends InMemoryGroupRepository {
  int getActiveGroupsCallCount = 0;
  int getAllGroupsCallCount = 0;
  final Map<String, int> getGroupCallCountById = {};

  @override
  Future<List<GroupModel>> getActiveGroups() async {
    getActiveGroupsCallCount++;
    return super.getActiveGroups();
  }

  @override
  Future<List<GroupModel>> getAllGroups() async {
    getAllGroupsCallCount++;
    return super.getAllGroups();
  }

  @override
  Future<GroupModel?> getGroup(String id) async {
    getGroupCallCountById.update(id, (count) => count + 1, ifAbsent: () => 1);
    return super.getGroup(id);
  }

  void resetTracking() {
    getActiveGroupsCallCount = 0;
    getAllGroupsCallCount = 0;
    getGroupCallCountById.clear();
  }
}

class _SpyGroupMessageRepository extends InMemoryGroupMessageRepository {
  final Map<String, int> getLatestMessageCallCountByGroupId = {};
  final Map<String, int> getUnreadCountCallCountByGroupId = {};
  int getGroupThreadSummariesCallCount = 0;
  final Map<String, int> getGroupThreadSummaryCallCountByGroupId = {};

  @override
  Future<GroupMessage?> getLatestMessage(String groupId) async {
    getLatestMessageCallCountByGroupId.update(
      groupId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getLatestMessage(groupId);
  }

  @override
  Future<int> getUnreadCount(String groupId) async {
    getUnreadCountCallCountByGroupId.update(
      groupId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getUnreadCount(groupId);
  }

  @override
  Future<GroupThreadSummary> getGroupThreadSummary(String groupId) {
    getGroupThreadSummaryCallCountByGroupId.update(
      groupId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getGroupThreadSummary(groupId);
  }

  @override
  Future<Map<String, GroupThreadSummary>> getGroupThreadSummaries(
    Iterable<String> groupIds,
  ) {
    getGroupThreadSummariesCallCount++;
    return super.getGroupThreadSummaries(groupIds);
  }

  void resetTracking() {
    getLatestMessageCallCountByGroupId.clear();
    getUnreadCountCallCountByGroupId.clear();
    getGroupThreadSummariesCallCount = 0;
    getGroupThreadSummaryCallCountByGroupId.clear();
  }
}

class _DelayedSpyContactRepository extends _SpyContactRepository {
  Completer<void>? archivedContactsGate;

  @override
  Future<List<ContactModel>> getArchivedContacts() async {
    final gate = archivedContactsGate;
    if (gate != null) {
      await gate.future;
    }
    return super.getArchivedContacts();
  }
}

class _DelayedSpyMessageRepository extends _SpyMessageRepository {
  Completer<void>? markConversationAsReadGate;
  Completer<void>? getMessagesPageGate;

  @override
  Future<int> markConversationAsRead(String contactPeerId) async {
    final gate = markConversationAsReadGate;
    if (gate != null) {
      await gate.future;
    }
    return super.markConversationAsRead(contactPeerId);
  }

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    final gate = getMessagesPageGate;
    if (gate != null) {
      await gate.future;
    }
    return super.getMessagesPage(
      contactPeerId,
      limit: limit,
      beforeTimestamp: beforeTimestamp,
    );
  }
}

class _DelayedSpyGroupRepository extends _SpyGroupRepository {
  Completer<void>? allGroupsGate;

  @override
  Future<List<GroupModel>> getAllGroups() async {
    final gate = allGroupsGate;
    if (gate != null) {
      await gate.future;
    }
    return super.getAllGroups();
  }
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
    required super.messageRepo,
    required super.contactRepo,
  }) : super(chatMessageStream: const Stream.empty());

  @override
  Stream<ConversationMessage> get incomingMessageStream =>
      _incomingController.stream;

  @override
  Stream<ContactModel> get contactUpdatedStream =>
      _contactUpdateController.stream;

  void emitIncomingMessage(ConversationMessage msg) =>
      _incomingController.add(msg);

  @override
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
    required super.requestRepo,
    required super.contactRepo,
    required super.bridge,
  }) : super(
         contactRequestStream: const Stream.empty(),
         getOwnPeerId: () => '',
       );

  @override
  Stream<ContactRequestModel> get requestStream => _controller.stream;

  void emitRequest(ContactRequestModel request) => _controller.add(request);
}

/// Fake [GroupMessageListener] with a controllable stream for testing.
class _FakeGroupMessageListener extends GroupMessageListener {
  final Stream<GroupMessage> _externalStream;

  _FakeGroupMessageListener(this._externalStream)
    : super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;
}

class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpMsgRepo implements GroupMessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
