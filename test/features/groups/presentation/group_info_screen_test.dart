import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/group_security_status_view_state.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

import '../../../shared/helpers/readability_test_helpers.dart';

void main() {
  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'topic-1',
    description: 'A test group for testing',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  final testMembers = [
    GroupMember(
      groupId: 'group-1',
      peerId: 'peer-admin',
      username: 'Admin User',
      role: MemberRole.admin,
      joinedAt: DateTime.now().toUtc(),
    ),
    GroupMember(
      groupId: 'group-1',
      peerId: 'peer-member',
      username: 'Regular Member',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ),
  ];

  Widget buildTestWidget({
    List<GroupMember> members = const [],
    Map<String, GroupInviteDeliveryStatus> inviteStatusesByPeerId = const {},
    Map<String, GroupInviteDeliveryAttempt> inviteAttemptsByPeerId = const {},
    Set<String> resendingInvitePeerIds = const {},
    Map<String, GroupMemberIdentitySafety> memberSafetyByPeerId = const {},
    bool isAdmin = true,
    String? ownPeerId,
    bool isMuted = false,
    GroupModel? group,
    ValueChanged<bool>? onMuteChanged,
    VoidCallback? onEditDetails,
    VoidCallback? onDissolve,
    VoidCallback? onDeleteLocally,
    ValueChanged<GroupMember>? onToggleAdminRole,
    ValueChanged<GroupMember>? onRemoveMember,
    ValueChanged<GroupMember>? onResendInvite,
    VoidCallback? onAddMember,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
    GroupSecurityStatusViewState? securityStatus,
  }) {
    return MaterialApp(
      home: GroupInfoScreen(
        group: group ?? testGroup,
        members: members,
        inviteStatusesByPeerId: inviteStatusesByPeerId,
        inviteAttemptsByPeerId: inviteAttemptsByPeerId,
        resendingInvitePeerIds: resendingInvitePeerIds,
        memberSafetyByPeerId: memberSafetyByPeerId,
        isAdmin: isAdmin,
        ownPeerId: ownPeerId,
        isMuted: isMuted,
        onBack: () {},
        onLeave: () {},
        onMuteChanged: onMuteChanged,
        onEditDetails: onEditDetails,
        onDissolve: onDissolve,
        onDeleteLocally: onDeleteLocally,
        onRemoveMember: onRemoveMember,
        onToggleAdminRole: onToggleAdminRole,
        onAddMember: onAddMember,
        onResendInvite: onResendInvite,
        backgroundPreference: backgroundPreference,
        securityStatus: securityStatus,
      ),
    );
  }

  testWidgets('shows members', (tester) async {
    await tester.pumpWidget(buildTestWidget(members: testMembers));

    expect(find.text('Admin User'), findsOneWidget);
    expect(find.text('Regular Member'), findsOneWidget);
  });

  testWidgets('uses UserAvatar for each member row', (tester) async {
    await tester.pumpWidget(buildTestWidget(members: testMembers));

    expect(find.byType(UserAvatar), findsNWidgets(2));
  });

  testWidgets('keeps fallback identity readable when no avatar photo exists', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(members: testMembers));

    expect(find.text('Admin User'), findsOneWidget);
    expect(find.text('Regular Member'), findsOneWidget);
    expect(find.byType(RingAvatar), findsNWidgets(2));
  });

  testWidgets('shows roles', (tester) async {
    await tester.pumpWidget(buildTestWidget(members: testMembers));

    expect(find.text('admin'), findsOneWidget);
    expect(find.text('writer'), findsOneWidget);
  });

  testWidgets('shows invite status copy and resend only for needs resend', (
    tester,
  ) async {
    GroupMember? resentMember;
    final queuedMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-queued',
      username: 'Queued Member',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );
    final resendMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-resend',
      username: 'Resend Member',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );
    final cannotMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-cannot',
      username: 'Cannot Member',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );
    final attemptedAt = DateTime.utc(2026, 5, 9, 12);

    await tester.pumpWidget(
      buildTestWidget(
        members: [testMembers.first, queuedMember, resendMember, cannotMember],
        ownPeerId: 'peer-admin',
        inviteStatusesByPeerId: const {
          'peer-queued': GroupInviteDeliveryStatus.queued,
          'peer-resend': GroupInviteDeliveryStatus.needsResend,
          'peer-cannot': GroupInviteDeliveryStatus.cannotSend,
        },
        inviteAttemptsByPeerId: {
          'peer-cannot': GroupInviteDeliveryAttempt(
            groupId: 'group-1',
            peerId: 'peer-cannot',
            username: 'Cannot Member',
            status: GroupInviteDeliveryStatus.cannotSend,
            attemptedAt: attemptedAt,
            updatedAt: attemptedAt,
            lastError: 'missing_secure_key',
          ),
        },
        onResendInvite: (member) => resentMember = member,
      ),
    );

    expect(find.text('In their inbox'), findsOneWidget);
    expect(find.text('Resend needed'), findsOneWidget);
    expect(find.text('Cannot send'), findsOneWidget);
    expect(
      find.text(
        "We don't have the secure info needed to invite this friend. Ask them to open or reinstall the app, then try again.",
      ),
      findsOneWidget,
    );
    expect(find.text('Resend'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-member-resend-invite-peer-queued')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('group-member-resend-invite-peer-cannot')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('group-member-resend-invite-peer-resend')),
      findsOneWidget,
    );

    final resendButton = find.byKey(
      const ValueKey('group-member-resend-invite-peer-resend'),
    );
    await tester.ensureVisible(resendButton);
    await tester.pump();
    await tester.tap(resendButton, warnIfMissed: false);
    expect(resentMember?.peerId, 'peer-resend');
  });

  testWidgets('shows disabled invite resend busy state', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        ownPeerId: 'peer-admin',
        inviteStatusesByPeerId: const {
          'peer-member': GroupInviteDeliveryStatus.needsResend,
        },
        resendingInvitePeerIds: const {'peer-member'},
        onResendInvite: (_) {},
      ),
    );

    expect(find.text('Sending...'), findsOneWidget);
    final resendButton = tester.widget<TextButton>(
      find.byKey(const ValueKey('group-member-resend-invite-peer-member')),
    );
    expect(resendButton.onPressed, isNull);
  });
  testWidgets('shows identity warning and safety numbers for changed member', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        memberSafetyByPeerId: const {
          'peer-member': GroupMemberIdentitySafety(
            currentSafetyNumber: '1111 2222 3333',
            savedSafetyNumber: '4444 5555 6666',
            identityChanged: true,
          ),
        },
      ),
    );

    expect(
      find.byKey(const ValueKey('group-member-identity-warning-peer-member')),
      findsOneWidget,
    );
    expect(find.text('Identity changed'), findsOneWidget);
    expect(find.text('Current safety 1111 2222 3333'), findsOneWidget);
    expect(find.text('Saved safety 4444 5555 6666'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-member-identity-warning-peer-admin')),
      findsNothing,
    );
  });

  testWidgets('shows security status for encryption, key change, and review', (
    tester,
  ) async {
    const securityStatus = GroupSecurityStatusViewState(
      hasCurrentKey: true,
      keyEpoch: 2,
      memberCount: 2,
      verifiedMemberCount: 1,
      identityWarningCount: 1,
      unverifiedMemberCount: 0,
    );

    await tester.pumpWidget(
      buildTestWidget(members: testMembers, securityStatus: securityStatus),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-security-status-card')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.byKey(const ValueKey('group-security-status-card')),
      findsOneWidget,
    );
    expect(find.text('End-to-end encrypted'), findsOneWidget);
    expect(find.text('Key change visible'), findsOneWidget);
    expect(find.text('Group key changed to epoch 2'), findsNWidgets(2));
    expect(find.text('1 of 2 members verified'), findsOneWidget);
    expect(find.text('1 member needs verification review'), findsOneWidget);
    expect(find.text('Verification warning'), findsOneWidget);
  });

  testWidgets('shows leave button', (tester) async {
    await tester.pumpWidget(buildTestWidget(members: testMembers));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-leave-button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('Leave Group'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-leave-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-delete-local-button')),
      findsNothing,
    );
  });

  testWidgets('shows dissolve button for active admins', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(members: testMembers, isAdmin: true, onDissolve: () {}),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-dissolve-button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('Dissolve Group'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-dissolve-button')), findsOneWidget);
  });

  testWidgets('shows mute switch state', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(members: testMembers, isMuted: true),
    );

    final muteSwitch = tester.widget<Switch>(
      find.byKey(const ValueKey('group-mute-switch')),
    );
    expect(muteSwitch.value, isTrue);
    expect(
      find.text('New messages still arrive, but this group stays quiet.'),
      findsOneWidget,
    );
  });

  testWidgets('calls onMuteChanged when mute switch is toggled', (
    tester,
  ) async {
    bool? mutedValue;

    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        onMuteChanged: (value) => mutedValue = value,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('group-mute-switch')));
    await tester.pump();

    expect(mutedValue, isTrue);
  });

  // --- Phase 3: Add Member button tests ---

  testWidgets('shows Add Member button when isAdmin', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(members: testMembers, isAdmin: true, onAddMember: () {}),
    );

    expect(find.text('Add Member'), findsOneWidget);
  });

  testWidgets('hides Add Member button when not admin', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(members: testMembers, isAdmin: false),
    );

    expect(find.text('Add Member'), findsNothing);
  });

  testWidgets('calls onAddMember callback when tapped', (tester) async {
    var addMemberCalled = false;

    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        isAdmin: true,
        onAddMember: () => addMemberCalled = true,
      ),
    );

    await tester.tap(find.text('Add Member'));
    expect(addMemberCalled, isTrue);
  });

  testWidgets('shows role-management controls only for eligible admin rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        isAdmin: true,
        ownPeerId: 'peer-admin',
        onRemoveMember: (_) {},
        onToggleAdminRole: (_) {},
      ),
    );

    expect(
      find.byKey(const ValueKey('group-member-actions-peer-member')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('group-member-remove-peer-member')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('group-member-actions-peer-admin')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('group-member-remove-peer-admin')),
      findsNothing,
    );
  });

  testWidgets('shows Edit Details button when admin can edit metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        isAdmin: true,
        onEditDetails: () {},
      ),
    );

    expect(
      find.byKey(const ValueKey('group-edit-details-button')),
      findsOneWidget,
    );
  });

  testWidgets('hides Edit Details button when viewer is not admin', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        isAdmin: false,
        onEditDetails: () {},
      ),
    );

    expect(
      find.byKey(const ValueKey('group-edit-details-button')),
      findsNothing,
    );
  });

  testWidgets('dissolved groups show local cleanup and hide management controls', (
    tester,
  ) async {
    final dissolvedGroup = testGroup.copyWith(
      isDissolved: true,
      dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
      dissolvedBy: 'peer-admin',
    );

    await tester.pumpWidget(
      buildTestWidget(
        group: dissolvedGroup,
        members: testMembers,
        isAdmin: true,
        ownPeerId: 'peer-admin',
        onEditDetails: () {},
        onDissolve: () {},
        onDeleteLocally: () {},
        onAddMember: () {},
        onRemoveMember: (_) {},
        onToggleAdminRole: (_) {},
      ),
    );

    expect(find.text('Group dissolved'), findsOneWidget);
    expect(find.text('Dissolved'), findsOneWidget);
    expect(
      find.text(
        'This conversation is now read-only. Previous messages stay available for reference.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-delete-local-button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Delete from this device'), findsOneWidget);
    expect(
      find.text(
        'Keep this dissolved history as long as you want, or remove it from this device only. This will not affect anyone else.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('group-delete-local-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('group-edit-details-button')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('group-dissolve-button')), findsNothing);
    expect(find.byKey(const ValueKey('group-leave-button')), findsNothing);
    expect(find.text('Add Member'), findsNothing);
    expect(
      find.byKey(const ValueKey('group-member-actions-peer-member')),
      findsNothing,
    );
  });

  testWidgets('daylight lagoon keeps group info content readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        isMuted: true,
        onAddMember: () {},
        backgroundPreference: BackgroundPreference.daylightLagoon,
      ),
    );

    const colors = BackgroundReadableColors.representativeLight;
    final groupName = tester.widget<Text>(find.text('Test Group'));
    expectTextContrast(groupName.style!.color!, colors.surfaceBase);

    final description = tester.widget<Text>(
      find.text('A test group for testing'),
    );
    expectTextContrast(description.style!.color!, colors.surfaceBase);

    final muteTitle = tester.widget<Text>(find.text('Mute Notifications'));
    expectTextContrast(muteTitle.style!.color!, colors.surfaceRaised);

    final memberName = tester.widget<Text>(find.text('Regular Member'));
    expectTextContrast(memberName.style!.color!, colors.surfaceBase);
  });
}
