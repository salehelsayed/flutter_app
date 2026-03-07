import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';

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
  }) {
    return MaterialApp(
      home: OrbitScreen(
        identity: null,
        allFriends: const [],
        displayedFriends: const [],
        searchActive: false,
        searchQuery: '',
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
        filterTab: filterTab,
        activeCount: 0,
        archivedCount: 0,
        onFilterChanged: (_) {},
        onArchiveFriend: (_) {},
        onUnarchiveFriend: (_) {},
        onBlockFriend: (_) {},
        onUnblockFriend: (_) {},
        onDeleteFriend: (_) {},
        openRowNotifier: openRowNotifier,
        groups: groups,
        onGroupTap: (_) {},
        onCreateGroup: (_) {},
        onArchiveGroup: (_) {},
        onUnarchiveGroup: (_) {},
        onDeleteGroup: (_) {},
        introsData: introsData,
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
      );

      await tester.pumpWidget(
        buildOrbitScreen(filterTab: 'intros', introsData: introsData),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.text('From Noor'), findsOneWidget);
      expect(find.text('Sarah'), findsOneWidget);
    });
  });
}
