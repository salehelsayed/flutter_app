import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/introduction/application/resolve_introduction_notification_target_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/push/application/intro_accept_notification_open_flow.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/main.dart' show openIntroNotificationOrbitRoute;

import '../../conversation/domain/repositories/fake_message_repository.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../shared/fakes/intro_test_user.dart';
import '../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late AppShellController appShellController;
  late FakeMessageRepository messageRepository;

  setUp(() {
    // 214: these cases arrange a FEED-resting shell (returnTab restore back to
    // feed) — pin it explicitly now that the bare default is orbit.
    appShellController = AppShellController(initialTab: AppShellTab.feed);
    messageRepository = FakeMessageRepository()
      ..seed([
        _unreadMessage(id: 'm-1', contactPeerId: 'peer-a'),
        _unreadMessage(id: 'm-2', contactPeerId: 'peer-b'),
        _unreadMessage(id: 'm-3', contactPeerId: 'peer-c'),
      ]);
  });

  void setLargeTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
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

  void suppressOverflowErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  Future<void> pumpRouteTransition(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  NavBarButton navButton(WidgetTester tester, String label) {
    return tester
        .widgetList<NavBarButton>(find.byType(NavBarButton))
        .singleWhere((button) => button.label == label);
  }

  testWidgets(
    'intro notification route shows persistent nav with orbit active and feed return restores shell',
    (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();

      await tester.pumpWidget(
        _RouteHarnessApp(
          appShellController: appShellController,
          messageRepository: messageRepository,
        ),
      );

      expect(appShellController.activeTab, AppShellTab.feed);

      await tester.tap(find.text('Open intro orbit'));
      await pumpRouteTransition(tester);

      expect(appShellController.activeTab, AppShellTab.orbit);
      expect(find.byType(FeedNavigationBar), findsOneWidget);

      final feedButton = navButton(tester, 'Feed');
      final orbitButton = navButton(tester, 'Orbit');
      expect(feedButton.isActive, isFalse);
      expect(feedButton.badgeCount, 3);
      expect(orbitButton.isActive, isTrue);

      await tester.tap(find.text('Feed'));
      await pumpRouteTransition(tester);

      expect(appShellController.activeTab, AppShellTab.feed);
      expect(find.text('Open intro orbit'), findsOneWidget);
    },
  );

  testWidgets(
    'intro notification orbit route omits the redundant close button and restores via feed nav',
    (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();

      await tester.pumpWidget(
        _RouteHarnessApp(
          appShellController: appShellController,
          messageRepository: messageRepository,
        ),
      );

      await tester.tap(find.text('Open intro orbit'));
      await pumpRouteTransition(tester);

      expect(appShellController.activeTab, AppShellTab.orbit);
      // The Feed/Orbit nav bar is present, so the redundant X is omitted.
      expect(find.byType(FeedNavigationBar), findsOneWidget);
      expect(find.byType(OrbitCloseButton), findsNothing);

      // Tapping Feed restores the prior shell tab and pops the route.
      await tester.tap(find.text('Feed'));
      await pumpRouteTransition(tester);

      expect(appShellController.activeTab, AppShellTab.feed);
      expect(find.text('Open intro orbit'), findsOneWidget);
    },
  );

  testWidgets(
    'orbit resting tab: intro route returns to orbit without a spurious switch',
    (tester) async {
      // 214 sentinel: with orbit as home this is the COMMON resting tab. The
      // route's switchTo(orbit) is guarded and switchTo early-returns on
      // same-tab, so the whole open→pop cycle must fire ZERO tab changes and
      // end back on orbit.
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();

      final orbitRestingController = AppShellController(
        initialTab: AppShellTab.orbit,
      );
      addTearDown(orbitRestingController.dispose);
      var notifications = 0;
      orbitRestingController.addListener(() => notifications++);

      await tester.pumpWidget(
        _RouteHarnessApp(
          appShellController: orbitRestingController,
          messageRepository: messageRepository,
        ),
      );

      await tester.tap(find.text('Open intro orbit'));
      await pumpRouteTransition(tester);

      expect(orbitRestingController.activeTab, AppShellTab.orbit);
      expect(find.byType(OrbitScreen), findsOneWidget);
      expect(notifications, 0);

      // Pop the route without touching the controller (system back / close):
      // the finally-restore must be a same-tab no-op, not a switch to feed.
      Navigator.of(tester.element(find.byType(OrbitScreen))).pop();
      await pumpRouteTransition(tester);

      expect(find.text('Open intro orbit'), findsOneWidget);
      expect(orbitRestingController.activeTab, AppShellTab.orbit);
      expect(notifications, 0);
    },
  );

  for (final passed in [false, true]) {
    testWidgets(
      'IN-008 actual offer notification opens real introduction review and '
      'preserves ${passed ? 'terminal Pass' : 'pending consent'} without effects',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        late _PendingOfferFixture fixture;
        late String introductionId;
        await tester.runAsync(() async {
          fixture = _PendingOfferFixture();
          addTearDown(() => tester.runAsync(() async => fixture.dispose()));
          introductionId = await fixture.offer();
          if (passed) {
            await fixture.recipient.passIntro(introductionId);
            await fixture.until(
              () async =>
                  (await fixture.introduced.introRepo.getIntroduction(
                    introductionId,
                  ))?.status ==
                  IntroductionOverallStatus.passed,
            );
          }
        });
        final recipient = fixture.recipient;
        final before = (await recipient.introRepo.getIntroduction(
          introductionId,
        ))!;
        final otherBefore = (await fixture.introduced.introRepo.getIntroduction(
          introductionId,
        ))!;
        final contactsBefore = (await recipient.contactRepo.getAllContacts())
            .map((contact) => contact.toMap())
            .toList();
        final connectionsBefore = Set<String>.of(
          recipient.p2pService.connectedPeers,
        );
        final outboxBefore = await recipient.introRepo
            .loadOutboxDeliveriesForIntroduction(introductionId);
        final sendsBefore = fixture.network.deliverCallCount;
        final inboxBefore = fixture.network.storeInInboxCallCount;
        expect(sendsBefore, greaterThan(0));
        final identityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: recipient.peerId,
              publicKey: 'pk-${recipient.peerId}',
              privateKey: 'fixture-private-key',
              mnemonic12:
                  'one two three four five six seven eight nine ten eleven twelve',
              username: recipient.username,
              createdAt: before.createdAt,
              updatedAt: before.createdAt,
            ),
          );
        final requestRepo = FakeContactRequestRepository()
          ..contactRepository = recipient.contactRepo;
        final requestListener = ContactRequestListener(
          contactRequestStream: const Stream<ChatMessage>.empty(),
          requestRepo: requestRepo,
          contactRepo: recipient.contactRepo,
          bridge: recipient.bridge,
          getOwnPeerId: () => recipient.peerId,
        );
        addTearDown(requestListener.dispose);
        final privacyRepo = InMemoryPostsPrivacySettingsRepository();
        addTearDown(privacyRepo.dispose);
        final secureKeyStore = FakeSecureKeyStore();
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final mediaFileManager = FakeMediaFileManager();
        final postRepo = InMemoryPostRepository();
        final clearedRepo = InMemoryFeedClearedRepository();
        final pendingPostTargetStore = PendingPostTargetStore();
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async => null,
          compressVideo:
              ({required path, required compress, onProgress}) async => null,
        );
        Future<void>? routeFuture;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    // Use the notification emitted by the real offer listener.
                    // The OS tap is injected here; all route resolution and the
                    // destination below use the production public composition.
                    routeFuture = routeNotificationPayload(
                      payload:
                          fixture.notifications.shownGeneric.single.payload,
                      onBeforeRouteTarget: (target) async {
                        final prepared = await prepareNotificationOpen(
                          routeTarget: target,
                          drainOfflineInbox:
                              recipient.p2pService.drainOfflineInbox,
                          drainGroupOfflineInboxForGroup: (_) async =>
                              fail('An introduction must not open a group.'),
                        );
                        expect(prepared.ok, isTrue);
                      },
                      onRouteTarget: (target) =>
                          openIntroAcceptNotificationRoute(
                            routeTarget: target,
                            notificationTappedAt: DateTime.now(),
                            resolveTarget: (route) =>
                                resolveIntroductionNotificationTarget(
                                  routeTarget: route,
                                  introRepo: recipient.introRepo,
                                  contactRepo: recipient.contactRepo,
                                  loadOwnPeerId: () async => recipient.peerId,
                                  introStatusChanges: recipient
                                      .introListener
                                      .introStatusChangedStream,
                                ),
                            isConversationAlreadyActive: (_) => false,
                            openConversation: (_, _) async => fail(
                              'An offer tap must not open a conversation.',
                            ),
                            openIntros: () => openIntroNotificationOrbitRoute(
                              navigator: Navigator.of(context),
                              appShellController: appShellController,
                              messageRepository: recipient.messageRepo,
                              builder: (unreadCount) => OrbitWired(
                                identityRepo: identityRepo,
                                contactRepo: recipient.contactRepo,
                                contactRequestRepo: requestRepo,
                                contactRequestListener: requestListener,
                                messageRepo: recipient.messageRepo,
                                postRepository: postRepo,
                                mediaAttachmentRepo: mediaRepo,
                                chatMessageListener: recipient.chatListener,
                                bridge: recipient.bridge,
                                p2pService: recipient.p2pService,
                                mediaFileManager: mediaFileManager,
                                secureKeyStore: secureKeyStore,
                                imageProcessor: imageProcessor,
                                feedClearedRepository: clearedRepo,
                                introductionRepository: recipient.introRepo,
                                introductionListener: recipient.introListener,
                                appShellController: appShellController,
                                feedUnreadCountListenable: unreadCount,
                                pendingPostTargetStore: pendingPostTargetStore,
                                postsPrivacySettingsRepository: privacyRepo,
                                initialFilterTab: 'intros',
                              ),
                            ),
                          ),
                    );
                    unawaited(routeFuture);
                  },
                  child: const Text('Open current offer notification'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open current offer notification'));
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.byType(OrbitWired), findsOneWidget);
        expect(appShellController.activeTab, AppShellTab.orbit);
        if (passed) {
          expect(find.byType(IntroRow), findsNothing);
          expect(find.text('No introductions yet'), findsOneWidget);
        } else {
          final row = tester.widget<IntroRow>(find.byType(IntroRow));
          expect(row.introduction.id, introductionId);
          expect(row.introduction.introducerId, fixture.introducer.peerId);
          expect(row.introduction.recipientId, recipient.peerId);
          expect(row.introduction.introducedId, fixture.introduced.peerId);
          expect(row.displayPeerId, fixture.introduced.peerId);
          expect(find.text('Omar'), findsOneWidget);
          expect(find.text('Noor'), findsOneWidget);
          expect(
            find.byKey(ValueKey('intro-accept-$introductionId')),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('intro-pass-$introductionId')),
            findsOneWidget,
          );
        }
        final after = (await recipient.introRepo.getIntroduction(
          introductionId,
        ))!;
        expect(after.toMap(), before.toMap());
        expect(
          after.recipientStatus,
          passed ? IntroductionStatus.passed : IntroductionStatus.pending,
        );
        expect(after.introducedStatus, IntroductionStatus.pending);
        expect(
          (await fixture.introduced.introRepo.getIntroduction(
            introductionId,
          ))!.toMap(),
          otherBefore.toMap(),
        );
        expect(
          (await recipient.contactRepo.getAllContacts()).map(
            (contact) => contact.toMap(),
          ),
          unorderedEquals(contactsBefore),
        );
        expect(
          await recipient.contactRepo.contactExists(fixture.introduced.peerId),
          isFalse,
        );
        expect(await requestRepo.getPendingRequests(), isEmpty);
        expect(
          await recipient.introRepo.loadPendingResponses(introductionId),
          isEmpty,
        );
        expect(
          await recipient.introRepo.loadOutboxDeliveriesForIntroduction(
            introductionId,
          ),
          outboxBefore,
        );
        expect(fixture.network.deliverCallCount, sendsBefore);
        expect(fixture.network.storeInInboxCallCount, inboxBefore);
        expect(recipient.p2pService.connectedPeers, connectionsBefore);

        await tester.tap(find.text('Feed'));
        await pumpRouteTransition(tester);
        await routeFuture;
        expect(find.text('Open current offer notification'), findsOneWidget);
      },
    );
  }
}

