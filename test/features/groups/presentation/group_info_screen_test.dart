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
    VoidCallback? onAddMember,
  }) {
    return MaterialApp(
      home: GroupInfoScreen(
        group: testGroup,
        members: members,
        isAdmin: isAdmin,
        onBack: () {},
        onLeave: () {},
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
  });

  // --- Phase 3: Add Member button tests ---

  testWidgets('shows Add Member button when isAdmin', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        isAdmin: true,
        onAddMember: () {},
      ),
    );

    expect(find.text('Add Member'), findsOneWidget);
  });

  testWidgets('hides Add Member button when not admin', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        members: testMembers,
        isAdmin: false,
      ),
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
}
