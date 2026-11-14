import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

// Owner request 2026-11-10: the unread orbit is a tilted ellipse whose back
// half paints behind the avatar and whose front half paints in front of it,
// and an unopened thought adds an orbiting star. These tests read the real
// paint order of the indicator: 'avatar' is the host child, 'dot' an unread
// dot core, 'star' the thought star fill.
void main() {
  const avatarInk = Color(0xFF123456);
  const darkStarFill = Color(0xFFFFF4CC);
  const friendColour = Color(0xFF3366FF);

  Widget wrap(
    Widget child, {
    bool reduceMotion = false,
    BackgroundReadableColors colors = BackgroundReadableColors.dark,
  }) => MaterialApp(
    theme: ThemeData(extensions: [colors]),
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: Center(child: child),
        ),
      ),
    ),
  );

  Widget indicator({int unread = 0, Color? star}) => UnreadOrbitIndicator(
    unreadCount: unread,
    diameter: 48,
    thoughtStarColor: star,
    child: const SizedBox.square(
      dimension: 48,
      child: ColoredBox(color: avatarInk),
    ),
  );

  List<String> paintOrder(
    WidgetTester tester, {
    Color starFill = darkStarFill,
  }) {
    final order = <String>[];
    expect(
      find.byType(UnreadOrbitIndicator),
      paints..everything((method, args) {
        if (method == #drawRect &&
            (args[1] as Paint).color.toARGB32() == avatarInk.toARGB32()) {
          order.add('avatar');
        }
        if (method == #drawCircle &&
            (args[2] as Paint).color.toARGB32() ==
                UnreadOrbitIndicator.kUnreadAccent.toARGB32()) {
          order.add('dot');
        }
        if (method == #drawPath) {
          final paint = args[1] as Paint;
          if (paint.style == PaintingStyle.fill &&
              paint.maskFilter == null &&
              paint.color.toARGB32() == starFill.toARGB32()) {
            order.add('star');
          }
        }
        return true;
      }),
    );
    return order;
  }

  testWidgets(
    'count 0 without a thought renders only the avatar and no ticker',
    (tester) async {
      await tester.pumpWidget(wrap(indicator()));
      expect(paintOrder(tester), ['avatar']);
      expect(
        find.descendant(
          of: find.byType(UnreadOrbitIndicator),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('counts 1, 2 and 5 show 1, 2 and 3 dots around the avatar', (
    tester,
  ) async {
    final seen = <int, List<String>>{};
    for (final count in const [1, 2, 5]) {
      await tester.pumpWidget(
        wrap(indicator(unread: count), reduceMotion: true),
      );
      seen[count] = paintOrder(tester);
    }
    expect(seen, {
      1: ['avatar', 'dot'],
      2: ['dot', 'avatar', 'dot'],
      5: ['dot', 'dot', 'avatar', 'dot'],
    });
  });

  testWidgets('reduce motion keeps the dots visible and still', (tester) async {
    await tester.pumpWidget(wrap(indicator(unread: 2), reduceMotion: true));
    final before = paintOrder(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(before, ['dot', 'avatar', 'dot']);
    expect(paintOrder(tester), before);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'a dot paints above the avatar on the front half and below it half a turn later',
    (tester) async {
      await tester.pumpWidget(wrap(indicator(unread: 1)));
      expect(paintOrder(tester), ['avatar', 'dot']);
      await tester.pump(const Duration(seconds: 3));
      expect(paintOrder(tester), ['dot', 'avatar']);
      await tester.pump(const Duration(seconds: 3));
      expect(paintOrder(tester), ['avatar', 'dot']);
    },
  );

  testWidgets('an unopened thought alone orbits a star and no dots', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(indicator(star: friendColour), reduceMotion: true),
    );
    expect(paintOrder(tester), ['avatar', 'star']);
  });

  testWidgets('the star and the unread dots orbit together', (tester) async {
    await tester.pumpWidget(
      wrap(indicator(unread: 1, star: friendColour), reduceMotion: true),
    );
    expect(paintOrder(tester), ['avatar', 'dot', 'star']);
  });

  testWidgets('on a light background the star takes the friend colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        indicator(star: friendColour),
        reduceMotion: true,
        colors: BackgroundReadableColors.representativeLight,
      ),
    );
    expect(paintOrder(tester, starFill: friendColour), ['avatar', 'star']);
  });

  testWidgets('taps on the avatar reach it through the orbit and the star', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        GestureDetector(
          onTap: () => taps++,
          child: indicator(unread: 3, star: friendColour),
        ),
        reduceMotion: true,
      ),
    );
    await tester.tapAt(tester.getCenter(find.byType(UnreadOrbitIndicator)));
    expect(taps, 1);
    final star = tester.renderObject(
      find.byKey(const ValueKey('orbit-thought-star')),
    );
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      tester.getCenter(find.byKey(const ValueKey('orbit-thought-star'))),
      tester.view.viewId,
    );
    expect(result.path.where((entry) => entry.target == star), isEmpty);
  });
}
