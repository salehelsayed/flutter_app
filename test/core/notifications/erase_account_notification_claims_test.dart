import 'dart:io';

import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/erase_account_notification_claims.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'erase removes production claims and accepts an already missing directory',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'erase-notification-claims-',
      );
      addTearDown(() => support.delete(recursive: true));
      final lease = await DurableNotificationToneLease.openDefault(
        supportDirectory: () async => support,
        useIosAppGroup: false,
      );
      expect(await lease.claimEvent('fixture-message-id'), isTrue);
      final kept = File('${support.path}/unrelated-setting');
      await kept.writeAsString('keep');

      await eraseAccountNotificationClaims(supportDirectory: support);
      expect(await lease.directory.exists(), isFalse);
      await eraseAccountNotificationClaims(supportDirectory: support);
      expect(await kept.readAsString(), 'keep');
    },
  );
}
