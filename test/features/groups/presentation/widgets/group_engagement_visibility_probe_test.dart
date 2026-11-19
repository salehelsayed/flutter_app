import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/presentation/widgets/group_engagement_visibility_probe.dart';

const _item = ValueKey('incoming-unlocked-content');

Widget _probe(
  VoidCallback onVisible, {
  bool eligible = true,
  Key key = _item,
}) => GroupEngagementVisibilityProbe(
  key: key,
  eligible: eligible,
  onVisible: onVisible,
  child: const SizedBox(width: 80, height: 80),
);

Widget _page(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _PaintRecorder extends CustomPainter {
  _PaintRecorder(this.events);
  final List<String> events;

  @override
  void paint(Canvas canvas, Size size) {
    events.add('paint');
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(_PaintRecorder oldDelegate) => true;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('B15GF pending old frame cannot use a later owner', (
    tester,
  ) async {
    var owner = Object();
    final later = Object();
    final marks = <Object>[];
    GroupEngagementFrameObservation snapshot() {
      final captured = owner;
      return (binding: captured, onVisible: () => marks.add(captured));
    }

    await tester
        .pumpWidget(
          _page(
            GroupEngagementVisibilityProbe(
              key: _item,
              eligible: true,
              onVisible: () {},
              frameObservation: snapshot,
              child: const SizedBox(width: 80, height: 80),
            ),
          ),
        )
        .timeout(const Duration(seconds: 3));
    expect(marks, isEmpty);
    owner = later;
    await tester
        .pump(const Duration(milliseconds: 16))
        .timeout(const Duration(seconds: 3));
    expect(
      marks,
      isEmpty,
      reason: 'The old painted frame is not rebound to the later owner',
    );
    await _frames(tester).timeout(const Duration(seconds: 3));
    expect(marks, hasLength(1));
    expect(identical(marks.single, later), isTrue);
  });

  testWidgets(
    'B15GF a later binding requires its own paint without widget rebuild',
    (tester) async {
      var owner = Object();
      final original = owner;
      final later = Object();
      final marks = <Object>[];
      const content = ValueKey('frame-owned-content');
      GroupEngagementFrameObservation snapshot() {
        final captured = owner;
        return (binding: captured, onVisible: () => marks.add(captured));
      }

      await tester
          .pumpWidget(
            _page(
              GroupEngagementVisibilityProbe(
                key: _item,
                eligible: true,
                onVisible: () {},
                frameObservation: snapshot,
                child: const SizedBox(key: content, width: 80, height: 80),
              ),
            ),
          )
          .timeout(const Duration(seconds: 3));
      await _frames(tester).timeout(const Duration(seconds: 3));
      expect(marks, hasLength(1));
    expect(identical(marks.single, original), isTrue);
      owner = later;
      tester.renderObject<RenderBox>(find.byKey(content)).markNeedsPaint();
      await tester
          .pump(const Duration(milliseconds: 16))
          .timeout(const Duration(seconds: 3));
      expect(marks, [original]);
      await _frames(tester).timeout(const Duration(seconds: 3));
      expect(marks, [original, later]);
      await _frames(tester).timeout(const Duration(seconds: 3));
      expect(marks, [original, later]);
    },
  );

  testWidgets('reports after a completed painted frame, once per binding', (
    tester,
  ) async {
    final events = <String>[];
    void visible() => events.add('visible');
    await tester.pumpWidget(
      _page(
        GroupEngagementVisibilityProbe(
          key: _item,
          eligible: true,
          onVisible: visible,
          child: CustomPaint(
            painter: _PaintRecorder(events),
            size: const Size(80, 80),
          ),
        ),
      ),
    );
    expect(events, contains('paint'));
    expect(events, isNot(contains('visible')));
    await _frames(tester);
    expect(events.where((event) => event == 'visible'), hasLength(1));
    expect(events.indexOf('paint'), lessThan(events.indexOf('visible')));
    await _frames(tester);
    expect(events.where((event) => event == 'visible'), hasLength(1));
    await tester.pumpWidget(
      _page(
        GroupEngagementVisibilityProbe(
          key: _item,
          eligible: true,
          onVisible: visible,
          child: CustomPaint(
            painter: _PaintRecorder(events),
            size: const Size(80, 80),
          ),
        ),
      ),
    );
    await _frames(tester);
    expect(events.where((event) => event == 'visible'), hasLength(1));
  });

  testWidgets(
    'disabled or locked placeholder is excluded until eligible paint',
    (tester) async {
      var count = 0;
      void visible() => count++;
      await tester.pumpWidget(_page(_probe(visible, eligible: false)));
      await _frames(tester);
      expect(count, 0);
      await tester.pumpWidget(_page(_probe(visible)));
      await _frames(tester);
      expect(count, 1);
    },
  );

  testWidgets('built cached item requires entering the painted viewport', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var count = 0;
    await tester.pumpWidget(
      _page(
        SizedBox(
          width: 200,
          height: 200,
          child: ListView(
            controller: scroll,
            scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
            children: [
              const SizedBox(height: 900),
              _probe(() => count++),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
    );
    final cachedItem = find.byKey(_item, skipOffstage: false);
    expect(cachedItem, findsOneWidget);
    expect(tester.getTopLeft(cachedItem).dy, greaterThan(200));
    await _frames(tester);
    expect(count, 0);
    scroll.jumpTo(850);
    await _frames(tester);
    expect(tester.getTopLeft(find.byKey(_item)).dy, lessThan(200));
    expect(count, 1);
  });

  testWidgets(
    'ancestor clip rejects outside paint and admits partial overlap',
    (tester) async {
      var count = 0;
      void visible() => count++;
      Widget clipped(double offset) => _page(
        SizedBox(
          width: 100,
          height: 100,
          child: ClipRect(
            child: Transform.translate(
              offset: Offset(0, offset),
              child: _probe(visible),
            ),
          ),
        ),
      );
      await tester.pumpWidget(clipped(150));
      await _frames(tester);
      expect(count, 0);
      await tester.pumpWidget(clipped(50));
      await _frames(tester);
      expect(count, 1);
    },
  );

  for (final hidden in ['offstage', 'transparent', 'zero area']) {
    testWidgets('$hidden cannot qualify before visible restoration', (
      tester,
    ) async {
      var count = 0;
      void visible() => count++;
      Widget wrapped(bool hide) {
        final child = _probe(visible);
        return switch (hidden) {
          'offstage' => Offstage(offstage: hide, child: child),
          'transparent' => Opacity(opacity: hide ? 0 : 1, child: child),
          _ => SizedBox(
            width: hide ? 0 : 80,
            height: hide ? 0 : 80,
            child: child,
          ),
        };
      }

      await tester.pumpWidget(_page(wrapped(true)));
      await _frames(tester);
      expect(count, 0);
      await tester.pumpWidget(_page(wrapped(false)));
      await _frames(tester);
      expect(count, 1);
    });
  }

  testWidgets(
    'background cancels pending observation; resume needs new frame',
    (tester) async {
      var count = 0;
      await tester.pumpWidget(_page(_probe(() => count++)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _frames(tester);
      expect(count, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _frames(tester);
      expect(count, 1);
    },
  );

  testWidgets('covered route is excluded even when its child remains painted', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final eligible = ValueNotifier(false);
    addTearDown(eligible.dispose);
    var count = 0;
    final paints = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: eligible,
            builder: (context, enabled, child) =>
                GroupEngagementVisibilityProbe(
                  key: _item,
                  eligible: enabled,
                  onVisible: () => count++,
                  child: CustomPaint(
                    painter: _PaintRecorder(paints),
                    size: const Size(80, 80),
                  ),
                ),
          ),
        ),
      ),
    );
    navigator.currentState!.push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const SizedBox.expand(),
      ),
    );
    await _frames(tester);
    paints.clear();
    eligible.value = true;
    await _frames(tester);
    expect(paints, contains('paint'));
    expect(count, 0);
    navigator.currentState!.pop();
    await _frames(tester);
    expect(count, 1);
  });

  testWidgets('replacement and disposal fence deferred callbacks', (
    tester,
  ) async {
    var old = 0;
    var replacement = 0;
    await tester.pumpWidget(_page(_probe(() => old++)));
    await tester.pumpWidget(
      _page(_probe(() => replacement++, key: const ValueKey('replacement'))),
    );
    await _frames(tester);
    expect(old, 0);
    expect(replacement, 1);
    await tester.pumpWidget(
      _page(_probe(() => old++, key: const ValueKey('disposed'))),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    expect(old, 0);
  });

  testWidgets('disabling before confirmation cancels the pending callback', (
    tester,
  ) async {
    var count = 0;
    void visible() => count++;
    await tester.pumpWidget(_page(_probe(visible)));
    await tester.pumpWidget(_page(_probe(visible, eligible: false)));
    await _frames(tester);
    expect(count, 0);
    await tester.pumpWidget(_page(_probe(visible)));
    await _frames(tester);
    expect(count, 1);
  });

  testWidgets('callback replacement cannot receive an earlier binding frame', (
    tester,
  ) async {
    var old = 0;
    var replacement = 0;
    await tester.pumpWidget(_page(_probe(() => old++)));
    await tester.pumpWidget(_page(_probe(() => replacement++)));
    expect(old, 0);
    expect(replacement, 0);
    await _frames(tester);
    expect(old, 0);
    expect(replacement, 1);
  });
}
