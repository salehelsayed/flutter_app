import 'dart:ui';

import 'package:flutter_app/core/notifications/group_invite_android_notification_identity.dart';
import 'package:flutter_app/features/groups/application/group_invite_notification_presenter.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_app_visibility.dart';
import '../../../shared/fakes/fake_notification_service.dart';

void main() {
  late FakeNotificationService notificationService;

  setUp(() {
    notificationService = FakeNotificationService();
  });

  GroupInviteNotificationPresenter presenter({
    required FixedAppVisibility visibility,
  }) => GroupInviteNotificationPresenter(
    notificationService: notificationService,
    appVisibility: visibility,
    locale: const Locale('en'),
  );

  test(
    'background invite uses exact copy, route, and provider-compatible identity',
    () async {
      final visibility = FixedAppVisibility();
      final subject = presenter(visibility: visibility);
      final invite = _invite();

      expect(
        await subject.present(invite),
        GroupInviteNotificationPresentationResult.shown,
      );
      expect(
        await subject.present(invite),
        GroupInviteNotificationPresentationResult.shown,
      );

      expect(notificationService.shownGeneric, hasLength(2));
      for (final shown in notificationService.shownGeneric) {
        expect(shown.title, 'Book Club');
        expect(shown.body, 'Invited by Alice');
        expect(shown.payload, 'group_invite:group-1|message:invite-1');
        expect(shown.androidNotificationId, groupInviteAndroidNotificationId);
        expect(
          shown.androidNotificationTag,
          groupInviteAndroidNotificationTag(
            groupId: 'group-1',
            inviteId: 'invite-1',
          ),
        );
      }
      expect(visibility.evaluations, 2);
    },
  );

  test(
    'foreground suppression does not silence a later background invite',
    () async {
      final invite = _invite();

      expect(
        await presenter(
          visibility: FixedAppVisibility(isForegroundActive: true),
        ).present(invite),
        GroupInviteNotificationPresentationResult.foregroundSuppressed,
      );
      expect(notificationService.shownGeneric, isEmpty);

      expect(
        await presenter(visibility: FixedAppVisibility()).present(invite),
        GroupInviteNotificationPresentationResult.shown,
      );
      expect(notificationService.shownGeneric, hasLength(1));
    },
  );

  test('multi-use replay with the same invite id remains notifiable', () async {
    final firstReceivedAt = DateTime.utc(2026, 8, 21, 20);
    final subject = presenter(visibility: FixedAppVisibility());

    expect(
      await subject.present(_invite(receivedAt: firstReceivedAt)),
      GroupInviteNotificationPresentationResult.shown,
    );
    expect(
      await subject.present(
        _invite(receivedAt: firstReceivedAt.add(const Duration(minutes: 2))),
      ),
      GroupInviteNotificationPresentationResult.shown,
    );

    expect(notificationService.shownGeneric, hasLength(2));
    expect(
      notificationService.shownGeneric.first.androidNotificationTag,
      notificationService.shownGeneric.last.androidNotificationTag,
    );
  });
}

PendingGroupInvite _invite({DateTime? receivedAt}) {
  final received = receivedAt ?? DateTime.utc(2026, 8, 21, 20);
  return PendingGroupInvite(
    groupId: 'group-1',
    inviteId: 'invite-1',
    payloadJson: '{}',
    groupName: 'Book Club',
    groupType: GroupType.chat,
    senderPeerId: 'peer-alice',
    senderUsername: 'Alice',
    createdBy: 'peer-alice',
    createdAt: received,
    receivedAt: received,
    expiresAt: received.add(const Duration(days: 7)),
  );
}
