import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
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
    bool showLoadingPlaceholders = false,
    List<OrbitGroup> groups = const [],
  }) {
    final headerNotifier = ValueNotifier(const OrbitHeaderProjection());
    final listNotifier = ValueNotifier(
      OrbitViewProjection(
        groups: groups,
        mergedItems: groups.map(OrbitGroupItem.new).toList(),
        filterTab: filterTab,
        showLoadingPlaceholders: showLoadingPlaceholders,
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

  void suppressOverflowErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
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
  });
}
