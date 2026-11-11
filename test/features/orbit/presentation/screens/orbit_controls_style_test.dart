import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_control_circle.dart';
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

  // Owner follow-up 2026-11-11: the + glyph meets WCAG AA for a graphical
  // object (3:1) on the blue fill.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  for (final tone in {
    'dark': BackgroundReadableColors.dark,
    'light': BackgroundReadableColors.representativeLight,
  }.entries) {
    testWidgets('the + glyph has at least 3:1 contrast on ${tone.key}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [tone.value]),
          home: Scaffold(
            body: ExpandableFab(
              anchor: ExpandableFabAnchor.topRight,
              fabSize: OrbitControlCircle.size,
              filled: true,
              items: const [],
            ),
          ),
        ),
      );
      final visual = find.byKey(const ValueKey('expandable-fab-toggle-visual'));
      final fill = circleOf(tester, visual).color!;
      expect(fill, tone.value.ctaIcon, reason: 'the fill keeps the accent');
      final glyph = tester
          .widget<Icon>(
            find.descendant(of: visual, matching: find.byType(Icon)),
          )
          .color!;
      expect(glyph.a, 1.0, reason: 'an opaque glyph');
      final ratio = contrast(glyph, fill);
      // ignore: avoid_print
      print(
        '+ glyph ${tone.key}: $glyph on $fill = ${ratio.toStringAsFixed(2)}:1',
      );
      expect(ratio, greaterThanOrEqualTo(3.0));
    });
  }

  testWidgets('the calls control takes taps across its whole 44 px circle', (
    tester,
  ) async {
    phone(tester);
    var opened = 0;
    await tester.pumpWidget(
      buildOrbitScreenHarness(
        viewMode: OrbitViewMode.innerCircle,
        onToggleView: () {},
        onOpenCalls: () => opened++,
      ),
    );
    await settle(tester);

    final hit = tester.getRect(find.byKey(const ValueKey('orbit-calls')));
    expect(hit.size, const Size(44, 44));
    final circle = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('orbit-calls')),
        matching: find.byType(OrbitControlCircle),
        matchRoot: true,
      ),
    );
    expect(circle, hit, reason: 'the hit area is the drawn circle');
    for (final edge in [
      Offset(hit.left + 0.5, hit.center.dy),
      Offset(hit.right - 0.5, hit.center.dy),
      Offset(hit.center.dx, hit.top + 0.5),
      Offset(hit.center.dx, hit.bottom - 0.5),
    ]) {
      await tester.tapAt(edge);
      await tester.pump();
    }
    expect(opened, 4, reason: 'every edge of the circle opens calls');
    await tester.pump(const Duration(seconds: 2));
  });
}
