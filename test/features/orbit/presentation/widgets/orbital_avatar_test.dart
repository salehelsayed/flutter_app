import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('OrbitalAvatar', () {
    testWidgets('classic avatar entrance scales from 0.9 and fades in 200 ms', (
      tester,
    ) async {
      const deadline = Duration(seconds: 3);
      await tester.pumpWidget(
        wrap(
          const OrbitalAvatar(
            peerId: 'peer-entrance',
            size: 38,
            globalIndex: 0,
            child: SizedBox(),
          ),
        ),
      ).timeout(deadline);
      // Elapse fake time to run the zero-delay timer and start the ticker.
      await tester.pump(const Duration(milliseconds: 1)).timeout(deadline);
      final avatar = find.byType(OrbitalAvatar);
      final scale = find.descendant(
        of: avatar,
        matching: find.byType(Transform),
      );
      final opacity = find.descendant(
        of: avatar,
        matching: find.byType(Opacity),
      );
      double currentScale() =>
          tester.widget<Transform>(scale).transform.entry(0, 0);
      double currentOpacity() => tester.widget<Opacity>(opacity).opacity;

      expect(currentScale(), closeTo(0.9, 0.001));
      expect(currentOpacity(), 0);
      await tester.pump(const Duration(milliseconds: 100)).timeout(deadline);
      final halfway = Curves.easeOut.transform(0.5);
      expect(currentScale(), closeTo(0.9 + 0.1 * halfway, 0.001));
      expect(currentOpacity(), closeTo(halfway, 0.001));
      await tester.pump(const Duration(milliseconds: 100)).timeout(deadline);
      expect(currentScale(), closeTo(1, 0.001));
      expect(currentOpacity(), 1);
    });

    testWidgets('classic avatar only accepts taps once visible', (
      tester,
    ) async {
      const deadline = Duration(seconds: 3);
      var taps = 0;
      await tester
          .pumpWidget(
            wrap(
              OrbitalAvatar(
                peerId: 'peer-stagger',
                size: 38,
                globalIndex: 0,
                entranceDelayMs: 100,
                onTap: () => taps++,
                child: const SizedBox(),
              ),
            ),
          )
          .timeout(deadline);

      final target = tester.getCenter(find.byType(GestureDetector));
      await tester.tapAt(target).timeout(deadline);
      final tapsWhileInvisible = taps;
      await tester.pump(const Duration(milliseconds: 100)).timeout(deadline);
      await tester.pump(const Duration(milliseconds: 50)).timeout(deadline);
      await tester.tapAt(target).timeout(deadline);
      await tester.pump(const Duration(milliseconds: 150)).timeout(deadline);

      expect(tapsWhileInvisible, 0);
      expect(taps, 1);
    });

    for (final reduceMotion in [false, true]) {
      testWidgets('custom avatar tap feedback, reduce motion $reduceMotion', (
        tester,
      ) async {
        const deadline = Duration(seconds: 3);
        const curve = Cubic(0.23, 1, 0.32, 1);
        const face = ValueKey('press-feedback-avatar-face');
        var taps = 0;
        await tester
            .pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduceMotion),
                  child: child!,
                ),
                home: Scaffold(
                  body: OrbitalAvatar(
                    peerId: 'peer-feedback',
                    size: 30,
                    globalIndex: 0,
                    animateEntrance: false,
                    onTap: () => taps++,
                    child: const SizedBox(key: face),
                  ),
                ),
              ),
            )
            .timeout(deadline);

        final avatar = find.byKey(face);
        final target = find.byType(GestureDetector);
        final originalWidth = tester.getRect(avatar).width;
        final outerEdge = tester.getCenter(target) + const Offset(23.8, 0);
        final gesture = await tester.startGesture(outerEdge).timeout(deadline);
        await tester.pump().timeout(deadline);
        await tester.pump(const Duration(milliseconds: 60)).timeout(deadline);
        expect(
          tester.getRect(avatar).width / originalWidth,
          closeTo(reduceMotion ? 1 : 1 - 0.03 * curve.transform(0.5), 0.001),
        );
        await tester.pump(const Duration(milliseconds: 60)).timeout(deadline);
        expect(
          tester.getRect(avatar).width / originalWidth,
          closeTo(reduceMotion ? 1 : 0.97, 0.001),
        );

        await gesture.up().timeout(deadline);
        expect(taps, 1);
        await tester.pump().timeout(deadline);
        await tester.pump(const Duration(milliseconds: 120)).timeout(deadline);
        expect(tester.getRect(avatar).width, closeTo(originalWidth, 0.001));

        final cancel = await tester
            .startGesture(tester.getCenter(target))
            .timeout(deadline);
        await tester.pump().timeout(deadline);
        await tester.pump(const Duration(milliseconds: 120)).timeout(deadline);
        await cancel.cancel().timeout(deadline);
        await tester.pump().timeout(deadline);
        await tester.pump(const Duration(milliseconds: 120)).timeout(deadline);
        expect(tester.getRect(avatar).width, closeTo(originalWidth, 0.001));
        expect(taps, 1);
      });
    }

    testWidgets('renders UserAvatar with given size', (tester) async {
      await tester.pumpWidget(
        wrap(const OrbitalAvatar(peerId: 'peer-123', size: 38, globalIndex: 0)),
      );
      // globalIndex 0 -> 0ms delay, pump past it + animation
      await tester.pumpAndSettle();
      expect(find.byType(UserAvatar), findsOneWidget);
    });

    testWidgets('renders ClipOval', (tester) async {
      await tester.pumpWidget(
        wrap(const OrbitalAvatar(peerId: 'peer-123', size: 38, globalIndex: 0)),
      );
      // Pump past the delayed timer to prevent pending timer errors.
      await tester.pumpAndSettle();
      expect(find.byType(ClipOval), findsWidgets);
    });

    testWidgets('renders circular border container', (tester) async {
      await tester.pumpWidget(
        wrap(const OrbitalAvatar(peerId: 'peer-123', size: 38, globalIndex: 0)),
      );
      await tester.pumpAndSettle();
      final containers = tester.widgetList<Container>(find.byType(Container));
      final bordered = containers.where((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.border != null;
      });
      expect(bordered, isNotEmpty);
    });

    testWidgets('applies custom borderWidth and borderColor', (tester) async {
      await tester.pumpWidget(
        wrap(
          const OrbitalAvatar(
            peerId: 'peer-123',
            size: 30,
            globalIndex: 0,
            borderWidth: 2.0,
            borderColor: Color(0xFF00FF00),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final containers = tester.widgetList<Container>(find.byType(Container));
      final bordered = containers.where((c) {
        final d = c.decoration;
        if (d is BoxDecoration && d.border is Border) {
          final border = d.border as Border;
          return border.top.width == 2.0 &&
              border.top.color == const Color(0xFF00FF00);
        }
        return false;
      });
      expect(bordered, isNotEmpty);
    });

    testWidgets('exposes actionable label and padded tap target', (
      tester,
    ) async {
      var taps = 0;

      await tester.pumpWidget(
        wrap(
          OrbitalAvatar(
            peerId: 'peer-123',
            size: 30,
            globalIndex: 0,
            semanticLabel: 'Open chat with Bob',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final actionFinder = find.bySemanticsLabel('Open chat with Bob');
      expect(actionFinder, findsOneWidget);
      final tapTarget = find.byType(GestureDetector);
      expect(tester.getSize(tapTarget), const Size(48, 48));

      final rect = tester.getRect(tapTarget);
      await tester.tapAt(rect.center + const Offset(22, 0));

      expect(taps, 1);
    });

    // 194 TC-194-36 — repaint containment: the rotating satellite field must not
    // rebuild the avatar's child subtree. Uses motionEnabled:false so the
    // entrance is instant and only the indicator rotation is live; bounded pumps
    // (the ~9s repeat never settles).
    testWidgets('satellite rotation does not rebuild the avatar child subtree', (
      tester,
    ) async {
      var buildCount = 0;
      await tester.pumpWidget(
        wrap(
          OrbitalAvatar(
            peerId: 'peer-123',
            size: 38,
            globalIndex: 0,
            motionEnabled: false,
            unreadCount: 2,
            child: _CountingBuildProbe(onBuild: () => buildCount++),
          ),
        ),
      );
      await tester.pump();
      final afterMount = buildCount;
      expect(afterMount, greaterThan(0));

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        buildCount,
        afterMount,
        reason: 'the rotating satellite field must not rebuild the avatar child',
      );
    });
  });
}

class _CountingBuildProbe extends StatelessWidget {
  const _CountingBuildProbe({required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox(width: 10, height: 10);
  }
}
