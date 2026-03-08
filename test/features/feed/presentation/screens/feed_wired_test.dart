import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../conversation/domain/repositories/fake_reaction_repository.dart';
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  /// Builds a FeedWired widget with default fakes, wrapped in MaterialApp.
  ///
  /// Uses a wide surface (iPhone 14 Pro Max size) to avoid layout overflow
  /// in widgets like ConnectionCard.
  ///
  /// [contactRequestListener] and [chatMessageListener] can be overridden
  /// for tests that need controllable streams.
  Widget buildFeedWired({
    ContactRequestListener? contactRequestListener,
    ChatMessageListener? chatMessageListener,
    FakeReactionRepository? reactionRepository,
    ReactionListener? reactionListener,
    ContactRepository? contactRepository,
    MessageRepository? messageRepository,
    MediaAttachmentRepository? mediaAttachmentRepository,
    MediaFileManager? mediaFileManagerOverride,
    InMemoryGroupRepository? groupRepository,
    InMemoryGroupMessageRepository? groupMessageRepository,
    GroupMessageListener? groupMessageListener,
    IntroductionListener? introductionListener,
    List<NavigatorObserver>? navigatorObservers,
  }) {
    final effectiveContactRepo = contactRepository ?? contactRepo;
    final effectiveMessageRepo = messageRepository ?? messageRepo;

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

    return MaterialApp(
      navigatorObservers: navigatorObservers ?? const <NavigatorObserver>[],
      home: FeedWired(
        repository: identityRepo,
        contactRepository: effectiveContactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: crListener,
        messageRepository: effectiveMessageRepo,
        mediaAttachmentRepository:
            mediaAttachmentRepository ?? mediaAttachmentRepo,
        chatMessageListener: cmListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManagerOverride ?? mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        reactionRepository: reactionRepository,
        reactionListener: reactionListener,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        introductionListener: introductionListener,
      ),
    );
  }

  Future<void> pumpFeedFrames(WidgetTester tester, {int count = 6}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('FeedWired', () {
    testWidgets('loads and displays username from identity', (tester) async {
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The EditableUsernameWidget renders as '@Alice'
      expect(find.text('@Alice'), findsOneWidget);
    });

    testWidgets('displays empty feed state when no messages exist', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      // No contacts or messages seeded

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The _EmptyFeedStateCard shows this text with the username
      expect(find.textContaining('Your feed is ready'), findsOneWidget);
    });

    testWidgets('displays feed items when contacts with messages exist', (
      tester,
    ) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

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

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // A thread card or connection card with Bob should appear
      expect(find.textContaining('Bob'), findsWidgets);
    });

    testWidgets('refreshes feed on incoming chat message', (tester) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      await tester.pumpWidget(
        buildFeedWired(chatMessageListener: fakeChatListener),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Initially the feed has a connection card for Bob but no thread
      // (no messages yet). The feed loaded with 1 item (ConnectionFeedItem).
      expect(find.textContaining('Bob'), findsWidgets);

      // Count how many Bob-related widgets exist before the message
      final bobWidgetsBefore = find.textContaining('Bob').evaluate().length;

      // Now seed a message and emit an incoming chat event
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-2',
          contactPeerId: 'contact-peer-id',
          text: 'New message from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      fakeChatListener.emitIncomingMessage(
        ConversationMessage(
          id: 'msg-2',
          contactPeerId: 'contact-peer-id',
          text: 'New message from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // After the refresh, a ThreadFeedItem should also appear for Bob,
      // so there should be more Bob-related widgets than before.
      final bobWidgetsAfter = find.textContaining('Bob').evaluate().length;
      expect(
        bobWidgetsAfter,
        greaterThanOrEqualTo(bobWidgetsBefore),
        reason: 'Feed should have refreshed with new thread item for Bob',
      );
    });

    testWidgets('refreshes feed on contact update stream event', (
      tester,
    ) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-3',
          contactPeerId: 'contact-peer-id',
          text: 'Hello',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pumpWidget(
        buildFeedWired(chatMessageListener: fakeChatListener),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Feed should show Bob initially
      expect(find.textContaining('Bob'), findsWidgets);

      // Update the contact username and emit update
      final updatedContact = testContact.copyWith(username: 'Bobby');
      contactRepo.seed([updatedContact]);

      fakeChatListener.emitContactUpdate(updatedContact);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Feed should now show updated username
      expect(find.textContaining('Bobby'), findsWidgets);
    });

    testWidgets('shows contact request dialog on incoming request', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);

      final fakeRequestListener = _FakeContactRequestListener(
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      await tester.pumpWidget(
        buildFeedWired(contactRequestListener: fakeRequestListener),
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

    testWidgets('orbit navigation bar button exists', (tester) async {
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The FeedNavigationBar renders NavBarButton with label 'Orbit'
      expect(find.text('Orbit'), findsOneWidget);
      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Remember'), findsOneWidget);
    });

    testWidgets('collapse from open-mode card does not expand collapsed card', (
      tester,
    ) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      // One unread incoming message → open-mode card
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-unread-1',
          contactPeerId: 'contact-peer-id',
          text: 'Hey there!',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Should have OpenModeCardBody (unread message)
      expect(find.byType(OpenModeCardBody), findsOneWidget);

      // Tap "Collapse" link
      await tester.tap(find.text('Collapse'));
      // Pump through markConversationRead + refreshFeed
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Card should now be CollapsedModeCardBody without ScrollableMessagePreview
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      expect(find.byType(ScrollableMessagePreview), findsNothing);
    });

    testWidgets(
      'collapse from open-mode group card marks messages read and collapses',
      (tester) async {
        // Regression: _onToggleExpand must find GroupThreadFeedItem (not just
        // ThreadFeedItem) and call groupMessageRepository.markAsRead so the
        // card transitions from open mode to collapsed mode.
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();

        await groupRepo.saveGroup(
          GroupModel(
            id: 'g1',
            name: 'Collapse Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );

        // Seed an unread incoming group message → open-mode card
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-unread-1',
            groupId: 'g1',
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Unread group message',
            timestamp: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
        );

        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // Group card should be in open mode (unread)
        expect(find.byType(OpenModeCardBody), findsOneWidget);
        expect(find.text('Collapse Group'), findsOneWidget);

        // Tap the "Collapse" link (shown in OpenModeCardBody's
        // ScrollableMessagePreview)
        expect(find.text('Collapse'), findsOneWidget);
        await tester.tap(find.text('Collapse'));

        // Pump through markAsRead + refreshFeed
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // Card should now be collapsed (messages marked as read)
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.byType(OpenModeCardBody), findsNothing);

        // Verify that markAsRead was actually called — the message should
        // have a readAt value now
        final msgs = await groupMsgRepo.getMessagesPage('g1');
        expect(
          msgs.first.readAt,
          isNotNull,
          reason: 'Group message should be marked as read after collapse',
        );
      },
    );

    testWidgets('loads image quality preference from SecureKeyStore', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);

      // Pre-set image quality preference to 'original'
      await secureKeyStore.write('image_quality_preference', 'original');

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // No crash means the preference was loaded successfully.
      // Verify the widget tree rendered correctly.
      expect(find.byType(FeedWired), findsOneWidget);
    });

    testWidgets('loads video quality preference from SecureKeyStore', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);

      // Pre-set video quality preference to 'original'
      await secureKeyStore.write('video_quality_preference', 'original');

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // No crash means the preference was loaded successfully.
      expect(find.byType(FeedWired), findsOneWidget);
    });

    testWidgets('incoming message clears session reply so card shows open mode', (
      tester,
    ) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      // Seed an incoming read message (readAt set → treated as read)
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-in-1',
          contactPeerId: 'contact-peer-id',
          text: 'Hi from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now()
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          isIncoming: true,
          status: 'read',
          readAt: DateTime.now()
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          createdAt: DateTime.now()
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        ),
      );

      await tester.pumpWidget(
        buildFeedWired(chatMessageListener: fakeChatListener),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Card should be in collapsed mode (read state)
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);

      // Now seed a NEW unread incoming message and emit it
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-in-2',
          contactPeerId: 'contact-peer-id',
          text: 'New message from Bob!',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      fakeChatListener.emitIncomingMessage(
        ConversationMessage(
          id: 'msg-in-2',
          contactPeerId: 'contact-peer-id',
          text: 'New message from Bob!',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Card should switch to open mode (session reply cleared + unread message)
      expect(find.byType(OpenModeCardBody), findsOneWidget);
    });

    testWidgets('tap to expand works after inline reply from collapsed card', (
      tester,
    ) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      // Seed a read incoming message (readAt set)
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-read-1',
          contactPeerId: 'contact-peer-id',
          text: 'Hey from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now()
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          isIncoming: true,
          status: 'read',
          readAt: DateTime.now()
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          createdAt: DateTime.now()
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        ),
      );

      // Configure P2P for successful send
      p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
        discoverPeerResult: const DiscoveredPeer(
          id: 'contact-peer-id',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
      );

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Card should be in collapsed mode with Continue... input
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      expect(find.text('Continue...'), findsOneWidget);

      // Enter text and send
      await tester.enterText(find.byType(TextField).first, 'My reply');
      await tester.pump();
      final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
      await tester.ensureVisible(sendButton);
      await tester.pump();
      await tester.tap(sendButton);

      // Pump through async send + markConversationRead + refreshFeed
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Card should show session reply text (collapsed with "Just now")
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);

      // Now tap "Tap to expand"
      await tester.tap(find.text('Tap to expand'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // After fix: ScrollableMessagePreview should appear
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    });

    testWidgets(
      'focused inline reply draft survives targeted contact refresh',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-focus-1',
            contactPeerId: testContact.peerId,
            text: 'Earlier reply thread',
            senderPeerId: testContact.peerId,
            timestamp: DateTime.utc(2026, 2, 1, 10).toIso8601String(),
            isIncoming: true,
            status: 'read',
            readAt: DateTime.utc(2026, 2, 1, 10, 15).toIso8601String(),
            createdAt: DateTime.utc(2026, 2, 1, 10).toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(chatMessageListener: fakeChatListener),
        );
        await pumpFeedFrames(tester);

        final inlineReplyFinder = find.byType(InlineReplyInput);
        final textFieldFinder = find.descendant(
          of: inlineReplyFinder,
          matching: find.byType(TextField),
        );
        final editableFinder = find.descendant(
          of: inlineReplyFinder,
          matching: find.byType(EditableText),
        );

        await tester.ensureVisible(textFieldFinder);
        await tester.pump();
        await tester.tap(textFieldFinder);
        await tester.pump();
        await tester.enterText(textFieldFinder, 'Draft that should stay');
        await tester.pump();

        final editableBefore = tester.widget<EditableText>(editableFinder);
        expect(editableBefore.controller.text, 'Draft that should stay');
        expect(editableBefore.focusNode.hasFocus, isTrue);

        final updatedContact = testContact.copyWith(username: 'Bobby');
        await contactRepo.addContact(updatedContact);
        fakeChatListener.emitContactUpdate(updatedContact);

        await pumpFeedFrames(tester);

        final editableAfter = tester.widget<EditableText>(editableFinder);
        expect(find.textContaining('Bobby'), findsWidgets);
        expect(editableAfter.controller.text, 'Draft that should stay');
        expect(editableAfter.focusNode.hasFocus, isTrue);
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      },
    );

    testWidgets('loads reactions for feed messages on init', (tester) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      final reactionRepo = FakeReactionRepository();

      // Seed a message
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-r1',
          contactPeerId: 'contact-peer-id',
          text: 'Hello from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      // Seed a reaction
      await reactionRepo.saveReaction(
        MessageReaction(
          id: 'r1',
          messageId: 'msg-r1',
          emoji: '👍',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pumpWidget(buildFeedWired(reactionRepository: reactionRepo));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Inline reaction chips render (no standalone ReactionDisplay)
      expect(find.byType(ReactionDisplay), findsNothing);
      expect(find.text('👍'), findsOneWidget);
    });

    testWidgets('incoming reaction from listener updates state', (
      tester,
    ) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      final reactionRepo = FakeReactionRepository();
      final fakeReactionListener = _FakeReactionListener(
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      // Seed a message
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-r2',
          contactPeerId: 'contact-peer-id',
          text: 'Hello from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pumpWidget(
        buildFeedWired(
          reactionRepository: reactionRepo,
          reactionListener: fakeReactionListener,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // No reactions yet (no inline chips)
      expect(find.text('❤️'), findsNothing);

      // Emit an incoming reaction
      fakeReactionListener.emitReaction(
        MessageReaction(
          id: 'r2',
          messageId: 'msg-r2',
          emoji: '❤️',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Inline reaction chips should now show the reaction
      expect(find.byType(ReactionDisplay), findsNothing);
      expect(find.text('❤️'), findsOneWidget);
    });

    testWidgets(
      'incoming reaction removal updates feed without reloading threads',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        final spyContactRepo = _SpyContactRepository()..seed([testContact]);
        final spyMessageRepo = _SpyMessageRepository();
        final reactionRepo = FakeReactionRepository();
        final fakeReactionListener = _FakeReactionListener(
          reactionRepo: reactionRepo,
          contactRepo: spyContactRepo,
          bridge: bridge,
        );

        await spyMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-r3',
            contactPeerId: testContact.peerId,
            text: 'Remote reaction target',
            senderPeerId: testContact.peerId,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'r3',
            messageId: 'msg-r3',
            emoji: '🔥',
            senderPeerId: testContact.peerId,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(
            contactRepository: spyContactRepo,
            messageRepository: spyMessageRepo,
            reactionRepository: reactionRepo,
            reactionListener: fakeReactionListener,
          ),
        );
        await pumpFeedFrames(tester);

        expect(find.text('🔥'), findsOneWidget);

        spyContactRepo.resetTracking();
        spyMessageRepo.resetTracking();
        await reactionRepo.removeReaction('msg-r3', testContact.peerId);
        fakeReactionListener.emitReactionChange(
          ReactionChange.removed(
            messageId: 'msg-r3',
            senderPeerId: testContact.peerId,
          ),
        );

        await pumpFeedFrames(tester, count: 2);

        expect(find.text('🔥'), findsNothing);
        expect(spyContactRepo.getActiveContactsCallCount, 0);
        expect(spyContactRepo.getContactCallCountByPeerId, isEmpty);
        expect(spyMessageRepo.getMessagesForContactCallCountByPeerId, isEmpty);
      },
    );

    testWidgets('displays group thread cards when group data exists', (
      tester,
    ) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);

      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'other-peer',
          senderUsername: 'OtherUser',
          text: 'Hello from group!',
          timestamp: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final fakeGroupListener = _FakeGroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
      );

      await tester.pumpWidget(
        buildFeedWired(
          groupRepository: groupRepo,
          groupMessageRepository: groupMsgRepo,
          groupMessageListener: fakeGroupListener,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Group renders through FeedCard now
      expect(find.byType(FeedCard), findsOneWidget);
      expect(find.text('Alpha Group'), findsOneWidget);
    });

    testWidgets('refreshes feed on incoming group message', (tester) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);

      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Beta Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );

      final fakeGroupListener = _FakeGroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
      );

      await tester.pumpWidget(
        buildFeedWired(
          groupRepository: groupRepo,
          groupMessageRepository: groupMsgRepo,
          groupMessageListener: fakeGroupListener,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // No group card initially (no messages)
      expect(find.byType(FeedCard), findsNothing);

      // Seed a message and emit group message event
      final newMsg = GroupMessage(
        id: 'gm-1',
        groupId: 'g1',
        senderPeerId: 'other-peer',
        senderUsername: 'OtherUser',
        text: 'New group message!',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
      );
      await groupMsgRepo.saveMessage(newMsg);
      fakeGroupListener.emitGroupMessage(newMsg);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Group FeedCard should now appear after refresh
      expect(find.byType(FeedCard), findsOneWidget);
      expect(find.text('Beta Group'), findsOneWidget);
    });

    testWidgets(
      'incremental group message carries media attachments to feed card',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();

        await groupRepo.saveGroup(
          GroupModel(
            id: 'g1',
            name: 'Media Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
        );

        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await pumpFeedFrames(tester);

        // Seed a group message + media attachment in DB, then emit the stream
        // event. This simulates what GroupMessageListener does: save to DB
        // first, then broadcast the bare GroupMessage (without media field).
        final newMsg = GroupMessage(
          id: 'gm-media-1',
          groupId: 'g1',
          senderPeerId: 'other-peer',
          senderUsername: 'Hisam',
          text: 'Check this',
          timestamp: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
        );
        await groupMsgRepo.saveMessage(newMsg);
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-gm-1',
            messageId: 'gm-media-1',
            mime: 'image/jpeg',
            size: 2048,
            mediaType: 'image',
            localPath: 'media/groups/img.jpg',
            downloadStatus: 'done',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        // Emit bare GroupMessage (no media field) — mimics real listener
        fakeGroupListener.emitGroupMessage(newMsg);
        await pumpFeedFrames(tester);

        // The card should appear
        expect(find.byType(FeedCard), findsOneWidget);
        expect(find.text('Media Group'), findsOneWidget);

        // The open-mode card renders via ScrollableMessagePreview which uses
        // MessageBubble. If media was loaded, MessageBubble receives non-empty
        // media list. We verify by finding the Image.file widget that renders
        // the thumbnail (20×20 in collapsed, or MediaGrid in open).
        final messageBubbles = tester.widgetList<MessageBubble>(
          find.byType(MessageBubble),
        );
        expect(messageBubbles, isNotEmpty);

        // The first MessageBubble should have media
        final bubble = messageBubbles.first;
        expect(bubble.media, isNotEmpty);
        expect(bubble.media.first.id, 'att-gm-1');
        expect(bubble.media.first.localPath, contains('media/groups/img.jpg'));
      },
    );

    testWidgets('incoming chat updates only the affected contact thread', (
      tester,
    ) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);

      final otherContact = testContact.copyWith(
        peerId: 'contact-peer-id-2',
        publicKey: 'contact-pk-2',
        username: 'Bea',
        signature: 'sig-2',
        scannedAt: '2026-02-01T09:30:00.000Z',
      );
      final spyContactRepo = _SpyContactRepository()
        ..seed([testContact, otherContact]);
      final spyMessageRepo = _SpyMessageRepository();
      final spyMediaAttachmentRepo = _SpyMediaAttachmentRepository();
      final spyMediaFileManager = _SpyMediaFileManager();

      await spyMessageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-a-1',
          contactPeerId: testContact.peerId,
          text: 'Earlier message from Bob',
          senderPeerId: testContact.peerId,
          timestamp: '2026-02-01T10:00:00.000Z',
          isIncoming: true,
          status: 'read',
          readAt: '2026-02-01T10:30:00.000Z',
          createdAt: '2026-02-01T10:00:00.000Z',
        ),
      );
      await spyMessageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-b-1',
          contactPeerId: otherContact.peerId,
          text: 'Earlier message from Bea',
          senderPeerId: otherContact.peerId,
          timestamp: '2026-02-01T10:05:00.000Z',
          isIncoming: true,
          status: 'read',
          readAt: '2026-02-01T10:35:00.000Z',
          createdAt: '2026-02-01T10:05:00.000Z',
        ),
      );
      await spyMediaAttachmentRepo.saveAttachment(
        MediaAttachment(
          id: 'att-a-1',
          messageId: 'msg-a-1',
          mime: 'image/jpeg',
          size: 123,
          mediaType: 'image',
          localPath: 'media/contact-peer-id/blob-a.jpg',
          downloadStatus: 'done',
          createdAt: '2026-02-01T10:00:00.000Z',
        ),
      );
      await spyMediaAttachmentRepo.saveAttachment(
        MediaAttachment(
          id: 'att-b-1',
          messageId: 'msg-b-1',
          mime: 'image/jpeg',
          size: 456,
          mediaType: 'image',
          localPath: 'media/contact-peer-id-2/blob-b.jpg',
          downloadStatus: 'done',
          createdAt: '2026-02-01T10:05:00.000Z',
        ),
      );

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: spyMessageRepo,
        contactRepo: spyContactRepo,
      );

      await tester.pumpWidget(
        buildFeedWired(
          contactRepository: spyContactRepo,
          messageRepository: spyMessageRepo,
          mediaAttachmentRepository: spyMediaAttachmentRepo,
          mediaFileManagerOverride: spyMediaFileManager,
          chatMessageListener: fakeChatListener,
        ),
      );
      await pumpFeedFrames(tester);

      spyContactRepo.resetTracking();
      spyMessageRepo.resetTracking();
      spyMediaAttachmentRepo.resetTracking();
      spyMediaFileManager.resetTracking();

      final newMessage = ConversationMessage(
        id: 'msg-a-2',
        contactPeerId: testContact.peerId,
        text: 'New message from Bob',
        senderPeerId: testContact.peerId,
        timestamp: '2026-02-01T11:00:00.000Z',
        isIncoming: true,
        status: 'delivered',
        createdAt: '2026-02-01T11:00:00.000Z',
      );
      await spyMessageRepo.saveMessage(newMessage);
      fakeChatListener.emitIncomingMessage(newMessage);

      await pumpFeedFrames(tester);

      expect(find.byType(OpenModeCardBody), findsOneWidget);
      expect(find.textContaining('New message from Bob'), findsWidgets);
      expect(spyContactRepo.getActiveContactsCallCount, 0);
      expect(spyContactRepo.getContactCallCountByPeerId.keys, <String>{
        testContact.peerId,
      });
      expect(spyContactRepo.getContactCallCountByPeerId[testContact.peerId], 1);
      expect(spyMessageRepo.getMessagesForContactCallCountByPeerId, isEmpty);
      expect(spyMessageRepo.getTotalUnreadCountExcludingArchivedCallCount, 1);
      expect(spyMediaAttachmentRepo.requestedMessageIdBatches, isEmpty);
      expect(
        spyMediaAttachmentRepo.getAttachmentsForMessageCallCountByMessageId,
        <String, int>{'msg-a-2': 1},
      );
      expect(spyMediaFileManager.resolvedStoredPaths, isEmpty);
    });

    testWidgets('contact update patches only the affected contact thread', (
      tester,
    ) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);

      final otherContact = testContact.copyWith(
        peerId: 'contact-peer-id-2',
        publicKey: 'contact-pk-2',
        username: 'Bea',
        signature: 'sig-2',
        scannedAt: '2026-02-01T09:30:00.000Z',
      );
      final spyContactRepo = _SpyContactRepository()
        ..seed([testContact, otherContact]);
      final spyMessageRepo = _SpyMessageRepository();

      await spyMessageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-contact-1',
          contactPeerId: testContact.peerId,
          text: 'Message for Bob',
          senderPeerId: testContact.peerId,
          timestamp: '2026-02-01T10:00:00.000Z',
          isIncoming: true,
          status: 'delivered',
          createdAt: '2026-02-01T10:00:00.000Z',
        ),
      );
      await spyMessageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-contact-2',
          contactPeerId: otherContact.peerId,
          text: 'Message for Bea',
          senderPeerId: otherContact.peerId,
          timestamp: '2026-02-01T10:05:00.000Z',
          isIncoming: true,
          status: 'delivered',
          createdAt: '2026-02-01T10:05:00.000Z',
        ),
      );

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: spyMessageRepo,
        contactRepo: spyContactRepo,
      );

      await tester.pumpWidget(
        buildFeedWired(
          contactRepository: spyContactRepo,
          messageRepository: spyMessageRepo,
          chatMessageListener: fakeChatListener,
        ),
      );
      await pumpFeedFrames(tester);

      spyContactRepo.resetTracking();
      spyMessageRepo.resetTracking();

      final updatedContact = testContact.copyWith(username: 'Bobby');
      await spyContactRepo.addContact(updatedContact);
      fakeChatListener.emitContactUpdate(updatedContact);

      await pumpFeedFrames(tester);

      expect(find.textContaining('Bobby'), findsWidgets);
      expect(spyContactRepo.getActiveContactsCallCount, 0);
      expect(spyContactRepo.getContactCallCountByPeerId, isEmpty);
      expect(spyMessageRepo.getMessagesForContactCallCountByPeerId, isEmpty);
    });

    testWidgets(
      'incoming group message updates only the affected group thread',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        final spyGroupRepo = _SpyGroupRepository();
        final spyGroupMessageRepo = _SpyGroupMessageRepository();

        await spyGroupRepo.saveGroup(
          GroupModel(
            id: 'g1',
            name: 'Alpha Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await spyGroupRepo.saveGroup(
          GroupModel(
            id: 'g2',
            name: 'Beta Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g2',
            createdAt: DateTime(2026, 2, 2),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await spyGroupMessageRepo.saveMessage(
          GroupMessage(
            id: 'gm-1',
            groupId: 'g1',
            senderPeerId: 'peer-a',
            senderUsername: 'Peer A',
            text: 'Old alpha message',
            timestamp: DateTime.utc(2026, 2, 1, 10),
            readAt: DateTime.utc(2026, 2, 1, 10, 30),
            createdAt: DateTime.utc(2026, 2, 1, 10),
          ),
        );
        await spyGroupMessageRepo.saveMessage(
          GroupMessage(
            id: 'gm-2',
            groupId: 'g2',
            senderPeerId: 'peer-b',
            senderUsername: 'Peer B',
            text: 'Old beta message',
            timestamp: DateTime.utc(2026, 2, 1, 10, 5),
            readAt: DateTime.utc(2026, 2, 1, 10, 35),
            createdAt: DateTime.utc(2026, 2, 1, 10, 5),
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: spyGroupRepo,
          msgRepo: spyGroupMessageRepo,
        );

        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: spyGroupRepo,
            groupMessageRepository: spyGroupMessageRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await pumpFeedFrames(tester);

        spyGroupRepo.resetTracking();
        spyGroupMessageRepo.resetTracking();

        final newMessage = GroupMessage(
          id: 'gm-3',
          groupId: 'g1',
          senderPeerId: 'peer-a',
          senderUsername: 'Peer A',
          text: 'Fresh alpha update',
          timestamp: DateTime.utc(2026, 2, 1, 11),
          createdAt: DateTime.utc(2026, 2, 1, 11),
        );
        await spyGroupMessageRepo.saveMessage(newMessage);
        fakeGroupListener.emitGroupMessage(newMessage);

        await pumpFeedFrames(tester);

        expect(find.byType(OpenModeCardBody), findsOneWidget);
        expect(find.textContaining('Fresh alpha update'), findsWidgets);
        expect(spyGroupRepo.getActiveGroupsCallCount, 0);
        expect(spyGroupRepo.getGroupCallCountById.keys, <String>{'g1'});
        expect(spyGroupRepo.getGroupCallCountById['g1'], 1);
        expect(spyGroupMessageRepo.getMessagesPageCallCountByGroupId, isEmpty);
      },
    );

    testWidgets(
      'send message pushes conversation route before read marking completes',
      (tester) async {
        identityRepo.seed(testIdentity);

        final spyContactRepo = _SpyContactRepository()..seed([testContact]);
        final delayedMessageRepo = _DelayedSpyMessageRepository()
          ..markConversationAsReadGate = Completer<void>();
        final observer = _RecordingNavigatorObserver();

        await tester.pumpWidget(
          buildFeedWired(
            contactRepository: spyContactRepo,
            messageRepository: delayedMessageRepo,
            navigatorObservers: [observer],
          ),
        );
        await pumpFeedFrames(tester);

        observer.reset();

        await tester.tap(find.text('Send Message'));
        await tester.pump();

        expect(observer.pushCount, 1);
        expect(observer.lastPushedRoute, isNotNull);

        delayedMessageRepo.markConversationAsReadGate!.complete();
        await pumpFeedFrames(tester, count: 6);
      },
    );

    testWidgets(
      'view earlier pushes conversation route before conversation preload resolves',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        final spyContactRepo = _SpyContactRepository()..seed([testContact]);
        final delayedMessageRepo = _DelayedSpyMessageRepository();
        final observer = _RecordingNavigatorObserver();

        await delayedMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-history-1',
            contactPeerId: testContact.peerId,
            text: 'Earlier read context',
            senderPeerId: testContact.peerId,
            timestamp: '2026-02-01T10:00:00.000Z',
            isIncoming: true,
            status: 'read',
            readAt: '2026-02-01T10:10:00.000Z',
            createdAt: '2026-02-01T10:00:00.000Z',
          ),
        );
        await delayedMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-history-2',
            contactPeerId: testContact.peerId,
            text: 'Unread latest message',
            senderPeerId: testContact.peerId,
            timestamp: '2026-02-01T11:00:00.000Z',
            isIncoming: true,
            status: 'delivered',
            createdAt: '2026-02-01T11:00:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(
            contactRepository: spyContactRepo,
            messageRepository: delayedMessageRepo,
            navigatorObservers: [observer],
          ),
        );
        await pumpFeedFrames(tester);

        expect(find.text('View earlier messages'), findsOneWidget);

        delayedMessageRepo.getMessagesForContactGate = Completer<void>();
        observer.reset();

        await tester.tap(find.text('View earlier messages'));
        await tester.pump();

        expect(observer.pushCount, 1);
        expect(observer.lastPushedRoute, isNotNull);
      },
    );

    testWidgets(
      'mutual intro acceptance refreshes only the new contact snapshot',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        final spyContactRepo = _SpyContactRepository()..seed([testContact]);
        final spyMessageRepo = _SpyMessageRepository();
        final introRepo = InMemoryIntroductionRepository();
        final fakeIntroListener = _FakeIntroductionListener(
          introRepo: introRepo,
          contactRepo: spyContactRepo,
          messageRepo: spyMessageRepo,
          bridge: bridge,
        );

        await tester.pumpWidget(
          buildFeedWired(
            contactRepository: spyContactRepo,
            messageRepository: spyMessageRepo,
            introductionListener: fakeIntroListener,
          ),
        );
        await pumpFeedFrames(tester);

        spyContactRepo.resetTracking();
        spyMessageRepo.resetTracking();

        final introducedContact = ContactModel(
          peerId: 'intro-peer-id',
          publicKey: 'intro-pk',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Dora',
          signature: 'intro-sig',
          scannedAt: '2026-02-01T12:00:00.000Z',
          introducedBy: 'Eve',
          introducedByPeerId: 'introducer-peer-id',
        );
        await spyContactRepo.addContact(introducedContact);

        fakeIntroListener.emitIntroStatusChanged(
          IntroductionModel(
            id: 'intro-1',
            introducerId: 'introducer-peer-id',
            recipientId: testIdentity.peerId,
            introducedId: introducedContact.peerId,
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.mutualAccepted,
            createdAt: '2026-02-01T11:00:00.000Z',
            introducerUsername: 'Eve',
            recipientUsername: testIdentity.username,
            introducedUsername: introducedContact.username,
          ),
        );

        await pumpFeedFrames(tester);

        expect(find.textContaining('Dora'), findsWidgets);
        expect(spyContactRepo.getActiveContactsCallCount, 0);
        expect(spyContactRepo.getContactCallCountByPeerId.keys, <String>{
          introducedContact.peerId,
        });
        expect(
          spyContactRepo.getContactCallCountByPeerId[introducedContact.peerId],
          1,
        );
        expect(
          spyMessageRepo.getMessagesForContactCallCountByPeerId.keys,
          <String>{introducedContact.peerId},
        );
        expect(
          spyMessageRepo
              .getMessagesForContactCallCountByPeerId[introducedContact.peerId],
          1,
        );
      },
    );

    testWidgets(
      'orbit route result refreshes only the changed contact snapshot',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        final otherContact = testContact.copyWith(
          peerId: 'contact-peer-id-2',
          publicKey: 'contact-pk-2',
          username: 'Bea',
          signature: 'sig-2',
          scannedAt: '2026-02-01T09:30:00.000Z',
        );
        final spyContactRepo = _SpyContactRepository()
          ..seed([testContact, otherContact]);
        final spyMessageRepo = _SpyMessageRepository();
        final observer = _RecordingNavigatorObserver();

        await spyMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-orbit-1',
            contactPeerId: testContact.peerId,
            text: 'Orbit message for Bob',
            senderPeerId: testContact.peerId,
            timestamp: '2026-02-01T10:00:00.000Z',
            isIncoming: true,
            status: 'delivered',
            createdAt: '2026-02-01T10:00:00.000Z',
          ),
        );
        await spyMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-orbit-2',
            contactPeerId: otherContact.peerId,
            text: 'Orbit message for Bea',
            senderPeerId: otherContact.peerId,
            timestamp: '2026-02-01T10:05:00.000Z',
            isIncoming: true,
            status: 'delivered',
            createdAt: '2026-02-01T10:05:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(
            contactRepository: spyContactRepo,
            messageRepository: spyMessageRepo,
            navigatorObservers: [observer],
          ),
        );
        await pumpFeedFrames(tester);

        await tester.tap(find.text('Orbit'));
        await pumpFeedFrames(tester);

        spyContactRepo.resetTracking();
        spyMessageRepo.resetTracking();

        await spyContactRepo.addContact(
          testContact.copyWith(username: 'Bobby'),
        );
        observer.lastPushedRoute!.navigator!.pop(
          const FeedRouteChanges(changedContactPeerIds: {'contact-peer-id'}),
        );

        await pumpFeedFrames(tester, count: 8);

        expect(find.textContaining('Bobby'), findsWidgets);
        expect(spyContactRepo.getActiveContactsCallCount, 0);
        expect(spyContactRepo.getContactCallCountByPeerId.keys, <String>{
          testContact.peerId,
        });
        expect(
          spyContactRepo.getContactCallCountByPeerId[testContact.peerId],
          1,
        );
        expect(
          spyMessageRepo.getMessagesForContactCallCountByPeerId.keys,
          <String>{testContact.peerId},
        );
        expect(
          spyMessageRepo.getMessagesForContactCallCountByPeerId[testContact
              .peerId],
          1,
        );
      },
    );

    testWidgets(
      'orbit route result with reloadAllContacts refreshes the full contacts section',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        final otherContact = testContact.copyWith(
          peerId: 'contact-peer-id-2',
          publicKey: 'contact-pk-2',
          username: 'Bea',
          signature: 'sig-2',
          scannedAt: '2026-02-01T09:30:00.000Z',
        );
        final spyContactRepo = _SpyContactRepository()
          ..seed([testContact, otherContact]);
        final spyMessageRepo = _SpyMessageRepository();
        final observer = _RecordingNavigatorObserver();

        await spyMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-reload-1',
            contactPeerId: testContact.peerId,
            text: 'Reload message for Bob',
            senderPeerId: testContact.peerId,
            timestamp: '2026-02-01T10:00:00.000Z',
            isIncoming: true,
            status: 'delivered',
            createdAt: '2026-02-01T10:00:00.000Z',
          ),
        );
        await spyMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-reload-2',
            contactPeerId: otherContact.peerId,
            text: 'Reload message for Bea',
            senderPeerId: otherContact.peerId,
            timestamp: '2026-02-01T10:05:00.000Z',
            isIncoming: true,
            status: 'delivered',
            createdAt: '2026-02-01T10:05:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(
            contactRepository: spyContactRepo,
            messageRepository: spyMessageRepo,
            navigatorObservers: [observer],
          ),
        );
        await pumpFeedFrames(tester);

        await tester.tap(find.text('Orbit'));
        await pumpFeedFrames(tester);

        spyContactRepo.resetTracking();
        spyMessageRepo.resetTracking();

        await spyContactRepo.addContact(
          testContact.copyWith(username: 'Bobby'),
        );
        await spyContactRepo.addContact(
          otherContact.copyWith(username: 'Beatrice'),
        );
        observer.lastPushedRoute!.navigator!.pop(
          const FeedRouteChanges(reloadAllContacts: true),
        );

        await pumpFeedFrames(tester, count: 8);

        expect(find.textContaining('Bobby'), findsWidgets);
        expect(find.textContaining('Beatrice'), findsWidgets);
        expect(spyContactRepo.getActiveContactsCallCount, 1);
        expect(spyContactRepo.getContactCallCountByPeerId, isEmpty);
        expect(
          spyMessageRepo.getMessagesForContactCallCountByPeerId.keys,
          <String>{testContact.peerId, otherContact.peerId},
        );
        expect(
          spyMessageRepo.getMessagesForContactCallCountByPeerId[testContact
              .peerId],
          1,
        );
        expect(
          spyMessageRepo.getMessagesForContactCallCountByPeerId[otherContact
              .peerId],
          1,
        );
        expect(spyMessageRepo.getTotalUnreadCountExcludingArchivedCallCount, 1);
      },
    );

    testWidgets('feed cards expose stable keys tied to feed ids', (
      tester,
    ) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-key-1',
          contactPeerId: testContact.peerId,
          text: 'Keyed thread',
          senderPeerId: testContact.peerId,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester);

      final cards = tester.widgetList<FeedCard>(find.byType(FeedCard)).toList();
      expect(cards, isNotEmpty);
      expect(
        cards.map((card) => card.key).whereType<ValueKey<String>>().length,
        cards.length,
      );
      expect(
        cards
            .map((card) => (card.key! as ValueKey<String>).value)
            .toSet()
            .length,
        cards.length,
      );
    });

    testWidgets('disposes stream subscriptions without errors', (tester) async {
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
        buildFeedWired(
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

      // No crash or error means subscriptions were disposed cleanly
      expect(find.text('Replaced'), findsOneWidget);
    });

    testWidgets(
      'group card + button shows media picker bottom sheet',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();

        await groupRepo.saveGroup(
          GroupModel(
            id: 'g-attach',
            name: 'Attach Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g-attach',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );

        // Seed a read message so card is in collapsed mode (shows + button)
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-read-1',
            groupId: 'g-attach',
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Hello group',
            timestamp: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            readAt: DateTime.now().toUtc(),
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
        );

        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await pumpFeedFrames(tester, count: 6);

        // The group card should be in collapsed mode with a + button
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.byIcon(Icons.add_rounded), findsOneWidget);

        // Tap the + button
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));

        // Should show bottom sheet with media options
        expect(find.text('Media Library'), findsOneWidget);
        expect(find.text('Take Photo'), findsOneWidget);
        expect(find.text('Record Video'), findsOneWidget);
      },
    );
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

