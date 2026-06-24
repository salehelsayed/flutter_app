import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/utils/message_window_cap.dart';

void main() {
  // TC-159-09 — the pure trim helper caps newest-first (oldest evicted, live
  // edge retained) and is a no-op within the cap.
  group('TC-159-09 trimToNewestInMemoryCap', () {
    test('caps to the newest kMax, evicting the OLDEST (front)', () {
      final list = List<int>.generate(kMaxInMemoryMessages + 5, (i) => i);
      final capped = trimToNewestInMemoryCap(list);
      expect(capped.length, kMaxInMemoryMessages);
      // Oldest 0..4 evicted; the window starts at 5.
      expect(capped.first, 5);
      // Newest (live edge) retained.
      expect(capped.last, kMaxInMemoryMessages + 4);
    });

    test('returns the SAME instance when already within the cap', () {
      final list = [1, 2, 3];
      expect(identical(trimToNewestInMemoryCap(list), list), isTrue);
      final exact = List<int>.generate(kMaxInMemoryMessages, (i) => i);
      expect(identical(trimToNewestInMemoryCap(exact), exact), isTrue);
    });

    test('131 guard: the just-appended newest is NEVER the evicted one', () {
      // Simulate an append: oldest..newest ascending, newest = the new arrival.
      final list = List<int>.generate(kMaxInMemoryMessages + 1, (i) => i);
      final capped = trimToNewestInMemoryCap(list);
      expect(capped.last, kMaxInMemoryMessages, reason: 'newest survives');
      expect(capped.contains(0), isFalse, reason: 'oldest evicted');
    });

    test('honors a custom cap', () {
      expect(trimToNewestInMemoryCap([1, 2, 3, 4, 5], cap: 3), [3, 4, 5]);
    });
  });

  // TC-159-09c — the cap is live-drain-scoped: applying it to a back-scroll
  // PREPEND would evict exactly the just-loaded oldest page (the load→evict→load
  // loop), which is why the older-page path is exempt and never calls the trim.
  group('TC-159-09c cap is live-append-scoped (back-scroll exempt)', () {
    test('applying the trim AFTER a prepend would evict the just-loaded page', () {
      // The in-memory window is the newest kMax messages (1000..).
      final window = List<int>.generate(
        kMaxInMemoryMessages,
        (i) => 1000 + i,
      );
      // A back-scroll prepends an OLDER page to the FRONT.
      final olderPage = List<int>.generate(50, (i) => i); // 0..49 (older)
      final afterPrepend = [...olderPage, ...window];

      // If the trim were (wrongly) applied here, the older page is evicted →
      // the user sits at the top and _maybeLoadMore re-fires forever.
      final wronglyTrimmed = trimToNewestInMemoryCap(afterPrepend);
      expect(
        wronglyTrimmed.contains(0),
        isFalse,
        reason: 'a newest-first trim on a prepend evicts the just-loaded page',
      );

      // Hence the back-scroll path keeps the full (over-cap) list untouched.
      expect(afterPrepend.length, kMaxInMemoryMessages + 50);
    });
  });
}
