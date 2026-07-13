import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ordinary resolver call sites require only their own projection family',
    () {
      final source = File(
        'ios/NotificationService/NotificationPreviewResolver.swift',
      ).readAsStringSync();
      final directStart = source.indexOf('private func resolveOneToOne(');
      final directEnd = source.indexOf(
        'private func resolveReaction(',
        directStart,
      );
      final groupStart = source.indexOf('private func resolveGroup(');
      final groupEnd = source.indexOf(
        'private func prepareOrdinaryDisplay(',
        groupStart,
      );
      expect(directStart, greaterThanOrEqualTo(0));
      expect(directEnd, greaterThan(directStart));
      expect(groupStart, greaterThanOrEqualTo(0));
      expect(groupEnd, greaterThan(groupStart));

      final direct = source.substring(directStart, directEnd);
      final group = source.substring(groupStart, groupEnd);
      expect(direct, contains('OrdinaryNotificationProjectionSnapshot('));
      expect(direct, isNot(contains('requiresDirectContacts: false')));
      expect(group, contains('OrdinaryNotificationProjectionSnapshot('));
      expect(group, contains('requiresDirectContacts: false'));
    },
  );
}