/// Reuses the real introduction use cases/listeners with existing in-memory
/// repositories and fake crypto, notification-display and transport ports.
class _PendingOfferFixture {
  _PendingOfferFixture() {
    introducer = IntroTestUser.create(
      peerId: 'peer-A',
      username: 'Noor',
      network: network,
    );
    recipient = IntroTestUser.create(
      peerId: 'peer-B',
      username: 'Lina',
      network: network,
      notificationService: notifications,
    );
    introduced = IntroTestUser.create(
      peerId: 'peer-C',
      username: 'Omar',
      network: network,
    );
    introducer.addContact(recipient);
    introducer.addContact(introduced);
    recipient.addContact(introducer);
    introduced.addContact(introducer);
    introducer.start();
    recipient.start();
    introduced.start();
  }

  final network = FakeP2PNetwork();
  final notifications = FakeNotificationService();
  late final IntroTestUser introducer;
  late final IntroTestUser recipient;
  late final IntroTestUser introduced;

  Future<String> offer() async {
    final recipientReceived = recipient.introListener.introReceivedStream.first;
    final introducedReceived =
        introduced.introListener.introReceivedStream.first;
    final introductions = await introducer.sendIntroductions(
      recipientPeerId: recipient.peerId,
      friends: [(await introducer.contactRepo.getContact(introduced.peerId))!],
    );
    await Future.wait([
      recipientReceived,
      introducedReceived,
    ]).timeout(const Duration(seconds: 3));
    await until(() async => notifications.shownGeneric.isNotEmpty);
    return introductions.single.id;
  }

