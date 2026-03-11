import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_card.dart';

void main() {
  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  Widget buildTestWidget({
    GroupModel? group,
    int unreadCount = 0,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: GroupCard(
          group: group ?? testGroup,
          unreadCount: unreadCount,
        ),
      ),
    );
  }

  testWidgets('renders group name and type badge', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    expect(find.text('Test Group'), findsOneWidget);
    expect(find.text('Discussion'), findsOneWidget);
  });

  testWidgets('shows unread count when > 0', (tester) async {
    await tester.pumpWidget(buildTestWidget(unreadCount: 5));

    expect(find.text('5'), findsOneWidget);
  });
}
