import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_dock.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

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

  OrbitFriend makeFriend({
    required String id,
    required String username,
    String lastActivity = 'See you near the lagoon',
  }) {
    return OrbitFriend(
      contact: ContactModel(
        peerId: id,
        publicKey: 'public-key-$id',
        rendezvous: '/ip4/127.0.0.1/tcp/4001/p2p/$id',
        username: username,
        signature: 'signature-$id',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ),
      messageCount: 6,
      lastActivity: lastActivity,
      lastMessageTimestamp: DateTime.now().toUtc().toIso8601String(),
      unreadCount: 3,
    );
  }

  Widget buildOrbitScreen({
    String filterTab = 'all',
    bool searchActive = false,
    bool showLoadingPlaceholders = false,
    List<OrbitFriend> friends = const [],
    List<OrbitGroup> groups = const [],
    ValueNotifier<int>? feedUnreadCountListenable,
    String? activeTab,
    void Function(String)? onSwitchView,
    Animation<double> searchDockAnimation = const AlwaysStoppedAnimation(0.0),
    Animation<double> searchTriggerAnimation = const AlwaysStoppedAnimation(
      1.0,
    ),
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
    BackgroundReadableTone? readableToneOverride,
    OrbitIntrosViewData? introsData,
    int introCount = 0,
    int pendingGroupInviteCount = 0,
    int? reviewCount,
  }) {
    final mergedItems = <OrbitItem>[
      ...friends.map(OrbitFriendItem.new),
      ...groups.map(OrbitGroupItem.new),
    ];
    final effectiveReviewCount =
        reviewCount ?? introCount + pendingGroupInviteCount;
    final headerNotifier = ValueNotifier(
      OrbitHeaderProjection(allFriends: friends),
    );
    final listNotifier = ValueNotifier(
      OrbitViewProjection(
        allFriends: friends,
        displayedFriends: friends,
        groups: groups,
        mergedItems: mergedItems,
        activeCount: mergedItems.length,
        introCount: introCount,
        pendingGroupInviteCount: pendingGroupInviteCount,
        reviewCount: effectiveReviewCount,
        introsData: introsData,
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
        backgroundPreference: backgroundPreference,
        readableToneOverride: readableToneOverride,
      ),
    );
  }

  Color? textColorFor(WidgetTester tester, String label) {
    return tester.widget<Text>(find.text(label).first).style?.color;
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
      'loading placeholders use representative light readable roles',
      (tester) async {
        suppressOverflowErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(
            showLoadingPlaceholders: true,
            readableToneOverride: BackgroundReadableTone.representativeLight,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final loadingRow = tester.widget<Container>(
          find.byKey(const ValueKey('orbit-loading-row-0')),
        );
        final decoration = loadingRow.decoration as BoxDecoration;
        expect(
          decoration.color,
          BackgroundReadableColors.representativeLight.surfaceSubtle,
        );
      },
    );

    testWidgets(
      'daylight lagoon uses light readable roles for loading placeholders',
      (tester) async {
        suppressOverflowErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(
            showLoadingPlaceholders: true,
            backgroundPreference: BackgroundPreference.daylightLagoon,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(DaylightLagoonBackground), findsOneWidget);

        final loadingRow = tester.widget<Container>(
          find.byKey(const ValueKey('orbit-loading-row-0')),
        );
        final decoration = loadingRow.decoration as BoxDecoration;
        expect(
          decoration.color,
          BackgroundReadableColors.representativeLight.surfaceSubtle,
        );
      },
    );

    testWidgets('daylight lagoon keeps visible orbit content readable', (
      tester,
    ) async {
      suppressOverflowErrors();
      suppressNavAssetErrors();
      setPhoneSurface(tester);

      await tester.pumpWidget(
        buildOrbitScreen(
          backgroundPreference: BackgroundPreference.daylightLagoon,
          friends: [
            makeFriend(
              id: 'friend-1',
              username: 'Riley Lagoon',
              lastActivity: 'مرحبا from a bright background',
            ),
          ],
          groups: [makeGroup(id: 'g-readable', name: 'Readable Group')],
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(DaylightLagoonBackground), findsOneWidget);
      expect(find.text('Riley Lagoon'), findsOneWidget);
      expect(find.text('Readable Group'), findsOneWidget);

      final colors = BackgroundReadableColors.representativeLight;
      expectTextContrast(
        textColorFor(tester, 'Riley Lagoon')!,
        colors.surfaceSubtle,
      );
      expectTextContrast(
        textColorFor(tester, 'Readable Group')!,
        colors.surfaceSubtle,
      );
      expectTextContrast(
        textColorFor(tester, 'مرحبا from a bright background')!,
        colors.surfaceSubtle,
      );

      final closeFriendColors = tester
          .widgetList<Text>(find.text('Close Friends'))
          .map((text) => text.style?.color)
          .whereType<Color>()
          .toSet();
      expect(closeFriendColors, contains(colors.textPrimary));
      expect(closeFriendColors, contains(colors.textMuted));

      final chevronIcons = tester.widgetList<Icon>(
        find.byIcon(Icons.chevron_right),
      );
      expect(
        chevronIcons.map((icon) => icon.color),
        contains(colors.iconMuted),
      );
    });

    testWidgets('daylight lagoon keeps intro list content readable', (
      tester,
    ) async {
      suppressOverflowErrors();
      suppressNavAssetErrors();
      setPhoneSurface(tester);

      final intro = IntroductionModel(
        id: 'intro-light-readable',
        introducerId: 'peer-noor',
        recipientId: 'peer-me',
        introducedId: 'peer-riley',
        introducerUsername: 'Noor',
        recipientUsername: 'Me',
        introducedUsername: 'Riley Intro',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      final introsData = OrbitIntrosViewData(
        groupedIntros: {
          'peer-noor': [intro],
        },
        introducerUsernames: const {'peer-noor': 'Noor'},
        ownPeerId: 'peer-me',
        onAccept: (_) {},
        onPass: (_) {},
      );

      await tester.pumpWidget(
        buildOrbitScreen(
          filterTab: 'intros',
          backgroundPreference: BackgroundPreference.daylightLagoon,
          introsData: introsData,
          introCount: 1,
          reviewCount: 1,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(DaylightLagoonBackground), findsOneWidget);
      expect(find.text('Riley Intro'), findsOneWidget);
      expect(find.text('Introduced by'), findsOneWidget);

      final colors = BackgroundReadableColors.representativeLight;
      final introNameColor = textColorFor(tester, 'Riley Intro')!;
      final attributionColor = textColorFor(tester, 'Introduced by')!;
      final headerColor = textColorFor(tester, 'From')!;

      expect(introNameColor, colors.textPrimary);
      expect(attributionColor, colors.textMuted);
      expect(headerColor, colors.textSecondary);
      expectTextContrast(introNameColor, colors.surfaceSubtle);
      expectTextContrast(attributionColor, colors.surfaceSubtle);
      expectTextContrast(headerColor, Colors.white);
    });

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

        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -2400),
        );
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
