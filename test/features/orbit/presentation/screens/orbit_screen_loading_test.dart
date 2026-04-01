import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_dock.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';

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
    bool searchActive = false,
    bool showLoadingPlaceholders = false,
    List<OrbitGroup> groups = const [],
    ValueNotifier<int>? feedUnreadCountListenable,
    String? activeTab,
    void Function(String)? onSwitchView,
    Animation<double> searchDockAnimation = const AlwaysStoppedAnimation(0.0),
    Animation<double> searchTriggerAnimation = const AlwaysStoppedAnimation(1.0),
  }) {
    final headerNotifier = ValueNotifier(const OrbitHeaderProjection());
    final listNotifier = ValueNotifier(
      OrbitViewProjection(
        groups: groups,
        mergedItems: groups.map(OrbitGroupItem.new).toList(),
        filterTab: filterTab,
        searchActive: searchActive,
        showLoadingPlaceholders: showLoadingPlaceholders,
      ),
    );
    addTearDown(headerNotifier.dispose);
    addTearDown(listNotifier.dispose);
    if (feedUnreadCountListenable != null) {
      addTearDown(feedUnreadCountListenable.dispose);
    }
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
        searchDockAnimation: searchDockAnimation,
        searchTriggerAnimation: searchTriggerAnimation,
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
        activeTab: activeTab,
        onSwitchView: onSwitchView,
        feedUnreadCountListenable: feedUnreadCountListenable,
      ),
    );
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

  void setPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(414, 896);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('OrbitScreen loading placeholders', () {
    testWidgets(
      'renders loading placeholders while all tab is still hydrating',
      (tester) async {
        suppressOverflowErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(showLoadingPlaceholders: true),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const ValueKey('orbit-loading-row-0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('orbit-loading-row-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('orbit-loading-row-2')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'renders archived loading placeholders when archived tab is selected and archived data is not ready',
      (tester) async {
        suppressOverflowErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(
            filterTab: 'archived',
            showLoadingPlaceholders: true,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const ValueKey('orbit-loading-row-0')),
          findsOneWidget,
        );
        expect(find.text('No archived friends yet'), findsNothing);
      },
    );

    testWidgets(
      'does not render placeholders after real orbit items are available',
      (tester) async {
        suppressOverflowErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(
            showLoadingPlaceholders: true,
            groups: [makeGroup(id: 'g-1', name: 'Active Group')],
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const ValueKey('orbit-loading-row-0')), findsNothing);
        expect(find.text('Active Group'), findsOneWidget);
      },
    );

    testWidgets(
      'keeps orbit chrome visible while loading placeholders are shown',
      (tester) async {
        suppressOverflowErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(showLoadingPlaceholders: true),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Close Friends'), findsWidgets);
        expect(find.byType(OrbitCloseButton), findsOneWidget);
        expect(find.byType(OrbitSearchTrigger), findsOneWidget);
        expect(find.byType(ExpandableFab), findsOneWidget);
      },
    );

    testWidgets(
      'persistent nav keeps bottom chrome and scrolled content above the bar',
      (tester) async {
        suppressOverflowErrors();
        suppressNavAssetErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(
            groups: List.generate(
              16,
              (index) => makeGroup(id: 'g-$index', name: 'Group $index'),
            ),
            activeTab: 'orbit',
            onSwitchView: (_) {},
            feedUnreadCountListenable: ValueNotifier<int>(4),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));

        final navRect = tester.getRect(find.byType(FeedNavigationBar));
        final closeRect = tester.getRect(find.byType(OrbitCloseButton));
        final searchRect = tester.getRect(find.byType(OrbitSearchTrigger));
        final lastGroupRect = tester.getRect(find.text('Group 15'));

        expect(closeRect.bottom, lessThanOrEqualTo(navRect.top));
        expect(searchRect.bottom, lessThanOrEqualTo(closeRect.top));
        expect(lastGroupRect.bottom, lessThanOrEqualTo(navRect.top));
      },
    );

    testWidgets(
      'search dock lifts above the persistent nav and leaves the close button clear',
      (tester) async {
        suppressOverflowErrors();
        suppressNavAssetErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(
            searchActive: true,
            activeTab: 'orbit',
            onSwitchView: (_) {},
            feedUnreadCountListenable: ValueNotifier<int>(2),
            searchDockAnimation: const AlwaysStoppedAnimation(1.0),
            searchTriggerAnimation: const AlwaysStoppedAnimation(0.0),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final navRect = tester.getRect(find.byType(FeedNavigationBar));
        final searchDockRect = tester.getRect(find.byType(OrbitSearchDock));
        final closeRect = tester.getRect(find.byType(OrbitCloseButton));

        expect(searchDockRect.bottom, lessThanOrEqualTo(navRect.top));
        expect(closeRect.bottom, lessThanOrEqualTo(searchDockRect.top));
      },
    );
  });
}
