import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';

late final IntegrationTestWidgetsFlutterBinding binding;

const Duration _frameStep = Duration(milliseconds: 16);
const int _openFrames = 40; // ~640ms > 420ms route push transition.
const int _closeFrames = 24; // ~384ms > 280ms reverse transition.
const int _badgeFrames = 78; // ~1248ms covers 1000ms delay + animation start.

class _OrbitScenario {
  const _OrbitScenario({
    required this.id,
    required this.friends,
    required this.expectOverflow,
  });

  final String id;
  final List<OrbitFriend> friends;
  final bool expectOverflow;
}

OrbitFriend _makeFriend(int i) {
  return OrbitFriend(
    contact: ContactModel(
      peerId: 'orbit-peer-$i',
      publicKey: 'pk-$i',
      rendezvous: '/dns4/example.com/tcp/${4000 + i}',
      username: 'friend$i',
      signature: 'sig-$i',
      scannedAt: '2026-03-26T00:00:00Z',
    ),
    messageCount: 50 - i,
  );
}

class _OrbitHost extends StatefulWidget {
  const _OrbitHost({super.key, required this.scenario});

  final _OrbitScenario scenario;

  @override
  State<_OrbitHost> createState() => _OrbitHostState();
}

class _OrbitHostState extends State<_OrbitHost> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void openOrbit() {
    final navigator = navigatorKey.currentState!;
    unawaited(
      navigator.push<void>(
        buildOrbitSlideUpRoute<void>(
          builder: (_) => _OrbitRouteScreen(friends: widget.scenario.friends),
        ),
      ),
    );
  }

  void closeOrbit() {
    navigatorKey.currentState!.pop();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: Center(child: Text('Orbit Perf Home')),
      ),
    );
  }
}

class _OrbitRouteScreen extends StatefulWidget {
  const _OrbitRouteScreen({required this.friends});

  final List<OrbitFriend> friends;

  @override
  State<_OrbitRouteScreen> createState() => _OrbitRouteScreenState();
}

class _OrbitRouteScreenState extends State<_OrbitRouteScreen> {
  late final ValueNotifier<Key?> _openRowNotifier;
  late final ValueNotifier<OrbitHeaderProjection> _headerNotifier;
  late final ValueNotifier<OrbitViewProjection> _listNotifier;
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _openRowNotifier = ValueNotifier<Key?>(null);
    _headerNotifier = ValueNotifier<OrbitHeaderProjection>(
      OrbitHeaderProjection(
        userPeerId: 'self-peer',
        allFriends: List<OrbitFriend>.unmodifiable(widget.friends),
      ),
    );
    _listNotifier = ValueNotifier<OrbitViewProjection>(
      const OrbitViewProjection(filterTab: 'all'),
    );
    _scrollController = ScrollController();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _openRowNotifier.dispose();
    _headerNotifier.dispose();
    _listNotifier.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
      onClose: () => Navigator.of(context).maybePop(),
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
    );
  }
}

Future<void> _pumpFrames(WidgetTester tester, {required int count}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frameStep);
  }
}

Future<void> _pumpHost(WidgetTester tester, _OrbitScenario scenario) async {
  await tester.pumpWidget(
    _OrbitHost(
      key: ValueKey('host-${scenario.id}'),
      scenario: scenario,
    ),
  );
  await _pumpFrames(tester, count: 10);
  expect(find.text('Orbit Perf Home'), findsOneWidget);
}

Future<void> _runScenario(
  WidgetTester tester,
  _OrbitScenario scenario,
) async {
  final hostState = tester.state<_OrbitHostState>(find.byType(_OrbitHost));

  developer.Timeline.instantSync(
    'orbit_perf_phase',
    arguments: {'scenario': scenario.id, 'phase': 'push_start'},
  );
  hostState.openOrbit();
  await tester.pump();
  await _pumpFrames(tester, count: _openFrames);
  expect(find.byType(OrbitScreen), findsOneWidget);

  if (scenario.expectOverflow) {
    expect(find.byType(OverflowBadge), findsOneWidget);
    developer.Timeline.instantSync(
      'orbit_perf_phase',
      arguments: {'scenario': scenario.id, 'phase': 'badge_delay_window'},
    );
    await _pumpFrames(tester, count: _badgeFrames);
  } else {
    expect(find.byType(OverflowBadge), findsNothing);
  }

  developer.Timeline.instantSync(
    'orbit_perf_phase',
    arguments: {'scenario': scenario.id, 'phase': 'pop_start'},
  );
  hostState.closeOrbit();
  await tester.pump();
  await _pumpFrames(tester, count: _closeFrames);
  expect(find.byType(OrbitScreen), findsNothing);
}

