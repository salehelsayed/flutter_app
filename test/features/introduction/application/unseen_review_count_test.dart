import 'package:flutter_app/features/introduction/application/unseen_review_count.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeUnseenReviewKeys (TC-207-18)', () {
    test('empty seen set preserves raw pending review keys', () {
      final current = {'intro:peer-a', 'invite:group-a'};

      expect(
        computeUnseenReviewKeys(currentKeys: current, seenKeys: const {}),
        current,
      );
    });

    test('seen subset is removed from current keys', () {
      expect(
        computeUnseenReviewKeys(
          currentKeys: const {'intro:peer-a', 'invite:group-a'},
          seenKeys: const {'intro:peer-a'},
        ),
        {'invite:group-a'},
      );
    });

    test('new current key re-inflates after earlier dismissal', () {
      expect(
        computeUnseenReviewKeys(
          currentKeys: const {
            'intro:peer-a',
            'invite:group-a',
            'invite:group-b',
          },
          seenKeys: const {'intro:peer-a', 'invite:group-a'},
        ),
        {'invite:group-b'},
      );
    });

    test('stale seen keys are inert', () {
      expect(
        computeUnseenReviewKeys(
          currentKeys: const {'intro:peer-a'},
          seenKeys: const {'intro:peer-z', 'invite:group-z'},
        ),
        {'intro:peer-a'},
      );
    });
  });
}
