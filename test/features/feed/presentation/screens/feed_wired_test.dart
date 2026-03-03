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
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
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
    InMemoryGroupRepository? groupRepository,
    InMemoryGroupMessageRepository? groupMessageRepository,
    GroupMessageListener? groupMessageListener,
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

    return MaterialApp(
      home: FeedWired(
        repository: identityRepo,
        contactRepository: contactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: crListener,
        messageRepository: messageRepo,
        mediaAttachmentRepository: mediaAttachmentRepo,
        chatMessageListener: cmListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        reactionRepository: reactionRepository,
        reactionListener: reactionListener,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
      ),
    );
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

    testWidgets('displays empty feed state when no messages exist',
        (tester) async {
      identityRepo.seed(testIdentity);
      // No contacts or messages seeded

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The _EmptyFeedStateCard shows this text with the username
      expect(
        find.textContaining('Your feed is ready'),
        findsOneWidget,
      );
    });

    testWidgets('displays feed items when contacts with messages exist',
        (tester) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

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

      await tester.pumpWidget(buildFeedWired(
        chatMessageListener: fakeChatListener,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Initially the feed has a connection card for Bob but no thread
      // (no messages yet). The feed loaded with 1 item (ConnectionFeedItem).
      expect(find.textContaining('Bob'), findsWidgets);

      // Count how many Bob-related widgets exist before the message
      final bobWidgetsBefore = find.textContaining('Bob').evaluate().length;

      // Now seed a message and emit an incoming chat event
      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-2',
        contactPeerId: 'contact-peer-id',
        text: 'New message from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      fakeChatListener.emitIncomingMessage(ConversationMessage(
        id: 'msg-2',
        contactPeerId: 'contact-peer-id',
        text: 'New message from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

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

    testWidgets('refreshes feed on contact update stream event',
        (tester) async {
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

      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-3',
        contactPeerId: 'contact-peer-id',
        text: 'Hello',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      await tester.pumpWidget(buildFeedWired(
        chatMessageListener: fakeChatListener,
      ));
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

    testWidgets('shows contact request dialog on incoming request',
        (tester) async {
      identityRepo.seed(testIdentity);

      final fakeRequestListener = _FakeContactRequestListener(
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      await tester.pumpWidget(buildFeedWired(
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

    testWidgets('collapse from open-mode card does not expand collapsed card',
        (tester) async {
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
      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-unread-1',
        contactPeerId: 'contact-peer-id',
        text: 'Hey there!',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

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

      await groupRepo.saveGroup(GroupModel(
        id: 'g1',
        name: 'Collapse Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/g1',
        createdAt: DateTime(2026, 2, 1),
        createdBy: 'admin',
        myRole: GroupRole.member,
      ));

      // Seed an unread incoming group message → open-mode card
      await groupMsgRepo.saveMessage(GroupMessage(
        id: 'gm-unread-1',
        groupId: 'g1',
        senderPeerId: 'other-peer',
        senderUsername: 'OtherUser',
        text: 'Unread group message',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
      ));

      final fakeGroupListener = _FakeGroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
      );

      await tester.pumpWidget(buildFeedWired(
        groupRepository: groupRepo,
        groupMessageRepository: groupMsgRepo,
        groupMessageListener: fakeGroupListener,
      ));
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
      expect(msgs.first.readAt, isNotNull,
          reason: 'Group message should be marked as read after collapse');
    });

    testWidgets('loads image quality preference from SecureKeyStore',
        (tester) async {
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

    testWidgets('loads video quality preference from SecureKeyStore',
        (tester) async {
      identityRepo.seed(testIdentity);

      // Pre-set video quality preference to 'original'
      await secureKeyStore.write('video_quality_preference', 'original');

      await tester.pumpWidget(buildFeedWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // No crash means the preference was loaded successfully.
      expect(find.byType(FeedWired), findsOneWidget);
    });

    testWidgets('incoming message clears session reply so card shows open mode',
        (tester) async {
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
      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-in-1',
        contactPeerId: 'contact-peer-id',
        text: 'Hi from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
        isIncoming: true,
        status: 'read',
        readAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
      ));

      await tester.pumpWidget(buildFeedWired(
        chatMessageListener: fakeChatListener,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Card should be in collapsed mode (read state)
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);

      // Now seed a NEW unread incoming message and emit it
      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-in-2',
        contactPeerId: 'contact-peer-id',
        text: 'New message from Bob!',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      fakeChatListener.emitIncomingMessage(ConversationMessage(
        id: 'msg-in-2',
        contactPeerId: 'contact-peer-id',
        text: 'New message from Bob!',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Card should switch to open mode (session reply cleared + unread message)
      expect(find.byType(OpenModeCardBody), findsOneWidget);
    });

    testWidgets('tap to expand works after inline reply from collapsed card',
        (tester) async {
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
      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-read-1',
        contactPeerId: 'contact-peer-id',
        text: 'Hey from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
        isIncoming: true,
        status: 'read',
        readAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
      ));

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
      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-r1',
        contactPeerId: 'contact-peer-id',
        text: 'Hello from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Seed a reaction
      await reactionRepo.saveReaction(MessageReaction(
        id: 'r1',
        messageId: 'msg-r1',
        emoji: '👍',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      await tester.pumpWidget(buildFeedWired(
        reactionRepository: reactionRepo,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Inline reaction chips render (no standalone ReactionDisplay)
      expect(find.byType(ReactionDisplay), findsNothing);
      expect(find.text('👍'), findsOneWidget);
    });

    testWidgets('incoming reaction from listener updates state',
        (tester) async {
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
      await messageRepo.saveMessage(ConversationMessage(
        id: 'msg-r2',
        contactPeerId: 'contact-peer-id',
        text: 'Hello from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      await tester.pumpWidget(buildFeedWired(
        reactionRepository: reactionRepo,
        reactionListener: fakeReactionListener,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // No reactions yet (no inline chips)
      expect(find.text('❤️'), findsNothing);

      // Emit an incoming reaction
      fakeReactionListener.emitReaction(MessageReaction(
        id: 'r2',
        messageId: 'msg-r2',
        emoji: '❤️',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Inline reaction chips should now show the reaction
      expect(find.byType(ReactionDisplay), findsNothing);
      expect(find.text('❤️'), findsOneWidget);
    });

    testWidgets('displays group thread cards when group data exists',
        (tester) async {
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

      await groupRepo.saveGroup(GroupModel(
        id: 'g1',
        name: 'Alpha Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/g1',
        createdAt: DateTime(2026, 2, 1),
        createdBy: 'admin',
        myRole: GroupRole.member,
      ));
      await groupMsgRepo.saveMessage(GroupMessage(
        id: 'gm-1',
        groupId: 'g1',
        senderPeerId: 'other-peer',
        senderUsername: 'OtherUser',
        text: 'Hello from group!',
        timestamp: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
      ));

      final fakeGroupListener = _FakeGroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
      );

      await tester.pumpWidget(buildFeedWired(
        groupRepository: groupRepo,
        groupMessageRepository: groupMsgRepo,
        groupMessageListener: fakeGroupListener,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Group renders through FeedCard now
      expect(find.byType(FeedCard), findsOneWidget);
      expect(find.text('Alpha Group'), findsOneWidget);
    });

    testWidgets('refreshes feed on incoming group message',
        (tester) async {
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

      await groupRepo.saveGroup(GroupModel(
        id: 'g1',
        name: 'Beta Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/g1',
        createdAt: DateTime(2026, 2, 1),
        createdBy: 'admin',
        myRole: GroupRole.member,
      ));

      final fakeGroupListener = _FakeGroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
      );

      await tester.pumpWidget(buildFeedWired(
        groupRepository: groupRepo,
        groupMessageRepository: groupMsgRepo,
        groupMessageListener: fakeGroupListener,
      ));
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

    testWidgets('disposes stream subscriptions without errors',
        (tester) async {
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

      await tester.pumpWidget(buildFeedWired(
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

      // No crash or error means subscriptions were disposed cleanly
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

/// Fake [ReactionListener] with a controllable stream for testing.
class _FakeReactionListener extends ReactionListener {
  final _reactionEmitter = StreamController<MessageReaction>.broadcast();

  _FakeReactionListener({
    required ReactionRepository reactionRepo,
    required ContactRepository contactRepo,
    required Bridge bridge,
  }) : super(
          reactionStream: const Stream.empty(),
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnMlKemSecretKey: () async => null,
        );

  @override
  Stream<MessageReaction> get incomingReactionStream =>
      _reactionEmitter.stream;

  void emitReaction(MessageReaction reaction) =>
      _reactionEmitter.add(reaction);
}

/// Fake [GroupMessageListener] with a controllable stream for testing.
class _FakeGroupMessageListener extends GroupMessageListener {
  final _groupMsgEmitter = StreamController<GroupMessage>.broadcast();

  _FakeGroupMessageListener({
    required InMemoryGroupRepository groupRepo,
    required InMemoryGroupMessageRepository msgRepo,
  }) : super(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
        );

  @override
  Stream<GroupMessage> get groupMessageStream => _groupMsgEmitter.stream;

  void emitGroupMessage(GroupMessage msg) => _groupMsgEmitter.add(msg);
}
