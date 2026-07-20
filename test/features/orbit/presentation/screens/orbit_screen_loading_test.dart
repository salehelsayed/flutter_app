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
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_dock.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
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
    OrbitViewMode viewMode = OrbitViewMode.allChats,
  }) {
    final mergedItems = <OrbitItem>[
      ...friends.map(OrbitFriendItem.new),
      ...groups.map(OrbitGroupItem.new),
    ];
    final effectiveReviewCount =
        reviewCount ?? introCount + pendingGroupInviteCount;
    final headerNotifier = ValueNotifier(
      // 197: the Inner-Circle surface renders the merged friends+groups
      // `innerItems`; `allFriends` still feeds the friend-only search badge.
      OrbitHeaderProjection(allFriends: friends, innerItems: mergedItems),
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
        onLeaveGroup: (_) {},
        onDeleteGroup: (_) {},
        viewMode: viewMode,
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

    testWidgets(
      'daylight lagoon keeps visible orbit content readable and TC-203-16 '
      'all-chats view renders no Close Friends header text',
      (tester) async {
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

        // 203 B5: the 'Close Friends' header text was removed from the
        // all-chats view (with the FriendsListHeader widget itself).
        expect(find.text('Close Friends'), findsNothing);

        final chevronIcons = tester.widgetList<Icon>(
          find.byIcon(Icons.chevron_right),
        );
        expect(
          chevronIcons.map((icon) => icon.color),
          contains(colors.iconMuted),
        );
      },
    );

    testWidgets(
      'TC-203-15 Inner-Circle view: no Close Friends caption, no search '
      'affordance (daylight)',
      (tester) async {
        suppressOverflowErrors();
        suppressNavAssetErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(
            viewMode: OrbitViewMode.innerCircle,
            backgroundPreference: BackgroundPreference.daylightLagoon,
            friends: [
              makeFriend(
                id: 'friend-1',
                username: 'Riley Lagoon',
                lastActivity: 'مرحبا from a bright background',
              ),
            ],
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(DaylightLagoonBackground), findsOneWidget);

        // 203 B5: the Inner-Circle caption was removed with its ARB key, and
        // still no all-chats search affordance is mounted on this view.
        expect(find.text('Close Friends'), findsNothing);
        expect(find.byType(OrbitSearchTrigger), findsNothing);
      },
    );

    testWidgets(
      'TC-197-11: inner-circle surface seats a provided group as a ring node',
      (tester) async {
        suppressOverflowErrors();
        suppressNavAssetErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(
            viewMode: OrbitViewMode.innerCircle,
            friends: [makeFriend(id: 'f-1', username: 'Riley')],
            groups: [makeGroup(id: 'g-1', name: 'Alpha Group')],
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // The header carries the merged group (innerItems), so the Inner-Circle
        // visualization seats it as a GroupAvatar ring node.
        expect(find.byType(OrbitalVisualization), findsOneWidget);
        expect(find.byType(GroupAvatar), findsOneWidget);
      },
    );

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

        expect(find.byType(OrbitCloseButton), findsOneWidget);
        expect(find.byType(OrbitSearchTrigger), findsOneWidget);
        expect(find.byType(ExpandableFab), findsOneWidget);
      },
    );

    testWidgets(
      'TC-212-12 persistent nav centers the bar; the search trigger rides '
      'the nav line at the right edge, with content above the nav',
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

        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        final navRect = tester.getRect(find.byType(FeedNavigationBar));
        final searchRect = tester.getRect(find.byType(OrbitSearchTrigger));
        final lastGroupRect = tester.getRect(find.text('Group 15'));

        // The redundant X close button is removed in persistent mode — the
        // Feed tab is the way back.
        expect(find.byType(OrbitCloseButton), findsNothing);
        // The trigger rides the nav bar's vertical level at the physical
        // right edge (inset 16), beside the centered bar.
        expect(searchRect.right, screen.width - 16);
        expect(searchRect.center.dy, closeTo(navRect.center.dy, 1.0));
        // The bar keeps the horizontal center without the inline trigger slot.
        expect(navRect.center.dx, closeTo(screen.width / 2, 1.0));
        // Scrolled content stays above the nav bar.
        expect(lastGroupRect.bottom, lessThanOrEqualTo(navRect.top));
      },
    );

    testWidgets('search dock lifts above the persistent nav', (tester) async {
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

      // No close button in persistent mode; the dock simply clears the nav.
      expect(find.byType(OrbitCloseButton), findsNothing);
      expect(searchDockRect.bottom, lessThanOrEqualTo(navRect.top));
    });

    testWidgets(
      'TC-201-04 expanded find pill is full-width and clears the persistent nav',
      (tester) async {
        suppressOverflowErrors();
        suppressNavAssetErrors();
        setPhoneSurface(tester);

        await tester.pumpWidget(
          buildOrbitScreen(
            viewMode: OrbitViewMode.innerCircle,
            activeTab: 'orbit',
            onSwitchView: (_) {},
            feedUnreadCountListenable: ValueNotifier<int>(0),
            friends: [makeFriend(id: 'f-1', username: 'Riley')],
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Open the find pill on the inner-circle surface.
        await tester.tap(
          find.byKey(const ValueKey('orbit-find-pill')),
          warnIfMissed: false,
        );
        await tester.pump();

        final screen = tester.getRect(find.byType(OrbitScreen));
        final pill = tester.getRect(
          find.byKey(const ValueKey('orbit-find-pill')),
        );
        // HEAD-red: on HEAD the expanded pill is a 200px right-anchored box,
        // not a full-width bar.
        expect(
          pill.left - screen.left,
          closeTo(16, 2),
          reason: 'expanded pill spans full width (left inset 16)',
        );
        expect(
          screen.right - pill.right,
          closeTo(16, 2),
          reason: 'expanded pill spans full width (right inset 16)',
        );
        // Nav-clearance: the widened pill must not sit under the persistent nav
        // band at zero safe-area (needs the bottomClearance wiring).
        final nav = tester.getRect(find.byType(FeedNavigationBar));
        expect(
          pill.overlaps(nav),
          isFalse,
          reason: 'the pill clears the persistent Feed/Orbit nav band',
        );
      },
    );
  });
}
