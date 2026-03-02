import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';

void main() {
  final testGroups = [
    GroupModel(
      id: 'group-1',
      name: 'Alpha Group',
      type: GroupType.chat,
      topicName: 'topic-1',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-1',
      myRole: GroupRole.admin,
    ),
    GroupModel(
      id: 'group-2',
      name: 'Beta Announcements',
      type: GroupType.announcement,
      topicName: 'topic-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-1',
      myRole: GroupRole.member,
    ),
  ];

  Widget buildTestWidget({
    List<GroupModel> groups = const [],
  }) {
    return MaterialApp(
      home: GroupListScreen(
        groups: groups,
        onGroupTap: (_) {},
        onCreateGroup: () {},
        onBack: () {},
      ),
    );
  }

  testWidgets('renders groups', (tester) async {
    await tester.pumpWidget(buildTestWidget(groups: testGroups));

    expect(find.text('Alpha Group'), findsOneWidget);
    expect(find.text('Beta Announcements'), findsOneWidget);
  });

  testWidgets('shows empty state when no groups', (tester) async {
    await tester.pumpWidget(buildTestWidget(groups: []));

    expect(find.text('No groups yet'), findsOneWidget);
  });

  testWidgets('shows type badges', (tester) async {
    await tester.pumpWidget(buildTestWidget(groups: testGroups));

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Announce'), findsOneWidget);
  });
}
