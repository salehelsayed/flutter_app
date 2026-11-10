import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/services/fake_p2p_service.dart';
import 'orbit_screen_pump_harness.dart';

// Owner request 2026-11-10: every round Orbit control is the same 44 px
// circle with a hairline border and faint fill; only the + is filled, with no
// glow. The Online pill takes the same hairline and faint fill.
void main() {
  const hairline = Color(0x24FFFFFF);
  const faintFill = Color(0x0AFFFFFF);
  const onlineState = NodeState(
    isStarted: true,
    relayState: 'offline',
    sendCapabilityReady: true,
    inboxCapabilityReady: true,
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(414, 896);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('overflowed') || msg.contains('Unable to load asset')) {
        return;
      }
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
  }

  BoxDecoration circleOf(WidgetTester tester, Finder control) {
    Iterable<BoxDecoration> circles(Finder f) => tester
        .widgetList<DecoratedBox>(f)
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle);
    final inside = circles(
      find.descendant(
        of: control,
        matching: find.byType(DecoratedBox),
        matchRoot: true,
      ),
    );
    if (inside.isNotEmpty) return inside.first;
    return circles(
      find.ancestor(of: control, matching: find.byType(DecoratedBox)),
    ).first;
  }

  void expectOutlined(WidgetTester tester, String name, Finder control) {
    final d = circleOf(tester, control);
    expect(
      (d.border as Border?)?.top,
      const BorderSide(color: hairline),
      reason: '$name hairline',
    );
    expect(d.color, faintFill, reason: '$name faint fill');
    expect(d.boxShadow, isNull, reason: '$name has no shadow');
  }

  testWidgets('top row and nav line controls are 44 px circles', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      buildOrbitScreenHarness(
        viewMode: OrbitViewMode.innerCircle,
        onToggleView: () {},
        onOpenCalls: () {},
        onOpenSettings: () {},
        activeTab: 'orbit',
        onSwitchView: (_) {},
      ),
    );
    await settle(tester);

    final outlined = {
      'chat list': find.byKey(const ValueKey('orbit-view-toggle')),
      'calls': find.byKey(const ValueKey('orbit-calls')),
      'settings': find.byKey(const ValueKey('orbit-settings-button')),
      'find': find.byKey(const ValueKey('orbit-find-pill')),
    };
    final add = find.byKey(const ValueKey('expandable-fab-toggle-visual'));
    final sizes = {
      for (final e in {...outlined, 'add': add}.entries)
        e.key: tester.getSize(e.value),
    };
    expect(sizes, {
      'chat list': const Size(44, 44),
      'calls': const Size(44, 44),
      'settings': const Size(44, 44),
      'find': const Size(44, 44),
      'add': const Size(44, 44),
    });
    for (final e in outlined.entries) {
      expectOutlined(tester, e.key, e.value);
    }

    final plus = circleOf(tester, add);
    expect(plus.color, BackgroundReadableColors.dark.ctaIcon);
    expect(plus.border, isNull);
    expect(plus.boxShadow, isNull);
  });

  testWidgets('standalone search and close controls are 44 px circles', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      buildOrbitScreenHarness(
        viewMode: OrbitViewMode.allChats,
        onToggleView: () {},
        searchTriggerAnimation: const AlwaysStoppedAnimation<double>(1),
      ),
    );
    await settle(tester);

    final search = find.byType(OrbitSearchTrigger);
    final close = find.byType(OrbitCloseButton);
    expect(tester.getSize(search), const Size(44, 44));
    expect(tester.getSize(close), const Size(44, 44));
    expectOutlined(tester, 'search', search);
    expectOutlined(tester, 'close', close);
    expect(
      find.descendant(of: search, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
  });

  testWidgets('the Online pill is a 32 px hairline capsule with a green dot', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      buildOrbitScreenHarness(
        viewMode: OrbitViewMode.innerCircle,
        onToggleView: () {},
        p2pService: FakeP2PService(initialState: onlineState),
      ),
    );
    await settle(tester);

    final pill = find.byType(ConnectionStatusIndicator);
    final capsule = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: pill, matching: find.byType(DecoratedBox)),
        )
        .map((d) => d.decoration as BoxDecoration)
        .toList();
    expect(capsule.first.border, Border.all(color: hairline));
    expect(capsule.first.color, faintFill);
    expect(
      capsule.any((d) => d.color == const Color(0xFF1DB954)),
      isTrue,
      reason: 'the 8 px status dot is the unread green',
    );
    final capsuleBox = find
        .descendant(of: pill, matching: find.byType(DecoratedBox))
        .first;
    expect(tester.getSize(capsuleBox).height, 32);
    final label = tester.widget<Text>(find.text('Online'));
    expect(label.style!.fontSize, 13);
    expect(label.style!.fontWeight, FontWeight.w500);
  });
}
