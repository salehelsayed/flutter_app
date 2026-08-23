import 'package:flutter_app/core/debug/group_reaction_notification_ios_setup_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Plan 397 setup actions require both E2E mode and the exact profile',
    () {
      expect(
        allowsGroupReactionNotificationIosSetupActions(
          e2eTestMode: true,
          installedProfileId: groupReactionNotificationIosSetupBuildProfile,
        ),
        isTrue,
      );
      for (final tuple in const <(bool, String)>[
        (false, groupReactionNotificationIosSetupBuildProfile),
        (true, 'ios.device.production'),
        (true, 'ios.device.group_media_269'),
        (true, ''),
      ]) {
        expect(
          allowsGroupReactionNotificationIosSetupActions(
            e2eTestMode: tuple.$1,
            installedProfileId: tuple.$2,
          ),
          isFalse,
          reason: '$tuple',
        );
      }
    },
  );
}
