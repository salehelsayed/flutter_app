import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime.utc(2026, 11, 1, 8);

  test('a Thought that ran its full lifetime was not replaced', () {
    expect(
      ThoughtLifetime.isReplaced(
        created,
        created.add(ThoughtLifetime.duration),
      ),
      isFalse,
    );
  });

  test('a Thought that ended early was replaced', () {
    expect(
      ThoughtLifetime.isReplaced(
        created,
        created.add(const Duration(hours: 2)),
      ),
      isTrue,
    );
    expect(
      ThoughtLifetime.isReplaced(
        created,
        created.add(ThoughtLifetime.duration - const Duration(seconds: 1)),
      ),
      isTrue,
    );
  });

  test('time zones do not change the answer', () {
    expect(
      ThoughtLifetime.isReplaced(
        created.toLocal(),
        created.add(ThoughtLifetime.duration),
      ),
      isFalse,
    );
  });
}
