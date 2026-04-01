import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/main.dart' show openIntroNotificationOrbitRoute;

import '../../conversation/domain/repositories/fake_message_repository.dart';

void main() {
  late AppShellController appShellController;
  late FakeMessageRepository messageRepository;

  setUp(() {
    appShellController = AppShellController();
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
    'closing intro notification orbit while still on orbit restores the prior shell tab',
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
      expect(find.byType(OrbitCloseButton), findsOneWidget);

      await tester.tap(find.byType(OrbitCloseButton));
      await pumpRouteTransition(tester);

      expect(appShellController.activeTab, AppShellTab.feed);
      expect(find.text('Open intro orbit'), findsOneWidget);
    },
  );
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
      openRowNotifier: _openRowNotifier,
      onGroupTap: (_) {},
      onCreateGroup: (_) {},
      onArchiveGroup: (_) {},
      onUnarchiveGroup: (_) {},
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