  Future<void> until(Future<bool> Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!await ready()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Introduction did not converge.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  void dispose() {
    introducer.dispose();
    recipient.dispose();
    introduced.dispose();
  }
}

class _RouteHarnessApp extends StatelessWidget {
  final AppShellController appShellController;
  final FakeMessageRepository messageRepository;

  const _RouteHarnessApp({
    required this.appShellController,
    required this.messageRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                unawaited(
                  openIntroNotificationOrbitRoute(
                    navigator: Navigator.of(context),
                    appShellController: appShellController,
                    messageRepository: messageRepository,
                    builder: (feedUnreadCountListenable) => _IntroOrbitHarness(
                      appShellController: appShellController,
                      feedUnreadCountListenable: feedUnreadCountListenable,
                    ),
                  ),
                );
              },
              child: const Text('Open intro orbit'),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroOrbitHarness extends StatefulWidget {
  final AppShellController appShellController;
  final ValueListenable<int> feedUnreadCountListenable;

  const _IntroOrbitHarness({
    required this.appShellController,
    required this.feedUnreadCountListenable,
  });

  @override
  State<_IntroOrbitHarness> createState() => _IntroOrbitHarnessState();
}

class _IntroOrbitHarnessState extends State<_IntroOrbitHarness> {
  late final ValueNotifier<OrbitHeaderProjection> _headerNotifier;
  late final ValueNotifier<OrbitViewProjection> _listNotifier;
  late final ValueNotifier<Key?> _openRowNotifier;
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _headerNotifier = ValueNotifier<OrbitHeaderProjection>(
      const OrbitHeaderProjection(),
    );
    _listNotifier = ValueNotifier<OrbitViewProjection>(
      const OrbitViewProjection(filterTab: 'intros'),
    );
    _openRowNotifier = ValueNotifier<Key?>(null);
    _scrollController = ScrollController();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _headerNotifier.dispose();
    _listNotifier.dispose();
    _openRowNotifier.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSwitchView(String tab) {
    if (tab == AppShellTab.feed) {
      widget.appShellController.switchTo(AppShellTab.feed);
      Navigator.of(context).pop();
      return;
    }

    widget.appShellController.switchTo(tab);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return OrbitScreen(
      headerProjectionListenable: _headerNotifier,
      listProjectionListenable: _listNotifier,
      scrollController: _scrollController,
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      collapseAnimation: const AlwaysStoppedAnimation(1.0),
      searchDockAnimation: const AlwaysStoppedAnimation(0.0),
      searchTriggerAnimation: const AlwaysStoppedAnimation(1.0),
      onClose: () => Navigator.of(context).pop(),
      onFriendTap: (_) {},
      onSearchOpen: () {},
      onSearchClose: () {},
      onSearchChanged: (_) {},
      onSearchClear: () {},
      onFilterChanged: (_) {},
      onArchiveFriend: (_) {},
      onUnarchiveFriend: (_) {},
      onBlockFriend: (_) {},
      onUnblockFriend: (_) {},
      onDeleteFriend: (_) {},
      openRowNotifier: _openRowNotifier,
      onGroupTap: (_) {},
      onCreateGroup: (_) {},
      onArchiveGroup: (_) {},
      onUnarchiveGroup: (_) {},
      onLeaveGroup: (_) {},
      onDeleteGroup: (_) {},
      activeTab: widget.appShellController.activeTab,
      onSwitchView: _onSwitchView,
      feedUnreadCountListenable: widget.feedUnreadCountListenable,
    );
  }
}

ConversationMessage _unreadMessage({
  required String id,
  required String contactPeerId,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: contactPeerId,
    text: 'Unread $id',
    status: 'delivered',
    isIncoming: true,
    timestamp: DateTime.parse('2026-03-30T12:00:00Z').toIso8601String(),
    createdAt: DateTime.parse('2026-03-30T12:00:00Z').toIso8601String(),
  );
}
