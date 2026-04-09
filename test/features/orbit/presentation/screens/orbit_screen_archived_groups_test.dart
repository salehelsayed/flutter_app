import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_group_header.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';

void main() {
  late ValueNotifier<Key?> openRowNotifier;
  late ScrollController scrollController;
  late TextEditingController searchController;
  late FocusNode searchFocusNode;

  setUp(() {
    openRowNotifier = ValueNotifier(null);
    scrollController = ScrollController();
    searchController = TextEditingController();
    searchFocusNode = FocusNode();
  });

  tearDown(() {
    openRowNotifier.dispose();
    scrollController.dispose();
    searchController.dispose();
    searchFocusNode.dispose();
  });

  OrbitGroup makeGroup({
    required String id,
    required String name,
    bool isArchived = false,
  }) {
    return OrbitGroup(
      group: GroupModel(
        id: id,
        name: name,
        type: GroupType.chat,
        topicName: '/mknoon/group/$id',
        createdBy: 'creator',
        myRole: GroupRole.admin,
        createdAt: DateTime.now().toUtc(),
        isArchived: isArchived,
        archivedAt: isArchived ? DateTime.now().toUtc() : null,
      ),
      latestMessage: 'Hello from $name',
      lastActivityTimestamp: DateTime.now().toUtc(),
    );
  }

  Widget buildOrbitScreen({
    String filterTab = 'all',
    List<OrbitGroup> groups = const [],
    OrbitIntrosViewData? introsData,
    int introCount = 0,
    int pendingGroupInviteCount = 0,
    int? reviewCount,
  }) {
    final headerNotifier = ValueNotifier(const OrbitHeaderProjection());
    final effectiveReviewCount =
        reviewCount ?? introCount + pendingGroupInviteCount;
    final listNotifier = ValueNotifier(
      OrbitViewProjection(
        groups: groups,
        mergedItems: groups.map(OrbitGroupItem.new).toList(),
        introsData: introsData,
        filterTab: filterTab,
        introCount: introCount,
        pendingGroupInviteCount: pendingGroupInviteCount,
        reviewCount: effectiveReviewCount,
      ),
    );
    addTearDown(headerNotifier.dispose);
    addTearDown(listNotifier.dispose);
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OrbitScreen(
        headerProjectionListenable: headerNotifier,
        listProjectionListenable: listNotifier,
        scrollController: scrollController,
        searchController: searchController,
        searchFocusNode: searchFocusNode,
        collapseAnimation: const AlwaysStoppedAnimation(1.0),
        searchDockAnimation: const AlwaysStoppedAnimation(0.0),
        searchTriggerAnimation: const AlwaysStoppedAnimation(1.0),
        onClose: () {},
        onFriendTap: (_) {},
        onMyQR: () {},
        onScanQR: () {},
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
        openRowNotifier: openRowNotifier,
        onGroupTap: (_) {},
        onCreateGroup: (_) {},
        onArchiveGroup: (_) {},
        onUnarchiveGroup: (_) {},
        onDeleteGroup: (_) {},
      ),
    );
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

  group('OrbitScreen archived groups', () {
    // Use a phone-sized surface to avoid layout overflow in tests
    const testViewSize = Size(414, 896);

    testWidgets(
      'shows archived groups in archived tab even when no archived friends',
      (tester) async {
        suppressOverflowErrors();
        tester.view.physicalSize = testViewSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final archivedGroup = makeGroup(
          id: 'archived-group-1',
          name: 'Test Group',
          isArchived: true,
        );

        await tester.pumpWidget(
          buildOrbitScreen(filterTab: 'archived', groups: [archivedGroup]),
        );
        // Use pump instead of pumpAndSettle — OrbitalVisualization has looping animations
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(CustomScrollView), findsOneWidget);
        expect(find.byType(SingleChildScrollView), findsNothing);

        // The group card should be visible
        expect(find.text('Test Group'), findsOneWidget);

        // The empty state should NOT be shown
        expect(find.text('No archived friends yet'), findsNothing);
      },
    );

    testWidgets('shows empty state when no archived friends and no groups', (
      tester,
    ) async {
      suppressOverflowErrors();
      tester.view.physicalSize = testViewSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildOrbitScreen(filterTab: 'archived', groups: []),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No archived friends yet'), findsOneWidget);
    });

    testWidgets('shows groups in all tab', (tester) async {
      suppressOverflowErrors();
      tester.view.physicalSize = testViewSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final group = makeGroup(id: 'active-group-1', name: 'Active Group');

      await tester.pumpWidget(
        buildOrbitScreen(filterTab: 'all', groups: [group]),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Active Group'), findsOneWidget);
    });

    testWidgets('renders intros in the sliver list without nested ListView', (
      tester,
    ) async {
      suppressOverflowErrors();
      tester.view.physicalSize = testViewSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final introsData = OrbitIntrosViewData(
        groupedIntros: {
          'peer-noor': [
            IntroductionModel(
              id: 'intro-1',
              introducerId: 'peer-noor',
              recipientId: 'peer-me',
              introducedId: 'peer-sarah',
              introducerUsername: 'Noor',
              recipientUsername: 'Me',
              introducedUsername: 'Sarah',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        },
        introducerUsernames: const {'peer-noor': 'Noor'},
        ownPeerId: 'peer-me',
        onAccept: (_) {},
        onPass: (_) {},
        onDelete: (_) {},
      );

      await tester.pumpWidget(
        buildOrbitScreen(filterTab: 'intros', introsData: introsData),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final header = find.byType(IntroGroupHeader);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('From')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: header, matching: find.text('Noor')),
        findsOneWidget,
      );
      expect(find.text('Sarah'), findsOneWidget);
    });

    testWidgets(
      'intros tab renders grouped intros and carries the correct pending count',
      (tester) async {
        suppressOverflowErrors();
        tester.view.physicalSize = testViewSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final introsData = OrbitIntrosViewData(
          groupedIntros: {
            'peer-noor': [
              IntroductionModel(
                id: 'intro-1',
                introducerId: 'peer-noor',
                recipientId: 'peer-me',
                introducedId: 'peer-sarah',
                introducerUsername: 'Noor',
                recipientUsername: 'Me',
                introducedUsername: 'Sarah',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              ),
            ],
            'peer-layla': [
              IntroductionModel(
                id: 'intro-2',
                introducerId: 'peer-layla',
                recipientId: 'peer-me',
                introducedId: 'peer-dora',
                introducerUsername: 'Layla',
                recipientUsername: 'Me',
                introducedUsername: 'Dora',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              ),
            ],
          },
          introducerUsernames: const {
            'peer-noor': 'Noor',
            'peer-layla': 'Layla',
          },
          ownPeerId: 'peer-me',
          onAccept: (_) {},
          onPass: (_) {},
          onDelete: (_) {},
        );

        await tester.pumpWidget(
          buildOrbitScreen(
            filterTab: 'intros',
            introsData: introsData,
            introCount: 2,
            reviewCount: 2,
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(IntroGroupHeader), findsNWidgets(2));
        expect(find.text('Sarah'), findsOneWidget);
        expect(find.text('Dora'), findsOneWidget);

        final filterToggle = tester.widget<FriendsFilterToggle>(
          find.byType(FriendsFilterToggle),
        );
        expect(filterToggle.activeFilter, 'intros');
        expect(filterToggle.introsCount, 2);
      },
    );

    testWidgets('hides the intro banner when there are no pending review items',
        (tester) async {
      suppressOverflowErrors();
      tester.view.physicalSize = testViewSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildOrbitScreen(filterTab: 'all'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('item pending'), findsNothing);
      expect(
        find.text('Review and accept introductions to start chatting'),
        findsNothing,
      );
    });

    testWidgets('shows singular intro banner copy for one pending intro', (
      tester,
    ) async {
      suppressOverflowErrors();
      tester.view.physicalSize = testViewSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final introsData = OrbitIntrosViewData(
        groupedIntros: {
          'peer-noor': [
            IntroductionModel(
              id: 'intro-banner-one',
              introducerId: 'peer-noor',
              recipientId: 'peer-me',
              introducedId: 'peer-sarah',
              introducerUsername: 'Noor',
              recipientUsername: 'Me',
              introducedUsername: 'Sarah',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        },
        introducerUsernames: const {'peer-noor': 'Noor'},
        ownPeerId: 'peer-me',
        onAccept: (_) {},
        onPass: (_) {},
      );

      await tester.pumpWidget(
        buildOrbitScreen(
          filterTab: 'all',
          introsData: introsData,
          introCount: 1,
          reviewCount: 1,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('1 item pending'), findsOneWidget);
      expect(
        find.text('Review and accept introductions to start chatting'),
        findsOneWidget,
      );
    });

    testWidgets('shows plural intro banner copy for multiple pending intros', (
      tester,
    ) async {
      suppressOverflowErrors();
      tester.view.physicalSize = testViewSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final introsData = OrbitIntrosViewData(
        groupedIntros: {
          'peer-noor': [
            IntroductionModel(
              id: 'intro-banner-two',
              introducerId: 'peer-noor',
              recipientId: 'peer-me',
              introducedId: 'peer-sarah',
              introducerUsername: 'Noor',
              recipientUsername: 'Me',
              introducedUsername: 'Sarah',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
            IntroductionModel(
              id: 'intro-banner-three',
              introducerId: 'peer-noor',
              recipientId: 'peer-me',
              introducedId: 'peer-dora',
              introducerUsername: 'Noor',
              recipientUsername: 'Me',
              introducedUsername: 'Dora',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
            IntroductionModel(
              id: 'intro-banner-four',
              introducerId: 'peer-noor',
              recipientId: 'peer-me',
              introducedId: 'peer-yara',
              introducerUsername: 'Noor',
              recipientUsername: 'Me',
              introducedUsername: 'Yara',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        },
        introducerUsernames: const {'peer-noor': 'Noor'},
        ownPeerId: 'peer-me',
        onAccept: (_) {},
        onPass: (_) {},
      );

      await tester.pumpWidget(
        buildOrbitScreen(
          filterTab: 'all',
          introsData: introsData,
          introCount: 3,
          reviewCount: 3,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('3 items pending'), findsOneWidget);
      expect(
        find.text('Review and accept introductions to start chatting'),
        findsOneWidget,
      );
    });

    testWidgets('live intro row reveals delete on swipe', (tester) async {
      suppressOverflowErrors();
      tester.view.physicalSize = testViewSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var deleteCalled = false;
      final introsData = OrbitIntrosViewData(
        groupedIntros: {
          'peer-noor': [
            IntroductionModel(
              id: 'intro-delete',
              introducerId: 'peer-noor',
              recipientId: 'peer-me',
              introducedId: 'peer-sarah',
              introducerUsername: 'Noor',
              recipientUsername: 'Me',
              introducedUsername: 'Sarah',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        },
        introducerUsernames: const {'peer-noor': 'Noor'},
        ownPeerId: 'peer-me',
        onAccept: (_) {},
        onPass: (_) {},
        onDelete: (_) => deleteCalled = true,
      );

      await tester.pumpWidget(
        buildOrbitScreen(filterTab: 'intros', introsData: introsData),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final center = tester.getCenter(find.text('Sarah'));
      await tester.dragFrom(center, const Offset(-140, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);

      await tester.tap(find.text('Delete'));
      await tester.pump();

      expect(deleteCalled, isTrue);
    });
  });
}