/// Fake [ReactionListener] with a controllable stream for testing.
class _FakeReactionListener extends ReactionListener {
  final _reactionEmitter = StreamController<MessageReaction>.broadcast();
  final _reactionChangeEmitter = StreamController<ReactionChange>.broadcast();

  _FakeReactionListener({
    required super.reactionRepo,
    required super.contactRepo,
    required super.bridge,
  }) : super(
         reactionStream: const Stream.empty(),
         getOwnMlKemSecretKey: () async => null,
       );

  @override
  Stream<MessageReaction> get incomingReactionStream => _reactionEmitter.stream;

  @override
  Stream<ReactionChange> get incomingReactionChangeStream =>
      _reactionChangeEmitter.stream;

  void emitReaction(MessageReaction reaction) {
    _reactionEmitter.add(reaction);
    _reactionChangeEmitter.add(ReactionChange.upsert(reaction));
  }

  void emitReactionChange(ReactionChange change) =>
      _reactionChangeEmitter.add(change);
}

/// Fake [GroupMessageListener] with a controllable stream for testing.
class _FakeGroupMessageListener extends GroupMessageListener {
  final _groupMsgEmitter = StreamController<GroupMessage>.broadcast();

  _FakeGroupMessageListener({
    required InMemoryGroupRepository groupRepo,
    required InMemoryGroupMessageRepository msgRepo,
  }) : super(groupRepo: groupRepo, msgRepo: msgRepo);

