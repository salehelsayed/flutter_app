import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';

void main() {
  group('formatMessageTime', () {
    test('formats morning timestamp correctly', () {
      // 9:05 AM UTC
      final result = formatMessageTime('2026-02-09T09:05:00.000Z');
      expect(result, isNotEmpty);
      // Should contain AM or PM depending on local timezone
      expect(result, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
    });

    test('formats afternoon timestamp correctly', () {
      // 3:30 PM UTC
      final result = formatMessageTime('2026-02-09T15:30:00.000Z');
      expect(result, isNotEmpty);
      expect(result, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
    });

    test('returns empty string for invalid input', () {
      expect(formatMessageTime('not-a-date'), '');
    });

    test('returns empty string for empty input', () {
      expect(formatMessageTime(''), '');
    });
  });
}
