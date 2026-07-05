import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart'
    show ConversationWired;
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
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
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
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
    // 214: this suite ARRANGES feed-first behavior (swipe/scroll/bg cases
    // start on the Feed pane); the orbit-as-home default is locked elsewhere.
    appShellController = AppShellController(initialTab: AppShellTab.feed);
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
    InMemoryFeedClearedRepository? feedClearedRepository,
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
        feedClearedRepository:
            feedClearedRepository ?? InMemoryFeedClearedRepository(),
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
      'opens Settings from the orbit center avatar and reflects background '
      'change on Feed',
      (tester) async {
        // 206 B row 15 (PROD-CRITICAL full chain): FeedWired → embedded
        // OrbitWired → center avatar → SettingsWired → shared-controller
        // background propagation back onto the Feed. Replaces the old
        // Feed-header-avatar entry (that avatar is removed).
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        expect(find.byType(CosmicBackground), findsNothing);

        // Mount + reveal the embedded orbit host, then open Settings from its
        // center self-avatar.
        appShellController.switchTo('orbit');
        await pumpFeedFrames(tester, count: 10);

        await tester.tap(
          find.byKey(const ValueKey('orbit-center-self-avatar')),
        );
        await pumpFeedFrames(tester, count: 10);

        expect(find.text('Settings'), findsOneWidget);
        // 209: the background options live behind the row's focused sheet.
        await tester.tap(
          find.byKey(const ValueKey('settings-row-background')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find.byKey(const ValueKey('background-choice-cosmic')),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          await secureKeyStore.read(BackgroundPreference.storageKey),
          BackgroundPreference.cosmic.toStorageString(),
        );

        await tester.tap(find.byIcon(Icons.chevron_left));
        await pumpFeedFrames(tester, count: 10);

        appShellController.switchTo('feed');
        await pumpFeedFrames(tester, count: 10);

        expect(find.byType(FeedScreen), findsOneWidget);
        // Scope to the Feed pane: the embedded orbit host stays mounted and also
        // renders a CosmicBackground, so an unscoped finder would see two.
        expect(
          find.descendant(
            of: find.byType(FeedScreen),
            matching: find.byType(CosmicBackground),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('TC-206-19 identity change-kind reloads Feed username',
        (tester) async {
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 8);
      expect(find.text('@Alice'), findsOneWidget);

      // Change the username in the repo, then fire the identity change-kind —
      // the Feed reloads identity without any Settings-return `.then`.
      identityRepo.seed(IdentityModel(
        peerId: testIdentity.peerId,
        publicKey: testIdentity.publicKey,
        privateKey: testIdentity.privateKey,
        mnemonic12: testIdentity.mnemonic12,
        username: 'Bob',
        createdAt: testIdentity.createdAt,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      appShellController.notifyIdentityChanged();
      await pumpFeedFrames(tester, count: 4);

      expect(find.text('@Bob'), findsOneWidget);
    });

    testWidgets('TC-206-20 mediaQuality change-kind reloads quality prefs',
        (tester) async {
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 8);

      // Persist NEW image + video quality, then fire the mediaQuality kind.
      await saveImageQualityPreference(
        secureKeyStore: secureKeyStore,
        preference: ImageQualityPreference.original,
      );
      await saveVideoQualityPreference(
        secureKeyStore: secureKeyStore,
        preference: ImageQualityPreference.original,
      );
      appShellController.notifyMediaQualityChanged();
      await pumpFeedFrames(tester, count: 4);

      // Open a 1:1 conversation via the Feed's own callback: the reloaded prefs
      // must be CARRIED INTO the ConversationWired push (not just the keystore).
      final feedScreen = tester.widget<FeedScreen>(find.byType(FeedScreen));
      feedScreen.onOpenFullConversation!(testContact.peerId);
      await pumpFeedFrames(tester, count: 6);

      final conversation =
          tester.widget<ConversationWired>(find.byType(ConversationWired));
      expect(conversation.qualityPreference, ImageQualityPreference.original);
      expect(
        conversation.videoQualityPreference,
        ImageQualityPreference.original,
      );
    });

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

      // 134-P7: the loaded-empty state is now the caught-up card.
      expect(find.text("You're all caught up"), findsOneWidget);
      expect(find.textContaining('Your feed is ready'), findsNothing);
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
      'B2: Orbit badge counts only not-already-joined pending invites (parity with the list filter)',
      (tester) async {
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        // Invite for an already-joined group → must NOT count.
        await pendingInviteRepo.savePendingInvite(
          makePendingInvite(groupId: 'grp-joined'),
        );
        // Invite for a not-yet-joined group → counts.
        await pendingInviteRepo.savePendingInvite(
          makePendingInvite(groupId: 'grp-fresh'),
        );
        final fakeGroupInviteListener = _FakeGroupInviteListener(
          pendingInviteRepo: pendingInviteRepo,
        );

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(
          GroupModel(
            id: 'grp-joined',
            name: 'Joined Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/grp-joined',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(
            groupInviteListener: fakeGroupInviteListener,
            groupRepository: groupRepo,
          ),
        );
        await pumpFeedFrames(tester, count: 8);

        // Two invites in the repo, but one group is already joined → badge = 1.
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
      'orbit re-entry resets to the Inner-Circle view (search state does not survive)',
      (tester) async {
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

        // Reach the all-chats view, open search, and filter to Bob.
        await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
        await pumpFeedFrames(tester, count: 4);
        await tester.tap(find.byType(OrbitSearchTrigger));
        await pumpFeedFrames(tester, count: 4);
        await tester.enterText(orbitSearchField(), 'Bo');
        await pumpFeedFrames(tester, count: 4);
        expect(orbitScopedText('Bob'), findsWidgets);
        expect(orbitScopedText('Cara'), findsNothing);

        // Leave to Feed and re-enter Orbit → the inline-tab rising edge resets
        // the view to Inner-Circle. This is the ONLY path that proves the reset
        // fires on the latched host (initState alone cannot cover it). The
        // search state does NOT survive.
        await tester.tap(orbitFeedNavLabel());
        await pumpFeedFrames(tester, count: 10);
        await tester.tap(feedOrbitNavLabel());
        await pumpFeedFrames(tester, count: 10);

        expect(find.byType(OrbitalVisualization), findsOneWidget);
        expect(orbitSearchField(), findsNothing);
        expect(orbitScopedText('Bob'), findsNothing);
      },
    );

    testWidgets('orbit nav tap lands on the Inner-Circle view', (tester) async {
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-orbit-nav-1',
          contactPeerId: testContact.peerId,
          text: 'Bob orbit message',
          senderPeerId: testContact.peerId,
          timestamp: '2026-02-01T10:00:00.000Z',
          isIncoming: true,
          status: 'delivered',
          createdAt: '2026-02-01T10:00:00.000Z',
        ),
      );

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 10);

      await tester.tap(feedOrbitNavLabel());
      await pumpFeedFrames(tester, count: 10);

      // The shell entry lands on the Inner-Circle view: the visualization is
      // shown and no all-chats list/search affordance is present.
      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byType(OrbitSearchTrigger), findsNothing);
      expect(orbitScopedText('Bob'), findsNothing);
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

      // Reach the all-chats list where Bob's row lives.
      await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
      await pumpFeedFrames(tester, count: 4);

      final orbitBobFinder = orbitScopedText('Bob').first;
      await tester.ensureVisible(orbitBobFinder);
      await tester.pump();
      await tester.drag(orbitBobFinder, const Offset(-230, 0));
      await pumpFeedFrames(tester, count: 6);

      expect(appShellController.activeTab, 'orbit');
      expect(find.byType(OrbitWired), findsOneWidget);
    });

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

    // 141: belt-and-suspenders for the notif-open inbox-drain race. When Feed
    // becomes the active home (incl. the Android cold-tap path that lands on
    // Feed), it must request ONE opportunistic offline-inbox drain — idempotent
    // (one per mount, not per frame), never zero.
    testWidgets(
      'requests an opportunistic inbox drain on first-ready / '
      'notification-handled',
      (tester) async {
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        expect(
          p2pService.drainOfflineInboxCallCount,
          1,
          reason: 'Feed becoming the active home must request exactly one '
              'opportunistic offline-inbox drain',
        );

        // Idempotent: further frames must not re-drain (not per-frame).
        await pumpFeedFrames(tester, count: 8);
        expect(
          p2pService.drainOfflineInboxCallCount,
          1,
          reason: 'the opportunistic drain is one-shot, not per-rebuild',
        );
      },
    );

    // ── 160: feed N+1 → batched-summary preview + bounded per-event refresh ──

    testWidgets(
      'TC-160-08: delete refreshes via the bounded paged read, never the '
      'unbounded getMessagesForContact',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final ts = DateTime.now().toUtc().toIso8601String();
        final outgoing = ConversationMessage(
          id: 'out-1',
          contactPeerId: 'contact-peer-id',
          text: 'my message',
          senderPeerId: 'me-peer',
          timestamp: ts,
          isIncoming: false,
          status: 'sent',
          createdAt: ts,
        );
        await messageRepo.saveMessage(outgoing);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        messageRepo.resetSpyCounters();
        // Soft-delete the outgoing → fires a repo-change → bounded refresh.
        await messageRepo.saveMessage(
          outgoing.copyWith(
            deletedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        await pumpFeedFrames(tester);

        expect(messageRepo.getMessagesForContactCallCount, 0);
        final pages = messageRepo.getMessagesPageCalls
            .where((c) => c.$1 == 'contact-peer-id')
            .toList();
        expect(pages, isNotEmpty);
        expect(pages.every((c) => c.$2 > 1), isTrue); // bounded, never limit-1
      },
    );

    testWidgets(
      'TC-160-21: an all-read contact WITH history loads 0 messages and its '
      '"new connection" letter stays suppressed; a brand-new contact still '
      'shows its letter',
      (tester) async {
        identityRepo.seed(testIdentity);
        ContactModel mk(String peerId, String name) => ContactModel(
          peerId: peerId,
          publicKey: 'pk-$peerId',
          rendezvous: '/dns4/relay/tcp/443',
          username: name,
          signature: 'sig',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
        );
        contactRepo.seed([mk('peer-history', 'Historic'), mk('peer-new', 'Newbie')]);
        // History contact: a single READ incoming (all-read prior history).
        final ts = DateTime.now().toUtc().toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'h1',
            contactPeerId: 'peer-history',
            text: 'old hi',
            senderPeerId: 'peer-history',
            timestamp: ts,
            isIncoming: true,
            status: 'delivered',
            createdAt: ts,
            readAt: ts,
          ),
        );

        messageRepo.resetSpyCounters();
        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        // All-read contact loaded ZERO messages.
        expect(
          messageRepo.getMessagesPageCalls.where((c) => c.$1 == 'peer-history'),
          isEmpty,
        );
        expect(messageRepo.getMessagesForContactCallCount, 0);
        // Exactly ONE "tap to say hi" letter renders. Two active contacts, but
        // only the brand-new (no-history) contact shows its connection letter;
        // the all-read-with-history contact is suppressed. (If suppression
        // regressed, BOTH would render → findsNWidgets(2).)
        expect(find.text('tap to say hi'), findsOneWidget);
      },
    );

    testWidgets(
      'TC-160-05: feed reaction fan-out on mount is bounded to the preview '
      'window, not the full decrypted history',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final reactionRepo = FakeReactionRepository();
        // Deep thread: 20 read (older) + 5 unread (newest). Window ≈ 8.
        final base = DateTime.utc(2026, 3, 1, 8);
        for (var i = 0; i < 25; i++) {
          final ts = base.add(Duration(minutes: i)).toIso8601String();
          await messageRepo.saveMessage(
            ConversationMessage(
              id: 'm$i',
              contactPeerId: 'contact-peer-id',
              text: 'm$i',
              senderPeerId: 'contact-peer-id',
              timestamp: ts,
              isIncoming: true,
              status: 'delivered',
              createdAt: ts,
              readAt: i < 20 ? ts : null,
            ),
          );
        }

        await tester.pumpWidget(
          buildFeedWired(reactionRepository: reactionRepo),
        );
        await pumpFeedFrames(tester);

        final loadedIds = reactionRepo.getReactionsForMessagesCalls
            .expand((c) => c)
            .toSet();
        // The mount reaction load carries only the windowed ids, not all 25.
        expect(loadedIds.length, lessThan(25));
        expect(loadedIds.contains('m24'), isTrue); // newest is in the window
        expect(loadedIds.contains('m0'), isFalse); // oldest read is off-window
      },
    );

    testWidgets(
      'TC-160-11: a just-drained (notif) incoming message stays visible as the '
      'latest message after a bounded refresh — the snapshot caps newest-first, '
      'not oldest-first (131/141/145 preservation)',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final base = DateTime.utc(2026, 3, 1, 8);
        // A deep thread PAST the 50-message snapshot page so the cap DIRECTION
        // decides which messages survive a bounded refresh: 54 older READ
        // incoming (m0..m53) + 1 OUTGOING (the bounded-refresh trigger).
        for (var i = 0; i < 54; i++) {
          final ts = base.add(Duration(minutes: i)).toIso8601String();
          await messageRepo.saveMessage(
            ConversationMessage(
              id: 'm$i',
              contactPeerId: 'contact-peer-id',
              text: 'm$i',
              senderPeerId: 'contact-peer-id',
              timestamp: ts,
              isIncoming: true,
              status: 'delivered',
              createdAt: ts,
              readAt: ts,
            ),
          );
        }
        final outTs = base.add(const Duration(minutes: 54)).toIso8601String();
        final outgoing = ConversationMessage(
          id: 'out-old',
          contactPeerId: 'contact-peer-id',
          text: 'my old reply',
          senderPeerId: 'me-peer',
          timestamp: outTs,
          isIncoming: false,
          status: 'sent',
          createdAt: outTs,
        );
        await messageRepo.saveMessage(outgoing);
        // The just-drained message: the NEWEST incoming, still UNREAD (as a
        // relay-inbox drain persists it), so the thread is pending and renders.
        final drainedTs =
            base.add(const Duration(minutes: 100)).toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'drained-newest',
            contactPeerId: 'contact-peer-id',
            text: 'drained newest',
            senderPeerId: 'contact-peer-id',
            timestamp: drainedTs,
            isIncoming: true,
            status: 'delivered',
            createdAt: drainedTs,
          ),
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        // Trigger a BOUNDED refresh: a soft-delete of the OUTGOING message fires
        // a destructive repo-change (the repo-change listener processes outgoing
        // edits) → the coalescer escalates to a bounded _refreshContactFeedItem
        // (loadContactFeedSnapshot → getMessagesPage, pageSize 50), re-deriving
        // the window newest-first from the repo.
        messageRepo.resetSpyCounters();
        await messageRepo.saveMessage(
          outgoing.copyWith(deletedAt: DateTime.utc(2026, 3, 2).toIso8601String()),
        );
        await pumpFeedFrames(tester);

        // The bounded snapshot path ran (never the unbounded full load).
        expect(messageRepo.getMessagesForContactCallCount, 0);
        expect(
          messageRepo.getMessagesPageCalls.where(
            (c) => c.$1 == 'contact-peer-id',
          ),
          isNotEmpty,
        );

        // Read the LIVE projected thread (the listenable, not the stale prop).
        final thread = tester
            .widget<FeedScreen>(find.byType(FeedScreen))
            .feedItemsListenable!
            .value
            .whereType<ThreadFeedItem>()
            .singleWhere((i) => i.contactPeerId == 'contact-peer-id');

        // Newest-first cap: the just-drained message is the latest rendered, it
        // survives inside the loaded window, and the OLDEST message was evicted
        // by the bound. An oldest-first (ASC + limit) cap would invert all three
        // (drained falls off the window, m0 stays) → RED.
        expect(thread.latestMessage.id, 'drained-newest');
        expect(thread.messages.any((m) => m.id == 'drained-newest'), isTrue);
        expect(thread.messages.every((m) => m.id != 'm0'), isTrue);
      },
    );

    group('161 group feed batched windowing', () {
      GroupModel grp(String id, String name) => GroupModel(
            id: id,
            name: name,
            type: GroupType.chat,
            topicName: '/mknoon/group/$id',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
          );

      Future<void> seedDeepGroup(
        InMemoryGroupMessageRepository repo,
        String groupId, {
        required int read,
        required int unread,
      }) async {
        final base = DateTime.utc(2026, 3, 1, 8);
        var minute = 0;
        for (var i = 0; i < read; i++) {
          final ts = base.add(Duration(minutes: minute++));
          await repo.saveMessage(GroupMessage(
            id: '$groupId-r$i',
            groupId: groupId,
            senderPeerId: 'p1',
            text: 'read $i',
            timestamp: ts,
            createdAt: ts,
            isIncoming: true,
            readAt: ts,
          ));
        }
        for (var i = 0; i < unread; i++) {
          final ts = base.add(Duration(minutes: minute++));
          await repo.saveMessage(GroupMessage(
            id: '$groupId-u$i',
            groupId: groupId,
            senderPeerId: 'p1',
            text: 'unread $i',
            timestamp: ts,
            createdAt: ts,
            isIncoming: true,
          ));
        }
      }

      GroupThreadFeedItem groupItemFor(WidgetTester tester, String groupId) {
        // Read the LIVE projected list (FeedScreen renders from the listenable;
        // the `feedItems` prop is a stale snapshot from the last FeedWired build).
        final feedScreen = tester.widget<FeedScreen>(find.byType(FeedScreen));
        final items = feedScreen.feedItemsListenable!.value;
        return items
            .whereType<GroupThreadFeedItem>()
            .singleWhere((i) => i.groupId == groupId);
      }

      testWidgets(
        'TC-161-07: collapsed group card is built from the windowed preview on '
        'mount (batched summary, no limit:200 full-page load)',
        (tester) async {
          identityRepo.seed(testIdentity);
          final groupRepo = InMemoryGroupRepository()..saveGroup(grp('g1', 'Deep Group'));
          final groupMsgRepo = InMemoryGroupMessageRepository();
          await seedDeepGroup(groupMsgRepo, 'g1', read: 30, unread: 5);

          await tester.pumpWidget(
            buildFeedWired(
              groupRepository: groupRepo,
              groupMessageRepository: groupMsgRepo,
            ),
          );
          await pumpFeedFrames(tester);

          // Batched preview used; never the unbounded 200-row per-group load.
          expect(groupMsgRepo.getGroupThreadPreviewsCallCount,
              greaterThanOrEqualTo(1));
          expect(
            groupMsgRepo.getMessagesPageCallLog.where((c) => c.$2 >= 200),
            isEmpty,
          );

          final item = groupItemFor(tester, 'g1');
          expect(item.unreadCount, 5);
          expect(item.totalMessageCount, 35); // from the summary
          expect(item.messages.length, lessThan(35)); // windowed slice
          expect(item.hasEarlierHistory, isTrue);
        },
      );

      testWidgets(
        'TC-161-08: group windowing does NOT leak group message ids into the '
        'contact reaction fan-out',
        (tester) async {
          identityRepo.seed(testIdentity);
          contactRepo.seed([testContact]);
          final base = DateTime.utc(2026, 3, 1, 9);
          for (var i = 0; i < 3; i++) {
            final ts = base.add(Duration(minutes: i)).toIso8601String();
            await messageRepo.saveMessage(ConversationMessage(
              id: 'cm$i',
              contactPeerId: 'contact-peer-id',
              text: 'cm$i',
              senderPeerId: 'contact-peer-id',
              timestamp: ts,
              isIncoming: true,
              status: 'delivered',
              createdAt: ts,
            ));
          }
          final reactionRepo = FakeReactionRepository();
          final groupRepo = InMemoryGroupRepository()..saveGroup(grp('g1', 'Grp'));
          final groupMsgRepo = InMemoryGroupMessageRepository();
          await seedDeepGroup(groupMsgRepo, 'g1', read: 0, unread: 4);

          await tester.pumpWidget(
            buildFeedWired(
              reactionRepository: reactionRepo,
              groupRepository: groupRepo,
              groupMessageRepository: groupMsgRepo,
            ),
          );
          await pumpFeedFrames(tester);

          final loadedIds = reactionRepo.getReactionsForMessagesCalls
              .expand((c) => c)
              .toSet();
          // Contact ids loaded; group ids never enter the contact fan-out.
          expect(loadedIds.contains('cm0'), isTrue);
          expect(loadedIds.any((id) => id.startsWith('g1-')), isFalse);
        },
      );

      testWidgets(
        'TC-161-13: a live group message keeps the summary-sourced totalMessageCount '
        '(+1 on a new id), no drift to the windowed slice length',
        (tester) async {
          identityRepo.seed(testIdentity);
          final groupRepo = InMemoryGroupRepository()..saveGroup(grp('g1', 'Live Group'));
          final groupMsgRepo = InMemoryGroupMessageRepository();
          await seedDeepGroup(groupMsgRepo, 'g1', read: 30, unread: 5);
          final listener = _FakeGroupMessageListener(
            groupRepo: groupRepo,
            msgRepo: groupMsgRepo,
          );

          await tester.pumpWidget(
            buildFeedWired(
              groupRepository: groupRepo,
              groupMessageRepository: groupMsgRepo,
              groupMessageListener: listener,
            ),
          );
          await pumpFeedFrames(tester);

          final before = groupItemFor(tester, 'g1');
          expect(before.totalMessageCount, 35);
          expect(before.hasEarlierHistory, isTrue);

          // Deliver a brand-new live incoming group message.
          final liveTs = DateTime.utc(2026, 3, 1, 12);
          final live = GroupMessage(
            id: 'g1-live',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'live!',
            timestamp: liveTs,
            createdAt: liveTs,
            isIncoming: true,
          );
          await groupMsgRepo.saveMessage(live);
          listener.emit(live);
          await pumpFeedFrames(tester);

          final after = groupItemFor(tester, 'g1');
          // Carried summary total + 1 on the new id — NOT re-derived from the
          // windowed list length (which would collapse "View earlier").
          expect(after.totalMessageCount, 36);
          expect(after.unreadCount, 6);
          expect(after.hasEarlierHistory, isTrue);
        },
      );
    });

  });

  // ── 162: feed reload debounce (per-contact coalescer with sticky escalation) ─
  group('162 feed reload debounce', () {
    // Reads the LIVE projected thread for a contact (FeedScreen renders from the
    // listenable; the `feedItems` prop is a stale last-build snapshot).
    ThreadFeedItem? threadFor(WidgetTester tester, String contactPeerId) {
      final feedScreen = tester.widget<FeedScreen>(find.byType(FeedScreen));
      final items = feedScreen.feedItemsListenable!.value;
      final matches = items
          .whereType<ThreadFeedItem>()
          .where((t) => t.contactPeerId == contactPeerId)
          .toList();
      return matches.isEmpty ? null : matches.single;
    }

    // Delivers all synchronously-queued stream events to the listeners (enqueue +
    // arm the coalescer timer), fires the timer once, then drains the async flush.
    Future<void> settleCoalesce(WidgetTester tester) async {
      await tester.pump(); // deliver queued broadcast events → enqueue + arm
      await tester.pump(const Duration(milliseconds: 100)); // fire the window
      await tester.pump(); // drain the async flush
    }

    ConversationMessage outgoing(
      String id,
      String peerId, {
      String status = 'sent',
      String text = 'msg',
      String? timestamp,
      String? deletedAt,
      String? hiddenAt,
    }) {
      final ts = timestamp ?? DateTime.now().toUtc().toIso8601String();
      return ConversationMessage(
        id: id,
        contactPeerId: peerId,
        text: text,
        senderPeerId: 'me-peer',
        timestamp: ts,
        isIncoming: false,
        status: status,
        createdAt: ts,
        deletedAt: deletedAt,
        hiddenAt: hiddenAt,
      );
    }

    // An UNREAD incoming message keeps the contact's thread PENDING so the
    // pending projection (FeedStore._buildItems → projectPendingFeed) keeps it
    // in `feedItemsListenable`. It must be the NEWEST message (a thread is
    // "answered" — and dropped — if any outgoing is newer than the newest unread
    // incoming), so the default sits after the 08:xx outgoing burst timestamps.
    ConversationMessage unreadIncoming(
      String id,
      String peerId, {
      String text = 'incoming',
      String? timestamp,
    }) {
      final ts = timestamp ?? DateTime.utc(2026, 3, 1, 9, 0).toIso8601String();
      return ConversationMessage(
        id: id,
        contactPeerId: peerId,
        text: text,
        senderPeerId: peerId,
        timestamp: ts,
        isIncoming: true,
        status: 'delivered',
        createdAt: ts,
      );
    }

    final contactB = ContactModel(
      peerId: 'peer-B',
      publicKey: 'pk-peer-B',
      rendezvous: '/dns4/relay/tcp/443',
      username: 'Carol',
      signature: 'sig',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'mlkem-peer-B',
    );

    testWidgets(
      'TC-162-04: a burst of N same-contact repo-change events coalesces into '
      'ONE feed materialization pass (debounce)',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        contactRepo.resetGetContactCounts();

        // 5 rapid same-id outgoing status flips for the SAME contact.
        for (final status in ['sent', 'delivered', 'sent', 'delivered', 'delivered']) {
          messageRepo.debugEmitMessageChange(
            outgoing('out-1', testContact.peerId, status: status),
          );
        }
        await settleCoalesce(tester);

        // One effective materialization, not five.
        expect(contactRepo.getContactCallsByPeerId[testContact.peerId], 1);
      },
    );

    testWidgets(
      'TC-162-05a: debounce flushes once per contact, last-write-wins '
      '(same-id status flip)',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        // Unread incoming keeps the thread pending so it stays in the projection.
        await messageRepo.saveMessage(
          unreadIncoming('in-a', testContact.peerId),
        );
        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        contactRepo.resetGetContactCounts();

        const lwwTs = '2026-03-01T08:00:00.000Z'; // older than the 09:00 incoming
        messageRepo.debugEmitMessageChange(
          outgoing('lww-1', testContact.peerId,
              status: 'sent', text: 'first', timestamp: lwwTs),
        );
        messageRepo.debugEmitMessageChange(
          outgoing('lww-1', testContact.peerId,
              status: 'delivered', text: 'latest', timestamp: lwwTs),
        );
        await settleCoalesce(tester);

        expect(contactRepo.getContactCallsByPeerId[testContact.peerId], 1);
        final thread = threadFor(tester, testContact.peerId);
        expect(thread, isNotNull);
        final msg = thread!.messages.singleWhere((m) => m.id == 'lww-1');
        expect(msg.status, 'delivered'); // latest state wins
        expect(msg.text, 'latest');
      },
    );

    testWidgets(
      'TC-162-05b: delete(X)-then-send(Y) escalates to a full refresh; a HIDDEN '
      'tombstone X is dropped, Y survives (delete NOT swallowed)',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final tsX = DateTime.utc(2026, 3, 1, 8, 0).toIso8601String();
        final tsY = DateTime.utc(2026, 3, 1, 8, 1).toIso8601String();
        // X is a delivered delete-for-everyone → HIDDEN tombstone (hiddenAt set).
        final xTomb = outgoing(
          'X',
          testContact.peerId,
          status: 'delivered',
          text: '',
          timestamp: tsX,
          deletedAt: tsX,
          hiddenAt: tsX,
        );
        final ySent = outgoing(
          'Y',
          testContact.peerId,
          status: 'sent',
          text: 'after delete',
          timestamp: tsY,
        );
        // Unread incoming keeps the thread pending so it stays projected.
        await messageRepo.saveMessage(
          unreadIncoming('in-b', testContact.peerId),
        );
        await messageRepo.saveMessage(xTomb);
        await messageRepo.saveMessage(ySent);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        contactRepo.resetGetContactCounts();
        messageRepo.resetSpyCounters();

        // delete(X) THEN sent(Y) — delete is NOT the last event.
        messageRepo.debugEmitMessageChange(xTomb);
        messageRepo.debugEmitMessageChange(ySent);
        await settleCoalesce(tester);

        // One materialization for the contact.
        expect(contactRepo.getContactCallsByPeerId[testContact.peerId], 1);
        // The destructive escalation ran the FULL refresh (getMessagesPage),
        // NOT the incremental in-memory apply (which never reads the page).
        expect(
          messageRepo.getMessagesPageCalls.where((c) => c.$1 == testContact.peerId),
          isNotEmpty,
        );
        // Status-dependent post-state: the HIDDEN tombstone X is dropped; Y stays.
        final thread = threadFor(tester, testContact.peerId);
        expect(thread, isNotNull);
        final ids = thread!.messages.map((m) => m.id).toSet();
        expect(ids.contains('X'), isFalse);
        expect(ids.contains('Y'), isTrue);
      },
    );

    testWidgets(
      'TC-162-05b2: a NON-hidden delete tombstone (sent delete-for-everyone) is '
      'retained as a visible empty isDeleted row (not purged)',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final tsX = DateTime.utc(2026, 3, 1, 8, 0).toIso8601String();
        final tsY = DateTime.utc(2026, 3, 1, 8, 1).toIso8601String();
        // X is a SENT delete-for-everyone → NON-hidden tombstone (no hiddenAt).
        final xTomb = outgoing(
          'X',
          testContact.peerId,
          status: 'sent',
          text: '',
          timestamp: tsX,
          deletedAt: tsX,
        );
        final ySent = outgoing(
          'Y',
          testContact.peerId,
          status: 'sent',
          text: 'after delete',
          timestamp: tsY,
        );
        // Unread incoming keeps the thread pending so it stays projected.
        await messageRepo.saveMessage(
          unreadIncoming('in-b2', testContact.peerId),
        );
        await messageRepo.saveMessage(xTomb);
        await messageRepo.saveMessage(ySent);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        contactRepo.resetGetContactCounts();
        messageRepo.resetSpyCounters();

        messageRepo.debugEmitMessageChange(xTomb);
        messageRepo.debugEmitMessageChange(ySent);
        await settleCoalesce(tester);

        expect(contactRepo.getContactCallsByPeerId[testContact.peerId], 1);
        // The destructive escalation ran the FULL refresh (getMessagesPage).
        expect(
          messageRepo.getMessagesPageCalls.where((c) => c.$1 == testContact.peerId),
          isNotEmpty,
        );
        final thread = threadFor(tester, testContact.peerId);
        expect(thread, isNotNull);
        final x = thread!.messages.singleWhere((m) => m.id == 'X');
        expect(x.isDeleted, isTrue); // retained as an empty isDeleted tombstone
        expect(x.media, isEmpty);
        expect(thread.messages.any((m) => m.id == 'Y'), isTrue);
      },
    );

    testWidgets(
      'TC-162-05f: a same-id NON-hidden delete burst escalates to a full '
      'refresh via sawDestructive (no distinct-id co-trigger)',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final tsX = DateTime.utc(2026, 3, 1, 8, 0).toIso8601String();
        // Single id X, NON-hidden delete-for-everyone tombstone. sawDistinctIds
        // stays false (one id) and X is not hidden (no internal isHidden
        // escalation in `_applyIncomingContactMessageToFeed`), so ONLY
        // sawDestructive can drive the full-refresh escalation here.
        final xTomb = outgoing(
          'X',
          testContact.peerId,
          status: 'sent',
          text: '',
          timestamp: tsX,
          deletedAt: tsX,
        );
        await messageRepo.saveMessage(xTomb);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        contactRepo.resetGetContactCounts();
        messageRepo.resetSpyCounters();

        // Same delete emitted twice → coalesces to one flush; sawDestructive set.
        messageRepo.debugEmitMessageChange(xTomb);
        messageRepo.debugEmitMessageChange(xTomb);
        await settleCoalesce(tester);

        expect(contactRepo.getContactCallsByPeerId[testContact.peerId], 1);
        // sawDestructive forces the FULL refresh (getMessagesPage). Dropping it
        // would run the incremental apply, which never reads the page → RED.
        expect(
          messageRepo.getMessagesPageCalls.where((c) => c.$1 == testContact.peerId),
          isNotEmpty,
        );
      },
    );

    testWidgets(
      'TC-162-05c: the coalescer keys per contact — a burst spanning two '
      'contacts materializes BOTH (no global collapse)',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact, contactB]);
        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        contactRepo.resetGetContactCounts();

        // Two events per contact (so HEAD == 2 each → RED; fixed == 1 each).
        messageRepo.debugEmitMessageChange(
          outgoing('a-1', testContact.peerId, status: 'sent'),
        );
        messageRepo.debugEmitMessageChange(
          outgoing('b-1', contactB.peerId, status: 'sent'),
        );
        messageRepo.debugEmitMessageChange(
          outgoing('a-1', testContact.peerId, status: 'delivered'),
        );
        messageRepo.debugEmitMessageChange(
          outgoing('b-1', contactB.peerId, status: 'delivered'),
        );
        await settleCoalesce(tester);

        expect(contactRepo.getContactCallsByPeerId[testContact.peerId], 1);
        expect(contactRepo.getContactCallsByPeerId[contactB.peerId], 1);
      },
    );

    testWidgets(
      'TC-162-05d: a distinct-id NO-delete burst (sent(X) then sent(Y), X not '
      'pre-applied) escalates so BOTH X and Y survive',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final tsX = DateTime.utc(2026, 3, 1, 8, 0).toIso8601String();
        final tsY = DateTime.utc(2026, 3, 1, 8, 1).toIso8601String();
        final xMsg = outgoing('X', testContact.peerId, status: 'sent', text: 'X', timestamp: tsX);
        final yMsg = outgoing('Y', testContact.peerId, status: 'sent', text: 'Y', timestamp: tsY);
        // Unread incoming keeps the thread pending so it stays projected.
        await messageRepo.saveMessage(
          unreadIncoming('in-d', testContact.peerId),
        );
        await messageRepo.saveMessage(xMsg);
        await messageRepo.saveMessage(yMsg);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester);

        contactRepo.resetGetContactCounts();
        messageRepo.resetSpyCounters();

        messageRepo.debugEmitMessageChange(xMsg);
        messageRepo.debugEmitMessageChange(yMsg);
        await settleCoalesce(tester);

        expect(contactRepo.getContactCallsByPeerId[testContact.peerId], 1);
        // The discriminating lock: a distinct-id burst escalates to the FULL
        // refresh (getMessagesPage). A keep-latest draft that drops the sticky
        // `sawDistinctIds` would run the incremental apply(Y) instead — never
        // calling getMessagesPage — and X would silently vanish.
        expect(
          messageRepo.getMessagesPageCalls.where((c) => c.$1 == testContact.peerId),
          isNotEmpty,
        );
        final thread = threadFor(tester, testContact.peerId);
        expect(thread, isNotNull);
        final ids = thread!.messages.map((m) => m.id).toSet();
        expect(ids.containsAll({'X', 'Y'}), isTrue);
      },
    );

    testWidgets(
      'TC-162-05e: a mixed incoming(refresh=true)+outgoing(refresh=false) burst '
      'for the same contact still recomputes the unread count exactly once',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        final tsIn = DateTime.utc(2026, 3, 1, 8, 0).toIso8601String();
        final tsOut = DateTime.utc(2026, 3, 1, 8, 1).toIso8601String();
        final incoming = ConversationMessage(
          id: 'inc-1',
          contactPeerId: testContact.peerId,
          text: 'incoming',
          senderPeerId: testContact.peerId,
          timestamp: tsIn,
          isIncoming: true,
          status: 'delivered',
          createdAt: tsIn,
        );
        final outDelivered = outgoing(
          'out-1',
          testContact.peerId,
          status: 'delivered',
          timestamp: tsOut,
        );
        await messageRepo.saveMessage(incoming);
        await messageRepo.saveMessage(outDelivered);

        await tester.pumpWidget(
          buildFeedWired(chatMessageListener: fakeChatListener),
        );
        await pumpFeedFrames(tester);

        contactRepo.resetGetContactCounts();
        messageRepo.resetSpyCounters();

        // Same contact, ONE window: incoming via the chat stream (refresh=true)
        // + outgoing delivered via messageChanges (refresh=false).
        fakeChatListener.emitIncomingMessage(incoming);
        messageRepo.debugEmitMessageChange(outDelivered);
        await settleCoalesce(tester);

        // One materialization, and the unread recompute is NOT skipped.
        expect(contactRepo.getContactCallsByPeerId[testContact.peerId], 1);
        expect(
          messageRepo.getTotalUnreadCountExcludingArchivedCallCount,
          greaterThan(0),
        );
      },
    );

    testWidgets(
      'reading a conversation on another surface clears the Feed nav unread '
      'badge (repo read-event drives the total-unread recompute)',
      (tester) async {
        setPhoneViewport(tester);
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        final ts = DateTime.utc(2026, 3, 1, 8, 0).toIso8601String();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'unread-1',
            contactPeerId: testContact.peerId,
            text: 'unread hello',
            senderPeerId: testContact.peerId,
            timestamp: ts,
            isIncoming: true,
            status: 'delivered',
            createdAt: ts,
          ),
        );

        await tester.pumpWidget(
          buildFeedWired(chatMessageListener: fakeChatListener),
        );
        await pumpFeedFrames(tester);

        // The Feed nav button shows the aggregate unread.
        expect(navButton(tester, 'Feed').badgeCount, 1);

        // Read the conversation on ANOTHER surface (orbit avatar tap /
        // notification route): the same repo is marked read WITHOUT traversing
        // the feed's own leave-thread recompute. markConversationAsRead does NOT
        // emit on messageChanges, so only the read-event seam can catch this.
        await messageRepo.markConversationAsRead(testContact.peerId);
        await pumpFeedFrames(tester);

        expect(navButton(tester, 'Feed').badgeCount, 0);
      },
    );

    testWidgets(
      'TC-162-06 (PRESERVATION): a newly-arrived incoming message surfaces within '
      'one debounce window; the feed coalescer is independent of the 145/131 drain',
      (tester) async {
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        await tester.pumpWidget(
          buildFeedWired(chatMessageListener: fakeChatListener),
        );
        await pumpFeedFrames(tester);

        final ts = DateTime.utc(2026, 3, 1, 9, 0).toIso8601String();
        final incoming = ConversationMessage(
          id: 'fresh-1',
          contactPeerId: testContact.peerId,
          text: 'fresh arrival',
          senderPeerId: testContact.peerId,
          timestamp: ts,
          isIncoming: true,
          status: 'delivered',
          createdAt: ts,
        );
        fakeChatListener.emitIncomingMessage(incoming);
        await settleCoalesce(tester);

        // The message surfaces (not dropped / indefinitely deferred).
        final thread = threadFor(tester, testContact.peerId);
        expect(thread, isNotNull);
        expect(thread!.messages.any((m) => m.id == 'fresh-1'), isTrue);
        // Independence: the feed debounce never drives the notif-tap drain path.
        expect(
          events.map((e) => e['event']),
          isNot(contains('NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING')),
        );
      },
    );
  });

  group('163 shell rebuild minimization + off-screen pause', () {
    // Mounts OrbitWired (one-way latch) and returns to the Feed tab at rest, so
    // both panes are present in the swipe host with Feed active.
    Future<void> latchOrbitThenReturnToFeed(WidgetTester tester) async {
      appShellController.switchTo('orbit');
      await pumpFeedFrames(tester, count: 8);
      appShellController.switchTo('feed');
      await pumpFeedFrames(tester, count: 8);
    }

    testWidgets(
      'TC-163-02: a background-only change recolors the panes without re-running '
      'tab side-effects; a tab change still fires them',
      (tester) async {
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);
        await latchOrbitThenReturnToFeed(tester);
        // F8a: confirm the orbit host latched so a later miss is not mistaken
        // for a missing widget.
        expect(find.byType(OrbitWired), findsOneWidget);
        expect(appShellController.activeTab, 'feed');

        // Background-only change: the new preference must reach the panes
        // (recolor needs the rebuild under minimal scope) but must NOT switch
        // tabs / re-drive the host.
        appShellController.setBackgroundPreference(BackgroundPreference.cosmic);
        await pumpFeedFrames(tester, count: 4);
        expect(
          tester.widget<FeedScreen>(find.byType(FeedScreen)).backgroundPreference,
          BackgroundPreference.cosmic,
        );
        expect(appShellController.activeTab, 'feed');

        // Inverse (F8b): a TAB change still fires its side-effects (orbit shows,
        // tab flips) and preserves the recolor.
        appShellController.switchTo('orbit');
        await pumpFeedFrames(tester, count: 8);
        expect(appShellController.activeTab, 'orbit');
        expect(find.byType(OrbitWired), findsOneWidget);
        expect(
          tester.widget<FeedScreen>(find.byType(FeedScreen)).backgroundPreference,
          BackgroundPreference.cosmic,
        );
      },
    );

    testWidgets(
      'TC-163-03: each pane is isolated in its own keyed RepaintBoundary',
      (tester) async {
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);
        await latchOrbitThenReturnToFeed(tester);
        expect(find.byType(OrbitWired), findsOneWidget);

        expect(
          find.byKey(const ValueKey<String>('feed-pane-repaint-boundary')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('orbit-pane-repaint-boundary')),
          findsOneWidget,
        );
        // The boundary is an ancestor of each pane (it actually wraps it).
        expect(
          find.ancestor(
            of: find.byType(FeedScreen),
            matching: find.byKey(
              const ValueKey<String>('feed-pane-repaint-boundary'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.byType(OrbitWired),
            matching: find.byKey(
              const ValueKey<String>('orbit-pane-repaint-boundary'),
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'TC-163-04 (preservation): pane widget instances stay stable across a '
      'swipe frame (no re-allocation into the AnimatedBuilder)',
      (tester) async {
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);
        await latchOrbitThenReturnToFeed(tester);

        final feedBefore = tester.widget<FeedScreen>(find.byType(FeedScreen));
        final orbitBefore = tester.widget<OrbitWired>(find.byType(OrbitWired));

        // A partial drag drives the host AnimationController WITHOUT a build()
        // rebuild — the captured pane instances must remain identical.
        final gesture = await tester.startGesture(
          tester.getCenter(feedOrbitSwipeHost()),
        );
        await gesture.moveBy(const Offset(-70, 0));
        await tester.pump();

        expect(
          identical(
            feedBefore,
            tester.widget<FeedScreen>(find.byType(FeedScreen)),
          ),
          isTrue,
        );
        expect(
          identical(
            orbitBefore,
            tester.widget<OrbitWired>(find.byType(OrbitWired)),
          ),
          isTrue,
        );

        await gesture.up();
        await pumpFeedFrames(tester, count: 8);
      },
    );

    bool tickerEnabled(WidgetTester tester, String key) => tester
        .widget<TickerMode>(find.byKey(ValueKey<String>(key)))
        .enabled;

    testWidgets(
      'TC-163-08: the inactive Stack child is ticker-muted at rest, the active '
      'one enabled',
      (tester) async {
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);
        await latchOrbitThenReturnToFeed(tester);
        expect(find.byType(OrbitWired), findsOneWidget);
        expect(appShellController.activeTab, 'feed');

        // On Feed at rest: orbit (off-screen) muted, feed (on-screen) ticking.
        expect(tickerEnabled(tester, 'orbit-pane-ticker-mode'), isFalse);
        expect(tickerEnabled(tester, 'feed-pane-ticker-mode'), isTrue);
      },
    );

    testWidgets(
      'TC-163-09: mid-swipe BOTH panes stay ticker-enabled (drag AND snap-back); '
      'inactive muted at rest',
      (tester) async {
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);
        await latchOrbitThenReturnToFeed(tester);

        // clause 1 — drag in progress: BOTH enabled.
        final gesture = await tester.startGesture(
          tester.getCenter(feedOrbitSwipeHost()),
        );
        await gesture.moveBy(const Offset(-70, 0));
        await tester.pump();
        expect(tickerEnabled(tester, 'feed-pane-ticker-mode'), isTrue);
        expect(tickerEnabled(tester, 'orbit-pane-ticker-mode'), isTrue);

        // clause 2 — release → settle (240ms) animating: BOTH still enabled
        // mid-settle so the outgoing tab does not freeze.
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(tickerEnabled(tester, 'feed-pane-ticker-mode'), isTrue);
        expect(tickerEnabled(tester, 'orbit-pane-ticker-mode'), isTrue);

        // clause 3 — at rest: exactly one muted.
        await pumpFeedFrames(tester, count: 8);
        expect(
          tickerEnabled(tester, 'feed-pane-ticker-mode') !=
              tickerEnabled(tester, 'orbit-pane-ticker-mode'),
          isTrue,
        );
      },
    );

    testWidgets(
      '214: cold start on orbit applies off-screen pause to the feed pane',
      (tester) async {
        // Orbit-INITIAL mount (the 214 cold-start state): the hidden feed pane
        // must be ticker-muted from the FIRST resting frame, not only after a
        // feed→orbit round trip.
        setPhoneViewport(tester);
        suppressFeedNavErrors();
        identityRepo.seed(testIdentity);
        appShellController = AppShellController(
          initialTab: AppShellTab.orbit,
        );

        await tester.pumpWidget(buildFeedWired());
        await pumpFeedFrames(tester, count: 8);

        expect(appShellController.activeTab, AppShellTab.orbit);
        expect(find.byType(OrbitWired), findsOneWidget);
        expect(tickerEnabled(tester, 'orbit-pane-ticker-mode'), isTrue);
        expect(tickerEnabled(tester, 'feed-pane-ticker-mode'), isFalse);
      },
    );

    testWidgets('214: initial-orbit mount swipes back to feed', (
      tester,
    ) async {
      // The orbit exit action must be registered from an orbit-INITIAL mount
      // so the right swipe works from the first frame.
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      appShellController = AppShellController(initialTab: AppShellTab.orbit);

      await tester.pumpWidget(buildFeedWired());
      await pumpFeedFrames(tester, count: 8);
      expect(find.byType(OrbitWired), findsOneWidget);

      await tester.drag(feedOrbitSwipeHost(), const Offset(170, 0));
      await pumpFeedFrames(tester, count: 8);

      expect(appShellController.activeTab, AppShellTab.feed);
      expect(find.byType(FeedScreen), findsOneWidget);
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

/// Fake [GroupMessageListener] exposing a controllable [groupMessageStream] so
/// tests can drive the incremental live-message merge (161 TC-161-13).
class _FakeGroupMessageListener extends GroupMessageListener {
  _FakeGroupMessageListener({
    required super.groupRepo,
    required super.msgRepo,
  });

  final _messageController = StreamController<GroupMessage>.broadcast();

  @override
  Stream<GroupMessage> get groupMessageStream => _messageController.stream;

  void emit(GroupMessage message) => _messageController.add(message);
}
