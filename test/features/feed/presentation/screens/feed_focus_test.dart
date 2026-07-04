import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/feed/presentation/widgets/caught_up_empty_state.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_composer.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_one_to_one.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 134-P5 focus + shared composer tests (TC-19/19b/20/21/22/30). Mounts the
/// REAL FeedWired so focus state, the shared composer, append-stay sends, and
/// the never-silent retry affordance are exercised end-to-end (bounded pumps —
/// AmbientBackground.repeat() hangs pumpAndSettle).
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
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMsgRepo;
  late List<Map<String, dynamic>> flowEvents;

  final testIdentity = IdentityModel(
    peerId: 'me-peer',
    publicKey: 'me-pk',
    privateKey: 'me-sk',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Me',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  ContactModel contact(String peerId, String name) => ContactModel(
    peerId: peerId,
    publicKey: '$peerId-pk',
    rendezvous: '/dns4/relay/tcp/443',
    username: name,
    signature: 'sig',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: 'mlkem-$peerId',
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
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
    mediaFileManager = FakeMediaFileManager();
    groupRepo = InMemoryGroupRepository();
    groupMsgRepo = InMemoryGroupMessageRepository();
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
    flowEvents = [];
    debugSetFlowEventSink((payload) => flowEvents.add(payload));

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
    debugSetFlowEventSink(null);
    postRepository.dispose();
    postsPrivacySettingsRepository.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  Future<void> seedPendingThread(String peerId, String name, String body) async {
    final ts = DateTime.now().toUtc().toIso8601String();
    await messageRepo.saveMessage(
      ConversationMessage(
        id: 'in-$peerId',
        contactPeerId: peerId,
        text: body,
        senderPeerId: peerId,
        timestamp: ts,
        isIncoming: true,
        status: 'delivered',
        createdAt: ts,
      ),
    );
  }

  Widget buildWired({
    ChatMessageListener? chatMessageListener,
    InMemoryFeedClearedRepository? feedClearedRepository,
    GroupRepository? groupRepository,
    GroupMessageRepository? groupMessageRepository,
  }) {
    final crListener = ContactRequestListener(
      contactRequestStream: const Stream.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => '',
    );
    final cmListener =
        chatMessageListener ??
        ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FeedWired(
        repository: identityRepo,
        contactRepository: contactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: crListener,
        messageRepository: messageRepo,
        postRepository: postRepository,
        mediaAttachmentRepository: mediaAttachmentRepo,
        chatMessageListener: cmListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
        feedClearedRepository:
            feedClearedRepository ?? InMemoryFeedClearedRepository(),
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
      ),
    );
  }

  // Seeds a JOINED chat group + one UNREAD INCOMING message so the feed
  // projects a focusable LetterCardGroup. me-peer is seeded as an admin member
  // with NO devices (skips the device-binding send gate), plus a group key
  // (latestKey != null is required for a successful group send).
  Future<void> seedGroupThread(
    String groupId,
    String groupName,
    String body,
  ) async {
    final now = DateTime.now().toUtc();
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: groupName,
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: now,
        createdBy: 'me-peer',
        myRole: GroupRole.admin,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'me-peer',
        username: 'Me',
        role: MemberRole.admin,
        publicKey: 'me-pk',
        joinedAt: now,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'grp-other',
        username: 'Grace',
        role: MemberRole.writer,
        publicKey: 'grp-other-pk',
        joinedAt: now,
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'test-group-key-1',
        createdAt: now,
      ),
    );
    await groupMsgRepo.saveMessage(
      GroupMessage(
        id: 'grp-in-$groupId',
        groupId: groupId,
        senderPeerId: 'grp-other',
        senderUsername: 'Grace',
        text: body,
        timestamp: now,
        isIncoming: true,
        createdAt: now,
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 8}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void setWideViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  bool flowEmitted(String event) =>
      flowEvents.any((e) => e['event'] == event);

  // Mounting the Orbit host (tab switch) renders the all-chats list chrome,
  // which overflows at the test viewport — unrelated to the focus-clear
  // behavior under test. Swallow only layout/asset noise (mirrors
  // feed_swipe_test).
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

  double opacityOf(WidgetTester tester, Finder finder) {
    final widget = tester.widget<AnimatedOpacity>(
      find.ancestor(of: finder, matching: find.byType(AnimatedOpacity)).first,
    );
    return widget.opacity;
  }

  testWidgets(
    'TC-19: tapping a card focuses it, collapses+fades the others, shows the '
    'composer, and fades the nav bar WITHOUT the keyboard',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([
        contact('p1', 'Ann'),
        contact('p2', 'Ben'),
        contact('p3', 'Cara'),
      ]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');
      await seedPendingThread('p2', 'Ben', 'hi from ben');
      await seedPendingThread('p3', 'Cara', 'hi from cara');

      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      // BEFORE focus: three letter cards, no composer, no open-conversation
      // affordance, nav bar fully opaque.
      expect(find.byType(LetterCardOneToOne), findsNWidgets(3));
      expect(find.byType(FeedComposer), findsNothing);
      expect(find.byKey(const ValueKey('feed-open-full-conversation')),
          findsNothing);
      expect(opacityOf(tester, find.byType(FeedNavigationBar)), 1.0);

      // Tap the first card.
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      // The single shared composer + "open full conversation" appear.
      expect(find.byType(FeedComposer), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-open-full-conversation')),
          findsOneWidget);

      // The focused card stays opaque + present; the other two collapse away
      // (AnimatedSize→0) AND fade (AnimatedOpacity→0): their text is gone and
      // only one letter card remains rendered.
      expect(find.text('hi from ann'), findsOneWidget);
      expect(opacityOf(tester, find.text('hi from ann')), 1.0);
      expect(find.text('hi from ben'), findsNothing);
      expect(find.text('hi from cara'), findsNothing);
      expect(find.byType(LetterCardOneToOne), findsOneWidget);

      // Nav bar fades via AnimatedOpacity→0, and the keyboard was NOT raised.
      expect(opacityOf(tester, find.byType(FeedNavigationBar)), 0.0);
      expect(tester.view.viewInsets.bottom, 0.0);
    },
  );

  testWidgets(
    'TC-19b: the scrollable reserves ~170 bottom padding so the last card '
    'clears the floating composer / nav',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');

      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      final padding = tester
          .widgetList<SliverPadding>(find.byType(SliverPadding))
          .map((p) => p.padding.resolve(TextDirection.ltr).bottom)
          .reduce((a, b) => a > b ? a : b);
      expect(padding, greaterThanOrEqualTo(160.0));
    },
  );

  testWidgets(
    'TC-21: 1:1 composer placeholder reads "Reply to <contact>…"',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');

      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      expect(find.text('Reply to Ann…'), findsOneWidget);
    },
  );

  testWidgets(
    'TC-22: composer send appends a green outgoing bubble, keeps focus with '
    '"Add another…", and emits FEED_SEND_APPEND',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');

      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      await tester.enterText(
        find.byKey(const ValueKey('feed-composer-field')),
        'on my way',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
      await pumpFrames(tester);

      // A new OUTGOING green bubble was appended.
      final outgoing = tester
          .widgetList<LetterBubble>(find.byType(LetterBubble))
          .where((b) => b.role == LetterBubbleRole.outgoing)
          .toList();
      expect(outgoing.any((b) => b.text == 'on my way'), isTrue);

      // Composer stays mounted and the hint flips to "Add another…".
      expect(find.byType(FeedComposer), findsOneWidget);
      expect(find.text('Add another…'), findsOneWidget);

      expect(flowEmitted('FEED_SEND_APPEND'), isTrue);
    },
  );

  testWidgets(
    'TC-30: a failed outgoing reply renders a tappable retry affordance (no '
    'status tick) and emits FEED_SEND_RETRY_SHOWN; tapping re-invokes the send',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');

      // p2pService default send fails (no live peer) → SendChatMessageResult is
      // not success → the optimistic bubble persists with a retry affordance.
      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      await tester.enterText(
        find.byKey(const ValueKey('feed-composer-field')),
        'this will fail',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
      await pumpFrames(tester);

      // The failed bubble PERSISTS and a retry affordance is shown.
      expect(find.text('this will fail'), findsOneWidget);
      expect(find.text('tap to retry'), findsOneWidget);
      expect(flowEmitted('FEED_SEND_RETRY_SHOWN'), isTrue);

      // Tapping retry re-invokes the send: capture flow events before the tap
      // and assert a SECOND FEED_SEND_RETRY_SHOWN fires (the re-send fails again
      // → re-marks the reply failed → re-emits). TI-1: this PROVES the retry
      // callback actually ran the send, not just that the bubble persists.
      final retryShownBefore = flowEvents
          .where((e) => e['event'] == 'FEED_SEND_RETRY_SHOWN')
          .length;
      await tester.tap(find.text('tap to retry'));
      await pumpFrames(tester);
      expect(find.text('this will fail'), findsOneWidget);
      final retryShownAfter = flowEvents
          .where((e) => e['event'] == 'FEED_SEND_RETRY_SHOWN')
          .length;
      expect(
        retryShownAfter,
        greaterThan(retryShownBefore),
        reason: 'tapping retry must re-invoke the send (a second failure '
            're-emits FEED_SEND_RETRY_SHOWN)',
      );
    },
  );

  // Seeds a live connection to [peerId] so a composer send SUCCEEDS (the
  // default fake has no live peer → sendChatMessage returns nodeNotRunning).
  void seedLiveConnection(String peerId) {
    p2pService.emitState(
      NodeState(
        isStarted: true,
        connections: [
          p2p.ConnectionState(
            peerId: peerId,
            multiaddrs: const ['/dns4/relay/tcp/443'],
            direction: 'outbound',
            status: 'connected',
          ),
        ],
      ),
    );
  }

  testWidgets(
    'B5/TC-9: a successful 1:1 reply send KEEPS the incoming bubbles visible '
    '(PROD-CRITICAL)',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');

      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      // The contact starts unread.
      expect(await messageRepo.getUnreadCountForContact('p1'), 1);

      // Seed a live connection so the send SUCCEEDS.
      seedLiveConnection('p1');
      await pumpFrames(tester);

      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      await tester.enterText(
        find.byKey(const ValueKey('feed-composer-field')),
        'on my way',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
      await pumpFrames(tester);

      // The incoming bubble survives the SUCCESSFUL send. On HEAD the success
      // branch calls markConversationRead → unreadMessages empties → red.
      expect(find.text('hi from ann'), findsOneWidget);

      // The outgoing reply was appended (the send actually succeeded).
      final outgoing = tester
          .widgetList<LetterBubble>(find.byType(LetterBubble))
          .where((b) => b.role == LetterBubbleRole.outgoing)
          .toList();
      expect(outgoing.any((b) => b.text == 'on my way'), isTrue);

      // Read is DEFERRED to leave: the conversation stays unread after a send.
      expect(await messageRepo.getUnreadCountForContact('p1'), 1);
    },
  );

  testWidgets(
    'B5/TC-10: a successful GROUP reply send KEEPS the incoming run visible',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      await seedGroupThread('g1', 'Trail Crew', 'hi from grp');

      await tester.pumpWidget(
        buildWired(
          groupRepository: groupRepo,
          groupMessageRepository: groupMsgRepo,
        ),
      );
      await pumpFrames(tester);

      // The group starts unread and its incoming run is on the feed.
      expect(await groupMsgRepo.getUnreadCount('g1'), 1);
      expect(find.text('hi from grp'), findsOneWidget);

      // Focus the group card.
      await tester.tap(find.text('hi from grp'));
      await pumpFrames(tester);
      expect(find.byType(FeedComposer), findsOneWidget);

      // Send a group reply — the default FakeBridge yields a successful publish.
      await tester.enterText(
        find.byKey(const ValueKey('feed-composer-field')),
        'on the way',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
      await pumpFrames(tester);

      // The incoming run SURVIVES the successful send. On HEAD the success
      // branch calls groupMessageRepository.markAsRead → unread empties → red.
      expect(find.text('hi from grp'), findsOneWidget);

      final outgoing = tester
          .widgetList<LetterBubble>(find.byType(LetterBubble))
          .where((b) => b.role == LetterBubbleRole.outgoing)
          .toList();
      expect(outgoing.any((b) => b.text == 'on the way'), isTrue);

      // Read is DEFERRED to leave: the group stays unread after a send.
      expect(await groupMsgRepo.getUnreadCount('g1'), 1);
    },
  );

  testWidgets(
    'B2/TC-5: a focused thread shows a back affordance that returns to Feed '
    'WITHOUT committing when no reply was sent',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([
        contact('p1', 'Ann'),
        contact('p2', 'Ben'),
        contact('p3', 'Cara'),
      ]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');
      await seedPendingThread('p2', 'Ben', 'hi from ben');
      await seedPendingThread('p3', 'Cara', 'hi from cara');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      // No back affordance before focus.
      expect(find.byKey(const ValueKey('feed-focused-back')), findsNothing);

      // Focus the first card → composer + back affordance appear.
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);
      expect(find.byType(FeedComposer), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-focused-back')), findsOneWidget);

      // Tap back WITHOUT sending a reply.
      await tester.tap(find.byKey(const ValueKey('feed-focused-back')));
      await pumpFrames(tester);

      // Returned to the feed: composer gone, all three sibling cards reappear,
      // and the thread was NOT committed (no FEED_CLEAR_COMMIT, no markCleared).
      expect(find.byType(FeedComposer), findsNothing);
      expect(find.byType(LetterCardOneToOne), findsNWidgets(3));
      expect(find.text('hi from ann'), findsOneWidget);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isFalse);
      expect(clearedRepo.markCalls, isEmpty);
    },
  );

  testWidgets(
    'B2/B4/B5/TC-11: leaving a replied thread via the back affordance commits, '
    'removes the card, and marks it read (read deferred to leave)',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);
      expect(await messageRepo.getUnreadCountForContact('p1'), 1);

      seedLiveConnection('p1');
      await pumpFrames(tester);
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      // Send a reply (success) — read stays deferred at this point.
      await tester.enterText(
        find.byKey(const ValueKey('feed-composer-field')),
        'on my way',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
      await pumpFrames(tester);
      expect(await messageRepo.getUnreadCountForContact('p1'), 1);

      // Leave the replied thread via the back affordance → commit + read-mark.
      await tester.tap(find.byKey(const ValueKey('feed-focused-back')));
      await pumpFrames(tester);

      // Card removed, conversation read-marked (read happens on LEAVE), and the
      // last card leaving surfaces the caught-up empty state.
      expect(find.text('hi from ann'), findsNothing);
      expect(find.byType(LetterCardOneToOne), findsNothing);
      expect(clearedRepo.markCalls, hasLength(1));
      expect(clearedRepo.markCalls.single.markRead, isTrue);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isTrue);
      expect(await messageRepo.getUnreadCountForContact('p1'), 0);
      expect(find.byType(CaughtUpEmptyState), findsOneWidget);
    },
  );

  testWidgets(
    'B3/TC-6: the open-full-conversation link sits at the END of the thread '
    '(below the incoming bubbles) and above the composer field',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');

      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      expect(
        find.byKey(const ValueKey('feed-open-full-conversation')),
        findsOneWidget,
      );

      final linkDy = tester
          .getTopLeft(find.byKey(const ValueKey('feed-open-full-conversation')))
          .dy;
      final bubbleDy = tester.getTopLeft(find.text('hi from ann')).dy;
      final fieldDy = tester
          .getTopLeft(find.byKey(const ValueKey('feed-composer-field')))
          .dy;

      // History entry point lives at the END of the focused column — BELOW the
      // incoming bubbles (per the bug report, image #4) but still above the
      // bottom-anchored floating composer field.
      expect(linkDy, greaterThan(bubbleDy));
      expect(linkDy, lessThan(fieldDy));
    },
  );

  // ── REG-LEAVE-SURFACE: leaving the feed surface ends the new focus session ─
  testWidgets(
    'REG-LEAVE-SURFACE: switching away from the feed tab clears the new focus '
    'session — composer + open-conversation affordance gone; locks the '
    '_clearFeedComposerFocus new-focus clear',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');

      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      // Focus the card → the shared composer + open-conversation affordance show.
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);
      expect(find.byType(FeedComposer), findsOneWidget);
      expect(
        find.byKey(const ValueKey('feed-open-full-conversation')),
        findsOneWidget,
      );

      // Leave the feed surface via the injected shell controller (the most
      // reachable _clearFeedComposerFocus caller in this harness: switchTo a
      // non-feed tab → _onShellChanged → _clearFeedComposerFocus(notify:false)).
      appShellController.switchTo('orbit');
      await pumpFrames(tester);

      // The new focus session ended: composer retracted + affordance gone.
      // Mutation-falsifiable: reverting _clearFeedComposerFocus to clear only
      // _activeFocusPeerId leaves _focusedId set → composer stays mounted.
      expect(find.byType(FeedComposer), findsNothing);
      expect(
        find.byKey(const ValueKey('feed-open-full-conversation')),
        findsNothing,
      );
    },
  );

  // ── 160: feed N+1 → batched-summary preview + lazy-on-focus ──────────────

  Future<void> seedMixedThread(
    String peerId, {
    required int readCount,
    required int unreadCount,
  }) async {
    final base = DateTime.utc(2026, 3, 1, 8);
    var i = 0;
    for (var r = 0; r < readCount; r++, i++) {
      final ts = base.add(Duration(minutes: i)).toIso8601String();
      await messageRepo.saveMessage(
        ConversationMessage(
          id: '$peerId-r$r',
          contactPeerId: peerId,
          text: 'read $r',
          senderPeerId: peerId,
          timestamp: ts,
          isIncoming: true,
          status: 'delivered',
          createdAt: ts,
          readAt: ts,
        ),
      );
    }
    for (var u = 0; u < unreadCount; u++, i++) {
      final ts = base.add(Duration(minutes: i)).toIso8601String();
      await messageRepo.saveMessage(
        ConversationMessage(
          id: '$peerId-u$u',
          contactPeerId: peerId,
          text: 'unread $u',
          senderPeerId: peerId,
          timestamp: ts,
          isIncoming: true,
          status: 'delivered',
          createdAt: ts,
        ),
      );
    }
  }

  testWidgets(
    'TC-160-06/19: mount loads only the bounded preview window; focus hydrates '
    'the full thread with a larger page and does NOT mark read',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      // 10 read (older) + 3 unread (newest): mount window = unread + context.
      await seedMixedThread('p1', readCount: 10, unreadCount: 3);

      messageRepo.resetSpyCounters();
      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      // Mount: a bounded window only — never the unbounded full load.
      expect(messageRepo.getMessagesForContactCallCount, 0);
      final mountPages = messageRepo.getMessagesPageCalls
          .where((c) => c.$1 == 'p1')
          .toList();
      expect(mountPages, isNotEmpty);
      expect(mountPages.every((c) => c.$2 < 50), isTrue);

      // Focus hydrates the focused thread with a LARGER page.
      messageRepo.getMessagesPageCalls.clear();
      await tester.tap(find.text('unread 2'));
      await pumpFrames(tester);
      final focusPages = messageRepo.getMessagesPageCalls
          .where((c) => c.$1 == 'p1')
          .toList();
      expect(focusPages.any((c) => c.$2 >= 50), isTrue);

      // REG-INV3: focus never marks the conversation read.
      expect(await messageRepo.getUnreadCountForContact('p1'), 3);
    },
  );

  testWidgets(
    'TC-160-15: a thread with more unread than the rejected fixed cap renders '
    'EVERY unread line (the window covers the full unread run)',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      // 12 unread > 8 (the rejected fixed tail-cap) and > maxPreview(3).
      await seedMixedThread('p1', readCount: 0, unreadCount: 12);

      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      for (var u = 0; u < 12; u++) {
        expect(find.text('unread $u'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'TC-160-07: send from the feed composer merges in memory — no unbounded DB '
    're-read',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'Ann', 'hi from ann');

      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      // Reset AFTER focus hydration so we measure only the send.
      messageRepo.resetSpyCounters();
      await tester.enterText(
        find.byKey(const ValueKey('feed-composer-field')),
        'optimistic reply',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
      await pumpFrames(tester);

      // A feed-composer send appends the optimistic bubble WITHOUT any
      // per-contact DB read — neither the unbounded full load nor a bounded
      // snapshot page. (The send-success branch's in-memory merge cannot be
      // driven here — the feed harness has no live peer so the send does not
      // reach success — but the optimistic/session path must never reload, and
      // the merge's count-carry mechanics are locked at the model tier and by
      // the shared incoming-merge path.)
      expect(messageRepo.getMessagesForContactCallCount, 0);
      expect(
        messageRepo.getMessagesPageCalls.where((c) => c.$1 == 'p1'),
        isEmpty,
      );
      // The optimistic outgoing bubble is rendered.
      final outgoing = tester
          .widgetList<LetterBubble>(find.byType(LetterBubble))
          .where((b) => b.role == LetterBubbleRole.outgoing)
          .toList();
      expect(outgoing.any((b) => b.text == 'optimistic reply'), isTrue);
    },
  );

  // Reads the LIVE projected 1:1 thread from the listenable (the `feedItems`
  // prop is a stale snapshot from the last FeedWired build).
  ThreadFeedItem threadFor(WidgetTester tester, String peerId) {
    final feedScreen = tester.widget<FeedScreen>(find.byType(FeedScreen));
    return feedScreen.feedItemsListenable!.value
        .whereType<ThreadFeedItem>()
        .singleWhere((i) => i.contactPeerId == peerId);
  }

  testWidgets(
    'TC-160-19: focus hydrates the FULL thread (read history off the mount '
    'window) and marks nothing read; a contact-update while focused does NOT '
    'clobber the hydrated thread back to the bounded window',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      // 30 older READ + 3 newest UNREAD: the mount window is unread-run-sized,
      // so the oldest read ('p1-r0') is OFF the mount window and only the focus
      // hydration (a larger page) pulls the full thread in.
      await seedMixedThread('p1', readCount: 30, unreadCount: 3);

      // A controllable contact-update stream — the reachable "while-focused"
      // rebuild path (see the clobber note below).
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      await tester.pumpWidget(buildWired(chatMessageListener: listener));
      await pumpFrames(tester);

      // Mount: the bounded preview window excludes the oldest read history.
      final mounted = threadFor(tester, 'p1');
      expect(mounted.messages.length, lessThan(33));
      expect(mounted.messages.any((m) => m.id == 'p1-r0'), isFalse);

      // Focus hydrates the FULL thread (all 33 incl. the oldest read).
      await tester.tap(find.text('unread 0'));
      await pumpFrames(tester);
      final focused = threadFor(tester, 'p1');
      expect(focused.messages.length, 33);
      expect(focused.messages.any((m) => m.id == 'p1-r0'), isTrue);
      // REG-INV3: focus never marks the conversation read.
      expect(await messageRepo.getUnreadCountForContact('p1'), 3);

      // No-clobber while focused: a contact update (rename/avatar) rebuilds the
      // focused card from the IN-MEMORY hydrated messages (feed_wired.dart:1212),
      // NOT a fresh mount-window snapshot — the full thread survives.
      //
      // NOTE: the literal _refreshAllContactsSection clobber guard
      // (feed_wired.dart:760-765) cannot be reached WHILE focused through public
      // interaction — its only trigger is orbit-exit route changes, and
      // switching tabs runs _clearFeedComposerFocus first (nulls _focusedId).
      // The contact-update rebuild is the reachable embodiment of INV-14.
      listener.emitContactUpdate(contact('p1', 'Ann Renamed'));
      await pumpFrames(tester);
      final afterUpdate = threadFor(tester, 'p1');
      expect(afterUpdate.messages.length, 33);
      expect(afterUpdate.messages.any((m) => m.id == 'p1-r0'), isTrue);
      expect(await messageRepo.getUnreadCountForContact('p1'), 3);
    },
  );
}
