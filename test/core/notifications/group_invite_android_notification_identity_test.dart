import 'package:flutter_app/core/notifications/group_invite_android_notification_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches the relay SHA-256 native-tag contract', () {
    expect(
      groupInviteAndroidNotificationTag(
        groupId: 'group-1',
        inviteId: 'invite-1',
      ),
      'mknoon_group_invite_ed9a409a17e30f392210675cde7ed859',
    );
    expect(groupInviteAndroidNotificationId, 0);
  });

  test('normalizes whitespace and separates group plus invite identity', () {
    final baseline = groupInviteAndroidNotificationTag(
      groupId: 'group-1',
      inviteId: 'invite-1',
    );
    expect(
      groupInviteAndroidNotificationTag(
        groupId: ' group-1 ',
        inviteId: ' invite-1 ',
      ),
      baseline,
    );
    expect(
      groupInviteAndroidNotificationTag(
        groupId: 'group-1',
        inviteId: 'invite-2',
      ),
      isNot(baseline),
    );
    expect(
      groupInviteAndroidNotificationTag(
        groupId: 'group-2',
        inviteId: 'invite-1',
      ),
      isNot(baseline),
    );
    expect(baseline, isNot(contains('group-1')));
    expect(baseline, isNot(contains('invite-1')));
  });
}
