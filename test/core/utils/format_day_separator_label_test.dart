import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/format_day_separator_label.dart';

void main() {
  // All timestamps are constructed as LOCAL DateTimes so `.toLocal()` is a
  // no-op and the calendar-day math is independent of the test runner's
  // timezone.

  group('formatDaySeparatorLabel', () {
    test('returns the today label for a message on the same calendar day', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      final result = formatDaySeparatorLabel(
        DateTime(2026, 6, 14, 9, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, 'Today');
    });

    test('returns the today label even one minute into the day', () {
      final now = DateTime(2026, 6, 14, 23, 59);
      final result = formatDaySeparatorLabel(
        DateTime(2026, 6, 14, 0, 1),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, 'Today');
    });

    test('returns the yesterday label for the previous calendar day', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      final result = formatDaySeparatorLabel(
        DateTime(2026, 6, 13, 22, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, 'Yesterday');
    });

    test('returns yesterday across a month boundary', () {
      final now = DateTime(2026, 6, 1, 8, 0);
      final result = formatDaySeparatorLabel(
        DateTime(2026, 5, 31, 23, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, 'Yesterday');
    });

    test('returns yesterday across a year boundary', () {
      final now = DateTime(2026, 1, 1, 8, 0);
      final result = formatDaySeparatorLabel(
        DateTime(2025, 12, 31, 23, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, 'Yesterday');
    });

    test(
      'returns "Wed 13. May" for an older message in the current year',
      () {
        final now = DateTime(2026, 6, 14, 10, 30);
        final result = formatDaySeparatorLabel(
          DateTime(2026, 5, 13, 12, 0),
          now: now,
          todayLabel: 'Today',
          yesterdayLabel: 'Yesterday',
          locale: 'en',
        );
        expect(result, 'Wed 13. May');
      },
    );

    test('uses abbreviated weekday + day + abbreviated month (no year)', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      // 2026-03-27 is a Friday.
      final result = formatDaySeparatorLabel(
        DateTime(2026, 3, 27, 8, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, 'Fri 27. Mar');
    });

    test('does not zero-pad the day-of-month', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      // 2026-06-08 is a Monday; the day should render as "8", not "08".
      final result = formatDaySeparatorLabel(
        DateTime(2026, 6, 8, 8, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, 'Mon 8. Jun');
    });

    test('appends the year for a message from a previous year', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      // 2025-05-13 is a Tuesday.
      final result = formatDaySeparatorLabel(
        DateTime(2025, 5, 13, 12, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, 'Tue 13. May 2025');
    });

    test('appends the year for an older message across the year boundary', () {
      final now = DateTime(2026, 1, 1, 8, 0);
      // 2025-12-30 is a Tuesday (older than yesterday, previous year).
      final result = formatDaySeparatorLabel(
        DateTime(2025, 12, 30, 12, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, 'Tue 30. Dec 2025');
    });

    test('does NOT append the year for older messages in the current year', () {
      final now = DateTime(2026, 12, 31, 10, 0);
      final result = formatDaySeparatorLabel(
        DateTime(2026, 1, 5, 12, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: 'en',
      );
      expect(result, isNot(contains('2026')));
    });

    test('returns the injected (localized) today/yesterday strings verbatim', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      expect(
        formatDaySeparatorLabel(
          DateTime(2026, 6, 14, 1, 0),
          now: now,
          todayLabel: 'Heute',
          yesterdayLabel: 'Gestern',
          locale: 'en',
        ),
        'Heute',
      );
      expect(
        formatDaySeparatorLabel(
          DateTime(2026, 6, 13, 1, 0),
          now: now,
          todayLabel: 'Heute',
          yesterdayLabel: 'Gestern',
          locale: 'en',
        ),
        'Gestern',
      );
    });

    test('falls back gracefully when locale is null', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      final result = formatDaySeparatorLabel(
        DateTime(2026, 5, 13, 12, 0),
        now: now,
        todayLabel: 'Today',
        yesterdayLabel: 'Yesterday',
        locale: null,
      );
      // Shape: "Wed 13. May" (weekday day. month), independent of locale arg.
      expect(result, matches(RegExp(r'^[A-Za-z]{3} \d{1,2}\. [A-Za-z]{3}$')));
    });
  });
}