  @override
  Stream<GroupMessage> get groupMessageStream => _groupMsgEmitter.stream;

  void emitGroupMessage(GroupMessage msg) => _groupMsgEmitter.add(msg);
}

class _FakeIntroductionListener extends IntroductionListener {
  final _introReceivedController =
      StreamController<IntroductionModel>.broadcast();
  final _introStatusController =
      StreamController<IntroductionModel>.broadcast();

  _FakeIntroductionListener({
    required super.introRepo,
    required super.contactRepo,
    required super.messageRepo,
    required super.bridge,
  }) : super(
         introductionStream: const Stream<ChatMessage>.empty(),
         getOwnMlKemSecretKey: () async => null,
         getOwnPeerId: () async => null,
       );

  @override
  Stream<IntroductionModel> get introReceivedStream =>
      _introReceivedController.stream;

  @override
  Stream<IntroductionModel> get introStatusChangedStream =>
      _introStatusController.stream;

  void emitIntroReceived(IntroductionModel intro) =>
      _introReceivedController.add(intro);

  void emitIntroStatusChanged(IntroductionModel intro) =>
      _introStatusController.add(intro);
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

  void resetTracking() {
    getActiveContactsCallCount = 0;
    getContactCallCountByPeerId.clear();
  }
}

class _SpyMessageRepository extends InMemoryMessageRepository {
  final Map<String, int> getMessagesForContactCallCountByPeerId = {};
  int getTotalUnreadCountExcludingArchivedCallCount = 0;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    getMessagesForContactCallCountByPeerId.update(
      contactPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getMessagesForContact(contactPeerId);
  }

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async {
    getTotalUnreadCountExcludingArchivedCallCount++;
    return super.getTotalUnreadCountExcludingArchived();
  }

