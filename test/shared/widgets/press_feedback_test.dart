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
}
