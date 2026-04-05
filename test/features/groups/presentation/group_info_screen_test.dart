import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';

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
    bool isAdmin = true,
    String? ownPeerId,
    bool isMuted = false,
    GroupModel? group,
    ValueChanged<bool>? onMuteChanged,
    VoidCallback? onEditDetails,
    VoidCallback? onDissolve,
    ValueChanged<GroupMember>? onToggleAdminRole,
    ValueChanged<GroupMember>? onRemoveMember,
    VoidCallback? onAddMember,
  }) {
    return MaterialApp(
      home: GroupInfoScreen(
        group: group ?? testGroup,
        members: members,
        isAdmin: isAdmin,
        ownPeerId: ownPeerId,
        isMuted: isMuted,
        onBack: () {},
        onLeave: () {},
        onMuteChanged: onMuteChanged,
        onEditDetails: onEditDetails,
        onDissolve: onDissolve,
        onRemoveMember: onRemoveMember,
        onToggleAdminRole: onToggleAdminRole,
        onAddMember: onAddMember,
      ),
    );
  }

  testWidgets('shows members', (tester) async {
    await tester.pumpWidget(buildTestWidget(members: testMembers));

    expect(find.text('Admin User'), findsOneWidget);
    expect(find.text('Regular Member'), findsOneWidget);
  });

  testWidgets('shows roles', (tester) async {
    await tester.pumpWidget(buildTestWidget(members: testMembers));

    expect(find.text('admin'), findsOneWidget);
    expect(find.text('writer'), findsOneWidget);
  });

  testWidgets('shows leave button', (tester) async {
    await tester.pumpWidget(buildTestWidget(members: testMembers));

    expect(find.text('Leave Group'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-leave-button')), findsOneWidget);
  });

  testWidgets('shows dissolve button for active admins', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(members: testMembers, isAdmin: true, onDissolve: () {}),
    );

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

  testWidgets('dissolved groups show status and hide management controls', (
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
}