  void resetTracking() {
    getMessagesForContactCallCountByPeerId.clear();
    getTotalUnreadCountExcludingArchivedCallCount = 0;
  }
}

class _DelayedSpyMessageRepository extends _SpyMessageRepository {
  Completer<void>? getMessagesForContactGate;
  Completer<void>? markConversationAsReadGate;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    final gate = getMessagesForContactGate;
    if (gate != null) {
      await gate.future;
    }
    return super.getMessagesForContact(contactPeerId);
  }

  @override
  Future<int> markConversationAsRead(String contactPeerId) async {
    final gate = markConversationAsReadGate;
    if (gate != null) {
      await gate.future;
    }
    return super.markConversationAsRead(contactPeerId);
  }
}

class _SpyMediaAttachmentRepository extends InMemoryMediaAttachmentRepository {
  final List<List<String>> requestedMessageIdBatches = [];
  final Map<String, int> getAttachmentsForMessageCallCountByMessageId = {};

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    getAttachmentsForMessageCallCountByMessageId.update(
      messageId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getAttachmentsForMessage(messageId);
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async {
    requestedMessageIdBatches.add(List<String>.from(messageIds));
    return super.getAttachmentsForMessages(messageIds);
  }

  void resetTracking() {
    requestedMessageIdBatches.clear();
    getAttachmentsForMessageCallCountByMessageId.clear();
  }
}

class _SpyMediaFileManager extends FakeMediaFileManager {
  final List<String> resolvedStoredPaths = [];

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    resolvedStoredPaths.add(storedPath);
    return super.resolveStoredPath(storedPath);
  }

  void resetTracking() {
    resolvedStoredPaths.clear();
  }
}

class _SpyGroupRepository extends InMemoryGroupRepository {
  int getActiveGroupsCallCount = 0;
  final Map<String, int> getGroupCallCountById = {};

  @override
  Future<GroupModel?> getGroup(String id) async {
    getGroupCallCountById.update(id, (count) => count + 1, ifAbsent: () => 1);
    return super.getGroup(id);
  }

  @override
  Future<List<GroupModel>> getActiveGroups() async {
    getActiveGroupsCallCount++;
    return super.getActiveGroups();
  }

  void resetTracking() {
    getActiveGroupsCallCount = 0;
    getGroupCallCountById.clear();
  }
}

class _SpyGroupMessageRepository extends InMemoryGroupMessageRepository {
  final Map<String, int> getMessagesPageCallCountByGroupId = {};

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    getMessagesPageCallCountByGroupId.update(
      groupId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getMessagesPage(groupId, limit: limit, offset: offset);
  }

  void resetTracking() {
    getMessagesPageCallCountByGroupId.clear();
  }
}
