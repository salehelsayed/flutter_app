import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';

void main() {
  group('group backlog retention policy', () {
    test('uses a 7 day retention window', () {
      expect(groupBacklogRetentionWindowDays, 7);
      expect(groupBacklogRetentionWindow, const Duration(days: 7));
    });

    test('cutoff helper subtracts the retention window in UTC', () {
      final now = DateTime.utc(2026, 4, 5, 12);

      expect(groupBacklogRetentionCutoff(now), DateTime.utc(2026, 3, 29, 12));
    });
  });
}
