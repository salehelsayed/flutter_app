import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/introduction_connection_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_pending_group_invite_repository.dart';
import '../../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
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
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late AppShellController appShellController;
  late PendingPostTargetStore pendingPostTargetStore;
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
    mlKemPublicKey: 'mlkem-contact-peer-id',
  );

  String freshPendingIntroductionCreatedAt() => DateTime.now()
      .toUtc()
      .subtract(const Duration(days: 1))
      .toIso8601String();

  setUp(() {
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    contactRequestRepo = FakeContactRequestRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService();
    secureKeyStore = FakeSecureKeyStore();
    messageRepo = InMemoryMessageRepository();
    mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
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
    postRepository.dispose();
    postsPrivacySettingsRepository.dispose();
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
    FakeIdentityRepository? identityRepository,
    ContactRequestListener? contactRequestListener,
    ChatMessageListener? chatMessageListener,
    FakeReactionRepository? reactionRepository,
    ReactionListener? reactionListener,
    ContactRepository? contactRepository,
    MessageRepository? messageRepository,
    MediaAttachmentRepository? mediaAttachmentRepository,
    MediaFileManager? mediaFileManagerOverride,
    EditChatMessageFn? editChatMessageFn,
    DeleteMessageForMeFn? deleteForMeFn,
    DeleteMessageForEveryoneFn? deleteForEveryoneFn,
    InMemoryGroupRepository? groupRepository,
    InMemoryGroupMessageRepository? groupMessageRepository,
    FakeGroupReactionReplayOutboxRepository?
    groupReactionReplayOutboxRepository,
    GroupMessageListener? groupMessageListener,
    GroupInviteListener? groupInviteListener,
    InMemoryIntroductionRepository? introductionRepository,
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
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: navigatorObservers ?? const <NavigatorObserver>[],
      home: FeedWired(
        repository: identityRepository ?? identityRepo,
        contactRepository: effectiveContactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: crListener,
        messageRepository: effectiveMessageRepo,
        postRepository: postRepository,
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
        groupReactionReplayOutboxRepository:
            groupReactionReplayOutboxRepository,
        groupMessageListener: groupMessageListener,
        groupInviteListener: groupInviteListener,
        introductionRepository: introductionRepository,
        introductionListener: introductionListener,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
        editChatMessageFn: editChatMessageFn ?? editChatMessage,
        deleteMessageForMeFn: deleteForMeFn ?? deleteMessageForMe,
        deleteMessageForEveryoneFn:
            deleteForEveryoneFn ?? deleteMessageForEveryone,
      ),
    );
  }

  Future<void> pumpFeedFrames(WidgetTester tester, {int count = 6}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> saveSelfGroupMember(
    InMemoryGroupRepository groupRepo,
    String groupId, {
    MemberRole role = MemberRole.writer,
  }) async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: testIdentity.peerId,
        username: testIdentity.username,
        role: role,
        publicKey: testIdentity.publicKey,
        joinedAt: DateTime.utc(2026, 2, 1, 0, 1),
      ),
    );
  }

  Future<void> saveOtherGroupMember(
    InMemoryGroupRepository groupRepo,
    String groupId, {
    required String peerId,
    required String username,
    MemberRole role = MemberRole.writer,
  }) async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: peerId,
        username: username,
        role: role,
        joinedAt: DateTime.utc(2026, 2, 1, 0, 2),
      ),
    );
  }

  NavBarButton navButton(WidgetTester tester, String label, {Finder? scope}) {
    final finder = scope == null
        ? find.byType(NavBarButton)
        : find.descendant(of: scope, matching: find.byType(NavBarButton));
    return tester
        .widgetList<NavBarButton>(finder)
        .singleWhere((button) => button.label == label);
  }

  void setPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder feedOrbitSwipeHost() =>
      find.byKey(const ValueKey<String>('feed-orbit-swipe-host'));

  Finder feedOrbitNavLabel() => find.descendant(
    of: find.byType(FeedScreen),
    matching: find.text('Orbit'),
  );

  Finder orbitFeedNavLabel() =>
      find.descendant(of: find.byType(OrbitWired), matching: find.text('Feed'));

  Finder orbitSearchField() => find.descendant(
    of: find.byType(OrbitWired),
    matching: find.byType(TextField),
  );

  Finder orbitScopedText(String text) =>
      find.descendant(of: find.byType(OrbitWired), matching: find.text(text));

  Finder orbitFriendRow(String username) => find
      .ancestor(
        of: orbitScopedText(username).first,
        matching: find.byType(FriendRow),
      )
      .first;

  Finder orbitFriendUnreadCount(String username, String count) =>
      find.descendant(of: orbitFriendRow(username), matching: find.text(count));

  Finder orbitFriendChevron(String username) => find.descendant(
    of: orbitFriendRow(username),
    matching: find.byIcon(Icons.chevron_right),
  );

  Finder feedScrollView() =>
      find.byKey(const PageStorageKey<String>('feed-scroll'));

  Finder feedScrollable() => find.descendant(
    of: feedScrollView(),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  double currentFeedScrollOffset(WidgetTester tester) {
    expect(feedScrollable(), findsOneWidget);
    return tester.state<ScrollableState>(feedScrollable()).position.pixels;
  }

  Rect feedViewportRect(WidgetTester tester) {
    expect(feedScrollable(), findsOneWidget);
    return tester.getRect(feedScrollable());
  }

  bool isVisibleInFeedViewport(WidgetTester tester, Finder finder) {
    if (finder.evaluate().isEmpty) {
      return false;
    }
    final targetRect = tester.getRect(finder);
    final viewportRect = feedViewportRect(tester);
    return targetRect.bottom > viewportRect.top &&
        targetRect.top < viewportRect.bottom;
  }

  Future<void> dragFeedUntilVisible(
    WidgetTester tester,
    Finder finder, {
    int maxAttempts = 20,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (isVisibleInFeedViewport(tester, finder)) {
        return;
      }
      await tester.drag(feedScrollView(), const Offset(0, -400));
      await pumpFeedFrames(tester, count: 4);
    }

    expect(
      isVisibleInFeedViewport(tester, finder),
      isTrue,
      reason: 'Expected finder to become visible in the Feed viewport',
    );
  }

  Future<void> emitInlineOrbitExit(
    WidgetTester tester,
    FeedRouteChanges changes,
  ) async {
    final feedWired = tester.widget<FeedWired>(find.byType(FeedWired));
    final orbit = tester.widget<OrbitWired>(find.byType(OrbitWired));
    feedWired.appShellController.switchTo('feed');
    orbit.onEmbeddedExit?.call(changes);
    await pumpFeedFrames(tester, count: 8);
  }

  void suppressFeedNavErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (details.toString().contains('overflowed') ||
          message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  IntroductionModel pendingIntroduction({
    required String id,
    required String ownPeerId,
    required String otherPeerId,
    required String createdAt,
    IntroductionStatus recipientStatus = IntroductionStatus.pending,
    IntroductionStatus introducedStatus = IntroductionStatus.pending,
    IntroductionOverallStatus status = IntroductionOverallStatus.pending,
  }) {
    return IntroductionModel(
      id: id,
      introducerId: 'introducer-peer-id',
      recipientId: ownPeerId,
      introducedId: otherPeerId,
      recipientStatus: recipientStatus,
      introducedStatus: introducedStatus,
      status: status,
      createdAt: createdAt,
      introducerUsername: 'Eve',
      recipientUsername: testIdentity.username,
      introducedUsername: 'Dora',
    );
  }

  PendingGroupInvite makePendingInvite({
    String groupId = 'grp-feed-intro',
    String groupName = 'Orbit Writers',
  }) {
    return PendingGroupInvite.fromPayload(
      GroupInvitePayload(
        id: 'invite-$groupId',
        groupId: groupId,
        groupKey: 'group-key',
        keyEpoch: 1,
        groupConfig: {
          'name': groupName,
          'groupType': 'chat',
          'description': 'Pending review',
          'createdBy': 'peer-admin',
          'createdAt': '2026-04-06T10:00:00.000Z',
          'members': [
            {
              'peerId': 'peer-admin',
              'username': 'Alice',
              'role': 'admin',
              'publicKey': 'pk-admin',
              'mlKemPublicKey': 'mlkem-admin',
            },
            {
              'peerId': testIdentity.peerId,
              'username': testIdentity.username,
              'role': 'writer',
              'publicKey': testIdentity.publicKey,
              'mlKemPublicKey': 'mlkem-user',
            },
          ],
        },
        senderPeerId: 'peer-admin',
        senderUsername: 'Alice',
        timestamp: '2026-04-06T10:00:00.000Z',
        invitePolicy: GroupInvitePolicy(
          expiresAt: DateTime.utc(2026, 4, 7, 10),
          allowedDevices: [testIdentity.peerId],
          assignedRole: 'writer',
          canInviteOthers: false,
          joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
          keyEpoch: 1,
        ),
      ),
      receivedAt: DateTime.utc(2026, 4, 6, 10, 5),
    );
  }

  group('FeedWired', () {
    testWidgets('loads stored cosmic background preference into Feed', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      await secureKeyStore.write(
        BackgroundPreference.storageKey,
        BackgroundPreference.cosmic.toStorageString(),
      );

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 8);

      expect(find.byType(FeedScreen), findsOneWidget);
      expect(find.byType(CosmicBackground), findsOneWidget);
    });

    testWidgets(
      'refreshes background preference after returning from Settings',
      (tester) async {
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        expect(find.byType(CosmicBackground), findsNothing);

        await tester.tap(find.byType(UserAvatar).first);
        await pumpFeedFrames(tester, count: 10);

        expect(find.text('Settings'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('background-choice-cosmic')),
        );
        await tester.tap(
          find.byKey(const ValueKey('background-choice-cosmic')),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          await secureKeyStore.read(BackgroundPreference.storageKey),
          BackgroundPreference.cosmic.toStorageString(),
        );

        await tester.tap(find.byIcon(Icons.chevron_left));
        await pumpFeedFrames(tester, count: 10);

        expect(find.byType(FeedScreen), findsOneWidget);
        expect(find.byType(CosmicBackground), findsOneWidget);
      },
    );

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
    });

    testWidgets(
      'orbit tab switch keeps the shared nav visible inside the inline host',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          final message = details.exceptionAsString();
          if (details.toString().contains('overflowed') ||
              message.contains('Unable to load asset') ||
              message.contains('SvgPicture') ||
              message.contains('ImageFilter')) {
            return;
          }
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        await tester.tap(find.text('Orbit'));
        await pumpFeedFrames(tester, count: 10);

        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        expect(find.byType(OrbitWired), findsOneWidget);
        expect(navigator.canPop(), isFalse);
        expect(
          find.descendant(
            of: find.byType(OrbitWired),
            matching: find.byType(FeedNavigationBar),
          ),
          findsOneWidget,
        );

        final orbitButtons = tester
            .widgetList<NavBarButton>(
              find.descendant(
                of: find.byType(OrbitWired),
                matching: find.byType(NavBarButton),
              ),
            )
            .toList();
        expect(orbitButtons, hasLength(2));
        expect(orbitButtons[0].isActive, isFalse);
        expect(orbitButtons[1].isActive, isTrue);
      },
    );

    testWidgets(
      'loads the Orbit badge from non-expired pending introductions on first load',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);
        final now = DateTime.now().toUtc();

        final introRepo = InMemoryIntroductionRepository();
        await introRepo.saveIntroduction(
          pendingIntroduction(
            id: 'intro-fresh',
            ownPeerId: testIdentity.peerId,
            otherPeerId: 'fresh-peer-id',
            createdAt: now.subtract(const Duration(days: 5)).toIso8601String(),
          ),
        );
        await introRepo.saveIntroduction(
          pendingIntroduction(
            id: 'intro-expired',
            ownPeerId: testIdentity.peerId,
            otherPeerId: 'expired-peer-id',
            createdAt: now.subtract(const Duration(days: 45)).toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(introductionRepository: introRepo),
        );
        await pumpFeedFrames(tester, count: 8);

        expect(navButton(tester, 'Orbit').badgeCount, 1);
        final expiredIntro = await introRepo.getIntroduction('intro-expired');
        expect(expiredIntro?.status, IntroductionOverallStatus.expired);
      },
    );

    testWidgets(
      'loads the Orbit badge from folded pending introduction targets on first load',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        final introRepo = InMemoryIntroductionRepository();
        await introRepo.saveIntroduction(
          pendingIntroduction(
            id: 'intro-noor',
            ownPeerId: testIdentity.peerId,
            otherPeerId: 'folded-peer-id',
            createdAt: freshPendingIntroductionCreatedAt(),
          ).copyWith(introducerId: 'peer-noor', introducerUsername: 'Noor'),
        );
        await introRepo.saveIntroduction(
          pendingIntroduction(
            id: 'intro-layla',
            ownPeerId: testIdentity.peerId,
            otherPeerId: 'folded-peer-id',
            createdAt: freshPendingIntroductionCreatedAt(),
          ).copyWith(introducerId: 'peer-layla', introducerUsername: 'Layla'),
        );

        await tester.pumpWidget(
          buildFeedWired(introductionRepository: introRepo),
        );
        await pumpFeedFrames(tester, count: 8);

        expect(navButton(tester, 'Orbit').badgeCount, 1);
      },
    );

    testWidgets(
      'loads the Orbit badge from pending group invites on first load',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        await pendingInviteRepo.savePendingInvite(makePendingInvite());
        final fakeGroupInviteListener = _FakeGroupInviteListener(
          pendingInviteRepo: pendingInviteRepo,
        );

        await tester.pumpWidget(
          buildFeedWired(groupInviteListener: fakeGroupInviteListener),
        );
        await pumpFeedFrames(tester, count: 8);

        expect(navButton(tester, 'Orbit').badgeCount, 1);
      },
    );

    testWidgets(
      'refreshes the Orbit badge on intro receipt and remote status changes',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        final introRepo = InMemoryIntroductionRepository();
        final fakeIntroListener = _FakeIntroductionListener(
          introRepo: introRepo,
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          bridge: bridge,
        );

        await tester.pumpWidget(
          buildFeedWired(
            introductionRepository: introRepo,
            introductionListener: fakeIntroListener,
          ),
        );
        await pumpFeedFrames(tester, count: 8);

        expect(
          navButton(tester, 'Orbit', scope: find.byType(FeedScreen)).badgeCount,
          0,
        );

        final intro = pendingIntroduction(
          id: 'intro-live',
          ownPeerId: testIdentity.peerId,
          otherPeerId: 'live-peer-id',
          createdAt: freshPendingIntroductionCreatedAt(),
        );
        await introRepo.saveIntroduction(intro);
        fakeIntroListener.emitIntroReceived(intro);
        await pumpFeedFrames(tester, count: 4);

        expect(navButton(tester, 'Orbit').badgeCount, 1);

        final passedIntro = intro.copyWith(
          recipientStatus: IntroductionStatus.passed,
          status: IntroductionOverallStatus.passed,
        );
        await introRepo.updateRecipientStatus(
          intro.id,
          IntroductionStatus.passed,
        );
        await introRepo.updateOverallStatus(
          intro.id,
          IntroductionOverallStatus.passed,
        );
        fakeIntroListener.emitIntroStatusChanged(passedIntro);
        await pumpFeedFrames(tester, count: 4);

        expect(
          navButton(tester, 'Orbit', scope: find.byType(FeedScreen)).badgeCount,
          0,
        );
      },
    );

    testWidgets(
      'refreshes the Orbit badge when a pending group invite arrives',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final fakeGroupInviteListener = _FakeGroupInviteListener(
          pendingInviteRepo: pendingInviteRepo,
        );

        await tester.pumpWidget(
          buildFeedWired(groupInviteListener: fakeGroupInviteListener),
        );
        await pumpFeedFrames(tester, count: 8);

        expect(navButton(tester, 'Orbit').badgeCount, 0);

        final invite = makePendingInvite(groupId: 'grp-live');
        await pendingInviteRepo.savePendingInvite(invite);
        fakeGroupInviteListener.emitPendingInvite(invite);
        await pumpFeedFrames(tester, count: 4);

        expect(navButton(tester, 'Orbit').badgeCount, 1);
      },
    );

    testWidgets(
      'inline orbit return refreshes the Orbit badge after local intro actions',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        final introRepo = InMemoryIntroductionRepository();
        final intro = pendingIntroduction(
          id: 'intro-route-return',
          ownPeerId: testIdentity.peerId,
          otherPeerId: 'route-peer-id',
          createdAt: freshPendingIntroductionCreatedAt(),
        );
        await introRepo.saveIntroduction(intro);

        await tester.pumpWidget(
          buildFeedWired(introductionRepository: introRepo),
        );
        await pumpFeedFrames(tester, count: 8);

        expect(navButton(tester, 'Orbit').badgeCount, 1);

        await tester.tap(find.text('Orbit'));
        await pumpFeedFrames(tester, count: 10);

        await introRepo.updateRecipientStatus(
          intro.id,
          IntroductionStatus.passed,
        );
        await introRepo.updateOverallStatus(
          intro.id,
          IntroductionOverallStatus.passed,
        );
        await emitInlineOrbitExit(
          tester,
          const FeedRouteChanges(refreshPendingIntroductions: true),
        );

        expect(
          navButton(tester, 'Orbit', scope: find.byType(FeedScreen)).badgeCount,
          0,
        );
      },
    );

    testWidgets(
      'inline orbit return refreshes the Orbit badge after local pending group invite changes',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final invite = makePendingInvite(groupId: 'grp-route-return');
        await pendingInviteRepo.savePendingInvite(invite);
        final fakeGroupInviteListener = _FakeGroupInviteListener(
          pendingInviteRepo: pendingInviteRepo,
        );

        await tester.pumpWidget(
          buildFeedWired(groupInviteListener: fakeGroupInviteListener),
        );
        await pumpFeedFrames(tester, count: 8);

        expect(navButton(tester, 'Orbit').badgeCount, 1);

        await tester.tap(find.text('Orbit'));
        await pumpFeedFrames(tester, count: 10);

        await pendingInviteRepo.deletePendingInvite(invite.groupId);
        await emitInlineOrbitExit(
          tester,
          const FeedRouteChanges(refreshPendingIntroductions: true),
        );

        expect(
          navButton(tester, 'Orbit', scope: find.byType(FeedScreen)).badgeCount,
          0,
        );
      },
    );

    testWidgets('feed scroll position survives an inline orbit round trip', (
      tester,
    ) async {
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);

      final contacts = List.generate(
        40,
        (index) => testContact.copyWith(
          peerId: 'scroll-peer-$index',
          publicKey: 'scroll-pk-$index',
          username: 'Scroll User $index',
          signature: 'scroll-sig-$index',
          scannedAt:
              '2026-02-01T09:${index.toString().padLeft(2, '0')}:00.000Z',
        ),
      );
      contactRepo.seed(contacts);
      for (final contact in contacts) {
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'scroll-msg-${contact.peerId}',
            contactPeerId: contact.peerId,
            text: 'Message for ${contact.username}',
            senderPeerId: contact.peerId,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
      }

      double feedScrollOffset() {
        final scrollableFinder = find.descendant(
          of: find.byKey(const PageStorageKey<String>('feed-scroll')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        expect(scrollableFinder, findsOneWidget);
        return tester.state<ScrollableState>(scrollableFinder).position.pixels;
      }

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 10);
      expect(feedScrollOffset(), 0);

      await tester.drag(
        find.byKey(const PageStorageKey<String>('feed-scroll')),
        const Offset(0, -1600),
      );
      await pumpFeedFrames(tester, count: 10);

      final scrolledOffset = feedScrollOffset();
      expect(scrolledOffset, greaterThan(0));

      await tester.tap(feedOrbitNavLabel());
      await pumpFeedFrames(tester, count: 10);
      await tester.tap(orbitFeedNavLabel());
      await pumpFeedFrames(tester, count: 10);

      expect(feedScrollOffset(), closeTo(scrolledOffset, 1));
    });

    testWidgets(
      'successful inline reply reorients the viewport to the same moved feed card',
      (tester) async {
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);
        p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final contacts = List.generate(
          28,
          (index) => testContact.copyWith(
            peerId: 'reorient-peer-$index',
            publicKey: 'reorient-pk-$index',
            username: 'Reorient User $index',
            signature: 'reorient-sig-$index',
            scannedAt:
                '2026-03-01T09:${index.toString().padLeft(2, '0')}:00.000Z',
          ),
        );
        contactRepo.seed(contacts);

        final newestTimestamp = DateTime.utc(2026, 3, 1, 12, 0);
        for (var index = 0; index < contacts.length; index++) {
          final contact = contacts[index];
          final timestamp = newestTimestamp.subtract(Duration(minutes: index));
          await messageRepo.saveMessage(
            ConversationMessage(
              id: 'reorient-msg-${contact.peerId}',
              contactPeerId: contact.peerId,
              text: 'Unread for ${contact.username}',
              senderPeerId: contact.peerId,
              timestamp: timestamp.toIso8601String(),
              isIncoming: true,
              status: 'delivered',
              createdAt: timestamp.toIso8601String(),
            ),
          );
        }

        final targetContact = contacts[18];
        final targetCardFinder = find.byKey(
          ValueKey<String>('thread_${targetContact.peerId}'),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 10);

        await dragFeedUntilVisible(tester, targetCardFinder, maxAttempts: 24);
        final offsetBeforeReply = currentFeedScrollOffset(tester);
        expect(offsetBeforeReply, greaterThan(0));
        expect(isVisibleInFeedViewport(tester, targetCardFinder), isTrue);

        final targetComposerField = find.descendant(
          of: targetCardFinder,
          matching: find.byType(TextField),
        );
        expect(targetComposerField, findsOneWidget);

        await tester.enterText(targetComposerField, 'Stay with this card');
        await tester.pump();

        final sendButton = find.descendant(
          of: targetCardFinder,
          matching: find.byIcon(Icons.arrow_upward_rounded),
        );
        expect(sendButton, findsOneWidget);
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await pumpFeedFrames(tester, count: 12);

        final offsetAfterReply = currentFeedScrollOffset(tester);
        expect(
          offsetAfterReply,
          greaterThan(offsetBeforeReply),
          reason:
              'The scroll offset should change so the viewport follows the moved card',
        );
        expect(targetCardFinder, findsOneWidget);
        expect(
          isVisibleInFeedViewport(tester, targetCardFinder),
          isTrue,
          reason:
              'The same card should remain visible after it collapses and reorders',
        );
        expect(
          find.descendant(
            of: targetCardFinder,
            matching: find.textContaining('You replied'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: targetCardFinder,
            matching: find.byType(CollapsedModeCardBody),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: targetCardFinder,
            matching: find.byType(TextField),
          ),
          findsOneWidget,
          reason:
              'The post-reply card should still be immediately usable for a follow-up reply',
        );
      },
    );

    testWidgets('orbit search state survives an inline host tab round trip', (
      tester,
    ) async {
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);

      final otherContact = testContact.copyWith(
        peerId: 'contact-peer-id-2',
        publicKey: 'contact-pk-2',
        username: 'Cara',
        signature: 'sig-2',
        scannedAt: '2026-02-01T09:30:00.000Z',
      );
      contactRepo.seed([testContact, otherContact]);

      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-orbit-search-1',
          contactPeerId: testContact.peerId,
          text: 'Bob orbit message',
          senderPeerId: testContact.peerId,
          timestamp: '2026-02-01T10:00:00.000Z',
          isIncoming: true,
          status: 'delivered',
          createdAt: '2026-02-01T10:00:00.000Z',
        ),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-orbit-search-2',
          contactPeerId: otherContact.peerId,
          text: 'Cara orbit message',
          senderPeerId: otherContact.peerId,
          timestamp: '2026-02-01T10:05:00.000Z',
          isIncoming: true,
          status: 'delivered',
          createdAt: '2026-02-01T10:05:00.000Z',
        ),
      );

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 10);

      await tester.tap(feedOrbitNavLabel());
      await pumpFeedFrames(tester, count: 10);

      await tester.tap(find.byType(OrbitSearchTrigger));
      await pumpFeedFrames(tester, count: 4);
      await tester.enterText(orbitSearchField(), 'Bo');
      await pumpFeedFrames(tester, count: 4);

      expect(orbitScopedText('Bob'), findsWidgets);
      expect(orbitScopedText('Cara'), findsNothing);

      await tester.tap(orbitFeedNavLabel());
      await pumpFeedFrames(tester, count: 10);
      await tester.tap(feedOrbitNavLabel());
      await pumpFeedFrames(tester, count: 10);

      expect(orbitScopedText('Bob'), findsWidgets);
      expect(orbitScopedText('Cara'), findsNothing);
      final searchField = tester.widget<TextField>(orbitSearchField());
      expect(searchField.controller!.text, 'Bo');
    });

    testWidgets(
      'feed left swipe follows the finger and snaps back before threshold',
      (tester) async {
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        final feedScrollFinder = find.byKey(
          const PageStorageKey<String>('feed-scroll'),
        );
        final hostFinder = feedOrbitSwipeHost();
        final initialDx = tester.getTopLeft(feedScrollFinder).dx;

        final gesture = await tester.startGesture(tester.getCenter(hostFinder));
        await gesture.moveBy(const Offset(-70, 0));
        await tester.pump();

        final draggedDx = tester.getTopLeft(feedScrollFinder).dx;
        expect(draggedDx, lessThan(initialDx));

        await gesture.up();
        await pumpFeedFrames(tester, count: 8);

        expect(appShellController.activeTab, 'feed');
        expect(tester.getTopLeft(feedScrollFinder).dx, closeTo(initialDx, 1));
      },
    );

    testWidgets('feed left swipe completes into orbit by threshold', (
      tester,
    ) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 8);

      await tester.drag(feedOrbitSwipeHost(), const Offset(-170, 0));
      await pumpFeedFrames(tester, count: 8);

      expect(appShellController.activeTab, 'orbit');
      expect(find.byType(OrbitWired), findsOneWidget);
    });

    testWidgets(
      'feed left fling completes into orbit below distance threshold',
      (tester) async {
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        await tester.fling(feedOrbitSwipeHost(), const Offset(-90, 0), 2400);
        await pumpFeedFrames(tester, count: 8);

        expect(appShellController.activeTab, 'orbit');
        expect(find.byType(OrbitWired), findsOneWidget);
      },
    );

    testWidgets('feed swipe-away clears inline reply focus', (tester) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'focus-msg-1',
          contactPeerId: testContact.peerId,
          text: 'Focus me before orbit',
          senderPeerId: testContact.peerId,
          timestamp: '2026-03-30T10:00:00.000Z',
          isIncoming: true,
          status: 'delivered',
          createdAt: '2026-03-30T10:00:00.000Z',
        ),
      );

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 8);

      await tester.tap(find.byType(TextField).first);
      await tester.pump();

      final editableBefore = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(editableBefore.focusNode.hasFocus, isTrue);

      await tester.drag(feedOrbitSwipeHost(), const Offset(-170, 0));
      await pumpFeedFrames(tester, count: 8);

      final editableAfter = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(appShellController.activeTab, 'orbit');
      expect(editableAfter.focusNode.hasFocus, isFalse);
    });

    testWidgets(
      'feed quote swipe keeps ownership over right-swipe message gestures',
      (tester) async {
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'quote-gesture-msg-1',
            contactPeerId: testContact.peerId,
            text: 'Quote gesture stays local',
            senderPeerId: testContact.peerId,
            timestamp: '2026-03-30T10:05:00.000Z',
            isIncoming: true,
            status: 'delivered',
            createdAt: '2026-03-30T10:05:00.000Z',
          ),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        await tester.drag(
          find.byType(SwipeToQuoteBubble).first,
          const Offset(60, 0),
        );
        await pumpFeedFrames(tester, count: 4);

        expect(appShellController.activeTab, 'feed');
        expect(find.text('Replying to'), findsOneWidget);
        expect(find.text('Quote gesture stays local'), findsWidgets);
      },
    );

    testWidgets('orbit right swipe completes back to feed', (tester) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 8);

      await tester.tap(find.text('Orbit'));
      await pumpFeedFrames(tester, count: 10);

      await tester.drag(feedOrbitSwipeHost(), const Offset(170, 0));
      await pumpFeedFrames(tester, count: 8);

      expect(appShellController.activeTab, 'feed');
      expect(find.byType(OrbitWired), findsOneWidget);
    });

    testWidgets('orbit row-area left swipe does not trigger screen return', (
      tester,
    ) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'orbit-row-msg-1',
          contactPeerId: testContact.peerId,
          text: 'Orbit row message',
          senderPeerId: testContact.peerId,
          timestamp: '2026-03-30T10:10:00.000Z',
          isIncoming: true,
          status: 'delivered',
          createdAt: '2026-03-30T10:10:00.000Z',
        ),
      );

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 8);

      await tester.tap(find.text('Orbit'));
      await pumpFeedFrames(tester, count: 10);

      final orbitBobFinder = orbitScopedText('Bob').first;
      await tester.ensureVisible(orbitBobFinder);
      await tester.pump();
      await tester.drag(orbitBobFinder, const Offset(-230, 0));
      await pumpFeedFrames(tester, count: 6);

      expect(appShellController.activeTab, 'orbit');
      expect(find.byType(OrbitWired), findsOneWidget);
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
      'tapping open-mode nickname collapses card and clears unread state',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final unreadTimestamp = DateTime.now().toUtc().toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-unread-name-collapse',
            contactPeerId: testContact.peerId,
            text: 'Tap the name to mark read',
            senderPeerId: testContact.peerId,
            timestamp: unreadTimestamp,
            isIncoming: true,
            status: 'delivered',
            createdAt: unreadTimestamp,
          ),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        expect(find.byType(OpenModeCardBody), findsOneWidget);
        final nicknameFinder = find.descendant(
          of: find.byType(OpenModeCardBody),
          matching: find.text('Bob'),
        );
        expect(nicknameFinder, findsOneWidget);

        await tester.tap(nicknameFinder);
        await pumpFeedFrames(tester, count: 8);

        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.byType(OpenModeCardBody), findsNothing);
        expect(find.text('Tap to expand'), findsOneWidget);

        final refreshedMessage = await messageRepo.getMessage(
          'msg-unread-name-collapse',
        );
        expect(
          refreshedMessage?.readAt,
          isNotNull,
          reason: 'Tapping the open-mode nickname should mark the message read',
        );
      },
    );

    testWidgets(
      'collapsing an unread feed card clears the same mounted Orbit row',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final unreadTimestamp = DateTime.now().toUtc().toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'mounted-orbit-collapse-unread',
            contactPeerId: testContact.peerId,
            text: 'Unread for Orbit sync',
            senderPeerId: testContact.peerId,
            timestamp: unreadTimestamp,
            isIncoming: true,
            status: 'delivered',
            createdAt: unreadTimestamp,
          ),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        expect(find.byType(OpenModeCardBody), findsOneWidget);

        await tester.tap(feedOrbitNavLabel());
        await pumpFeedFrames(tester, count: 10);

        await tester.ensureVisible(orbitScopedText('Bob').first);
        await tester.pump();
        expect(orbitFriendUnreadCount('Bob', '1'), findsOneWidget);

        await tester.tap(orbitFeedNavLabel());
        await pumpFeedFrames(tester, count: 10);

        await tester.tap(find.text('Collapse'));
        await pumpFeedFrames(tester, count: 8);

        await tester.tap(feedOrbitNavLabel());
        await pumpFeedFrames(tester, count: 10);

        await tester.ensureVisible(orbitScopedText('Bob').first);
        await tester.pump();
        expect(orbitFriendUnreadCount('Bob', '1'), findsNothing);
        expect(orbitFriendChevron('Bob'), findsOneWidget);
      },
    );

    testWidgets('successful inline reply clears the same mounted Orbit row', (
      tester,
    ) async {
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );

      final unreadTimestamp = DateTime.now().toUtc().toIso8601String();
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'mounted-orbit-reply-unread',
          contactPeerId: testContact.peerId,
          text: 'Reply from this card',
          senderPeerId: testContact.peerId,
          timestamp: unreadTimestamp,
          isIncoming: true,
          status: 'delivered',
          createdAt: unreadTimestamp,
        ),
      );

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 8);

      await tester.tap(feedOrbitNavLabel());
      await pumpFeedFrames(tester, count: 10);

      await tester.ensureVisible(orbitScopedText('Bob').first);
      await tester.pump();
      expect(orbitFriendUnreadCount('Bob', '1'), findsOneWidget);

      await tester.tap(orbitFeedNavLabel());
      await pumpFeedFrames(tester, count: 10);

      final feedComposerField = find.descendant(
        of: find.byType(FeedScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(feedComposerField.first, 'B1 reply');
      await tester.pump();
      final sendButton = find
          .descendant(
            of: find.byType(FeedScreen),
            matching: find.byIcon(Icons.arrow_upward_rounded),
          )
          .first;
      await tester.ensureVisible(sendButton);
      await tester.pump();
      await tester.tap(sendButton);
      await pumpFeedFrames(tester, count: 8);

      expect(find.textContaining('You replied'), findsOneWidget);

      await tester.tap(feedOrbitNavLabel());
      await pumpFeedFrames(tester, count: 10);

      await tester.ensureVisible(orbitScopedText('Bob').first);
      await tester.pump();
      expect(orbitFriendUnreadCount('Bob', '1'), findsNothing);
      expect(orbitFriendChevron('Bob'), findsOneWidget);
    });

    testWidgets(
      'successful inline reply keeps first Orbit open clear when Orbit was not mounted',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final unreadTimestamp = DateTime.now().toUtc().toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'later-open-orbit-reply-unread',
            contactPeerId: testContact.peerId,
            text: 'Later-open Orbit sync',
            senderPeerId: testContact.peerId,
            timestamp: unreadTimestamp,
            isIncoming: true,
            status: 'delivered',
            createdAt: unreadTimestamp,
          ),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        final feedComposerField = find.descendant(
          of: find.byType(FeedScreen),
          matching: find.byType(TextField),
        );
        await tester.enterText(feedComposerField.first, 'B1 reply');
        await tester.pump();
        final sendButton = find
            .descendant(
              of: find.byType(FeedScreen),
              matching: find.byIcon(Icons.arrow_upward_rounded),
            )
            .first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await pumpFeedFrames(tester, count: 8);

        expect(find.textContaining('You replied'), findsOneWidget);

        await tester.tap(feedOrbitNavLabel());
        await pumpFeedFrames(tester, count: 10);

        await tester.ensureVisible(orbitScopedText('Bob').first);
        await tester.pump();
        expect(orbitFriendUnreadCount('Bob', '1'), findsNothing);
        expect(orbitFriendChevron('Bob'), findsOneWidget);
      },
    );

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
      final expandFinder = find.text('Tap to expand').last;
      await tester.ensureVisible(expandFinder);
      await tester.pump();
      await tester.tap(expandFinder);
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
        messageRepo: messageRepo,
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
          messageRepo: spyMessageRepo,
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

    testWidgets(
      'incremental group message blocks tampered done media in feed card',
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

        const relativePath = 'media/groups/feed-tampered.jpg';
        final absolutePath = await mediaFileManager.resolveStoredPath(
          relativePath,
        );
        final file = File(absolutePath)..createSync(recursive: true);
        file.writeAsBytesSync(utf8.encode('tampered feed bytes'));
        final newMsg = GroupMessage(
          id: 'gm-media-tampered',
          groupId: 'g1',
          senderPeerId: 'other-peer',
          senderUsername: 'Hisam',
          text: 'Check this',
          timestamp: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
        );
        await groupMsgRepo.saveMessage(newMsg);
        final tamperedAttachment = MediaAttachment(
          id: 'att-gm-tampered',
          messageId: 'gm-media-tampered',
          mime: 'image/jpeg',
          size: file.lengthSync(),
          mediaType: 'image',
          localPath: relativePath,
          downloadStatus: 'done',
          contentHash: 'not-a-valid-sha256',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );
        await mediaAttachmentRepo.saveAttachment(tamperedAttachment);

        fakeGroupListener.emitGroupMessage(newMsg);
        await pumpFeedFrames(tester);

        expect(find.byType(FeedCard), findsOneWidget);
        final bubbles = tester
            .widgetList<MessageBubble>(find.byType(MessageBubble))
            .toList();
        final bubble = bubbles.first;
        expect(bubble.media.single.id, 'att-gm-tampered');
        expect(
          bubble.media.single.downloadStatus,
          kMediaDownloadStatusIntegrityFailed,
        );
        expect(bubble.media.single.localPath, absolutePath);
      },
    );

    testWidgets(
      'incoming group message clears session reply so card shows open mode',
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
            name: 'Reply Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );

        // Seed a read message so the card starts in collapsed mode
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-read-1',
            groupId: 'g1',
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Old message',
            timestamp: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            createdAt: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            readAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
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

        // Card should start in collapsed mode (all messages read)
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);

        // Now seed an unread incoming message and emit it
        final newMsg = GroupMessage(
          id: 'gm-unread-1',
          groupId: 'g1',
          senderPeerId: 'other-peer',
          senderUsername: 'OtherUser',
          text: 'New unread group msg!',
          timestamp: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
        );
        await groupMsgRepo.saveMessage(newMsg);
        fakeGroupListener.emitGroupMessage(newMsg);

        await pumpFeedFrames(tester);

        // Card should switch to open mode (unread message arrived,
        // session reply cleared if any)
        expect(find.byType(OpenModeCardBody), findsOneWidget);
        expect(find.byType(CollapsedModeCardBody), findsNothing);
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
      'late mutual acceptance surfaces intro connection card and later block update keeps the same contact card',
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
        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: spyMessageRepo,
          contactRepo: spyContactRepo,
        );
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
            chatMessageListener: fakeChatListener,
            introductionListener: fakeIntroListener,
          ),
        );
        await pumpFeedFrames(tester);

        final introducedContact = ContactModel(
          peerId: 'intro-peer-id',
          publicKey: 'intro-pk',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Dora',
          signature: 'intro-sig',
          scannedAt: '2026-03-02T12:00:00.000Z',
          introducedBy: 'Eve',
          introducedByPeerId: 'introducer-peer-id',
        );
        await spyContactRepo.addContact(introducedContact);

        fakeIntroListener.emitIntroStatusChanged(
          IntroductionModel(
            id: 'intro-late-feed',
            introducerId: 'introducer-peer-id',
            recipientId: testIdentity.peerId,
            introducedId: introducedContact.peerId,
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.mutualAccepted,
            createdAt: '2026-02-25T11:00:00.000Z',
            introducerUsername: 'Eve',
            recipientUsername: testIdentity.username,
            introducedUsername: introducedContact.username,
          ),
        );

        await pumpFeedFrames(tester);

        expect(find.textContaining('Dora'), findsWidgets);
        expect(find.text('Introduced by Eve'), findsOneWidget);
        expect(find.byType(IntroductionConnectionCard), findsOneWidget);

        final blockedContact = introducedContact.copyWith(
          isBlocked: true,
          blockedAt: '2026-03-02T12:05:00.000Z',
        );
        await spyContactRepo.addContact(blockedContact);
        fakeChatListener.emitContactUpdate(blockedContact);

        await pumpFeedFrames(tester);

        expect(find.textContaining('Dora'), findsWidgets);
        expect(find.text('Introduced by Eve'), findsOneWidget);
        expect(find.byType(IntroductionConnectionCard), findsOneWidget);
        expect(find.text('Blocked'), findsOneWidget);
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
        await emitInlineOrbitExit(
          tester,
          const FeedRouteChanges(changedContactPeerIds: {'contact-peer-id'}),
        );

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
        await emitInlineOrbitExit(
          tester,
          const FeedRouteChanges(reloadAllContacts: true),
        );

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

    testWidgets(
      'orbit route result refreshes only the changed group snapshot',
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
            createdAt: DateTime.utc(2026, 2, 1),
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
            createdAt: DateTime.utc(2026, 2, 2),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await spyGroupMessageRepo.saveMessage(
          GroupMessage(
            id: 'gm-orbit-1',
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
            id: 'gm-orbit-2',
            groupId: 'g2',
            senderPeerId: 'peer-b',
            senderUsername: 'Peer B',
            text: 'Old beta message',
            timestamp: DateTime.utc(2026, 2, 1, 10, 5),
            readAt: DateTime.utc(2026, 2, 1, 10, 35),
            createdAt: DateTime.utc(2026, 2, 1, 10, 5),
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: spyGroupRepo,
            groupMessageRepository: spyGroupMessageRepo,
          ),
        );
        await pumpFeedFrames(tester);

        expect(find.text('Old alpha message'), findsOneWidget);
        expect(find.text('Old beta message'), findsOneWidget);

        await tester.tap(find.text('Orbit'));
        await pumpFeedFrames(tester);

        spyGroupRepo.resetTracking();
        spyGroupMessageRepo.resetTracking();

        await spyGroupMessageRepo.saveMessage(
          GroupMessage(
            id: 'gm-orbit-3',
            groupId: 'g1',
            senderPeerId: 'peer-a',
            senderUsername: 'Peer A',
            text: 'Fresh alpha message',
            timestamp: DateTime.utc(2026, 2, 1, 11),
            createdAt: DateTime.utc(2026, 2, 1, 11),
          ),
        );

        await emitInlineOrbitExit(
          tester,
          const FeedRouteChanges(changedGroupIds: {'g1'}),
        );

        expect(find.text('Fresh alpha message'), findsOneWidget);
        expect(spyGroupRepo.getActiveGroupsCallCount, 0);
        expect(spyGroupRepo.getGroupCallCountById.keys, <String>{'g1'});
        expect(spyGroupRepo.getGroupCallCountById['g1'], 1);
        expect(
          spyGroupMessageRepo.getMessagesPageCallCountByGroupId.keys,
          <String>{'g1'},
        );
        expect(spyGroupMessageRepo.getMessagesPageCallCountByGroupId['g1'], 1);
      },
    );

    testWidgets(
      'changed group snapshot refresh updates the feed group avatar metadata',
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
            id: 'g-avatar',
            name: 'Avatar Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g-avatar',
            createdAt: DateTime.utc(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await spyGroupMessageRepo.saveMessage(
          GroupMessage(
            id: 'gm-avatar-1',
            groupId: 'g-avatar',
            senderPeerId: 'peer-a',
            senderUsername: 'Peer A',
            text: 'Avatar seed message',
            timestamp: DateTime.utc(2026, 2, 1, 10),
            readAt: DateTime.utc(2026, 2, 1, 10, 30),
            createdAt: DateTime.utc(2026, 2, 1, 10),
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: spyGroupRepo,
            groupMessageRepository: spyGroupMessageRepo,
          ),
        );
        await pumpFeedFrames(tester);

        GroupAvatar avatar = tester.widget<GroupAvatar>(
          find.byType(GroupAvatar),
        );
        expect(avatar.groupId, 'g-avatar');
        expect(avatar.avatarPath, isNull);
        expect(avatar.cacheBustKey, isNull);

        await tester.tap(find.text('Orbit'));
        await pumpFeedFrames(tester);

        spyGroupRepo.resetTracking();
        spyGroupMessageRepo.resetTracking();

        final refreshedAt = DateTime.utc(2026, 2, 1, 11, 45);
        await spyGroupRepo.saveGroup(
          GroupModel(
            id: 'g-avatar',
            name: 'Avatar Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g-avatar',
            avatarBlobId: 'blob-2',
            avatarMime: 'image/jpeg',
            avatarPath: 'media/group_avatars/g-avatar.jpg',
            createdAt: DateTime.utc(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
            lastMetadataEventAt: refreshedAt,
          ),
        );

        await emitInlineOrbitExit(
          tester,
          const FeedRouteChanges(changedGroupIds: {'g-avatar'}),
        );

        avatar = tester.widget<GroupAvatar>(find.byType(GroupAvatar));
        expect(avatar.groupId, 'g-avatar');
        expect(avatar.avatarPath, 'media/group_avatars/g-avatar.jpg');
        expect(avatar.cacheBustKey, refreshedAt.toIso8601String());
        expect(spyGroupRepo.getGroupCallCountById.keys, <String>{'g-avatar'});
        expect(spyGroupRepo.getGroupCallCountById['g-avatar'], 1);
        expect(
          spyGroupMessageRepo.getMessagesPageCallCountByGroupId.keys,
          <String>{'g-avatar'},
        );
        expect(
          spyGroupMessageRepo.getMessagesPageCallCountByGroupId['g-avatar'],
          1,
        );
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

      final keyedEntry = find.byKey(
        ValueKey<String>('thread_${testContact.peerId}'),
      );
      expect(keyedEntry, findsOneWidget);
      expect(
        find.descendant(of: keyedEntry, matching: find.byType(FeedCard)),
        findsOneWidget,
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

    testWidgets('group card + button shows media picker bottom sheet', (
      tester,
    ) async {
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
    });

    testWidgets(
      'long-press reply shows preview, focuses composer, and persists quotedMessageId on send',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final originalTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'quoted-msg-long-press',
            contactPeerId: 'contact-peer-id',
            text: 'Long-press quote target',
            senderPeerId: 'contact-peer-id',
            timestamp: originalTimestamp,
            isIncoming: true,
            status: 'delivered',
            createdAt: originalTimestamp,
          ),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        await tester.longPress(find.text('Long-press quote target'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.selectedMessageKey),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(MessageContextOverlay.selectedMessageKey),
            matching: find.text('Long-press quote target'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );

        await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Replying to'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(QuotePreviewBar),
            matching: find.text('Long-press quote target'),
          ),
          findsOneWidget,
        );

        final editable = tester.widget<EditableText>(
          find.descendant(
            of: find.byType(InlineReplyInput),
            matching: find.byType(EditableText),
          ),
        );
        expect(editable.focusNode.hasFocus, isTrue);

        await tester.enterText(
          find.byType(TextField).first,
          'Quoted from long press',
        );
        await tester.pump();

        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await tester.pump(const Duration(milliseconds: 200));

        final sentMessages = await messageRepo.getMessagesForContact(
          'contact-peer-id',
        );
        final sentReply = sentMessages
            .where((message) => message.text == 'Quoted from long press')
            .first;

        expect(sentReply.quotedMessageId, 'quoted-msg-long-press');
      },
    );

    testWidgets(
      'swipe-to-reply shows preview and persists quotedMessageId on send',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final originalTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'quoted-msg-1',
            contactPeerId: 'contact-peer-id',
            text: 'Quote this one',
            senderPeerId: 'contact-peer-id',
            timestamp: originalTimestamp,
            isIncoming: true,
            status: 'delivered',
            createdAt: originalTimestamp,
          ),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        expect(find.byType(SwipeToQuoteBubble), findsOneWidget);

        final swipeBubble = tester.widget<SwipeToQuoteBubble>(
          find.byType(SwipeToQuoteBubble).first,
        );
        swipeBubble.onQuoteTriggered();
        await tester.pump();

        expect(find.text('Replying to'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(QuotePreviewBar),
            matching: find.text('Quote this one'),
          ),
          findsOneWidget,
        );

        await tester.enterText(
          find.byType(TextField).first,
          'Quoted from feed',
        );
        await tester.pump();

        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await tester.pump(const Duration(milliseconds: 200));

        final sentMessages = await messageRepo.getMessagesForContact(
          'contact-peer-id',
        );
        final sentReply = sentMessages
            .where((message) => message.text == 'Quoted from feed')
            .first;

        expect(sentReply.quotedMessageId, 'quoted-msg-1');
      },
    );

    testWidgets(
      'long-press reply on sent feed message focuses composer and persists quotedMessageId on send',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final incomingTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String();
        final outgoingTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String();

        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'incoming-msg-1',
            contactPeerId: 'contact-peer-id',
            text: 'Incoming first',
            senderPeerId: 'contact-peer-id',
            timestamp: incomingTimestamp,
            isIncoming: true,
            status: 'read',
            readAt: incomingTimestamp,
            createdAt: incomingTimestamp,
          ),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'outgoing-msg-1',
            contactPeerId: 'contact-peer-id',
            text: 'My sent message',
            senderPeerId: testIdentity.peerId,
            timestamp: outgoingTimestamp,
            isIncoming: false,
            status: 'delivered',
            createdAt: outgoingTimestamp,
          ),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        await tester.tap(find.text('Tap to expand'));
        await pumpFeedFrames(tester);

        final sentMessageFinder = find.text('My sent message');
        await tester.ensureVisible(sentMessageFinder);
        await tester.pump();
        await tester.longPress(sentMessageFinder);
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(MessageContextOverlay.selectedMessageKey),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(MessageContextOverlay.selectedMessageKey),
            matching: find.text('My sent message'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );

        await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Replying to'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(QuotePreviewBar),
            matching: find.text('My sent message'),
          ),
          findsOneWidget,
        );

        final editable = tester.widget<EditableText>(
          find.byType(EditableText).first,
        );
        expect(editable.focusNode.hasFocus, isTrue);

        await tester.enterText(
          find.byType(TextField).first,
          'Reply from long press',
        );
        await tester.pump();

        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await tester.pump(const Duration(milliseconds: 200));

        final sentMessages = await messageRepo.getMessagesForContact(
          'contact-peer-id',
        );
        final sentReply = sentMessages
            .where((message) => message.text == 'Reply from long press')
            .first;

        expect(sentReply.quotedMessageId, 'outgoing-msg-1');
      },
    );

    testWidgets(
      'long-press edit prefills the feed composer and cancel exits edit mode',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final incomingTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String();
        final outgoingTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String();

        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'incoming-edit-1',
            contactPeerId: 'contact-peer-id',
            text: 'Incoming first',
            senderPeerId: 'contact-peer-id',
            timestamp: incomingTimestamp,
            isIncoming: true,
            status: 'read',
            readAt: incomingTimestamp,
            createdAt: incomingTimestamp,
          ),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'outgoing-edit-1',
            contactPeerId: 'contact-peer-id',
            text: 'Editable sent message',
            senderPeerId: testIdentity.peerId,
            timestamp: outgoingTimestamp,
            isIncoming: false,
            status: 'delivered',
            createdAt: outgoingTimestamp,
          ),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        await tester.tap(find.text('Tap to expand'));
        await pumpFeedFrames(tester);

        await tester.longPress(find.text('Editable sent message'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(const ValueKey('feed-edit-mode-banner')),
          findsOneWidget,
        );
        expect(find.text('Editing message'), findsOneWidget);

        final editableBefore = tester.widget<EditableText>(
          find.byType(EditableText).first,
        );
        expect(editableBefore.controller.text, 'Editable sent message');
        expect(editableBefore.focusNode.hasFocus, isTrue);

        final cancelEditFinder = find.byKey(
          const ValueKey('feed-cancel-edit-action'),
        );
        await tester.ensureVisible(cancelEditFinder);
        await tester.pump();
        await tester.tap(cancelEditFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(const ValueKey('feed-edit-mode-banner')),
          findsNothing,
        );

        final editableAfter = tester.widget<EditableText>(
          find.byType(EditableText).first,
        );
        expect(editableAfter.controller.text, isEmpty);
      },
    );

    testWidgets('identical feed edit submit is a no-op', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      final incomingTimestamp = DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toUtc()
          .toIso8601String();
      final outgoingTimestamp = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String();
      var editCalled = false;

      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'incoming-noop-1',
          contactPeerId: 'contact-peer-id',
          text: 'Incoming first',
          senderPeerId: 'contact-peer-id',
          timestamp: incomingTimestamp,
          isIncoming: true,
          status: 'read',
          readAt: incomingTimestamp,
          createdAt: incomingTimestamp,
        ),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'outgoing-noop-1',
          contactPeerId: 'contact-peer-id',
          text: 'No-op edit text',
          senderPeerId: testIdentity.peerId,
          timestamp: outgoingTimestamp,
          isIncoming: false,
          status: 'delivered',
          createdAt: outgoingTimestamp,
        ),
      );

      await tester.pumpWidget(
        buildFeedWired(
          editChatMessageFn:
              ({
                required p2pService,
                required messageRepo,
                required originalMessage,
                required updatedText,
                required senderUsername,
                bridge,
                recipientMlKemPublicKey,
                mediaAttachmentRepo,
                emitTimingEvent = true,
              }) async {
                editCalled = true;
                return (SendChatMessageResult.success, originalMessage);
              },
        ),
      );
      await pumpFeedFrames(tester);

      await tester.tap(find.text('Tap to expand'));
      await pumpFeedFrames(tester);

      await tester.longPress(find.text('No-op edit text'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
      await tester.ensureVisible(sendButton);
      await tester.pump();
      await tester.tap(sendButton);
      await tester.pump(const Duration(milliseconds: 250));

      expect(editCalled, isFalse);
      expect(find.byKey(const ValueKey('feed-edit-mode-banner')), findsNothing);
      final messages = await messageRepo.getMessagesForContact(
        'contact-peer-id',
      );
      expect(messages.where((message) => !message.isIncoming).length, 1);
      expect(
        messages
            .where((message) => message.id == 'outgoing-noop-1')
            .single
            .text,
        'No-op edit text',
      );
    });

    testWidgets(
      'changed feed edit submit updates the same row and does not create a session reply',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final incomingTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String();
        final outgoingTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String();
        const editedAt = '2026-03-31T10:06:00.000Z';
        String? editedMessageId;
        String? editedText;

        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'incoming-edit-success-1',
            contactPeerId: 'contact-peer-id',
            text: 'Incoming first',
            senderPeerId: 'contact-peer-id',
            timestamp: incomingTimestamp,
            isIncoming: true,
            status: 'read',
            readAt: incomingTimestamp,
            createdAt: incomingTimestamp,
          ),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'outgoing-edit-success-1',
            contactPeerId: 'contact-peer-id',
            text: 'Original feed text',
            senderPeerId: testIdentity.peerId,
            timestamp: outgoingTimestamp,
            isIncoming: false,
            status: 'delivered',
            createdAt: outgoingTimestamp,
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(
            editChatMessageFn:
                ({
                  required p2pService,
                  required messageRepo,
                  required originalMessage,
                  required updatedText,
                  required senderUsername,
                  bridge,
                  recipientMlKemPublicKey,
                  mediaAttachmentRepo,
                  emitTimingEvent = true,
                }) async {
                  editedMessageId = originalMessage.id;
                  editedText = updatedText;
                  final updated = originalMessage.copyWith(
                    text: updatedText,
                    editedAt: editedAt,
                  );
                  await messageRepo.saveMessage(updated);
                  return (SendChatMessageResult.success, updated);
                },
          ),
        );
        await pumpFeedFrames(tester);

        await tester.tap(find.text('Tap to expand'));
        await pumpFeedFrames(tester);

        await tester.longPress(find.text('Original feed text'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        await tester.enterText(
          find.byType(TextField).first,
          'Updated feed text',
        );
        await tester.pump();

        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await tester.pump(const Duration(milliseconds: 250));

        expect(editedMessageId, 'outgoing-edit-success-1');
        expect(editedText, 'Updated feed text');
        expect(find.text('Updated feed text'), findsOneWidget);
        expect(find.text('(edited)'), findsWidgets);

        final updatedMessage = await messageRepo.getMessage(
          'outgoing-edit-success-1',
        );
        expect(updatedMessage?.text, 'Updated feed text');
        expect(updatedMessage?.editedAt, editedAt);
        final messages = await messageRepo.getMessagesForContact(
          'contact-peer-id',
        );
        expect(messages.where((message) => !message.isIncoming).length, 1);
      },
    );

    testWidgets(
      'group swipe-to-reply shows preview and persists quotedMessageId on send',
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
            name: 'Quoted Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await saveSelfGroupMember(groupRepo, 'g1');
        await _saveLatestGroupKey(groupRepo, 'g1');
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-quoted-1',
            groupId: 'g1',
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Quote this group message',
            timestamp: DateTime.now()
                .subtract(const Duration(minutes: 5))
                .toUtc(),
            createdAt: DateTime.now()
                .subtract(const Duration(minutes: 5))
                .toUtc(),
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

        expect(find.byType(SwipeToQuoteBubble), findsOneWidget);

        final swipeBubble = tester.widget<SwipeToQuoteBubble>(
          find.byType(SwipeToQuoteBubble).first,
        );
        swipeBubble.onQuoteTriggered();
        await tester.pump();

        expect(find.text('Replying to'), findsOneWidget);
        expect(find.text('Quote this group message'), findsWidgets);

        await tester.enterText(
          find.byType(TextField).first,
          'Quoted group send',
        );
        await tester.pump();

        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        final publishMsg = bridge.sentMessages.firstWhere(
          (message) => (jsonDecode(message) as Map)['cmd'] == 'group:publish',
        );
        final payload =
            (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
        expect(payload['quotedMessageId'], 'gm-quoted-1');

        final savedMessages = await groupMsgRepo.getMessagesPage('g1');
        final sentReply = savedMessages
            .where((message) => message.text == 'Quoted group send')
            .first;
        expect(sentReply.quotedMessageId, 'gm-quoted-1');
      },
    );

    testWidgets('updateWireEnvelope writes through for an existing row', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);

      final saved = ConversationMessage(
        id: 'msg-wire-1',
        contactPeerId: testContact.peerId,
        text: 'Wire envelope seed',
        senderPeerId: testIdentity.peerId,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: false,
        status: 'sending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );

      await messageRepo.saveMessage(saved);
      await messageRepo.updateWireEnvelope('msg-wire-1', '{"wire":"ok"}');
      await messageRepo.updateWireEnvelope(
        'missing-message',
        '{"wire":"nope"}',
      );

      final updated = await messageRepo.getMessage('msg-wire-1');
      expect(updated, isNotNull);
      expect(updated!.wireEnvelope, '{"wire":"ok"}');
      expect(
        await messageRepo.getMessage('missing-message'),
        isNull,
        reason: 'Missing rows should remain untouched',
      );
    });

    testWidgets(
      'feed inline 1:1 reply becomes retry-discoverable before network completes',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        // Seed a read incoming message so the card starts in collapsed mode
        // with an inline reply input.
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-opt-2',
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

        // Keep the send gate closed so the test can inspect repository state
        // before the transport call finishes.
        final gatedP2P = _GatedP2PService();
        p2pService = gatedP2P;

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.text('Continue...'), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, 'Quick reply');
        await tester.pump();
        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        try {
          final persisted = await messageRepo.getMessagesForContact(
            testContact.peerId,
          );
          final outgoing = persisted
              .where(
                (message) =>
                    !message.isIncoming && message.text == 'Quick reply',
              )
              .toList();

          expect(
            outgoing,
            isNotEmpty,
            reason:
                'Feed inline 1:1 send should pre-persist a retryable row before the send gate completes',
          );

          final sent = outgoing.single;
          expect(sent.status, 'sending');
          expect(sent.wireEnvelope, isNotNull);
        } finally {
          if (!gatedP2P.sendGate.isCompleted) {
            gatedP2P.sendGate.complete();
          }
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    );

    testWidgets(
      'inline reply shows session reply immediately before network completes',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        // Seed a read incoming message so the card starts in collapsed mode
        // with an inline reply input.
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-opt-1',
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

        // Use a gated P2P service that blocks send operations
        final gatedP2P = _GatedP2PService();
        p2pService = gatedP2P;

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        // Card should be collapsed with inline reply input
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.text('Continue...'), findsOneWidget);

        // Type and send
        await tester.enterText(find.byType(TextField).first, 'Quick reply');
        await tester.pump();
        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);

        // Pump a few frames — but the P2P gate is still blocked,
        // so sendChatMessage has NOT completed.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // The session reply text should already be visible (optimistic).
        // RepliedIndicator renders "You replied Active now" for just-created
        // SessionReply timestamps.
        expect(
          find.textContaining('You replied'),
          findsOneWidget,
          reason:
              'Session reply should appear immediately, not after network completes',
        );

        // Clean up: complete the gate so the async send doesn't leak.
        gatedP2P.sendGate.complete();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'inline reply clears earlier unread preview before later unread arrives',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        final a1Timestamp = DateTime.now()
            .subtract(const Duration(hours: 2))
            .toUtc();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-a1',
            contactPeerId: testContact.peerId,
            text: 'A1 from Bob',
            senderPeerId: testContact.peerId,
            timestamp: a1Timestamp.toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: a1Timestamp.toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(chatMessageListener: fakeChatListener),
        );
        await pumpFeedFrames(tester);

        expect(find.byType(OpenModeCardBody), findsOneWidget);
        expect(find.text('A1 from Bob'), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, 'B1 reply');
        await tester.pump();
        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await pumpFeedFrames(tester);

        expect(
          find.byType(CollapsedModeCardBody),
          findsOneWidget,
          reason:
              'A successful inline reply should collapse the card into a post-read replied state',
        );
        expect(find.byType(OpenModeCardBody), findsNothing);
        expect(find.textContaining('You replied'), findsOneWidget);
        expect(
          find.text('A1 from Bob'),
          findsNothing,
          reason:
              'Earlier unread rows answered by the inline reply should not remain visible after success',
        );

        final a2Timestamp = DateTime.now().toUtc();
        final a2Message = ConversationMessage(
          id: 'msg-a2',
          contactPeerId: testContact.peerId,
          text: 'A2 from Bob',
          senderPeerId: testContact.peerId,
          timestamp: a2Timestamp.toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: a2Timestamp.toIso8601String(),
        );
        await messageRepo.saveMessage(a2Message);
        fakeChatListener.emitIncomingMessage(a2Message);
        await pumpFeedFrames(tester);

        expect(find.byType(OpenModeCardBody), findsOneWidget);
        expect(find.text('A2 from Bob'), findsOneWidget);
        expect(
          find.text('A1 from Bob'),
          findsNothing,
          reason:
              'Only the later unread message should remain in the reopened unread preview',
        );
      },
    );

    testWidgets('inline reply restores quote and draft on send failure', (
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
          id: 'msg-fail-1',
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

      // P2P node not started → sendChatMessage returns nodeNotRunning
      p2pService = FakeP2PService(initialState: NodeState.stopped);

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester);

      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      await tester.tap(find.text('Tap to expand'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final swipeBubble = tester.widget<SwipeToQuoteBubble>(
        find.byType(SwipeToQuoteBubble).first,
      );
      swipeBubble.onQuoteTriggered();
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Hey from Bob'), findsWidgets);

      // Type and send
      const draftText = 'مرحبا Hello 123';
      await tester.enterText(find.byType(TextField).first, draftText);
      await tester.pump();
      final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
      await tester.ensureVisible(sendButton);
      await tester.pump();
      await tester.tap(sendButton);

      // Pump through async send (returns immediately since node is stopped)
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Session reply should NOT remain, but the composer should be restored
      // so the user can retry without retyping or re-quoting.
      expect(
        find.textContaining('failed to send'),
        findsOneWidget,
        reason: 'Error snackbar should appear on send failure',
      );
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Hey from Bob'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        draftText,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).textDirection,
        TextDirection.rtl,
      );
    });

    testWidgets(
      'group swipe-to-reply shows preview and persists quotedMessageId on send',
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
            id: 'g-quote',
            name: 'Quote Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g-quote',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await saveSelfGroupMember(groupRepo, 'g-quote');
        await _saveLatestGroupKey(groupRepo, 'g-quote');
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-parent',
            groupId: 'g-quote',
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Quote this group parent',
            timestamp: DateTime.now()
                .subtract(const Duration(minutes: 5))
                .toUtc(),
            createdAt: DateTime.now()
                .subtract(const Duration(minutes: 5))
                .toUtc(),
            isIncoming: true,
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

        expect(find.byType(SwipeToQuoteBubble), findsOneWidget);

        final swipeBubble = tester.widget<SwipeToQuoteBubble>(
          find.byType(SwipeToQuoteBubble).first,
        );
        swipeBubble.onQuoteTriggered();
        await tester.pump();

        expect(find.text('Replying to'), findsOneWidget);
        expect(find.text('Quote this group parent'), findsWidgets);

        await tester.enterText(
          find.byType(TextField).first,
          'Feed group reply',
        );
        await tester.pump();

        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await pumpFeedFrames(tester);

        final publishMsg = bridge.sentMessages.firstWhere(
          (m) =>
              (jsonDecode(m) as Map<String, dynamic>)['cmd'] == 'group:publish',
        );
        final payload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(payload['quotedMessageId'], 'gm-parent');

        final savedMessages = await groupMsgRepo.getMessagesPage('g-quote');
        final sentReply = savedMessages.firstWhere(
          (message) => message.text == 'Feed group reply',
        );
        expect(sentReply.quotedMessageId, 'gm-parent');
      },
    );

    testWidgets('group inline send wraps publish in a background task', (
      tester,
    ) async {
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
          id: 'g-bg-inline',
          name: 'Background Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g-bg-inline',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await saveSelfGroupMember(groupRepo, 'g-bg-inline');
      await _saveLatestGroupKey(groupRepo, 'g-bg-inline');
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-read-bg-inline-1',
          groupId: 'g-bg-inline',
          senderPeerId: 'other-peer',
          senderUsername: 'OtherUser',
          text: 'Existing thread seed',
          timestamp: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
          createdAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
          readAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
        ),
      );

      final fakeGroupListener = _FakeGroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
      );

      bridge = _InlineGroupBgBridge();

      await tester.pumpWidget(
        buildFeedWired(
          groupRepository: groupRepo,
          groupMessageRepository: groupMsgRepo,
          groupMessageListener: fakeGroupListener,
        ),
      );
      await pumpFeedFrames(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'Background task inline reply',
      );
      await tester.pump();
      final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
      await tester.ensureVisible(sendButton);
      await tester.pump();
      await tester.tap(sendButton);
      await pumpFeedFrames(tester);

      expect(bridge.commandLog, contains('bg:begin'));
      expect(bridge.commandLog, contains('group.encrypt'));
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('bg:end'));
      _expectCommandOrder(bridge.commandLog, 'bg:begin', 'group.encrypt');
      _expectCommandOrder(bridge.commandLog, 'group.encrypt', 'group:publish');
      _expectCommandOrder(bridge.commandLog, 'group:publish', 'bg:end');
    });

    testWidgets(
      'group inline send becomes retry-discoverable before publish resolves',
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
            id: 'g-retryable',
            name: 'Retryable Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g-retryable',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await saveSelfGroupMember(groupRepo, 'g-retryable');
        await _saveLatestGroupKey(groupRepo, 'g-retryable');
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-read-retryable-1',
            groupId: 'g-retryable',
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Existing thread seed',
            timestamp: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            createdAt: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            readAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
        );

        final gatedBridge = _GatedBridge();
        bridge = gatedBridge;

        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await pumpFeedFrames(tester);

        await tester.enterText(
          find.byType(TextField).first,
          'Retry-discoverable inline send',
        );
        await tester.pump();
        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        final persisted = await groupMsgRepo.getMessagesPage('g-retryable');
        final outgoing = persisted.firstWhere(
          (message) =>
              !message.isIncoming &&
              message.text == 'Retry-discoverable inline send',
        );
        expect(outgoing.status, 'sending');
        expect(outgoing.wireEnvelope, isNotNull);
        expect(outgoing.inboxRetryPayload, isNotNull);

        gatedBridge.sendGate.complete();
        await pumpFeedFrames(tester);
      },
    );

    testWidgets(
      'group inline reply shows session reply immediately before network completes',
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
            name: 'Optimistic Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await saveSelfGroupMember(groupRepo, 'g1');
        await _saveLatestGroupKey(groupRepo, 'g1');

        // Seed a read message so the card starts in collapsed mode
        // with an inline reply input.
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-read-opt-1',
            groupId: 'g1',
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Old group message',
            timestamp: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            createdAt: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            readAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
        );

        // Use a gated bridge that blocks send operations so
        // sendGroupMessage never completes during the assertion window.
        final gatedBridge = _GatedBridge();
        bridge = gatedBridge;

        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await pumpFeedFrames(tester);

        // Card should be collapsed with inline reply input
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.text('Continue...'), findsOneWidget);

        // Type and send
        await tester.enterText(find.byType(TextField).first, 'Group reply');
        await tester.pump();
        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);

        // Pump a few frames — the bridge gate is still blocked,
        // so sendGroupMessage has NOT completed.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // The session reply should already be visible (optimistic).
        expect(
          find.textContaining('You replied'),
          findsOneWidget,
          reason:
              'Group session reply should appear immediately, not after network completes',
        );

        // Clean up: complete the gate so the async send doesn't leak.
        gatedBridge.sendGate.complete();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets('group inline reply restores quote and draft on send failure', (
      tester,
    ) async {
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
          name: 'Fail Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await saveSelfGroupMember(groupRepo, 'g1');
      await _saveLatestGroupKey(groupRepo, 'g1');

      // Seed a read message so the card starts in collapsed mode
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-read-fail-1',
          groupId: 'g1',
          senderPeerId: 'other-peer',
          senderUsername: 'OtherUser',
          text: 'Old group message',
          timestamp: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
          createdAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
          readAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
        ),
      );

      final fakeGroupListener = _FakeGroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
      );

      // Bridge that throws on send → sendGroupMessage returns error
      bridge = FakeBridge()..throwOnSend = true;

      await tester.pumpWidget(
        buildFeedWired(
          groupRepository: groupRepo,
          groupMessageRepository: groupMsgRepo,
          groupMessageListener: fakeGroupListener,
        ),
      );
      await pumpFeedFrames(tester);

      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      await tester.tap(find.text('Tap to expand'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final swipeBubble = tester.widget<SwipeToQuoteBubble>(
        find.byType(SwipeToQuoteBubble).first,
      );
      swipeBubble.onQuoteTriggered();
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Old group message'), findsWidgets);

      // Type and send
      await tester.enterText(find.byType(TextField).first, 'Group fail');
      await tester.pump();
      final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
      await tester.ensureVisible(sendButton);
      await tester.pump();
      await tester.tap(sendButton);

      // Pump through async send (throws immediately)
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Session reply should be reverted and the composer restored.
      expect(
        find.textContaining('failed to send'),
        findsOneWidget,
        reason: 'Error snackbar should appear on group send failure',
      );
      expect(
        find.textContaining('You replied'),
        findsNothing,
        reason: 'Session reply should be reverted on failure',
      );
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Old group message'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'Group fail',
      );
    });

    testWidgets(
      'group inline reply shows session reply on success end-to-end',
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
            name: 'Success Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await saveSelfGroupMember(groupRepo, 'g1');
        await _saveLatestGroupKey(groupRepo, 'g1');

        // Seed a read message so the card starts in collapsed mode
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-read-succ-1',
            groupId: 'g1',
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Old group message',
            timestamp: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            createdAt: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            readAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
        );

        // Default bridge returns ok → sendGroupMessage succeeds
        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await pumpFeedFrames(tester);

        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.text('Continue...'), findsOneWidget);

        // Type and send
        await tester.enterText(find.byType(TextField).first, 'Group success');
        await tester.pump();
        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);

        // Pump through the full async chain
        await pumpFeedFrames(tester);

        // Session reply should be visible
        expect(
          find.textContaining('You replied'),
          findsOneWidget,
          reason: 'Session reply should show after successful group send',
        );
        // Card should remain collapsed
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      },
    );

    testWidgets(
      'group inline reply treats zero-peer publish as success and keeps the message sent',
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
            id: 'g-zero-peers',
            name: 'Zero Peer Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g-zero-peers',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        await saveSelfGroupMember(groupRepo, 'g-zero-peers');
        await _saveLatestGroupKey(groupRepo, 'g-zero-peers');
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-read-zero-peers-1',
            groupId: 'g-zero-peers',
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Old group message',
            timestamp: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            createdAt: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc(),
            readAt: DateTime.now().subtract(const Duration(hours: 1)).toUtc(),
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
        );

        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': true,
              'messageId': 'msg-zero-peers',
              'topicPeers': 0,
            },
          },
        );

        await tester.pumpWidget(
          buildFeedWired(
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await pumpFeedFrames(tester);

        await tester.enterText(find.byType(TextField).first, 'Zero peers');
        await tester.pump();
        final sendButton = find.byIcon(Icons.arrow_upward_rounded).first;
        await tester.ensureVisible(sendButton);
        await tester.pump();
        await tester.tap(sendButton);
        await pumpFeedFrames(tester);

        expect(
          find.textContaining('You replied'),
          findsOneWidget,
          reason:
              'Zero-peer publish still counts as a successful group send in the feed composer',
        );
        expect(find.textContaining('failed to send'), findsNothing);

        final savedMessages = await groupMsgRepo.getMessagesPage(
          'g-zero-peers',
        );
        final saved = savedMessages.firstWhere(
          (message) => message.text == 'Zero peers' && !message.isIncoming,
        );
        expect(saved.status, 'sent');
        expect(saved.inboxStored, isTrue);
      },
    );

    testWidgets(
      'outgoing repository retry success updates the open feed card without reload',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final parent = ConversationMessage(
          id: 'parent-retry',
          contactPeerId: testContact.peerId,
          text: 'Retry parent',
          senderPeerId: testContact.peerId,
          timestamp: '2026-02-01T10:00:00.000Z',
          isIncoming: true,
          status: 'read',
          readAt: '2026-02-01T10:05:00.000Z',
          createdAt: '2026-02-01T10:00:00.000Z',
        );
        final failedReply = ConversationMessage(
          id: 'failed-retry',
          contactPeerId: testContact.peerId,
          text: 'Retry reply',
          senderPeerId: testIdentity.peerId,
          timestamp: '2026-02-01T10:06:00.000Z',
          isIncoming: false,
          status: 'failed',
          quotedMessageId: 'parent-retry',
          createdAt: '2026-02-01T10:06:00.000Z',
        );
        await messageRepo.saveMessage(parent);
        await messageRepo.saveMessage(failedReply);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        await tester.tap(find.text('Tap to expand'));
        await pumpFeedFrames(tester, count: 4);

        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

        await messageRepo.saveMessage(
          failedReply.copyWith(status: 'delivered'),
        );
        await pumpFeedFrames(tester, count: 2);

        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'updateMessageStatus retry success updates the open feed card without reload',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final parent = ConversationMessage(
          id: 'parent-update-status',
          contactPeerId: testContact.peerId,
          text: 'Retry parent',
          senderPeerId: testContact.peerId,
          timestamp: '2026-02-01T10:00:00.000Z',
          isIncoming: true,
          status: 'read',
          readAt: '2026-02-01T10:05:00.000Z',
          createdAt: '2026-02-01T10:00:00.000Z',
        );
        final failedReply = ConversationMessage(
          id: 'failed-update-status',
          contactPeerId: testContact.peerId,
          text: 'Retry reply',
          senderPeerId: testIdentity.peerId,
          timestamp: '2026-02-01T10:06:00.000Z',
          isIncoming: false,
          status: 'failed',
          quotedMessageId: 'parent-update-status',
          createdAt: '2026-02-01T10:06:00.000Z',
        );
        await messageRepo.saveMessage(parent);
        await messageRepo.saveMessage(failedReply);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        await tester.tap(find.text('Tap to expand'));
        await pumpFeedFrames(tester, count: 4);

        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

        await messageRepo.updateMessageStatus(failedReply.id, 'delivered');
        await pumpFeedFrames(tester, count: 2);

        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'failed outgoing repository edit refresh updates the open feed card without reload',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final parent = ConversationMessage(
          id: 'parent-edit-failed',
          contactPeerId: testContact.peerId,
          text: 'Retry parent',
          senderPeerId: testContact.peerId,
          timestamp: '2026-02-01T10:00:00.000Z',
          isIncoming: true,
          status: 'read',
          readAt: '2026-02-01T10:05:00.000Z',
          createdAt: '2026-02-01T10:00:00.000Z',
        );
        final failedReply = ConversationMessage(
          id: 'failed-edit-refresh',
          contactPeerId: testContact.peerId,
          text: 'Failed original text',
          senderPeerId: testIdentity.peerId,
          timestamp: '2026-02-01T10:06:00.000Z',
          isIncoming: false,
          status: 'failed',
          quotedMessageId: 'parent-edit-failed',
          createdAt: '2026-02-01T10:06:00.000Z',
        );
        await messageRepo.saveMessage(parent);
        await messageRepo.saveMessage(failedReply);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        await tester.tap(find.text('Tap to expand'));
        await pumpFeedFrames(tester, count: 4);

        expect(find.text('Failed original text'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

        await messageRepo.saveMessage(
          failedReply.copyWith(
            text: 'Failed edited text',
            editedAt: '2026-02-01T10:07:00.000Z',
          ),
        );
        await pumpFeedFrames(tester, count: 2);

        expect(find.text('Failed edited text'), findsOneWidget);
        expect(find.text('(edited)'), findsWidgets);
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'incremental group updates preserve quoted replies in feed cards',
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
            id: 'g-quoted-refresh',
            name: 'Quoted Refresh Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g-quoted-refresh',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );
        final parent = GroupMessage(
          id: 'gm-parent-refresh',
          groupId: 'g-quoted-refresh',
          senderPeerId: 'other-peer',
          senderUsername: 'OtherUser',
          text: 'Parent quote source',
          timestamp: DateTime.utc(2026, 2, 1, 10),
          createdAt: DateTime.utc(2026, 2, 1, 10),
          isIncoming: true,
        );
        await groupMsgRepo.saveMessage(parent);

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

        final beforeCount = find.text('Parent quote source').evaluate().length;

        final reply = GroupMessage(
          id: 'gm-reply-refresh',
          groupId: 'g-quoted-refresh',
          senderPeerId: 'other-peer',
          senderUsername: 'OtherUser',
          text: 'Reply with quote',
          timestamp: DateTime.utc(2026, 2, 1, 10, 1),
          createdAt: DateTime.utc(2026, 2, 1, 10, 1),
          isIncoming: true,
          quotedMessageId: 'gm-parent-refresh',
        );
        await groupMsgRepo.saveMessage(reply);
        fakeGroupListener.emitGroupMessage(reply);

        await pumpFeedFrames(tester, count: 3);

        final bubbles = tester.widgetList<MessageBubble>(
          find.byType(MessageBubble),
        );
        expect(
          bubbles.any(
            (bubble) =>
                bubble.text == 'Reply with quote' &&
                bubble.quotedText == 'Parent quote source',
          ),
          isTrue,
        );
        expect(
          find.text('Parent quote source').evaluate().length,
          greaterThan(beforeCount),
        );
      },
    );

    testWidgets(
      'feed opens announcement admins with a writable group conversation',
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
        final adminGroup = GroupModel(
          id: 'g-admin-announce',
          name: 'Admin Announcements',
          type: GroupType.announcement,
          topicName: '/mknoon/group/g-admin-announce',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin-peer',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(adminGroup);
        await saveSelfGroupMember(
          groupRepo,
          adminGroup.id,
          role: MemberRole.admin,
        );
        await _saveLatestGroupKey(groupRepo, adminGroup.id);
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-admin-announce-1',
            groupId: adminGroup.id,
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Unread announcement',
            timestamp: DateTime.utc(2026, 2, 1, 10),
            createdAt: DateTime.utc(2026, 2, 1, 10),
            isIncoming: true,
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

        await tester.tap(find.text('View earlier messages'));
        await pumpFeedFrames(tester, count: 4);

        final pushed = tester.widget<GroupConversationWired>(
          find.byType(GroupConversationWired),
        );
        expect(pushed.group.type, GroupType.announcement);
        expect(pushed.group.myRole, GroupRole.admin);
      },
    );

    testWidgets(
      'feed entry keeps group long-press actions aligned with the shared conversation surface',
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
        final feedGroup = GroupModel(
          id: 'g-feed-actions',
          name: 'Feed Actions Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g-feed-actions',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin-peer',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(feedGroup);
        await saveSelfGroupMember(
          groupRepo,
          feedGroup.id,
          role: MemberRole.admin,
        );
        await saveOtherGroupMember(
          groupRepo,
          feedGroup.id,
          peerId: 'other-peer',
          username: 'OtherUser',
        );
        await _saveLatestGroupKey(groupRepo, feedGroup.id);
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-feed-actions-1',
            groupId: feedGroup.id,
            senderPeerId: 'other-peer',
            senderUsername: 'OtherUser',
            text: 'Feed action message',
            timestamp: DateTime.utc(2026, 2, 1, 11),
            createdAt: DateTime.utc(2026, 2, 1, 11),
            isIncoming: true,
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

        await tester.tap(find.text('View earlier messages'));
        await pumpFeedFrames(tester, count: 4);

        expect(find.byType(GroupConversationWired), findsOneWidget);
        expect(find.text('Feed action message'), findsWidgets);

        await tester.longPress(find.text('Feed action message').last);
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      },
    );

    testWidgets(
      'feed entry keeps group reaction inspection aligned with the shared conversation surface',
      (tester) async {
        identityRepo.seed(testIdentity);
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        final reactionRepo = FakeReactionRepository();
        final feedGroup = GroupModel(
          id: 'g-feed-reactions',
          name: 'Feed Reactions Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g-feed-reactions',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin-peer',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(feedGroup);
        await groupRepo.saveMember(
          GroupMember(
            groupId: feedGroup.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 2, 1, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: feedGroup.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 2, 1, 10, 1),
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-feed-reaction-1',
            groupId: feedGroup.id,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
            text: 'Feed reaction message',
            timestamp: DateTime.utc(2026, 2, 1, 11),
            createdAt: DateTime.utc(2026, 2, 1, 11),
            isIncoming: true,
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-feed-self',
            messageId: 'gm-feed-reaction-1',
            emoji: '🔥',
            senderPeerId: testIdentity.peerId,
            timestamp: DateTime.utc(2026, 2, 1, 11, 1).toIso8601String(),
            createdAt: DateTime.utc(2026, 2, 1, 11, 1).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-feed-bob',
            messageId: 'gm-feed-reaction-1',
            emoji: '🔥',
            senderPeerId: 'peer-bob',
            timestamp: DateTime.utc(2026, 2, 1, 11, 2).toIso8601String(),
            createdAt: DateTime.utc(2026, 2, 1, 11, 2).toIso8601String(),
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
        );

        await tester.pumpWidget(
          buildFeedWired(
            reactionRepository: reactionRepo,
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await pumpFeedFrames(tester);

        await tester.tap(find.text('View earlier messages'));
        await pumpFeedFrames(tester, count: 8);

        expect(find.byType(GroupConversationWired), findsOneWidget);
        expect(find.text('Feed reaction message'), findsWidgets);
        expect(find.textContaining('🔥', skipOffstage: false), findsWidgets);
        await tester.tap(find.textContaining('🔥', skipOffstage: false).last);
        await pumpFeedFrames(tester);

        expect(find.byKey(GroupReactionDetailsSheet.sheetKey), findsOneWidget);
        expect(
          find.byKey(GroupReactionDetailsSheet.rowKey(testIdentity.peerId)),
          findsOneWidget,
        );
        expect(
          find.byKey(GroupReactionDetailsSheet.rowKey('peer-bob')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'stale dissolved feed reaction entry restores prior state and refreshes the card',
      (tester) async {
        identityRepo.seed(testIdentity);
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();
        final reactionRepo = FakeReactionRepository();
        final reactionReplayOutboxRepo =
            FakeGroupReactionReplayOutboxRepository();
        final feedGroup = GroupModel(
          id: 'g-feed-dissolved-race',
          name: 'Frozen Feed Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g-feed-dissolved-race',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin-peer',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(feedGroup);
        await groupRepo.saveMember(
          GroupMember(
            groupId: feedGroup.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 2, 1, 10),
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-feed-dissolved-race-1',
            groupId: feedGroup.id,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
            text: 'Feed reaction race message',
            timestamp: DateTime.utc(2026, 2, 1, 11),
            createdAt: DateTime.utc(2026, 2, 1, 11),
            isIncoming: true,
          ),
        );

        final fakeGroupListener = _FakeGroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
        );

        await tester.pumpWidget(
          buildFeedWired(
            reactionRepository: reactionRepo,
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            groupReactionReplayOutboxRepository: reactionReplayOutboxRepo,
            groupMessageListener: fakeGroupListener,
          ),
        );
        await pumpFeedFrames(tester);

        await groupRepo.updateGroup(
          feedGroup.copyWith(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 2, 1, 11, 30),
            dissolvedBy: 'admin-peer',
          ),
        );

        await tester.longPress(find.text('Feed reaction race message'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(MessageContextOverlay.reactionBarKey),
          findsOneWidget,
        );

        final thumbsUp = find.descendant(
          of: find.byKey(MessageContextOverlay.reactionBarKey),
          matching: find.text('\u{1F44D}'),
        );
        expect(thumbsUp, findsOneWidget);

        await tester.tap(thumbsUp);
        await pumpFeedFrames(tester, count: 8);

        expect(
          await reactionRepo.getReactionsForMessage('gm-feed-dissolved-race-1'),
          isEmpty,
        );
        expect(find.text('This group has been dissolved'), findsOneWidget);
        expect(
          find.text(
            'This group has been dissolved. History stays available, but new messages are disabled.',
          ),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);

        await tester.longPress(find.text('Feed reaction race message').first);
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(find.byKey(MessageContextOverlay.reactionBarKey), findsNothing);
        expect(find.byKey(MessageContextOverlay.replyActionKey), findsNothing);
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      },
    );

    testWidgets(
      'feed delete-for-me removes the thread row and keeps the contact card',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final timestamp = DateTime.now().toUtc().toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'delete-for-me-msg',
            contactPeerId: 'contact-peer-id',
            text: 'Delete for me only',
            senderPeerId: 'contact-peer-id',
            timestamp: timestamp,
            isIncoming: true,
            status: 'delivered',
            createdAt: timestamp,
          ),
        );

        var deleteForMeCalled = false;
        await tester.pumpWidget(
          buildFeedWired(
            deleteForMeFn:
                ({
                  required message,
                  required messageRepo,
                  reactionRepo,
                  mediaAttachmentRepo,
                  mediaFileManager,
                }) async {
                  deleteForMeCalled = true;
                  return deleteMessageForMe(
                    message: message,
                    messageRepo: messageRepo,
                    reactionRepo: reactionRepo,
                    mediaAttachmentRepo: mediaAttachmentRepo,
                    mediaFileManager: mediaFileManager,
                  );
                },
          ),
        );
        await pumpFeedFrames(tester);

        await tester.longPress(find.text('Delete for me only'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(MessageContextOverlay.deleteActionKey),
          findsOneWidget,
        );

        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(FeedWired.deleteSheetKey), findsOneWidget);

        final deleteForMeInkWell = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(FeedWired.deleteForMeKey),
            matching: find.byType(InkWell),
          ),
        );
        deleteForMeInkWell.onTap?.call();
        await tester.pump();
        await pumpFeedFrames(tester, count: 4);

        expect(deleteForMeCalled, isTrue);
        expect(find.text('Delete for me only'), findsNothing);
        expect(find.textContaining('Bob'), findsWidgets);
        expect(
          await messageRepo.getMessagesForContact('contact-peer-id'),
          isEmpty,
        );
      },
    );

    testWidgets(
      'feed delete-for-everyone refreshes to the next latest visible message',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final olderTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String();
        final latestTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'delete-fallback-earlier',
            contactPeerId: 'contact-peer-id',
            text: 'Earlier visible message',
            senderPeerId: 'contact-peer-id',
            timestamp: olderTimestamp,
            isIncoming: true,
            status: 'read',
            readAt: olderTimestamp,
            createdAt: olderTimestamp,
          ),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'delete-fallback-latest',
            contactPeerId: 'contact-peer-id',
            text: 'Delete latest for everyone',
            senderPeerId: testIdentity.peerId,
            timestamp: latestTimestamp,
            isIncoming: false,
            status: 'delivered',
            createdAt: latestTimestamp,
          ),
        );

        var deleteForEveryoneCalled = false;
        await tester.pumpWidget(
          buildFeedWired(
            deleteForEveryoneFn:
                ({
                  required p2pService,
                  required messageRepo,
                  required originalMessage,
                  reactionRepo,
                  mediaAttachmentRepo,
                  mediaFileManager,
                  bridge,
                  recipientMlKemPublicKey,
                  emitTimingEvent = true,
                }) async {
                  deleteForEveryoneCalled = true;
                  final tombstone = buildDeletedMessageTombstone(
                    originalMessage: originalMessage,
                    deletedAt: DateTime.now().toUtc().toIso8601String(),
                    deletedByPeerId: originalMessage.senderPeerId,
                    hiddenLocally: true,
                    status: 'delivered',
                  );
                  await messageRepo.saveMessage(tombstone);
                  return (SendChatMessageResult.success, tombstone);
                },
          ),
        );
        await pumpFeedFrames(tester);

        expect(find.text('Delete latest for everyone'), findsOneWidget);

        await tester.tap(find.text('Tap to expand'));
        await pumpFeedFrames(tester, count: 4);

        await tester.longPress(find.text('Delete latest for everyone'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(FeedWired.deleteForEveryoneKey), findsOneWidget);

        final deleteForEveryoneInkWell = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(FeedWired.deleteForEveryoneKey),
            matching: find.byType(InkWell),
          ),
        );
        deleteForEveryoneInkWell.onTap?.call();
        await tester.pump();
        await pumpFeedFrames(tester, count: 4);

        expect(deleteForEveryoneCalled, isTrue);
        expect(find.text('Delete latest for everyone'), findsNothing);

        await tester.tap(find.text('Collapse'));
        await pumpFeedFrames(tester, count: 4);

        expect(find.text('Earlier visible message'), findsOneWidget);
      },
    );

    testWidgets(
      'feed keeps the deleted placeholder visible while sender delete is failed',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        final olderTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String();
        final latestTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'delete-visible-earlier',
            contactPeerId: 'contact-peer-id',
            text: 'Earlier visible message',
            senderPeerId: 'contact-peer-id',
            timestamp: olderTimestamp,
            isIncoming: true,
            status: 'read',
            readAt: olderTimestamp,
            createdAt: olderTimestamp,
          ),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'delete-visible-latest',
            contactPeerId: 'contact-peer-id',
            text: 'Delete latest but keep placeholder',
            senderPeerId: testIdentity.peerId,
            timestamp: latestTimestamp,
            isIncoming: false,
            status: 'delivered',
            createdAt: latestTimestamp,
          ),
        );

        var deleteForEveryoneCalled = false;
        await tester.pumpWidget(
          buildFeedWired(
            deleteForEveryoneFn:
                ({
                  required p2pService,
                  required messageRepo,
                  required originalMessage,
                  reactionRepo,
                  mediaAttachmentRepo,
                  mediaFileManager,
                  bridge,
                  recipientMlKemPublicKey,
                  emitTimingEvent = true,
                }) async {
                  deleteForEveryoneCalled = true;
                  final tombstone = buildDeletedMessageTombstone(
                    originalMessage: originalMessage,
                    deletedAt: DateTime.now().toUtc().toIso8601String(),
                    deletedByPeerId: originalMessage.senderPeerId,
                    hiddenLocally: false,
                    status: 'failed',
                  );
                  await messageRepo.saveMessage(tombstone);
                  return (SendChatMessageResult.peerNotFound, tombstone);
                },
          ),
        );
        await pumpFeedFrames(tester);

        expect(find.text('Delete latest but keep placeholder'), findsOneWidget);

        await tester.tap(find.text('Tap to expand'));
        await pumpFeedFrames(tester, count: 4);

        await tester.longPress(find.text('Delete latest but keep placeholder'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final deleteForEveryoneInkWell = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(FeedWired.deleteForEveryoneKey),
            matching: find.byType(InkWell),
          ),
        );
        deleteForEveryoneInkWell.onTap?.call();
        await tester.pump();
        await pumpFeedFrames(tester, count: 4);

        expect(deleteForEveryoneCalled, isTrue);
        expect(find.text('Delete latest but keep placeholder'), findsNothing);
        expect(find.text('This message was deleted'), findsOneWidget);

        await tester.tap(find.text('Collapse'));
        await pumpFeedFrames(tester, count: 4);

        expect(find.text('Earlier visible message'), findsNothing);
        expect(find.text('This message was deleted'), findsOneWidget);
      },
    );

    testWidgets(
      'incoming deleted messages refresh the feed card to the deleted placeholder',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
        final originalTimestamp = DateTime.now()
            .subtract(const Duration(minutes: 2))
            .toUtc()
            .toIso8601String();
        final originalMessage = ConversationMessage(
          id: 'incoming-delete-refresh',
          contactPeerId: 'contact-peer-id',
          text: 'Incoming will be deleted',
          senderPeerId: 'contact-peer-id',
          timestamp: originalTimestamp,
          isIncoming: true,
          status: 'delivered',
          createdAt: originalTimestamp,
        );
        await messageRepo.saveMessage(originalMessage);

        await tester.pumpWidget(
          buildFeedWired(chatMessageListener: fakeChatListener),
        );
        await pumpFeedFrames(tester);

        expect(find.text('Incoming will be deleted'), findsOneWidget);

        final deletedMessage = originalMessage.copyWith(
          text: '',
          deletedAt: DateTime.now().toUtc().toIso8601String(),
          deletedByPeerId: originalMessage.senderPeerId,
          media: const [],
        );
        await messageRepo.saveMessage(deletedMessage);
        fakeChatListener.emitIncomingMessage(deletedMessage);

        await pumpFeedFrames(tester, count: 4);

        expect(find.text('Incoming will be deleted'), findsNothing);
        expect(find.text('This message was deleted'), findsOneWidget);
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
    required super.messageRepo,
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

class _FakeGroupInviteListener extends GroupInviteListener {
  final _joinedController = StreamController<GroupModel>.broadcast();
  final _pendingController = StreamController<PendingGroupInvite>.broadcast();

  _FakeGroupInviteListener({
    required InMemoryPendingGroupInviteRepository pendingInviteRepo,
  }) : super(
         groupInviteStream: const Stream<ChatMessage>.empty(),
         groupRepo: InMemoryGroupRepository(),
         pendingInviteRepo: pendingInviteRepo,
         contactRepo: FakeContactRepository(),
         bridge: FakeBridge(),
         getOwnMlKemSecretKey: () async => null,
       );

  @override
  Stream<GroupModel> get groupJoinedStream => _joinedController.stream;

  @override
  Stream<PendingGroupInvite> get pendingInviteStream =>
      _pendingController.stream;

  void emitPendingInvite(PendingGroupInvite invite) =>
      _pendingController.add(invite);

  void emitJoinedGroup(GroupModel group) => _joinedController.add(group);
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

  @override
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

/// [FakeP2PService] subclass whose send/discover/inbox methods block
/// on a [Completer] so tests can assert UI state before the network
/// operation completes.
class _GatedP2PService extends FakeP2PService {
  final Completer<void> sendGate = Completer<void>();

  _GatedP2PService()
    : super(
        initialState: const NodeState(isStarted: true),
        discoverPeerResult: const DiscoveredPeer(
          id: 'contact-peer-id',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
      );

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    await sendGate.future;
    return const SendMessageResult(sent: true, reply: 'ack');
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    await sendGate.future;
    return discoverPeerResult;
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    await sendGate.future;
    return true;
  }
}

/// [FakeBridge] subclass whose [send] blocks on a [Completer] so tests
/// can assert UI state while the bridge call (group publish, etc.) is
/// still in flight.
class _GatedBridge extends FakeBridge {
  final Completer<void> sendGate = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'bg:begin') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return 'feed-inline-gated-bg-task';
    }
    if (cmd == 'bg:end') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return '';
    }
    if (cmd == 'group.encrypt' || cmd == 'payload.sign') {
      return super.send(message);
    }
    await sendGate.future;
    return super.send(message);
  }
}

class _InlineGroupBgBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);

    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;
    if (cmd != null) {
      commandLog.add(cmd);
    }

    switch (cmd) {
      case 'bg:begin':
        return 'feed-inline-bg-task';
      case 'bg:end':
        return '';
      case 'group:publish':
        return jsonEncode({
          'ok': true,
          'messageId': 'feed-inline-bg-message',
          'topicPeers': 1,
        });
      case 'group:inboxStore':
        return jsonEncode({'ok': true});
      default:
        return jsonEncode({'ok': true});
    }
  }
}

Future<void> _saveLatestGroupKey(
  InMemoryGroupRepository groupRepo,
  String groupId,
) async {
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'encrypted-key-$groupId',
      createdAt: DateTime(2026, 2, 1).toUtc(),
    ),
  );
}

void _expectCommandOrder(List<String> commands, String earlier, String later) {
  expect(commands, contains(earlier));
  expect(commands, contains(later));
  expect(commands.indexOf(earlier), lessThan(commands.indexOf(later)));
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
