import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/utils/has_significant_time_gap.dart';

void main() {
  group('hasSignificantTimeGap', () {
    test('1 hour apart returns false', () {
      final a = DateTime(2026, 2, 9, 10, 0);
      final b = DateTime(2026, 2, 9, 11, 0);
      expect(hasSignificantTimeGap(a, b), isFalse);
    });

    test('3 hours apart returns true', () {
      final a = DateTime(2026, 2, 9, 10, 0);
      final b = DateTime(2026, 2, 9, 13, 0);
      expect(hasSignificantTimeGap(a, b), isTrue);
    });

    test('exactly 2 hours apart returns true', () {
      final a = DateTime(2026, 2, 9, 10, 0);
      final b = DateTime(2026, 2, 9, 12, 0);
      expect(hasSignificantTimeGap(a, b), isTrue);
    });

    test('AM to PM boundary returns true even if less than 2 hours', () {
      final a = DateTime(2026, 2, 9, 11, 30);
      final b = DateTime(2026, 2, 9, 12, 30);
      expect(hasSignificantTimeGap(a, b), isTrue);
    });

    test('same AM period within 2 hours returns false', () {
      final a = DateTime(2026, 2, 9, 9, 0);
      final b = DateTime(2026, 2, 9, 10, 30);
      expect(hasSignificantTimeGap(a, b), isFalse);
    });

    test('same PM period within 2 hours returns false', () {
      final a = DateTime(2026, 2, 9, 14, 0);
      final b = DateTime(2026, 2, 9, 15, 30);
      expect(hasSignificantTimeGap(a, b), isFalse);
    });
  });
}
