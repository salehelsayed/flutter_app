import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/press_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only the inner control animates on a nested tap', (
    tester,
  ) async {
    const deadline = Duration(seconds: 3);
    const outer = ValueKey('outer');
    const inner = ValueKey('inner');
    var outerTaps = 0;
    var innerTaps = 0;

    await tester
        .pumpWidget(
          MaterialApp(
            home: Center(
              child: GestureDetector(
                onTap: () => outerTaps++,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  key: outer,
                  width: 96,
                  height: 96,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => innerTaps++,
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox(key: inner, width: 48, height: 48),
                    ).withPressFeedback(),
                  ),
                ),
              ).withPressFeedback(),
            ),
          ),
        )
        .timeout(deadline);

    final outerControl = find.byKey(outer);
    final innerControl = find.byKey(inner);
    final gesture = await tester
        .startGesture(tester.getCenter(innerControl))
        .timeout(deadline);
    await tester.pump().timeout(deadline);
    await tester.pump(const Duration(milliseconds: 120)).timeout(deadline);
    expect(tester.getRect(outerControl).width, 96);
    expect(tester.getRect(innerControl).width, closeTo(48 * 0.97, 0.001));
    await gesture.up().timeout(deadline);
    expect(outerTaps, 0);
    expect(innerTaps, 1);
    await tester.pump().timeout(deadline);
    await tester.pump(const Duration(milliseconds: 120)).timeout(deadline);
  });

  testWidgets('disposing a pressed row ignores the old pointer release', (
    tester,
  ) async {
    const deadline = Duration(seconds: 3);
    const hitBox = ValueKey('picker-row-hit-box');
    const first = ValueKey('first-contact');
    const replacement = ValueKey('replacement-contact');
    final taps = <Key>[];

    Widget scene(Key contact) => MaterialApp(
      home: Center(
        child: GestureDetector(
          key: contact,
          behavior: HitTestBehavior.opaque,
          onTap: () => taps.add(contact),
          child: const SizedBox(key: hitBox, width: 48, height: 48),
        ).withPressFeedback(),
      ),
    );

    await tester.pumpWidget(scene(first)).timeout(deadline);
    final target = find.byKey(hitBox);
    final gesture = await tester
        .startGesture(tester.getCenter(target))
        .timeout(deadline);
    await tester.pump().timeout(deadline);
    await tester.pump(const Duration(milliseconds: 120)).timeout(deadline);
    expect(tester.getRect(target).width, closeTo(48 * 0.97, 0.001));

    await tester.pumpWidget(scene(replacement)).timeout(deadline);
    await gesture.up().timeout(deadline);
    expect(tester.takeException(), isNull);
    expect(taps, isEmpty);
    expect(tester.getRect(target).width, 48);

    await tester.tap(target).timeout(deadline);
    expect(taps, [replacement]);
    await tester.pump().timeout(deadline);
  });
}
