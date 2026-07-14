import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'APL-01 announcement rows reuse group lifecycle state and no third policy vocabulary',
    () {
      final row = <String, dynamic>{
        'id': 'announcement-private-row',
        'group_id': 'announcement-1',
        'sender_peer_id': 'admin-peer',
        'sender_username': 'Admin',
        'text': '',
        'timestamp': '2026-07-12T10:00:00.000Z',
        'key_generation': 3,
        'status': 'delivered',
        'is_incoming': 1,
        'is_forwarded': 0,
        'media_policy_version': 1,
        'media_lifecycle': 'disappearing',
        'media_duration_seconds': 86400,
        'media_protected': 1,
        'media_received_at': 1000,
        'media_expires_at': 86401000,
        'media_last_checked_at': 4000,
        'media_consumed_at': null,
        'media_expired_at': null,
        'media_cleanup_pending': 0,
        'created_at': '2026-07-12T10:00:00.000Z',
      };

      final message = GroupMessage.fromMap(row);
      expect(
        message.privateMediaPolicy,
        GroupPrivateMediaPolicy.disappearing(86400),
      );
      expect(message.mediaReceivedAt, 1000);
      expect(message.mediaExpiresAt, 86401000);
      expect(message.mediaLastCheckedAt, 4000);
      expect(message.toMap()['group_id'], 'announcement-1');
      expect(message.toMap()['media_lifecycle'], 'disappearing');
      expect(
        GroupMediaLifecycle.values.map((value) => value.name),
        containsAll(<String>['standard', 'viewOnce', 'disappearing']),
      );
    },
  );

  test(
    'APL-02 availability admits current announcement admins and no reader or writer role',
    () {
      const enabled = GroupPrivateMediaAvailability.enabledForTesting();
      const disabled = GroupPrivateMediaAvailability.disabled();

      expect(enabled.canAuthorPrivateMedia(GroupType.chat), isTrue);
      expect(enabled.canAuthorPrivateMedia(GroupType.announcement), isTrue);
      expect(enabled.canAuthorPrivateMedia(GroupType.qa), isFalse);
      expect(disabled.canAuthorPrivateMedia(GroupType.announcement), isFalse);

      expect(
        enabled.canCurrentMemberAuthorPrivateMedia(
          groupType: GroupType.announcement,
          localRole: GroupRole.admin,
          memberRole: MemberRole.admin,
        ),
        isTrue,
      );
      for (final roles in <(GroupRole, MemberRole)>[
        (GroupRole.member, MemberRole.admin),
        (GroupRole.admin, MemberRole.writer),
        (GroupRole.admin, MemberRole.reader),
        (GroupRole.member, MemberRole.reader),
      ]) {
        expect(
          enabled.canCurrentMemberAuthorPrivateMedia(
            groupType: GroupType.announcement,
            localRole: roles.$1,
            memberRole: roles.$2,
          ),
          isFalse,
          reason: '$roles',
        );
      }

      expect(
        enabled.canCurrentMemberAuthorPrivateMedia(
          groupType: GroupType.chat,
          localRole: GroupRole.member,
          memberRole: MemberRole.writer,
        ),
        isTrue,
      );
      expect(
        enabled.canCurrentMemberAuthorPrivateMedia(
          groupType: GroupType.chat,
          localRole: GroupRole.member,
          memberRole: MemberRole.reader,
        ),
        isFalse,
      );
    },
  );
}