Map<String, dynamic> _timelineEventSummary(Map<String, dynamic> timeline) {
  final events = (timeline['traceEvents'] as List<dynamic>? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
  int countContains(String needle) => events
      .where((event) => '${event['name'] ?? ''}'.contains(needle))
      .length;

  final interestingNames = events
      .map((event) => '${event['name'] ?? ''}')
      .where(
        (name) =>
            name.contains('RenderCustomPaint') ||
            name.contains('BackdropFilter') ||
            name.contains('ShaderMask') ||
            name.contains('SceneDisplayLag') ||
            name.contains('orbit_perf_phase'),
      )
      .toSet()
      .toList()
    ..sort();

  return <String, dynamic>{
    'eventCount': events.length,
    'customPaintEvents': countContains('RenderCustomPaint'),
    'backdropFilterEvents': countContains('BackdropFilter'),
    'shaderMaskEvents': countContains('ShaderMask'),
    'phaseMarkerEvents': countContains('orbit_perf_phase'),
    'interestingEventNames': interestingNames,
  };
}

void _printReportEntry(String key) {
  final data = binding.reportData?[key];
  if (data == null) {
    debugPrint('[$key] report entry missing');
    return;
  }
  debugPrint('[$key] ${jsonEncode(data)}');
}

Future<void> _captureScenario(
  WidgetTester tester, {
  required _OrbitScenario scenario,
}) async {
  final perfKey = '${scenario.id}_performance';
  final timelineKey = '${scenario.id}_timeline';
  final timelineSummaryKey = '${scenario.id}_timeline_summary';

  await _pumpHost(tester, scenario);
  await binding.watchPerformance(
    () async => _runScenario(tester, scenario),
    reportKey: perfKey,
  );
  _printReportEntry(perfKey);

  await _pumpHost(tester, scenario);
  await binding.traceAction(
    () async => _runScenario(tester, scenario),
    reportKey: timelineKey,
    streams: const <String>['all'],
  );

  final timeline = binding.reportData?[timelineKey] as Map<String, dynamic>;
  final timelineSummary = _timelineEventSummary(timeline);
  binding.reportData ??= <String, dynamic>{};
  binding.reportData![timelineSummaryKey] = timelineSummary;
  _printReportEntry(timelineSummaryKey);
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final originalDebugProfilePaintsEnabled = debugProfilePaintsEnabled;
  debugProfilePaintsEnabled = true;

  tearDown(() {
    debugProfilePaintsEnabled = originalDebugProfilePaintsEnabled;
  });

  const noOverflow = _OrbitScenario(
    id: 'orbit_open_close_no_overflow',
    friends: <OrbitFriend>[
      // 8 keeps the second ring populated without triggering OverflowBadge.
      // The actual friend objects are expanded below for const-safety reasons.
    ],
    expectOverflow: false,
  );

  const withOverflow = _OrbitScenario(
    id: 'orbit_open_idle_badge_close_with_overflow',
    friends: <OrbitFriend>[
      // 15 triggers OverflowBadge and exercises the delayed badge animation.
    ],
    expectOverflow: true,
  );

  final scenarios = <_OrbitScenario>[
    _OrbitScenario(
      id: noOverflow.id,
      friends: List<OrbitFriend>.generate(8, _makeFriend),
      expectOverflow: false,
    ),
    _OrbitScenario(
      id: withOverflow.id,
      friends: List<OrbitFriend>.generate(15, _makeFriend),
      expectOverflow: true,
    ),
  ];

  testWidgets('captures Orbit route performance evidence', (tester) async {
    debugProfilePaintsEnabled = true;
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['orbit_perf_meta'] = <String, dynamic>{
      'routeTransition': 'buildOrbitSlideUpRoute',
      'openFrames': _openFrames,
      'closeFrames': _closeFrames,
      'badgeFrames': _badgeFrames,
      'usesOverflowScenario': true,
      'usesNoOverflowScenario': true,
    };

    for (final scenario in scenarios) {
      await _captureScenario(tester, scenario: scenario);
    }

    debugProfilePaintsEnabled = originalDebugProfilePaintsEnabled;
    expect(binding.reportData, isNotNull);
  });
}
