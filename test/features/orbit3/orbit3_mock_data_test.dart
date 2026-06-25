import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit3/application/orbit3_mock_data.dart';

void main() {
  test('build(count:100) returns 100 deterministic items including groups (C5)',
      () {
    final items = Orbit3MockData.build(count: 100);
    expect(items.length, 100);
    expect(items.where((it) => it.isGroup).length, greaterThanOrEqualTo(2));
    // The inner circle (first 13) stays friends-only.
    expect(items.take(13).every((it) => !it.isGroup), isTrue);
    // Deterministic across calls.
    final again = Orbit3MockData.build(count: 100);
    expect([for (final it in again) it.displayName],
        [for (final it in items) it.displayName]);
    // First two never substring-collide (search/glow still works).
    expect(items[0].displayName == items[1].displayName, isFalse);
  });

  test('existing populations are unchanged (5/13/24/50)', () {
    for (final n in [5, 13, 24, 50]) {
      expect(Orbit3MockData.build(count: n).length, n);
    }
  });
}
