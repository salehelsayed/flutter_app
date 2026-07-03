import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/glow_fab.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/group_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_list_header.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 193 — Orbit screen view split: the Inner-Circle visualization is the default
/// on every entry; the classic all-chats list is a separate, toggle-reachable
/// view. Copies the `buildOrbitWired`/`pumpOrbitFrames` idioms from
/// `orbit_wired_test.dart` (kept small — the stream-dependent live-rerank case
/// lives beside the private fakes in that file). Toggle key: `orbit-view-toggle`.
double _logicalWidth(WidgetTester tester) =>
    tester.view.physicalSize.width / tester.view.devicePixelRatio;

IntroductionModel _pendingIntroduction({
  required String ownPeerId,
  required String otherPeerId,
  required String createdAt,
  String id = 'orbit-intro',
}) {
  return IntroductionModel(
    id: id,
    introducerId: 'peer-A',
    recipientId: ownPeerId,
    introducedId: otherPeerId,
    createdAt: createdAt,
    introducerUsername: 'Noor',
    recipientUsername: 'Alice',
    introducedUsername: 'Dora',
  );
}

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
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late List<Map<String, dynamic>> flowEvents;

  final testIdentity = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    mlKemPublicKey: 'mlkem-test-peer-id-12345',
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
    mediaFileManager = FakeMediaFileManager();
    groupRepo = InMemoryGroupRepository();
    groupMsgRepo = InMemoryGroupMessageRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
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

  tearDown(() {
    debugSetFlowEventSink(null);
    postsPrivacySettingsRepository.dispose();
  });

  void setLargeTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  void suppressOverflowErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  void suppressNavAssetErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  Widget buildOrbitWired({
    FakeContactRepository? contactRepository,
    InMemoryGroupRepository? groupRepository,
    InMemoryIntroductionRepository? introductionRepository,
    AppShellController? appShellController,
    ValueNotifier<int>? feedUnreadCountListenable,
    String? initialFilterTab,
    Locale locale = const Locale('en'),
  }) {
    final effectiveContactRepo = contactRepository ?? contactRepo;
    final effectiveGroupRepo = groupRepository ?? groupRepo;

    final crListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: effectiveContactRepo,
      bridge: bridge,
      getOwnPeerId: () => '',
    );
    final cmListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepo,
      contactRepo: effectiveContactRepo,
    );

    final orbitWidget = OrbitWired(
      identityRepo: identityRepo,
      contactRepo: effectiveContactRepo,
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
      feedClearedRepository: InMemoryFeedClearedRepository(),
      groupRepository: effectiveGroupRepo,
      groupMessageRepository: groupMsgRepo,
      introductionRepository: introductionRepository,
      appShellController: appShellController,
      postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      feedUnreadCountListenable: feedUnreadCountListenable,
      initialFilterTab: initialFilterTab,
    );

    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: orbitWidget,
    );
  }

  Future<void> pumpOrbitFrames(WidgetTester tester, {int count = 3}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> switchToAllChats(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
    await pumpOrbitFrames(tester);
  }

  Future<void> seedGroup(String id, String name, {bool isArchived = false}) =>
      groupRepo.saveGroup(
        GroupModel(
          id: id,
          name: name,
          type: GroupType.chat,
          topicName: 'topic-$id',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
          isArchived: isArchived,
          archivedAt: isArchived ? DateTime.utc(2026, 3, 2) : null,
        ),
      );

  group('193 orbit view split', () {
    testWidgets('default entry shows only the Inner-Circle surface', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      await seedGroup('g-1', 'Alpha Group');
      final introRepo = InMemoryIntroductionRepository();
      await introRepo.saveIntroduction(
        _pendingIntroduction(
          ownPeerId: testIdentity.peerId,
          otherPeerId: 'intro-peer-id',
          createdAt: freshPendingIntroductionCreatedAt(),
        ),
      );

      await tester.pumpWidget(
        buildOrbitWired(introductionRepository: introRepo),
      );
      await pumpOrbitFrames(tester, count: 4);

      // Inner-Circle surface only: the visualization renders, but NONE of the
      // all-chats list-coupled affordances leak onto it.
      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byType(FriendRow), findsNothing);
      expect(find.byType(GroupRow), findsNothing);
      expect(find.byType(FriendsFilterToggle), findsNothing);
      expect(find.byType(FriendsListHeader), findsNothing);
      expect(find.byType(OrbitSearchTrigger), findsNothing);
      // The intro banner (list-header sibling) is absent on the inner view.
      expect(find.text('1 item pending'), findsNothing);
    });

    // ── 197: group chats appear on the inner-circle rings ───────────────────

    testWidgets(
      'inner-circle default surface shows a seeded group as a ring node '
      '(not a list row)',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);
        await seedGroup('g-1', 'Alpha Group');

        await tester.pumpWidget(buildOrbitWired());
        await pumpOrbitFrames(tester, count: 4);

        // PROD-CRITICAL: the wired path
        // orbit_wired → OrbitHeaderProjection.innerItems →
        // _buildInnerCircleSurface → OrbitalVisualization
        // must deliver the seeded group to the rings as a GroupAvatar node —
        // and it is a ring node, NOT an all-chats list row.
        expect(find.byType(OrbitalVisualization), findsOneWidget);
        expect(find.byType(GroupAvatar), findsOneWidget);
        expect(find.byType(GroupRow), findsNothing);
      },
    );

    testWidgets('archived group is not shown on the inner circle', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      await seedGroup('g-active', 'Bravo Team');
      await seedGroup('g-archived', 'Zulu Squad', isArchived: true);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      // Only the active group seats a ring node (the header feed uses
      // _activeGroups, which excludes archived groups).
      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byType(GroupAvatar), findsOneWidget);
      expect(find.text('BT'), findsOneWidget); // "Bravo Team" initials fallback
      expect(find.text('ZS'), findsNothing); // "Zulu Squad" excluded
    });

    testWidgets('top-left toggle switches to the all-chats view', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      await seedGroup('g-1', 'Alpha Group');

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      expect(find.byKey(const ValueKey('orbit-view-toggle')), findsOneWidget);

      await switchToAllChats(tester);

      expect(find.byType(FriendRow), findsWidgets);
      expect(find.byType(FriendsFilterToggle), findsOneWidget);
      expect(find.byType(FriendsListHeader), findsOneWidget);
      expect(find.byType(OrbitalVisualization), findsNothing);

      final toggleRect = tester.getRect(
        find.byKey(const ValueKey('orbit-view-toggle')),
      );
      expect(toggleRect.left, lessThan(_logicalWidth(tester) / 2));
      expect(toggleRect.top, lessThan(120));
    });

    testWidgets('toggle returns to the Inner-Circle view', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      await switchToAllChats(tester);
      expect(find.byType(FriendsFilterToggle), findsOneWidget);

      // Second tap returns to the circle.
      await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
      await pumpOrbitFrames(tester);

      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byType(FriendRow), findsNothing);
      expect(find.byType(FriendsFilterToggle), findsNothing);
    });

    testWidgets('rapid toggling lands deterministically', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      // Five taps from the Inner-Circle default → parity lands on all-chats.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
        await tester.pump();
      }
      await pumpOrbitFrames(tester);

      expect(find.byType(FriendsFilterToggle), findsOneWidget);
      expect(find.byType(OrbitalVisualization), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('RTL keeps the toggle clear of the FAB', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired(locale: const Locale('ar')));
      await pumpOrbitFrames(tester, count: 4);

      final toggleRect = tester.getRect(
        find.byKey(const ValueKey('orbit-view-toggle')),
      );
      // Physical top-left in RTL too — a PositionedDirectional would flip it to
      // the physical right, into the FAB.
      expect(toggleRect.center.dx, lessThan(_logicalWidth(tester) / 2));

      final fabRect = tester.getRect(find.byType(GlowFab));
      expect(toggleRect.right, lessThanOrEqualTo(fabRect.left));
    });

    testWidgets('all-chats header clears the top chrome strip (LTR+RTL)', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      // 196: the QR entries left the header for the top-center chrome strip
      // (toggle + pair), so the list header no longer needs the physical-left
      // inset — it now clears the strip VERTICALLY instead. That invariant is
      // font-independent (unlike the old left-edge assert whose pill
      // justification died), so the Ahem width inflation cannot break it, and
      // it holds in both directions.
      for (final locale in const [Locale('en'), Locale('ar')]) {
        // Fully unmount first so each locale starts from a fresh Inner-Circle
        // default (a bare re-pump reuses OrbitWired's State, which would keep
        // the previous iteration's all-chats view and make switchToAllChats
        // toggle back to the circle).
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(buildOrbitWired(locale: locale));
        await pumpOrbitFrames(tester, count: 4);
        await switchToAllChats(tester);

        final toggleRect = tester.getRect(
          find.byKey(const ValueKey('orbit-view-toggle')),
        );
        final headerRect = tester.getRect(find.byType(FriendsListHeader));
        final pairRect = tester
            .getRect(find.byKey(const ValueKey('orbit-my-qr-button')))
            .expandToInclude(
              tester.getRect(find.byKey(const ValueKey('orbit-scan-button'))),
            );

        expect(
          headerRect.top,
          greaterThanOrEqualTo(toggleRect.bottom),
          reason: '$locale: FriendsListHeader overlaps the top chrome strip',
        );
        expect(
          headerRect.overlaps(pairRect),
          isFalse,
          reason: '$locale: FriendsListHeader overlaps the QR chrome pair',
        );
      }
    });

    testWidgets('toggle semantics label flips per view', (tester) async {
      final handle = tester.ensureSemantics();
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      // Inner-Circle view: the toggle invites switching to the all-chats list.
      expect(find.bySemanticsLabel('Show all chats'), findsOneWidget);
      expect(find.bySemanticsLabel('Show inner circle'), findsNothing);

      await switchToAllChats(tester);

      expect(find.bySemanticsLabel('Show inner circle'), findsOneWidget);
      expect(find.bySemanticsLabel('Show all chats'), findsNothing);
      handle.dispose();
    });

    testWidgets('create-group FAB lives on the Inner-Circle view', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      expect(find.byType(ExpandableFab), findsOneWidget);
      expect(find.byType(FriendRow), findsNothing);
    });

    testWidgets('nav badge is live on the Inner-Circle view', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      // Seed a friend so the list-absence conjunct is a real RED on HEAD (the
      // badge holds on either surface; the discriminator is FriendRow absence).
      contactRepo.seed([testContact]);

      final introRepo = InMemoryIntroductionRepository();
      await introRepo.saveIntroduction(
        _pendingIntroduction(
          id: 'i1',
          ownPeerId: testIdentity.peerId,
          otherPeerId: 'p1',
          createdAt: freshPendingIntroductionCreatedAt(),
        ),
      );
      await introRepo.saveIntroduction(
        _pendingIntroduction(
          id: 'i2',
          ownPeerId: testIdentity.peerId,
          otherPeerId: 'p2',
          createdAt: freshPendingIntroductionCreatedAt(),
        ),
      );
      final feedUnread = ValueNotifier<int>(0);
      addTearDown(feedUnread.dispose);

      await tester.pumpWidget(
        buildOrbitWired(
          appShellController: AppShellController(initialTab: AppShellTab.orbit),
          feedUnreadCountListenable: feedUnread,
          introductionRepository: introRepo,
        ),
      );
      await pumpOrbitFrames(tester, count: 6);

      final buttons = tester
          .widgetList<NavBarButton>(find.byType(NavBarButton))
          .toList();
      expect(buttons[1].badgeCount, 2);
      expect(find.byType(FriendRow), findsNothing);
    });

    testWidgets('zero contacts shows a meaningful Inner-Circle state', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(
        find.text('Add friends to see your inner circle'),
        findsOneWidget,
      );
      expect(find.byType(FriendRow), findsNothing);

      // The toggle still works from the empty inner view.
      await switchToAllChats(tester);
      expect(find.byType(FriendsListHeader), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('non-null initialFilterTab forces the all-chats view', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);

      final introRepo = InMemoryIntroductionRepository();
      await introRepo.saveIntroduction(
        _pendingIntroduction(
          ownPeerId: testIdentity.peerId,
          otherPeerId: 'intro-peer-id',
          createdAt: freshPendingIntroductionCreatedAt(),
        ),
      );
      final feedUnread = ValueNotifier<int>(0);
      addTearDown(feedUnread.dispose);

      await tester.pumpWidget(
        buildOrbitWired(
          initialFilterTab: 'intros',
          appShellController: AppShellController(initialTab: AppShellTab.orbit),
          feedUnreadCountListenable: feedUnread,
          introductionRepository: introRepo,
        ),
      );
      await pumpOrbitFrames(tester, count: 6);

      // The intros surface is reachable from the notification route with ZERO
      // taps, and it is the all-chats view (no orbital visualization).
      expect(find.text('Dora'), findsWidgets);
      expect(find.byType(OrbitalVisualization), findsNothing);
    });

    testWidgets(
      'a fresh mount defaults to Inner-Circle even after a prior toggle',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([testContact]);

        await tester.pumpWidget(buildOrbitWired());
        await pumpOrbitFrames(tester, count: 4);

        await switchToAllChats(tester);
        expect(find.byType(FriendsFilterToggle), findsOneWidget);

        // Fully unmount, then a brand-new OrbitWired mount reconstructs the
        // default (no persistence). The intermediate SizedBox forces a real
        // dispose→initState rather than State reuse.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(buildOrbitWired());
        await pumpOrbitFrames(tester, count: 4);

        expect(find.byType(OrbitalVisualization), findsOneWidget);
        expect(find.byType(FriendRow), findsNothing);
      },
    );

    testWidgets('re-entry reset preserves the filter tab', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      final shell = AppShellController(initialTab: AppShellTab.orbit);
      final feedUnread = ValueNotifier<int>(0);
      addTearDown(feedUnread.dispose);

      await tester.pumpWidget(
        buildOrbitWired(
          appShellController: shell,
          feedUnreadCountListenable: feedUnread,
        ),
      );
      await pumpOrbitFrames(tester, count: 4);

      await switchToAllChats(tester);
      await tester.tap(find.text('Archived'));
      await pumpOrbitFrames(tester);
      expect(
        tester
            .widget<FriendsFilterToggle>(find.byType(FriendsFilterToggle))
            .activeFilter,
        'archived',
      );

      // Leave and re-enter Orbit → the view resets to Inner-Circle.
      shell.switchTo(AppShellTab.feed);
      await pumpOrbitFrames(tester);
      shell.switchTo(AppShellTab.orbit);
      await pumpOrbitFrames(tester);
      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byType(FriendsFilterToggle), findsNothing);

      // ... but the filter tab is deliberately NOT reset (locked asymmetry).
      await switchToAllChats(tester);
      expect(
        tester
            .widget<FriendsFilterToggle>(find.byType(FriendsFilterToggle))
            .activeFilter,
        'archived',
      );
    });

    testWidgets('background-kind controller notify does not reset the view', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      final shell = AppShellController(initialTab: AppShellTab.orbit);
      final feedUnread = ValueNotifier<int>(0);
      addTearDown(feedUnread.dispose);

      await tester.pumpWidget(
        buildOrbitWired(
          appShellController: shell,
          feedUnreadCountListenable: feedUnread,
        ),
      );
      await pumpOrbitFrames(tester, count: 4);

      await switchToAllChats(tester);
      expect(find.byType(FriendsFilterToggle), findsOneWidget);

      // A background-kind notification while Orbit is active must NOT reset the
      // view (only an inactive→active transition does).
      final other = BackgroundPreference.values.firstWhere(
        (p) => p != shell.backgroundPreference,
      );
      shell.setBackgroundPreference(other);
      await pumpOrbitFrames(tester);

      expect(find.byType(FriendsFilterToggle), findsOneWidget);
      expect(find.byType(OrbitalVisualization), findsNothing);
    });
  });
}
